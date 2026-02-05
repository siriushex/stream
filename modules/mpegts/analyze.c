/*
 * Astra Module: MPEG-TS (Analyze)
 * http://cesbo.com/astra
 *
 * Copyright (C) 2012-2014, Andrey Dyldin <and@cesbo.com>
 *
 * This program is free software: you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation, either version 3 of the License, or
 * (at your option) any later version.
 *
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 * GNU General Public License for more details.
 *
 * You should have received a copy of the GNU General Public License
 * along with this program.  If not, see <http://www.gnu.org/licenses/>.
 */

/*
 * Module Name:
 *      analyze
 *
 * Module Options:
 *      upstream    - object, stream instance returned by module_instance:stream()
 *      name        - string, analyzer name
 *      rate_stat   - boolean, dump bitrate with 10ms interval
 *      join_pid    - boolean, request all SI tables on the upstream module
 *      callback    - function(data), events callback:
 *                    data.error    - string,
 *                    data.psi      - table, psi information (PAT, PMT, CAT, SDT)
 *                    data.analyze  - table, per pid information: errors, bitrate
 *                    data.on_air   - boolean, comes with data.analyze, stream status
 *                    data.rate     - table, rate_stat array
 */

#include <astra.h>

typedef struct
{
    mpegts_packet_type_t type;

    uint8_t cc;

    uint32_t packets;

    // errors
    uint32_t cc_error;  // Continuity Counter
    uint32_t sc_error;  // Scrambled
    uint32_t pes_error; // PES header
} analyze_item_t;

typedef struct
{
    uint16_t pnr;
    uint32_t crc;
} pmt_checksum_t;

struct module_data_t
{
    MODULE_STREAM_DATA();

    const char *name;
    bool rate_stat;
    int cc_limit;
    int bitrate_limit;
    bool join_pid;

    bool cc_check; // to skip initial cc errors
    bool video_check; // increase bitrate_limit for channel with video stream

    int idx_callback;

    uint16_t tsid;

    asc_timer_t *check_stat;
    analyze_item_t *stream[MAX_PID];

    mpegts_psi_t *pat;
    mpegts_psi_t *cat;
    mpegts_psi_t *pmt;
    mpegts_psi_t *sdt;
    mpegts_psi_t *nit;
    mpegts_psi_t *tdt;

    bool tdt_seen;

    int pmt_ready;
    int pmt_count;
    pmt_checksum_t *pmt_checksum_list;

    uint8_t sdt_max_section_id;
    uint32_t *sdt_checksum_list;

    // rate_stat
    uint64_t last_ts;
    uint32_t ts_count;
    int rate_count;
    int rate[10];
};

#define MSG(_msg) "[analyze %s] " _msg, mod->name

static const char __pid[] = "pid";
static const char __crc32[] = "crc32";
static const char __pnr[] = "pnr";
static const char __tsid[] = "tsid";
static const char __network_id[] = "network_id";
static const char __table_id[] = "table_id";
static const char __onid[] = "onid";
static const char __delivery[] = "delivery";
static const char __frequency_khz[] = "frequency_khz";
static const char __symbolrate_ksps[] = "symbolrate_ksps";
static const char __modulation[] = "modulation";
static const char __fec_inner[] = "fec_inner";
static const char __network_name[] = "network_name";
static const char __lcn_list[] = "lcn";
static const char __free_ca[] = "free_ca";
static const char __service_list[] = "service_list";
static const char __ts_list[] = "ts_list";
static const char __descriptors[] = "descriptors";
static const char __psi[] = "psi";
static const char __err[] = "error";
static const char __callback[] = "callback";

static uint32_t bcd_to_uint(const uint8_t *src, size_t digits)
{
    uint32_t value = 0;
    for(size_t i = 0; i < digits; ++i)
    {
        const uint8_t byte = src[i / 2];
        const uint8_t nibble = (i & 1) ? (byte & 0x0F) : (uint8_t)(byte >> 4);
        if(nibble > 9)
            break;
        value = (value * 10) + nibble;
    }
    return value;
}

static const char *modulation_name(uint8_t code)
{
    switch(code)
    {
        case 0x01: return "16qam";
        case 0x02: return "32qam";
        case 0x03: return "64qam";
        case 0x04: return "128qam";
        case 0x05: return "256qam";
        default: return "unknown";
    }
}

static const char *fec_name(uint8_t code)
{
    switch(code)
    {
        case 0x01: return "1/2";
        case 0x02: return "2/3";
        case 0x03: return "3/4";
        case 0x04: return "5/6";
        case 0x05: return "7/8";
        case 0x0F: return "auto";
        default: return "unknown";
    }
}

static void callback(module_data_t *mod)
{
    asc_assert((lua_type(lua, -1) == LUA_TTABLE), "table required");

    lua_rawgeti(lua, LUA_REGISTRYINDEX, mod->idx_callback);
    lua_pushvalue(lua, -2);
    lua_call(lua, 1, 0);

    lua_pop(lua, 1); // data
}

