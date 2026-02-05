/*
 * Astral Module: MPEG-TS (MPTS Mux)
 *
 * Реализует MPTS-мультиплексор с генерацией PSI/SI и CBR.
 */

#include <astra.h>
#include <time.h>
#include <stdlib.h>

#define PID_DROP 0xFFFF
#define MPTS_MAX_PIDS 8192
#define PCR_MAX_TICKS ((1ULL << 33) * 300ULL)
#define MPTS_PNR_MAX 65535
#define MPTS_MAX_LCN_TAGS 8

typedef struct mpts_service_t mpts_service_t;

typedef struct
{
    module_stream_t stream;
    mpts_service_t *service;
} mpts_input_t;

struct mpts_service_t
{
    struct module_data_t *mod;

    int index;
    char *label;

    uint16_t pnr_cfg;
    bool has_pnr;
    uint16_t pnr_in;
    uint16_t pnr_out;
    bool pnr_conflict_warned;
    bool pnr_missing_warned;

    uint16_t pmt_pid_in;
    uint16_t pmt_pid_out;
    uint16_t pcr_pid_in;
    uint16_t pcr_pid_out;
    bool pcr_missing_warned;
    bool pcr_not_in_es_warned;
    bool spts_only_warned;

    double pcr_smooth_offset;
    bool pcr_smooth_ready;

    char *service_name;
    char *service_provider;
    uint8_t service_type_id;
    bool has_service_type_id;
    bool scrambled;
    uint16_t lcn;
    bool has_lcn;

    bool ready;
    bool mapping_ready;
    uint32_t pmt_crc;
    uint8_t pmt_version;

    uint16_t pid_map[MPTS_MAX_PIDS];

    mpegts_psi_t *pat;
    mpegts_psi_t *pmt;
    mpegts_psi_t *pmt_out;

    mpts_input_t *input;
};

struct module_data_t
{
    MODULE_STREAM_DATA();

    const char *name;

    uint16_t tsid;
    uint16_t onid;
    uint16_t network_id;

    const char *network_name;
    const char *provider_name;
    const char *codepage;
    const char *country;
    int utc_offset;

    const char *delivery;
    uint32_t frequency_khz;
    uint32_t symbolrate_ksps;
    const char *modulation;
    const char *fec;
    const char *network_search;

    int si_interval_ms;
    int target_bitrate;

    bool disable_auto_remap;
    bool pass_nit;
    bool pass_sdt;
    bool pass_eit;
    bool pass_tdt;
    bool pass_cat;
    bool pcr_restamp;
    bool pcr_smoothing;
    bool strict_pnr;
    bool spts_only;

    int eit_source_index;
    int cat_source_index;
    uint8_t lcn_descriptor_tag;
    uint8_t lcn_descriptor_tags[MPTS_MAX_LCN_TAGS];
    uint8_t lcn_descriptor_tags_count;

    double pcr_smooth_alpha;
    uint64_t pcr_smooth_max_offset_ticks;

    uint8_t pat_version;
    uint8_t cat_version;
    uint8_t nit_version;
    uint8_t sdt_version;
    bool pat_version_fixed;
    bool cat_version_fixed;
    bool nit_version_fixed;
    bool sdt_version_fixed;

    bool psi_dirty;
    bool psi_built;

    bool pass_warned;
    bool eit_source_warned;
    bool cat_source_warned;

    uint8_t cc[MPTS_MAX_PIDS];
    bool pid_in_use[MPTS_MAX_PIDS];
    uint16_t next_pid;

    asc_list_t *services;
    int service_count;

    mpegts_psi_t *pat_out;
    mpegts_psi_t *cat_out;
    mpegts_psi_t *sdt_out;
    mpegts_psi_t *nit_out;
    mpegts_psi_t *tdt_out;
    mpegts_psi_t *tot_out;

    asc_timer_t *si_timer;
    asc_timer_t *cbr_timer;
    uint64_t cbr_start_us;
    uint64_t sent_packets;
    uint64_t null_packets;
    uint64_t cbr_last_warn_us;
    uint64_t pcr_restamp_start_us;
    uint64_t start_us;
    uint64_t last_si_us;
    uint32_t psi_interval_actual_ms;

    mpegts_psi_t *eit_in;
    mpts_service_t *eit_source;
    mpts_service_t *cat_source;
};

#define MSG(_msg) "[mpts %s] " _msg, (mod->name ? mod->name : "mux")
#define SVC_MSG(_svc, _msg) "[mpts %s #%d] " _msg, (mod->name ? mod->name : "mux"), (_svc)->index

static uint8_t to_bcd(uint8_t value)
{
    return (uint8_t)(((value / 10) << 4) | (value % 10));
}

static void write_bcd(uint8_t *dst, size_t digits, uint32_t value)
{
    char buf[16];
    if(digits >= sizeof(buf))
        digits = sizeof(buf) - 1;
    snprintf(buf, sizeof(buf), "%0*u", (int)digits, value);
    for(size_t i = 0; i < digits; ++i)
    {
        const uint8_t digit = (uint8_t)(buf[i] - '0');
        if((i & 1) == 0)
            dst[i / 2] = (uint8_t)(digit << 4);
        else
            dst[i / 2] |= digit;
    }
}

static uint16_t mjd_from_time(time_t t)
{
    if(t < 0)
        t = 0;
    return (uint16_t)(40587 + (t / 86400));
}

static void write_utc_time(uint8_t *dst)
{
    const time_t now = time(NULL);
    const struct tm *tm = gmtime(&now);
    const uint16_t mjd = mjd_from_time(now);

    dst[0] = (uint8_t)(mjd >> 8);
    dst[1] = (uint8_t)(mjd & 0xFF);
    dst[2] = to_bcd((uint8_t)(tm ? tm->tm_hour : 0));
    dst[3] = to_bcd((uint8_t)(tm ? tm->tm_min : 0));
    dst[4] = to_bcd((uint8_t)(tm ? tm->tm_sec : 0));
}

static int64_t pcr_diff(uint64_t a, uint64_t b)
{
    int64_t diff = (int64_t)(a - b);
    const int64_t half = (int64_t)(PCR_MAX_TICKS / 2);
    if(diff > half)
        diff -= (int64_t)PCR_MAX_TICKS;
    else if(diff < -half)
        diff += (int64_t)PCR_MAX_TICKS;
    return diff;
}

static mpts_service_t *find_service_by_pnr_in(module_data_t *mod, uint16_t pnr)
{
    asc_list_for(mod->services)
    {
        mpts_service_t *svc = (mpts_service_t *)asc_list_data(mod->services);
        if(svc->pnr_in == pnr)
            return svc;
        if(svc->has_pnr && svc->pnr_cfg == pnr)
            return svc;
    }
    return NULL;
}

static void reserve_pid(module_data_t *mod, uint16_t pid)
{
    if(pid < MPTS_MAX_PIDS)
        mod->pid_in_use[pid] = true;
}

static uint16_t alloc_pid(module_data_t *mod)
{
    const uint16_t start = mod->next_pid;
    for(uint16_t pid = start; pid < NULL_TS_PID; ++pid)
    {
        if(!mod->pid_in_use[pid])
        {
            mod->pid_in_use[pid] = true;
            mod->next_pid = pid + 1;
            return pid;
        }
    }
    for(uint16_t pid = 0x0020; pid < start; ++pid)
    {
        if(!mod->pid_in_use[pid])
        {
            mod->pid_in_use[pid] = true;
            mod->next_pid = pid + 1;
            return pid;
        }
    }
    return PID_DROP;
}

static void mpts_send_ts(module_data_t *mod, const uint8_t *ts)
{
    uint8_t out[TS_PACKET_SIZE];
    memcpy(out, ts, TS_PACKET_SIZE);
    const uint16_t pid = TS_GET_PID(out);
    const uint8_t cc = mod->cc[pid] & 0x0F;
    TS_SET_CC(out, cc);
    mod->cc[pid] = (uint8_t)((cc + 1) & 0x0F);
    module_stream_send(mod, out);
    mod->sent_packets++;
    if(pid == NULL_TS_PID)
        mod->null_packets++;
    if(mod->start_us == 0)
        mod->start_us = asc_utime();
}

