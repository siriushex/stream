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
};

#define MSG(_msg) "[jitter] " _msg

static void jitter_flush(module_data_t *mod)
{
    if(mod->capacity == 0 || mod->config.jitter_ms == 0)
        return;

    const uint64_t now = asc_utime();
    const uint64_t target_us = (uint64_t)mod->config.jitter_ms * 1000ULL;

    while(mod->count > 0)
    {
        const uint64_t ts = mod->timestamps[mod->head];
        if(now < ts || (now - ts) < target_us)
            break;

        const uint8_t *pkt = mod->buffer + (mod->head * TS_PACKET_SIZE);
        module_stream_send(mod, pkt);
        mod->last_send_ts = now;

        mod->head = (mod->head + 1) % mod->capacity;
        mod->count--;
    }

    if(mod->count == 0)
    {
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

static void on_ts(module_data_t *mod, const uint8_t *ts)
{
    if(mod->capacity == 0 || mod->config.jitter_ms == 0)
    {
        module_stream_send(mod, ts);
        return;
    }

    if(mod->count >= mod->capacity)
    {
        // Буфер переполнен: сбрасываем самый старый пакет, чтобы не расти в памяти.
        mod->head = (mod->head + 1) % mod->capacity;
        mod->count--;
        mod->underruns_total++;
    }

    memcpy(mod->buffer + (mod->tail * TS_PACKET_SIZE), ts, TS_PACKET_SIZE);
    mod->timestamps[mod->tail] = asc_utime();
    mod->tail = (mod->tail + 1) % mod->capacity;
    mod->count++;

    jitter_flush(mod);
}

static int method_stats(module_data_t *mod)
{
    lua_newtable(lua);

    const uint64_t now = asc_utime();
    uint64_t fill_ms = 0;
    if(mod->count > 0 && mod->capacity > 0)
    {
        const uint64_t ts = mod->timestamps[mod->head];
        if(now > ts)
            fill_ms = (now - ts) / 1000ULL;
    }

    lua_pushnumber(lua, (lua_Number)fill_ms);
    lua_setfield(lua, -2, "buffer_fill_ms");
    lua_pushnumber(lua, (lua_Number)mod->config.jitter_ms);
    lua_setfield(lua, -2, "buffer_target_ms");
    lua_pushnumber(lua, (lua_Number)mod->underruns_total);
    lua_setfield(lua, -2, "buffer_underruns_total");

    return 1;
}

static void module_init(module_data_t *mod)
{
    module_stream_init(mod, on_ts);

    double value = 0;
    if(module_option_number("jitter_buffer_ms", &value) && value > 0)
        mod->config.jitter_ms = (uint32_t)value;
    else
        mod->config.jitter_ms = 0;

    double max_mb = 0;
    if(module_option_number("max_buffer_mb", &max_mb) && max_mb > 0)
        mod->config.max_buffer_bytes = (size_t)(max_mb * 1024.0 * 1024.0);
    else
        mod->config.max_buffer_bytes = (size_t)(4 * 1024 * 1024);

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