/*
 * oooooooooo   o   ooooooooooo
 *  888    888 888  88  888  88
 *  888oooo88 8  88     888
 *  888      8oooo88    888
 * o888o   o88o  o888o o888o
 *
 */

static void on_pat(void *arg, mpegts_psi_t *psi)
{
    module_data_t *mod = (module_data_t *)arg;

    if(psi->buffer[0] != 0x00)
        return;

    // check changes
    const uint32_t crc32 = PSI_GET_CRC32(psi);
    if(crc32 == psi->crc32)
        return;

    lua_newtable(lua);

    lua_pushnumber(lua, psi->pid);
    lua_setfield(lua, -2, __pid);

    // check crc
    if(crc32 != PSI_CALC_CRC32(psi))
    {
        lua_pushstring(lua, "PAT checksum error");
        lua_setfield(lua, -2, __err);
        callback(mod);
        return;
    }

    psi->crc32 = crc32;
    mod->tsid = PAT_GET_TSID(psi);

    lua_pushstring(lua, "pat");
    lua_setfield(lua, -2, __psi);

    lua_pushnumber(lua, psi->crc32);
    lua_setfield(lua, -2, __crc32);

    lua_pushnumber(lua, mod->tsid);
    lua_setfield(lua, -2, __tsid);

    mod->pmt_ready = 0;
    mod->pmt_count = 0;

    lua_newtable(lua);
    const uint8_t *pointer;
    PAT_ITEMS_FOREACH(psi, pointer)
    {
        const uint16_t pnr = PAT_ITEM_GET_PNR(psi, pointer);
        const uint16_t pid = PAT_ITEM_GET_PID(psi, pointer);

        if(!pid || pid >= NULL_TS_PID)
            continue;

        const int item_count = luaL_len(lua, -1) + 1;
        lua_pushnumber(lua, item_count);
        lua_newtable(lua);
        lua_pushnumber(lua, pnr);
        lua_setfield(lua, -2, __pnr);
        lua_pushnumber(lua, pid);
        lua_setfield(lua, -2, __pid);
        lua_settable(lua, -3); // append to the "programs" table

        if(!mod->stream[pid])
            mod->stream[pid] = (analyze_item_t *)calloc(1, sizeof(analyze_item_t));

        if(pnr != 0)
        {
            mod->stream[pid]->type = MPEGTS_PACKET_PMT;
            if(mod->join_pid)
                module_stream_demux_join_pid(mod, pid);
            ++ mod->pmt_count;
        }
        else
        {
            mod->stream[pid]->type = MPEGTS_PACKET_NIT;
            if(mod->join_pid)
                module_stream_demux_join_pid(mod, pid);
        }
    }
    lua_setfield(lua, -2, "programs");

    if(mod->pmt_checksum_list)
    {
        free(mod->pmt_checksum_list);
        mod->pmt_checksum_list = NULL;
    }
    if(mod->pmt_count > 0)
        mod->pmt_checksum_list = (pmt_checksum_t *)calloc(mod->pmt_count, sizeof(pmt_checksum_t));

    callback(mod);
}

/*
 *   oooooooo8     o   ooooooooooo
 * o888     88    888  88  888  88
 * 888           8  88     888
 * 888o     oo  8oooo88    888
 *  888oooo88 o88o  o888o o888o
 *
 */

static void on_cat(void *arg, mpegts_psi_t *psi)
{
    module_data_t *mod = (module_data_t *)arg;

    if(psi->buffer[0] != 0x01)
        return;

    // check changes
    const uint32_t crc32 = PSI_GET_CRC32(psi);
    if(crc32 == psi->crc32)
        return;

    lua_newtable(lua);

    lua_pushnumber(lua, psi->pid);
    lua_setfield(lua, -2, __pid);

    // check crc
    if(crc32 != PSI_CALC_CRC32(psi))
    {
        lua_pushstring(lua, "CAT checksum error");
        lua_setfield(lua, -2, __err);
        callback(mod);
        return;
    }
    psi->crc32 = crc32;

    lua_pushstring(lua, "cat");
    lua_setfield(lua, -2, __psi);

    lua_pushnumber(lua, psi->crc32);
    lua_setfield(lua, -2, __crc32);

    int descriptors_count = 1;
    lua_newtable(lua);
    const uint8_t *desc_pointer = CAT_DESC_FIRST(psi);
    while(!CAT_DESC_EOL(psi, desc_pointer))
    {
        lua_pushnumber(lua, descriptors_count++);
        mpegts_desc_to_lua(desc_pointer);
        lua_settable(lua, -3); // append to the "descriptors" table

        CAT_DESC_NEXT(psi, desc_pointer);
    }
    lua_setfield(lua, -2, __descriptors);

    callback(mod);
}

/*
 * oooooo   oooooo ooooo ooooooooooo
 *  888      888   888   88  888  88
 *  888      888   888       888
 *  888      888   888       888
 *  888ooooo  888 o888o     o888o
 *
 */

