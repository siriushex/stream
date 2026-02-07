/*
 * Astra Module: SoftCAM. Decrypt Module
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
 *      decrypt
 *
 * Module Options:
 *      upstream    - object, stream instance returned by module_instance:stream()
 *      name        - string, channel name
 *      biss        - string, BISS key, 16 chars length. example: biss = "1122330044556600"
 *      cam         - object, cam instance returned by cam_module_instance:cam()
 *      cas_data    - string, additional paramters for CAS
 *      cas_pnr     - number, original PNR
 */

#include <astra.h>
#include "module_cam.h"
#include "cas/cas_list.h"

#ifndef FFDECSA
#   define FFDECSA 1
#endif

#ifndef LIBDVBCSA
#   define LIBDVBCSA 0
#endif

#if FFDECSA == 1
#   include "FFdecsa/FFdecsa.h"
#elif LIBDVBCSA == 1
#   include <dvbcsa/dvbcsa.h>
#else
#   error "DVB-CSA is not defined"
#endif

typedef struct ca_stream_t ca_stream_t;

typedef struct
{
    ca_stream_t *stream;
    bool is_backup;
} cam_ecm_arg_t;

typedef struct
{
    module_data_t *mod;
    ca_stream_t *stream;
} cam_backup_timer_arg_t;

struct ca_stream_t
{
    uint8_t ecm_type;
    uint16_t ecm_pid;

    bool is_keys;
    uint8_t parity;

    /* ECM retry state (helps recovery when CAM returns Not Found or responds late) */
    uint8_t last_ecm_type;
    bool last_ecm_ok;
    uint32_t ecm_fail_count;
    uint64_t last_ecm_send_us;
    uint64_t last_ecm_ok_us;

    /* Observability (best-effort, debug-friendly) */
    uint64_t stat_ecm_sent;
    uint64_t stat_ecm_retry;
    uint64_t stat_ecm_not_found;
    uint64_t stat_ecm_ok;
    uint64_t stat_ecm_ok_primary;
    uint64_t stat_ecm_ok_backup;
    uint64_t stat_rtt_sum_ms;
    uint64_t stat_rtt_count;
    uint64_t stat_rtt_min_ms;
    uint64_t stat_rtt_max_ms;
    uint64_t stat_rtt_hist[5];

    /* Per-CAM send timestamps */
    uint64_t sendtime_primary;
    uint64_t sendtime_backup;

    /* Dual-CAM hedge */
    asc_timer_t *backup_timer;
    cam_backup_timer_arg_t backup_timer_arg;
    uint8_t *backup_ecm_buf;
    uint16_t backup_ecm_len;
    bool backup_ecm_pending;

    /* Arg wrappers to identify which CAM responded */
    cam_ecm_arg_t arg_primary;
    cam_ecm_arg_t arg_backup;

    /* Last applied control words (for split updates / key guard) */
    bool active_key_set;
    uint8_t active_key[16]; /* [0..7]=even, [8..15]=odd */

    /* Candidate key guard (PES header validation before applying new keys) */
    bool cand_pending;
    uint8_t cand_mask;      /* 1=even, 2=odd, 3=both */
    uint8_t cand_key[16];
    uint64_t cand_set_us;
    uint8_t cand_ok_count;
    uint8_t cand_fail_count;

#if FFDECSA == 1

    void *keys;
    uint8_t **batch;

    void *cand_keys; /* scratch key schedule for candidate validation */

#elif LIBDVBCSA == 1

    struct dvbcsa_bs_key_s *even_key;
    struct dvbcsa_bs_key_s *odd_key;
    struct dvbcsa_bs_batch_s *batch;

    struct dvbcsa_bs_key_s *cand_even_key;
    struct dvbcsa_bs_key_s *cand_odd_key;

#endif

    size_t batch_skip;

    int new_key_id;  // 0 - not, 1 - first key, 2 - second key, 3 - both keys
    uint8_t new_key[16];

    uint64_t sendtime;
};

typedef struct
{
    uint16_t es_pid;

    ca_stream_t *ca_stream;
} el_stream_t;

struct module_data_t
{
    MODULE_STREAM_DATA();
    MODULE_DECRYPT_DATA();

    /* Config */
    const char *name;
    int caid;
    bool disable_emm;
    int ecm_pid;
    bool key_guard;
    bool dual_cam;
    uint32_t cam_backup_hedge_ms;
    uint64_t cam_backup_hedge_us;
    uint64_t backup_active_ms;
    uint64_t backup_active_since_us;
    bool backup_active;
    uint64_t started_us;

    /* CAM redundancy */
    module_cam_t *cam_primary;
    module_cam_t *cam_backup;

    /* dvbcsa */
    asc_list_t *el_list;
    asc_list_t *ca_list;

    size_t batch_size;

    struct
    {
        uint8_t *buffer;
        size_t size;
        size_t count;
        size_t dsc_count;
        size_t read;
        size_t write;
    } storage;

    struct
    {
        uint8_t *buffer;
        size_t size;
        size_t count;
        size_t read;
        size_t write;
    } shift;

    /* Base */
    mpegts_psi_t *stream[MAX_PID];
    mpegts_psi_t *pmt;
};

#define BISS_CAID 0x2600
#define MSG(_msg) "[decrypt %s] " _msg, mod->name

#define SHIFT_ASSUME_MBIT 10
#define SHIFT_MAX_BYTES (4 * 1024 * 1024)

void ca_stream_set_keys(ca_stream_t *ca_stream, const uint8_t *even, const uint8_t *odd);

static inline bool decrypt_any_cam_ready(module_data_t *mod)
{
    return (   (mod->cam_primary && mod->cam_primary->is_ready)
            || (mod->cam_backup && mod->cam_backup->is_ready));
}

static inline bool decrypt_all_cams_disable_emm(module_data_t *mod)
{
    bool any = false;
    bool all = true;
    if(mod->cam_primary)
    {
        any = true;
        if(!mod->cam_primary->disable_emm)
            all = false;
    }
    if(mod->cam_backup)
    {
        any = true;
        if(!mod->cam_backup->disable_emm)
            all = false;
    }
    if(!any)
        return true;
    return all;
}

static inline module_cam_t * decrypt_pick_ready_cam(module_data_t *mod)
{
    /* Keep current active CAM if still ready (avoid unnecessary reloads). */
    if(mod->__decrypt.cam && mod->__decrypt.cam->is_ready)
        return mod->__decrypt.cam;
    if(mod->cam_primary && mod->cam_primary->is_ready)
        return mod->cam_primary;
    if(mod->cam_backup && mod->cam_backup->is_ready)
        return mod->cam_backup;
    return mod->cam_primary ? mod->cam_primary : mod->__decrypt.cam;
}

ca_stream_t * ca_stream_init(module_data_t *mod, uint16_t ecm_pid)
{
    ca_stream_t *ca_stream;
    asc_list_for(mod->ca_list)
    {
        ca_stream = asc_list_data(mod->ca_list);
#if FFDECSA == 1
        return ca_stream;
#else
        if(ca_stream->ecm_pid == ecm_pid)
            return ca_stream;
#endif
    }

    ca_stream = malloc(sizeof(ca_stream_t));
    memset(ca_stream, 0, sizeof(ca_stream_t));

    ca_stream->ecm_pid = ecm_pid;
    ca_stream->arg_primary.stream = ca_stream;
    ca_stream->arg_primary.is_backup = false;
    ca_stream->arg_backup.stream = ca_stream;
    ca_stream->arg_backup.is_backup = true;
    ca_stream->backup_timer_arg.mod = mod;
    ca_stream->backup_timer_arg.stream = ca_stream;

#if FFDECSA == 1

    ca_stream->keys = get_key_struct();
    ca_stream->batch = calloc(mod->batch_size * 2 + 2, sizeof(uint8_t *));

#elif LIBDVBCSA == 1

    ca_stream->even_key = dvbcsa_bs_key_alloc();
    ca_stream->odd_key = dvbcsa_bs_key_alloc();
    ca_stream->batch = calloc(mod->batch_size + 1, sizeof(struct dvbcsa_bs_batch_s));

#endif

    asc_list_insert_tail(mod->ca_list, ca_stream);

    return ca_stream;
}

