/*
 * Read-only DVB EIT section collector.
 *
 * This module is a sibling stream consumer: it requests PID 0x12 from its
 * upstream, reassembles complete EIT sections, and calls Lua without ever
 * forwarding or modifying transport-stream packets.
 */

#include <astra.h>

struct module_data_t
{
    MODULE_STREAM_DATA();

    mpegts_psi_t *eit;
    int idx_callback;
    uint16_t service_id;
    bool filter_service;
    uint32_t section_crc[17][256];
};

static int actual_table_index(uint8_t table_id)
{
    if(table_id == 0x4E)
        return 0;
    if(table_id >= 0x50 && table_id <= 0x5F)
        return 1 + (table_id - 0x50);
    return -1;
}

static void disable_callback(module_data_t *mod, const char *message)
{
    asc_log_error("[eit_collect] callback error: %s", message ? message : "unknown");
    if(mod->idx_callback > 0)
    {
        luaL_unref(lua, LUA_REGISTRYINDEX, mod->idx_callback);
        mod->idx_callback = LUA_NOREF;
    }
}

static void on_eit(void *arg, mpegts_psi_t *psi)
{
    module_data_t *mod = (module_data_t *)arg;
    if(!psi || psi->buffer_size < 18 || mod->idx_callback <= 0)
        return;

    const uint8_t table_id = psi->buffer[0];
    const int table_index = actual_table_index(table_id);
    if(table_index < 0)
        return;

    /* current_next_indicator must be set for an active schedule. */
    if((psi->buffer[5] & 0x01) == 0)
        return;

    const uint16_t service_id = EIT_GET_PNR(psi);
    if(mod->filter_service && service_id != mod->service_id)
        return;

    const uint32_t crc = PSI_GET_CRC32(psi);
    if(crc != PSI_CALC_CRC32(psi))
        return;

    const uint8_t section_number = psi->buffer[6];
    if(mod->section_crc[table_index][section_number] == crc)
        return;
    mod->section_crc[table_index][section_number] = crc;

    lua_rawgeti(lua, LUA_REGISTRYINDEX, mod->idx_callback);
    lua_pushlstring(lua, (const char *)psi->buffer, psi->buffer_size);
    if(lua_pcall(lua, 1, 0, 0) != 0)
    {
        const char *message = lua_tostring(lua, -1);
        disable_callback(mod, message);
        lua_pop(lua, 1);
    }
}

static void on_ts(module_data_t *mod, const uint8_t *ts)
{
    if(TS_GET_PID(ts) != 0x12)
        return;
    mpegts_psi_mux(mod->eit, ts, on_eit, mod);
}

static void module_init(module_data_t *mod)
{
    lua_getfield(lua, MODULE_OPTIONS_IDX, "callback");
    asc_assert(lua_isfunction(lua, -1), "[eit_collect] option 'callback' is required");
    mod->idx_callback = luaL_ref(lua, LUA_REGISTRYINDEX);

    int service_id = 0;
    if(module_option_number("service_id", &service_id) && service_id > 0 && service_id <= 0xFFFF)
    {
        mod->service_id = (uint16_t)service_id;
        mod->filter_service = true;
    }

    module_stream_init(mod, on_ts);
    module_stream_demux_set(mod, NULL, NULL);
    module_stream_demux_join_pid(mod, 0x12);
    mod->eit = mpegts_psi_init(MPEGTS_PACKET_EIT, 0x12);
}

static void module_destroy(module_data_t *mod)
{
    module_stream_destroy(mod);
    if(mod->eit)
    {
        mpegts_psi_destroy(mod->eit);
        mod->eit = NULL;
    }
    if(mod->idx_callback > 0)
    {
        luaL_unref(lua, LUA_REGISTRYINDEX, mod->idx_callback);
        mod->idx_callback = LUA_NOREF;
    }
}

MODULE_STREAM_METHODS()
MODULE_LUA_METHODS()
{
    MODULE_STREAM_METHODS_REF()
};

MODULE_LUA_REGISTER(eit_collect)
