/*
 * Astra Module: HTTP TS Buffer
 * http://cesbo.com/astra
 *
 * Copyright (C) 2025
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

#include <astra.h>

#include <arpa/inet.h>
#include <errno.h>
#include <netdb.h>
#include <pthread.h>
#include <signal.h>
#include <stdlib.h>
#include <string.h>
#include <strings.h>
#include <sys/socket.h>
#include <sys/time.h>
#include <sys/types.h>
#include <time.h>
#include <unistd.h>

#include "../mpegts/mpegts.h"

#define MSG(_msg) "[http_buffer] " _msg

#define BUFFER_MIN_BYTES (2 * 1024 * 1024)
#define BUFFER_MAX_BYTES (256 * 1024 * 1024)
#define BUFFER_CHECKPOINTS 1024
#define BUFFER_HEADER_MAX 8192
#define BUFFER_READ_CHUNK 65536
#define IDR_SCAN_LIMIT (256 * 1024)

#define START_FLAG_PAT 0x01
#define START_FLAG_PMT 0x02
#define START_FLAG_PCR 0x04
#define START_FLAG_PARAMSET 0x08
#define START_FLAG_PTS_OK 0x10

#define INPUT_STATE_DOWN 0
#define INPUT_STATE_PROBING 1
#define INPUT_STATE_OK 2

#define RESOURCE_STATE_DOWN 0
#define RESOURCE_STATE_PROBING 1
#define RESOURCE_STATE_OK 2

typedef struct
{
    uint16_t pid;
    uint8_t pusi;
    uint8_t afc;
    uint8_t has_adaptation;
    uint8_t random_access;
    uint8_t has_pcr;
    uint64_t pcr_90k;
    uint8_t is_pat;
    uint8_t is_pmt;
    uint8_t pes_start;
    uint8_t pts_valid;
    uint64_t pts_90k;
    uint8_t is_keyframe;
    uint8_t has_sps;
    uint8_t has_pps;
    uint8_t has_vps;
} ts_meta_t;

typedef struct
{
    uint64_t keyframe_index;
    uint64_t pat_index;
    uint64_t pmt_index;
    uint64_t pcr_index;
    uint64_t paramset_index;
    uint64_t video_pts_90k;
    uint64_t audio_pts_90k;
    int64_t av_desync_ms;
    uint32_t flags;
    uint64_t created_write_index;
} start_checkpoint_t;

typedef struct
{
    char *id;
    char *url;
    bool enable;
    int priority;
    int state;
    uint64_t last_ok_ts;
    char last_error[128];
    uint32_t reconnects;
    uint64_t bytes_in;
} buffer_input_t;

typedef struct
{
    char *id;
    char *kind;
    char *value;
    uint32_t ip_from;
    uint32_t ip_to;
} buffer_allow_rule_t;

typedef struct
{
    char mode[32];
    uint64_t start_index;
    uint64_t keyframe_index;
    uint64_t pat_index;
    uint64_t pmt_index;
    uint64_t pcr_index;
    uint64_t paramset_index;
    int64_t desync_ms;
    uint32_t score;
} buffer_start_debug_t;

typedef struct buffer_resource_t
{
    char *id;
    char *name;
    char *path;
    bool enable;

    char *backup_type;
    int no_data_timeout_sec;
    int backup_start_delay_sec;
    int backup_return_delay_sec;
    int backup_probe_interval_sec;

    int buffering_sec;
    int bandwidth_kbps;
    int client_start_offset_sec;
    int max_client_lag_ms;

    bool smart_start_enabled;
    int smart_target_delay_ms;
    int smart_lookback_ms;
    bool smart_require_pat_pmt;
    bool smart_require_keyframe;
    bool smart_require_pcr;
    int smart_wait_ready_ms;
    int smart_max_lead_ms;

    char *keyframe_detect_mode;
    bool av_pts_align_enabled;
    int av_pts_max_desync_ms;
    bool paramset_required;
    bool start_debug_enabled;

    bool ts_resync_enabled;
    bool ts_drop_corrupt_enabled;
    bool ts_rewrite_cc_enabled;
    char *pacing_mode;

    buffer_input_t *inputs;
    int input_count;

    pthread_mutex_t lock;
    pthread_cond_t cond;

    uint8_t *ts_packets;
    ts_meta_t *meta;
    uint64_t capacity_packets;
    uint64_t write_index;
    uint64_t generation;

    mpegts_psi_t *pat;
    mpegts_psi_t *pmt;
    uint16_t pmt_pid;
    uint16_t video_pid;
    uint16_t audio_pid;
    uint8_t video_type;
    char video_codec[16];

    uint64_t last_pat_index;
    uint64_t last_pmt_index;
    uint64_t last_pcr_index;
    uint64_t last_paramset_index;
    uint64_t last_keyframe_index;
    uint64_t last_video_pts;
    uint64_t last_audio_pts;

    bool random_access_seen;
    bool idr_parse_enabled;
    uint8_t *idr_scan_buf;
    size_t idr_scan_len;
    size_t idr_scan_offset;
    size_t idr_scan_limit;
    bool idr_scan_active;

    start_checkpoint_t *checkpoints;
    uint32_t checkpoint_size;
    uint32_t checkpoint_write;
    uint32_t checkpoint_count;

    int state;
    char last_error[128];
    uint64_t last_ok_ts;
    uint64_t last_write_ts;
    uint64_t bytes_in;
    uint32_t clients_connected;

    uint32_t reconnects;
    int active_input_index;

    pthread_t thread;
    bool thread_running;
    bool thread_stop;
    int reader_fd;

    uint8_t pending[TS_PACKET_SIZE * 2];
    size_t pending_len;

    uint32_t config_hash;
    bool delete_pending;

    buffer_start_debug_t last_start_debug;

    struct module_data_t *owner;
} buffer_resource_t;

struct module_data_t
{
    bool enabled;
    char *listen_host;
    int listen_port;
    char *source_bind_interface;
    int max_clients_total;
    int client_read_timeout_sec;

    int listener_fd;
    pthread_t listener_thread;
    bool listener_running;

    pthread_mutex_t lock;
    uint32_t clients_total;

    asc_list_t *resources;
    asc_list_t *allow_rules;
};

typedef struct
{
    int fd;
    module_data_t *mod;
    buffer_resource_t *resource;
    uint64_t read_index;
    uint64_t generation;
    uint8_t *cc_map;
    bool rewrite_cc;
    bool pacing_pcr;
    uint64_t last_pcr_90k;
    uint64_t last_pcr_wall_us;
    uint64_t last_activity_us;
} buffer_client_t;

static uint32_t hash_update(uint32_t h, const void *data, size_t len)
{
    const uint8_t *p = (const uint8_t *)data;
    uint32_t hash = h ? h : 2166136261u;
    for(size_t i = 0; i < len; ++i)
    {
        hash ^= p[i];
        hash *= 16777619u;
    }
    return hash;
}

static uint32_t hash_update_str(uint32_t h, const char *value)
{
    if(!value)
        return hash_update(h, "", 1);
    return hash_update(h, value, strlen(value));
}

static uint32_t hash_update_int(uint32_t h, int value)
{
    return hash_update(h, &value, sizeof(value));
}

static bool parse_ipv4(const char *text, uint32_t *out)
{
    struct in_addr addr;
    if(!text || !out)
        return false;
    if(inet_aton(text, &addr) == 0)
        return false;
    *out = ntohl(addr.s_addr);
    return true;
}

static bool parse_cidr(const char *text, uint32_t *ip_from, uint32_t *ip_to)
{
    char buf[64];
    if(!text)
        return false;
    snprintf(buf, sizeof(buf), "%s", text);
    char *slash = strchr(buf, '/');
    if(!slash)
        return false;
    *slash = '\0';
    const char *base = buf;
    const char *mask_str = slash + 1;
    uint32_t ip = 0;
    if(!parse_ipv4(base, &ip))
        return false;
    int prefix = atoi(mask_str);
    if(prefix < 0 || prefix > 32)
        return false;
    uint32_t mask = prefix == 0 ? 0 : 0xFFFFFFFFu << (32 - prefix);
    uint32_t start = ip & mask;
    uint32_t end = start | (~mask);
    *ip_from = start;
    *ip_to = end;
    return true;
}

static bool parse_range_value(const char *value, uint32_t *ip_from, uint32_t *ip_to)
{
    if(!value)
        return false;
    if(parse_cidr(value, ip_from, ip_to))
        return true;

    char buf[128];
    snprintf(buf, sizeof(buf), "%s", value);

    char *sep = strstr(buf, "..");
    if(sep)
    {
        *sep = '\0';
        sep += 2;
        return parse_ipv4(buf, ip_from) && parse_ipv4(sep, ip_to);
    }

    sep = strchr(buf, '-');
    if(!sep)
        sep = strchr(buf, ',');
    if(!sep)
        return false;

    *sep = '\0';
    sep += 1;
    return parse_ipv4(buf, ip_from) && parse_ipv4(sep, ip_to);
}

static uint64_t now_sec(void)
{
    return (uint64_t)time(NULL);
}

static uint64_t now_us(void)
{
    return asc_utime();
}

static const char *resource_state_name(int state)
{
    switch(state)
    {
        case RESOURCE_STATE_OK:
            return "OK";
        case RESOURCE_STATE_PROBING:
            return "PROBING";
        case RESOURCE_STATE_DOWN:
        default:
            return "DOWN";
    }
}

static const char *input_state_name(int state)
{
    switch(state)
    {
        case INPUT_STATE_OK:
            return "OK";
        case INPUT_STATE_PROBING:
            return "PROBING";
        case INPUT_STATE_DOWN:
        default:
            return "DOWN";
    }
}

static buffer_resource_t *resource_find_by_id(module_data_t *mod, const char *id)
{
    if(!mod || !id)
        return NULL;
    asc_list_for(mod->resources)
    {
        buffer_resource_t *res = (buffer_resource_t *)asc_list_data(mod->resources);
        if(res && res->id && strcmp(res->id, id) == 0)
            return res;
    }
    return NULL;
}

static buffer_resource_t *resource_find_by_id_list(asc_list_t *list, const char *id)
{
    if(!list || !id)
        return NULL;
    asc_list_for(list)
    {
        buffer_resource_t *res = (buffer_resource_t *)asc_list_data(list);
        if(res && res->id && strcmp(res->id, id) == 0)
            return res;
    }
    return NULL;
}

static buffer_resource_t *resource_find_by_path(module_data_t *mod, const char *path)
{
    if(!mod || !path)
        return NULL;
    asc_list_for(mod->resources)
    {
        buffer_resource_t *res = (buffer_resource_t *)asc_list_data(mod->resources);
        if(res && res->path && strcmp(res->path, path) == 0)
            return res;
    }
    return NULL;
}

static void free_inputs(buffer_input_t *inputs, int count)
{
    if(!inputs)
        return;
    for(int i = 0; i < count; ++i)
    {
        free(inputs[i].id);
        free(inputs[i].url);
    }
    free(inputs);
}

static void resource_clear_packets(buffer_resource_t *res)
{
    if(!res)
        return;
    res->write_index = 0;
    res->pending_len = 0;
    res->generation += 1;
    if(res->meta)
        memset(res->meta, 0, sizeof(ts_meta_t) * res->capacity_packets);
    res->last_pat_index = 0;
    res->last_pmt_index = 0;
    res->last_pcr_index = 0;
    res->last_paramset_index = 0;
    res->last_keyframe_index = 0;
    res->last_video_pts = 0;
    res->last_audio_pts = 0;
    res->last_write_ts = 0;
    res->bytes_in = 0;
    res->checkpoint_write = 0;
    res->checkpoint_count = 0;
    res->random_access_seen = false;
    res->idr_parse_enabled = false;
    res->idr_scan_len = 0;
    res->idr_scan_offset = 0;
    res->idr_scan_active = false;

    if(res->pat)
    {
        mpegts_psi_destroy(res->pat);
        res->pat = NULL;
    }
    if(res->pmt)
    {
        mpegts_psi_destroy(res->pmt);
        res->pmt = NULL;
    }
    res->pmt_pid = 0;
    res->video_pid = 0;
    res->audio_pid = 0;
    res->video_type = 0;
    res->video_codec[0] = '\0';

    res->pat = mpegts_psi_init(MPEGTS_PACKET_PAT, 0);
}

static uint64_t packets_for_ms(buffer_resource_t *res, uint64_t ms)
{
    const double kbps = res->bandwidth_kbps > 0 ? res->bandwidth_kbps : 4000.0;
    const double bytes_per_ms = (kbps * 1000.0 / 8.0) / 1000.0;
    const double packets = (bytes_per_ms * ms) / TS_PACKET_SIZE;
    if(packets < 1.0)
        return 1;
    return (uint64_t)(packets + 0.5);
}

static uint64_t ms_for_packets(buffer_resource_t *res, uint64_t packets)
{
    const double kbps = res->bandwidth_kbps > 0 ? res->bandwidth_kbps : 4000.0;
    const double bytes = packets * TS_PACKET_SIZE;
    const double ms = (bytes * 8.0 * 1000.0) / (kbps * 1000.0);
    if(ms < 0.0)
        return 0;
    return (uint64_t)(ms + 0.5);
}

static uint32_t resource_compute_hash(buffer_resource_t *res)
{
    uint32_t h = 0;
    h = hash_update_str(h, res->id);
    h = hash_update_str(h, res->name);
    h = hash_update_str(h, res->path);
    h = hash_update_int(h, res->enable ? 1 : 0);
    h = hash_update_str(h, res->backup_type);
    h = hash_update_int(h, res->no_data_timeout_sec);
    h = hash_update_int(h, res->backup_start_delay_sec);
    h = hash_update_int(h, res->backup_return_delay_sec);
    h = hash_update_int(h, res->backup_probe_interval_sec);
    h = hash_update_int(h, res->buffering_sec);
    h = hash_update_int(h, res->bandwidth_kbps);
    h = hash_update_int(h, res->client_start_offset_sec);
    h = hash_update_int(h, res->max_client_lag_ms);
    h = hash_update_int(h, res->smart_start_enabled ? 1 : 0);
    h = hash_update_int(h, res->smart_target_delay_ms);
    h = hash_update_int(h, res->smart_lookback_ms);
    h = hash_update_int(h, res->smart_require_pat_pmt ? 1 : 0);
    h = hash_update_int(h, res->smart_require_keyframe ? 1 : 0);
    h = hash_update_int(h, res->smart_require_pcr ? 1 : 0);
    h = hash_update_int(h, res->smart_wait_ready_ms);
    h = hash_update_int(h, res->smart_max_lead_ms);
    h = hash_update_str(h, res->keyframe_detect_mode);
    h = hash_update_int(h, res->av_pts_align_enabled ? 1 : 0);
    h = hash_update_int(h, res->av_pts_max_desync_ms);
    h = hash_update_int(h, res->paramset_required ? 1 : 0);
    h = hash_update_int(h, res->start_debug_enabled ? 1 : 0);
    h = hash_update_int(h, res->ts_resync_enabled ? 1 : 0);
    h = hash_update_int(h, res->ts_drop_corrupt_enabled ? 1 : 0);
    h = hash_update_int(h, res->ts_rewrite_cc_enabled ? 1 : 0);
    h = hash_update_str(h, res->pacing_mode);
    h = hash_update_int(h, res->input_count);
    for(int i = 0; i < res->input_count; ++i)
    {
        h = hash_update_str(h, res->inputs[i].id);
        h = hash_update_str(h, res->inputs[i].url);
        h = hash_update_int(h, res->inputs[i].enable ? 1 : 0);
        h = hash_update_int(h, res->inputs[i].priority);
    }
    return h;
}

static int compare_inputs(const void *a, const void *b)
{
    const buffer_input_t *ia = (const buffer_input_t *)a;
    const buffer_input_t *ib = (const buffer_input_t *)b;
    if(ia->priority != ib->priority)
        return ia->priority < ib->priority ? -1 : 1;
    if(!ia->id || !ib->id)
        return 0;
    return strcmp(ia->id, ib->id);
}

static void resource_realloc_packets(buffer_resource_t *res)
{
    const uint64_t bytes = (uint64_t)res->bandwidth_kbps * 1000ULL / 8ULL * (uint64_t)res->buffering_sec;
    uint64_t alloc_bytes = bytes;
    if(alloc_bytes < BUFFER_MIN_BYTES)
        alloc_bytes = BUFFER_MIN_BYTES;
    if(alloc_bytes > BUFFER_MAX_BYTES)
        alloc_bytes = BUFFER_MAX_BYTES;
    uint64_t capacity = alloc_bytes / TS_PACKET_SIZE;
    if(capacity < 1)
        capacity = BUFFER_MIN_BYTES / TS_PACKET_SIZE;

    if(res->capacity_packets == capacity && res->ts_packets && res->meta)
        return;

    free(res->ts_packets);
    free(res->meta);

    res->capacity_packets = capacity;
    res->ts_packets = (uint8_t *)calloc(res->capacity_packets, TS_PACKET_SIZE);
    res->meta = (ts_meta_t *)calloc(res->capacity_packets, sizeof(ts_meta_t));
}

static void resource_destroy(buffer_resource_t *res)
{
    if(!res)
        return;
    free(res->id);
    free(res->name);
    free(res->path);
    free(res->backup_type);
    free(res->keyframe_detect_mode);
    free(res->pacing_mode);
    free_inputs(res->inputs, res->input_count);
    free(res->ts_packets);
    free(res->meta);
    free(res->checkpoints);
    free(res->idr_scan_buf);
    if(res->pat)
        mpegts_psi_destroy(res->pat);
    if(res->pmt)
        mpegts_psi_destroy(res->pmt);
    pthread_mutex_destroy(&res->lock);
    pthread_cond_destroy(&res->cond);
    free(res);
}

static bool allow_check(module_data_t *mod, uint32_t ip)
{
    if(!mod || !mod->allow_rules)
        return true;
    if(asc_list_size(mod->allow_rules) == 0)
        return true;

    asc_list_for(mod->allow_rules)
    {
        buffer_allow_rule_t *rule = (buffer_allow_rule_t *)asc_list_data(mod->allow_rules);
        if(!rule)
            continue;
        if(ip >= rule->ip_from && ip <= rule->ip_to)
            return true;
    }
    return false;
}

static void mark_input_state(buffer_input_t *input, int state, const char *error)
{
    if(!input)
        return;
    input->state = state;
    if(state == INPUT_STATE_OK)
    {
        input->last_ok_ts = now_sec();
        input->last_error[0] = '\0';
    }
    else if(error)
    {
        snprintf(input->last_error, sizeof(input->last_error), "%s", error);
    }
}

static void resource_set_state(buffer_resource_t *res, int state, const char *error)
{
    if(!res)
        return;
    res->state = state;
    if(state == RESOURCE_STATE_OK)
    {
        res->last_ok_ts = now_sec();
        res->last_error[0] = '\0';
    }
    else if(error)
    {
        snprintf(res->last_error, sizeof(res->last_error), "%s", error);
    }
}

static bool resource_is_ready(buffer_resource_t *res)
{
    if(!res)
        return false;
    if(res->last_pat_index == 0 || res->last_pmt_index == 0)
        return false;
    if(res->video_pid == 0 || res->last_keyframe_index == 0)
        return false;
    if(res->smart_require_pcr && res->last_pcr_index == 0)
        return false;
    return true;
}

static void resource_update_state(buffer_resource_t *res)
{
    if(!res)
        return;
    int next_state = resource_is_ready(res) ? RESOURCE_STATE_OK : RESOURCE_STATE_PROBING;
    if(next_state != res->state)
    {
        if(next_state == RESOURCE_STATE_OK)
            resource_set_state(res, next_state, NULL);
        else
            resource_set_state(res, next_state, "warming");
    }
}

static int select_enabled_input(buffer_resource_t *res, int preferred)
{
    if(!res || res->input_count == 0)
        return -1;
    if(preferred < 0 || preferred >= res->input_count)
        preferred = 0;
    if(res->inputs[preferred].enable)
        return preferred;
    for(int i = 0; i < res->input_count; ++i)
    {
        if(res->inputs[i].enable)
            return i;
    }
    return -1;
}

static int next_enabled_input(buffer_resource_t *res, int current)
{
    if(!res || res->input_count == 0)
        return -1;
    for(int i = 1; i <= res->input_count; ++i)
    {
        int idx = (current + i) % res->input_count;
        if(res->inputs[idx].enable)
            return idx;
    }
    return -1;
}

static bool parse_http_url(const char *url, char **host, int *port, char **path)
{
    if(!url)
        return false;
    const char *prefix = "http://";
    const size_t prefix_len = strlen(prefix);
    if(strncmp(url, prefix, prefix_len) != 0)
        return false;
    const char *p = url + prefix_len;
    const char *slash = strchr(p, '/');
    const char *host_end = slash ? slash : (url + strlen(url));
    const char *port_sep = strchr(p, ':');
    if(port_sep && port_sep < host_end)
    {
        *host = strndup(p, port_sep - p);
        *port = atoi(port_sep + 1);
    }
    else
    {
        *host = strndup(p, host_end - p);
        *port = 80;
    }
    if(!*port)
        *port = 80;
    if(slash)
        *path = strdup(slash);
    else
        *path = strdup("/");
    return true;
}

static int open_tcp_socket(const char *host, int port, const char *bind_iface)
{
    struct addrinfo hints;
    struct addrinfo *result = NULL;
    int fd = -1;
    char port_str[16];

    memset(&hints, 0, sizeof(hints));
    hints.ai_family = AF_INET;
    hints.ai_socktype = SOCK_STREAM;
    snprintf(port_str, sizeof(port_str), "%d", port);

    if(getaddrinfo(host, port_str, &hints, &result) != 0)
        return -1;

    for(struct addrinfo *rp = result; rp != NULL; rp = rp->ai_next)
    {
        fd = socket(rp->ai_family, rp->ai_socktype, rp->ai_protocol);
        if(fd == -1)
            continue;

#ifdef SO_BINDTODEVICE
        if(bind_iface && *bind_iface)
        {
            if(setsockopt(fd, SOL_SOCKET, SO_BINDTODEVICE, bind_iface, strlen(bind_iface)) != 0)
            {
                asc_log_warning(MSG("SO_BINDTODEVICE failed: %s"), strerror(errno));
            }
        }
#endif

        if(connect(fd, rp->ai_addr, rp->ai_addrlen) == 0)
            break;

        close(fd);
        fd = -1;
    }

    if(result)
        freeaddrinfo(result);

    return fd;
}

static bool send_all(int fd, const void *data, size_t size)
{
    const uint8_t *ptr = (const uint8_t *)data;
    size_t sent = 0;
    while(sent < size)
    {
        ssize_t n = send(fd, ptr + sent, size - sent,
#ifdef MSG_NOSIGNAL
                         MSG_NOSIGNAL
#else
                         0
#endif
        );
        if(n < 0)
        {
            if(errno == EINTR)
                continue;
            return false;
        }
        if(n == 0)
            return false;
        sent += (size_t)n;
    }
    return true;
}

static void parse_pmt(buffer_resource_t *res, mpegts_psi_t *psi)
{
    if(!psi)
        return;
    const uint8_t table_id = psi->buffer[0];
    if(table_id != 0x02)
        return;

    uint16_t video_pid = 0;
    uint16_t audio_pid = 0;
    uint8_t video_type = 0;

    const uint8_t *ptr;
    PMT_ITEMS_FOREACH(psi, ptr)
    {
        const uint8_t type = PMT_ITEM_GET_TYPE(psi, ptr);
        const uint16_t pid = PMT_ITEM_GET_PID(psi, ptr);
        if(!pid || pid >= NULL_TS_PID)
            continue;

        if(type == 0x1B || type == 0x24 || type == 0x02)
        {
            if(!video_pid)
            {
                video_pid = pid;
                video_type = type;
                continue;
            }
        }

        if(!audio_pid && type != 0x1B && type != 0x24 && type != 0x02)
        {
            audio_pid = pid;
        }
    }

    res->video_pid = video_pid;
    res->audio_pid = audio_pid;
    res->video_type = video_type;
    if(video_type == 0x1B)
        snprintf(res->video_codec, sizeof(res->video_codec), "H264");
    else if(video_type == 0x24)
        snprintf(res->video_codec, sizeof(res->video_codec), "HEVC");
    else if(video_type == 0x02)
        snprintf(res->video_codec, sizeof(res->video_codec), "MPEG2");
    else
        res->video_codec[0] = '\0';
}

static void on_pat(void *arg, mpegts_psi_t *psi)
{
    buffer_resource_t *res = (buffer_resource_t *)arg;
    if(!res || !psi)
        return;
    if(psi->buffer[0] != 0x00)
        return;

    const uint8_t *ptr;
    uint16_t pmt_pid = 0;
    PAT_ITEMS_FOREACH(psi, ptr)
    {
        const uint16_t pnr = PAT_ITEM_GET_PNR(psi, ptr);
        const uint16_t pid = PAT_ITEM_GET_PID(psi, ptr);
        if(pnr != 0 && pid && pid < NULL_TS_PID)
        {
            pmt_pid = pid;
            break;
        }
    }

    if(pmt_pid && pmt_pid != res->pmt_pid)
    {
        if(res->pmt)
            mpegts_psi_destroy(res->pmt);
        res->pmt = mpegts_psi_init(MPEGTS_PACKET_PMT, pmt_pid);
        res->pmt_pid = pmt_pid;
    }
}

static void on_pmt(void *arg, mpegts_psi_t *psi)
{
    buffer_resource_t *res = (buffer_resource_t *)arg;
    if(!res || !psi)
        return;
    parse_pmt(res, psi);
}

static void update_checkpoints(buffer_resource_t *res, uint64_t keyframe_index)
{
    if(!res || !res->checkpoints)
        return;

    start_checkpoint_t *cp = &res->checkpoints[res->checkpoint_write % res->checkpoint_size];
    memset(cp, 0, sizeof(*cp));
    cp->keyframe_index = keyframe_index;
    cp->pat_index = res->last_pat_index;
    cp->pmt_index = res->last_pmt_index;
    cp->pcr_index = res->last_pcr_index;
    cp->paramset_index = res->last_paramset_index;
    cp->video_pts_90k = res->last_video_pts;
    cp->audio_pts_90k = res->last_audio_pts;
    cp->created_write_index = res->write_index;

    if(cp->pat_index)
        cp->flags |= START_FLAG_PAT;
    if(cp->pmt_index)
        cp->flags |= START_FLAG_PMT;
    if(cp->pcr_index)
        cp->flags |= START_FLAG_PCR;
    if(cp->paramset_index)
        cp->flags |= START_FLAG_PARAMSET;

    if(cp->video_pts_90k && cp->audio_pts_90k)
    {
        const int64_t delta = (int64_t)cp->video_pts_90k - (int64_t)cp->audio_pts_90k;
        cp->av_desync_ms = (delta * 1000) / 90000;
        cp->flags |= START_FLAG_PTS_OK;
    }

    res->checkpoint_write += 1;
    if(res->checkpoint_count < res->checkpoint_size)
        res->checkpoint_count += 1;
}

static bool parse_annexb(buffer_resource_t *res, const uint8_t *data, size_t len, ts_meta_t *meta)
{
    if(!res || !data || !meta)
        return false;
    const bool is_h265 = res->video_type == 0x24;
    size_t i = 0;
    bool found_keyframe = false;
    while(i + 4 < len)
    {
        size_t start = i;
        while(start + 3 < len && !(data[start] == 0x00 && data[start + 1] == 0x00 &&
            (data[start + 2] == 0x01 || (data[start + 2] == 0x00 && data[start + 3] == 0x01))))
        {
            start++;
        }
        if(start + 3 >= len)
            break;
        size_t nal_start = (data[start + 2] == 0x01) ? start + 3 : start + 4;
        if(nal_start >= len)
            break;
        if(is_h265)
        {
            if(nal_start + 1 >= len)
                break;
            uint8_t nal_type = (data[nal_start] >> 1) & 0x3F;
            if(nal_type == 32)
            {
                meta->has_vps = 1;
                res->last_paramset_index = res->write_index;
            }
            else if(nal_type == 33)
            {
                meta->has_sps = 1;
                res->last_paramset_index = res->write_index;
            }
            else if(nal_type == 34)
            {
                meta->has_pps = 1;
                res->last_paramset_index = res->write_index;
            }
            else if(nal_type >= 16 && nal_type <= 21)
            {
                meta->is_keyframe = 1;
                found_keyframe = true;
            }
        }
        else
        {
            uint8_t nal_type = data[nal_start] & 0x1F;
            if(nal_type == 7)
            {
                meta->has_sps = 1;
                res->last_paramset_index = res->write_index;
            }
            else if(nal_type == 8)
            {
                meta->has_pps = 1;
                res->last_paramset_index = res->write_index;
            }
            else if(nal_type == 5)
            {
                meta->is_keyframe = 1;
                found_keyframe = true;
            }
        }
        i = nal_start + 1;
        if(i > len)
            break;
    }
    return found_keyframe;
}

static void idr_scan_start(buffer_resource_t *res)
{
    if(!res)
        return;
    res->idr_scan_len = 0;
    res->idr_scan_offset = 0;
    res->idr_scan_active = true;
}

static void idr_scan_stop(buffer_resource_t *res)
{
    if(!res)
        return;
    res->idr_scan_active = false;
}

static void idr_scan_append(buffer_resource_t *res, const uint8_t *data, size_t len, ts_meta_t *meta)
{
    if(!res || !meta || !data || len == 0)
        return;
    if(!res->idr_scan_active || !res->idr_scan_buf || res->idr_scan_limit == 0)
        return;
    if(res->idr_scan_len >= res->idr_scan_limit)
    {
        res->idr_scan_active = false;
        return;
    }

    size_t room = res->idr_scan_limit - res->idr_scan_len;
    if(len > room)
        len = room;

    memcpy(res->idr_scan_buf + res->idr_scan_len, data, len);
    res->idr_scan_len += len;

    size_t scan_from = res->idr_scan_offset;
    if(scan_from > 4)
        scan_from -= 4;
    else
        scan_from = 0;

    if(parse_annexb(res, res->idr_scan_buf + scan_from, res->idr_scan_len - scan_from, meta))
        res->idr_scan_active = false;

    res->idr_scan_offset = res->idr_scan_len;
    if(res->idr_scan_len >= res->idr_scan_limit)
        res->idr_scan_active = false;
}

static bool buffer_select_start(buffer_resource_t *res, uint64_t *start_index, buffer_start_debug_t *dbg)
{
    if(!res || !start_index)
        return false;

    const uint64_t write_index = res->write_index;
    if(write_index == 0)
        return false;

    const uint64_t target_delay = packets_for_ms(res, res->smart_target_delay_ms);
    const uint64_t target = (write_index > target_delay)
        ? (write_index - target_delay)
        : write_index;
    const uint64_t min_index = (write_index > res->capacity_packets)
        ? (write_index - res->capacity_packets)
        : 0;
    const uint64_t lookback = packets_for_ms(res, res->smart_lookback_ms);

    uint32_t best_score = 0xFFFFFFFFu;
    bool found = false;
    start_checkpoint_t best_cp;
    memset(&best_cp, 0, sizeof(best_cp));

    for(uint32_t i = 0; i < res->checkpoint_count; ++i)
    {
        start_checkpoint_t *cp = &res->checkpoints[i];
        if(cp->keyframe_index < min_index)
            continue;
        if(cp->keyframe_index > target)
            continue;
        if(cp->keyframe_index + lookback < target)
            continue;

        uint32_t flags = cp->flags;
        if(cp->pat_index < min_index)
            flags &= ~START_FLAG_PAT;
        if(cp->pmt_index < min_index)
            flags &= ~START_FLAG_PMT;
        if(cp->pcr_index < min_index)
            flags &= ~START_FLAG_PCR;
        if(cp->paramset_index < min_index)
            flags &= ~START_FLAG_PARAMSET;

        if(res->smart_require_pat_pmt)
        {
            if(!(flags & START_FLAG_PAT) || !(flags & START_FLAG_PMT))
                continue;
        }
        if(res->smart_require_keyframe)
        {
            if(cp->keyframe_index == 0)
                continue;
        }
        if(res->smart_require_pcr && !(flags & START_FLAG_PCR))
            continue;
        if(res->paramset_required && !(flags & START_FLAG_PARAMSET))
            continue;

        int64_t desync = cp->av_desync_ms;
        if(res->av_pts_align_enabled && (flags & START_FLAG_PTS_OK))
        {
            if(llabs(desync) > res->av_pts_max_desync_ms)
                continue;
        }

        uint64_t distance = target - cp->keyframe_index;
        uint32_t score = (uint32_t)(distance > 0xFFFFFFFFu ? 0xFFFFFFFFu : distance);
        if(cp->flags & START_FLAG_PTS_OK)
            score += (uint32_t)llabs(desync);

        if(score < best_score)
        {
            best_score = score;
            best_cp = *cp;
            best_cp.flags = flags;
            found = true;
        }
    }

    if(!found)
        return false;

    uint64_t base_start = (best_cp.flags & START_FLAG_PAT) ? best_cp.pat_index :
        ((best_cp.flags & START_FLAG_PMT) ? best_cp.pmt_index : best_cp.keyframe_index);
    uint64_t start = base_start;
    if(res->paramset_required && (best_cp.flags & START_FLAG_PARAMSET))
    {
        const uint64_t lead_packets = best_cp.keyframe_index - best_cp.paramset_index;
        if(ms_for_packets(res, lead_packets) <= (uint64_t)res->smart_max_lead_ms)
        {
            if(best_cp.paramset_index < start)
                start = best_cp.paramset_index;
        }
    }
    if(res->smart_require_pcr && (best_cp.flags & START_FLAG_PCR))
    {
        if(best_cp.pcr_index < start)
            start = best_cp.pcr_index;
    }
    if(start < min_index)
        start = min_index;

    const uint64_t lead_packets = best_cp.keyframe_index - start;
    if(ms_for_packets(res, lead_packets) > (uint64_t)res->smart_max_lead_ms)
        return false;

    *start_index = start;

    if(dbg)
    {
        snprintf(dbg->mode, sizeof(dbg->mode), "smart_checkpoint");
        dbg->start_index = start;
        dbg->keyframe_index = best_cp.keyframe_index;
        dbg->pat_index = best_cp.pat_index;
        dbg->pmt_index = best_cp.pmt_index;
        dbg->pcr_index = best_cp.pcr_index;
        dbg->paramset_index = best_cp.paramset_index;
        dbg->desync_ms = best_cp.av_desync_ms;
        dbg->score = best_score;
    }

    return true;
}

static void buffer_store_packet(buffer_resource_t *res, const uint8_t *ts)
{
    if(!res || !ts)
        return;

    const uint64_t idx = res->write_index % res->capacity_packets;
    memcpy(&res->ts_packets[idx * TS_PACKET_SIZE], ts, TS_PACKET_SIZE);
    ts_meta_t *meta = &res->meta[idx];
    memset(meta, 0, sizeof(*meta));

    meta->pid = TS_GET_PID(ts);
    meta->pusi = TS_IS_PAYLOAD_START(ts) ? 1 : 0;
    meta->afc = ts[3] & 0x30;
    meta->has_adaptation = TS_IS_AF(ts) ? 1 : 0;
    if(TS_IS_AF(ts) && ts[4] > 0)
        meta->random_access = (ts[5] & 0x40) ? 1 : 0;

    if(TS_IS_PCR(ts))
    {
        meta->has_pcr = 1;
        meta->pcr_90k = TS_GET_PCR(ts) / 300;
        res->last_pcr_index = res->write_index;
    }

    const uint8_t *payload = TS_GET_PAYLOAD(ts);
    size_t payload_len = 0;
    if(payload)
        payload_len = (size_t)(TS_PACKET_SIZE - (payload - ts));
    if(meta->pid == 0)
    {
        if(payload && meta->pusi)
        {
            const uint8_t pointer = payload[0];
            if(pointer + 1 < TS_PACKET_SIZE)
            {
                const uint8_t table_id = payload[1 + pointer];
                if(table_id == 0x00)
                {
                    meta->is_pat = 1;
                    res->last_pat_index = res->write_index;
                }
            }
        }
        if(res->pat)
            mpegts_psi_mux(res->pat, ts, on_pat, res);
    }

    if(res->pmt_pid && meta->pid == res->pmt_pid)
    {
        if(payload && meta->pusi)
        {
            const uint8_t pointer = payload[0];
            if(pointer + 1 < TS_PACKET_SIZE)
            {
                const uint8_t table_id = payload[1 + pointer];
                if(table_id == 0x02)
                {
                    meta->is_pmt = 1;
                    res->last_pmt_index = res->write_index;
                }
            }
        }
        if(res->pmt)
            mpegts_psi_mux(res->pmt, ts, on_pmt, res);
    }

    if(res->video_pid && meta->pid == res->video_pid && payload)
    {
        if(meta->pusi)
        {
            if(meta->random_access)
            {
                meta->is_keyframe = 1;
                res->random_access_seen = true;
                if(strcmp(res->keyframe_detect_mode, "auto") == 0 && res->idr_parse_enabled &&
                    (!res->paramset_required || res->last_paramset_index != 0))
                {
                    res->idr_parse_enabled = false;
                    idr_scan_stop(res);
                    asc_log_info(MSG("IDR_PARSER_DISABLED %s"), res->id);
                }
            }

            if(payload_len >= 3 && payload[0] == 0x00 && payload[1] == 0x00 && payload[2] == 0x01)
            {
                meta->pes_start = 1;
                if(payload[7] & 0x80)
                {
                    if(payload_len > 13)
                    {
                        uint64_t pts =
                            ((uint64_t)(payload[9] & 0x0E) << 29) |
                            ((uint64_t)payload[10] << 22) |
                            ((uint64_t)(payload[11] & 0xFE) << 14) |
                            ((uint64_t)payload[12] << 7) |
                            ((uint64_t)(payload[13] >> 1));
                        meta->pts_valid = 1;
                        meta->pts_90k = pts;
                        res->last_video_pts = pts;
                    }
                }

                bool parse_idr = false;
                if(strcmp(res->keyframe_detect_mode, "idr_parse") == 0)
                    parse_idr = true;
                else if(strcmp(res->keyframe_detect_mode, "auto") == 0)
                {
                    if(!res->random_access_seen || (res->paramset_required && res->last_paramset_index == 0))
                        parse_idr = true;
                }

                if(parse_idr)
                {
                    if(!res->idr_parse_enabled)
                    {
                        res->idr_parse_enabled = true;
                        asc_log_info(MSG("IDR_PARSER_ENABLED %s"), res->id);
                    }
                    idr_scan_start(res);
                    const size_t header_len = 9 + payload[8];
                    if(payload_len > header_len)
                    {
                        const uint8_t *es = payload + header_len;
                        const size_t es_len = payload_len - header_len;
                        idr_scan_append(res, es, es_len, meta);
                    }
                }
                else
                {
                    idr_scan_stop(res);
                }
            }
        }
        else if(res->idr_scan_active && payload_len > 0)
        {
            idr_scan_append(res, payload, payload_len, meta);
        }
    }

    if(res->audio_pid && meta->pid == res->audio_pid && payload && meta->pusi)
    {
        if(payload[0] == 0x00 && payload[1] == 0x00 && payload[2] == 0x01)
        {
            meta->pes_start = 1;
            if(payload[7] & 0x80)
            {
                if(TS_PACKET_SIZE > 13)
                {
                    uint64_t pts =
                        ((uint64_t)(payload[9] & 0x0E) << 29) |
                        ((uint64_t)payload[10] << 22) |
                        ((uint64_t)(payload[11] & 0xFE) << 14) |
                        ((uint64_t)payload[12] << 7) |
                        ((uint64_t)(payload[13] >> 1));
                    meta->pts_valid = 1;
                    meta->pts_90k = pts;
                    res->last_audio_pts = pts;
                }
            }
        }
    }

    if(meta->is_keyframe)
    {
        res->last_keyframe_index = res->write_index;
        update_checkpoints(res, res->write_index);
    }

    res->write_index += 1;
    res->last_write_ts = now_sec();
    res->bytes_in += TS_PACKET_SIZE;
    resource_update_state(res);
}

static bool feed_ts_data(buffer_resource_t *res, const uint8_t *data, size_t len)
{
    size_t offset = 0;

    if(res->pending_len > 0)
    {
        const size_t need = TS_PACKET_SIZE - res->pending_len;
        const size_t take = len < need ? len : need;
        memcpy(&res->pending[res->pending_len], data, take);
        res->pending_len += take;
        offset += take;
        if(res->pending_len < TS_PACKET_SIZE)
            return true;
        if(res->pending[0] != 0x47)
        {
            res->pending_len = 0;
            if(!res->ts_resync_enabled || !res->ts_drop_corrupt_enabled)
                return false;
            return true;
        }
        buffer_store_packet(res, res->pending);
        res->pending_len = 0;
    }

    while(offset + TS_PACKET_SIZE <= len)
    {
        const uint8_t *pkt = data + offset;
        if(pkt[0] != 0x47)
        {
            if(!res->ts_resync_enabled || !res->ts_drop_corrupt_enabled)
                return false;
            offset += 1;
            continue;
        }
        if(offset + TS_PACKET_SIZE * 2 <= len)
        {
            if(pkt[TS_PACKET_SIZE] != 0x47)
            {
                if(!res->ts_resync_enabled || !res->ts_drop_corrupt_enabled)
                    return false;
                offset += 1;
                continue;
            }
        }
        buffer_store_packet(res, pkt);
        offset += TS_PACKET_SIZE;
    }

    if(offset < len)
    {
        res->pending_len = len - offset;
        if(res->pending_len > sizeof(res->pending))
        {
            if(res->ts_resync_enabled && res->ts_drop_corrupt_enabled)
            {
                res->pending_len = 0;
            }
            else
            {
                return false;
            }
        }
        else
        {
            memcpy(res->pending, data + offset, res->pending_len);
        }
    }

    return true;
}

typedef struct
{
    bool headers_done;
    bool chunked;
    int status_code;
    int64_t content_length;
    int64_t content_read;
    size_t chunk_left;
    bool chunk_need_crlf;
    char *location;
} http_stream_state_t;

static bool parse_headers(http_stream_state_t *state, const char *buf)
{
    const char *line_end = strstr(buf, "\n");
    if(!line_end)
        return false;
    int status = 0;
    if(sscanf(buf, "HTTP/%*s %d", &status) == 1)
        state->status_code = status;

    const char *headers = line_end + 1;
    const char *p = headers;
    while(*p)
    {
        const char *eol = strstr(p, "\n");
        if(!eol)
            break;
        if(eol == p || (eol == p + 1 && p[0] == '\r'))
            break;
        const char *sep = memchr(p, ':', eol - p);
        if(sep)
        {
            const size_t key_len = sep - p;
            const char *value = sep + 1;
            while(value < eol && (*value == ' ' || *value == '\t'))
                value++;
            if(key_len == strlen("Content-Length") && strncasecmp(p, "Content-Length", key_len) == 0)
            {
                state->content_length = atoll(value);
            }
            else if(key_len == strlen("Transfer-Encoding") && strncasecmp(p, "Transfer-Encoding", key_len) == 0)
            {
                if(strstr(value, "chunked"))
                    state->chunked = true;
            }
            else if(key_len == strlen("Location") && strncasecmp(p, "Location", key_len) == 0)
            {
                while(value < eol && (*value == ' ' || *value == '\t'))
                    value++;
                const char *end = eol;
                while(end > value && (end[-1] == '\r' || end[-1] == ' ' || end[-1] == '\t'))
                    end--;
                if(state->location)
                {
                    free(state->location);
                    state->location = NULL;
                }
                if(end > value)
                    state->location = strndup(value, (size_t)(end - value));
            }
        }
        p = eol + 1;
    }
    return true;
}

static char *build_redirect_url(const char *location, const char *host, int port, const char *path)
{
    if(!location || location[0] == '\0')
        return NULL;
    if(strncmp(location, "http://", 7) == 0)
        return strdup(location);
    if(strncmp(location, "https://", 8) == 0)
        return NULL;

    const char *base = "/";
    char *base_alloc = NULL;
    if(path)
    {
        const char *slash = strrchr(path, '/');
        if(slash)
        {
            size_t len = (size_t)(slash - path + 1);
            base_alloc = strndup(path, len);
            base = base_alloc ? base_alloc : "/";
        }
    }

    char *out = NULL;
    if(location[0] == '/')
    {
        size_t len = snprintf(NULL, 0, "http://%s:%d%s", host, port, location);
        out = (char *)malloc(len + 1);
        if(out)
            snprintf(out, len + 1, "http://%s:%d%s", host, port, location);
    }
    else
    {
        size_t len = snprintf(NULL, 0, "http://%s:%d%s%s", host, port, base, location);
        out = (char *)malloc(len + 1);
        if(out)
            snprintf(out, len + 1, "http://%s:%d%s%s", host, port, base, location);
    }

    if(base_alloc)
        free(base_alloc);
    return out;
}

static void parse_input_url_options(const char *url, char **base_url, char **user_agent)
{
    *base_url = NULL;
    *user_agent = NULL;
    if(!url)
        return;
    const char *hash = strchr(url, '#');
    if(!hash)
    {
        *base_url = strdup(url);
        return;
    }
    *base_url = strndup(url, (size_t)(hash - url));
    const char *opts = hash + 1;
    while(opts && *opts)
    {
        const char *next = strchr(opts, '&');
        size_t len = next ? (size_t)(next - opts) : strlen(opts);
        const char *eq = memchr(opts, '=', len);
        const char *key = opts;
        size_t key_len = eq ? (size_t)(eq - opts) : len;
        const char *val = eq ? (eq + 1) : NULL;
        size_t val_len = eq ? (len - key_len - 1) : 0;
        if(key_len > 0)
        {
            if((key_len == 2 && strncasecmp(key, "ua", 2) == 0) ||
               (key_len == 10 && strncasecmp(key, "user_agent", 10) == 0) ||
               (key_len == 10 && strncasecmp(key, "user-agent", 10) == 0))
            {
                if(val && val_len > 0)
                {
                    if(*user_agent)
                    {
                        free(*user_agent);
                        *user_agent = NULL;
                    }
                    *user_agent = strndup(val, val_len);
                }
            }
        }
        if(!next)
            break;
        opts = next + 1;
    }
}

static bool read_http_stream(buffer_resource_t *res, buffer_input_t *input, const char *bind_iface)
{
    char *redirect_url = NULL;
    char *base_url = NULL;
    char *user_agent = NULL;
    parse_input_url_options(input->url, &base_url, &user_agent);
    const char *current_url = base_url ? base_url : input->url;
    int redirects = 0;

    while(true)
    {
        char *host = NULL;
        char *path = NULL;
        int port = 0;
        if(!parse_http_url(current_url, &host, &port, &path))
        {
            free(host);
            free(path);
            if(redirect_url)
                free(redirect_url);
            if(base_url)
                free(base_url);
            if(user_agent)
                free(user_agent);
            return false;
        }

        int fd = open_tcp_socket(host, port, bind_iface);
        if(fd < 0)
        {
            free(host);
            free(path);
            if(redirect_url)
                free(redirect_url);
            if(base_url)
                free(base_url);
            if(user_agent)
                free(user_agent);
            return false;
        }

        struct timeval tv;
        tv.tv_sec = 1;
        tv.tv_usec = 0;
        setsockopt(fd, SOL_SOCKET, SO_RCVTIMEO, &tv, sizeof(tv));

        char request[1024];
        snprintf(request, sizeof(request),
            "GET %s HTTP/1.1\r\n"
            "Host: %s:%d\r\n"
            "User-Agent: %s\r\n"
            "Connection: close\r\n\r\n",
            path, host, port, user_agent ? user_agent : "Astra");

        if(!send_all(fd, request, strlen(request)))
        {
            close(fd);
            free(host);
            free(path);
            if(redirect_url)
                free(redirect_url);
            if(base_url)
                free(base_url);
            if(user_agent)
                free(user_agent);
            return false;
        }

        res->reader_fd = fd;

        char buffer[BUFFER_READ_CHUNK];
        size_t buffer_len = 0;
        http_stream_state_t stream;
        memset(&stream, 0, sizeof(stream));
        stream.status_code = 0;
        stream.content_length = -1;

        uint64_t last_data = now_sec();
        bool ok = false;
        char *next_url = NULL;

        while(!res->thread_stop)
        {
            ssize_t n = recv(fd, buffer + buffer_len, sizeof(buffer) - buffer_len, 0);
            if(n == 0)
                break;
            if(n < 0)
            {
                if(errno == EINTR)
                    continue;
                if(errno == EAGAIN || errno == EWOULDBLOCK)
                {
                    if(now_sec() - last_data > (uint64_t)res->no_data_timeout_sec)
                    {
                        close(fd);
                        res->reader_fd = -1;
                        if(stream.location)
                            free(stream.location);
                        free(host);
                        free(path);
                        if(redirect_url)
                            free(redirect_url);
                        if(base_url)
                            free(base_url);
                        if(user_agent)
                            free(user_agent);
                        return false;
                    }
                    continue;
                }
                break;
            }

            buffer_len += (size_t)n;
            size_t offset = 0;

            if(!stream.headers_done)
            {
                char *header_end = NULL;
                for(size_t i = 0; i + 3 < buffer_len; ++i)
                {
                    if(buffer[i] == '\r' && buffer[i + 1] == '\n' && buffer[i + 2] == '\r' && buffer[i + 3] == '\n')
                    {
                        header_end = buffer + i + 4;
                        break;
                    }
                    if(buffer[i] == '\n' && buffer[i + 1] == '\n')
                    {
                        header_end = buffer + i + 2;
                        break;
                    }
                }
                if(!header_end)
                {
                    if(buffer_len >= BUFFER_HEADER_MAX)
                    {
                        close(fd);
                        res->reader_fd = -1;
                        if(stream.location)
                            free(stream.location);
                        free(host);
                        free(path);
                        if(redirect_url)
                            free(redirect_url);
                        if(base_url)
                            free(base_url);
                        if(user_agent)
                            free(user_agent);
                        return false;
                    }
                    continue;
                }

                *header_end = '\0';
                parse_headers(&stream, buffer);
                offset = (header_end - buffer);
                stream.headers_done = true;

                if(stream.status_code == 301 || stream.status_code == 302 ||
                   stream.status_code == 307 || stream.status_code == 308)
                {
                    if(stream.location && redirects < 5)
                        next_url = build_redirect_url(stream.location, host, port, path);
                    if(next_url)
                        break;
                }

                if(stream.status_code != 200)
                {
                    close(fd);
                    res->reader_fd = -1;
                    if(stream.location)
                        free(stream.location);
                    free(host);
                    free(path);
                    if(redirect_url)
                        free(redirect_url);
                    if(base_url)
                        free(base_url);
                    if(user_agent)
                        free(user_agent);
                    return false;
                }
            }

            if(stream.headers_done && offset < buffer_len)
            {
                if(stream.chunked)
                {
                    while(offset < buffer_len)
                    {
                        if(stream.chunk_left == 0)
                        {
                            if(stream.chunk_need_crlf)
                            {
                                if(buffer_len - offset < 2)
                                    break;
                                offset += 2;
                                stream.chunk_need_crlf = false;
                            }
                            char *line_end = memchr(buffer + offset, '\n', buffer_len - offset);
                            if(!line_end)
                                break;
                            char line[32];
                            size_t line_len = line_end - (buffer + offset);
                            if(line_len >= sizeof(line))
                            {
                                close(fd);
                                res->reader_fd = -1;
                                if(stream.location)
                                    free(stream.location);
                                free(host);
                                free(path);
                                if(redirect_url)
                                    free(redirect_url);
                                if(base_url)
                                    free(base_url);
                                if(user_agent)
                                    free(user_agent);
                                return false;
                            }
                            memcpy(line, buffer + offset, line_len);
                            line[line_len] = '\0';
                            stream.chunk_left = strtoul(line, NULL, 16);
                            offset += line_len + 1;
                            if(stream.chunk_left == 0)
                            {
                                ok = true;
                                break;
                            }
                        }
                        if(stream.chunk_left > 0)
                        {
                            size_t avail = buffer_len - offset;
                            size_t take = stream.chunk_left < avail ? stream.chunk_left : avail;
                            pthread_mutex_lock(&res->lock);
                            bool ok_feed = feed_ts_data(res, (const uint8_t *)buffer + offset, take);
                            if(ok_feed)
                            {
                                input->bytes_in += take;
                                if(input->state != INPUT_STATE_OK)
                                    mark_input_state(input, INPUT_STATE_OK, NULL);
                                resource_update_state(res);
                            }
                            pthread_cond_broadcast(&res->cond);
                            pthread_mutex_unlock(&res->lock);
                            if(!ok_feed)
                            {
                                close(fd);
                                res->reader_fd = -1;
                                if(stream.location)
                                    free(stream.location);
                                free(host);
                                free(path);
                                if(redirect_url)
                                    free(redirect_url);
                                if(base_url)
                                    free(base_url);
                                if(user_agent)
                                    free(user_agent);
                                return false;
                            }
                            last_data = now_sec();
                            stream.chunk_left -= take;
                            offset += take;
                            if(stream.chunk_left == 0)
                                stream.chunk_need_crlf = true;
                        }
                    }
                    if(ok)
                        break;
                }
                else
                {
                    size_t avail = buffer_len - offset;
                    size_t take = avail;
                    if(stream.content_length >= 0)
                    {
                        int64_t left = stream.content_length - stream.content_read;
                        if(left <= 0)
                            break;
                        if((int64_t)take > left)
                            take = (size_t)left;
                    }

                    pthread_mutex_lock(&res->lock);
                    bool ok_feed = feed_ts_data(res, (const uint8_t *)buffer + offset, take);
                    if(ok_feed)
                    {
                        input->bytes_in += take;
                        if(input->state != INPUT_STATE_OK)
                            mark_input_state(input, INPUT_STATE_OK, NULL);
                        resource_update_state(res);
                    }
                    pthread_cond_broadcast(&res->cond);
                    pthread_mutex_unlock(&res->lock);
                    if(!ok_feed)
                    {
                        close(fd);
                        res->reader_fd = -1;
                        if(stream.location)
                            free(stream.location);
                        free(host);
                        free(path);
                        if(redirect_url)
                            free(redirect_url);
                        if(base_url)
                            free(base_url);
                        if(user_agent)
                            free(user_agent);
                        return false;
                    }

                    last_data = now_sec();
                    stream.content_read += take;
                    offset += take;

                    if(stream.content_length >= 0 && stream.content_read >= stream.content_length)
                    {
                        ok = true;
                        break;
                    }
                }
            }

            if(offset < buffer_len)
            {
                memmove(buffer, buffer + offset, buffer_len - offset);
                buffer_len = buffer_len - offset;
            }
            else
            {
                buffer_len = 0;
            }
        }

        close(fd);
        res->reader_fd = -1;
        if(stream.location)
            free(stream.location);
        free(host);
        free(path);

        if(next_url)
        {
            redirects += 1;
            if(redirects > 5)
            {
                free(next_url);
                if(redirect_url)
                    free(redirect_url);
                if(base_url)
                    free(base_url);
                if(user_agent)
                    free(user_agent);
                return false;
            }
            if(redirect_url)
                free(redirect_url);
            redirect_url = next_url;
            current_url = redirect_url;
            continue;
        }

        if(redirect_url)
            free(redirect_url);
        if(base_url)
            free(base_url);
        if(user_agent)
            free(user_agent);
        return ok;
    }
}

static void *resource_thread(void *arg)
{
    buffer_resource_t *res = (buffer_resource_t *)arg;
    module_data_t *mod = res->owner;
    int backoff = 1;
    time_t last_probe = 0;
    time_t backup_since = 0;

    while(!res->thread_stop)
    {
        if(!mod || !mod->enabled || !res->enable || res->input_count == 0)
        {
            resource_set_state(res, RESOURCE_STATE_DOWN, "disabled");
            sleep(1);
            continue;
        }

        int active = select_enabled_input(res, res->active_input_index);
        if(active < 0)
        {
            resource_set_state(res, RESOURCE_STATE_DOWN, "no inputs");
            sleep(1);
            continue;
        }

        time_t now = (time_t)now_sec();
        bool probing_primary = false;
        int fallback_index = -1;

        if(active != 0 && res->backup_probe_interval_sec > 0)
        {
            if(backup_since == 0)
                backup_since = now;
            if(res->backup_return_delay_sec <= 0 || now - backup_since >= res->backup_return_delay_sec)
            {
                if(now - last_probe >= res->backup_probe_interval_sec)
                {
                    fallback_index = active;
                    active = 0;
                    probing_primary = true;
                    last_probe = now;
                }
            }
        }

        if(active == 0)
            backup_since = 0;

        buffer_input_t *input = &res->inputs[active];
        res->active_input_index = active;
        resource_set_state(res, RESOURCE_STATE_PROBING, "connecting");
        mark_input_state(input, INPUT_STATE_PROBING, "connecting");

        pthread_mutex_lock(&res->lock);
        resource_clear_packets(res);
        pthread_cond_broadcast(&res->cond);
        pthread_mutex_unlock(&res->lock);

        bool ok = read_http_stream(res, input, mod->source_bind_interface);

        if(res->thread_stop)
            break;

        bool had_data = false;
        pthread_mutex_lock(&res->lock);
        had_data = res->bytes_in > 0;
        pthread_mutex_unlock(&res->lock);
        if(had_data)
            backoff = 1;

        input->reconnects += 1;
        snprintf(input->last_error, sizeof(input->last_error), ok ? "input_eof" : "input_error");
        input->state = INPUT_STATE_DOWN;
        resource_set_state(res, RESOURCE_STATE_DOWN, "input_error");
        res->reconnects += 1;
        asc_log_warning(MSG("RESOURCE_DOWN %s %s"), res->id, input->url ? input->url : "");

        int next = -1;
        if(probing_primary && fallback_index >= 0)
            next = fallback_index;
        else
            next = next_enabled_input(res, active);

        if(next >= 0 && next != active)
        {
            if(res->input_count > 1)
                asc_log_info(MSG("FAILOVER_SWITCH %s %d->%d"), res->id, active, next);
            res->active_input_index = next;
            if(next != 0)
                backup_since = (time_t)now_sec();
        }

        int sleep_for = backoff;
        if(active == 0 && next > 0 && res->backup_start_delay_sec > 0)
            sleep_for = res->backup_start_delay_sec;
        else if(strcmp(res->backup_type, "active") == 0)
            sleep_for = 0;

        if(sleep_for > 0)
            sleep(sleep_for);

        backoff = backoff < 30 ? backoff * 2 : 30;
    }

    return NULL;
}

static void resource_start(buffer_resource_t *res)
{
    if(res->thread_running)
        return;
    res->thread_stop = false;
    res->reader_fd = -1;
    if(pthread_create(&res->thread, NULL, resource_thread, res) == 0)
    {
        res->thread_running = true;
    }
}

static void resource_stop(buffer_resource_t *res)
{
    if(!res->thread_running)
        return;
    res->thread_stop = true;
    if(res->reader_fd >= 0)
    {
        shutdown(res->reader_fd, SHUT_RDWR);
        close(res->reader_fd);
        res->reader_fd = -1;
    }
    pthread_join(res->thread, NULL);
    res->thread_running = false;
}

static void client_release(buffer_client_t *client)
{
    if(!client)
        return;
    if(client->fd >= 0)
        close(client->fd);

    module_data_t *mod = client->mod;
    buffer_resource_t *res = client->resource;
    bool destroy = false;
    if(res)
    {
        pthread_mutex_lock(&res->lock);
        if(res->clients_connected > 0)
            res->clients_connected -= 1;
        destroy = res->delete_pending && res->clients_connected == 0;
        pthread_mutex_unlock(&res->lock);
    }

    if(mod)
    {
        pthread_mutex_lock(&mod->lock);
        if(mod->clients_total > 0)
            mod->clients_total -= 1;
        pthread_mutex_unlock(&mod->lock);
    }

    free(client->cc_map);
    free(client);

    if(destroy)
        resource_destroy(res);
}

static void *client_thread(void *arg)
{
    buffer_client_t *client = (buffer_client_t *)arg;
    buffer_resource_t *res = client->resource;
    client->last_activity_us = now_us();

    uint64_t start_index = 0;
    buffer_start_debug_t dbg;
    memset(&dbg, 0, sizeof(dbg));

    pthread_mutex_lock(&res->lock);
    uint64_t deadline = now_us() + (uint64_t)res->smart_wait_ready_ms * 1000ULL;
    bool picked = false;
    while(!picked && !res->thread_stop)
    {
        if(res->smart_start_enabled)
        {
            picked = buffer_select_start(res, &start_index, &dbg);
            if(picked)
                break;
        }
        else
        {
            picked = true;
            break;
        }

        if(now_us() >= deadline)
            break;

        struct timespec ts;
        uint64_t wait_us = 200000;
        uint64_t now = now_us();
        if(deadline > now && deadline - now < wait_us)
            wait_us = deadline - now;
        uint64_t target = now + wait_us;
        ts.tv_sec = (time_t)(target / 1000000ULL);
        ts.tv_nsec = (long)((target % 1000000ULL) * 1000ULL);
        pthread_cond_timedwait(&res->cond, &res->lock, &ts);
    }

    if(!picked)
    {
        uint64_t offset_packets = packets_for_ms(res, (uint64_t)res->client_start_offset_sec * 1000ULL);
        if(res->write_index > offset_packets)
            start_index = res->write_index - offset_packets;
        else
            start_index = 0;
        snprintf(dbg.mode, sizeof(dbg.mode), "fallback_offset");
        dbg.start_index = start_index;
        dbg.keyframe_index = res->last_keyframe_index;
        dbg.pat_index = res->last_pat_index;
        dbg.pmt_index = res->last_pmt_index;
        dbg.pcr_index = res->last_pcr_index;
        dbg.paramset_index = res->last_paramset_index;
        if(res->last_audio_pts && res->last_video_pts)
        {
            int64_t delta = (int64_t)res->last_video_pts - (int64_t)res->last_audio_pts;
            dbg.desync_ms = (delta * 1000) / 90000;
        }
        asc_log_warning(MSG("SMART_START_FALLBACK %s"), res->id);
    }

    client->read_index = start_index;
    client->generation = res->generation;
    if(res->start_debug_enabled)
        res->last_start_debug = dbg;

    pthread_mutex_unlock(&res->lock);

    const char *headers =
        "HTTP/1.1 200 OK\r\n"
        "Cache-Control: no-cache\r\n"
        "Pragma: no-cache\r\n"
        "Content-Type: application/octet-stream\r\n"
        "Connection: close\r\n\r\n";

    if(!send_all(client->fd, headers, strlen(headers)))
    {
        client_release(client);
        return NULL;
    }

    client->rewrite_cc = res->ts_rewrite_cc_enabled;
    client->pacing_pcr = strcmp(res->pacing_mode, "pcr") == 0;
    if(client->rewrite_cc)
        client->cc_map = (uint8_t *)calloc(MAX_PID, sizeof(uint8_t));

    while(!res->thread_stop)
    {
        pthread_mutex_lock(&res->lock);
        if(client->generation != res->generation)
        {
            client->read_index = res->write_index;
            client->generation = res->generation;
        }

        if(res->write_index == 0 || client->read_index >= res->write_index)
        {
            struct timespec ts;
            uint64_t now = now_us();
            ts.tv_sec = (time_t)(now / 1000000ULL + 1);
            ts.tv_nsec = (long)((now % 1000000ULL) * 1000ULL);
            pthread_cond_timedwait(&res->cond, &res->lock, &ts);
            pthread_mutex_unlock(&res->lock);
            int timeout_sec = client->mod ? client->mod->client_read_timeout_sec : 20;
            if((now_us() - client->last_activity_us) / 1000000ULL > (uint64_t)timeout_sec)
                break;
            continue;
        }

        uint64_t min_index = (res->write_index > res->capacity_packets)
            ? (res->write_index - res->capacity_packets)
            : 0;

        uint64_t lag_packets = 0;
        if(res->max_client_lag_ms > 0)
            lag_packets = packets_for_ms(res, res->max_client_lag_ms);
        uint64_t min_allowed = (lag_packets > 0 && res->write_index > lag_packets)
            ? (res->write_index - lag_packets)
            : min_index;

        if(client->read_index < min_allowed)
        {
            client->read_index = min_allowed;
            asc_log_warning(MSG("CLIENT_LAG_DROP %s"), res->id);
        }

        const uint64_t idx = client->read_index % res->capacity_packets;
        uint8_t packet[TS_PACKET_SIZE];
        memcpy(packet, &res->ts_packets[idx * TS_PACKET_SIZE], TS_PACKET_SIZE);
        ts_meta_t meta = res->meta[idx];
        pthread_mutex_unlock(&res->lock);

        if(packet[0] != 0x47)
        {
            if(!res->ts_resync_enabled)
                break;
            client->read_index += 1;
            continue;
        }

        if(client->rewrite_cc)
        {
            uint16_t pid = meta.pid;
            uint8_t cc = client->cc_map[pid] & 0x0F;
            TS_SET_CC(packet, cc);
            client->cc_map[pid] = (cc + 1) & 0x0F;
        }

        if(client->pacing_pcr && meta.has_pcr)
        {
            if(client->last_pcr_90k != 0)
            {
                uint64_t delta_pcr = meta.pcr_90k - client->last_pcr_90k;
                uint64_t delta_us = (delta_pcr * 1000000ULL) / 90000ULL;
                uint64_t now = now_us();
                uint64_t expected = client->last_pcr_wall_us + delta_us;
                if(expected > now)
                    usleep(expected - now);
            }
            client->last_pcr_90k = meta.pcr_90k;
            client->last_pcr_wall_us = now_us();
        }

        if(!send_all(client->fd, packet, TS_PACKET_SIZE))
            break;

        client->read_index += 1;
        client->last_activity_us = now_us();
    }

    client_release(client);
    return NULL;
}

static void *listener_thread(void *arg)
{
    module_data_t *mod = (module_data_t *)arg;
    struct sockaddr_in addr;
    int fd = socket(AF_INET, SOCK_STREAM, 0);
    if(fd < 0)
        return NULL;

    int reuse = 1;
    setsockopt(fd, SOL_SOCKET, SO_REUSEADDR, &reuse, sizeof(reuse));

    memset(&addr, 0, sizeof(addr));
    addr.sin_family = AF_INET;
    addr.sin_port = htons(mod->listen_port);
    if(!mod->listen_host || strcmp(mod->listen_host, "0.0.0.0") == 0)
        addr.sin_addr.s_addr = htonl(INADDR_ANY);
    else
        inet_aton(mod->listen_host, &addr.sin_addr);

    if(bind(fd, (struct sockaddr *)&addr, sizeof(addr)) != 0)
    {
        asc_log_error(MSG("bind failed: %s"), strerror(errno));
        close(fd);
        return NULL;
    }

    if(listen(fd, 128) != 0)
    {
        asc_log_error(MSG("listen failed: %s"), strerror(errno));
        close(fd);
        return NULL;
    }

    mod->listener_fd = fd;

    while(mod->listener_running)
    {
        struct sockaddr_in client_addr;
        socklen_t client_len = sizeof(client_addr);
        int client_fd = accept(fd, (struct sockaddr *)&client_addr, &client_len);
        if(client_fd < 0)
        {
            if(errno == EINTR)
                continue;
            if(!mod->listener_running)
                break;
            continue;
        }

        pthread_mutex_lock(&mod->lock);
        bool over_limit = mod->clients_total >= (uint32_t)mod->max_clients_total;
        pthread_mutex_unlock(&mod->lock);

        if(over_limit)
        {
            const char *reply = "HTTP/1.1 503 Service Unavailable\r\nConnection: close\r\n\r\n";
            send_all(client_fd, reply, strlen(reply));
            close(client_fd);
            continue;
        }

        char header[BUFFER_HEADER_MAX];
        ssize_t read_len = recv(client_fd, header, sizeof(header) - 1, 0);
        if(read_len <= 0)
        {
            close(client_fd);
            continue;
        }
        header[read_len] = '\0';

        char method[8] = { 0 };
        char path[256] = { 0 };
        if(sscanf(header, "%7s %255s", method, path) != 2)
        {
            const char *reply = "HTTP/1.1 400 Bad Request\r\nConnection: close\r\n\r\n";
            send_all(client_fd, reply, strlen(reply));
            close(client_fd);
            continue;
        }

        if(strcmp(method, "GET") != 0)
        {
            const char *reply = "HTTP/1.1 405 Method Not Allowed\r\nConnection: close\r\n\r\n";
            send_all(client_fd, reply, strlen(reply));
            close(client_fd);
            continue;
        }

        char *query = strchr(path, '?');
        if(query)
            *query = '\0';

        buffer_resource_t *res = resource_find_by_path(mod, path);
        if(!res || !res->enable)
        {
            const char *reply = "HTTP/1.1 404 Not Found\r\nConnection: close\r\n\r\n";
            send_all(client_fd, reply, strlen(reply));
            close(client_fd);
            continue;
        }

        uint32_t ip = ntohl(client_addr.sin_addr.s_addr);
        if(!allow_check(mod, ip))
        {
            const char *reply = "HTTP/1.1 403 Forbidden\r\nConnection: close\r\n\r\n";
            send_all(client_fd, reply, strlen(reply));
            close(client_fd);
            continue;
        }

        buffer_client_t *client = (buffer_client_t *)calloc(1, sizeof(buffer_client_t));
        client->fd = client_fd;
        client->mod = mod;
        client->resource = res;

        pthread_mutex_lock(&mod->lock);
        mod->clients_total += 1;
        pthread_mutex_unlock(&mod->lock);

        pthread_mutex_lock(&res->lock);
        res->clients_connected += 1;
        pthread_mutex_unlock(&res->lock);

        pthread_t thread;
        if(pthread_create(&thread, NULL, client_thread, client) == 0)
        {
            pthread_detach(thread);
        }
        else
        {
            client_release(client);
        }
    }

    close(fd);
    mod->listener_fd = -1;
    return NULL;
}

static void buffer_start_listener(module_data_t *mod)
{
    if(mod->listener_running)
        return;
    mod->listener_running = true;
    if(pthread_create(&mod->listener_thread, NULL, listener_thread, mod) != 0)
        mod->listener_running = false;
}

static void buffer_stop_listener(module_data_t *mod)
{
    if(!mod->listener_running)
        return;
    mod->listener_running = false;
    if(mod->listener_fd >= 0)
    {
        shutdown(mod->listener_fd, SHUT_RDWR);
        close(mod->listener_fd);
        mod->listener_fd = -1;
    }
    pthread_join(mod->listener_thread, NULL);
}

static buffer_resource_t *resource_from_lua(module_data_t *mod, lua_State *L, int idx)
{
    buffer_resource_t *res = (buffer_resource_t *)calloc(1, sizeof(buffer_resource_t));
    if(!res)
        return NULL;

    lua_getfield(L, idx, "id");
    res->id = strdup(lua_tostring(L, -1) ? lua_tostring(L, -1) : "");
    lua_pop(L, 1);

    lua_getfield(L, idx, "name");
    res->name = strdup(lua_tostring(L, -1) ? lua_tostring(L, -1) : "");
    lua_pop(L, 1);

    lua_getfield(L, idx, "path");
    res->path = strdup(lua_tostring(L, -1) ? lua_tostring(L, -1) : "");
    lua_pop(L, 1);

    lua_getfield(L, idx, "enable");
    res->enable = lua_toboolean(L, -1);
    lua_pop(L, 1);

    lua_getfield(L, idx, "backup_type");
    res->backup_type = strdup(lua_tostring(L, -1) ? lua_tostring(L, -1) : "passive");
    lua_pop(L, 1);

    lua_getfield(L, idx, "no_data_timeout_sec");
    res->no_data_timeout_sec = (int)lua_tointeger(L, -1);
    lua_pop(L, 1);

    lua_getfield(L, idx, "backup_start_delay_sec");
    res->backup_start_delay_sec = (int)lua_tointeger(L, -1);
    lua_pop(L, 1);

    lua_getfield(L, idx, "backup_return_delay_sec");
    res->backup_return_delay_sec = (int)lua_tointeger(L, -1);
    lua_pop(L, 1);

    lua_getfield(L, idx, "backup_probe_interval_sec");
    res->backup_probe_interval_sec = (int)lua_tointeger(L, -1);
    lua_pop(L, 1);

    lua_getfield(L, idx, "active_input_index");
    res->active_input_index = (int)lua_tointeger(L, -1);
    lua_pop(L, 1);

    lua_getfield(L, idx, "buffering_sec");
    res->buffering_sec = (int)lua_tointeger(L, -1);
    lua_pop(L, 1);

    lua_getfield(L, idx, "bandwidth_kbps");
    res->bandwidth_kbps = (int)lua_tointeger(L, -1);
    lua_pop(L, 1);

    lua_getfield(L, idx, "client_start_offset_sec");
    res->client_start_offset_sec = (int)lua_tointeger(L, -1);
    lua_pop(L, 1);

    lua_getfield(L, idx, "max_client_lag_ms");
    res->max_client_lag_ms = (int)lua_tointeger(L, -1);
    lua_pop(L, 1);

    lua_getfield(L, idx, "smart_start_enabled");
    res->smart_start_enabled = lua_toboolean(L, -1);
    lua_pop(L, 1);

    lua_getfield(L, idx, "smart_target_delay_ms");
    res->smart_target_delay_ms = (int)lua_tointeger(L, -1);
    lua_pop(L, 1);

    lua_getfield(L, idx, "smart_lookback_ms");
    res->smart_lookback_ms = (int)lua_tointeger(L, -1);
    lua_pop(L, 1);

    lua_getfield(L, idx, "smart_require_pat_pmt");
    res->smart_require_pat_pmt = lua_toboolean(L, -1);
    lua_pop(L, 1);

    lua_getfield(L, idx, "smart_require_keyframe");
    res->smart_require_keyframe = lua_toboolean(L, -1);
    lua_pop(L, 1);

    lua_getfield(L, idx, "smart_require_pcr");
    res->smart_require_pcr = lua_toboolean(L, -1);
    lua_pop(L, 1);

    lua_getfield(L, idx, "smart_wait_ready_ms");
    res->smart_wait_ready_ms = (int)lua_tointeger(L, -1);
    lua_pop(L, 1);

    lua_getfield(L, idx, "smart_max_lead_ms");
    res->smart_max_lead_ms = (int)lua_tointeger(L, -1);
    lua_pop(L, 1);

    lua_getfield(L, idx, "keyframe_detect_mode");
    res->keyframe_detect_mode = strdup(lua_tostring(L, -1) ? lua_tostring(L, -1) : "auto");
    lua_pop(L, 1);

    lua_getfield(L, idx, "av_pts_align_enabled");
    res->av_pts_align_enabled = lua_toboolean(L, -1);
    lua_pop(L, 1);

    lua_getfield(L, idx, "av_pts_max_desync_ms");
    res->av_pts_max_desync_ms = (int)lua_tointeger(L, -1);
    lua_pop(L, 1);

    lua_getfield(L, idx, "paramset_required");
    res->paramset_required = lua_toboolean(L, -1);
    lua_pop(L, 1);

    lua_getfield(L, idx, "start_debug_enabled");
    res->start_debug_enabled = lua_toboolean(L, -1);
    lua_pop(L, 1);

    lua_getfield(L, idx, "ts_resync_enabled");
    res->ts_resync_enabled = lua_toboolean(L, -1);
    lua_pop(L, 1);

    lua_getfield(L, idx, "ts_drop_corrupt_enabled");
    res->ts_drop_corrupt_enabled = lua_toboolean(L, -1);
    lua_pop(L, 1);

    lua_getfield(L, idx, "ts_rewrite_cc_enabled");
    res->ts_rewrite_cc_enabled = lua_toboolean(L, -1);
    lua_pop(L, 1);

    lua_getfield(L, idx, "pacing_mode");
    res->pacing_mode = strdup(lua_tostring(L, -1) ? lua_tostring(L, -1) : "none");
    lua_pop(L, 1);

    lua_getfield(L, idx, "inputs");
    if(lua_istable(L, -1))
    {
        int count = (int)lua_rawlen(L, -1);
        if(count > 0)
        {
            res->inputs = (buffer_input_t *)calloc(count, sizeof(buffer_input_t));
            res->input_count = count;
            for(int i = 0; i < count; ++i)
            {
                lua_rawgeti(L, -1, i + 1);
                if(lua_istable(L, -1))
                {
                    lua_getfield(L, -1, "id");
                    res->inputs[i].id = strdup(lua_tostring(L, -1) ? lua_tostring(L, -1) : "");
                    lua_pop(L, 1);

                    lua_getfield(L, -1, "url");
                    res->inputs[i].url = strdup(lua_tostring(L, -1) ? lua_tostring(L, -1) : "");
                    lua_pop(L, 1);

                    lua_getfield(L, -1, "enable");
                    res->inputs[i].enable = lua_toboolean(L, -1);
                    lua_pop(L, 1);

                    lua_getfield(L, -1, "priority");
                    res->inputs[i].priority = (int)lua_tointeger(L, -1);
                    lua_pop(L, 1);
                }
                lua_pop(L, 1);
            }
        }
    }
    lua_pop(L, 1);

    if(res->input_count > 1)
        qsort(res->inputs, res->input_count, sizeof(buffer_input_t), compare_inputs);

    pthread_mutex_init(&res->lock, NULL);
    pthread_cond_init(&res->cond, NULL);

    res->checkpoints = (start_checkpoint_t *)calloc(BUFFER_CHECKPOINTS, sizeof(start_checkpoint_t));
    res->checkpoint_size = BUFFER_CHECKPOINTS;
    res->idr_scan_limit = IDR_SCAN_LIMIT;
    if(res->idr_scan_limit > 0)
        res->idr_scan_buf = (uint8_t *)calloc(res->idr_scan_limit, sizeof(uint8_t));

    resource_realloc_packets(res);
    resource_clear_packets(res);
    res->config_hash = resource_compute_hash(res);
    res->owner = mod;

    return res;
}

static int method_apply_config(module_data_t *mod)
{
    luaL_checktype(lua, 2, LUA_TTABLE);
    bool was_enabled = mod->enabled;
    int old_port = mod->listen_port;
    char *old_host = mod->listen_host ? strdup(mod->listen_host) : NULL;

    lua_getfield(lua, 2, "settings");
    if(lua_istable(lua, -1))
    {
        lua_getfield(lua, -1, "enabled");
        mod->enabled = lua_toboolean(lua, -1);
        lua_pop(lua, 1);

        lua_getfield(lua, -1, "listen_host");
        const char *host = lua_tostring(lua, -1);
        if(host)
        {
            free(mod->listen_host);
            mod->listen_host = strdup(host);
        }
        lua_pop(lua, 1);

        lua_getfield(lua, -1, "listen_port");
        mod->listen_port = (int)lua_tointeger(lua, -1);
        lua_pop(lua, 1);

        lua_getfield(lua, -1, "source_bind_interface");
        const char *iface = lua_tostring(lua, -1);
        free(mod->source_bind_interface);
        mod->source_bind_interface = iface ? strdup(iface) : NULL;
        lua_pop(lua, 1);

        lua_getfield(lua, -1, "max_clients_total");
        mod->max_clients_total = (int)lua_tointeger(lua, -1);
        lua_pop(lua, 1);

        lua_getfield(lua, -1, "client_read_timeout_sec");
        mod->client_read_timeout_sec = (int)lua_tointeger(lua, -1);
        lua_pop(lua, 1);
    }
    lua_pop(lua, 1);

    bool host_changed = false;
    if((old_host && !mod->listen_host) || (!old_host && mod->listen_host))
        host_changed = true;
    else if(old_host && mod->listen_host && strcmp(old_host, mod->listen_host) != 0)
        host_changed = true;
    bool port_changed = mod->listen_port != old_port;
    if(old_host)
        free(old_host);

    if(mod->enabled)
    {
        if(mod->listener_running && (host_changed || port_changed || !was_enabled))
        {
            buffer_stop_listener(mod);
            buffer_start_listener(mod);
        }
        else if(!mod->listener_running)
        {
            buffer_start_listener(mod);
        }
    }
    else
    {
        buffer_stop_listener(mod);
    }

    lua_getfield(lua, 2, "allow");
    if(lua_istable(lua, -1))
    {
        if(mod->allow_rules)
        {
            asc_list_for(mod->allow_rules)
            {
                buffer_allow_rule_t *rule = (buffer_allow_rule_t *)asc_list_data(mod->allow_rules);
                if(rule)
                {
                    free(rule->id);
                    free(rule->kind);
                    free(rule->value);
                    free(rule);
                }
            }
            asc_list_destroy(mod->allow_rules);
        }
        mod->allow_rules = asc_list_init();
        int count = (int)lua_rawlen(lua, -1);
        for(int i = 0; i < count; ++i)
        {
            lua_rawgeti(lua, -1, i + 1);
            if(lua_istable(lua, -1))
            {
                buffer_allow_rule_t *rule = (buffer_allow_rule_t *)calloc(1, sizeof(buffer_allow_rule_t));
                lua_getfield(lua, -1, "id");
                rule->id = strdup(lua_tostring(lua, -1) ? lua_tostring(lua, -1) : "");
                lua_pop(lua, 1);
                lua_getfield(lua, -1, "kind");
                rule->kind = strdup(lua_tostring(lua, -1) ? lua_tostring(lua, -1) : "");
                lua_pop(lua, 1);
                lua_getfield(lua, -1, "value");
                rule->value = strdup(lua_tostring(lua, -1) ? lua_tostring(lua, -1) : "");
                lua_pop(lua, 1);

                uint32_t ip_from = 0;
                uint32_t ip_to = 0;
                bool ok = false;
                if(strcmp(rule->kind, "allow") == 0)
                {
                    if(strcmp(rule->value, "0.0.0.0") == 0)
                    {
                        ip_from = 0;
                        ip_to = 0xFFFFFFFFu;
                        ok = true;
                    }
                    else if(parse_ipv4(rule->value, &ip_from))
                    {
                        ip_to = ip_from;
                        ok = true;
                    }
                }
                else if(strcmp(rule->kind, "allowRange") == 0)
                {
                    ok = parse_range_value(rule->value, &ip_from, &ip_to);
                }

                if(ok)
                {
                    rule->ip_from = ip_from;
                    rule->ip_to = ip_to;
                    asc_list_insert_tail(mod->allow_rules, rule);
                }
                else
                {
                    asc_log_warning(MSG("invalid allow rule %s"), rule->value);
                    free(rule->id);
                    free(rule->kind);
                    free(rule->value);
                    free(rule);
                }
            }
            lua_pop(lua, 1);
        }
    }
    lua_pop(lua, 1);

    lua_getfield(lua, 2, "resources");
    if(lua_istable(lua, -1))
    {
        asc_list_t *next_resources = asc_list_init();
        int count = (int)lua_rawlen(lua, -1);
        for(int i = 0; i < count; ++i)
        {
            lua_rawgeti(lua, -1, i + 1);
            if(lua_istable(lua, -1))
            {
                buffer_resource_t *parsed = resource_from_lua(mod, lua, lua_gettop(lua));
                if(parsed && parsed->id)
                {
                    buffer_resource_t *existing = resource_find_by_id(mod, parsed->id);
                    if(existing)
                    {
                        existing->owner = mod;
                        uint32_t new_hash = parsed->config_hash;
                        if(existing->config_hash != new_hash)
                        {
                            resource_stop(existing);
                            free(existing->name);
                            free(existing->path);
                            free(existing->backup_type);
                            free(existing->keyframe_detect_mode);
                            free(existing->pacing_mode);
                            free_inputs(existing->inputs, existing->input_count);

                            existing->name = parsed->name;
                            existing->path = parsed->path;
                            existing->backup_type = parsed->backup_type;
                            existing->keyframe_detect_mode = parsed->keyframe_detect_mode;
                            existing->pacing_mode = parsed->pacing_mode;
                            existing->enable = parsed->enable;
                            existing->no_data_timeout_sec = parsed->no_data_timeout_sec;
                            existing->backup_start_delay_sec = parsed->backup_start_delay_sec;
                            existing->backup_return_delay_sec = parsed->backup_return_delay_sec;
                            existing->backup_probe_interval_sec = parsed->backup_probe_interval_sec;
                            existing->active_input_index = parsed->active_input_index;
                            existing->buffering_sec = parsed->buffering_sec;
                            existing->bandwidth_kbps = parsed->bandwidth_kbps;
                            existing->client_start_offset_sec = parsed->client_start_offset_sec;
                            existing->max_client_lag_ms = parsed->max_client_lag_ms;
                            existing->smart_start_enabled = parsed->smart_start_enabled;
                            existing->smart_target_delay_ms = parsed->smart_target_delay_ms;
                            existing->smart_lookback_ms = parsed->smart_lookback_ms;
                            existing->smart_require_pat_pmt = parsed->smart_require_pat_pmt;
                            existing->smart_require_keyframe = parsed->smart_require_keyframe;
                            existing->smart_require_pcr = parsed->smart_require_pcr;
                            existing->smart_wait_ready_ms = parsed->smart_wait_ready_ms;
                            existing->smart_max_lead_ms = parsed->smart_max_lead_ms;
                            existing->av_pts_align_enabled = parsed->av_pts_align_enabled;
                            existing->av_pts_max_desync_ms = parsed->av_pts_max_desync_ms;
                            existing->paramset_required = parsed->paramset_required;
                            existing->start_debug_enabled = parsed->start_debug_enabled;
                            existing->ts_resync_enabled = parsed->ts_resync_enabled;
                            existing->ts_drop_corrupt_enabled = parsed->ts_drop_corrupt_enabled;
                            existing->ts_rewrite_cc_enabled = parsed->ts_rewrite_cc_enabled;
                            existing->inputs = parsed->inputs;
                            existing->input_count = parsed->input_count;
                            existing->config_hash = new_hash;

                            parsed->name = NULL;
                            parsed->path = NULL;
                            parsed->backup_type = NULL;
                            parsed->keyframe_detect_mode = NULL;
                            parsed->pacing_mode = NULL;
                            parsed->inputs = NULL;
                            parsed->input_count = 0;

                            resource_realloc_packets(existing);
                            pthread_mutex_lock(&existing->lock);
                            resource_clear_packets(existing);
                            pthread_mutex_unlock(&existing->lock);
                            if(mod->enabled && existing->enable)
                                resource_start(existing);
                        }
                        asc_list_insert_tail(next_resources, existing);
                    }
                    else
                    {
                        if(mod->enabled && parsed->enable)
                            resource_start(parsed);
                        asc_list_insert_tail(next_resources, parsed);
                        parsed = NULL;
                    }
                }
                if(parsed)
                    resource_destroy(parsed);
            }
            lua_pop(lua, 1);
        }

        if(mod->resources)
        {
            asc_list_for(mod->resources)
            {
                buffer_resource_t *res = (buffer_resource_t *)asc_list_data(mod->resources);
                if(!res)
                    continue;
                if(!resource_find_by_id_list(next_resources, res->id))
                {
                    resource_stop(res);
                    res->delete_pending = true;
                    if(res->clients_connected == 0)
                        resource_destroy(res);
                }
            }
            asc_list_destroy(mod->resources);
        }
        mod->resources = next_resources;
    }
    lua_pop(lua, 1);

    if(mod->resources)
    {
        if(mod->enabled)
        {
            asc_list_for(mod->resources)
            {
                buffer_resource_t *res = (buffer_resource_t *)asc_list_data(mod->resources);
                if(res && res->enable && !res->thread_running)
                    resource_start(res);
            }
        }
        else
        {
            asc_list_for(mod->resources)
            {
                buffer_resource_t *res = (buffer_resource_t *)asc_list_data(mod->resources);
                if(res)
                {
                    resource_stop(res);
                    resource_set_state(res, RESOURCE_STATE_DOWN, "disabled");
                }
            }
        }
    }

    return 0;
}

static void push_resource_status(buffer_resource_t *res)
{
    lua_newtable(lua);
    lua_pushstring(lua, res->id ? res->id : "");
    lua_setfield(lua, -2, "id");
    lua_pushstring(lua, res->name ? res->name : "");
    lua_setfield(lua, -2, "name");
    lua_pushboolean(lua, res->enable);
    lua_setfield(lua, -2, "enable");
    lua_pushstring(lua, res->path ? res->path : "");
    lua_setfield(lua, -2, "path");
    lua_pushstring(lua, resource_state_name(res->state));
    lua_setfield(lua, -2, "state");
    lua_pushstring(lua, res->last_error);
    lua_setfield(lua, -2, "last_error");
    lua_pushnumber(lua, (lua_Number)res->last_ok_ts);
    lua_setfield(lua, -2, "last_ok_ts");
    lua_pushnumber(lua, (lua_Number)res->reconnects);
    lua_setfield(lua, -2, "reconnects");
    lua_pushnumber(lua, (lua_Number)res->bytes_in);
    lua_setfield(lua, -2, "bytes_in");
    lua_pushnumber(lua, res->active_input_index);
    lua_setfield(lua, -2, "active_input_index");
    lua_pushnumber(lua, (lua_Number)res->clients_connected);
    lua_setfield(lua, -2, "clients_connected");

    lua_newtable(lua);
    lua_pushnumber(lua, (lua_Number)res->capacity_packets);
    lua_setfield(lua, -2, "capacity_packets");
    lua_pushnumber(lua, (lua_Number)res->write_index);
    lua_setfield(lua, -2, "write_index");
    lua_pushnumber(lua, (lua_Number)res->last_write_ts);
    lua_setfield(lua, -2, "last_write_ts");
    lua_setfield(lua, -2, "buffer");

    lua_newtable(lua);
    lua_pushnumber(lua, res->pmt_pid);
    lua_setfield(lua, -2, "pmt_pid");
    lua_pushnumber(lua, res->video_pid);
    lua_setfield(lua, -2, "video_pid");
    lua_pushnumber(lua, res->audio_pid);
    lua_setfield(lua, -2, "audio_pid");
    lua_pushstring(lua, res->video_codec);
    lua_setfield(lua, -2, "video_codec");
    lua_setfield(lua, -2, "pids");

    lua_newtable(lua);
    lua_newtable(lua);
    lua_pushboolean(lua, res->last_pat_index != 0);
    lua_setfield(lua, -2, "pat_ok");
    lua_pushboolean(lua, res->last_pmt_index != 0);
    lua_setfield(lua, -2, "pmt_ok");
    lua_pushboolean(lua, res->last_keyframe_index != 0);
    lua_setfield(lua, -2, "keyframe_ok");
    lua_pushboolean(lua, res->last_pcr_index != 0);
    lua_setfield(lua, -2, "pcr_ok");
    lua_pushboolean(lua, res->last_paramset_index != 0);
    lua_setfield(lua, -2, "paramset_ok");
    lua_setfield(lua, -2, "ready_flags");
    lua_pushnumber(lua, res->checkpoint_count);
    lua_setfield(lua, -2, "checkpoints_count");
    lua_setfield(lua, -2, "smart");

    lua_newtable(lua);
    for(int i = 0; i < res->input_count; ++i)
    {
        buffer_input_t *input = &res->inputs[i];
        lua_pushnumber(lua, i + 1);
        lua_newtable(lua);
        lua_pushstring(lua, input->id ? input->id : "");
        lua_setfield(lua, -2, "id");
        lua_pushstring(lua, input->url ? input->url : "");
        lua_setfield(lua, -2, "url");
        lua_pushboolean(lua, input->enable);
        lua_setfield(lua, -2, "enable");
        lua_pushnumber(lua, input->priority);
        lua_setfield(lua, -2, "priority");
        lua_pushstring(lua, input_state_name(input->state));
        lua_setfield(lua, -2, "state");
        lua_pushnumber(lua, (lua_Number)input->last_ok_ts);
        lua_setfield(lua, -2, "last_ok_ts");
        lua_pushstring(lua, input->last_error);
        lua_setfield(lua, -2, "last_error");
        lua_pushnumber(lua, (lua_Number)input->reconnects);
        lua_setfield(lua, -2, "reconnects");
        lua_pushnumber(lua, (lua_Number)input->bytes_in);
        lua_setfield(lua, -2, "bytes_in");
        lua_settable(lua, -3);
    }
    lua_setfield(lua, -2, "inputs");

    if(res->start_debug_enabled)
    {
        lua_newtable(lua);
        lua_pushstring(lua, res->last_start_debug.mode);
        lua_setfield(lua, -2, "mode");
        lua_pushnumber(lua, (lua_Number)res->last_start_debug.start_index);
        lua_setfield(lua, -2, "start_index");
        lua_pushnumber(lua, (lua_Number)res->last_start_debug.keyframe_index);
        lua_setfield(lua, -2, "keyframe_index");
        lua_pushnumber(lua, (lua_Number)res->last_start_debug.pat_index);
        lua_setfield(lua, -2, "pat_index");
        lua_pushnumber(lua, (lua_Number)res->last_start_debug.pmt_index);
        lua_setfield(lua, -2, "pmt_index");
        lua_pushnumber(lua, (lua_Number)res->last_start_debug.pcr_index);
        lua_setfield(lua, -2, "pcr_index");
        lua_pushnumber(lua, (lua_Number)res->last_start_debug.paramset_index);
        lua_setfield(lua, -2, "paramset_index");
        lua_pushnumber(lua, (lua_Number)res->last_start_debug.desync_ms);
        lua_setfield(lua, -2, "desync_ms");
        lua_pushnumber(lua, (lua_Number)res->last_start_debug.score);
        lua_setfield(lua, -2, "score");
        lua_setfield(lua, -2, "last_start_debug");
    }
}

static int method_list_status(module_data_t *mod)
{
    lua_newtable(lua);
    int idx = 1;
    asc_list_for(mod->resources)
    {
        buffer_resource_t *res = (buffer_resource_t *)asc_list_data(mod->resources);
        if(!res)
            continue;
        pthread_mutex_lock(&res->lock);
        lua_pushnumber(lua, idx++);
        push_resource_status(res);
        pthread_mutex_unlock(&res->lock);
        lua_settable(lua, -3);
    }
    return 1;
}

static int method_get_status(module_data_t *mod)
{
    const char *id = luaL_checkstring(lua, 2);
    buffer_resource_t *res = resource_find_by_id(mod, id);
    if(!res)
    {
        lua_pushnil(lua);
        return 1;
    }
    pthread_mutex_lock(&res->lock);
    push_resource_status(res);
    pthread_mutex_unlock(&res->lock);
    return 1;
}

static int method_restart_reader(module_data_t *mod)
{
    const char *id = luaL_checkstring(lua, 2);
    buffer_resource_t *res = resource_find_by_id(mod, id);
    if(!res)
    {
        lua_pushboolean(lua, 0);
        return 1;
    }
    resource_stop(res);
    if(mod->enabled && res->enable)
        resource_start(res);
    lua_pushboolean(lua, 1);
    return 1;
}

static int module_call(module_data_t *mod)
{
    (void)mod;
    return 0;
}

static int __module_call(lua_State *L)
{
    module_data_t *mod = (module_data_t *)lua_touserdata(L, lua_upvalueindex(1));
    return module_call(mod);
}

static void module_init(module_data_t *mod)
{
    mod->enabled = false;
    mod->listen_port = 8089;
    mod->max_clients_total = 2000;
    mod->client_read_timeout_sec = 20;
    mod->listener_fd = -1;
    mod->listener_running = false;
    mod->resources = asc_list_init();
    mod->allow_rules = asc_list_init();
    pthread_mutex_init(&mod->lock, NULL);

    lua_getmetatable(lua, 3);
    lua_pushlightuserdata(lua, (void *)mod);
    lua_pushcclosure(lua, __module_call, 1);
    lua_setfield(lua, -2, "__call");
    lua_pop(lua, 1);
}

static void module_destroy(module_data_t *mod)
{
    buffer_stop_listener(mod);
    if(mod->resources)
    {
        asc_list_for(mod->resources)
        {
            buffer_resource_t *res = (buffer_resource_t *)asc_list_data(mod->resources);
            if(res)
            {
                resource_stop(res);
                resource_destroy(res);
            }
        }
        asc_list_destroy(mod->resources);
        mod->resources = NULL;
    }
    if(mod->allow_rules)
    {
        asc_list_for(mod->allow_rules)
        {
            buffer_allow_rule_t *rule = (buffer_allow_rule_t *)asc_list_data(mod->allow_rules);
            if(rule)
            {
                free(rule->id);
                free(rule->kind);
                free(rule->value);
                free(rule);
            }
        }
        asc_list_destroy(mod->allow_rules);
        mod->allow_rules = NULL;
    }
    free(mod->listen_host);
    free(mod->source_bind_interface);
    pthread_mutex_destroy(&mod->lock);
}

MODULE_LUA_METHODS()
{
    { "apply_config", method_apply_config },
    { "list_status", method_list_status },
    { "get_status", method_get_status },
    { "restart_reader", method_restart_reader },
    { NULL, NULL }
};

MODULE_LUA_REGISTER(http_buffer)