void ca_stream_destroy(ca_stream_t *ca_stream)
{
    if(ca_stream->backup_timer)
    {
        asc_timer_destroy(ca_stream->backup_timer);
        ca_stream->backup_timer = NULL;
    }
    if(ca_stream->backup_ecm_buf)
    {
        free(ca_stream->backup_ecm_buf);
        ca_stream->backup_ecm_buf = NULL;
        ca_stream->backup_ecm_len = 0;
    }

#if FFDECSA == 1

    free_key_struct(ca_stream->keys);
    free(ca_stream->batch);
    if(ca_stream->cand_keys)
        free_key_struct(ca_stream->cand_keys);

#elif LIBDVBCSA == 1

    dvbcsa_bs_key_free(ca_stream->even_key);
    dvbcsa_bs_key_free(ca_stream->odd_key);
    free(ca_stream->batch);
    if(ca_stream->cand_even_key)
        dvbcsa_bs_key_free(ca_stream->cand_even_key);
    if(ca_stream->cand_odd_key)
        dvbcsa_bs_key_free(ca_stream->cand_odd_key);

#endif

    free(ca_stream);
}

void ca_stream_set_keys(ca_stream_t *ca_stream, const uint8_t *even, const uint8_t *odd)
{
#if FFDECSA == 1

    if(even)
        set_even_control_word(ca_stream->keys, even);
    if(odd)
        set_odd_control_word(ca_stream->keys, odd);

#elif LIBDVBCSA == 1

    if(even)
        dvbcsa_bs_key_set(even, ca_stream->even_key);
    if(odd)
        dvbcsa_bs_key_set(odd, ca_stream->odd_key);

#endif
}

static void ca_stream_set_active_key(ca_stream_t *ca_stream, int mask, const uint8_t *key16)
{
    if(mask & 0x01)
        memcpy(&ca_stream->active_key[0], &key16[0], 8);
    if(mask & 0x02)
        memcpy(&ca_stream->active_key[8], &key16[8], 8);
    ca_stream->active_key_set = true;
}

static void ca_stream_stat_rtt(ca_stream_t *ca_stream, uint64_t ms)
{
    ca_stream->stat_rtt_sum_ms += ms;
    ca_stream->stat_rtt_count += 1;
    if(ca_stream->stat_rtt_min_ms == 0 || ms < ca_stream->stat_rtt_min_ms)
        ca_stream->stat_rtt_min_ms = ms;
    if(ms > ca_stream->stat_rtt_max_ms)
        ca_stream->stat_rtt_max_ms = ms;

    if(ms <= 50)
        ca_stream->stat_rtt_hist[0] += 1;
    else if(ms <= 100)
        ca_stream->stat_rtt_hist[1] += 1;
    else if(ms <= 250)
        ca_stream->stat_rtt_hist[2] += 1;
    else if(ms <= 500)
        ca_stream->stat_rtt_hist[3] += 1;
    else
        ca_stream->stat_rtt_hist[4] += 1;
}

static void module_backup_active_set(module_data_t *mod, bool active, uint64_t now_us)
{
    if(active)
    {
        if(!mod->backup_active)
        {
            mod->backup_active = true;
            mod->backup_active_since_us = now_us;
        }
        return;
    }

    if(mod->backup_active)
    {
        if(mod->backup_active_since_us)
            mod->backup_active_ms += (now_us - mod->backup_active_since_us) / 1000ULL;
        mod->backup_active = false;
        mod->backup_active_since_us = 0;
    }
}

static void on_cam_backup_hedge(void *arg)
{
    cam_backup_timer_arg_t *ctx = (cam_backup_timer_arg_t *)arg;
    if(!ctx || !ctx->mod || !ctx->stream)
        return;

    module_data_t *mod = ctx->mod;
    ca_stream_t *ca_stream = ctx->stream;

    ca_stream->backup_timer = NULL;
    ca_stream->backup_ecm_pending = false;

    if(!mod->cam_backup || !mod->cam_backup->is_ready)
        return;
    if(!ca_stream->backup_ecm_buf || ca_stream->backup_ecm_len == 0)
        return;

    mod->cam_backup->send_em(mod->cam_backup->self, &mod->__decrypt, &ca_stream->arg_backup,
                             ca_stream->backup_ecm_buf, ca_stream->backup_ecm_len);
    ca_stream->sendtime_backup = asc_utime();
}

static void ca_stream_guard_clear(ca_stream_t *ca_stream)
{
    ca_stream->cand_pending = false;
    ca_stream->cand_mask = 0;
    ca_stream->cand_set_us = 0;
    ca_stream->cand_ok_count = 0;
    ca_stream->cand_fail_count = 0;
}

static void ca_stream_guard_set_candidate(ca_stream_t *ca_stream, const uint8_t *key16, uint8_t mask, bool allow_initial)
{
    if(mask == 0)
        return;

    uint8_t cand_key[16];
    uint8_t cand_mask = mask;

    if(!ca_stream->active_key_set)
    {
        if(!allow_initial)
            return;
        /* Initial validation: require both halves (we don't have an "active" base). */
        cand_mask = 3;
        memcpy(cand_key, key16, sizeof(cand_key));
    }
    else
    {
        /* Build candidate from active keys + updated halves */
        memcpy(cand_key, ca_stream->active_key, sizeof(cand_key));
        if(mask & 0x01)
            memcpy(&cand_key[0], &key16[0], 8);
        if(mask & 0x02)
            memcpy(&cand_key[8], &key16[8], 8);
    }

    if(ca_stream->cand_pending && ca_stream->cand_mask == cand_mask
       && memcmp(ca_stream->cand_key, cand_key, sizeof(cand_key)) == 0)
    {
        /* Same candidate already staged: keep counters. */
        return;
    }

    memcpy(ca_stream->cand_key, cand_key, sizeof(ca_stream->cand_key));

    ca_stream->cand_pending = true;
    ca_stream->cand_mask = cand_mask;
    ca_stream->cand_set_us = asc_utime();
    ca_stream->cand_ok_count = 0;
    ca_stream->cand_fail_count = 0;

#if FFDECSA == 1
    if(!ca_stream->cand_keys)
        ca_stream->cand_keys = get_key_struct();
    set_control_words(ca_stream->cand_keys, &ca_stream->cand_key[0], &ca_stream->cand_key[8]);
#elif LIBDVBCSA == 1
    if(!ca_stream->cand_even_key)
        ca_stream->cand_even_key = dvbcsa_bs_key_alloc();
    if(!ca_stream->cand_odd_key)
        ca_stream->cand_odd_key = dvbcsa_bs_key_alloc();
    dvbcsa_bs_key_set(&ca_stream->cand_key[0], ca_stream->cand_even_key);
    dvbcsa_bs_key_set(&ca_stream->cand_key[8], ca_stream->cand_odd_key);
#endif
}

static inline bool __ts_payload_has_pes_header(const uint8_t *ts)
{
    const uint8_t *payload = TS_GET_PAYLOAD(ts);
    if(!payload)
        return false;
    if(payload + 6 > ts + TS_PACKET_SIZE)
        return false;
    return (payload[0] == 0x00 && payload[1] == 0x00 && payload[2] == 0x01);
}

static bool ca_stream_guard_validate_pes(module_data_t *mod, ca_stream_t *ca_stream, const uint8_t *ts)
{
    __uarg(mod);

    uint8_t scratch[TS_PACKET_SIZE];
    memcpy(scratch, ts, TS_PACKET_SIZE);

#if FFDECSA == 1
    if(!ca_stream->cand_keys)
        return false;
    unsigned char *cluster[3];
    cluster[0] = (unsigned char *)scratch;
    cluster[1] = (unsigned char *)scratch + TS_PACKET_SIZE;
    cluster[2] = NULL;
    decrypt_packets(ca_stream->cand_keys, cluster);
#elif LIBDVBCSA == 1
    const uint8_t sc = TS_IS_SCRAMBLED(scratch);
    int hdr_size = 0;
    if(TS_IS_PAYLOAD(scratch))
    {
        if(TS_IS_AF(scratch))
            hdr_size = 4 + scratch[4] + 1;
        else
            hdr_size = 4;
    }
    if(hdr_size <= 0 || hdr_size >= TS_PACKET_SIZE)
        return false;

    scratch[3] &= ~0xC0;

    struct dvbcsa_bs_batch_s batch[2];
    batch[0].data = &scratch[hdr_size];
    batch[0].len = TS_PACKET_SIZE - hdr_size;
    batch[1].data = NULL;

    if(sc == 0x80 && ca_stream->cand_even_key)
        dvbcsa_bs_decrypt(ca_stream->cand_even_key, batch, TS_BODY_SIZE);
    else if(sc == 0xC0 && ca_stream->cand_odd_key)
        dvbcsa_bs_decrypt(ca_stream->cand_odd_key, batch, TS_BODY_SIZE);
    else
        return false;
#endif

    return __ts_payload_has_pes_header(scratch);
}