static void on_nit(void *arg, mpegts_psi_t *psi)
{
    module_data_t *mod = (module_data_t *)arg;
    const uint8_t *buf = psi->buffer;

    const uint8_t table_id = buf[0];
    if(table_id != 0x40 && table_id != 0x41)
        return;

    const uint32_t crc32 = PSI_GET_CRC32(psi);

    // Проверяем CRC, чтобы не принимать поврежденные секции.
    if(crc32 != PSI_CALC_CRC32(psi))
    {
        lua_newtable(lua);
        lua_pushnumber(lua, psi->pid);
        lua_setfield(lua, -2, __pid);
        lua_pushstring(lua, "NIT checksum error");
        lua_setfield(lua, -2, __err);
        callback(mod);
        return;
    }

    // Отсекаем повтор, если секция не менялась.
    if(crc32 == psi->crc32)
        return;
    psi->crc32 = crc32;

    const uint16_t network_id = (uint16_t)((buf[3] << 8) | buf[4]);

    lua_newtable(lua);
    lua_pushnumber(lua, psi->pid);
    lua_setfield(lua, -2, __pid);
    lua_pushstring(lua, "nit");
    lua_setfield(lua, -2, __psi);
    lua_pushnumber(lua, crc32);
    lua_setfield(lua, -2, __crc32);
    lua_pushnumber(lua, network_id);
    lua_setfield(lua, -2, __network_id);
    lua_pushnumber(lua, table_id);
    lua_setfield(lua, -2, __table_id);

    // Разбор NIT delivery (сейчас нужен DVB-C cable_delivery_system_descriptor).
    const size_t section_length = (size_t)(((buf[1] & 0x0F) << 8) | buf[2]);
    const size_t section_end = 3 + section_length;
    if(section_end >= 12 && section_end <= psi->buffer_size)
    {
        bool lcn_initialized = false;
        bool service_list_initialized = false;
        bool ts_list_initialized = false;
        int ts_list_count = 1;
        size_t pos = 8;
        if(pos + 2 <= section_end)
        {
            const uint16_t network_desc_len = (uint16_t)(((buf[pos] & 0x0F) << 8) | buf[pos + 1]);
            pos += 2;
            size_t network_desc_end = pos + network_desc_len;
            if(network_desc_end > section_end)
                network_desc_end = section_end;
            while(pos + 2 <= network_desc_end)
            {
                const uint8_t tag = buf[pos];
                const uint8_t len = buf[pos + 1];
                pos += 2;
                if(pos + len > network_desc_end)
                    break;
                if(tag == 0x40 && len > 0)
                {
                    char *name = iso8859_decode(&buf[pos], len);
                    if(name)
                    {
                        lua_pushstring(lua, name);
                        free(name);
                    }
                    else
                    {
                        lua_pushstring(lua, "");
                    }
                    lua_setfield(lua, -2, __network_name);
                }
                pos += len;
            }
            pos = network_desc_end;
        }
        if(pos + 2 <= section_end)
        {
            const uint16_t ts_loop_len = (uint16_t)(((buf[pos] & 0x0F) << 8) | buf[pos + 1]);
            pos += 2;
            size_t ts_loop_end = pos + ts_loop_len;
            if(section_end >= 4 && ts_loop_end > section_end - 4)
                ts_loop_end = section_end - 4;
            while(pos + 6 <= ts_loop_end)
            {
                const uint16_t tsid = (uint16_t)((buf[pos] << 8) | buf[pos + 1]);
                const uint16_t onid = (uint16_t)((buf[pos + 2] << 8) | buf[pos + 3]);
                const uint16_t desc_len = (uint16_t)(((buf[pos + 4] & 0x0F) << 8) | buf[pos + 5]);
                pos += 6;
                // Список TS для проверки network_search.
                if(!ts_list_initialized)
                {
                    lua_newtable(lua);
                    lua_setfield(lua, -2, __ts_list);
                    ts_list_initialized = true;
                }
                lua_getfield(lua, -1, __ts_list);
                if(lua_type(lua, -1) == LUA_TTABLE)
                {
                    char ts_entry[32];
                    snprintf(ts_entry, sizeof(ts_entry), "%u:%u", (unsigned)tsid, (unsigned)onid);
                    lua_pushnumber(lua, ts_list_count++);
                    lua_pushstring(lua, ts_entry);
                    lua_settable(lua, -3);
                }
                lua_pop(lua, 1);
                size_t desc_end = pos + desc_len;
                if(desc_end > ts_loop_end)
                    desc_end = ts_loop_end;
                while(pos + 2 <= desc_end)
                {
                    const uint8_t tag = buf[pos];
                    const uint8_t len = buf[pos + 1];
                    pos += 2;
                    if(pos + len > desc_end)
                        break;
                    if(tag == 0x44 && len >= 11)
                    {
                        const uint8_t *desc = &buf[pos];
                        const uint32_t freq_digits = bcd_to_uint(desc, 8);
                        const uint32_t sr_digits = bcd_to_uint(desc + 7, 7);
                        const uint32_t frequency_khz = freq_digits / 10;
                        const uint32_t symbolrate_ksps = sr_digits / 10;
                        const uint8_t modulation = desc[6];
                        const uint8_t fec = (uint8_t)(desc[10] & 0x0F);

                        lua_pushstring(lua, "cable");
                        lua_setfield(lua, -2, __delivery);
                        lua_pushnumber(lua, tsid);
                        lua_setfield(lua, -2, __tsid);
                        lua_pushnumber(lua, onid);
                        lua_setfield(lua, -2, __onid);
                        lua_pushnumber(lua, frequency_khz);
                        lua_setfield(lua, -2, __frequency_khz);
                        lua_pushnumber(lua, symbolrate_ksps);
                        lua_setfield(lua, -2, __symbolrate_ksps);
                        lua_pushstring(lua, modulation_name(modulation));
                        lua_setfield(lua, -2, __modulation);
                        lua_pushstring(lua, fec_name(fec));
                        lua_setfield(lua, -2, __fec_inner);
                        pos = desc_end;
                        break;
                    }
                    if(tag == 0x41 && len >= 3)
                    {
                        // service_list_descriptor: (service_id, service_type)
                        if(!service_list_initialized)
                        {
                            lua_newtable(lua);
                            lua_setfield(lua, -2, __service_list);
                            service_list_initialized = true;
                        }
                        lua_getfield(lua, -1, __service_list);
                        if(lua_type(lua, -1) == LUA_TTABLE)
                        {
                            size_t lpos = 0;
                            while(lpos + 3 <= len)
                            {
                                const uint16_t service_id = (uint16_t)((buf[pos + lpos] << 8) | buf[pos + lpos + 1]);
                                const uint8_t service_type = buf[pos + lpos + 2];
                                lua_pushnumber(lua, service_id);
                                lua_pushnumber(lua, service_type);
                                lua_settable(lua, -3);
                                lpos += 3;
                            }
                        }
                        lua_pop(lua, 1);
                    }
                    if(tag == 0x83 && len >= 4)
                    {
                        // NorDig logical_channel_descriptor: service_id + visible + lcn
                        if(!lcn_initialized)
                        {
                            lua_newtable(lua);
                            lua_setfield(lua, -2, __lcn_list);
                            lcn_initialized = true;
                        }
                        lua_getfield(lua, -1, __lcn_list);
                        if(lua_type(lua, -1) == LUA_TTABLE)
                        {
                            size_t lpos = 0;
                            while(lpos + 4 <= len)
                            {
                                const uint16_t service_id = (uint16_t)((buf[pos + lpos] << 8) | buf[pos + lpos + 1]);
                                const uint16_t lcn = (uint16_t)(((buf[pos + lpos + 2] & 0x03) << 8) | buf[pos + lpos + 3]);
                                lua_pushnumber(lua, service_id);
                                lua_pushnumber(lua, lcn);
                                lua_settable(lua, -3);
                                lpos += 4;
                            }
                        }
                        lua_pop(lua, 1);
                    }
                    pos += len;
                }
                pos = desc_end;
            }
        }
    }

    callback(mod);
}

