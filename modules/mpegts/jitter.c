/*
 * Astra Module: MPEG-TS (Jitter Buffer)
 * http://cesbo.com/astra
 *
 * Copyright (C) 2026
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
 *      jitter
 *
 * Module Options:
 *      upstream           - object, stream instance returned by module_instance:stream()
 *      jitter_buffer_ms   - number, target delay in milliseconds
 *      max_buffer_mb      - number, memory limit for buffer (MB)
 *      assumed_mbps       - number, initial bitrate estimate (Mbps) for output pacing
 */

#include <astra.h>
#include "mpegts.h"

struct module_data_t
{
    MODULE_STREAM_DATA();

    struct
    {
        uint32_t jitter_ms;
        size_t max_buffer_bytes;
        uint64_t assumed_bitrate_bps;
    } config;

    uint8_t *buffer;
    uint64_t *timestamps;
    size_t capacity;
    size_t head;
    size_t tail;
    size_t count;

    asc_timer_t *timer;

    bool in_underrun;
    uint64_t last_send_ts;
    uint32_t underruns_total;
    uint32_t drops_total;

    /* Оценка входного битрейта (EMA), чтобы пейсить выход и не отдавать burst'ами.
     * Это критично для IPTV-панелей, которые отдают TS рывками: фиксированная задержка
     * без пейсинга даёт длинные паузы и клиенты воспринимают поток как "пропал". */
    double bitrate_bps_ema;
    uint64_t rate_window_start_ts;
    size_t rate_window_bytes;

    uint64_t last_sched_ts;
};

#define MSG(_msg) "[jitter] " _msg

static void jitter_flush(module_data_t *mod)
{
    if(mod->capacity == 0 || mod->config.jitter_ms == 0)
        return;

    const uint64_t now = asc_utime();

    while(mod->count > 0)
    {
        const uint64_t ts = mod->timestamps[mod->head];
        if(now < ts)
            break;

        const uint8_t *pkt = mod->buffer + (mod->head * TS_PACKET_SIZE);
        module_stream_send(mod, pkt);
        mod->last_send_ts = now;

        mod->head = (mod->head + 1) % mod->capacity;
        mod->count--;
    }

    if(mod->count == 0)
    {
        /* Буфер пуст: следующий пакет должен начать новый таймлайн. */
        mod->last_sched_ts = 0;
        if(!mod->in_underrun && mod->last_send_ts > 0)
        {
            mod->underruns_total++;
            mod->in_underrun = true;
        }
    }
    else
    {
        mod->in_underrun = false;
    }
}

static void jitter_timer(void *arg)
{
    module_data_t *mod = (module_data_t *)arg;
    jitter_flush(mod);
}

static inline void jitter_update_bitrate(module_data_t *mod, uint64_t now)
{
    /* Накапливаем байты минимум за 1 секунду "реального" времени,
     * чтобы burst delivery не давал ложный огромный bitrate. */
    const uint64_t window_us = 1000000ULL;
    if(mod->rate_window_start_ts == 0)
    {
        mod->rate_window_start_ts = now;
        mod->rate_window_bytes = TS_PACKET_SIZE;
        return;
    }

    mod->rate_window_bytes += TS_PACKET_SIZE;
    const uint64_t delta = now - mod->rate_window_start_ts;
    if(delta < window_us)
        return;

    const double inst_bps = ((double)mod->rate_window_bytes * 8.0 * 1000000.0) / (double)delta;
    if(inst_bps > 1000.0)
    {
        if(mod->bitrate_bps_ema <= 0.0)
            mod->bitrate_bps_ema = inst_bps;
        else
            mod->bitrate_bps_ema = (mod->bitrate_bps_ema * 0.8) + (inst_bps * 0.2);
    }

    mod->rate_window_start_ts = now;
    mod->rate_window_bytes = 0;
}

static inline uint64_t jitter_packet_interval_us(module_data_t *mod)
{
    double bps = mod->bitrate_bps_ema;
    if(bps <= 0.0)
        bps = (double)mod->config.assumed_bitrate_bps;
    if(bps < 100000.0)
        bps = 100000.0;

    const double bits_per_pkt = (double)(TS_PACKET_SIZE * 8);
    double interval = (bits_per_pkt * 1000000.0) / bps;
    if(interval < 50.0)
        interval = 50.0;
    /* Не даём слишком большой шаг, иначе при низком bitrate будет "ступенчатая" отдача. */
    if(interval > 20000.0)
        interval = 20000.0;
    return (uint64_t)interval;
}