static ca_stream_t * ca_stream_for_pid(module_data_t *mod, uint16_t pid)
{
    asc_list_for(mod->el_list)
    {
        el_stream_t *el_stream = asc_list_data(mod->el_list);
        if(el_stream->es_pid == pid)
            return el_stream->ca_stream;
    }
    asc_list_first(mod->ca_list);
    if(asc_list_eol(mod->ca_list))
        return NULL;
    return asc_list_data(mod->ca_list);
}

static void module_decrypt_cas_init(module_data_t *mod)
{
    for(int i = 0; cas_init_list[i]; ++i)
    {
        mod->__decrypt.cas = cas_init_list[i](&mod->__decrypt);
        if(mod->__decrypt.cas)
            return;
    }
    asc_assert(mod->__decrypt.cas != NULL, MSG("CAS with CAID:0x%04X not found"), mod->caid);
}

static void module_decrypt_cas_destroy(module_data_t *mod)
{
    if(mod->__decrypt.cas)
    {
        free(mod->__decrypt.cas->self);
        mod->__decrypt.cas = NULL;
    }

    for(  asc_list_first(mod->el_list)
        ; !asc_list_eol(mod->el_list)
        ; asc_list_remove_current(mod->el_list))
    {
        el_stream_t *el_stream = asc_list_data(mod->el_list);
        free(el_stream);
    }

    if(mod->caid == BISS_CAID)
    {
        asc_list_first(mod->ca_list);
        ca_stream_t *ca_stream = asc_list_data(mod->ca_list);
        ca_stream->batch_skip = 0;
        return;
    }

    for(  asc_list_first(mod->ca_list)
        ; !asc_list_eol(mod->ca_list)
        ; asc_list_remove_current(mod->ca_list))
    {
        ca_stream_t *ca_stream = asc_list_data(mod->ca_list);
        ca_stream_destroy(ca_stream);
    }
}

static void stream_reload(module_data_t *mod)
{
    mod->stream[0]->crc32 = 0;

    for(int i = 1; i < MAX_PID; ++i)
    {
        if(mod->stream[i])
        {
            mpegts_psi_destroy(mod->stream[i]);
            mod->stream[i] = NULL;
        }
    }

    module_decrypt_cas_destroy(mod);

    mod->storage.count = 0;
    mod->storage.dsc_count = 0;
    mod->storage.read = 0;
    mod->storage.write = 0;

    mod->shift.count = 0;
    mod->shift.read = 0;
    mod->shift.write = 0;
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
    module_data_t *mod = arg;

    // check changes
    const uint32_t crc32 = PSI_GET_CRC32(psi);
    if(crc32 == psi->crc32)
        return;

    // check crc
    if(crc32 != PSI_CALC_CRC32(psi))
    {
        asc_log_error(MSG("PAT checksum mismatch"));
        return;
    }

    // reload stream
    if(psi->crc32 != 0)
    {
        asc_log_warning(MSG("PAT changed. Reload stream info"));
        stream_reload(mod);
    }

    psi->crc32 = crc32;

    const uint8_t *pointer;
    PAT_ITEMS_FOREACH(psi, pointer)
    {
        const uint16_t pnr = PAT_ITEM_GET_PNR(psi, pointer);
        if(pnr == 0)
            continue; // skip NIT

        const uint16_t pid = PAT_ITEM_GET_PID(psi, pointer);
        if(mod->stream[pid])
            asc_log_error(MSG("Skip PMT pid:%d"), pid);
        else
        {
            mod->__decrypt.pnr = pnr;
            if(mod->__decrypt.cas_pnr == 0)
                mod->__decrypt.cas_pnr = pnr;

            mod->stream[pid] = mpegts_psi_init(MPEGTS_PACKET_PMT, pid);
        }

        break;
    }

    if(mod->__decrypt.cam && mod->__decrypt.cam->is_ready)
    {
        module_decrypt_cas_init(mod);
        mod->stream[1] = mpegts_psi_init(MPEGTS_PACKET_CAT, 1);
    }
}

/*
 *   oooooooo8     o   ooooooooooo
 * o888     88    888  88  888  88
 * 888           8  88     888
 * 888o     oo  8oooo88    888
 *  888oooo88 o88o  o888o o888o
 *
 */

static bool __cat_check_desc(module_data_t *mod, const uint8_t *desc)
{
    const uint16_t pid = DESC_CA_PID(desc);

    /* Skip BISS */
    if(pid == NULL_TS_PID)
        return false;

    if(mod->stream[pid])
    {
        if(!(mod->stream[pid]->type & MPEGTS_PACKET_CA))
        {
            asc_log_warning(MSG("Skip EMM pid:%d"), pid);
            return false;
        }
    }
    else
        mod->stream[pid] = mpegts_psi_init(MPEGTS_PACKET_CA, pid);

    if(mod->disable_emm || decrypt_all_cams_disable_emm(mod))
        return false;

    if(   mod->__decrypt.cas
       && DESC_CA_CAID(desc) == mod->caid
       && module_cas_check_descriptor(mod->__decrypt.cas, desc))
    {
        mod->stream[pid]->type = MPEGTS_PACKET_EMM;
        asc_log_info(MSG("Select EMM pid:%d"), pid);
        return true;
    }

    return false;
}

static void on_cat(void *arg, mpegts_psi_t *psi)
{
    module_data_t *mod = arg;

    // check changes
    const uint32_t crc32 = PSI_GET_CRC32(psi);
    if(crc32 == psi->crc32)
        return;

    // check crc
    if(crc32 != PSI_CALC_CRC32(psi))
    {
        asc_log_error(MSG("CAT checksum mismatch"));
        return;
    }

    // reload stream
    if(psi->crc32 != 0)
    {
        asc_log_warning(MSG("CAT changed. Reload stream info"));
        stream_reload(mod);
        return;
    }

    psi->crc32 = crc32;

    bool is_emm_selected = (mod->disable_emm || decrypt_all_cams_disable_emm(mod));

    const uint8_t *desc_pointer;
    CAT_DESC_FOREACH(psi, desc_pointer)
    {
        if(desc_pointer[0] == 0x09)
        {
            if(__cat_check_desc(mod, desc_pointer))
                is_emm_selected = true;
        }
    }

    if(!is_emm_selected)
        asc_log_warning(MSG("EMM is not found"));
}

/*
 * oooooooooo oooo     oooo ooooooooooo
 *  888    888 8888o   888  88  888  88
 *  888oooo88  88 888o8 88      888
 *  888        88  888  88      888
 * o888o      o88o  8  o88o    o888o
 *
 */

static ca_stream_t * __pmt_check_desc(  module_data_t *mod
                                      , const uint8_t *desc
                                      , bool is_ecm_selected)
{
    const uint16_t pid = DESC_CA_PID(desc);

    /* Skip BISS */
    if(pid == NULL_TS_PID)
        return NULL;

    if(mod->stream[pid] == NULL)
        mod->stream[pid] = mpegts_psi_init(MPEGTS_PACKET_CA, pid);

    do
    {
        if(!mod->__decrypt.cas)
            break;
        if(is_ecm_selected)
            break;
        if(!(mod->stream[pid]->type & MPEGTS_PACKET_CA))
            break;

        if(mod->ecm_pid == 0)
        {
            if(DESC_CA_CAID(desc) != mod->caid)
                break;
            if(!module_cas_check_descriptor(mod->__decrypt.cas, desc))
                break;
        }
        else
        {
            if(mod->ecm_pid != pid)
                break;
        }

        asc_list_for(mod->ca_list)
        {
            ca_stream_t *ca_stream = asc_list_data(mod->ca_list);
            if(ca_stream->ecm_pid == pid)
                return ca_stream;
        }

        mod->stream[pid]->type = MPEGTS_PACKET_ECM;
        asc_log_info(MSG("Select ECM pid:%d"), pid);
        return ca_stream_init(mod, pid);
    } while(0);

    asc_log_warning(MSG("Skip ECM pid:%d"), pid);
    return NULL;
}