/*
 * oooooooooo oooo     oooo ooooooooooo
 *  888    888 8888o   888  88  888  88
 *  888oooo88  88 888o8 88      888
 *  888        88  888  88      888
 * o888o      o88o  8  o88o    o888o
 *
 */

static void on_pmt(void *arg, mpegts_psi_t *psi)
{
    module_data_t *mod = (module_data_t *)arg;

    if(psi->buffer[0] != 0x02)
        return;

    const uint32_t crc32 = PSI_GET_CRC32(psi);

    // check crc
    if(crc32 != PSI_CALC_CRC32(psi))
    {
        lua_newtable(lua);

        lua_pushnumber(lua, psi->pid);
        lua_setfield(lua, -2, __pid);

        lua_pushstring(lua, "PMT checksum error");
        lua_setfield(lua, -2, __err);
        callback(mod);
        return;
    }

    const uint16_t pnr = PMT_GET_PNR(psi);

    // check changes
    for(int i = 0; i < mod->pmt_count; ++i)
    {
        if(mod->pmt_checksum_list[i].pnr == pnr)
        {
            if(mod->pmt_checksum_list[i].crc == crc32)
                return;

            -- mod->pmt_ready;
            mod->pmt_checksum_list[i].pnr = 0;
            break;
        }
    }

    for(int i = 0; i < mod->pmt_count; ++i)
    {
        if(mod->pmt_checksum_list[i].pnr == 0)
        {
            ++ mod->pmt_ready;
            mod->pmt_checksum_list[i].pnr = pnr;
            mod->pmt_checksum_list[i].crc = crc32;
            break;
        }
    }

    mod->video_check = false;

    lua_newtable(lua);

    lua_pushnumber(lua, psi->pid);
    lua_setfield(lua, -2, __pid);

    lua_pushstring(lua, "pmt");
    lua_setfield(lua, -2, __psi);

    lua_pushnumber(lua, crc32);
    lua_setfield(lua, -2, __crc32);

    lua_pushnumber(lua, pnr);
    lua_setfield(lua, -2, __pnr);

    int descriptors_count = 1;
    lua_newtable(lua);
    const uint8_t *desc_pointer = PMT_DESC_FIRST(psi);
    while(!PMT_DESC_EOL(psi, desc_pointer))
    {
        lua_pushnumber(lua, descriptors_count++);
        mpegts_desc_to_lua(desc_pointer);
        lua_settable(lua, -3); // append to the "descriptors" table

        PMT_DESC_NEXT(psi, desc_pointer);
    }
    lua_setfield(lua, -2, __descriptors);

    lua_pushnumber(lua, PMT_GET_PCR(psi));
    lua_setfield(lua, -2, "pcr");

    int streams_count = 1;
    lua_newtable(lua);
    const uint8_t *pointer;
    PMT_ITEMS_FOREACH(psi, pointer)
    {
        const uint16_t pid = PMT_ITEM_GET_PID(psi, pointer);
        const uint8_t type = PMT_ITEM_GET_TYPE(psi, pointer);

        if(!pid || pid >= NULL_TS_PID)
            continue;

        lua_pushnumber(lua, streams_count++);
        lua_newtable(lua);

        if(!mod->stream[pid])
            mod->stream[pid] = (analyze_item_t *)calloc(1, sizeof(analyze_item_t));

        mod->stream[pid]->type = mpegts_pes_type(type);

        lua_pushnumber(lua, pid);
        lua_setfield(lua, -2, __pid);

        descriptors_count = 1;
        lua_newtable(lua);
        const uint8_t *desc_pointer;
        PMT_ITEM_DESC_FOREACH(pointer, desc_pointer)
        {
            lua_pushnumber(lua, descriptors_count++);
            mpegts_desc_to_lua(desc_pointer);
            lua_settable(lua, -3); // append to the "streams[X].descriptors" table

            if(type == 0x06)
            {
                switch(desc_pointer[0])
                {
                    case 0x59:
                        mod->stream[pid]->type = MPEGTS_PACKET_SUB;
                        break;
                    case 0x6A:
                        mod->stream[pid]->type = MPEGTS_PACKET_AUDIO;
                        break;
                    default:
                        break;
                }
            }
        }
        lua_setfield(lua, -2, __descriptors);

        lua_pushstring(lua, mpegts_type_name(mod->stream[pid]->type));
        lua_setfield(lua, -2, "type_name");

        lua_pushnumber(lua, type);
        lua_setfield(lua, -2, "type_id");

        lua_settable(lua, -3); // append to the "streams" table

        if(mod->stream[pid]->type == MPEGTS_PACKET_VIDEO)
            mod->video_check = true;
    }
    lua_setfield(lua, -2, "streams");

    callback(mod);
}