static void mpts_send_psi(void *arg, const uint8_t *ts)
{
    mpts_send_ts((module_data_t *)arg, ts);
}

static void mpts_send_null(module_data_t *mod, size_t count)
{
    static const uint8_t base_null[TS_PACKET_SIZE] = {
        0x47, 0x1F, 0xFF, 0x10
    };
    for(size_t i = 0; i < count; ++i)
        mpts_send_ts(mod, base_null);
}

static void service_release_map(mpts_service_t *svc)
{
    module_data_t *mod = svc->mod;
    for(uint32_t pid = 0; pid < MPTS_MAX_PIDS; ++pid)
    {
        const uint16_t mapped = svc->pid_map[pid];
        if(mapped != PID_DROP && mapped < MPTS_MAX_PIDS)
            mod->pid_in_use[mapped] = false;
        svc->pid_map[pid] = PID_DROP;
    }
    if(svc->pmt_pid_out > 0 && svc->pmt_pid_out < MPTS_MAX_PIDS)
        mod->pid_in_use[svc->pmt_pid_out] = false;
    svc->pmt_pid_out = 0;
    svc->pcr_pid_out = 0;
    svc->mapping_ready = false;
}

static bool service_map_pids(mpts_service_t *svc)
{
    module_data_t *mod = svc->mod;
    if(!svc->pmt || svc->pmt->buffer_size == 0)
        return false;

    service_release_map(svc);

    uint16_t pid_list[256];
    size_t pid_count = 0;

    uint16_t pcr_pid = PMT_GET_PCR(svc->pmt);
    bool pcr_auto = false;
    if(pcr_pid == 0 || pcr_pid >= NULL_TS_PID)
        pcr_pid = 0;

    const uint8_t *ptr;
    PMT_ITEMS_FOREACH(svc->pmt, ptr)
    {
        const uint16_t pid = PMT_ITEM_GET_PID(svc->pmt, ptr);
        bool exists = false;
        for(size_t i = 0; i < pid_count; ++i)
        {
            if(pid_list[i] == pid)
            {
                exists = true;
                break;
            }
        }
        if(!exists && pid_count < ASC_ARRAY_SIZE(pid_list))
        {
            pid_list[pid_count++] = pid;
            if(pcr_pid == 0)
            {
                pcr_pid = pid;
                pcr_auto = true;
            }
        }
    }

    if(pcr_pid == 0 || pcr_pid >= NULL_TS_PID)
    {
        asc_log_error(SVC_MSG(svc, "не удалось определить PCR PID"));
        return false;
    }

    // добавляем PCR PID в список, если его нет
    bool has_pcr = false;
    for(size_t i = 0; i < pid_count; ++i)
    {
        if(pid_list[i] == pcr_pid)
        {
            has_pcr = true;
            break;
        }
    }
    if(!has_pcr && pid_count < ASC_ARRAY_SIZE(pid_list))
    {
        pid_list[pid_count++] = pcr_pid;
        if(!svc->pcr_not_in_es_warned)
        {
            asc_log_warning(SVC_MSG(svc, "PCR PID %d отсутствует в ES, добавлен в список"), pcr_pid);
            svc->pcr_not_in_es_warned = true;
        }
    }

    if(pcr_auto && !svc->pcr_missing_warned)
    {
        asc_log_warning(SVC_MSG(svc, "PCR PID не задан в PMT, выбран первый ES PID=%d"), pcr_pid);
        svc->pcr_missing_warned = true;
    }

    bool ok = true;

    if(mod->disable_auto_remap)
    {
        for(size_t i = 0; i < pid_count; ++i)
        {
            const uint16_t pid_in = pid_list[i];
            if(pid_in >= NULL_TS_PID || mod->pid_in_use[pid_in])
            {
                asc_log_error(SVC_MSG(svc, "PID конфликт при disable_auto_remap (PID=%d, PMT=%d)"),
                              pid_in, svc->pmt_pid_in);
                ok = false;
                break;
            }
            svc->pid_map[pid_in] = pid_in;
            reserve_pid(mod, pid_in);
        }

        if(ok)
        {
            if(svc->pmt_pid_in >= NULL_TS_PID || mod->pid_in_use[svc->pmt_pid_in])
            {
                asc_log_error(SVC_MSG(svc, "PMT PID конфликт при disable_auto_remap (PID=%d, PNR=%d)"),
                              svc->pmt_pid_in, svc->pnr_in);
                ok = false;
            }
            else
            {
                svc->pmt_pid_out = svc->pmt_pid_in;
                reserve_pid(mod, svc->pmt_pid_out);
            }
        }
    }
    else
    {
        for(size_t i = 0; i < pid_count; ++i)
        {
            const uint16_t pid_in = pid_list[i];
            const uint16_t pid_out = alloc_pid(mod);
            if(pid_out == PID_DROP)
            {
                asc_log_error(SVC_MSG(svc, "нет свободных PID для ремапа"));
                ok = false;
                break;
            }
            svc->pid_map[pid_in] = pid_out;
        }
        if(ok)
        {
            const uint16_t pmt_pid_out = alloc_pid(mod);
            if(pmt_pid_out == PID_DROP)
            {
                asc_log_error(SVC_MSG(svc, "нет свободных PID для PMT"));
                ok = false;
            }
            else
            {
                svc->pmt_pid_out = pmt_pid_out;
            }
        }
    }

    if(!ok)
    {
        service_release_map(svc);
        return false;
    }

    svc->pcr_pid_in = pcr_pid;
    svc->pcr_pid_out = svc->pid_map[pcr_pid];
    svc->mapping_ready = true;
    return true;
}

static void service_build_pmt(mpts_service_t *svc)
{
    if(!svc->mapping_ready || !svc->pmt || svc->pmt->buffer_size == 0)
        return;

    memcpy(svc->pmt_out->buffer, svc->pmt->buffer, svc->pmt->buffer_size);
    svc->pmt_out->buffer_size = svc->pmt->buffer_size;
    svc->pmt_out->pid = svc->pmt_pid_out;

    PMT_SET_PNR(svc->pmt_out, svc->pnr_out);
    PMT_SET_VERSION(svc->pmt_out, svc->pmt_version);
    PMT_SET_PCR(svc->pmt_out, svc->pcr_pid_out);

    const uint8_t *ptr_in;
    uint8_t *ptr_out;
    for(ptr_in = PMT_ITEMS_FIRST(svc->pmt), ptr_out = PMT_ITEMS_FIRST(svc->pmt_out)
        ; !PMT_ITEMS_EOL(svc->pmt, ptr_in)
        ; PMT_ITEMS_NEXT(svc->pmt, ptr_in), PMT_ITEMS_NEXT(svc->pmt_out, ptr_out))
    {
        const uint16_t pid_in = PMT_ITEM_GET_PID(svc->pmt, ptr_in);
        const uint16_t pid_out = svc->pid_map[pid_in];
        if(pid_out != PID_DROP)
            PMT_ITEM_SET_PID(svc->pmt_out, ptr_out, pid_out);
    }

    PSI_SET_CRC32(svc->pmt_out);
}

static uint16_t append_descriptor(uint8_t *buf, uint16_t offset, uint8_t tag, const uint8_t *payload, uint8_t len)
{
    buf[offset++] = tag;
    buf[offset++] = len;
    if(len > 0)
    {
        memcpy(&buf[offset], payload, len);
        offset += len;
    }
    return offset;
}

static bool is_delivery_cable(const char *value)
{
    if(!value || value[0] == '\0') return false;
    if(!strcasecmp(value, "cable")) return true;
    if(!strcasecmp(value, "dvb-c")) return true;
    if(!strcasecmp(value, "dvb_c")) return true;
    return false;
}

static uint8_t parse_modulation(const char *value)
{
    if(!value) return 0;
    if(!strcasecmp(value, "16qam")) return 0x01;
    if(!strcasecmp(value, "32qam")) return 0x02;
    if(!strcasecmp(value, "64qam")) return 0x03;
    if(!strcasecmp(value, "128qam")) return 0x04;
    if(!strcasecmp(value, "256qam")) return 0x05;
    return 0;
}