static void on_pmt(void *arg, mpegts_psi_t *psi)
{
    module_data_t *mod = arg;

    if(psi->buffer[0] != 0x02)
        return;

    // check pnr
    const uint16_t pnr = PMT_GET_PNR(psi);
    if(pnr != mod->__decrypt.pnr)
        return;

    // check changes
    const uint32_t crc32 = PSI_GET_CRC32(psi);
    if(crc32 == psi->crc32)
    {
        mpegts_psi_demux(  mod->pmt
                         , (void (*)(void *, const uint8_t *))__module_stream_send
                         , &mod->__stream);
        return;
    }

    // check crc
    if(crc32 != PSI_CALC_CRC32(psi))
    {
        asc_log_error(MSG("PMT checksum mismatch"));
        return;
    }

    // reload stream
    if(psi->crc32 != 0)
    {
        asc_log_warning(MSG("PMT changed. Reload stream info"));
        stream_reload(mod);
        return;
    }

    psi->crc32 = crc32;

    // Make custom PMT and set descriptors for CAS
    mod->pmt->pid = psi->pid;

    ca_stream_t *ca_stream_g = NULL;
    bool is_ecm_selected;

    uint16_t skip = 12;
    memcpy(mod->pmt->buffer, psi->buffer, 10);

    is_ecm_selected = false;
    const uint8_t *desc_pointer;
    PMT_DESC_FOREACH(psi, desc_pointer)
    {
        if(desc_pointer[0] == 0x09)
        {
            ca_stream_t *__ca_stream = __pmt_check_desc(mod, desc_pointer, is_ecm_selected);
            if(__ca_stream)
            {
                ca_stream_g = __ca_stream;
                is_ecm_selected = true;
            }
        }
        else
        {
            const uint8_t size = desc_pointer[1] + 2;
            memcpy(&mod->pmt->buffer[skip], desc_pointer, size);
            skip += size;
        }
    }
    const uint16_t size = skip - 12; // 12 - PMT header
    mod->pmt->buffer[10] = (psi->buffer[10] & 0xF0) | ((size >> 8) & 0x0F);
    mod->pmt->buffer[11] = size & 0xFF;

    const uint8_t *pointer;
    PMT_ITEMS_FOREACH(psi, pointer)
    {
        memcpy(&mod->pmt->buffer[skip], pointer, 5);
        skip += 5;

        const uint16_t skip_last = skip;

        ca_stream_t *ca_stream_e = ca_stream_g;
        is_ecm_selected = (ca_stream_g != NULL);
        PMT_ITEM_DESC_FOREACH(pointer, desc_pointer)
        {
            if(desc_pointer[0] == 0x09)
            {
                ca_stream_t *__ca_stream = __pmt_check_desc(mod, desc_pointer, is_ecm_selected);
                if(__ca_stream)
                {
                    ca_stream_e = __ca_stream;
                    is_ecm_selected = true;
                }
            }
            else
            {
                const uint8_t size = desc_pointer[1] + 2;
                memcpy(&mod->pmt->buffer[skip], desc_pointer, size);
                skip += size;
            }
        }

        if(ca_stream_e)
        {
            el_stream_t *el_stream = malloc(sizeof(el_stream_t));
            el_stream->es_pid = PMT_ITEM_GET_PID(psi, pointer);
            el_stream->ca_stream = ca_stream_e;
            asc_list_insert_tail(mod->el_list, el_stream);
        }

        const uint16_t size = skip - skip_last;
        mod->pmt->buffer[skip_last - 2] = (size << 8) & 0x0F;
        mod->pmt->buffer[skip_last - 1] = size & 0xFF;
    }

    mod->pmt->buffer_size = skip + CRC32_SIZE;
    PSI_SET_SIZE(mod->pmt);
    PSI_SET_CRC32(mod->pmt);

    mpegts_psi_demux(  mod->pmt
                     , (void (*)(void *, const uint8_t *))__module_stream_send
                     , &mod->__stream);
}

/*
 * ooooooooooo oooo     oooo
 *  888    88   8888o   888
 *  888ooo8     88 888o8 88
 *  888    oo   88  888  88
 * o888ooo8888 o88o  8  o88o
 *
 */

static void on_em(void *arg, mpegts_psi_t *psi)
{
    module_data_t *mod = arg;

    if(!decrypt_any_cam_ready(mod))
        return;

    if(psi->buffer_size > EM_MAX_SIZE)
    {
        asc_log_error(MSG("em size is greater than %d"), EM_MAX_SIZE);
        return;
    }

    ca_stream_t *ca_stream = NULL;

    const uint8_t em_type = psi->buffer[0];

    if(em_type == 0x80 || em_type == 0x81)
    { /* ECM */
        asc_list_for(mod->ca_list)
        {
            ca_stream_t *i = asc_list_data(mod->ca_list);
            if(i->ecm_pid == psi->pid)
            {
                ca_stream = i;
                break;
            }
        }

        if(!ca_stream)
            return;

        if(!module_cas_check_em(mod->__decrypt.cas, psi))
            return;

        const uint64_t now_us = asc_utime();
        uint64_t retry_us = 0;
        if(!ca_stream->is_keys || !ca_stream->last_ecm_ok || ca_stream->cand_pending)
        {
            /* Adaptive backoff: avoid ECM storms when CAM is degraded. */
            uint32_t fail = ca_stream->ecm_fail_count;
            if(fail == UINT32_MAX)
                fail = 4;
            uint32_t exp = fail;
            if(exp > 3)
                exp = 3;
            retry_us = 250000ULL * (1ULL << exp);
            if(retry_us > 2000000ULL)
                retry_us = 2000000ULL;
        }
        else
        {
            /* Stable: keep a small keepalive resend interval to tolerate short glitches. */
            retry_us = 2000000ULL;
        }

        /* Deterministic jitter (by PID) to reduce lockstep spikes across many streams. */
        retry_us += ((uint64_t)(psi->pid % 53)) * 1000ULL; /* 0..52ms */

        const bool is_retry = (em_type == ca_stream->last_ecm_type && ca_stream->last_ecm_send_us != 0);

        if(em_type == ca_stream->last_ecm_type && ca_stream->last_ecm_send_us != 0)
        {
            const uint64_t since_us = now_us - ca_stream->last_ecm_send_us;
            if(since_us < retry_us)
                return;
        }

        ca_stream->ecm_type = em_type;
        ca_stream->last_ecm_type = em_type;
        ca_stream->last_ecm_send_us = now_us;
        ca_stream->stat_ecm_sent += 1;
        if(is_retry)
            ca_stream->stat_ecm_retry += 1;
    }
    else if(em_type >= 0x82 && em_type <= 0x8F)
    { /* EMM */
        if(mod->disable_emm)
            return;

        if(!module_cas_check_em(mod->__decrypt.cas, psi))
            return;
    }
    else
    {
        asc_log_error(MSG("wrong packet type 0x%02X"), em_type);
        return;
    }

    const bool is_ecm = (em_type == 0x80 || em_type == 0x81);
    bool sent_primary = false;
    bool sent = false;
    if(mod->cam_primary && mod->cam_primary->is_ready)
    {
        if(em_type < 0x82 || em_type > 0x8F || !mod->cam_primary->disable_emm)
        {
            mod->cam_primary->send_em(mod->cam_primary->self, &mod->__decrypt, &ca_stream->arg_primary,
                                      psi->buffer, psi->buffer_size);
            ca_stream->sendtime_primary = asc_utime();
            sent_primary = true;
            sent = true;
        }
    }
    if(mod->cam_backup && mod->cam_backup->is_ready)
    {
        if(em_type < 0x82 || em_type > 0x8F || !mod->cam_backup->disable_emm)
        {
            if(is_ecm && mod->cam_backup_hedge_ms > 0 && sent_primary)
            {
                if(ca_stream->backup_timer)
                {
                    asc_timer_destroy(ca_stream->backup_timer);
                    ca_stream->backup_timer = NULL;
                }
                ca_stream->backup_ecm_buf = realloc(ca_stream->backup_ecm_buf, psi->buffer_size);
                if(ca_stream->backup_ecm_buf)
                {
                    memcpy(ca_stream->backup_ecm_buf, psi->buffer, psi->buffer_size);
                    ca_stream->backup_ecm_len = psi->buffer_size;
                    ca_stream->backup_ecm_pending = true;
                    ca_stream->backup_timer = asc_timer_one_shot(mod->cam_backup_hedge_ms,
                                                                 on_cam_backup_hedge,
                                                                 &ca_stream->backup_timer_arg);
                    sent = true;
                }
            }
            else
            {
                mod->cam_backup->send_em(mod->cam_backup->self, &mod->__decrypt, &ca_stream->arg_backup,
                                         psi->buffer, psi->buffer_size);
                ca_stream->sendtime_backup = asc_utime();
                sent = true;
            }
        }
    }
    __uarg(sent);
}

