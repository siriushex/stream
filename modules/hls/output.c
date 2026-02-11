/*
 * Astra Module: HLS Output
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

#include <errno.h>
#include <fcntl.h>
#include <limits.h>
#include <math.h>
#include <sys/stat.h>
#include <time.h>
#include <unistd.h>
#ifdef __linux__
#include <sys/syscall.h>
#endif

#include "hls_memfd.h"

#define MSG(_msg) "[hls_output] " _msg

#define DEFAULT_TARGET_DURATION 6
#define DEFAULT_WINDOW 5
#define DEFAULT_PREFIX "segment"
#define DEFAULT_PLAYLIST "index.m3u8"
#define DEFAULT_TS_EXTENSION "ts"

#define DEFAULT_MAX_BYTES (64 * 1024 * 1024)

#define HLS_NAMING_SEQUENCE 0
#define HLS_NAMING_PCR 1

#define HLS_STORAGE_DISK 0
#define HLS_STORAGE_MEMFD 1

struct module_data_t;

struct hls_memfd_segment_t
{
    int64_t seq;
    double duration;
    char name[128];
    bool discontinuity;
    bool expired;
    uint32_t name_hash;
    struct hls_memfd_segment_t *hash_next;
    int memfd;
    uint8_t *data;
    size_t size_bytes;
    int refcnt;
    time_t created_at;
    struct module_data_t *owner;
};

struct module_data_t
{
    MODULE_STREAM_DATA();

    const char *path;
    const char *playlist;
    const char *prefix;
    const char *base_url;
    const char *ts_extension;
    bool pass_data;
    const char *stream_id;

    int storage_mode;
    bool on_demand;
    bool hls_active;
    bool memfd_enabled;
    uint64_t last_access_mono;
    int idle_timeout_sec;
    size_t max_segments;
    size_t max_bytes;
    size_t segments_bytes;
    char *playlist_buf;
    size_t playlist_len;

    int target_duration_cfg;
    int playlist_target;
    int window;
    int cleanup;
    bool use_wall;
    bool round_duration;
    int naming_mode;

    uint64_t segment_target_us;
    uint64_t segment_elapsed_us;

    bool has_pcr;
    uint64_t pcr_last;
    uint64_t wall_last;

    int64_t seq;

    FILE *segment_fp;
    int segment_fd;
    uint8_t *segment_buf;
    size_t segment_buf_cap;
    size_t segment_size_bytes;
    bool segment_open;
    char segment_name[128];
    size_t segment_packets;
    bool discontinuity_pending;

    asc_list_t *segments;
    size_t segments_count;
    hls_memfd_segment_t **segment_buckets;
    size_t segment_bucket_count;
    uint32_t stream_hash;
    struct module_data_t *stream_hash_next;
#ifdef HLS_MEMFD_DEBUG
    int debug_hold_sec;
    uint64_t debug_hold_until;
    hls_memfd_segment_t *debug_hold_seg;
#endif

    mpegts_psi_t *pat;
    mpegts_psi_t *pmt;
    uint16_t pmt_pid;
    mpegts_packet_type_t pid_types[MAX_PID];
};

static asc_list_t *hls_memfd_streams = NULL;
static module_data_t **hls_memfd_stream_buckets = NULL;
static size_t hls_memfd_stream_bucket_count = 0;
static bool hls_memfd_checked = false;
static bool hls_memfd_available = false;

static uint32_t hls_memfd_hash_name(const char *name);
static void hls_memfd_stream_hash_rebuild(size_t new_bucket_count);
static void hls_memfd_debug_hold_release(module_data_t *mod, uint64_t now_us);

#ifdef __linux__
#ifndef MFD_CLOEXEC
#define MFD_CLOEXEC 0x0001U
#endif
static int hls_create_memfd(const char *name)
{
#ifdef SYS_memfd_create
    return syscall(SYS_memfd_create, name, MFD_CLOEXEC);
#else
    __uarg(name);
    errno = ENOSYS;
    return -1;
#endif
}
#else
static int hls_create_memfd(const char *name)
{
    __uarg(name);
    errno = ENOSYS;
    return -1;
}
#endif

static bool hls_memfd_is_available(void)
{
    if(hls_memfd_checked)
        return hls_memfd_available;

    hls_memfd_checked = true;
    hls_memfd_available = false;

#ifdef __linux__
    int fd = hls_create_memfd("astra-hls-check");
    if(fd >= 0)
    {
        close(fd);
        hls_memfd_available = true;
    }
#endif

    return hls_memfd_available;
}

static void mkdir_p(const char *path)
{
    char tmp[PATH_MAX];
    size_t len = strlen(path);

    if(len == 0 || len >= sizeof(tmp))
        return;

    memcpy(tmp, path, len);
    tmp[len] = '\0';

    for(char *p = tmp + 1; *p; ++p)
    {
        if(*p == '/')
        {
            *p = '\0';
            mkdir(tmp, 0755);
            *p = '/';
        }
    }

    mkdir(tmp, 0755);
}

static module_data_t *hls_memfd_find_stream(const char *stream_id)
{
    if(!stream_id || !hls_memfd_streams)
        return NULL;

    if(hls_memfd_stream_buckets && hls_memfd_stream_bucket_count > 0)
    {
        const uint32_t hash = hls_memfd_hash_name(stream_id);
        const size_t idx = (size_t)(hash % hls_memfd_stream_bucket_count);
        for(module_data_t *mod = hls_memfd_stream_buckets[idx]; mod; mod = mod->stream_hash_next)
        {
            if(mod->stream_id && mod->stream_hash == hash && strcmp(mod->stream_id, stream_id) == 0)
                return mod;
        }
    }

    asc_list_for(hls_memfd_streams)
    {
        module_data_t *mod = (module_data_t *)asc_list_data(hls_memfd_streams);
        if(mod && mod->storage_mode == HLS_STORAGE_MEMFD && mod->stream_id)
        {
            if(strcmp(mod->stream_id, stream_id) == 0)
                return mod;
        }
    }

    return NULL;
}

static void hls_memfd_register_stream(module_data_t *mod)
{
    if(!mod)
        return;
    if(!hls_memfd_streams)
        hls_memfd_streams = asc_list_init();
    if(!hls_memfd_stream_buckets)
        hls_memfd_stream_hash_rebuild(64);
    if(hls_memfd_stream_buckets && hls_memfd_stream_bucket_count > 0)
    {
        const size_t count = asc_list_size(hls_memfd_streams);
        if(count + 1 > hls_memfd_stream_bucket_count * 2)
            hls_memfd_stream_hash_rebuild(hls_memfd_stream_bucket_count * 2);
    }
    if(hls_memfd_stream_buckets && hls_memfd_stream_bucket_count > 0 && mod->stream_id)
    {
        mod->stream_hash = hls_memfd_hash_name(mod->stream_id);
        const size_t idx = (size_t)(mod->stream_hash % hls_memfd_stream_bucket_count);
        mod->stream_hash_next = hls_memfd_stream_buckets[idx];
        hls_memfd_stream_buckets[idx] = mod;
    }
    else
    {
        mod->stream_hash = 0;
        mod->stream_hash_next = NULL;
    }
    asc_list_insert_tail(hls_memfd_streams, mod);
}

static void hls_memfd_unregister_stream(module_data_t *mod)
{
    if(!mod || !hls_memfd_streams)
        return;

    if(hls_memfd_stream_buckets && hls_memfd_stream_bucket_count > 0)
    {
        const size_t idx = (size_t)(mod->stream_hash % hls_memfd_stream_bucket_count);
        module_data_t **cursor = &hls_memfd_stream_buckets[idx];
        while(*cursor)
        {
            if(*cursor == mod)
            {
                *cursor = mod->stream_hash_next;
                mod->stream_hash_next = NULL;
                break;
            }
            cursor = &((*cursor)->stream_hash_next);
        }
    }

    asc_list_remove_item(hls_memfd_streams, mod);
    if(asc_list_size(hls_memfd_streams) == 0)
    {
        asc_list_destroy(hls_memfd_streams);
        hls_memfd_streams = NULL;
        if(hls_memfd_stream_buckets)
        {
            free(hls_memfd_stream_buckets);
            hls_memfd_stream_buckets = NULL;
            hls_memfd_stream_bucket_count = 0;
        }
    }
    else if(hls_memfd_stream_bucket_count > 32)
    {
        const size_t count = asc_list_size(hls_memfd_streams);
        if(count < hls_memfd_stream_bucket_count / 4)
            hls_memfd_stream_hash_rebuild(hls_memfd_stream_bucket_count / 2);
    }
}

static uint32_t hls_memfd_hash_name(const char *name)
{
    uint32_t hash = 2166136261u;
    if(!name)
        return hash;
    for(const unsigned char *p = (const unsigned char *)name; *p; ++p)
    {
        hash ^= *p;
        hash *= 16777619u;
    }
    return hash;
}

static void hls_memfd_stream_hash_rebuild(size_t new_bucket_count)
{
    if(new_bucket_count < 32)
        new_bucket_count = 32;
    module_data_t **buckets = (module_data_t **)calloc(new_bucket_count, sizeof(*buckets));
    if(!buckets)
        return;

    if(hls_memfd_stream_buckets)
        free(hls_memfd_stream_buckets);
    hls_memfd_stream_buckets = buckets;
    hls_memfd_stream_bucket_count = new_bucket_count;

    if(!hls_memfd_streams)
        return;

    asc_list_for(hls_memfd_streams)
    {
        module_data_t *mod = (module_data_t *)asc_list_data(hls_memfd_streams);
        if(!mod || !mod->stream_id)
        {
            if(mod)
            {
                mod->stream_hash = 0;
                mod->stream_hash_next = NULL;
            }
            continue;
        }
        mod->stream_hash = hls_memfd_hash_name(mod->stream_id);
        const size_t idx = (size_t)(mod->stream_hash % hls_memfd_stream_bucket_count);
        mod->stream_hash_next = hls_memfd_stream_buckets[idx];
        hls_memfd_stream_buckets[idx] = mod;
    }
}

#ifdef HLS_MEMFD_DEBUG
static void hls_memfd_debug_hold_release(module_data_t *mod, uint64_t now_us)
{
    if(!mod || mod->debug_hold_sec <= 0 || !mod->debug_hold_seg)
        return;
    if(now_us < mod->debug_hold_until)
        return;
    if(mod->debug_hold_seg->refcnt > 0)
        --mod->debug_hold_seg->refcnt;
    mod->debug_hold_seg = NULL;
    mod->debug_hold_until = 0;
}
#else
static void hls_memfd_debug_hold_release(module_data_t *mod, uint64_t now_us)
{
    __uarg(mod);
    __uarg(now_us);
}
#endif

static void hls_memfd_segment_hash_add(module_data_t *mod, hls_memfd_segment_t *seg)
{
    if(!mod || !seg || !mod->segment_buckets || mod->segment_bucket_count == 0)
        return;
    seg->name_hash = hls_memfd_hash_name(seg->name);
    const size_t idx = (size_t)(seg->name_hash % mod->segment_bucket_count);
    seg->hash_next = mod->segment_buckets[idx];
    mod->segment_buckets[idx] = seg;
}

static void hls_memfd_segment_hash_remove(module_data_t *mod, hls_memfd_segment_t *seg)
{
    if(!mod || !seg || !mod->segment_buckets || mod->segment_bucket_count == 0)
        return;
    const size_t idx = (size_t)(seg->name_hash % mod->segment_bucket_count);
    hls_memfd_segment_t **cursor = &mod->segment_buckets[idx];
    while(*cursor)
    {
        if(*cursor == seg)
        {
            *cursor = seg->hash_next;
            seg->hash_next = NULL;
            return;
        }
        cursor = &((*cursor)->hash_next);
    }
}

static void hls_memfd_segment_free(module_data_t *mod, hls_memfd_segment_t *seg)
{
    if(!seg)
        return;

    if(mod && mod->storage_mode == HLS_STORAGE_MEMFD)
    {
#ifdef HLS_MEMFD_DEBUG
        if(mod->debug_hold_seg == seg)
        {
            mod->debug_hold_seg = NULL;
            mod->debug_hold_until = 0;
        }
#endif
        hls_memfd_segment_hash_remove(mod, seg);
        if(mod->segments_bytes >= seg->size_bytes)
            mod->segments_bytes -= seg->size_bytes;
        else
            mod->segments_bytes = 0;
    }

    if(seg->memfd >= 0)
        close(seg->memfd);
    if(seg->data)
        free(seg->data);
    free(seg);
}

static void hls_memfd_prune_expired(module_data_t *mod)
{
    if(!mod || !mod->segments)
        return;

    hls_memfd_debug_hold_release(mod, asc_utime());

    for(asc_list_first(mod->segments); !asc_list_eol(mod->segments);)
    {
        hls_memfd_segment_t *seg = (hls_memfd_segment_t *)asc_list_data(mod->segments);
        if(seg->expired && seg->refcnt == 0)
        {
            asc_list_remove_current(mod->segments);
            if(mod->segments_count > 0)
                --mod->segments_count;
            hls_memfd_segment_free(mod, seg);
            continue;
        }
        asc_list_next(mod->segments);
    }
}

static void hls_memfd_mark_expired(module_data_t *mod)
{
    if(!mod || !mod->segments)
        return;

    asc_list_for(mod->segments)
    {
        hls_memfd_segment_t *seg = (hls_memfd_segment_t *)asc_list_data(mod->segments);
        seg->expired = true;
    }

    hls_memfd_prune_expired(mod);
}

static void hls_abort_segment(module_data_t *mod)
{
    if(!mod)
        return;

    if(mod->segment_fp)
    {
        fclose(mod->segment_fp);
        mod->segment_fp = NULL;
    }
    if(mod->segment_fd >= 0)
    {
        close(mod->segment_fd);
        mod->segment_fd = -1;
    }
    if(mod->segment_buf)
    {
        free(mod->segment_buf);
        mod->segment_buf = NULL;
        mod->segment_buf_cap = 0;
    }

    mod->segment_size_bytes = 0;
    mod->segment_packets = 0;
    mod->segment_elapsed_us = 0;
    mod->segment_open = false;
    mod->has_pcr = false;
    mod->pcr_last = 0;
    mod->wall_last = 0;
    mod->discontinuity_pending = true;
}

static void hls_memfd_activate(module_data_t *mod)
{
    if(!mod || mod->hls_active)
        return;

    mod->hls_active = true;
    mod->last_access_mono = asc_utime();
    mod->discontinuity_pending = true;
    mod->has_pcr = false;
    mod->pcr_last = 0;
    mod->wall_last = 0;
    asc_log_info(MSG("HLS activate stream=%s"), mod->stream_id ? mod->stream_id : "?");
}

static void hls_memfd_deactivate(module_data_t *mod, const char *reason)
{
    if(!mod || !mod->hls_active)
        return;

    hls_memfd_debug_hold_release(mod, asc_utime());
    hls_abort_segment(mod);
    hls_memfd_mark_expired(mod);
    if(mod->playlist_buf)
    {
        free(mod->playlist_buf);
        mod->playlist_buf = NULL;
        mod->playlist_len = 0;
    }
    mod->playlist_target = mod->target_duration_cfg;
    mod->hls_active = false;
    asc_log_info(MSG("HLS deactivate stream=%s reason=%s"),
                 mod->stream_id ? mod->stream_id : "?", reason ? reason : "idle");
}

static void hls_write_playlist(module_data_t *mod)
{
    if(mod->storage_mode == HLS_STORAGE_MEMFD)
    {
        hls_memfd_prune_expired(mod);

        size_t active_segments = 0;
        asc_list_for(mod->segments)
        {
            hls_memfd_segment_t *seg = (hls_memfd_segment_t *)asc_list_data(mod->segments);
            if(!seg->expired)
                ++active_segments;
        }

        if(active_segments == 0)
        {
            if(mod->playlist_buf)
            {
                free(mod->playlist_buf);
                mod->playlist_buf = NULL;
                mod->playlist_len = 0;
            }
            return;
        }

        size_t skip = 0;
        if(active_segments > (size_t)mod->window)
            skip = active_segments - (size_t)mod->window;

        string_buffer_t *buf = string_buffer_alloc();
        if(!buf)
            return;

        string_buffer_addfstring(buf, "#EXTM3U\n");
        string_buffer_addfstring(buf, "#EXT-X-VERSION:3\n");
        string_buffer_addfstring(buf, "#EXT-X-TARGETDURATION:%d\n", mod->playlist_target);

        int64_t media_seq = 0;
        bool media_seq_set = false;

        asc_list_for(mod->segments)
        {
            hls_memfd_segment_t *seg = (hls_memfd_segment_t *)asc_list_data(mod->segments);
            if(seg->expired)
                continue;
            if(skip)
            {
                --skip;
                continue;
            }

            if(!media_seq_set)
            {
                media_seq = seg->seq;
                media_seq_set = true;
                string_buffer_addfstring(buf, "#EXT-X-MEDIA-SEQUENCE:%lld\n", (long long)media_seq);
            }

            if(seg->discontinuity)
                string_buffer_addfstring(buf, "#EXT-X-DISCONTINUITY\n");
            /* string_buffer_addfstring() is a limited formatter (no %f / precision support).
             * Format EXTINF with snprintf() to keep HLS playlists valid in memfd mode. */
            {
                char extinf[64];
                const int n = snprintf(extinf, sizeof(extinf), "#EXTINF:%.3f,\n", seg->duration);
                if(n > 0)
                {
                    size_t len = (size_t)n;
                    if(len >= sizeof(extinf))
                        len = sizeof(extinf) - 1;
                    string_buffer_addlstring(buf, extinf, len);
                }
            }
            if(mod->base_url && mod->base_url[0] != '\0')
            {
                const size_t base_len = strlen(mod->base_url);
                const char sep = (mod->base_url[base_len - 1] == '/') ? '\0' : '/';
                if(sep)
                    string_buffer_addfstring(buf, "%s/%s\n", mod->base_url, seg->name);
                else
                    string_buffer_addfstring(buf, "%s%s\n", mod->base_url, seg->name);
            }
            else
            {
                string_buffer_addfstring(buf, "%s\n", seg->name);
            }
        }

        size_t payload_len = 0;
        char *payload = string_buffer_release(buf, &payload_len);
        if(!payload)
            return;

        if(mod->playlist_buf)
            free(mod->playlist_buf);
        mod->playlist_buf = payload;
        mod->playlist_len = payload_len;
        return;
    }

    if(mod->segments_count == 0)
        return;

    char playlist_path[PATH_MAX];
    snprintf(playlist_path, sizeof(playlist_path), "%s/%s", mod->path, mod->playlist);

    FILE *fp = fopen(playlist_path, "w");
    if(!fp)
    {
        asc_log_error(MSG("failed to write playlist [%s]"), strerror(errno));
        return;
    }

    size_t skip = 0;
    if(mod->segments_count > (size_t)mod->window)
        skip = mod->segments_count - (size_t)mod->window;

    int64_t media_seq = 0;
    bool media_seq_set = false;

    fprintf(fp, "#EXTM3U\n");
    fprintf(fp, "#EXT-X-VERSION:3\n");
    fprintf(fp, "#EXT-X-TARGETDURATION:%d\n", mod->playlist_target);

    asc_list_for(mod->segments)
    {
        if(skip)
        {
            --skip;
            continue;
        }

        hls_memfd_segment_t *seg = (hls_memfd_segment_t *)asc_list_data(mod->segments);
        if(!media_seq_set)
        {
            media_seq = seg->seq;
            media_seq_set = true;
            fprintf(fp, "#EXT-X-MEDIA-SEQUENCE:%lld\n", (long long)media_seq);
        }

        if(seg->discontinuity)
            fprintf(fp, "#EXT-X-DISCONTINUITY\n");
        fprintf(fp, "#EXTINF:%.3f,\n", seg->duration);
        if(mod->base_url && mod->base_url[0] != '\0')
        {
            const size_t base_len = strlen(mod->base_url);
            const char sep = (mod->base_url[base_len - 1] == '/') ? '\0' : '/';
            if(sep)
                fprintf(fp, "%s/%s\n", mod->base_url, seg->name);
            else
                fprintf(fp, "%s%s\n", mod->base_url, seg->name);
        }
        else
        {
            fprintf(fp, "%s\n", seg->name);
        }
    }

    fclose(fp);
}