static uint8_t parse_fec_inner(const char *value)
{
    if(!value || value[0] == '\0') return 0x0F; // auto/undefined
    if(!strcmp(value, "1/2")) return 0x01;
    if(!strcmp(value, "2/3")) return 0x02;
    if(!strcmp(value, "3/4")) return 0x03;
    if(!strcmp(value, "5/6")) return 0x04;
    if(!strcmp(value, "7/8")) return 0x05;
    return 0x0F;
}

static void parse_lcn_descriptor_tags(module_data_t *mod, const char *value)
{
    if(!mod || !value || value[0] == '\0')
        return;

    char *dup = strdup(value);
    if(!dup)
        return;

    char *saveptr = NULL;
    for(char *token = strtok_r(dup, ",", &saveptr); token; token = strtok_r(NULL, ",", &saveptr))
    {
        while(*token == ' ' || *token == '\t')
            token++;
        if(*token == '\0')
            continue;

        char *endptr = NULL;
        long tag = strtol(token, &endptr, 0);
        if(endptr == token || tag <= 0 || tag > 255)
        {
            asc_log_warning(MSG("lcn_descriptor_tags содержит неверное значение: %s"), token);
            continue;
        }

        bool exists = false;
        for(uint8_t i = 0; i < mod->lcn_descriptor_tags_count; ++i)
        {
            if(mod->lcn_descriptor_tags[i] == (uint8_t)tag)
            {
                exists = true;
                break;
            }
        }
        if(exists)
            continue;

        if(mod->lcn_descriptor_tags_count >= MPTS_MAX_LCN_TAGS)
        {
            asc_log_warning(MSG("lcn_descriptor_tags: превышен лимит %d, остальные теги игнорируются"),
                            MPTS_MAX_LCN_TAGS);
            break;
        }
        mod->lcn_descriptor_tags[mod->lcn_descriptor_tags_count++] = (uint8_t)tag;
    }

    free(dup);
}

static bool is_utf8_codepage(const char *value)
{
    if(!value || value[0] == '\0') return false;
    if(!strcasecmp(value, "utf-8")) return true;
    if(!strcasecmp(value, "utf8")) return true;
    return false;
}

static size_t write_encoded_text(uint8_t *dst, size_t max_len, const char *text,
                                 size_t raw_len, bool use_utf8)
{
    if(!dst || !text || max_len == 0 || raw_len == 0)
        return 0;

    size_t pos = 0;
    if(use_utf8)
    {
        // DVB UTF-8 marker (ETSI EN 300 468)
        dst[pos++] = 0x15;
        if(pos >= max_len)
            return pos;
    }

    if(raw_len > max_len - pos)
        raw_len = max_len - pos;
    memcpy(&dst[pos], text, raw_len);
    return pos + raw_len;
}

static void build_pat(module_data_t *mod)
{
    PAT_INIT(mod->pat_out, mod->tsid, mod->pat_version);

    asc_list_for(mod->services)
    {
        mpts_service_t *svc = (mpts_service_t *)asc_list_data(mod->services);
        if(!svc->ready || !svc->mapping_ready || !svc->pmt_pid_out || svc->pnr_out == 0)
            continue;
        PAT_ITEMS_APPEND(mod->pat_out, svc->pnr_out, svc->pmt_pid_out);
    }

    PSI_SET_CRC32(mod->pat_out);
}

static void build_cat(module_data_t *mod)
{
    uint8_t *buf = mod->cat_out->buffer;
    buf[0] = 0x01; // CAT
    buf[1] = 0x80 | 0x30; // section_syntax_indicator + reserved
    buf[2] = 0x00; // section_length (set later)
    buf[3] = 0xFF; // reserved
    buf[4] = 0xFF; // reserved
    buf[5] = 0x01; // current_next_indicator
    CAT_SET_VERSION(mod->cat_out, mod->cat_version);
    buf[6] = 0x00; // section_number
    buf[7] = 0x00; // last_section_number
    mod->cat_out->buffer_size = 8 + CRC32_SIZE;
    PSI_SET_SIZE(mod->cat_out);
    PSI_SET_CRC32(mod->cat_out);
}

static void build_sdt(module_data_t *mod)
{
    uint8_t *buf = mod->sdt_out->buffer;
    uint16_t pos = 0;
    const bool use_utf8 = is_utf8_codepage(mod->codepage);

    buf[pos++] = 0x42; // SDT Actual
    buf[pos++] = 0x80 | 0x30; // section_syntax_indicator + reserved
    buf[pos++] = 0x00; // section_length (set later)
    buf[pos++] = (uint8_t)(mod->tsid >> 8);
    buf[pos++] = (uint8_t)(mod->tsid & 0xFF);
    buf[pos++] = 0xC0 | ((mod->sdt_version << 1) & 0x3E) | 0x01;
    buf[pos++] = 0x00; // section_number
    buf[pos++] = 0x00; // last_section_number
    buf[pos++] = (uint8_t)(mod->onid >> 8);
    buf[pos++] = (uint8_t)(mod->onid & 0xFF);
    buf[pos++] = 0xFF; // reserved

    asc_list_for(mod->services)
    {
        mpts_service_t *svc = (mpts_service_t *)asc_list_data(mod->services);
        if(!svc->ready || !svc->mapping_ready || svc->pnr_out == 0)
            continue;

        const char *provider = svc->service_provider ? svc->service_provider : mod->provider_name;
        const char *service_name = svc->service_name ? svc->service_name : "";
        if(!provider) provider = "";

        size_t provider_raw_len = strlen(provider);
        size_t service_raw_len = strlen(service_name);
        const size_t max_raw = use_utf8 ? 254 : 255;
        if(provider_raw_len > max_raw) provider_raw_len = max_raw;
        if(service_raw_len > max_raw) service_raw_len = max_raw;

        size_t provider_len = provider_raw_len + ((use_utf8 && provider_raw_len > 0) ? 1 : 0);
        size_t service_len = service_raw_len + ((use_utf8 && service_raw_len > 0) ? 1 : 0);

        if(3 + provider_len + 1 + service_len > 255)
        {
            size_t max_service_len = (255 > (4 + provider_len)) ? (255 - 4 - provider_len) : 0;
            if(service_len > max_service_len)
            {
                if(use_utf8)
                {
                    if(max_service_len <= 1)
                    {
                        service_raw_len = 0;
                        service_len = 0;
                    }
                    else
                    {
                        service_raw_len = max_service_len - 1;
                        service_len = service_raw_len + 1;
                    }
                }
                else
                {
                    service_raw_len = max_service_len;
                    service_len = service_raw_len;
                }
            }
        }

        uint8_t desc[512];
        uint16_t desc_len = 0;
        desc[desc_len++] = 0x48; // service_descriptor
        desc[desc_len++] = (uint8_t)(3 + provider_len + 1 + service_len);
        desc[desc_len++] = (uint8_t)(svc->has_service_type_id ? svc->service_type_id : 1);
        desc[desc_len++] = (uint8_t)provider_len;
        desc_len += (uint16_t)write_encoded_text(&desc[desc_len], sizeof(desc) - desc_len,
                                                 provider, provider_raw_len, use_utf8);
        desc[desc_len++] = (uint8_t)service_len;
        desc_len += (uint16_t)write_encoded_text(&desc[desc_len], sizeof(desc) - desc_len,
                                                 service_name, service_raw_len, use_utf8);

        buf[pos++] = (uint8_t)(svc->pnr_out >> 8);
        buf[pos++] = (uint8_t)(svc->pnr_out & 0xFF);
        buf[pos++] = 0xFC; // EIT flags disabled
        buf[pos++] = (uint8_t)(((4 << 5) | ((svc->scrambled ? 1 : 0) << 4)) | ((desc_len >> 8) & 0x0F));
        buf[pos++] = (uint8_t)(desc_len & 0xFF);
        memcpy(&buf[pos], desc, desc_len);
        pos += desc_len;
    }

    mod->sdt_out->buffer_size = pos + CRC32_SIZE;
    PSI_SET_SIZE(mod->sdt_out);
    PSI_SET_CRC32(mod->sdt_out);
}