/*
 * ooooooooooo  oooooooo8
 * 88  888  88 888
 *     888      888oooooo
 *     888             888
 *    o888o    o88oooo888
 *
 */

static void decrypt(module_data_t *mod)
{
    asc_list_for(mod->ca_list)
    {
        ca_stream_t *ca_stream = asc_list_data(mod->ca_list);

        if(ca_stream->batch_skip > 0)
        {

#if FFDECSA == 1

            ca_stream->batch[ca_stream->batch_skip] = NULL;

            size_t i = 0, i_size = ca_stream->batch_skip / 2;
            while(i < i_size)
                i += decrypt_packets(ca_stream->keys, ca_stream->batch);

#elif LIBDVBCSA == 1

            ca_stream->batch[ca_stream->batch_skip].data = NULL;

            if(ca_stream->parity == 0x80)
                dvbcsa_bs_decrypt(ca_stream->even_key, ca_stream->batch, TS_BODY_SIZE);
            else if(ca_stream->parity == 0xC0)
                dvbcsa_bs_decrypt(ca_stream->odd_key, ca_stream->batch, TS_BODY_SIZE);

#endif

            ca_stream->batch_skip = 0;
        }

        // check new key
        switch(ca_stream->new_key_id)
        {
            case 0:
                break;
            case 1:
                ca_stream_set_keys(ca_stream, &ca_stream->new_key[0], NULL);
                ca_stream_set_active_key(ca_stream, 1, ca_stream->new_key);
                ca_stream_guard_clear(ca_stream);
                ca_stream->new_key_id = 0;
                break;
            case 2:
                ca_stream_set_keys(ca_stream, NULL, &ca_stream->new_key[8]);
                ca_stream_set_active_key(ca_stream, 2, ca_stream->new_key);
                ca_stream_guard_clear(ca_stream);
                ca_stream->new_key_id = 0;
                break;
            case 3:
                ca_stream_set_keys(  ca_stream
                                   , &ca_stream->new_key[0]
                                   , &ca_stream->new_key[8]);
                ca_stream_set_active_key(ca_stream, 3, ca_stream->new_key);
                ca_stream_guard_clear(ca_stream);
                ca_stream->new_key_id = 0;
                break;
        }
    }

    mod->storage.dsc_count = mod->storage.count;
}

static void on_ts(module_data_t *mod, const uint8_t *ts)
{
    const uint16_t pid = TS_GET_PID(ts);

    if(pid == 0)
    {
        mpegts_psi_mux(mod->stream[pid], ts, on_pat, mod);
    }
    else if(pid == 1)
    {
        if(mod->stream[pid])
            mpegts_psi_mux(mod->stream[pid], ts, on_cat, mod);
        return;
    }
    else if(pid == NULL_TS_PID)
    {
        return;
    }
    else if(mod->stream[pid])
    {
        switch(mod->stream[pid]->type)
        {
            case MPEGTS_PACKET_PMT:
                mpegts_psi_mux(mod->stream[pid], ts, on_pmt, mod);
                return;
            case MPEGTS_PACKET_ECM:
            case MPEGTS_PACKET_EMM:
                mpegts_psi_mux(mod->stream[pid], ts, on_em, mod);
            case MPEGTS_PACKET_CA:
                return;
            default:
                break;
        }
    }

    if(asc_list_size(mod->ca_list) == 0)
    {
        module_stream_send(mod, ts);
        return;
    }

    if(mod->shift.buffer)
    {
        memcpy(&mod->shift.buffer[mod->shift.write], ts, TS_PACKET_SIZE);
        mod->shift.write += TS_PACKET_SIZE;
        if(mod->shift.write == mod->shift.size)
            mod->shift.write = 0;
        mod->shift.count += TS_PACKET_SIZE;

        if(mod->shift.count < mod->shift.size)
            return;

        ts = &mod->shift.buffer[mod->shift.read];
        mod->shift.read += TS_PACKET_SIZE;
        if(mod->shift.read == mod->shift.size)
            mod->shift.read = 0;
        mod->shift.count -= TS_PACKET_SIZE;
    }

    /* key_guard: validate candidate keys on PES headers before applying */
    if(mod->key_guard && TS_IS_SCRAMBLED(ts) && TS_IS_PAYLOAD_START(ts))
    {
        ca_stream_t *ca_stream = ca_stream_for_pid(mod, pid);
        if(ca_stream && ca_stream->cand_pending)
        {
            const uint64_t now_us = asc_utime();
            if(ca_stream->cand_set_us && now_us - ca_stream->cand_set_us > 10000000ULL)
            {
                /* Stale candidate: drop silently and retry via ECM resend. */
                ca_stream_guard_clear(ca_stream);
            }
            else
            {
                const uint8_t sc = TS_IS_SCRAMBLED(ts);
                uint8_t p_mask = 0;
                if(sc == 0x80)
                    p_mask = 1;
                else if(sc == 0xC0)
                    p_mask = 2;

                if(p_mask && (ca_stream->cand_mask & p_mask))
                {
                    const bool ok = ca_stream_guard_validate_pes(mod, ca_stream, ts);
                    if(ok)
                        ca_stream->cand_ok_count += 1;
                    else
                        ca_stream->cand_fail_count += 1;

                    if(ca_stream->cand_ok_count >= 2)
                    {
                        ca_stream->new_key_id = ca_stream->cand_mask;
                        memcpy(ca_stream->new_key, ca_stream->cand_key, sizeof(ca_stream->new_key));
                        if(asc_log_is_debug())
                            asc_log_debug(MSG("key_guard: candidate keys accepted (mask:%u)"), (unsigned)ca_stream->new_key_id);
                        ca_stream_guard_clear(ca_stream);
                    }
                    else if(ca_stream->cand_fail_count >= 2)
                    {
                        if(asc_log_is_debug())
                            asc_log_debug(MSG("key_guard: candidate keys rejected (mask:%u)"), (unsigned)ca_stream->cand_mask);
                        ca_stream_guard_clear(ca_stream);
                        ca_stream->last_ecm_ok = false;
                        ca_stream->last_ecm_send_us = 0;
                        if(ca_stream->ecm_fail_count != UINT32_MAX)
                            ++ca_stream->ecm_fail_count;
                    }
                }
            }
        }
    }

    uint8_t *dst = &mod->storage.buffer[mod->storage.write];
    memcpy(dst, ts, TS_PACKET_SIZE);

    mod->storage.write += TS_PACKET_SIZE;
    if(mod->storage.write == mod->storage.size)
        mod->storage.write = 0;
    mod->storage.count += TS_PACKET_SIZE;

#if FFDECSA == 1

    asc_list_first(mod->ca_list);
    ca_stream_t *ca_stream = asc_list_data(mod->ca_list);

    ca_stream->batch[ca_stream->batch_skip    ] = dst;
    ca_stream->batch[ca_stream->batch_skip + 1] = dst + TS_PACKET_SIZE;
    ca_stream->batch_skip += 2;

    if(ca_stream->batch_skip >= mod->batch_size * 2)
        decrypt(mod);

#elif LIBDVBCSA == 1

    const uint8_t sc = TS_IS_SCRAMBLED(dst);
    if(sc)
    {
        dst[3] &= ~0xC0;

        int hdr_size = 0;

        if(TS_IS_PAYLOAD(ts))
        {
            if(TS_IS_AF(ts))
                hdr_size = 4 + dst[4] + 1;
            else
                hdr_size = 4;
        }

        if(hdr_size)
        {
            ca_stream_t *ca_stream = NULL;
            asc_list_for(mod->el_list)
            {
                el_stream_t *el_stream = asc_list_data(mod->el_list);
                if(el_stream->es_pid == pid)
                {
                    ca_stream = el_stream->ca_stream;
                    break;
                }
            }
            if(!ca_stream)
            {
                asc_list_first(mod->ca_list);
                ca_stream = asc_list_data(mod->ca_list);
            }

            if(ca_stream->parity != sc)
            {
                if(ca_stream->parity != 0x00)
                    decrypt(mod);
                ca_stream->parity = sc;
            }

            ca_stream->batch[ca_stream->batch_skip].data = &dst[hdr_size];
            ca_stream->batch[ca_stream->batch_skip].len = TS_PACKET_SIZE - hdr_size;
            ++ca_stream->batch_skip;

            if(ca_stream->batch_skip >= mod->batch_size)
                decrypt(mod);
        }
    }

#endif

    if(mod->storage.count >= mod->storage.size)
        decrypt(mod);

    if(mod->storage.dsc_count > 0)
    {
        module_stream_send(mod, &mod->storage.buffer[mod->storage.read]);
        mod->storage.read += TS_PACKET_SIZE;
        if(mod->storage.read == mod->storage.size)
            mod->storage.read = 0;
        mod->storage.dsc_count -= TS_PACKET_SIZE;
        mod->storage.count -= TS_PACKET_SIZE;
    }
}