static void hls_cleanup_segments(module_data_t *mod)
{
    if(mod->storage_mode == HLS_STORAGE_MEMFD)
    {
        hls_memfd_prune_expired(mod);

        while(true)
        {
            const bool over_segments = (mod->max_segments > 0)
                && (mod->segments_count > mod->max_segments);
            const bool over_bytes = (mod->max_bytes > 0)
                && (mod->segments_bytes > mod->max_bytes);
            if(!over_segments && !over_bytes)
                return;

            bool dropped = false;
            asc_list_first(mod->segments);
            if(asc_list_eol(mod->segments))
                return;
            hls_memfd_segment_t *head = (hls_memfd_segment_t *)asc_list_data(mod->segments);
            for(asc_list_first(mod->segments); !asc_list_eol(mod->segments);)
            {
                hls_memfd_segment_t *seg = (hls_memfd_segment_t *)asc_list_data(mod->segments);
                if(seg->refcnt > 0)
                {
                    asc_list_next(mod->segments);
                    continue;
                }
                asc_list_remove_current(mod->segments);
                if(mod->segments_count > 0)
                    --mod->segments_count;
                const bool dropped_non_head = (seg != head);
                hls_memfd_segment_free(mod, seg);
                if(dropped_non_head)
                {
                    hls_memfd_segment_t *next_seg = NULL;
                    while(!asc_list_eol(mod->segments))
                    {
                        next_seg = (hls_memfd_segment_t *)asc_list_data(mod->segments);
                        if(!next_seg->expired)
                            break;
                        asc_list_next(mod->segments);
                    }
                    if(next_seg && !next_seg->expired)
                    {
                        next_seg->discontinuity = true;
                        asc_log_info(MSG("HLS discontinuity flagged reason=mem_limit stream=%s next=%s"),
                                     mod->stream_id ? mod->stream_id : "?",
                                     next_seg->name);
                    }
                    else
                    {
                        mod->discontinuity_pending = true;
                        asc_log_info(MSG("HLS discontinuity flagged reason=mem_limit stream=%s next=pending"),
                                     mod->stream_id ? mod->stream_id : "?");
                    }
                }
                dropped = true;
                break;
            }

            if(!dropped)
            {
                asc_log_warning(MSG("drop segment skipped (busy) stream=%s"),
                                mod->stream_id ? mod->stream_id : "?");
                return;
            }
            asc_log_info(MSG("HLS drop segment reason=mem_limit stream=%s segments=%zu bytes=%zu"),
                         mod->stream_id ? mod->stream_id : "?",
                         mod->segments_count, mod->segments_bytes);
        }
    }

    while(mod->segments_count > (size_t)mod->cleanup)
    {
        asc_list_first(mod->segments);
        if(asc_list_eol(mod->segments))
            return;

        hls_memfd_segment_t *seg = (hls_memfd_segment_t *)asc_list_data(mod->segments);
        char path[PATH_MAX];
        snprintf(path, sizeof(path), "%s/%s", mod->path, seg->name);
        unlink(path);

        asc_list_remove_current(mod->segments);
        free(seg);
        --mod->segments_count;
    }
}