static void build_nit(module_data_t *mod)
{
    uint8_t *buf = mod->nit_out->buffer;
    uint16_t pos = 0;

    buf[pos++] = 0x40; // NIT Actual
    buf[pos++] = 0x80 | 0x30;
    buf[pos++] = 0x00; // section_length
    buf[pos++] = (uint8_t)(mod->network_id >> 8);
    buf[pos++] = (uint8_t)(mod->network_id & 0xFF);
    buf[pos++] = 0xC0 | ((mod->nit_version << 1) & 0x3E) | 0x01;
    buf[pos++] = 0x00; // section_number
    buf[pos++] = 0x00; // last_section_number

    const uint16_t network_desc_len_pos = pos;
    buf[pos++] = 0xF0;
    buf[pos++] = 0x00;

    uint16_t network_desc_start = pos;
    if(mod->network_name && mod->network_name[0] != '\0')
    {
        const bool use_utf8 = is_utf8_codepage(mod->codepage);
        size_t raw_len = strlen(mod->network_name);
        const size_t max_raw = use_utf8 ? 254 : 255;
        if(raw_len > max_raw) raw_len = max_raw;

        uint8_t tmp[256];
        const size_t out_len = write_encoded_text(tmp, sizeof(tmp), mod->network_name, raw_len, use_utf8);
        if(out_len > 0)
            pos = append_descriptor(buf, pos, 0x40, tmp, (uint8_t)out_len);
    }
    uint16_t network_desc_len = pos - network_desc_start;
    buf[network_desc_len_pos] = 0xF0 | ((network_desc_len >> 8) & 0x0F);
    buf[network_desc_len_pos + 1] = (uint8_t)(network_desc_len & 0xFF);

    const uint16_t ts_loop_len_pos = pos;
    buf[pos++] = 0xF0;
    buf[pos++] = 0x00;
    uint16_t ts_loop_start = pos;

    // Основной TS
    uint16_t desc_len_pos = pos + 4;
    buf[pos++] = (uint8_t)(mod->tsid >> 8);
    buf[pos++] = (uint8_t)(mod->tsid & 0xFF);
    buf[pos++] = (uint8_t)(mod->onid >> 8);
    buf[pos++] = (uint8_t)(mod->onid & 0xFF);
    buf[pos++] = 0xF0;
    buf[pos++] = 0x00;

    uint16_t desc_start = pos;
    // service_list_descriptor
    {
        uint8_t tmp[1024];
        uint16_t tmp_len = 0;
        asc_list_for(mod->services)
        {
            mpts_service_t *svc = (mpts_service_t *)asc_list_data(mod->services);
            if(!svc->ready || !svc->mapping_ready || svc->pnr_out == 0)
                continue;
            tmp[tmp_len++] = (uint8_t)(svc->pnr_out >> 8);
            tmp[tmp_len++] = (uint8_t)(svc->pnr_out & 0xFF);
            tmp[tmp_len++] = (uint8_t)(svc->has_service_type_id ? svc->service_type_id : 1);
        }
        if(tmp_len > 0)
        {
            if(tmp_len > 255)
                tmp_len = (uint16_t)((255 / 3) * 3);
            pos = append_descriptor(buf, pos, 0x41, tmp, (uint8_t)tmp_len);
        }
    }

    // logical_channel_descriptor (LCN) - NorDig (0x83) или совместимые варианты.
    {
        uint8_t tmp[1024];
        uint16_t tmp_len = 0;
        asc_list_for(mod->services)
        {
            mpts_service_t *svc = (mpts_service_t *)asc_list_data(mod->services);
            if(!svc->ready || !svc->mapping_ready || svc->pnr_out == 0 || !svc->has_lcn)
                continue;
            if(svc->lcn == 0 || svc->lcn > 1023)
                continue;
            if(tmp_len + 4 > sizeof(tmp))
                break;
            tmp[tmp_len++] = (uint8_t)(svc->pnr_out >> 8);
            tmp[tmp_len++] = (uint8_t)(svc->pnr_out & 0xFF);
            tmp[tmp_len++] = (uint8_t)(0xFC | ((svc->lcn >> 8) & 0x03)); // visible=1 + reserved=1
            tmp[tmp_len++] = (uint8_t)(svc->lcn & 0xFF);
        }
        if(tmp_len > 0)
        {
            if(tmp_len > 255)
                tmp_len = (uint16_t)((255 / 4) * 4);
            if(mod->lcn_descriptor_tags_count > 0)
            {
                for(uint8_t i = 0; i < mod->lcn_descriptor_tags_count; ++i)
                {
                    const uint8_t tag = mod->lcn_descriptor_tags[i];
                    pos = append_descriptor(buf, pos, tag, tmp, (uint8_t)tmp_len);
                }
            }
            else
            {
                const uint8_t tag = mod->lcn_descriptor_tag ? mod->lcn_descriptor_tag : 0x83;
                pos = append_descriptor(buf, pos, tag, tmp, (uint8_t)tmp_len);
            }
        }
    }

    // cable_delivery_system_descriptor
    if(is_delivery_cable(mod->delivery))
    {
        uint8_t desc[11];
        memset(desc, 0, sizeof(desc));

        const uint32_t freq_digits = mod->frequency_khz > 0 ? (mod->frequency_khz * 10) : 0;
        write_bcd(desc, 8, freq_digits);

        desc[4] = 0xFF;
        desc[5] = 0xF0 | 0x02; // FEC_outer: RS(204/188)
        desc[6] = parse_modulation(mod->modulation);

        const uint32_t sr_digits = mod->symbolrate_ksps > 0 ? (mod->symbolrate_ksps * 10) : 0;
        write_bcd(&desc[7], 7, sr_digits);
        desc[10] = (desc[10] & 0xF0) | parse_fec_inner(mod->fec);

        pos = append_descriptor(buf, pos, 0x44, desc, sizeof(desc));
    }

    uint16_t desc_len = pos - desc_start;
    buf[desc_len_pos] = 0xF0 | ((desc_len >> 8) & 0x0F);
    buf[desc_len_pos + 1] = (uint8_t)(desc_len & 0xFF);

    // Дополнительные TS из network_search (формат: tsid[:onid])
    if(mod->network_search && mod->network_search[0] != '\0')
    {
        char *list = strdup(mod->network_search);
        char *saveptr = NULL;
        for(char *token = strtok_r(list, ",", &saveptr); token; token = strtok_r(NULL, ",", &saveptr))
        {
            while(*token == ' ') token++;
            if(*token == '\0') continue;
            char *sep = strchr(token, ':');
            uint16_t tsid = 0;
            uint16_t onid = mod->onid;
            if(sep)
            {
                *sep = '\0';
                tsid = (uint16_t)atoi(token);
                onid = (uint16_t)atoi(sep + 1);
            }
            else
            {
                tsid = (uint16_t)atoi(token);
            }
            if(tsid == 0)
                continue;
            buf[pos++] = (uint8_t)(tsid >> 8);
            buf[pos++] = (uint8_t)(tsid & 0xFF);
            buf[pos++] = (uint8_t)(onid >> 8);
            buf[pos++] = (uint8_t)(onid & 0xFF);
            buf[pos++] = 0xF0;
            buf[pos++] = 0x00; // descriptors length
        }
        free(list);
    }

    uint16_t ts_loop_len = pos - ts_loop_start;
    buf[ts_loop_len_pos] = 0xF0 | ((ts_loop_len >> 8) & 0x0F);
    buf[ts_loop_len_pos + 1] = (uint8_t)(ts_loop_len & 0xFF);

    mod->nit_out->buffer_size = pos + CRC32_SIZE;
    PSI_SET_SIZE(mod->nit_out);
    PSI_SET_CRC32(mod->nit_out);
}

static void build_tdt(module_data_t *mod)
{
    uint8_t *buf = mod->tdt_out->buffer;
    buf[0] = 0x70; // TDT
    buf[1] = 0x30; // section_syntax_indicator=0
    buf[2] = 0x05; // 5 bytes UTC time
    write_utc_time(&buf[3]);
    mod->tdt_out->buffer_size = 3 + 5;
}