/*
 *      o      oooooooooo ooooo
 *     888      888    888 888
 *    8  88     888oooo88  888
 *   8oooo88    888        888
 * o88o  o888o o888o      o888o
 *
 */

void on_cam_ready(module_data_t *mod)
{
    module_cam_t *active = decrypt_pick_ready_cam(mod);
    if(!active || !active->is_ready)
        return;

    const bool changed_cam = (mod->__decrypt.cam != active);
    mod->__decrypt.cam = active;

    if(mod->caid != active->caid || mod->__decrypt.cas == NULL || changed_cam)
    {
        mod->caid = active->caid;
        stream_reload(mod);
    }
    else
    {
        mod->caid = active->caid;
    }
}

void on_cam_error(module_data_t *mod)
{
    module_cam_t *active = decrypt_pick_ready_cam(mod);
    if(active && active->is_ready)
    {
        const bool changed_cam = (mod->__decrypt.cam != active);
        mod->__decrypt.cam = active;
        if(mod->caid != active->caid || mod->__decrypt.cas == NULL || changed_cam)
        {
            mod->caid = active->caid;
            stream_reload(mod);
        }
        else
        {
            mod->caid = active->caid;
        }
        return;
    }

    mod->caid = 0x0000;
    module_decrypt_cas_destroy(mod);
}