static void hls_finish_segment(module_data_t *mod)
{
    if(mod->storage_mode == HLS_STORAGE_DISK)
    {
        if(mod->segment_fp)
        {
            fclose(mod->segment_fp);
            mod->segment_fp = NULL;
        }
    }

    if(mod->segment_packets == 0)
    {
        if(mod->segment_fp)
        {
            fclose(mod->segment_fp);
            mod->segment_fp = NULL;
        }
        if(mod->segment_fd >= 0)
        {
            close(mod->segment_fd);
            mod->segment_fd = -1;
        }
        if(mod->segment_buf)
        {
            free(mod->segment_buf);
            mod->segment_buf = NULL;
            mod->segment_buf_cap = 0;
        }
        mod->segment_size_bytes = 0;
        mod->segment_elapsed_us = 0;
        mod->segment_open = false;
        return;
    }

    hls_memfd_segment_t *seg = (hls_memfd_segment_t *)calloc(1, sizeof(*seg));
    if(!seg)
    {
        asc_log_error(MSG("segment metadata alloc failed"));
        hls_abort_segment(mod);
        return;
    }
    seg->seq = mod->seq;
    double duration = (double)mod->segment_elapsed_us / 1000000.0;
    if(mod->round_duration)
        duration = ceil(duration);
    seg->duration = duration;
    snprintf(seg->name, sizeof(seg->name), "%s", mod->segment_name);
    seg->discontinuity = mod->discontinuity_pending;
    seg->expired = false;
    seg->name_hash = 0;
    seg->hash_next = NULL;
    seg->owner = mod;
    seg->refcnt = 0;
    seg->created_at = time(NULL);
    mod->discontinuity_pending = false;

    if(mod->storage_mode == HLS_STORAGE_MEMFD)
    {
        seg->memfd = mod->segment_fd;
        seg->data = mod->segment_buf;
        seg->size_bytes = mod->segment_size_bytes;
        mod->segment_fd = -1;
        mod->segment_buf = NULL;
        mod->segment_buf_cap = 0;
        mod->segment_size_bytes = 0;
        mod->segments_bytes += seg->size_bytes;
    }
    else
    {
        seg->memfd = -1;
        seg->data = NULL;
        seg->size_bytes = 0;
    }

    int duration_ceil = (int)ceil(seg->duration);
    if(duration_ceil < 1)
        duration_ceil = 1;
    if(duration_ceil > mod->playlist_target)
        mod->playlist_target = duration_ceil;

    asc_list_insert_tail(mod->segments, seg);
    ++mod->segments_count;
    hls_memfd_segment_hash_add(mod, seg);
#ifdef HLS_MEMFD_DEBUG
    if(mod->storage_mode == HLS_STORAGE_MEMFD && mod->debug_hold_sec > 0 && !mod->debug_hold_seg)
    {
        mod->debug_hold_seg = seg;
        ++seg->refcnt;
        mod->debug_hold_until = asc_utime() + ((uint64_t)mod->debug_hold_sec * 1000000ULL);
    }
#endif

    hls_cleanup_segments(mod);
    hls_write_playlist(mod);

    mod->segment_elapsed_us = 0;
    mod->segment_packets = 0;
    mod->segment_open = false;
    mod->wall_last = asc_utime();
}