static void build_tot(module_data_t *mod)
{
    uint8_t *buf = mod->tot_out->buffer;
    uint16_t pos = 0;

    buf[pos++] = 0x73; // TOT
    buf[pos++] = 0x30;
    buf[pos++] = 0x00; // section_length

    write_utc_time(&buf[pos]);
    pos += 5;

    uint16_t desc_len_pos = pos;
    buf[pos++] = 0xF0;
    buf[pos++] = 0x00;

    uint16_t desc_start = pos;
    if(mod->country && mod->country[0] != '\0')
    {
        const int offset_minutes = mod->utc_offset * 60;
        const int abs_minutes = offset_minutes >= 0 ? offset_minutes : -offset_minutes;
        const uint8_t offset_h = (uint8_t)(abs_minutes / 60);
        const uint8_t offset_m = (uint8_t)(abs_minutes % 60);

        uint8_t desc[13];
        memset(desc, 0, sizeof(desc));
        desc[0] = (uint8_t)(mod->country[0] ? mod->country[0] : 'X');
        desc[1] = (uint8_t)(mod->country[1] ? mod->country[1] : 'X');
        desc[2] = (uint8_t)(mod->country[2] ? mod->country[2] : 'X');
        desc[3] = (uint8_t)(0x02 | ((offset_minutes < 0) ? 0x01 : 0x00));
        desc[4] = to_bcd(offset_h);
        desc[5] = to_bcd(offset_m);

        // time_of_change: текущее время (без DST логики)
        write_utc_time(&desc[6]);
        desc[11] = desc[4];
        desc[12] = desc[5];

        pos = append_descriptor(buf, pos, 0x58, desc, sizeof(desc));
    }

    uint16_t desc_len = pos - desc_start;
    buf[desc_len_pos] = 0xF0 | ((desc_len >> 8) & 0x0F);
    buf[desc_len_pos + 1] = (uint8_t)(desc_len & 0xFF);

    mod->tot_out->buffer_size = pos + CRC32_SIZE;
    PSI_SET_SIZE(mod->tot_out);
    PSI_SET_CRC32(mod->tot_out);
}

static void rebuild_tables(module_data_t *mod)
{
    if(!mod->psi_dirty && mod->psi_built)
        return;

    if(mod->psi_built)
    {
        if(!mod->pat_version_fixed)
            mod->pat_version = (mod->pat_version + 1) & 0x1F;
        if(!mod->cat_version_fixed)
            mod->cat_version = (mod->cat_version + 1) & 0x1F;
        if(!mod->nit_version_fixed)
            mod->nit_version = (mod->nit_version + 1) & 0x1F;
        if(!mod->sdt_version_fixed)
            mod->sdt_version = (mod->sdt_version + 1) & 0x1F;
    }

    bool pnr_used[MPTS_PNR_MAX + 1];
    memset(pnr_used, 0, sizeof(pnr_used));

    // Первый проход: назначаем явные PNR или входные, если не конфликтуют
    asc_list_for(mod->services)
    {
        mpts_service_t *svc = (mpts_service_t *)asc_list_data(mod->services);
        if(!svc->ready || !svc->mapping_ready)
            continue;

        uint16_t requested_pnr = 0;
        if(svc->has_pnr)
            requested_pnr = svc->pnr_cfg;
        else if(svc->pnr_in > 0)
            requested_pnr = svc->pnr_in;

        if(requested_pnr > 0 && requested_pnr <= MPTS_PNR_MAX && !pnr_used[requested_pnr])
        {
            svc->pnr_out = requested_pnr;
            pnr_used[requested_pnr] = true;
        }
        else
        {
            svc->pnr_out = 0;
        }
    }

    // Второй проход: авто-назначение PNR
    uint16_t next_pnr = 1;
    asc_list_for(mod->services)
    {
        mpts_service_t *svc = (mpts_service_t *)asc_list_data(mod->services);
        if(!svc->ready || !svc->mapping_ready)
            continue;
        if(svc->pnr_out != 0)
            continue;

        while(next_pnr <= MPTS_PNR_MAX && pnr_used[next_pnr])
            next_pnr++;
        if(next_pnr > MPTS_PNR_MAX)
            break;
        svc->pnr_out = next_pnr;
        pnr_used[next_pnr] = true;
        next_pnr++;

        // Если был задан PNR (явно или из входа), а мы назначили новый — логируем.
        if((svc->has_pnr || svc->pnr_in > 0) && !svc->pnr_conflict_warned)
        {
            const uint16_t requested_pnr = svc->has_pnr ? svc->pnr_cfg : svc->pnr_in;
            if(requested_pnr > MPTS_PNR_MAX)
                asc_log_warning(SVC_MSG(svc, "PNR вне диапазона (PNR=%d), назначен %d"),
                                requested_pnr, svc->pnr_out);
            else
                asc_log_warning(SVC_MSG(svc, "PNR %d уже используется, назначен %d"),
                                requested_pnr, svc->pnr_out);
            svc->pnr_conflict_warned = true;
        }
    }

    build_pat(mod);
    build_cat(mod);
    build_sdt(mod);
    build_nit(mod);
    build_tdt(mod);
    build_tot(mod);

    asc_list_for(mod->services)
    {
        mpts_service_t *svc = (mpts_service_t *)asc_list_data(mod->services);
        if(!svc->ready || !svc->mapping_ready)
            continue;
        service_build_pmt(svc);
    }

    mod->psi_dirty = false;
    mod->psi_built = true;
}

static void on_si_timer(void *arg)
{
    module_data_t *mod = (module_data_t *)arg;
    const uint64_t now = asc_utime();
    if(mod->last_si_us != 0)
    {
        const uint64_t delta = now - mod->last_si_us;
        mod->psi_interval_actual_ms = (uint32_t)((delta + 500) / 1000);
    }
    mod->last_si_us = now;

    if(mod->pass_eit && !mod->eit_source && !mod->eit_source_warned)
    {
        asc_log_warning(MSG("pass_eit включён, но eit_source не найден"));
        mod->eit_source_warned = true;
    }
    if(mod->pass_cat && !mod->cat_source && !mod->cat_source_warned)
    {
        asc_log_warning(MSG("pass_cat включён, но cat_source не найден"));
        mod->cat_source_warned = true;
    }

    rebuild_tables(mod);

    if(mod->pat_out)
        mpegts_psi_demux(mod->pat_out, mpts_send_psi, mod);
    if(mod->cat_out && !mod->pass_cat)
        mpegts_psi_demux(mod->cat_out, mpts_send_psi, mod);

    asc_list_for(mod->services)
    {
        mpts_service_t *svc = (mpts_service_t *)asc_list_data(mod->services);
        if(svc->ready && svc->mapping_ready)
            mpegts_psi_demux(svc->pmt_out, mpts_send_psi, mod);
    }

    if(!mod->pass_sdt || mod->service_count != 1)
        mpegts_psi_demux(mod->sdt_out, mpts_send_psi, mod);

    if(!mod->pass_nit || mod->service_count != 1)
        mpegts_psi_demux(mod->nit_out, mpts_send_psi, mod);

    if(!mod->pass_tdt || mod->service_count != 1)
    {
        build_tdt(mod);
        mpegts_psi_demux(mod->tdt_out, mpts_send_psi, mod);
        if(mod->country && mod->country[0] != '\0')
        {
            build_tot(mod);
            mpegts_psi_demux(mod->tot_out, mpts_send_psi, mod);
        }
    }
}

static void on_cbr_timer(void *arg)
{
    module_data_t *mod = (module_data_t *)arg;
    if(mod->target_bitrate <= 0)
        return;

    const uint64_t now = asc_utime();
    if(mod->cbr_start_us == 0)
    {
        mod->cbr_start_us = now;
        mod->sent_packets = 0;
        return;
    }

    const uint64_t elapsed = now - mod->cbr_start_us;
    const uint64_t expected_packets = (uint64_t)mod->target_bitrate * elapsed / (TS_PACKET_SIZE * 8 * 1000000ULL);
    if(expected_packets > mod->sent_packets)
    {
        uint64_t diff = expected_packets - mod->sent_packets;
        if(diff > 2000)
            diff = 2000; // ограничение за один тик
        mpts_send_null(mod, (size_t)diff);
    }
    else if(elapsed > 1000000ULL)
    {
        // Если входной битрейт превышает target_bitrate, предупреждаем раз в 5 секунд.
        const uint64_t actual_bitrate = mod->sent_packets * (uint64_t)TS_PACKET_SIZE * 8ULL * 1000000ULL / elapsed;
        const uint64_t warn_threshold = (uint64_t)mod->target_bitrate * 105ULL / 100ULL;
        if(actual_bitrate > warn_threshold && (now - mod->cbr_last_warn_us) > 5000000ULL)
        {
            asc_log_warning(MSG("target_bitrate %d ниже входного (%llu), CBR не выдерживается"),
                            mod->target_bitrate, (unsigned long long)actual_bitrate);
            mod->cbr_last_warn_us = now;
        }
    }
}

