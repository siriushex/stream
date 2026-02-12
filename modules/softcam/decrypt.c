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
 *      cam_backup  - object, optional backup cam instance
 *      cam_backup_mode - string: race|hedge|failover
 *      cam_backup_hedge_ms - number: backup ECM delay for hedge/failover
 *      cam_prefer_primary_ms - number: hold backup CW waiting for primary
 *      descramble_parallel - string: off|per_stream_thread (opt-in)
 *      descramble_batch_packets - number: batch size in TS packets (default 64)
 *      descramble_queue_depth_batches - number: input queue depth in batches (default 16)
 *      descramble_worker_stack_kb - number: pthread stack size for worker (default 256)
 *      descramble_drop_policy - string: drop_oldest|drop_newest (default drop_oldest)
 *      descramble_log_rate_limit_sec - number: rate limit for overflow logs (default 5)
 *      cas_data    - string, additional paramters for CAS
 *      cas_pnr     - number, original PNR
 */

#include <astra.h>
#include "module_cam.h"
#include "cas/cas_list.h"

#include <pthread.h>
#include <unistd.h>
#include <fcntl.h>
#include <errno.h>

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

/*
 * Parallel descrambling (opt-in)
 *
 * Цель: вынести CPU-heavy CSA decrypt из main loop в отдельный поток на каждый decrypt-инстанс.
 * Важно: НЕ трогаем смысл CA (ECM/CW), только исполнение decrypt части.
 */
#define DESCRAMBLE_PARALLEL_OFF 0
#define DESCRAMBLE_PARALLEL_PER_STREAM_THREAD 1

typedef struct descramble_key_ctx_t descramble_key_ctx_t;
typedef struct descramble_batch_t descramble_batch_t;

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

struct descramble_key_ctx_t
{
    volatile uint32_t refcount;

#if FFDECSA == 1
    void *ff_keys;
#elif LIBDVBCSA == 1
    struct dvbcsa_bs_key_s *even_key;
    struct dvbcsa_bs_key_s *odd_key;
#endif
};

typedef struct
{
    descramble_batch_t **items;
    uint32_t capacity;
    uint32_t size;
    uint32_t head;
    uint32_t tail;
    pthread_mutex_t mutex;
    pthread_cond_t cond;
} descramble_queue_t;

struct descramble_batch_t
{
    uint64_t seq;
    uint32_t count;
    uint32_t cap;
    uint8_t *buf; /* cap * TS_PACKET_SIZE */

    /* Per-packet key ctx (NULL for clear packets). */
    descramble_key_ctx_t **pkt_ctx;

    /* Unique key ctx references held for this batch (inc once per unique ctx). */
    descramble_key_ctx_t **held_ctx;
    uint32_t held_ctx_count;
};

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

    /* Prefer-primary hold (backup CW waits a short window) */
    asc_timer_t *prefer_primary_timer;
    cam_backup_timer_arg_t prefer_primary_timer_arg;
    bool prefer_primary_pending;
    uint8_t prefer_primary_mask;
    uint8_t prefer_primary_key[16];
    bool prefer_primary_checksum_ok;

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
    bool cand_from_backup;
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
    bool new_key_from_backup;

    uint64_t sendtime;

    /* Per-CAM health and perf */
    uint64_t stat_ecm_sent_primary;
    uint64_t stat_ecm_sent_backup;
    uint64_t stat_ecm_not_found_primary;
    uint64_t stat_ecm_not_found_backup;
    uint64_t stat_key_guard_reject_primary;
    uint64_t stat_key_guard_reject_backup;
    uint64_t stat_cw_applied_primary;
    uint64_t stat_cw_applied_backup;
    uint64_t stat_rtt_primary_ema_ms;
    uint64_t stat_rtt_backup_ema_ms;
    uint8_t backup_bad_streak;
    uint64_t backup_suspend_until_us;
    uint64_t backup_suspend_count;

    /* Parallel descramble: immutable key ctx (refcounted) */
    descramble_key_ctx_t *parallel_key;
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
    uint8_t cam_backup_mode;
    uint32_t cam_backup_hedge_ms;
    uint64_t cam_backup_hedge_us;
    uint32_t cam_prefer_primary_ms;
    uint64_t cam_prefer_primary_us;
    bool cam_backup_hedge_warned;
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

    /* Parallel CSA descramble (opt-in). */
    struct
    {
        uint8_t mode; /* DESCRAMBLE_PARALLEL_* */
        uint32_t batch_packets;
        uint32_t queue_depth_batches;
        uint32_t worker_stack_kb;
        uint8_t drop_policy; /* 0=drop_oldest, 1=drop_newest */
        uint32_t log_rate_limit_sec;

        pthread_t thread;
        bool thread_running;
        bool stop;

        int pipe_rd;
        int pipe_wr;
        asc_event_t *event;

        descramble_queue_t in_q;
        descramble_queue_t out_q;

        descramble_batch_t *current;
        uint64_t seq_next;

        /* Pool (main thread only) */
        descramble_batch_t **pool_free;
        uint32_t pool_free_count;
        uint32_t pool_total;

        /* Stats (best-effort) */
        volatile uint64_t drops;
        volatile uint64_t batches;
        volatile uint64_t decrypt_us_sum;
        volatile uint64_t decrypt_us_max;
        volatile uint64_t last_drop_log_us;
    } descramble;

    /* Base */
    mpegts_psi_t *stream[MAX_PID];
    mpegts_psi_t *pmt;
};

#define BISS_CAID 0x2600
#define MSG(_msg) "[decrypt %s] " _msg, mod->name

#define SHIFT_ASSUME_MBIT 10
#define SHIFT_MAX_BYTES (4 * 1024 * 1024)

#define CAM_BACKUP_MODE_RACE 0
#define CAM_BACKUP_MODE_HEDGE 1
#define CAM_BACKUP_MODE_FAILOVER 2

#define CAM_BACKUP_HEDGE_MAX_MS 500
#define CAM_PREFER_PRIMARY_MAX_MS 500
#define CAM_FAILOVER_TIMEOUT_DEFAULT_MS 250
#define CAM_BACKUP_SUSPEND_BAD_STREAK 3
#define CAM_BACKUP_SUSPEND_MS 10000

void ca_stream_set_keys(ca_stream_t *ca_stream, const uint8_t *even, const uint8_t *odd);

static inline uint32_t ref_inc_u32(volatile uint32_t *v)
{
    return __sync_add_and_fetch(v, 1);
}

static inline uint32_t ref_dec_u32(volatile uint32_t *v)
{
    return __sync_sub_and_fetch(v, 1);
}

static descramble_key_ctx_t * descramble_key_ctx_create_from_active(const ca_stream_t *ca_stream)
{
    descramble_key_ctx_t *ctx = (descramble_key_ctx_t *)calloc(1, sizeof(descramble_key_ctx_t));
    ctx->refcount = 1;

    uint8_t even[8] = { 0 };
    uint8_t odd[8] = { 0 };
    if(ca_stream && ca_stream->active_key_set)
    {
        memcpy(even, &ca_stream->active_key[0], 8);
        memcpy(odd, &ca_stream->active_key[8], 8);
    }

#if FFDECSA == 1
    ctx->ff_keys = get_key_struct();
    if(ctx->ff_keys)
        set_control_words(ctx->ff_keys, even, odd);
#elif LIBDVBCSA == 1
    ctx->even_key = dvbcsa_bs_key_alloc();
    ctx->odd_key = dvbcsa_bs_key_alloc();
    if(ctx->even_key)
        dvbcsa_bs_key_set(even, ctx->even_key);
    if(ctx->odd_key)
        dvbcsa_bs_key_set(odd, ctx->odd_key);
#endif
    return ctx;
}

static void descramble_key_ctx_destroy(descramble_key_ctx_t *ctx)
{
    if(!ctx)
        return;
#if FFDECSA == 1
    if(ctx->ff_keys)
        free_key_struct(ctx->ff_keys);
    ctx->ff_keys = NULL;
#elif LIBDVBCSA == 1
    if(ctx->even_key)
        dvbcsa_bs_key_free(ctx->even_key);
    if(ctx->odd_key)
        dvbcsa_bs_key_free(ctx->odd_key);
    ctx->even_key = NULL;
    ctx->odd_key = NULL;
#endif
    free(ctx);
}

static inline void descramble_key_ctx_acquire(descramble_key_ctx_t *ctx)
{
    if(ctx)
        ref_inc_u32(&ctx->refcount);
}

static inline void descramble_key_ctx_release(descramble_key_ctx_t *ctx)
{
    if(!ctx)
        return;
    if(ref_dec_u32(&ctx->refcount) == 0)
        descramble_key_ctx_destroy(ctx);
}