static void hls_open_segment(module_data_t *mod)
{
    ++mod->seq;
    if(mod->naming_mode == HLS_NAMING_PCR)
    {
        uint64_t seed = mod->use_wall ? asc_utime() : mod->pcr_last;
        const uint32_t hash = crc32b((const uint8_t *)&seed, sizeof(seed));
        snprintf(mod->segment_name, sizeof(mod->segment_name), "%s_%08x.%s",
                 mod->prefix, hash, mod->ts_extension);
    }
    else
    {
        snprintf(mod->segment_name, sizeof(mod->segment_name), "%s_%08lld.%s",
                 mod->prefix, (long long)mod->seq, mod->ts_extension);
    }

    if(mod->storage_mode == HLS_STORAGE_MEMFD)
    {
        mod->segment_open = true;
        mod->segment_fd = -1;
        mod->segment_size_bytes = 0;
        if(mod->segment_buf)
        {
            free(mod->segment_buf);
            mod->segment_buf = NULL;
            mod->segment_buf_cap = 0;
        }

        if(mod->memfd_enabled)
        {
            mod->segment_fd = hls_create_memfd("astra-hls");
            if(mod->segment_fd == -1)
            {
                asc_log_warning(MSG("memfd_create failed, falling back to memory: %s"),
                                strerror(errno));
            }
        }

        mod->segment_elapsed_us = 0;
        mod->segment_packets = 0;
        mod->wall_last = asc_utime();
        return;
    }

    char path[PATH_MAX];
    snprintf(path, sizeof(path), "%s/%s", mod->path, mod->segment_name);

    mod->segment_fp = fopen(path, "wb");
    if(!mod->segment_fp)
    {
        asc_log_error(MSG("failed to open segment [%s]"), strerror(errno));
        return;
    }

    mod->segment_elapsed_us = 0;
    mod->segment_packets = 0;
    mod->wall_last = asc_utime();
}