void on_cam_response(module_data_t *mod, void *arg, const uint8_t *data)
{
    cam_ecm_arg_t *em_arg = (cam_ecm_arg_t *)arg;
    ca_stream_t *ca_stream = em_arg ? em_arg->stream : NULL;
    const bool is_backup = em_arg ? em_arg->is_backup : false;
    if(!ca_stream)
        return;
    asc_list_for(mod->ca_list)
    {
        if(asc_list_data(mod->ca_list) == ca_stream)
            break;
    }
    if(asc_list_eol(mod->ca_list))
        return;

    if((data[0] & ~0x01) != 0x80)
        return; /* Skip EMM */

    if(!mod->__decrypt.cas)
        return; /* after stream_reload */

    bool is_keys_ok = false;
    bool is_cw_checksum_ok = false;
    do
    {
        if(!module_cas_check_keys(mod->__decrypt.cas, data))
            break;

        if(data[2] != 16)
            break;

        /*
         * DVB-CSA control words often include "check" bytes (sum of previous 3 bytes)
         * at positions 3 and 7. Some CAM servers/implementations don't enforce this.
         * We treat checksum mismatch as non-fatal to maximize compatibility.
         */
        const uint8_t ck1 = (data[3] + data[4] + data[5]) & 0xFF;
        const uint8_t ck2 = (data[7] + data[8] + data[9]) & 0xFF;
        is_cw_checksum_ok = (ck1 == data[6] && ck2 == data[10]);

        is_keys_ok = true;
    } while(0);

    if(is_keys_ok)
    {
        const uint64_t now_us = asc_utime();
        const uint64_t sendtime = is_backup ? ca_stream->sendtime_backup : ca_stream->sendtime_primary;
        const uint64_t responsetime = sendtime ? (now_us - sendtime) / 1000 : 0;
        ca_stream->stat_ecm_ok += 1;
        if(is_backup)
            ca_stream->stat_ecm_ok_backup += 1;
        else
            ca_stream->stat_ecm_ok_primary += 1;
        if(sendtime)
            ca_stream_stat_rtt(ca_stream, responsetime);

        ca_stream->last_ecm_ok = true;
        ca_stream->ecm_fail_count = 0;
        ca_stream->last_ecm_ok_us = now_us;

        if(mod->dual_cam)
            module_backup_active_set(mod, is_backup, now_us);

        if(!is_backup && ca_stream->backup_timer)
        {
            asc_timer_destroy(ca_stream->backup_timer);
            ca_stream->backup_timer = NULL;
            ca_stream->backup_ecm_pending = false;
        }

        if(!is_cw_checksum_ok && asc_log_is_debug())
            asc_log_debug(MSG("ECM CW checksum mismatch"));

        uint8_t key16[16];
        memcpy(key16, &data[3], sizeof(key16));

        if(ca_stream->active_key_set && memcmp(key16, ca_stream->active_key, sizeof(key16)) == 0)
        {
            /* Avoid staging/reapplying identical keys (common with redundant CAM responses). */
            return;
        }

        /* Try to detect which key half changed using checksum bytes (best-effort). */
        uint8_t mask = 3;
        if(ca_stream->active_key_set)
        {
            /* odd checksum bytes (positions 3 and 7 in CW) */
            if(ca_stream->active_key[8 + 3] == data[11 + 3] && ca_stream->active_key[8 + 7] == data[11 + 7])
                mask = 1;
            /* even checksum bytes */
            else if(ca_stream->active_key[0 + 3] == data[3 + 3] && ca_stream->active_key[0 + 7] == data[3 + 7])
                mask = 2;
        }

        if(!ca_stream->is_keys)
            ca_stream->is_keys = true;

        if(mod->key_guard && (mod->dual_cam || ca_stream->active_key_set))
        {
            /* Guarded switch: validate candidate keys on PES headers before applying. */
            ca_stream_guard_set_candidate(ca_stream, key16, mask, mod->dual_cam);
            if(!is_cw_checksum_ok && asc_log_is_debug())
                asc_log_debug(MSG("key_guard: candidate keys staged (checksum mismatch)"));
        }
        else
        {
            /* Immediate apply path (legacy behavior) */
            ca_stream->new_key_id = mask;
            if(mask & 0x01)
                memcpy(&ca_stream->new_key[0], &key16[0], 8);
            if(mask & 0x02)
                memcpy(&ca_stream->new_key[8], &key16[8], 8);
            if(mask == 3 && ca_stream->active_key_set && asc_log_is_debug())
                asc_log_debug(MSG("Both keys changed"));
        }

        if(asc_log_is_debug())
        {
            char key_1[17], key_2[17];
            hex_to_str(key_1, &data[3], 8);
            hex_to_str(key_2, &data[11], 8);
            asc_log_debug(  MSG("ECM Found id:0x%02X time:%"PRIu64"ms key:%s:%s")
                          , data[0], responsetime, key_1, key_2);
        }

    }
    else
    {
        const uint64_t now_us = asc_utime();
        const uint64_t sendtime = is_backup ? ca_stream->sendtime_backup : ca_stream->sendtime_primary;
        const uint64_t responsetime = sendtime ? (now_us - sendtime) / 1000 : 0;
        ca_stream->stat_ecm_not_found += 1;
        if(sendtime)
            ca_stream_stat_rtt(ca_stream, responsetime);

        if(mod->dual_cam && ca_stream->last_ecm_ok_us && (now_us - ca_stream->last_ecm_ok_us) < 500000ULL)
        {
            /* In dual-CAM mode one CAM can reply Not Found while the other already provided keys. */
            return;
        }

        ca_stream->last_ecm_ok = false;
        if(ca_stream->ecm_fail_count != UINT32_MAX)
            ++ca_stream->ecm_fail_count;

        if(ca_stream->ecm_fail_count <= 3 && !asc_log_is_debug())
        {
            asc_log_warning(  MSG("ECM Not Found id:0x%02X time:%"PRIu64"ms size:%d fail:%u")
                            , data[0], responsetime, data[2], (unsigned)ca_stream->ecm_fail_count);
        }
        else
        {
            asc_log_error(  MSG("ECM Not Found id:0x%02X time:%"PRIu64"ms size:%d fail:%u")
                          , data[0], responsetime, data[2], (unsigned)ca_stream->ecm_fail_count);
        }
    }
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
    module_stream_init(mod, on_ts);

    mod->__decrypt.self = mod;

    module_option_string("name", &mod->name, NULL);
    asc_assert(mod->name != NULL, "[decrypt] option 'name' is required");

    module_option_boolean("key_guard", &mod->key_guard);

    mod->stream[0] = mpegts_psi_init(MPEGTS_PACKET_PAT, 0);
    mod->pmt = mpegts_psi_init(MPEGTS_PACKET_PMT, MAX_PID);

    mod->ca_list = asc_list_init();
    mod->el_list = asc_list_init();

#if FFDECSA == 1

    mod->batch_size = get_suggested_cluster_size();

#elif LIBDVBCSA == 1

    mod->batch_size = dvbcsa_bs_batch_size();

#endif

    mod->storage.size = mod->batch_size * 4 * TS_PACKET_SIZE;
    mod->storage.buffer = malloc(mod->storage.size);

    const char *biss_key = NULL;
    size_t biss_length = 0;
    module_option_string("biss", &biss_key, &biss_length);
    if(biss_key)
    {
        asc_assert(biss_length == 16, MSG("biss key must be 16 char length"));

        mod->caid = BISS_CAID;
        mod->disable_emm = true;

        uint8_t key[8];
        str_to_hex(biss_key, key, sizeof(key));
        key[3] = (key[0] + key[1] + key[2]) & 0xFF;
        key[7] = (key[4] + key[5] + key[6]) & 0xFF;

        ca_stream_t *biss = ca_stream_init(mod, NULL_TS_PID);
        ca_stream_set_keys(biss, key, key);
        uint8_t key16[16];
        memcpy(&key16[0], key, 8);
        memcpy(&key16[8], key, 8);
        ca_stream_set_active_key(biss, 3, key16);
    }

    lua_getfield(lua, 2, "cam");
    if(!lua_isnil(lua, -1))
    {
        asc_assert(  lua_type(lua, -1) == LUA_TLIGHTUSERDATA
                   , "option 'cam' required cam-module instance");
        mod->__decrypt.cam = lua_touserdata(lua, -1);
        mod->cam_primary = mod->__decrypt.cam;

        int cas_pnr = 0;
        module_option_number("cas_pnr", &cas_pnr);
        if(cas_pnr > 0 && cas_pnr <= 0xFFFF)
            mod->__decrypt.cas_pnr = (uint16_t)cas_pnr;

        const char *cas_data = NULL;
        module_option_string("cas_data", &cas_data, NULL);
        if(cas_data)
        {
            mod->__decrypt.is_cas_data = true;
            str_to_hex(cas_data, mod->__decrypt.cas_data, sizeof(mod->__decrypt.cas_data));
        }

        module_option_boolean("disable_emm", &mod->disable_emm);
        module_option_number("ecm_pid", &mod->ecm_pid);

        module_cam_attach_decrypt(mod->__decrypt.cam, &mod->__decrypt);
    }
    lua_pop(lua, 1);

    lua_getfield(lua, 2, "cam_backup");
    if(!lua_isnil(lua, -1))
    {
        asc_assert(  lua_type(lua, -1) == LUA_TLIGHTUSERDATA
                   , "option 'cam_backup' required cam-module instance");
        mod->cam_backup = lua_touserdata(lua, -1);
        if(mod->cam_backup && mod->cam_backup != mod->cam_primary)
        {
            mod->dual_cam = true;
            if(!mod->key_guard)
            {
                /* In dual-CAM mode we always enable guarded key switch to avoid bad CW blips. */
                mod->key_guard = true;
            }
            module_cam_attach_decrypt(mod->cam_backup, &mod->__decrypt);
            if(asc_log_is_debug())
                asc_log_debug(MSG("dual CAM enabled (primary+backup)"));
        }
    }
    lua_pop(lua, 1);

    int shift = 0;
    module_option_number("shift", &shift);
    if(shift > 0)
    {
        /*
         * shift is a buffered delay before decrypt (time-based, capped).
         * Backward compatibility: small values historically behaved like "units" rather than ms.
         * We treat shift < 100 as legacy units where 1 == 100ms.
         */
        uint64_t shift_ms = (uint64_t)shift;
        if(shift < 100)
            shift_ms = (uint64_t)shift * 100ULL;

        const uint64_t bits_per_sec = (uint64_t)SHIFT_ASSUME_MBIT * 1000ULL * 1000ULL;
        uint64_t bytes = (shift_ms * bits_per_sec) / 8ULL / 1000ULL;
        if(bytes < TS_PACKET_SIZE)
            bytes = TS_PACKET_SIZE;
        bytes = ((bytes + TS_PACKET_SIZE - 1) / TS_PACKET_SIZE) * TS_PACKET_SIZE;
        if(bytes > SHIFT_MAX_BYTES)
            bytes = SHIFT_MAX_BYTES;
        mod->shift.size = (size_t)bytes;
        mod->shift.buffer = malloc(mod->shift.size);
        if(asc_log_is_debug() && bytes == SHIFT_MAX_BYTES)
            asc_log_debug(MSG("shift buffer capped to %d bytes"), SHIFT_MAX_BYTES);
    }

    stream_reload(mod);
}

static void module_destroy(module_data_t *mod)
{
    module_stream_destroy(mod);

    module_cam_t *cam_primary = mod->cam_primary;
    module_cam_t *cam_backup = mod->cam_backup;
    mod->cam_primary = NULL;
    mod->cam_backup = NULL;
    mod->__decrypt.cam = NULL;

    if(cam_primary)
        module_cam_detach_decrypt(cam_primary, &mod->__decrypt);
    if(cam_backup && cam_backup != cam_primary)
        module_cam_detach_decrypt(cam_backup, &mod->__decrypt);

    if(asc_log_is_debug())
    {
        asc_list_for(mod->ca_list)
        {
            ca_stream_t *ca_stream = asc_list_data(mod->ca_list);
            if(ca_stream->stat_ecm_sent == 0 && ca_stream->stat_ecm_ok == 0 && ca_stream->stat_ecm_not_found == 0)
                continue;
            uint64_t rtt_avg_ms = 0;
            if(ca_stream->stat_rtt_count)
                rtt_avg_ms = ca_stream->stat_rtt_sum_ms / ca_stream->stat_rtt_count;
            asc_log_debug(  MSG("ECM stats pid:%d sent:%"PRIu64" retry:%"PRIu64" ok:%"PRIu64" not_found:%"PRIu64" rtt_avg:%"PRIu64"ms")
                          , ca_stream->ecm_pid
                          , ca_stream->stat_ecm_sent
                          , ca_stream->stat_ecm_retry
                          , ca_stream->stat_ecm_ok
                          , ca_stream->stat_ecm_not_found
                          , rtt_avg_ms);
        }
    }

    module_decrypt_cas_destroy(mod);

    if(mod->caid == BISS_CAID)
    {
        asc_list_first(mod->ca_list);
        ca_stream_t *ca_stream = asc_list_data(mod->ca_list);
        ca_stream_destroy(ca_stream);
        asc_list_remove_current(mod->ca_list);
    }

    asc_list_destroy(mod->ca_list);
    asc_list_destroy(mod->el_list);

    free(mod->storage.buffer);

    if(mod->shift.buffer)
        free(mod->shift.buffer);

    for(int i = 0; i < MAX_PID; ++i)
    {
        if(mod->stream[i])
        {
            mpegts_psi_destroy(mod->stream[i]);
            mod->stream[i] = NULL;
        }
    }
    mpegts_psi_destroy(mod->pmt);
}