/*
 *  oooooooo8 ooooooooo   ooooooooooo
 * 888         888    88o 88  888  88
 *  888oooooo  888    888     888
 *         888 888    888     888
 * o88oooo888 o888ooo88      o888o
 *
 */

static void on_sdt(void *arg, mpegts_psi_t *psi)
{
    module_data_t *mod = (module_data_t *)arg;

    if(psi->buffer[0] != 0x42)
        return;

    if(mod->tsid != SDT_GET_TSID(psi))
        return;

    const uint32_t crc32 = PSI_GET_CRC32(psi);

    // check crc
    if(crc32 != PSI_CALC_CRC32(psi))
    {
        lua_newtable(lua);

        lua_pushnumber(lua, psi->pid);
        lua_setfield(lua, -2, __pid);

        lua_pushstring(lua, "SDT checksum error");
        lua_setfield(lua, -2, __err);
        callback(mod);
        return;
    }

    // check changes
    if(!mod->sdt_checksum_list)
    {
        const uint8_t max_section_id = SDT_GET_LAST_SECTION_NUMBER(psi);
        mod->sdt_max_section_id = max_section_id;
        mod->sdt_checksum_list = (uint32_t *)calloc(max_section_id + 1, sizeof(uint32_t));
    }
    const uint8_t section_id = SDT_GET_SECTION_NUMBER(psi);
    if(section_id > mod->sdt_max_section_id)
    {
        asc_log_warning(MSG("SDT: section_number is greater then section_last_number"));
        return;
    }
    if(mod->sdt_checksum_list[section_id] == crc32)
        return;

    if(mod->sdt_checksum_list[section_id] != 0)
    {
        // Reload stream
        free(mod->sdt_checksum_list);
        mod->sdt_checksum_list = NULL;
        return;
    }

    mod->sdt_checksum_list[section_id] = crc32;

    lua_newtable(lua);

    lua_pushnumber(lua, psi->pid);
    lua_setfield(lua, -2, __pid);

    lua_pushstring(lua, "sdt");
    lua_setfield(lua, -2, __psi);

    lua_pushnumber(lua, crc32);
    lua_setfield(lua, -2, __crc32);

    lua_pushnumber(lua, mod->tsid);
    lua_setfield(lua, -2, __tsid);

    int descriptors_count;
    int services_count = 1;
    lua_newtable(lua);
    const uint8_t *pointer;
    SDT_ITEMS_FOREACH(psi, pointer)
    {
        const uint16_t sid = SDT_ITEM_GET_SID(psi, pointer);

        lua_pushnumber(lua, services_count++);

        lua_newtable(lua);
        lua_pushnumber(lua, sid);
        lua_setfield(lua, -2, "sid");
        // В SDT free_CA_mode находится в старшем полубайте после running_status.
        lua_pushboolean(lua, (pointer[3] & 0x10) != 0);
        lua_setfield(lua, -2, __free_ca);

        descriptors_count = 1;
        lua_newtable(lua);
        const uint8_t *desc_pointer;
        SDT_ITEM_DESC_FOREACH(pointer, desc_pointer)
        {
            lua_pushnumber(lua, descriptors_count++);
            mpegts_desc_to_lua(desc_pointer);
            lua_settable(lua, -3);
        }
        lua_setfield(lua, -2, __descriptors);

        lua_settable(lua, -3); // append to the "services[X].descriptors" table
    }
    lua_setfield(lua, -2, "services");

    callback(mod);
}