static void hls_mark_discontinuity(module_data_t *mod)
{
    if(!mod)
        return;

    if(mod->storage_mode == HLS_STORAGE_MEMFD)
    {
        if(mod->segment_open && mod->segment_packets > 0)
        {
            hls_finish_segment(mod);
        }
        else if(mod->segment_open)
        {
            hls_abort_segment(mod);
        }
    }
    else
    {
        if(mod->segment_fp && mod->segment_packets > 0)
        {
            hls_finish_segment(mod);
        }
        else if(mod->segment_fp)
        {
            fclose(mod->segment_fp);
            mod->segment_fp = NULL;
        }
    }

    mod->segment_packets = 0;
    mod->segment_elapsed_us = 0;
    mod->has_pcr = false;
    mod->pcr_last = 0;
    mod->wall_last = 0;
    mod->discontinuity_pending = true;
}

static int method_discontinuity(module_data_t *mod)
{
    hls_mark_discontinuity(mod);
    return 0;
}

static int method_stats(module_data_t *mod)
{
    lua_newtable(lua);
    lua_pushinteger(lua, (lua_Integer)mod->segments_count);
    lua_setfield(lua, -2, "current_segments");
    lua_pushinteger(lua, (lua_Integer)mod->segments_bytes);
    lua_setfield(lua, -2, "current_bytes");
    lua_pushboolean(lua, mod->hls_active);
    lua_setfield(lua, -2, "active");
    return 1;
}