static void on_eit(void *arg, mpegts_psi_t *psi)
{
    module_data_t *mod = (module_data_t *)arg;
    if(!psi || psi->buffer_size < 16)
        return;

    const uint8_t table_id = psi->buffer[0];
    if(table_id < 0x4E || table_id > 0x6F)
        return;
    if(table_id == 0x4F || table_id >= 0x60)
        return; // только EIT Actual

    const uint16_t pnr_in = EIT_GET_PNR(psi);
    mpts_service_t *svc = find_service_by_pnr_in(mod, pnr_in);
    if(!svc || !svc->ready || !svc->mapping_ready || svc->pnr_out == 0)
        return;

    // Переписываем идентификаторы под выходной MPTS.
    EIT_SET_PNR(psi, svc->pnr_out);
    psi->buffer[8] = (uint8_t)(mod->tsid >> 8);
    psi->buffer[9] = (uint8_t)(mod->tsid & 0xFF);
    psi->buffer[10] = (uint8_t)(mod->onid >> 8);
    psi->buffer[11] = (uint8_t)(mod->onid & 0xFF);

    PSI_SET_CRC32(psi);
    psi->crc32 = PSI_GET_CRC32(psi);

    mpegts_psi_demux(psi, mpts_send_psi, mod);
}

static void on_pat(void *arg, mpegts_psi_t *psi)
{
    mpts_service_t *svc = (mpts_service_t *)arg;
    module_data_t *mod = svc->mod;

    if(psi->buffer[0] != 0x00)
        return;

    const uint32_t crc32 = PSI_GET_CRC32(psi);
    if(crc32 != PSI_CALC_CRC32(psi))
        return;

    if(crc32 == psi->crc32)
        return;

    psi->crc32 = crc32;

    const uint8_t *pointer;
    uint16_t selected_pnr = 0;
    uint16_t selected_pid = 0;
    uint16_t program_count = 0;
    bool selected_found = false;

    PAT_ITEMS_FOREACH(psi, pointer)
    {
        const uint16_t pnr = PAT_ITEM_GET_PNR(psi, pointer);
        const uint16_t pid = PAT_ITEM_GET_PID(psi, pointer);
        if(pnr == 0)
            continue;

        ++program_count;

        if(svc->has_pnr)
        {
            if(pnr == svc->pnr_cfg && !selected_found)
            {
                selected_pnr = pnr;
                selected_pid = pid;
                selected_found = true;
            }
        }
        else if(!selected_found)
        {
            selected_pnr = pnr;
            selected_pid = pid;
            selected_found = true;
        }
    }

    if(program_count > 1 && mod->spts_only)
    {
        if(!svc->spts_only_warned)
        {
            asc_log_error(SVC_MSG(svc, "PAT содержит %d программ, но spts_only=true; "
                "вход отклонён"), program_count);
            svc->spts_only_warned = true;
        }
        return;
    }

    if(selected_pid == 0)
    {
        asc_log_warning(SVC_MSG(svc, "PAT не содержит выбранной программы"));
        return;
    }

    if(!svc->has_pnr && program_count > 1)
    {
        if(mod->strict_pnr)
        {
            if(!svc->pnr_missing_warned)
            {
                asc_log_error(SVC_MSG(svc, "PAT содержит %d программ, но pnr не задан. "
                    "strict_pnr=true -> поток отклонён"), program_count);
                svc->pnr_missing_warned = true;
            }
            return;
        }
        if(!svc->pnr_missing_warned)
        {
            asc_log_warning(SVC_MSG(svc, "PAT содержит %d программ, выбран первый (PNR=%d). "
                "Рекомендуется явно задать pnr"), program_count, selected_pnr);
            svc->pnr_missing_warned = true;
        }
    }

    if(svc->has_pnr && selected_pnr != svc->pnr_cfg)
    {
        asc_log_warning(SVC_MSG(svc, "PNR %d не найден в PAT, использую %d"),
                        svc->pnr_cfg, selected_pnr);
    }

    svc->pnr_in = selected_pnr;
    svc->pmt_pid_in = selected_pid;
    svc->pmt->pid = selected_pid;
    svc->pmt->crc32 = 0;
    mod->psi_dirty = true;
}

static void on_pmt(void *arg, mpegts_psi_t *psi)
{
    mpts_service_t *svc = (mpts_service_t *)arg;
    module_data_t *mod = svc->mod;

    if(psi->buffer[0] != 0x02)
        return;

    const uint32_t crc32 = PSI_GET_CRC32(psi);
    if(crc32 != PSI_CALC_CRC32(psi))
        return;

    if(crc32 == svc->pmt_crc)
        return;

    svc->pmt_crc = crc32;
    svc->pcr_missing_warned = false;
    svc->pcr_not_in_es_warned = false;

    if(!service_map_pids(svc))
    {
        svc->ready = false;
        return;
    }

    svc->ready = true;
    svc->pmt_version = (uint8_t)((svc->pmt_version + 1) & 0x1F);
    mod->psi_dirty = true;
}

static void input_on_ts(module_data_t *arg, const uint8_t *ts)
{
    mpts_input_t *input = (mpts_input_t *)arg;
    mpts_service_t *svc = input->service;
    module_data_t *mod = svc->mod;

    if(!TS_IS_SYNC(ts))
        return;

    const uint16_t pid = TS_GET_PID(ts);

    if(pid == 0x0000)
    {
        mpegts_psi_mux(svc->pat, ts, on_pat, svc);
        return;
    }

    if(svc->pmt_pid_in && pid == svc->pmt_pid_in)
    {
        mpegts_psi_mux(svc->pmt, ts, on_pmt, svc);
        return;
    }

    const bool allow_pass = (mod->service_count == 1);
    if(pid == 0x0010 && mod->pass_nit && allow_pass)
    {
        mpts_send_ts(mod, ts);
        return;
    }
    if(pid == 0x0011 && mod->pass_sdt && allow_pass)
    {
        mpts_send_ts(mod, ts);
        return;
    }
    if(pid == 0x0012)
    {
        if(mod->pass_eit && mod->eit_source == svc && mod->eit_in)
            mpegts_psi_mux(mod->eit_in, ts, on_eit, mod);
        return;
    }
    if(pid == 0x0014 && mod->pass_tdt && allow_pass)
    {
        mpts_send_ts(mod, ts);
        return;
    }
    if(pid == 0x0001)
    {
        if(mod->pass_cat && mod->cat_source == svc)
            mpts_send_ts(mod, ts);
        return;
    }

    if(pid == 0x0001 || pid == 0x0010 || pid == 0x0011 || pid == 0x0012 || pid == 0x0014)
        return;

    if(!svc->mapping_ready)
        return;

    const uint16_t mapped = svc->pid_map[pid];
    if(mapped == PID_DROP || mapped >= NULL_TS_PID)
        return;

    uint8_t out[TS_PACKET_SIZE];
    memcpy(out, ts, TS_PACKET_SIZE);
    TS_SET_PID(out, mapped);
    if(mod->pcr_restamp && pid == svc->pcr_pid_in && TS_IS_PCR(out))
    {
        // PCR restamp: выравниваем по локальному времени выхода.
        const uint64_t now = asc_utime();
        if(mod->pcr_restamp_start_us == 0)
            mod->pcr_restamp_start_us = now;
        const uint64_t elapsed = now - mod->pcr_restamp_start_us;
        const uint64_t target = (elapsed * 27ULL) % PCR_MAX_TICKS;
        if(mod->pcr_smoothing)
        {
            const uint64_t in_pcr = TS_GET_PCR(out);
            const int64_t diff = pcr_diff(target, in_pcr);
            if(!svc->pcr_smooth_ready)
            {
                svc->pcr_smooth_offset = (double)diff;
                svc->pcr_smooth_ready = true;
            }
            else
            {
                svc->pcr_smooth_offset += mod->pcr_smooth_alpha * ((double)diff - svc->pcr_smooth_offset);
            }
            if(mod->pcr_smooth_max_offset_ticks > 0)
            {
                const double limit = (double)mod->pcr_smooth_max_offset_ticks;
                if(svc->pcr_smooth_offset > limit)
                    svc->pcr_smooth_offset = limit;
                else if(svc->pcr_smooth_offset < -limit)
                    svc->pcr_smooth_offset = -limit;
            }
            int64_t out_pcr = (int64_t)in_pcr + (int64_t)svc->pcr_smooth_offset;
            if(out_pcr < 0)
                out_pcr += (int64_t)PCR_MAX_TICKS;
            else if(out_pcr >= (int64_t)PCR_MAX_TICKS)
                out_pcr %= (int64_t)PCR_MAX_TICKS;
            TS_SET_PCR(out, (uint64_t)out_pcr);
        }
        else
        {
            TS_SET_PCR(out, target);
        }
    }
    mpts_send_ts(mod, out);
}