/*
 * oooooooo8 ooooooooooo ooooooooooo
 * 888         888    88 88  888  88
 *  888oooooo  888        888
 *         888 888        888
 * o88oooo888 o888o      o888o
 *
 */

static void on_tdt(void *arg, mpegts_psi_t *psi)
{
    module_data_t *mod = (module_data_t *)arg;

    const uint8_t table_id = psi->buffer[0];
    if(table_id != 0x70 && table_id != 0x73)
        return;

    if(table_id == 0x73)
    {
        const uint32_t crc32 = PSI_GET_CRC32(psi);
        if(crc32 != PSI_CALC_CRC32(psi))
        {
            lua_newtable(lua);
            lua_pushnumber(lua, psi->pid);
            lua_setfield(lua, -2, __pid);
            lua_pushstring(lua, "TOT checksum error");
            lua_setfield(lua, -2, __err);
            callback(mod);
            return;
        }
        if(crc32 == psi->crc32)
            return;
        psi->crc32 = crc32;

        lua_newtable(lua);
        lua_pushnumber(lua, psi->pid);
        lua_setfield(lua, -2, __pid);
        lua_pushstring(lua, "tot");
        lua_setfield(lua, -2, __psi);
        lua_pushnumber(lua, crc32);
        lua_setfield(lua, -2, __crc32);
        lua_pushnumber(lua, table_id);
        lua_setfield(lua, -2, __table_id);
        callback(mod);
        return;
    }

    // TDT не имеет CRC, поэтому логируем единожды.
    if(mod->tdt_seen)
        return;
    mod->tdt_seen = true;

    lua_newtable(lua);
    lua_pushnumber(lua, psi->pid);
    lua_setfield(lua, -2, __pid);
    lua_pushstring(lua, "tdt");
    lua_setfield(lua, -2, __psi);
    lua_pushnumber(lua, table_id);
    lua_setfield(lua, -2, __table_id);
    callback(mod);
}

/*
 * ooooooooooo  oooooooo8
 * 88  888  88 888
 *     888      888oooooo
 *     888             888
 *    o888o    o88oooo888
 *
 */

static void append_rate(module_data_t *mod, int rate)
{
    mod->rate[mod->rate_count] = rate;
    ++mod->rate_count;
    if(mod->rate_count >= (int)(sizeof(mod->rate)/sizeof(*mod->rate)))
    {
        lua_newtable(lua);
        lua_newtable(lua);
        for(int i = 0; i < mod->rate_count; ++i)
        {
            lua_pushnumber(lua, i + 1);
            lua_pushnumber(lua, mod->rate[i]);
            lua_settable(lua, -3);
        }
        lua_setfield(lua, -2, "rate");
        callback(mod);
        mod->rate_count = 0;
    }
}