static void on_ts(module_data_t *mod, const uint8_t *ts)
{
    if(mod->capacity == 0 || mod->config.jitter_ms == 0)
    {
        module_stream_send(mod, ts);
        return;
    }

    const uint64_t now = asc_utime();
    jitter_update_bitrate(mod, now);

    if(mod->count >= mod->capacity)
    {
        // Буфер переполнен: сбрасываем самый старый пакет, чтобы не расти в памяти.
        mod->head = (mod->head + 1) % mod->capacity;
        mod->count--;
        mod->drops_total++;
    }

    memcpy(mod->buffer + (mod->tail * TS_PACKET_SIZE), ts, TS_PACKET_SIZE);
    const uint64_t jitter_us = (uint64_t)mod->config.jitter_ms * 1000ULL;
    /* Важно: это "настоящий" jitter buffer, который сглаживает рывки доставки.
     * Поэтому после стартового прогона (prebuffer) мы НЕ привязываем график выдачи к `now`,
     * иначе любые паузы в приёме будут полностью переноситься в выдачу (и анализатор видит `no_data`).
     * Вместо этого строим непрерывный таймлайн выдачи: пока в буфере есть данные, выдаём с пейсингом. */
    uint64_t sched = 0;
    if(mod->last_sched_ts == 0)
    {
        /* Первый пакет после старта/полного опустошения: даём набрать target buffer. */
        sched = now + jitter_us;
    }
    else
    {
        sched = mod->last_sched_ts + jitter_packet_interval_us(mod);
    }
    mod->timestamps[mod->tail] = sched;
    mod->last_sched_ts = sched;
    mod->tail = (mod->tail + 1) % mod->capacity;
    mod->count++;

    jitter_flush(mod);
}

static int method_stats(module_data_t *mod)
{
    lua_newtable(lua);

    const uint64_t now = asc_utime();
    /* Текущий "запас" по времени: сколько данных ещё есть до опустошения буфера
     * при текущем пейсинге (в миллисекундах). */
    uint64_t fill_ms = 0;
    if(mod->count > 0 && mod->last_sched_ts > now)
        fill_ms = (mod->last_sched_ts - now) / 1000ULL;

    lua_pushnumber(lua, (lua_Number)fill_ms);
    lua_setfield(lua, -2, "buffer_fill_ms");
    lua_pushnumber(lua, (lua_Number)mod->config.jitter_ms);
    lua_setfield(lua, -2, "buffer_target_ms");
    lua_pushnumber(lua, (lua_Number)mod->underruns_total);
    lua_setfield(lua, -2, "buffer_underruns_total");
    lua_pushnumber(lua, (lua_Number)mod->drops_total);
    lua_setfield(lua, -2, "buffer_drops_total");

    return 1;
}

static void module_init(module_data_t *mod)
{
    module_stream_init(mod, on_ts);

    int value = 0;
    if(module_option_number("jitter_buffer_ms", &value) && value > 0)
        mod->config.jitter_ms = (uint32_t)value;
    else
        mod->config.jitter_ms = 0;

    int max_mb = 0;
    if(module_option_number("max_buffer_mb", &max_mb) && max_mb > 0)
        mod->config.max_buffer_bytes = (size_t)max_mb * (size_t)1024 * (size_t)1024;
    else
        mod->config.max_buffer_bytes = (size_t)(4 * 1024 * 1024);

    int assumed_mbps = 0;
    if(module_option_number("assumed_mbps", &assumed_mbps) && assumed_mbps > 0)
        mod->config.assumed_bitrate_bps = (uint64_t)assumed_mbps * 1000ULL * 1000ULL;
    else
        mod->config.assumed_bitrate_bps = 6ULL * 1000ULL * 1000ULL;

    if(mod->config.jitter_ms > 0 && mod->config.max_buffer_bytes >= TS_PACKET_SIZE)
    {
        mod->capacity = mod->config.max_buffer_bytes / TS_PACKET_SIZE;
        if(mod->capacity < 64)
            mod->capacity = 64;
        mod->buffer = (uint8_t *)malloc(mod->capacity * TS_PACKET_SIZE);
        mod->timestamps = (uint64_t *)calloc(mod->capacity, sizeof(uint64_t));
        mod->head = 0;
        mod->tail = 0;
        mod->count = 0;
        mod->timer = asc_timer_init(20, jitter_timer, mod);
    }
}

static void module_destroy(module_data_t *mod)
{
    if(mod->timer)
    {
        asc_timer_destroy(mod->timer);
        mod->timer = NULL;
    }
    free(mod->buffer);
    mod->buffer = NULL;
    free(mod->timestamps);
    mod->timestamps = NULL;
    mod->capacity = 0;
    module_stream_destroy(mod);
}

MODULE_STREAM_METHODS()
MODULE_LUA_METHODS()
{
    { "stats", method_stats },
    MODULE_STREAM_METHODS_REF()
};

MODULE_LUA_REGISTER(jitter)