static int method_add_input(module_data_t *mod)
{
    if(lua_type(lua, 2) != LUA_TLIGHTUSERDATA)
        return 0;

    mpts_service_t *svc = (mpts_service_t *)calloc(1, sizeof(mpts_service_t));
    svc->mod = mod;
    svc->index = ++mod->service_count;

    for(uint32_t i = 0; i < MPTS_MAX_PIDS; ++i)
        svc->pid_map[i] = PID_DROP;

    if(lua_type(lua, 3) == LUA_TTABLE)
    {
        lua_getfield(lua, 3, "name");
        if(lua_type(lua, -1) == LUA_TSTRING)
            svc->label = strdup(lua_tostring(lua, -1));
        lua_pop(lua, 1);

        lua_getfield(lua, 3, "pnr");
        if(lua_type(lua, -1) == LUA_TNUMBER)
        {
            const int pnr = lua_tonumber(lua, -1);
            if(pnr > 0 && pnr <= MPTS_PNR_MAX)
            {
                svc->pnr_cfg = (uint16_t)pnr;
                svc->has_pnr = true;
            }
        }
        lua_pop(lua, 1);

        lua_getfield(lua, 3, "service_name");
        if(lua_type(lua, -1) == LUA_TSTRING)
            svc->service_name = strdup(lua_tostring(lua, -1));
        lua_pop(lua, 1);

        lua_getfield(lua, 3, "service_provider");
        if(lua_type(lua, -1) == LUA_TSTRING)
            svc->service_provider = strdup(lua_tostring(lua, -1));
        lua_pop(lua, 1);

        lua_getfield(lua, 3, "service_type_id");
        if(lua_type(lua, -1) == LUA_TNUMBER)
        {
            const int st = lua_tonumber(lua, -1);
            if(st >= 0 && st <= 255)
            {
                svc->service_type_id = (uint8_t)st;
                svc->has_service_type_id = true;
            }
        }
        lua_pop(lua, 1);

        lua_getfield(lua, 3, "lcn");
        if(lua_type(lua, -1) == LUA_TNUMBER)
        {
            const int lcn = lua_tonumber(lua, -1);
            if(lcn > 0 && lcn <= 1023)
            {
                svc->lcn = (uint16_t)lcn;
                svc->has_lcn = true;
            }
        }
        lua_pop(lua, 1);

        lua_getfield(lua, 3, "scrambled");
        if(lua_type(lua, -1) == LUA_TBOOLEAN)
            svc->scrambled = lua_toboolean(lua, -1);
        lua_pop(lua, 1);
    }

    svc->pat = mpegts_psi_init(MPEGTS_PACKET_PAT, 0x00);
    svc->pmt = mpegts_psi_init(MPEGTS_PACKET_PMT, MAX_PID);
    svc->pmt_out = mpegts_psi_init(MPEGTS_PACKET_PMT, MAX_PID);

    mpts_input_t *input = (mpts_input_t *)calloc(1, sizeof(mpts_input_t));
    input->service = svc;
    input->stream.self = (module_data_t *)input;
    input->stream.on_ts = input_on_ts;
    __module_stream_init(&input->stream);

    module_stream_t *upstream = (module_stream_t *)lua_touserdata(lua, 2);
    __module_stream_attach(upstream, &input->stream);

    svc->input = input;

    asc_list_insert_tail(mod->services, svc);

    if(mod->pass_eit && mod->eit_source == NULL && mod->eit_source_index == svc->index)
        mod->eit_source = svc;
    if(mod->pass_cat && mod->cat_source == NULL && mod->cat_source_index == svc->index)
        mod->cat_source = svc;

    mod->psi_dirty = true;
    if(!mod->pass_warned && mod->service_count > 1 &&
        (mod->pass_nit || mod->pass_sdt || mod->pass_tdt))
    {
        asc_log_warning(MSG("pass_nit/pass_sdt/pass_tdt корректны только для одного сервиса; используем генерацию"));
        mod->pass_warned = true;
    }

    return 0;
}