static void on_ts(module_data_t *mod, const uint8_t *ts)
{
    if(mod->rate_stat)
    {
        ++mod->ts_count;

        uint64_t diff_interval = 0;
        const uint64_t cur = asc_utime() / 10000;

        if(cur != mod->last_ts)
        {
            if(mod->last_ts != 0 && cur > mod->last_ts)
                diff_interval = cur - mod->last_ts;

            mod->last_ts = cur;
        }

        if(diff_interval > 0)
        {
            if(diff_interval > 1)
            {
                for(; diff_interval > 0; --diff_interval)
                    append_rate(mod, 0);
            }

            append_rate(mod, mod->ts_count);
            mod->ts_count = 0;
        }
    }

    const uint16_t pid = TS_GET_PID(ts);
    analyze_item_t *item = NULL;
    if(ts[0] == 0x47 && pid < MAX_PID)
        item = mod->stream[pid];
    if(!item)
        item = mod->stream[NULL_TS_PID];

    ++item->packets;

    if(item->type == MPEGTS_PACKET_NULL)
        return;

    if(item->type & (MPEGTS_PACKET_PSI | MPEGTS_PACKET_SI))
    {
        switch(item->type)
        {
            case MPEGTS_PACKET_PAT:
                mpegts_psi_mux(mod->pat, ts, on_pat, mod);
                break;
            case MPEGTS_PACKET_CAT:
                mpegts_psi_mux(mod->cat, ts, on_cat, mod);
                break;
            case MPEGTS_PACKET_PMT:
                mod->pmt->pid = pid;
                mpegts_psi_mux(mod->pmt, ts, on_pmt, mod);
                break;
            case MPEGTS_PACKET_SDT:
                mpegts_psi_mux(mod->sdt, ts, on_sdt, mod);
                break;
            case MPEGTS_PACKET_NIT:
                mpegts_psi_mux(mod->nit, ts, on_nit, mod);
                break;
            case MPEGTS_PACKET_TDT:
                mpegts_psi_mux(mod->tdt, ts, on_tdt, mod);
                break;
            default:
                break;
        }
    }

    // Analyze

    // skip packets without payload
    if(!TS_IS_PAYLOAD(ts))
        return;

    const uint8_t cc = TS_GET_CC(ts);
    const uint8_t last_cc = (item->cc + 1) & 0x0F;
    item->cc = cc;

    if(cc != last_cc)
        ++item->cc_error;

    if(TS_IS_SCRAMBLED(ts))
        ++item->sc_error;

    if(!(item->type & MPEGTS_PACKET_PES))
        return;

    if(item->type == MPEGTS_PACKET_VIDEO && TS_IS_PAYLOAD_START(ts))
    {
        const uint8_t *payload = TS_GET_PAYLOAD(ts);
        if(payload && PES_BUFFER_GET_HEADER(payload) != 0x000001)
            ++item->pes_error;
    }
}

/*
 *  oooooooo8 ooooooooooo   o   ooooooooooo
 * 888        88  888  88  888  88  888  88
 *  888oooooo     888     8  88     888
 *         888    888    8oooo88    888
 * o88oooo888    o888o o88o  o888o o888o
 *
 */

static void on_check_stat(void *arg)
{
    module_data_t *mod = (module_data_t *)arg;

    int items_count = 1;
    lua_newtable(lua);

    bool on_air = true;

    uint32_t bitrate = 0;
    uint32_t cc_errors = 0;
    uint32_t pes_errors = 0;
    bool scrambled = false;

    const uint32_t bitrate_limit = (mod->bitrate_limit > 0)
                                 ? ((uint32_t)mod->bitrate_limit)
                                 : ((mod->video_check) ? 256 : 32);

    lua_newtable(lua);
    for(int i = 0; i < MAX_PID; ++i)
    {
        analyze_item_t *item = mod->stream[i];

        if(!item)
            continue;

        if(!mod->cc_check)
            item->cc_error = 0;

        lua_pushnumber(lua, items_count++);
        lua_newtable(lua);

        lua_pushnumber(lua, i);
        lua_setfield(lua, -2, __pid);

        const uint32_t item_bitrate = (item->packets * TS_PACKET_SIZE * 8) / 1000;
        bitrate += item_bitrate;

        lua_pushnumber(lua, item_bitrate);
        lua_setfield(lua, -2, "bitrate");

        lua_pushnumber(lua, item->cc_error);
        lua_setfield(lua, -2, "cc_error");
        lua_pushnumber(lua, item->sc_error);
        lua_setfield(lua, -2, "sc_error");
        lua_pushnumber(lua, item->pes_error);
        lua_setfield(lua, -2, "pes_error");

        cc_errors += item->cc_error;
        pes_errors += item->pes_error;

        if(item->type == MPEGTS_PACKET_VIDEO || item->type == MPEGTS_PACKET_AUDIO)
        {
            if(item->sc_error)
            {
                scrambled = true;
                on_air = false;
            }
            if(item->pes_error > 2)
                on_air = false;
        }

        item->packets = 0;
        item->cc_error = 0;
        item->sc_error = 0;
        item->pes_error = 0;

        lua_settable(lua, -3);
    }
    lua_setfield(lua, -2, "analyze");

    lua_newtable(lua);
    {
        lua_pushnumber(lua, bitrate);
        lua_setfield(lua, -2, "bitrate");
        lua_pushnumber(lua, cc_errors);
        lua_setfield(lua, -2, "cc_errors");
        lua_pushnumber(lua, pes_errors);
        lua_setfield(lua, -2, "pes_errors");
        lua_pushboolean(lua, scrambled);
        lua_setfield(lua, -2, "scrambled");
    }
    lua_setfield(lua, -2, "total");

    if(!mod->cc_check)
        mod->cc_check = true;

    if(bitrate < bitrate_limit)
        on_air = false;
    if(mod->cc_limit > 0 && cc_errors >= (uint32_t)mod->cc_limit)
        on_air = false;
    if(mod->pmt_ready == 0 || mod->pmt_ready != mod->pmt_count)
        on_air = false;

    lua_pushboolean(lua, on_air);
    lua_setfield(lua, -2, "on_air");

    callback(mod);
}