static void hls_reset_pid_types(module_data_t *mod)
{
    memset(mod->pid_types, 0, sizeof(mod->pid_types));
    mod->pid_types[0] = MPEGTS_PACKET_PAT;
    if(mod->pmt_pid)
        mod->pid_types[mod->pmt_pid] = MPEGTS_PACKET_PMT;
}

static void on_pat(void *arg, mpegts_psi_t *psi)
{
    module_data_t *mod = (module_data_t *)arg;

    if(psi->buffer[0] != 0x00)
        return;

    const uint32_t crc32 = PSI_GET_CRC32(psi);
    if(crc32 == psi->crc32)
        return;
    if(crc32 != PSI_CALC_CRC32(psi))
        return;
    psi->crc32 = crc32;

    const uint8_t *pointer = NULL;
    uint16_t pmt_pid = 0;
    PAT_ITEMS_FOREACH(psi, pointer)
    {
        const uint16_t pnr = PAT_ITEM_GET_PNR(psi, pointer);
        if(pnr == 0)
            continue;
        const uint16_t pid = PAT_ITEM_GET_PID(psi, pointer);
        if(pid && pid < NULL_TS_PID)
        {
            pmt_pid = pid;
            break;
        }
    }

    if(pmt_pid && pmt_pid != mod->pmt_pid)
    {
        if(mod->pmt)
            mpegts_psi_destroy(mod->pmt);
        mod->pmt_pid = pmt_pid;
        mod->pmt = mpegts_psi_init(MPEGTS_PACKET_PMT, mod->pmt_pid);
        hls_reset_pid_types(mod);
    }
}

static void on_pmt(void *arg, mpegts_psi_t *psi)
{
    module_data_t *mod = (module_data_t *)arg;

    if(psi->buffer[0] != 0x02)
        return;

    const uint32_t crc32 = PSI_GET_CRC32(psi);
    if(crc32 == psi->crc32)
        return;
    if(crc32 != PSI_CALC_CRC32(psi))
        return;
    psi->crc32 = crc32;

    hls_reset_pid_types(mod);

    const uint8_t *pointer = NULL;
    PMT_ITEMS_FOREACH(psi, pointer)
    {
        const uint16_t pid = PMT_ITEM_GET_PID(psi, pointer);
        if(pid >= NULL_TS_PID)
            continue;

        const uint8_t item_type = PMT_ITEM_GET_TYPE(psi, pointer);
        mpegts_packet_type_t mpegts_type = mpegts_pes_type(item_type);

        if(item_type == 0x06)
        {
            const uint8_t *desc_pointer = NULL;
            PMT_ITEM_DESC_FOREACH(pointer, desc_pointer)
            {
                switch(desc_pointer[0])
                {
                    case 0x59:
                        mpegts_type = MPEGTS_PACKET_SUB;
                        break;
                    case 0x6A:
                        mpegts_type = MPEGTS_PACKET_AUDIO;
                        break;
                    default:
                        break;
                }
            }
        }

        mod->pid_types[pid] = mpegts_type;
    }
}

static bool hls_write_ts_packet(module_data_t *mod, const uint8_t *ts)
{
    if(mod->storage_mode == HLS_STORAGE_MEMFD)
    {
        if(mod->segment_fd >= 0)
        {
            const ssize_t written = write(mod->segment_fd, ts, TS_PACKET_SIZE);
            if(written != TS_PACKET_SIZE)
            {
                asc_log_error(MSG("memfd write failed: %s"), strerror(errno));
                return false;
            }
            mod->segment_size_bytes += (size_t)written;
            return true;
        }

        const size_t needed = mod->segment_size_bytes + TS_PACKET_SIZE;
        if(needed > mod->segment_buf_cap)
        {
            size_t next_cap = mod->segment_buf_cap ? (mod->segment_buf_cap * 2) : (TS_PACKET_SIZE * 256);
            if(next_cap < needed)
                next_cap = needed;
            uint8_t *next_buf = (uint8_t *)realloc(mod->segment_buf, next_cap);
            if(!next_buf)
            {
                asc_log_error(MSG("segment buffer realloc failed"));
                return false;
            }
            mod->segment_buf = next_buf;
            mod->segment_buf_cap = next_cap;
        }

        memcpy(mod->segment_buf + mod->segment_size_bytes, ts, TS_PACKET_SIZE);
        mod->segment_size_bytes += TS_PACKET_SIZE;
        return true;
    }

    if(!mod->segment_fp)
        return false;

    const size_t written = fwrite(ts, 1, TS_PACKET_SIZE, mod->segment_fp);
    if(written != TS_PACKET_SIZE)
    {
        asc_log_error(MSG("failed to write segment data [%s]"), strerror(errno));
        return false;
    }

    return true;
}

static void on_ts(module_data_t *mod, const uint8_t *ts)
{
    if(!ts)
        return;

    if(mod->storage_mode == HLS_STORAGE_MEMFD && !mod->hls_active)
        return;

    const uint16_t pid = TS_GET_PID(ts);
    if(!mod->pass_data)
    {
        if(pid == 0 && mod->pat)
            mpegts_psi_mux(mod->pat, ts, on_pat, mod);
        if(mod->pmt && pid == mod->pmt_pid)
            mpegts_psi_mux(mod->pmt, ts, on_pmt, mod);
        if(mod->pid_types[pid] == MPEGTS_PACKET_DATA)
            return;
    }

    if(mod->storage_mode == HLS_STORAGE_MEMFD)
    {
        if(!mod->segment_open)
            hls_open_segment(mod);
        if(!mod->segment_open)
            return;
    }
    else
    {
        if(!mod->segment_fp)
            hls_open_segment(mod);
        if(!mod->segment_fp)
            return;
    }

    if(!hls_write_ts_packet(mod, ts))
    {
        hls_abort_segment(mod);
        return;
    }

    ++mod->segment_packets;

    uint64_t delta_us = 0;
    if(mod->use_wall)
    {
        uint64_t now = asc_utime();
        if(mod->wall_last == 0)
            mod->wall_last = now;
        if(now > mod->wall_last)
            delta_us = now - mod->wall_last;
        mod->wall_last = now;
    }
    else if(TS_IS_PCR(ts))
    {
        uint64_t pcr = TS_GET_PCR(ts);
        if(!mod->has_pcr)
        {
            mod->pcr_last = pcr;
            mod->has_pcr = true;
            delta_us = 0;
        }
        else
        {
            delta_us = mpegts_pcr_block_us(&mod->pcr_last, &pcr);
        }
    }

    mod->segment_elapsed_us += delta_us;

    if(mod->segment_elapsed_us >= mod->segment_target_us)
    {
        hls_finish_segment(mod);
        hls_open_segment(mod);
    }
}