static void descramble_queue_init(descramble_queue_t *q, uint32_t capacity)
{
    memset(q, 0, sizeof(*q));
    q->capacity = capacity;
    q->items = (descramble_batch_t **)calloc(capacity, sizeof(descramble_batch_t *));
    pthread_mutex_init(&q->mutex, NULL);
    pthread_cond_init(&q->cond, NULL);
}

static void descramble_queue_destroy(descramble_queue_t *q)
{
    if(!q)
        return;
    if(q->items)
        free(q->items);
    q->items = NULL;
    pthread_mutex_destroy(&q->mutex);
    pthread_cond_destroy(&q->cond);
    memset(q, 0, sizeof(*q));
}

static inline bool descramble_queue_is_full(const descramble_queue_t *q)
{
    return q->size >= q->capacity;
}

static inline bool descramble_queue_is_empty(const descramble_queue_t *q)
{
    return q->size == 0;
}

static inline void descramble_queue_push_nolock(descramble_queue_t *q, descramble_batch_t *b)
{
    q->items[q->tail] = b;
    q->tail = (q->tail + 1) % q->capacity;
    q->size += 1;
}

static inline descramble_batch_t * descramble_queue_pop_nolock(descramble_queue_t *q)
{
    if(q->size == 0)
        return NULL;
    descramble_batch_t *b = q->items[q->head];
    q->items[q->head] = NULL;
    q->head = (q->head + 1) % q->capacity;
    q->size -= 1;
    return b;
}

static void descramble_batch_release_keys(descramble_batch_t *b)
{
    if(!b)
        return;
    for(uint32_t i = 0; i < b->held_ctx_count; ++i)
    {
        if(b->held_ctx[i])
            descramble_key_ctx_release(b->held_ctx[i]);
        b->held_ctx[i] = NULL;
    }
    b->held_ctx_count = 0;
}

static inline void descramble_batch_reset(descramble_batch_t *b)
{
    if(!b)
        return;
    b->count = 0;
    /* pkt_ctx[] is overwritten for indices < count, no need to memset. */
}

static descramble_batch_t * descramble_pool_get(module_data_t *mod)
{
    if(!mod || mod->descramble.pool_free_count == 0)
        return NULL;
    descramble_batch_t *b = mod->descramble.pool_free[--mod->descramble.pool_free_count];
    descramble_batch_reset(b);
    return b;
}

static void descramble_pool_put(module_data_t *mod, descramble_batch_t *b)
{
    if(!mod || !b)
        return;
    descramble_batch_release_keys(b);
    descramble_batch_reset(b);
    if(mod->descramble.pool_free_count < mod->descramble.pool_total)
        mod->descramble.pool_free[mod->descramble.pool_free_count++] = b;
}

static bool descramble_start(module_data_t *mod);
static void descramble_stop(module_data_t *mod);
static void descramble_queue_ts(module_data_t *mod, const uint8_t *ts);
static void descramble_flush_current(module_data_t *mod);

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
    ca_stream->prefer_primary_timer_arg.mod = mod;
    ca_stream->prefer_primary_timer_arg.stream = ca_stream;

#if FFDECSA == 1

    ca_stream->keys = get_key_struct();
    ca_stream->batch = calloc(mod->batch_size * 2 + 2, sizeof(uint8_t *));

#elif LIBDVBCSA == 1

    ca_stream->even_key = dvbcsa_bs_key_alloc();
    ca_stream->odd_key = dvbcsa_bs_key_alloc();
    ca_stream->batch = calloc(mod->batch_size + 1, sizeof(struct dvbcsa_bs_batch_s));

#endif

    asc_list_insert_tail(mod->ca_list, ca_stream);

    if(mod && mod->descramble.mode == DESCRAMBLE_PARALLEL_PER_STREAM_THREAD)
    {
        ca_stream->parallel_key = descramble_key_ctx_create_from_active(ca_stream);
    }

    return ca_stream;
}