/*
 * oooo     oooo  ooooooo  ooooooooo  ooooo  oooo ooooo       ooooooooooo
 *  8888o   888 o888   888o 888    88o 888    88   888         888    88
 *  88 888o8 88 888     888 888    888 888    88   888         888ooo8
 *  88  888  88 888o   o888 888    888 888    88   888      o  888    oo
 * o88o  8  o88o  88ooo88  o888ooo88    888oo88   o888ooooo88 o888ooo8888
 *
 */

static void module_init(module_data_t *mod)
{
    module_option_string("name", &mod->name, NULL);
    asc_assert(mod->name != NULL, "[analyze] option 'name' is required");

    lua_getfield(lua, MODULE_OPTIONS_IDX, __callback);
    asc_assert(lua_isfunction(lua, -1), MSG("option 'callback' is required"));
    mod->idx_callback = luaL_ref(lua, LUA_REGISTRYINDEX);

    module_option_boolean("rate_stat", &mod->rate_stat);
    module_option_number("cc_limit", &mod->cc_limit);
    module_option_number("bitrate_limit", &mod->bitrate_limit);
    module_option_boolean("join_pid", &mod->join_pid);

    module_stream_init(mod, on_ts);
    if(mod->join_pid)
    {
        module_stream_demux_set(mod, NULL, NULL);
        module_stream_demux_join_pid(mod, 0x00);
        module_stream_demux_join_pid(mod, 0x01);
        module_stream_demux_join_pid(mod, 0x10);
        module_stream_demux_join_pid(mod, 0x11);
        module_stream_demux_join_pid(mod, 0x12);
        module_stream_demux_join_pid(mod, 0x14);
    }

    // PAT
    mod->stream[0x00] = (analyze_item_t *)calloc(1, sizeof(analyze_item_t));
    mod->stream[0x00]->type = MPEGTS_PACKET_PAT;
    mod->pat = mpegts_psi_init(MPEGTS_PACKET_PAT, 0x00);
    // CAT
    mod->stream[0x01] = (analyze_item_t *)calloc(1, sizeof(analyze_item_t));
    mod->stream[0x01]->type = MPEGTS_PACKET_CAT;
    mod->cat = mpegts_psi_init(MPEGTS_PACKET_CAT, 0x01);
    // SDT
    mod->stream[0x11] = (analyze_item_t *)calloc(1, sizeof(analyze_item_t));
    mod->stream[0x11]->type = MPEGTS_PACKET_SDT;
    mod->sdt = mpegts_psi_init(MPEGTS_PACKET_SDT, 0x11);
    // NIT
    mod->stream[0x10] = (analyze_item_t *)calloc(1, sizeof(analyze_item_t));
    mod->stream[0x10]->type = MPEGTS_PACKET_NIT;
    mod->nit = mpegts_psi_init(MPEGTS_PACKET_NIT, 0x10);
    // EIT
    mod->stream[0x12] = (analyze_item_t *)calloc(1, sizeof(analyze_item_t));
    mod->stream[0x12]->type = MPEGTS_PACKET_EIT;
    // TDT/TOT
    mod->stream[0x14] = (analyze_item_t *)calloc(1, sizeof(analyze_item_t));
    mod->stream[0x14]->type = MPEGTS_PACKET_TDT;
    mod->tdt = mpegts_psi_init(MPEGTS_PACKET_TDT, 0x14);
    // PMT
    mod->pmt = mpegts_psi_init(MPEGTS_PACKET_PMT, MAX_PID);
    // NULL
    mod->stream[NULL_TS_PID] = (analyze_item_t *)calloc(1, sizeof(analyze_item_t));
    mod->stream[NULL_TS_PID]->type = MPEGTS_PACKET_NULL;

    mod->check_stat = asc_timer_init(1000, on_check_stat, mod);
}

static void module_destroy(module_data_t *mod)
{
    module_stream_destroy(mod);

    if(mod->idx_callback)
    {
        luaL_unref(lua, LUA_REGISTRYINDEX, mod->idx_callback);
        mod->idx_callback = 0;
    }

    for(int i = 0; i < MAX_PID; ++i)
    {
        if(mod->stream[i])
            free(mod->stream[i]);
    }

    mpegts_psi_destroy(mod->pat);
    mpegts_psi_destroy(mod->cat);
    mpegts_psi_destroy(mod->sdt);
    mpegts_psi_destroy(mod->pmt);
    mpegts_psi_destroy(mod->nit);
    mpegts_psi_destroy(mod->tdt);

    asc_timer_destroy(mod->check_stat);

    if(mod->pmt_checksum_list)
        free(mod->pmt_checksum_list);
    if(mod->sdt_checksum_list)
        free(mod->sdt_checksum_list);
}

MODULE_STREAM_METHODS()
MODULE_LUA_METHODS()
{
    MODULE_STREAM_METHODS_REF()
};
MODULE_LUA_REGISTER(analyze)