bool hls_memfd_touch(const char *stream_id)
{
    module_data_t *mod = hls_memfd_find_stream(stream_id);
    if(!mod)
        return false;

    mod->last_access_mono = asc_utime();
    if(mod->on_demand && !mod->hls_active)
        hls_memfd_activate(mod);

    return true;
}

char *hls_memfd_copy_playlist(const char *stream_id, size_t *len)
{
    if(len)
        *len = 0;

    module_data_t *mod = hls_memfd_find_stream(stream_id);
    if(!mod || !mod->playlist_buf || mod->playlist_len == 0)
        return NULL;

    char *payload = (char *)malloc(mod->playlist_len);
    if(!payload)
        return NULL;

    memcpy(payload, mod->playlist_buf, mod->playlist_len);
    if(len)
        *len = mod->playlist_len;
    return payload;
}

hls_memfd_segment_t *hls_memfd_segment_acquire(const char *stream_id, const char *name)
{
    module_data_t *mod = hls_memfd_find_stream(stream_id);
    if(!mod || !name)
        return NULL;

    if(mod->segment_buckets && mod->segment_bucket_count > 0)
    {
        const uint32_t hash = hls_memfd_hash_name(name);
        const size_t idx = (size_t)(hash % mod->segment_bucket_count);
        for(hls_memfd_segment_t *seg = mod->segment_buckets[idx]; seg; seg = seg->hash_next)
        {
            if(seg->expired)
                continue;
            if(seg->name_hash == hash && strcmp(seg->name, name) == 0)
            {
                ++seg->refcnt;
                return seg;
            }
        }
    }
    else
    {
        asc_list_for(mod->segments)
        {
            hls_memfd_segment_t *seg = (hls_memfd_segment_t *)asc_list_data(mod->segments);
            if(seg->expired)
                continue;
            if(strcmp(seg->name, name) == 0)
            {
                ++seg->refcnt;
                return seg;
            }
        }
    }

    return NULL;
}

void hls_memfd_segment_release(hls_memfd_segment_t *seg)
{
    if(!seg)
        return;

    if(seg->refcnt > 0)
        --seg->refcnt;

    module_data_t *mod = seg->owner;
    if(!mod)
        return;

    if(seg->expired && seg->refcnt == 0)
    {
        asc_list_remove_item(mod->segments, seg);
        if(mod->segments_count > 0)
            --mod->segments_count;
        hls_memfd_segment_free(mod, seg);
    }
}

int hls_memfd_segment_fd(const hls_memfd_segment_t *seg)
{
    return seg ? seg->memfd : -1;
}

const uint8_t *hls_memfd_segment_data(const hls_memfd_segment_t *seg)
{
    return seg ? seg->data : NULL;
}

size_t hls_memfd_segment_size(const hls_memfd_segment_t *seg)
{
    return seg ? seg->size_bytes : 0;
}

bool hls_memfd_segment_is_memfd(const hls_memfd_segment_t *seg)
{
    return seg && seg->memfd >= 0;
}

void hls_memfd_sweep(uint64_t now_us, int idle_timeout_sec)
{
    if(idle_timeout_sec <= 0 || !hls_memfd_streams)
        return;

    asc_list_for(hls_memfd_streams)
    {
        module_data_t *mod = (module_data_t *)asc_list_data(hls_memfd_streams);
        if(!mod || mod->storage_mode != HLS_STORAGE_MEMFD || !mod->on_demand || !mod->hls_active)
            continue;

        int timeout_sec = (mod->idle_timeout_sec > 0) ? mod->idle_timeout_sec : idle_timeout_sec;
        if(timeout_sec <= 0 || mod->last_access_mono == 0)
            continue;

        const uint64_t idle_us = (uint64_t)timeout_sec * 1000000ULL;
        if(now_us > mod->last_access_mono && (now_us - mod->last_access_mono) >= idle_us)
            hls_memfd_deactivate(mod, "idle");
    }
}