static void module_init(module_data_t *mod)
{
    module_stream_init(mod, NULL);

    mod->services = asc_list_init();
    mod->service_count = 0;
    mod->next_pid = 0x0020;
    mod->lcn_descriptor_tag = 0x83;
    mod->spts_only = true;
    mod->eit_source_index = 1;
    mod->cat_source_index = 1;
    mod->pcr_smooth_alpha = 0.1;
    mod->pcr_smooth_max_offset_ticks = 500ULL * 27000ULL;

    reserve_pid(mod, 0x0000); // PAT
    reserve_pid(mod, 0x0001); // CAT
    reserve_pid(mod, 0x0010); // NIT
    reserve_pid(mod, 0x0011); // SDT
    reserve_pid(mod, 0x0012); // EIT
    reserve_pid(mod, 0x0014); // TDT/TOT
    reserve_pid(mod, 0x1FFF); // NULL

    mod->tsid = 1;
    mod->onid = 1;
    mod->network_id = 1;
    mod->si_interval_ms = 500;

    module_option_string("name", &mod->name, NULL);

    int tmp = 0;
    if(module_option_number("tsid", &tmp)) mod->tsid = (uint16_t)tmp;
    if(module_option_number("onid", &tmp)) mod->onid = (uint16_t)tmp;
    if(module_option_number("network_id", &tmp)) mod->network_id = (uint16_t)tmp;
    module_option_string("network_name", &mod->network_name, NULL);
    module_option_string("provider_name", &mod->provider_name, NULL);
    module_option_string("codepage", &mod->codepage, NULL);
    module_option_string("country", &mod->country, NULL);
    if(module_option_number("utc_offset", &tmp)) mod->utc_offset = tmp;
    if(mod->codepage && mod->codepage[0] != '\0' && !is_utf8_codepage(mod->codepage))
        asc_log_warning(MSG("codepage %s не поддерживается; используется исходная строка"), mod->codepage);

    module_option_string("delivery", &mod->delivery, NULL);
    if(module_option_number("frequency", &tmp)) mod->frequency_khz = (uint32_t)tmp;
    if(module_option_number("symbolrate", &tmp)) mod->symbolrate_ksps = (uint32_t)tmp;
    module_option_string("modulation", &mod->modulation, NULL);
    module_option_string("fec", &mod->fec, NULL);
    module_option_string("network_search", &mod->network_search, NULL);

    if(module_option_number("si_interval_ms", &tmp))
    {
        if(tmp > 50) mod->si_interval_ms = tmp;
    }
    if(module_option_number("target_bitrate", &tmp))
        mod->target_bitrate = tmp;

    if(mod->delivery && mod->delivery[0] != '\0' && !is_delivery_cable(mod->delivery))
        asc_log_warning(MSG("delivery %s не поддерживается; генерируется только DVB-C"), mod->delivery);
    if(is_delivery_cable(mod->delivery))
    {
        if(mod->frequency_khz == 0 || mod->symbolrate_ksps == 0 || !mod->modulation || mod->modulation[0] == '\0')
        {
            asc_log_warning(MSG("DVB-C delivery требует frequency/symbolrate/modulation"));
        }
    }

    module_option_boolean("disable_auto_remap", &mod->disable_auto_remap);
    module_option_boolean("pass_nit", &mod->pass_nit);
    module_option_boolean("pass_sdt", &mod->pass_sdt);
    module_option_boolean("pass_eit", &mod->pass_eit);
    module_option_boolean("pass_tdt", &mod->pass_tdt);
    module_option_boolean("pass_cat", &mod->pass_cat);
    module_option_boolean("pcr_restamp", &mod->pcr_restamp);
    module_option_boolean("pcr_smoothing", &mod->pcr_smoothing);
    module_option_boolean("strict_pnr", &mod->strict_pnr);
    module_option_boolean("spts_only", &mod->spts_only);
    if(mod->pcr_restamp)
        asc_log_info(MSG("PCR restamp включён"));
    if(mod->pcr_smoothing && !mod->pcr_restamp)
    {
        asc_log_warning(MSG("pcr_smoothing работает только с pcr_restamp; отключаем сглаживание"));
        mod->pcr_smoothing = false;
    }

    if(module_option_number("eit_source", &tmp) && tmp > 0)
        mod->eit_source_index = tmp;
    if(module_option_number("cat_source", &tmp) && tmp > 0)
        mod->cat_source_index = tmp;
    if(module_option_number("lcn_descriptor_tag", &tmp))
    {
        if(tmp > 0 && tmp < 256)
            mod->lcn_descriptor_tag = (uint8_t)tmp;
        else
            asc_log_warning(MSG("lcn_descriptor_tag вне диапазона 1..255, игнорируем"));
    }
    const char *lcn_tags = NULL;
    if(module_option_string("lcn_descriptor_tags", &lcn_tags, NULL) && lcn_tags && lcn_tags[0] != '\0')
    {
        parse_lcn_descriptor_tags(mod, lcn_tags);
    }

    const char *alpha_str = NULL;
    if(module_option_string("pcr_smooth_alpha", &alpha_str, NULL) && alpha_str && alpha_str[0] != '\0')
    {
        double value = strtod(alpha_str, NULL);
        if(value > 0.0 && value < 1.0)
            mod->pcr_smooth_alpha = value;
        else if(value >= 1.0 && value <= 100.0)
            mod->pcr_smooth_alpha = value / 100.0;
        else
            asc_log_warning(MSG("pcr_smooth_alpha вне диапазона (0..1 или 1..100), игнорируем"));
    }
    if(module_option_number("pcr_smooth_max_offset_ms", &tmp) && tmp > 0)
        mod->pcr_smooth_max_offset_ticks = (uint64_t)tmp * 27000ULL;
    if(mod->pcr_smoothing)
    {
        asc_log_info(MSG("PCR smoothing включён (alpha=%.3f, max_offset_ms=%llu)"),
            mod->pcr_smooth_alpha,
            (unsigned long long)(mod->pcr_smooth_max_offset_ticks / 27000ULL));
    }

    if(module_option_number("pat_version", &tmp))
    {
        mod->pat_version = (uint8_t)(tmp & 0x1F);
        mod->pat_version_fixed = true;
    }
    if(module_option_number("cat_version", &tmp))
    {
        mod->cat_version = (uint8_t)(tmp & 0x1F);
        mod->cat_version_fixed = true;
    }
    if(module_option_number("nit_version", &tmp))
    {
        mod->nit_version = (uint8_t)(tmp & 0x1F);
        mod->nit_version_fixed = true;
    }
    if(module_option_number("sdt_version", &tmp))
    {
        mod->sdt_version = (uint8_t)(tmp & 0x1F);
        mod->sdt_version_fixed = true;
    }

    mod->pat_out = mpegts_psi_init(MPEGTS_PACKET_PAT, 0x0000);
    mod->cat_out = mpegts_psi_init(MPEGTS_PACKET_CAT, 0x0001);
    mod->sdt_out = mpegts_psi_init(MPEGTS_PACKET_SDT, 0x0011);
    mod->nit_out = mpegts_psi_init(MPEGTS_PACKET_NIT, 0x0010);
    mod->tdt_out = mpegts_psi_init(MPEGTS_PACKET_TDT, 0x0014);
    mod->tot_out = mpegts_psi_init(MPEGTS_PACKET_TDT, 0x0014);
    if(mod->pass_eit)
        mod->eit_in = mpegts_psi_init(MPEGTS_PACKET_EIT, 0x0012);

    mod->si_timer = asc_timer_init(mod->si_interval_ms, on_si_timer, mod);
    if(mod->target_bitrate > 0)
        mod->cbr_timer = asc_timer_init(10, on_cbr_timer, mod);
}

static int method_stats(module_data_t *mod)
{
    lua_newtable(lua);

    const uint64_t now = asc_utime();
    uint64_t bitrate = 0;
    if(mod->start_us > 0 && now > mod->start_us)
    {
        const uint64_t elapsed = now - mod->start_us;
        bitrate = mod->sent_packets * (uint64_t)TS_PACKET_SIZE * 8ULL * 1000000ULL / elapsed;
    }
    const double null_pct = (mod->sent_packets > 0)
        ? (double)mod->null_packets * 100.0 / (double)mod->sent_packets
        : 0.0;
    const uint32_t psi_ms = mod->psi_interval_actual_ms > 0
        ? mod->psi_interval_actual_ms
        : (uint32_t)mod->si_interval_ms;

    lua_pushinteger(lua, (lua_Integer)bitrate);
    lua_setfield(lua, -2, "bitrate_bps");
    lua_pushnumber(lua, null_pct);
    lua_setfield(lua, -2, "null_percent");
    lua_pushinteger(lua, (lua_Integer)psi_ms);
    lua_setfield(lua, -2, "psi_interval_ms");
    lua_pushinteger(lua, (lua_Integer)mod->sent_packets);
    lua_setfield(lua, -2, "packets_sent");
    lua_pushinteger(lua, (lua_Integer)mod->null_packets);
    lua_setfield(lua, -2, "packets_null");

    return 1;
}

static void module_destroy(module_data_t *mod)
{
    module_stream_destroy(mod);

    if(mod->si_timer)
        asc_timer_destroy(mod->si_timer);
    if(mod->cbr_timer)
        asc_timer_destroy(mod->cbr_timer);

    if(mod->pat_out) mpegts_psi_destroy(mod->pat_out);
    if(mod->cat_out) mpegts_psi_destroy(mod->cat_out);
    if(mod->sdt_out) mpegts_psi_destroy(mod->sdt_out);
    if(mod->nit_out) mpegts_psi_destroy(mod->nit_out);
    if(mod->tdt_out) mpegts_psi_destroy(mod->tdt_out);
    if(mod->tot_out) mpegts_psi_destroy(mod->tot_out);
    if(mod->eit_in) mpegts_psi_destroy(mod->eit_in);

    if(mod->services)
    {
        for(asc_list_first(mod->services); !asc_list_eol(mod->services); asc_list_first(mod->services))
        {
            mpts_service_t *svc = (mpts_service_t *)asc_list_data(mod->services);
            if(svc->input)
            {
                __module_stream_destroy(&svc->input->stream);
                free(svc->input);
            }
            if(svc->pat) mpegts_psi_destroy(svc->pat);
            if(svc->pmt) mpegts_psi_destroy(svc->pmt);
            if(svc->pmt_out) mpegts_psi_destroy(svc->pmt_out);
            if(svc->label) free(svc->label);
            if(svc->service_name) free(svc->service_name);
            if(svc->service_provider) free(svc->service_provider);
            free(svc);
            asc_list_remove_current(mod->services);
        }
        asc_list_destroy(mod->services);
    }
}

MODULE_STREAM_METHODS()
MODULE_LUA_METHODS()
{
    { "add_input", method_add_input },
    { "stats", method_stats },
    MODULE_STREAM_METHODS_REF()
};

MODULE_LUA_REGISTER(mpts_mux)
