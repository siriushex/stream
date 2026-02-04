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
#include <limits.h>
#include <math.h>
#include <sys/stat.h>
#include <unistd.h>

#define MSG(_msg) "[hls_output] " _msg

#define DEFAULT_TARGET_DURATION 6
#define DEFAULT_WINDOW 5
#define DEFAULT_PREFIX "segment"
#define DEFAULT_PLAYLIST "index.m3u8"
#define DEFAULT_TS_EXTENSION "ts"

#define HLS_NAMING_SEQUENCE 0
#define HLS_NAMING_PCR 1

typedef struct
{
    int64_t seq;
    double duration;
    char name[128];
    bool discontinuity;
} hls_segment_t;

struct module_data_t
{
    MODULE_STREAM_DATA();

    const char *path;
    const char *playlist;
    const char *prefix;
    const char *base_url;
    const char *ts_extension;
    bool pass_data;

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
    char segment_name[128];
    size_t segment_packets;
    bool discontinuity_pending;

    asc_list_t *segments;
    size_t segments_count;

    mpegts_psi_t *pat;
    mpegts_psi_t *pmt;
    uint16_t pmt_pid;
    mpegts_packet_type_t pid_types[MAX_PID];
};

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

static void hls_write_playlist(module_data_t *mod)
{
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

        hls_segment_t *seg = (hls_segment_t *)asc_list_data(mod->segments);
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
    while(mod->segments_count > (size_t)mod->cleanup)
    {
        asc_list_first(mod->segments);
        if(asc_list_eol(mod->segments))
            return;

        hls_segment_t *seg = (hls_segment_t *)asc_list_data(mod->segments);
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
    if(mod->segment_fp)
    {
        fclose(mod->segment_fp);
        mod->segment_fp = NULL;
    }

    if(mod->segment_packets == 0)
    {
        mod->segment_elapsed_us = 0;
        return;
    }

    hls_segment_t *seg = (hls_segment_t *)calloc(1, sizeof(*seg));
    seg->seq = mod->seq;
    double duration = (double)mod->segment_elapsed_us / 1000000.0;
    if(mod->round_duration)
        duration = ceil(duration);
    seg->duration = duration;
    snprintf(seg->name, sizeof(seg->name), "%s", mod->segment_name);
    seg->discontinuity = mod->discontinuity_pending;
    mod->discontinuity_pending = false;

    int duration_ceil = (int)ceil(seg->duration);
    if(duration_ceil < 1)
        duration_ceil = 1;
    if(duration_ceil > mod->playlist_target)
        mod->playlist_target = duration_ceil;

    asc_list_insert_tail(mod->segments, seg);
    ++mod->segments_count;

    hls_cleanup_segments(mod);
    hls_write_playlist(mod);

    mod->segment_elapsed_us = 0;
    mod->segment_packets = 0;
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

    if(mod->segment_fp && mod->segment_packets > 0)
    {
        hls_finish_segment(mod);
    }
    else if(mod->segment_fp)
    {
        fclose(mod->segment_fp);
        mod->segment_fp = NULL;
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

static void on_ts(module_data_t *mod, const uint8_t *ts)
{
    if(!ts)
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

    if(!mod->segment_fp)
        hls_open_segment(mod);

    if(!mod->segment_fp)
        return;

    fwrite(ts, 1, TS_PACKET_SIZE, mod->segment_fp);
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

static void module_init(module_data_t *mod)
{
    module_stream_init(mod, on_ts);

    module_option_string("path", &mod->path, NULL);
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

    mkdir_p(mod->path);

    mod->segments = asc_list_init();
    mod->seq = -1;
}

static void module_destroy(module_data_t *mod)
{
    hls_finish_segment(mod);

    if(mod->segment_fp)
    {
        fclose(mod->segment_fp);
        mod->segment_fp = NULL;
    }

    if(mod->segments)
    {
        asc_list_for(mod->segments)
        {
            hls_segment_t *seg = (hls_segment_t *)asc_list_data(mod->segments);
            free(seg);
        }
        asc_list_destroy(mod->segments);
        mod->segments = NULL;
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
    MODULE_STREAM_METHODS_REF(),
};

MODULE_LUA_REGISTER(hls_output)