static void module_init(module_data_t *mod)
{
    module_stream_init(mod, on_ts);

    mod->storage_mode = HLS_STORAGE_DISK;
    const char *storage = NULL;
    module_option_string("storage", &storage, NULL);
    if(storage && strcmp(storage, "memfd") == 0)
        mod->storage_mode = HLS_STORAGE_MEMFD;

    module_option_string("stream_id", &mod->stream_id, NULL);

    module_option_string("path", &mod->path, NULL);
    if(mod->storage_mode == HLS_STORAGE_DISK)
        asc_assert(mod->path != NULL, MSG("option 'path' is required"));

    mod->playlist = DEFAULT_PLAYLIST;
    module_option_string("playlist", &mod->playlist, NULL);

    mod->prefix = DEFAULT_PREFIX;
    module_option_string("prefix", &mod->prefix, NULL);

    module_option_string("base_url", &mod->base_url, NULL);

    mod->ts_extension = DEFAULT_TS_EXTENSION;
    module_option_string("ts_extension", &mod->ts_extension, NULL);
    if(mod->ts_extension && mod->ts_extension[0] == '.')
        mod->ts_extension = mod->ts_extension + 1;
    if(!mod->ts_extension || mod->ts_extension[0] == '\0')
        mod->ts_extension = DEFAULT_TS_EXTENSION;

    mod->target_duration_cfg = DEFAULT_TARGET_DURATION;
    module_option_number("target_duration", &mod->target_duration_cfg);
    if(mod->target_duration_cfg < 1)
        mod->target_duration_cfg = DEFAULT_TARGET_DURATION;

    mod->window = DEFAULT_WINDOW;
    module_option_number("window", &mod->window);
    if(mod->window < 1)
        mod->window = DEFAULT_WINDOW;

    mod->cleanup = mod->window * 2;
    module_option_number("cleanup", &mod->cleanup);
    if(mod->cleanup < mod->window)
        mod->cleanup = mod->window * 2;

    mod->on_demand = false;
    module_option_boolean("on_demand", &mod->on_demand);

    mod->idle_timeout_sec = 30;
    module_option_number("idle_timeout_sec", &mod->idle_timeout_sec);

    int max_segments_cfg = 0;
    module_option_number("max_segments", &max_segments_cfg);
    if(max_segments_cfg > 0)
        mod->max_segments = (size_t)max_segments_cfg;
    else
        mod->max_segments = (size_t)mod->cleanup;
    if(mod->max_segments < (size_t)mod->window)
        mod->max_segments = (size_t)mod->window;

    int max_bytes_cfg = 0;
    module_option_number("max_bytes", &max_bytes_cfg);
    if(max_bytes_cfg > 0)
        mod->max_bytes = (size_t)max_bytes_cfg;
    else
        mod->max_bytes = DEFAULT_MAX_BYTES;

#ifdef HLS_MEMFD_DEBUG
    mod->debug_hold_sec = 0;
    module_option_number("debug_hold_sec", &mod->debug_hold_sec);
    if(mod->debug_hold_sec < 0)
        mod->debug_hold_sec = 0;
#endif

    mod->use_wall = true;
    module_option_boolean("use_wall", &mod->use_wall);

    mod->round_duration = false;
    module_option_boolean("round_duration", &mod->round_duration);

    mod->pass_data = true;
    module_option_boolean("pass_data", &mod->pass_data);
    if(!mod->pass_data)
    {
        mod->pat = mpegts_psi_init(MPEGTS_PACKET_PAT, 0);
        mod->pmt = NULL;
        mod->pmt_pid = 0;
        hls_reset_pid_types(mod);
    }

    mod->naming_mode = HLS_NAMING_SEQUENCE;
    const char *naming = NULL;
    module_option_string("naming", &naming, NULL);
    if(naming && strcmp(naming, "pcr") == 0)
        mod->naming_mode = HLS_NAMING_PCR;

    mod->segment_target_us = (uint64_t)mod->target_duration_cfg * 1000000ULL;
    mod->playlist_target = mod->target_duration_cfg;

    mod->segments = asc_list_init();
    mod->segments_count = 0;
    mod->segments_bytes = 0;
    mod->segment_buckets = NULL;
    mod->segment_bucket_count = 0;
#ifdef HLS_MEMFD_DEBUG
    mod->debug_hold_until = 0;
    mod->debug_hold_seg = NULL;
#endif
    mod->seq = -1;
    mod->segment_fd = -1;
    mod->segment_buf = NULL;
    mod->segment_buf_cap = 0;
    mod->segment_size_bytes = 0;
    mod->segment_open = false;
    mod->playlist_buf = NULL;
    mod->playlist_len = 0;
    mod->last_access_mono = 0;

    if(mod->storage_mode == HLS_STORAGE_MEMFD)
    {
        asc_assert(mod->stream_id && mod->stream_id[0] != '\0',
                   MSG("memfd storage requires stream_id"));
        mod->memfd_enabled = hls_memfd_is_available();
        if(!mod->memfd_enabled)
            asc_log_warning(MSG("memfd not available, falling back to memory for stream=%s"),
                            mod->stream_id ? mod->stream_id : "?");
        mod->hls_active = !mod->on_demand;
        size_t bucket_count = mod->max_segments ? (mod->max_segments * 2) : 32;
        if(bucket_count < 32)
            bucket_count = 32;
        mod->segment_buckets = (hls_memfd_segment_t **)calloc(bucket_count, sizeof(*mod->segment_buckets));
        if(mod->segment_buckets)
            mod->segment_bucket_count = bucket_count;
        else
            asc_log_warning(MSG("segment map disabled (alloc failed) stream=%s"),
                            mod->stream_id ? mod->stream_id : "?");
        hls_memfd_register_stream(mod);
    }
    else
    {
        mod->memfd_enabled = false;
        mod->hls_active = true;
        mkdir_p(mod->path);
    }
}

static void module_destroy(module_data_t *mod)
{
    hls_finish_segment(mod);

    if(mod->storage_mode == HLS_STORAGE_MEMFD)
        hls_memfd_unregister_stream(mod);

    if(mod->segment_fp)
    {
        fclose(mod->segment_fp);
        mod->segment_fp = NULL;
    }
    if(mod->segment_fd >= 0)
    {
        close(mod->segment_fd);
        mod->segment_fd = -1;
    }
    if(mod->segment_buf)
    {
        free(mod->segment_buf);
        mod->segment_buf = NULL;
        mod->segment_buf_cap = 0;
    }
    if(mod->playlist_buf)
    {
        free(mod->playlist_buf);
        mod->playlist_buf = NULL;
        mod->playlist_len = 0;
    }

    if(mod->segments)
    {
        asc_list_for(mod->segments)
        {
            hls_memfd_segment_t *seg = (hls_memfd_segment_t *)asc_list_data(mod->segments);
            hls_memfd_segment_free(mod, seg);
        }
        asc_list_destroy(mod->segments);
        mod->segments = NULL;
    }
    if(mod->segment_buckets)
    {
        free(mod->segment_buckets);
        mod->segment_buckets = NULL;
        mod->segment_bucket_count = 0;
    }

    if(mod->pat)
    {
        mpegts_psi_destroy(mod->pat);
        mod->pat = NULL;
    }
    if(mod->pmt)
    {
        mpegts_psi_destroy(mod->pmt);
        mod->pmt = NULL;
    }

    module_stream_destroy(mod);
}

MODULE_STREAM_METHODS()
MODULE_LUA_METHODS()
{
    { "discontinuity", method_discontinuity },
    { "stats", method_stats },
    MODULE_STREAM_METHODS_REF(),
};

MODULE_LUA_REGISTER(hls_output)