static int method_stats(module_data_t *mod)
{
    lua_newtable(lua);

    lua_pushstring(lua, mod->name ? mod->name : "");
    lua_setfield(lua, -2, "name");

    lua_pushboolean(lua, mod->key_guard);
    lua_setfield(lua, -2, "key_guard");

    lua_pushboolean(lua, decrypt_any_cam_ready(mod));
    lua_setfield(lua, -2, "cam_ready");

    lua_pushboolean(lua, mod->dual_cam);
    lua_setfield(lua, -2, "dual_cam");

    lua_pushinteger(lua, (lua_Integer)mod->cam_backup_hedge_ms);
    lua_setfield(lua, -2, "cam_backup_hedge_ms");

    const uint64_t now_us = asc_utime();
    uint64_t backup_ms = mod->backup_active_ms;
    if(mod->backup_active && mod->backup_active_since_us)
        backup_ms += (now_us - mod->backup_active_since_us) / 1000ULL;
    lua_pushinteger(lua, (lua_Integer)backup_ms);
    lua_setfield(lua, -2, "backup_active_ms");
    if(mod->started_us && now_us > mod->started_us)
    {
        const uint64_t uptime_ms = (now_us - mod->started_us) / 1000ULL;
        if(uptime_ms > 0)
        {
            lua_pushnumber(lua, (lua_Number)backup_ms / (lua_Number)uptime_ms);
            lua_setfield(lua, -2, "backup_active_pct");
        }
    }

    /* shift buffer observability */
    lua_newtable(lua);
    lua_pushinteger(lua, (lua_Integer)mod->shift.size);
    lua_setfield(lua, -2, "size_bytes");
    lua_pushinteger(lua, (lua_Integer)mod->shift.count);
    lua_setfield(lua, -2, "fill_bytes");
    if(mod->shift.size > 0)
    {
        const lua_Number pct = (lua_Number)mod->shift.count / (lua_Number)mod->shift.size;
        lua_pushnumber(lua, pct);
        lua_setfield(lua, -2, "fill_pct");
    }
    lua_setfield(lua, -2, "shift");

    /* per-ECM PID stats */
    lua_newtable(lua);
    int idx = 1;
    asc_list_for(mod->ca_list)
    {
        ca_stream_t *ca_stream = asc_list_data(mod->ca_list);

        lua_newtable(lua);

        lua_pushinteger(lua, (lua_Integer)ca_stream->ecm_pid);
        lua_setfield(lua, -2, "ecm_pid");

        lua_pushinteger(lua, (lua_Integer)ca_stream->ecm_type);
        lua_setfield(lua, -2, "ecm_type");

        lua_pushboolean(lua, ca_stream->is_keys);
        lua_setfield(lua, -2, "is_keys");

        lua_pushboolean(lua, ca_stream->last_ecm_ok);
        lua_setfield(lua, -2, "last_ecm_ok");

        lua_pushinteger(lua, (lua_Integer)ca_stream->ecm_fail_count);
        lua_setfield(lua, -2, "ecm_fail_count");

        if(ca_stream->last_ecm_send_us)
        {
            lua_pushinteger(lua, (lua_Integer)((now_us - ca_stream->last_ecm_send_us) / 1000ULL));
            lua_setfield(lua, -2, "last_ecm_send_ago_ms");
        }

        if(ca_stream->last_ecm_ok_us)
        {
            lua_pushinteger(lua, (lua_Integer)((now_us - ca_stream->last_ecm_ok_us) / 1000ULL));
            lua_setfield(lua, -2, "last_ecm_ok_ago_ms");
        }

        lua_newtable(lua);
        lua_pushinteger(lua, (lua_Integer)ca_stream->stat_ecm_sent);
        lua_setfield(lua, -2, "sent");
        lua_pushinteger(lua, (lua_Integer)ca_stream->stat_ecm_retry);
        lua_setfield(lua, -2, "retry");
        lua_pushinteger(lua, (lua_Integer)ca_stream->stat_ecm_ok);
        lua_setfield(lua, -2, "ok");
        lua_pushinteger(lua, (lua_Integer)ca_stream->stat_ecm_ok_primary);
        lua_setfield(lua, -2, "ok_primary");
        lua_pushinteger(lua, (lua_Integer)ca_stream->stat_ecm_ok_backup);
        lua_setfield(lua, -2, "ok_backup");
        lua_pushinteger(lua, (lua_Integer)ca_stream->stat_ecm_not_found);
        lua_setfield(lua, -2, "not_found");
        lua_pushinteger(lua, (lua_Integer)ca_stream->stat_rtt_count);
        lua_setfield(lua, -2, "rtt_count");
        if(ca_stream->stat_rtt_count)
        {
            lua_pushinteger(lua, (lua_Integer)(ca_stream->stat_rtt_sum_ms / ca_stream->stat_rtt_count));
            lua_setfield(lua, -2, "rtt_avg_ms");
        }
        if(ca_stream->stat_rtt_min_ms)
        {
            lua_pushinteger(lua, (lua_Integer)ca_stream->stat_rtt_min_ms);
            lua_setfield(lua, -2, "rtt_min_ms");
        }
        if(ca_stream->stat_rtt_max_ms)
        {
            lua_pushinteger(lua, (lua_Integer)ca_stream->stat_rtt_max_ms);
            lua_setfield(lua, -2, "rtt_max_ms");
        }
        lua_newtable(lua);
        lua_pushinteger(lua, (lua_Integer)ca_stream->stat_rtt_hist[0]);
        lua_setfield(lua, -2, "le50");
        lua_pushinteger(lua, (lua_Integer)ca_stream->stat_rtt_hist[1]);
        lua_setfield(lua, -2, "le100");
        lua_pushinteger(lua, (lua_Integer)ca_stream->stat_rtt_hist[2]);
        lua_setfield(lua, -2, "le250");
        lua_pushinteger(lua, (lua_Integer)ca_stream->stat_rtt_hist[3]);
        lua_setfield(lua, -2, "le500");
        lua_pushinteger(lua, (lua_Integer)ca_stream->stat_rtt_hist[4]);
        lua_setfield(lua, -2, "gt500");
        lua_setfield(lua, -2, "rtt_hist");
        lua_setfield(lua, -2, "ecm");

        lua_newtable(lua);
        lua_pushboolean(lua, ca_stream->cand_pending);
        lua_setfield(lua, -2, "pending");
        lua_pushinteger(lua, (lua_Integer)ca_stream->cand_mask);
        lua_setfield(lua, -2, "mask");
        lua_pushinteger(lua, (lua_Integer)ca_stream->cand_ok_count);
        lua_setfield(lua, -2, "ok_count");
        lua_pushinteger(lua, (lua_Integer)ca_stream->cand_fail_count);
        lua_setfield(lua, -2, "fail_count");
        if(ca_stream->cand_set_us)
        {
            lua_pushinteger(lua, (lua_Integer)((now_us - ca_stream->cand_set_us) / 1000ULL));
            lua_setfield(lua, -2, "age_ms");
        }
        lua_setfield(lua, -2, "candidate");

        lua_rawseti(lua, -2, idx);
        idx += 1;
    }
    lua_setfield(lua, -2, "ca_streams");

    return 1;
}

MODULE_STREAM_METHODS()
MODULE_LUA_METHODS()
{
    MODULE_STREAM_METHODS_REF(),
    { "stats", method_stats },
    { NULL, NULL },
};
MODULE_LUA_REGISTER(decrypt)