void ca_stream_destroy(ca_stream_t *ca_stream)
{
    if(ca_stream->backup_timer)
    {
        asc_timer_destroy(ca_stream->backup_timer);
        ca_stream->backup_timer = NULL;
    }
    if(ca_stream->prefer_primary_timer)
    {
        asc_timer_destroy(ca_stream->prefer_primary_timer);
        ca_stream->prefer_primary_timer = NULL;
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

    if(ca_stream->parallel_key)
    {
        descramble_key_ctx_release(ca_stream->parallel_key);
        ca_stream->parallel_key = NULL;
    }

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

static void ca_stream_guard_set_candidate(ca_stream_t *ca_stream, const uint8_t *key16, uint8_t mask, bool allow_initial, bool from_backup);
static void ca_stream_apply_staged_key_parallel(module_data_t *mod, ca_stream_t *ca_stream);

static inline const char *cam_backup_mode_name(uint8_t mode)
{
    switch(mode)
    {
        case CAM_BACKUP_MODE_RACE:
            return "race";
        case CAM_BACKUP_MODE_FAILOVER:
            return "failover";
        case CAM_BACKUP_MODE_HEDGE:
        default:
            return "hedge";
    }
}

static uint8_t cam_backup_mode_parse(const char *mode)
{
    if(!mode || mode[0] == '\0')
        return CAM_BACKUP_MODE_HEDGE;
    if(!strcasecmp(mode, "race"))
        return CAM_BACKUP_MODE_RACE;
    if(!strcasecmp(mode, "failover"))
        return CAM_BACKUP_MODE_FAILOVER;
    if(!strcasecmp(mode, "hedge"))
        return CAM_BACKUP_MODE_HEDGE;
    return CAM_BACKUP_MODE_HEDGE;
}

static inline bool ca_stream_backup_is_suspended(ca_stream_t *ca_stream, uint64_t now_us)
{
    if(!ca_stream->backup_suspend_until_us)
        return false;
    if(now_us >= ca_stream->backup_suspend_until_us)
    {
        ca_stream->backup_suspend_until_us = 0;
        ca_stream->backup_bad_streak = 0;
        return false;
    }
    return true;
}

static inline void ca_stream_backup_mark_good(ca_stream_t *ca_stream)
{
    ca_stream->backup_bad_streak = 0;
}

static void ca_stream_backup_mark_bad(module_data_t *mod, ca_stream_t *ca_stream, const char *reason)
{
    if(!mod->dual_cam)
        return;

    if(ca_stream->backup_bad_streak < 255)
        ca_stream->backup_bad_streak += 1;

    if(ca_stream->backup_bad_streak < CAM_BACKUP_SUSPEND_BAD_STREAK)
        return;

    const uint64_t now_us = asc_utime();
    ca_stream->backup_suspend_until_us = now_us + (uint64_t)CAM_BACKUP_SUSPEND_MS * 1000ULL;
    ca_stream->backup_suspend_count += 1;
    ca_stream->backup_bad_streak = 0;
    asc_log_warning(MSG("cam_backup suspended for %dms (reason: %s)"),
                    CAM_BACKUP_SUSPEND_MS, reason ? reason : "bad_response");
}

static inline void ca_stream_stat_rtt_cam(ca_stream_t *ca_stream, bool is_backup, uint64_t ms)
{
    uint64_t *ema = is_backup ? &ca_stream->stat_rtt_backup_ema_ms : &ca_stream->stat_rtt_primary_ema_ms;
    if(*ema == 0)
        *ema = ms;
    else
        *ema = ((*ema * 7ULL) + ms) / 8ULL;
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

static void ca_stream_cancel_backup_send(ca_stream_t *ca_stream)
{
    if(ca_stream->backup_timer)
    {
        asc_timer_destroy(ca_stream->backup_timer);
        ca_stream->backup_timer = NULL;
    }
    ca_stream->backup_ecm_pending = false;
}

static void ca_stream_cancel_prefer_primary(ca_stream_t *ca_stream)
{
    if(ca_stream->prefer_primary_timer)
    {
        asc_timer_destroy(ca_stream->prefer_primary_timer);
        ca_stream->prefer_primary_timer = NULL;
    }
    ca_stream->prefer_primary_pending = false;
    ca_stream->prefer_primary_mask = 0;
}

static void ca_stream_stage_new_key(ca_stream_t *ca_stream, const uint8_t *key16, uint8_t mask, bool from_backup)
{
    ca_stream->new_key_id = mask;
    ca_stream->new_key_from_backup = from_backup;
    if(mask & 0x01)
        memcpy(&ca_stream->new_key[0], &key16[0], 8);
    if(mask & 0x02)
        memcpy(&ca_stream->new_key[8], &key16[8], 8);
}

static bool ca_stream_send_backup_pending(module_data_t *mod, ca_stream_t *ca_stream)
{
    if(!mod->cam_backup || !mod->cam_backup->is_ready)
        return false;
    if(ca_stream_backup_is_suspended(ca_stream, asc_utime()))
        return false;
    if(!ca_stream->backup_ecm_buf || ca_stream->backup_ecm_len == 0)
        return false;

    mod->cam_backup->send_em(mod->cam_backup->self, &mod->__decrypt, &ca_stream->arg_backup,
                             ca_stream->backup_ecm_buf, ca_stream->backup_ecm_len);
    ca_stream->sendtime_backup = asc_utime();
    ca_stream->stat_ecm_sent_backup += 1;
    return true;
}

static void ca_stream_apply_keys_from_cam(module_data_t *mod, ca_stream_t *ca_stream, const uint8_t *key16, uint8_t mask, bool is_backup, bool is_cw_checksum_ok)
{
    if(mask == 0)
        mask = 3;

    if(ca_stream->active_key_set && memcmp(key16, ca_stream->active_key, sizeof(ca_stream->active_key)) == 0)
    {
        /* Avoid staging/reapplying identical keys (common with redundant CAM responses). */
        return;
    }

    if(!ca_stream->is_keys)
        ca_stream->is_keys = true;

    if(mod->key_guard && (mod->dual_cam || ca_stream->active_key_set))
    {
        /* Guarded switch: validate candidate keys on PES headers before applying. */
        ca_stream_guard_set_candidate(ca_stream, key16, mask, mod->dual_cam, is_backup);
        if(!is_cw_checksum_ok && asc_log_is_debug())
            asc_log_debug(MSG("key_guard: candidate keys staged (checksum mismatch)"));
    }
    else
    {
        /* Immediate apply path (legacy behavior) */
        ca_stream_stage_new_key(ca_stream, key16, mask, is_backup);
        if(mod && mod->descramble.mode == DESCRAMBLE_PARALLEL_PER_STREAM_THREAD)
            ca_stream_apply_staged_key_parallel(mod, ca_stream);
        if(mask == 3 && ca_stream->active_key_set && asc_log_is_debug())
            asc_log_debug(MSG("Both keys changed"));
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

    ca_stream_send_backup_pending(mod, ca_stream);
}

static void on_cam_prefer_primary(void *arg)
{
    cam_backup_timer_arg_t *ctx = (cam_backup_timer_arg_t *)arg;
    if(!ctx || !ctx->mod || !ctx->stream)
        return;

    module_data_t *mod = ctx->mod;
    ca_stream_t *ca_stream = ctx->stream;
    ca_stream->prefer_primary_timer = NULL;

    if(!ca_stream->prefer_primary_pending || ca_stream->prefer_primary_mask == 0)
        return;

    ca_stream->prefer_primary_pending = false;
    ca_stream_apply_keys_from_cam(mod,
                                  ca_stream,
                                  ca_stream->prefer_primary_key,
                                  ca_stream->prefer_primary_mask,
                                  true,
                                  ca_stream->prefer_primary_checksum_ok);
}

static void ca_stream_guard_clear(ca_stream_t *ca_stream)
{
    ca_stream->cand_pending = false;
    ca_stream->cand_mask = 0;
    ca_stream->cand_from_backup = false;
    ca_stream->cand_set_us = 0;
    ca_stream->cand_ok_count = 0;
    ca_stream->cand_fail_count = 0;
}

static void ca_stream_parallel_key_replace(ca_stream_t *ca_stream)
{
    if(!ca_stream)
        return;
    descramble_key_ctx_t *new_ctx = descramble_key_ctx_create_from_active(ca_stream);
    descramble_key_ctx_t *old_ctx = ca_stream->parallel_key;
    ca_stream->parallel_key = new_ctx;
    if(old_ctx)
        descramble_key_ctx_release(old_ctx);
}

static void ca_stream_apply_staged_key_parallel(module_data_t *mod, ca_stream_t *ca_stream)
{
    if(!mod || !ca_stream)
        return;
    if(mod->descramble.mode != DESCRAMBLE_PARALLEL_PER_STREAM_THREAD)
        return;
    if(ca_stream->new_key_id == 0)
        return;

    bool applied_key = false;
    const bool applied_from_backup = ca_stream->new_key_from_backup;
    switch(ca_stream->new_key_id)
    {
        case 1:
            ca_stream_set_active_key(ca_stream, 1, ca_stream->new_key);
            ca_stream_guard_clear(ca_stream);
            applied_key = true;
            break;
        case 2:
            ca_stream_set_active_key(ca_stream, 2, ca_stream->new_key);
            ca_stream_guard_clear(ca_stream);
            applied_key = true;
            break;
        case 3:
            ca_stream_set_active_key(ca_stream, 3, ca_stream->new_key);
            ca_stream_guard_clear(ca_stream);
            applied_key = true;
            break;
        default:
            break;
    }

    ca_stream->new_key_id = 0;
    ca_stream->new_key_from_backup = false;

    if(applied_key)
    {
        ca_stream_parallel_key_replace(ca_stream);
        if(applied_from_backup)
        {
            ca_stream->stat_cw_applied_backup += 1;
            ca_stream_backup_mark_good(ca_stream);
        }
        else
        {
            ca_stream->stat_cw_applied_primary += 1;
        }
    }
}

static void ca_stream_guard_set_candidate(ca_stream_t *ca_stream, const uint8_t *key16, uint8_t mask, bool allow_initial, bool from_backup)
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
    ca_stream->cand_from_backup = from_backup;
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
    /*
     * Parallel descramble: restart worker on reload to avoid mixing old buffers
     * and to guarantee we don't have in-flight batches referencing stale PSI state.
     * Reloads are rare (PAT/PMT change, CAM ready/error), so restart cost is acceptable.
     */
    if(mod->descramble.mode == DESCRAMBLE_PARALLEL_PER_STREAM_THREAD)
        descramble_stop(mod);

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

    if(mod->descramble.mode == DESCRAMBLE_PARALLEL_PER_STREAM_THREAD)
    {
        if(!descramble_start(mod))
        {
            asc_log_error(MSG("descramble_parallel failed to start, falling back to off"));
            mod->descramble.mode = DESCRAMBLE_PARALLEL_OFF;
        }
    }
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

    /* In parallel mode keep TS order: PMT output must go through the same queue as A/V packets. */
    void (*pmt_send_cb)(void *, const uint8_t *) = (void (*)(void *, const uint8_t *))__module_stream_send;
    void *pmt_send_arg = &mod->__stream;
    if(mod->descramble.mode == DESCRAMBLE_PARALLEL_PER_STREAM_THREAD)
    {
        pmt_send_cb = (void (*)(void *, const uint8_t *))descramble_queue_ts;
        pmt_send_arg = mod;
    }

    // check pnr
    const uint16_t pnr = PMT_GET_PNR(psi);
    if(pnr != mod->__decrypt.pnr)
        return;

    // check changes
    const uint32_t crc32 = PSI_GET_CRC32(psi);
    if(crc32 == psi->crc32)
    {
        mpegts_psi_demux(mod->pmt, pmt_send_cb, pmt_send_arg);
        if(mod->descramble.mode == DESCRAMBLE_PARALLEL_PER_STREAM_THREAD)
            descramble_flush_current(mod);
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

    mpegts_psi_demux(mod->pmt, pmt_send_cb, pmt_send_arg);
    if(mod->descramble.mode == DESCRAMBLE_PARALLEL_PER_STREAM_THREAD)
        descramble_flush_current(mod);
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
    if(is_ecm && ca_stream->prefer_primary_pending)
        ca_stream_cancel_prefer_primary(ca_stream);

    bool sent_primary = false;
    bool sent = false;
    const uint64_t now_us = asc_utime();
    if(mod->cam_primary && mod->cam_primary->is_ready)
    {
        if(em_type < 0x82 || em_type > 0x8F || !mod->cam_primary->disable_emm)
        {
            mod->cam_primary->send_em(mod->cam_primary->self, &mod->__decrypt, &ca_stream->arg_primary,
                                      psi->buffer, psi->buffer_size);
            ca_stream->sendtime_primary = asc_utime();
            if(is_ecm)
                ca_stream->stat_ecm_sent_primary += 1;
            sent_primary = true;
            sent = true;
        }
    }
    if(mod->cam_backup && mod->cam_backup->is_ready)
    {
        if(em_type < 0x82 || em_type > 0x8F || !mod->cam_backup->disable_emm)
        {
            if(is_ecm && ca_stream_backup_is_suspended(ca_stream, now_us))
            {
                __uarg(sent);
                return;
            }

            if(is_ecm)
            {
                if(mod->cam_backup_mode == CAM_BACKUP_MODE_FAILOVER && sent_primary)
                {
                    const uint32_t timeout_ms = (mod->cam_backup_hedge_ms > 0)
                        ? mod->cam_backup_hedge_ms
                        : CAM_FAILOVER_TIMEOUT_DEFAULT_MS;
                    ca_stream_cancel_backup_send(ca_stream);
                    ca_stream->backup_ecm_buf = realloc(ca_stream->backup_ecm_buf, psi->buffer_size);
                    if(ca_stream->backup_ecm_buf)
                    {
                        memcpy(ca_stream->backup_ecm_buf, psi->buffer, psi->buffer_size);
                        ca_stream->backup_ecm_len = psi->buffer_size;
                        ca_stream->backup_ecm_pending = true;
                        ca_stream->backup_timer = asc_timer_one_shot(timeout_ms,
                                                                     on_cam_backup_hedge,
                                                                     &ca_stream->backup_timer_arg);
                        sent = true;
                    }
                    return;
                }

                if(mod->cam_backup_mode == CAM_BACKUP_MODE_HEDGE && sent_primary)
                {
                    if(mod->cam_backup_hedge_ms == 0 && !mod->cam_backup_hedge_warned)
                    {
                        mod->cam_backup_hedge_warned = true;
                        asc_log_warning(MSG("cam_backup_mode=hedge with cam_backup_hedge_ms=0 behaves like race"));
                    }

                    if(mod->cam_backup_hedge_ms > 0)
                    {
                        ca_stream_cancel_backup_send(ca_stream);
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
                            return;
                        }
                    }
                }
            }

            if(is_ecm && mod->cam_backup_mode == CAM_BACKUP_MODE_FAILOVER && sent_primary)
                return;

            ca_stream_cancel_backup_send(ca_stream);
            mod->cam_backup->send_em(mod->cam_backup->self, &mod->__decrypt, &ca_stream->arg_backup,
                                     psi->buffer, psi->buffer_size);
            ca_stream->sendtime_backup = asc_utime();
            if(is_ecm)
                ca_stream->stat_ecm_sent_backup += 1;
            sent = true;
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

static void descramble_decrypt_batch(module_data_t *mod, descramble_batch_t *b)
{
    if(!mod || !b || b->count == 0)
        return;

#if FFDECSA == 1
    /* FFdecsa: cluster is list of ranges [start,end,start,end,...,NULL]. */
    for(uint32_t h = 0; h < b->held_ctx_count; ++h)
    {
        descramble_key_ctx_t *ctx = b->held_ctx[h];
        if(!ctx || !ctx->ff_keys)
            continue;

        unsigned char *cluster[(2 * 1024) + 1];
        const uint32_t max_ranges = (uint32_t)((sizeof(cluster) / sizeof(cluster[0]) - 1) / 2);
        uint32_t ranges = 0;
        for(uint32_t i = 0; i < b->count && ranges < max_ranges; ++i)
        {
            if(b->pkt_ctx[i] != ctx)
                continue;
            unsigned char *pkt = (unsigned char *)&b->buf[i * TS_PACKET_SIZE];
            cluster[ranges * 2] = pkt;
            cluster[ranges * 2 + 1] = pkt + TS_PACKET_SIZE;
            ranges += 1;
        }
        cluster[ranges * 2] = NULL;

        size_t done = 0;
        const size_t total = ranges;
        while(done < total)
            done += decrypt_packets(ctx->ff_keys, cluster);
    }

#elif LIBDVBCSA == 1
    /* dvbcsa: group payloads by key ctx and parity (even/odd). */
    struct dvbcsa_bs_batch_s even_batch[1024 + 1];
    struct dvbcsa_bs_batch_s odd_batch[1024 + 1];

    for(uint32_t h = 0; h < b->held_ctx_count; ++h)
    {
        descramble_key_ctx_t *ctx = b->held_ctx[h];
        if(!ctx || !ctx->even_key || !ctx->odd_key)
            continue;

        uint32_t even_n = 0;
        uint32_t odd_n = 0;

        for(uint32_t i = 0; i < b->count; ++i)
        {
            if(b->pkt_ctx[i] != ctx)
                continue;

            uint8_t *pkt = &b->buf[i * TS_PACKET_SIZE];
            const uint8_t sc = TS_IS_SCRAMBLED(pkt);
            if(!sc)
                continue;

            int hdr_size = 0;
            if(TS_IS_PAYLOAD(pkt))
            {
                if(TS_IS_AF(pkt))
                    hdr_size = 4 + pkt[4] + 1;
                else
                    hdr_size = 4;
            }
            if(hdr_size <= 0 || hdr_size >= TS_PACKET_SIZE)
                continue;

            pkt[3] &= ~0xC0;

            if(sc == 0x80)
            {
                even_batch[even_n].data = &pkt[hdr_size];
                even_batch[even_n].len = TS_PACKET_SIZE - hdr_size;
                even_n += 1;
            }
            else if(sc == 0xC0)
            {
                odd_batch[odd_n].data = &pkt[hdr_size];
                odd_batch[odd_n].len = TS_PACKET_SIZE - hdr_size;
                odd_n += 1;
            }
        }

        even_batch[even_n].data = NULL;
        odd_batch[odd_n].data = NULL;

        if(even_n)
            dvbcsa_bs_decrypt(ctx->even_key, even_batch, TS_BODY_SIZE);
        if(odd_n)
            dvbcsa_bs_decrypt(ctx->odd_key, odd_batch, TS_BODY_SIZE);
    }
#endif
}

static void descramble_signal_main(module_data_t *mod)
{
    if(!mod || mod->descramble.pipe_wr == -1)
        return;
    const uint8_t b = 0x01;
    const ssize_t w = write(mod->descramble.pipe_wr, &b, 1);
    __uarg(w);
}

static void descramble_out_drain(module_data_t *mod)
{
    if(!mod)
        return;
    while(true)
    {
        pthread_mutex_lock(&mod->descramble.out_q.mutex);
        descramble_batch_t *b = descramble_queue_pop_nolock(&mod->descramble.out_q);
        if(b)
            pthread_cond_signal(&mod->descramble.out_q.cond);
        pthread_mutex_unlock(&mod->descramble.out_q.mutex);
        if(!b)
            break;

        for(uint32_t i = 0; i < b->count; ++i)
        {
            __module_stream_send(&mod->__stream, &b->buf[i * TS_PACKET_SIZE]);
        }

        descramble_pool_put(mod, b);
    }
}

static void descramble_event_read(void *arg)
{
    module_data_t *mod = (module_data_t *)arg;
    if(!mod)
        return;

    /* Drain pipe to clear readability. */
    uint8_t tmp[64];
    while(true)
    {
        const ssize_t r = read(mod->descramble.pipe_rd, tmp, sizeof(tmp));
        if(r > 0)
            continue;
        if(r == -1 && (errno == EAGAIN || errno == EWOULDBLOCK))
            break;
        break;
    }

    descramble_out_drain(mod);
}

static void * descramble_thread_main(void *arg)
{
    module_data_t *mod = (module_data_t *)arg;
    if(!mod)
        return NULL;

#if defined(__linux__)
    pthread_setname_np(pthread_self(), "descramble");
#elif defined(__APPLE__)
    pthread_setname_np("descramble");
#endif

    while(true)
    {
        pthread_mutex_lock(&mod->descramble.in_q.mutex);
        while(descramble_queue_is_empty(&mod->descramble.in_q) && !mod->descramble.stop)
            pthread_cond_wait(&mod->descramble.in_q.cond, &mod->descramble.in_q.mutex);

        if(mod->descramble.stop)
        {
            pthread_mutex_unlock(&mod->descramble.in_q.mutex);
            break;
        }

        descramble_batch_t *b = descramble_queue_pop_nolock(&mod->descramble.in_q);
        pthread_mutex_unlock(&mod->descramble.in_q.mutex);
        if(!b)
            continue;

        const uint64_t t0 = asc_utime();
        descramble_decrypt_batch(mod, b);
        const uint64_t dt = asc_utime() - t0;
        __sync_add_and_fetch(&mod->descramble.batches, 1);
        __sync_add_and_fetch(&mod->descramble.decrypt_us_sum, dt);
        uint64_t prev_max = mod->descramble.decrypt_us_max;
        while(dt > prev_max)
        {
            if(__sync_bool_compare_and_swap(&mod->descramble.decrypt_us_max, prev_max, dt))
                break;
            prev_max = mod->descramble.decrypt_us_max;
        }

        descramble_batch_release_keys(b);

        pthread_mutex_lock(&mod->descramble.out_q.mutex);
        while(descramble_queue_is_full(&mod->descramble.out_q) && !mod->descramble.stop)
            pthread_cond_wait(&mod->descramble.out_q.cond, &mod->descramble.out_q.mutex);
        if(!descramble_queue_is_full(&mod->descramble.out_q))
            descramble_queue_push_nolock(&mod->descramble.out_q, b);
        pthread_mutex_unlock(&mod->descramble.out_q.mutex);

        descramble_signal_main(mod);
    }

    return NULL;
}

static bool descramble_set_fd_nonblock_cloexec(int fd)
{
    if(fd < 0)
        return false;

    int flags = fcntl(fd, F_GETFL, 0);
    if(flags == -1)
        return false;
    if(fcntl(fd, F_SETFL, flags | O_NONBLOCK) == -1)
        return false;

    int fdflags = fcntl(fd, F_GETFD, 0);
    if(fdflags == -1)
        return false;
    if(fcntl(fd, F_SETFD, fdflags | FD_CLOEXEC) == -1)
        return false;

    return true;
}

static void descramble_free_pool(module_data_t *mod)
{
    if(!mod || !mod->descramble.pool_free)
        return;

    for(uint32_t i = 0; i < mod->descramble.pool_free_count; ++i)
    {
        descramble_batch_t *b = mod->descramble.pool_free[i];
        if(!b)
            continue;
        if(b->buf)
            free(b->buf);
        if(b->pkt_ctx)
            free(b->pkt_ctx);
        if(b->held_ctx)
            free(b->held_ctx);
        free(b);
        mod->descramble.pool_free[i] = NULL;
    }

    free(mod->descramble.pool_free);
    mod->descramble.pool_free = NULL;
    mod->descramble.pool_free_count = 0;
    mod->descramble.pool_total = 0;
}

static void descramble_drain_queue_to_pool(module_data_t *mod, descramble_queue_t *q)
{
    if(!mod || !q)
        return;
    while(true)
    {
        descramble_batch_t *b = descramble_queue_pop_nolock(q);
        if(!b)
            break;
        descramble_pool_put(mod, b);
    }
}

static bool descramble_start(module_data_t *mod)
{
    if(!mod)
        return false;
    if(mod->descramble.mode != DESCRAMBLE_PARALLEL_PER_STREAM_THREAD)
        return true;
    if(mod->descramble.thread_running)
        return true;

    /* Reset runtime state (keep config values). */
    mod->descramble.stop = false;
    mod->descramble.drops = 0;
    mod->descramble.batches = 0;
    mod->descramble.decrypt_us_sum = 0;
    mod->descramble.decrypt_us_max = 0;
    mod->descramble.last_drop_log_us = 0;
    mod->descramble.seq_next = 1;
    mod->descramble.current = NULL;

    /* Pipe for worker->main notifications. */
    int fds[2] = { -1, -1 };
    if(pipe(fds) != 0)
    {
        asc_log_error(MSG("descramble: pipe() failed: %s"), strerror(errno));
        return false;
    }
    mod->descramble.pipe_rd = fds[0];
    mod->descramble.pipe_wr = fds[1];
    if(!descramble_set_fd_nonblock_cloexec(mod->descramble.pipe_rd)
       || !descramble_set_fd_nonblock_cloexec(mod->descramble.pipe_wr))
    {
        asc_log_error(MSG("descramble: fcntl() failed: %s"), strerror(errno));
        close(mod->descramble.pipe_rd);
        close(mod->descramble.pipe_wr);
        mod->descramble.pipe_rd = -1;
        mod->descramble.pipe_wr = -1;
        return false;
    }

    /* Pool and queues. */
    mod->descramble.pool_total = mod->descramble.queue_depth_batches * 2 + 4;
    if(mod->descramble.pool_total < 8)
        mod->descramble.pool_total = 8;

    descramble_queue_init(&mod->descramble.in_q, mod->descramble.queue_depth_batches);
    descramble_queue_init(&mod->descramble.out_q, mod->descramble.pool_total);

    mod->descramble.pool_free = (descramble_batch_t **)calloc(mod->descramble.pool_total, sizeof(descramble_batch_t *));
    mod->descramble.pool_free_count = 0;
    for(uint32_t i = 0; i < mod->descramble.pool_total; ++i)
    {
        descramble_batch_t *b = (descramble_batch_t *)calloc(1, sizeof(descramble_batch_t));
        if(!b)
            break;
        b->cap = mod->descramble.batch_packets;
        b->buf = (uint8_t *)malloc((size_t)b->cap * TS_PACKET_SIZE);
        b->pkt_ctx = (descramble_key_ctx_t **)calloc(b->cap, sizeof(descramble_key_ctx_t *));
        b->held_ctx = (descramble_key_ctx_t **)calloc(b->cap, sizeof(descramble_key_ctx_t *));
        if(!b->buf || !b->pkt_ctx || !b->held_ctx)
        {
            if(b->buf)
                free(b->buf);
            if(b->pkt_ctx)
                free(b->pkt_ctx);
            if(b->held_ctx)
                free(b->held_ctx);
            free(b);
            break;
        }
        mod->descramble.pool_free[mod->descramble.pool_free_count++] = b;
    }

    if(mod->descramble.pool_free_count != mod->descramble.pool_total)
    {
        asc_log_error(MSG("descramble: pool alloc failed (%u/%u)"), (unsigned)mod->descramble.pool_free_count,
                      (unsigned)mod->descramble.pool_total);
        descramble_stop(mod);
        return false;
    }

    mod->descramble.event = asc_event_init(mod->descramble.pipe_rd, mod);
    if(!mod->descramble.event)
    {
        asc_log_error(MSG("descramble: asc_event_init failed"));
        descramble_stop(mod);
        return false;
    }
    asc_event_set_on_read(mod->descramble.event, descramble_event_read);

    /* Start worker thread. */
    pthread_attr_t attr;
    pthread_attr_init(&attr);
    if(mod->descramble.worker_stack_kb > 0)
    {
        size_t stack_size = (size_t)mod->descramble.worker_stack_kb * 1024U;
        if(stack_size < PTHREAD_STACK_MIN)
            stack_size = PTHREAD_STACK_MIN;
        pthread_attr_setstacksize(&attr, stack_size);
    }

    const int th_rc = pthread_create(&mod->descramble.thread, &attr, descramble_thread_main, mod);
    if(th_rc != 0)
    {
        pthread_attr_destroy(&attr);
        asc_log_error(MSG("descramble: pthread_create failed: %s"), strerror(th_rc));
        descramble_stop(mod);
        return false;
    }
    pthread_attr_destroy(&attr);

    mod->descramble.thread_running = true;
    if(asc_log_is_debug())
    {
        asc_log_debug(MSG("descramble_parallel enabled: per_stream_thread batch_packets:%u queue_depth:%u"),
                      (unsigned)mod->descramble.batch_packets,
                      (unsigned)mod->descramble.queue_depth_batches);
    }

    return true;
}

static void descramble_stop(module_data_t *mod)
{
    if(!mod)
        return;
    if(!mod->descramble.thread_running && mod->descramble.pipe_rd == -1 && mod->descramble.pipe_wr == -1)
        return;

    /* Drop current batch (module is reloading/stopping). */
    if(mod->descramble.current)
    {
        descramble_pool_put(mod, mod->descramble.current);
        mod->descramble.current = NULL;
    }

    /* Stop worker thread. */
    mod->descramble.stop = true;
    pthread_mutex_lock(&mod->descramble.in_q.mutex);
    pthread_cond_broadcast(&mod->descramble.in_q.cond);
    pthread_mutex_unlock(&mod->descramble.in_q.mutex);
    pthread_mutex_lock(&mod->descramble.out_q.mutex);
    pthread_cond_broadcast(&mod->descramble.out_q.cond);
    pthread_mutex_unlock(&mod->descramble.out_q.mutex);

    if(mod->descramble.thread_running)
    {
        pthread_join(mod->descramble.thread, NULL);
        mod->descramble.thread_running = false;
    }

    /* Drain queues back to pool (best-effort). */
    pthread_mutex_lock(&mod->descramble.out_q.mutex);
    descramble_drain_queue_to_pool(mod, &mod->descramble.out_q);
    pthread_mutex_unlock(&mod->descramble.out_q.mutex);

    pthread_mutex_lock(&mod->descramble.in_q.mutex);
    descramble_drain_queue_to_pool(mod, &mod->descramble.in_q);
    pthread_mutex_unlock(&mod->descramble.in_q.mutex);

    /* Close event before closing fds. */
    if(mod->descramble.event)
    {
        asc_event_close(mod->descramble.event);
        mod->descramble.event = NULL;
    }

    if(mod->descramble.pipe_rd != -1)
    {
        close(mod->descramble.pipe_rd);
        mod->descramble.pipe_rd = -1;
    }
    if(mod->descramble.pipe_wr != -1)
    {
        close(mod->descramble.pipe_wr);
        mod->descramble.pipe_wr = -1;
    }

    descramble_queue_destroy(&mod->descramble.in_q);
    descramble_queue_destroy(&mod->descramble.out_q);

    descramble_free_pool(mod);

    mod->descramble.stop = false;
}

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
        bool applied_key = false;
        const bool applied_from_backup = ca_stream->new_key_from_backup;
        switch(ca_stream->new_key_id)
        {
            case 0:
                break;
            case 1:
                ca_stream_set_keys(ca_stream, &ca_stream->new_key[0], NULL);
                ca_stream_set_active_key(ca_stream, 1, ca_stream->new_key);
                ca_stream_guard_clear(ca_stream);
                ca_stream->new_key_id = 0;
                applied_key = true;
                break;
            case 2:
                ca_stream_set_keys(ca_stream, NULL, &ca_stream->new_key[8]);
                ca_stream_set_active_key(ca_stream, 2, ca_stream->new_key);
                ca_stream_guard_clear(ca_stream);
                ca_stream->new_key_id = 0;
                applied_key = true;
                break;
            case 3:
                ca_stream_set_keys(  ca_stream
                                   , &ca_stream->new_key[0]
                                   , &ca_stream->new_key[8]);
                ca_stream_set_active_key(ca_stream, 3, ca_stream->new_key);
                ca_stream_guard_clear(ca_stream);
                ca_stream->new_key_id = 0;
                applied_key = true;
                break;
            default:
                ca_stream->new_key_id = 0;
                break;
        }
        if(applied_key)
        {
            if(applied_from_backup)
            {
                ca_stream->stat_cw_applied_backup += 1;
                ca_stream_backup_mark_good(ca_stream);
            }
            else
            {
                ca_stream->stat_cw_applied_primary += 1;
            }
            ca_stream->new_key_from_backup = false;
        }
    }

    mod->storage.dsc_count = mod->storage.count;
}

static void descramble_drop_log_rate_limited(module_data_t *mod, const char *reason)
{
    if(!mod)
        return;
    const uint64_t now_us = asc_utime();
    const uint64_t interval_us = (uint64_t)(mod->descramble.log_rate_limit_sec ? mod->descramble.log_rate_limit_sec : 5) * 1000000ULL;
    const uint64_t last_us = mod->descramble.last_drop_log_us;
    if(last_us != 0 && now_us - last_us < interval_us)
        return;
    if(__sync_bool_compare_and_swap(&mod->descramble.last_drop_log_us, last_us, now_us))
        asc_log_warning(MSG("descramble queue overflow: %s"), reason ? reason : "drop");
}

static void descramble_in_enqueue(module_data_t *mod, descramble_batch_t *b)
{
    if(!mod || !b)
        return;

    if(b->count == 0)
    {
        descramble_pool_put(mod, b);
        return;
    }

    b->seq = mod->descramble.seq_next++;

    pthread_mutex_lock(&mod->descramble.in_q.mutex);

    if(descramble_queue_is_full(&mod->descramble.in_q))
    {
        __sync_add_and_fetch(&mod->descramble.drops, 1);

        if(mod->descramble.drop_policy == 0 /* drop_oldest */)
        {
            descramble_batch_t *old = descramble_queue_pop_nolock(&mod->descramble.in_q);
            if(old)
                descramble_pool_put(mod, old);
            descramble_queue_push_nolock(&mod->descramble.in_q, b);
        }
        else
        {
            /* drop_newest: keep queue as-is */
            descramble_pool_put(mod, b);
        }

        descramble_drop_log_rate_limited(mod, "in_queue_full");
    }
    else
    {
        descramble_queue_push_nolock(&mod->descramble.in_q, b);
    }

    pthread_cond_signal(&mod->descramble.in_q.cond);
    pthread_mutex_unlock(&mod->descramble.in_q.mutex);
}

static inline void descramble_flush_current(module_data_t *mod)
{
    if(!mod || mod->descramble.mode != DESCRAMBLE_PARALLEL_PER_STREAM_THREAD)
        return;
    if(!mod->descramble.thread_running)
    {
        if(mod->descramble.current)
        {
            descramble_pool_put(mod, mod->descramble.current);
            mod->descramble.current = NULL;
        }
        return;
    }
    if(!mod->descramble.current)
        return;
    descramble_batch_t *b = mod->descramble.current;
    mod->descramble.current = NULL;
    descramble_in_enqueue(mod, b);
}

static void descramble_queue_ts(module_data_t *mod, const uint8_t *ts)
{
    if(!mod || !ts)
        return;
    if(mod->descramble.mode != DESCRAMBLE_PARALLEL_PER_STREAM_THREAD || !mod->descramble.thread_running)
    {
        __module_stream_send(&mod->__stream, ts);
        return;
    }

    if(!mod->descramble.current)
        mod->descramble.current = descramble_pool_get(mod);

    descramble_batch_t *b = mod->descramble.current;
    if(!b)
        return;

    if(b->count >= b->cap)
    {
        descramble_flush_current(mod);
        if(!mod->descramble.current)
            mod->descramble.current = descramble_pool_get(mod);
        b = mod->descramble.current;
        if(!b)
            return;
    }

    uint8_t *dst = &b->buf[b->count * TS_PACKET_SIZE];
    memcpy(dst, ts, TS_PACKET_SIZE);

    descramble_key_ctx_t *ctx = NULL;
    if(TS_IS_SCRAMBLED(dst) && TS_IS_PAYLOAD(dst))
    {
        const uint16_t pid = TS_GET_PID(dst);
        ca_stream_t *ca_stream = ca_stream_for_pid(mod, pid);
        if(ca_stream)
            ctx = ca_stream->parallel_key;
    }

    b->pkt_ctx[b->count] = ctx;
    if(ctx)
    {
        bool seen = false;
        for(uint32_t i = 0; i < b->held_ctx_count; ++i)
        {
            if(b->held_ctx[i] == ctx)
            {
                seen = true;
                break;
            }
        }
        if(!seen && b->held_ctx_count < b->cap)
        {
            b->held_ctx[b->held_ctx_count++] = ctx;
            descramble_key_ctx_acquire(ctx);
        }
    }

    b->count += 1;

    if(b->count >= mod->descramble.batch_packets)
        descramble_flush_current(mod);
}

static void on_ts_parallel(module_data_t *mod, const uint8_t *ts)
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
        /* Still go through parallel queue to keep ordering consistent. */
        descramble_queue_ts(mod, ts);
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
                        ca_stream_stage_new_key(ca_stream, ca_stream->cand_key, ca_stream->cand_mask, ca_stream->cand_from_backup);
                        ca_stream_apply_staged_key_parallel(mod, ca_stream);
                        if(asc_log_is_debug())
                            asc_log_debug(MSG("key_guard: candidate keys accepted (mask:%u)"), (unsigned)ca_stream->new_key_id);
                        ca_stream_guard_clear(ca_stream);
                    }
                    else if(ca_stream->cand_fail_count >= 2)
                    {
                        const bool cand_from_backup = ca_stream->cand_from_backup;
                        if(asc_log_is_debug())
                            asc_log_debug(MSG("key_guard: candidate keys rejected (mask:%u)"), (unsigned)ca_stream->cand_mask);
                        if(cand_from_backup)
                        {
                            ca_stream->stat_key_guard_reject_backup += 1;
                            ca_stream_backup_mark_bad(mod, ca_stream, "key_guard_reject");
                        }
                        else
                        {
                            ca_stream->stat_key_guard_reject_primary += 1;
                        }
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

    descramble_queue_ts(mod, ts);
}

static void on_ts(module_data_t *mod, const uint8_t *ts)
{
    if(mod->descramble.mode == DESCRAMBLE_PARALLEL_PER_STREAM_THREAD)
    {
        on_ts_parallel(mod, ts);
        return;
    }

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
                        ca_stream_stage_new_key(ca_stream, ca_stream->cand_key, ca_stream->cand_mask, ca_stream->cand_from_backup);
                        if(mod->descramble.mode == DESCRAMBLE_PARALLEL_PER_STREAM_THREAD)
                            ca_stream_apply_staged_key_parallel(mod, ca_stream);
                        if(asc_log_is_debug())
                            asc_log_debug(MSG("key_guard: candidate keys accepted (mask:%u)"), (unsigned)ca_stream->new_key_id);
                        ca_stream_guard_clear(ca_stream);
                    }
                    else if(ca_stream->cand_fail_count >= 2)
                    {
                        const bool cand_from_backup = ca_stream->cand_from_backup;
                        if(asc_log_is_debug())
                            asc_log_debug(MSG("key_guard: candidate keys rejected (mask:%u)"), (unsigned)ca_stream->cand_mask);
                        if(cand_from_backup)
                        {
                            ca_stream->stat_key_guard_reject_backup += 1;
                            ca_stream_backup_mark_bad(mod, ca_stream, "key_guard_reject");
                        }
                        else
                        {
                            ca_stream->stat_key_guard_reject_primary += 1;
                        }
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
        {
            ca_stream_stat_rtt(ca_stream, responsetime);
            ca_stream_stat_rtt_cam(ca_stream, is_backup, responsetime);
        }

        ca_stream->last_ecm_ok = true;
        ca_stream->ecm_fail_count = 0;
        ca_stream->last_ecm_ok_us = now_us;

        if(mod->dual_cam)
            module_backup_active_set(mod, is_backup, now_us);

        if(is_backup)
            ca_stream_backup_mark_good(ca_stream);

        if(!is_backup && ca_stream->backup_timer)
        {
            ca_stream_cancel_backup_send(ca_stream);
        }
        if(!is_backup && ca_stream->prefer_primary_pending)
        {
            ca_stream_cancel_prefer_primary(ca_stream);
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

        if(is_backup && mod->cam_prefer_primary_ms > 0 && mod->cam_primary && mod->cam_primary->is_ready)
        {
            ca_stream_cancel_prefer_primary(ca_stream);
            memcpy(ca_stream->prefer_primary_key, key16, sizeof(ca_stream->prefer_primary_key));
            ca_stream->prefer_primary_mask = mask;
            ca_stream->prefer_primary_checksum_ok = is_cw_checksum_ok;
            ca_stream->prefer_primary_pending = true;
            ca_stream->prefer_primary_timer = asc_timer_one_shot(mod->cam_prefer_primary_ms,
                                                                 on_cam_prefer_primary,
                                                                 &ca_stream->prefer_primary_timer_arg);
        }
        else
        {
            ca_stream_apply_keys_from_cam(mod, ca_stream, key16, mask, is_backup, is_cw_checksum_ok);
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
        if(!is_backup && ca_stream->prefer_primary_pending && ca_stream->prefer_primary_mask != 0)
        {
            uint8_t key16[16];
            const uint8_t mask = ca_stream->prefer_primary_mask;
            const bool checksum_ok = ca_stream->prefer_primary_checksum_ok;
            memcpy(key16, ca_stream->prefer_primary_key, sizeof(key16));
            ca_stream_cancel_prefer_primary(ca_stream);
            ca_stream_apply_keys_from_cam(mod, ca_stream, key16, mask, true, checksum_ok);
        }

        const uint64_t now_us = asc_utime();
        const uint64_t sendtime = is_backup ? ca_stream->sendtime_backup : ca_stream->sendtime_primary;
        const uint64_t responsetime = sendtime ? (now_us - sendtime) / 1000 : 0;
        ca_stream->stat_ecm_not_found += 1;
        if(is_backup)
            ca_stream->stat_ecm_not_found_backup += 1;
        else
            ca_stream->stat_ecm_not_found_primary += 1;
        if(sendtime)
        {
            ca_stream_stat_rtt(ca_stream, responsetime);
            ca_stream_stat_rtt_cam(ca_stream, is_backup, responsetime);
        }

        if(mod->dual_cam && ca_stream->last_ecm_ok_us && (now_us - ca_stream->last_ecm_ok_us) < 500000ULL)
        {
            /* In dual-CAM mode one CAM can reply Not Found while the other already provided keys. */
            return;
        }

        if(!is_backup && ca_stream->backup_ecm_pending)
        {
            ca_stream_cancel_backup_send(ca_stream);
            ca_stream_send_backup_pending(mod, ca_stream);
        }

        if(is_backup)
            ca_stream_backup_mark_bad(mod, ca_stream, "not_found");

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

    /* Parallel descramble (opt-in). По умолчанию выключено. */
    mod->descramble.mode = DESCRAMBLE_PARALLEL_OFF;
    mod->descramble.pipe_rd = -1;
    mod->descramble.pipe_wr = -1;
    mod->descramble.batch_packets = 64;
    mod->descramble.queue_depth_batches = 16;
    mod->descramble.worker_stack_kb = 256;
    mod->descramble.drop_policy = 0; /* drop_oldest */
    mod->descramble.log_rate_limit_sec = 5;

    const char *descramble_parallel_opt = NULL;
    module_option_string("descramble_parallel", &descramble_parallel_opt, NULL);
    if(descramble_parallel_opt)
    {
        if(!strcasecmp(descramble_parallel_opt, "per_stream_thread") || !strcasecmp(descramble_parallel_opt, "per_stream"))
            mod->descramble.mode = DESCRAMBLE_PARALLEL_PER_STREAM_THREAD;
        else if(!strcasecmp(descramble_parallel_opt, "off") || !strcasecmp(descramble_parallel_opt, "0") || !strcasecmp(descramble_parallel_opt, "false"))
            mod->descramble.mode = DESCRAMBLE_PARALLEL_OFF;
        else
            asc_log_warning(MSG("unknown descramble_parallel '%s', keeping 'off'"), descramble_parallel_opt);
    }

    int batch_packets = (int)mod->descramble.batch_packets;
    module_option_number("descramble_batch_packets", &batch_packets);
    if(batch_packets < 8)
        batch_packets = 8;
    if(batch_packets > 1024)
        batch_packets = 1024;
    mod->descramble.batch_packets = (uint32_t)batch_packets;

    int queue_depth = (int)mod->descramble.queue_depth_batches;
    module_option_number("descramble_queue_depth_batches", &queue_depth);
    if(queue_depth < 1)
        queue_depth = 1;
    if(queue_depth > 256)
        queue_depth = 256;
    mod->descramble.queue_depth_batches = (uint32_t)queue_depth;

    int worker_stack_kb = (int)mod->descramble.worker_stack_kb;
    module_option_number("descramble_worker_stack_kb", &worker_stack_kb);
    if(worker_stack_kb < 0)
        worker_stack_kb = 0;
    if(worker_stack_kb > 2048)
        worker_stack_kb = 2048;
    mod->descramble.worker_stack_kb = (uint32_t)worker_stack_kb;

    const char *drop_policy_opt = NULL;
    module_option_string("descramble_drop_policy", &drop_policy_opt, NULL);
    if(drop_policy_opt)
    {
        if(!strcasecmp(drop_policy_opt, "drop_newest"))
            mod->descramble.drop_policy = 1;
        else if(!strcasecmp(drop_policy_opt, "drop_oldest"))
            mod->descramble.drop_policy = 0;
        else
            asc_log_warning(MSG("unknown descramble_drop_policy '%s', using drop_oldest"), drop_policy_opt);
    }

    int log_rate = (int)mod->descramble.log_rate_limit_sec;
    module_option_number("descramble_log_rate_limit_sec", &log_rate);
    if(log_rate < 1)
        log_rate = 1;
    if(log_rate > 60)
        log_rate = 60;
    mod->descramble.log_rate_limit_sec = (uint32_t)log_rate;

    mod->cam_backup_mode = CAM_BACKUP_MODE_HEDGE;
    const char *cam_backup_mode_opt = NULL;
    module_option_string("cam_backup_mode", &cam_backup_mode_opt, NULL);
    if(cam_backup_mode_opt)
    {
        mod->cam_backup_mode = cam_backup_mode_parse(cam_backup_mode_opt);
        if(  strcasecmp(cam_backup_mode_opt, "race")
          && strcasecmp(cam_backup_mode_opt, "hedge")
          && strcasecmp(cam_backup_mode_opt, "failover"))
        {
            asc_log_warning(MSG("unknown cam_backup_mode '%s', fallback to 'hedge'"), cam_backup_mode_opt);
        }
    }

    int cam_backup_hedge_ms = 80;
    module_option_number("cam_backup_hedge_ms", &cam_backup_hedge_ms);
    if(cam_backup_hedge_ms < 0)
        cam_backup_hedge_ms = 0;
    if(cam_backup_hedge_ms > CAM_BACKUP_HEDGE_MAX_MS)
        cam_backup_hedge_ms = CAM_BACKUP_HEDGE_MAX_MS;
    mod->cam_backup_hedge_ms = (uint32_t)cam_backup_hedge_ms;
    mod->cam_backup_hedge_us = (uint64_t)mod->cam_backup_hedge_ms * 1000ULL;

    int cam_prefer_primary_ms = 30;
    module_option_number("cam_prefer_primary_ms", &cam_prefer_primary_ms);
    if(cam_prefer_primary_ms < 0)
        cam_prefer_primary_ms = 0;
    if(cam_prefer_primary_ms > CAM_PREFER_PRIMARY_MAX_MS)
        cam_prefer_primary_ms = CAM_PREFER_PRIMARY_MAX_MS;
    mod->cam_prefer_primary_ms = (uint32_t)cam_prefer_primary_ms;
    mod->cam_prefer_primary_us = (uint64_t)mod->cam_prefer_primary_ms * 1000ULL;

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
        if(mod->descramble.mode == DESCRAMBLE_PARALLEL_PER_STREAM_THREAD)
        {
            /* BISS sets active_key after ca_stream_init(): refresh parallel key ctx. */
            ca_stream_parallel_key_replace(biss);
        }
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
            if(mod->cam_backup_mode == CAM_BACKUP_MODE_HEDGE && mod->cam_backup_hedge_ms == 0)
            {
                mod->cam_backup_hedge_warned = true;
                asc_log_warning(MSG("cam_backup_mode=hedge with cam_backup_hedge_ms=0 behaves like race"));
            }
            if(asc_log_is_debug())
            {
                asc_log_debug(MSG("dual CAM enabled (primary+backup) mode:%s hedge:%ums prefer_primary:%ums"),
                              cam_backup_mode_name(mod->cam_backup_mode),
                              (unsigned)mod->cam_backup_hedge_ms,
                              (unsigned)mod->cam_prefer_primary_ms);
            }
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

    /* Stop parallel worker before we start freeing stream/CAS resources. */
    descramble_stop(mod);

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

    lua_pushstring(lua, cam_backup_mode_name(mod->cam_backup_mode));
    lua_setfield(lua, -2, "cam_backup_mode");

    lua_pushinteger(lua, (lua_Integer)mod->cam_prefer_primary_ms);
    lua_setfield(lua, -2, "cam_prefer_primary_ms");

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

    /* parallel descramble stats (lightweight) */
    lua_newtable(lua);
    const char *mode_s = "off";
    if(mod->descramble.mode == DESCRAMBLE_PARALLEL_PER_STREAM_THREAD)
        mode_s = "per_stream_thread";
    lua_pushstring(lua, mode_s);
    lua_setfield(lua, -2, "mode");
    lua_pushinteger(lua, (lua_Integer)mod->descramble.batch_packets);
    lua_setfield(lua, -2, "batch_packets");
    lua_pushinteger(lua, (lua_Integer)mod->descramble.queue_depth_batches);
    lua_setfield(lua, -2, "queue_depth_batches");
    lua_pushinteger(lua, (lua_Integer)mod->descramble.drops);
    lua_setfield(lua, -2, "drops");
    lua_pushinteger(lua, (lua_Integer)mod->descramble.batches);
    lua_setfield(lua, -2, "batches");
    if(mod->descramble.batches)
    {
        const uint64_t avg_us = mod->descramble.decrypt_us_sum / mod->descramble.batches;
        lua_pushinteger(lua, (lua_Integer)avg_us);
        lua_setfield(lua, -2, "decrypt_avg_us");
        lua_pushinteger(lua, (lua_Integer)mod->descramble.decrypt_us_max);
        lua_setfield(lua, -2, "decrypt_max_us");
    }
    if(mod->descramble.thread_running && mod->descramble.in_q.items && mod->descramble.out_q.items)
    {
        uint32_t in_len = 0;
        uint32_t out_len = 0;
        pthread_mutex_lock(&mod->descramble.in_q.mutex);
        in_len = mod->descramble.in_q.size;
        pthread_mutex_unlock(&mod->descramble.in_q.mutex);
        pthread_mutex_lock(&mod->descramble.out_q.mutex);
        out_len = mod->descramble.out_q.size;
        pthread_mutex_unlock(&mod->descramble.out_q.mutex);
        lua_pushinteger(lua, (lua_Integer)in_len);
        lua_setfield(lua, -2, "in_queue_len");
        lua_pushinteger(lua, (lua_Integer)out_len);
        lua_setfield(lua, -2, "out_queue_len");
    }
    lua_setfield(lua, -2, "descramble");

    /* per-ECM PID stats */
    lua_newtable(lua);
    int idx = 1;
    uint64_t stat_primary_ok = 0;
    uint64_t stat_backup_ok = 0;
    uint64_t stat_backup_bad = 0;
    uint64_t stat_primary_rtt_sum = 0;
    uint64_t stat_backup_rtt_sum = 0;
    uint64_t stat_primary_rtt_count = 0;
    uint64_t stat_backup_rtt_count = 0;
    bool backup_suspended = false;
    uint64_t backup_suspend_left_ms = 0;
    asc_list_for(mod->ca_list)
    {
        ca_stream_t *ca_stream = asc_list_data(mod->ca_list);

        stat_primary_ok += ca_stream->stat_ecm_ok_primary;
        stat_backup_ok += ca_stream->stat_ecm_ok_backup;
        stat_backup_bad += ca_stream->stat_ecm_not_found_backup + ca_stream->stat_key_guard_reject_backup;
        if(ca_stream->stat_rtt_primary_ema_ms)
        {
            stat_primary_rtt_sum += ca_stream->stat_rtt_primary_ema_ms;
            stat_primary_rtt_count += 1;
        }
        if(ca_stream->stat_rtt_backup_ema_ms)
        {
            stat_backup_rtt_sum += ca_stream->stat_rtt_backup_ema_ms;
            stat_backup_rtt_count += 1;
        }
        if(ca_stream->backup_suspend_until_us > now_us)
        {
            const uint64_t left_ms = (ca_stream->backup_suspend_until_us - now_us) / 1000ULL;
            backup_suspended = true;
            if(left_ms > backup_suspend_left_ms)
                backup_suspend_left_ms = left_ms;
        }

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
        lua_pushinteger(lua, (lua_Integer)ca_stream->stat_ecm_sent_primary);
        lua_setfield(lua, -2, "sent_primary");
        lua_pushinteger(lua, (lua_Integer)ca_stream->stat_ecm_sent_backup);
        lua_setfield(lua, -2, "sent_backup");
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
        lua_pushinteger(lua, (lua_Integer)ca_stream->stat_ecm_not_found_primary);
        lua_setfield(lua, -2, "not_found_primary");
        lua_pushinteger(lua, (lua_Integer)ca_stream->stat_ecm_not_found_backup);
        lua_setfield(lua, -2, "not_found_backup");
        lua_pushinteger(lua, (lua_Integer)ca_stream->stat_key_guard_reject_primary);
        lua_setfield(lua, -2, "key_guard_reject_primary");
        lua_pushinteger(lua, (lua_Integer)ca_stream->stat_key_guard_reject_backup);
        lua_setfield(lua, -2, "key_guard_reject_backup");
        lua_pushinteger(lua, (lua_Integer)ca_stream->stat_cw_applied_primary);
        lua_setfield(lua, -2, "cw_applied_primary");
        lua_pushinteger(lua, (lua_Integer)ca_stream->stat_cw_applied_backup);
        lua_setfield(lua, -2, "cw_applied_backup");
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
        lua_pushinteger(lua, (lua_Integer)ca_stream->stat_rtt_primary_ema_ms);
        lua_setfield(lua, -2, "primary_rtt_ms");
        lua_pushinteger(lua, (lua_Integer)ca_stream->stat_rtt_backup_ema_ms);
        lua_setfield(lua, -2, "backup_rtt_ms");
        lua_pushinteger(lua, (lua_Integer)ca_stream->backup_bad_streak);
        lua_setfield(lua, -2, "backup_bad_streak");
        lua_pushinteger(lua, (lua_Integer)ca_stream->backup_suspend_count);
        lua_setfield(lua, -2, "backup_suspend_count");
        if(ca_stream->backup_suspend_until_us > now_us)
        {
            lua_pushboolean(lua, true);
            lua_setfield(lua, -2, "backup_suspended");
            lua_pushinteger(lua, (lua_Integer)((ca_stream->backup_suspend_until_us - now_us) / 1000ULL));
            lua_setfield(lua, -2, "backup_suspend_left_ms");
        }
        else
        {
            lua_pushboolean(lua, false);
            lua_setfield(lua, -2, "backup_suspended");
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

    lua_pushinteger(lua, (lua_Integer)stat_primary_ok);
    lua_setfield(lua, -2, "primary_ok");
    lua_pushinteger(lua, (lua_Integer)stat_backup_ok);
    lua_setfield(lua, -2, "backup_ok");
    lua_pushinteger(lua, (lua_Integer)stat_backup_bad);
    lua_setfield(lua, -2, "backup_bad");
    if(stat_primary_rtt_count)
    {
        lua_pushinteger(lua, (lua_Integer)(stat_primary_rtt_sum / stat_primary_rtt_count));
        lua_setfield(lua, -2, "primary_rtt_ms");
    }
    if(stat_backup_rtt_count)
    {
        lua_pushinteger(lua, (lua_Integer)(stat_backup_rtt_sum / stat_backup_rtt_count));
        lua_setfield(lua, -2, "backup_rtt_ms");
    }
    lua_pushboolean(lua, backup_suspended);
    lua_setfield(lua, -2, "backup_suspended");
    lua_pushinteger(lua, (lua_Integer)backup_suspend_left_ms);
    lua_setfield(lua, -2, "backup_suspend_left_ms");

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
