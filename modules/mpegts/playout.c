/*
 * Astra Module: MPEG-TS (Playout Pacer)
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
 *      playout
 *
 * Назначение:
 *  - Пейсить выдачу MPEG-TS ровно по времени (anti-jitter / playout pacer).
 *  - При нехватке данных (пустой буфер) вставлять NULL-пакеты (PID=0x1FFF),
 *    чтобы транспорт не "рвался" и /play не залипал на длинных паузах входа.
 *
 * Важно:
 *  - Это opt-in модуль, включается только когда оператор явно включил playout в input.
 *  - NULL stuffing имеет смысл только если downstream не выкидывает NULL PID.
 *
 * Module Options:
 *      upstream                 - object, stream instance returned by module_instance:stream()
 *
 *      playout_mode             - string: "auto" (default) or "cbr"
 *      playout_target_kbps      - number or string "auto" (default: auto)
 *      playout_tick_ms          - number, pacing tick (default: 10)
 *      playout_null_stuffing    - bool/number (default: true)
 *
 *      playout_min_fill_ms      - number (default: 0)  - пока fill меньше, отдаём NULL (prebuffer)
 *      playout_target_fill_ms   - number (default: 0)  - пока только для статуса/внешней логики
 *      playout_max_fill_ms      - number (default: 60000) - пока только для статуса/внешней логики
 *      playout_max_buffer_mb    - number (default: 16)
 *
 *      assumed_mbps             - number, initial bitrate estimate for auto mode (default: 6)
 */

#include <astra.h>
#include "mpegts.h"

struct module_data_t
{
    MODULE_STREAM_DATA();

    struct
    {
        bool null_stuffing;
        bool mode_cbr;
        uint64_t target_bitrate_bps; /* только для CBR */
        uint64_t assumed_bitrate_bps; /* fallback для auto */
        uint32_t tick_ms;

        uint32_t min_fill_ms;
        uint32_t target_fill_ms;
        uint32_t max_fill_ms;

        size_t max_buffer_bytes;
    } config;

    uint8_t *buffer;
    size_t capacity;
    size_t head;
    size_t tail;
    size_t count;

    asc_timer_t *timer;
    uint64_t last_tick_ts;
    double pkt_credit;

    /* Оценка входного битрейта (EMA) - для auto режима. */
    double in_bitrate_bps_ema;
    uint64_t in_window_start_ts;
    size_t in_window_bytes;

    /* Оценка выходного битрейта (EMA) - для статуса/диагностики. */
    double out_bitrate_bps_ema;
    uint64_t out_window_start_ts;
    size_t out_window_bytes;

    /* NULL stuffing / underrun статистика */
    uint64_t null_packets_total;
    uint64_t underruns_total;
    uint64_t underrun_ms_total;
    uint64_t drops_total;

    bool in_underrun;
    uint64_t underrun_start_ts;
    uint64_t last_target_bps;
    uint8_t null_cc;
};

#define MSG(_msg) "[playout] " _msg

static inline void playout_update_in_bitrate(module_data_t *mod, uint64_t now)
{
    /* Накапливаем байты минимум за 1 секунду "реального" времени,
     * чтобы burst delivery не давал ложный огромный bitrate. */
    const uint64_t window_us = 1000000ULL;
    if(mod->in_window_start_ts == 0)
    {
        mod->in_window_start_ts = now;
        mod->in_window_bytes = TS_PACKET_SIZE;
        return;
    }

    mod->in_window_bytes += TS_PACKET_SIZE;
    const uint64_t delta = now - mod->in_window_start_ts;
    if(delta < window_us)
        return;

    const double inst_bps = ((double)mod->in_window_bytes * 8.0 * 1000000.0) / (double)delta;
    if(inst_bps > 1000.0)
    {
        if(mod->in_bitrate_bps_ema <= 0.0)
            mod->in_bitrate_bps_ema = inst_bps;
        else
            mod->in_bitrate_bps_ema = (mod->in_bitrate_bps_ema * 0.8) + (inst_bps * 0.2);
    }

    mod->in_window_start_ts = now;
    mod->in_window_bytes = 0;
}

static inline void playout_update_out_bitrate(module_data_t *mod, uint64_t now, size_t bytes_sent)
{
    const uint64_t window_us = 1000000ULL;
    if(mod->out_window_start_ts == 0)
    {
        mod->out_window_start_ts = now;
        mod->out_window_bytes = bytes_sent;
        return;
    }

    mod->out_window_bytes += bytes_sent;
    const uint64_t delta = now - mod->out_window_start_ts;
    if(delta < window_us)
        return;

    const double inst_bps = ((double)mod->out_window_bytes * 8.0 * 1000000.0) / (double)delta;
    if(inst_bps > 1000.0)
    {
        if(mod->out_bitrate_bps_ema <= 0.0)
            mod->out_bitrate_bps_ema = inst_bps;
        else
            mod->out_bitrate_bps_ema = (mod->out_bitrate_bps_ema * 0.8) + (inst_bps * 0.2);
    }

    mod->out_window_start_ts = now;
    mod->out_window_bytes = 0;
}

static inline uint64_t playout_get_target_bps(module_data_t *mod)
{
    uint64_t bps = 0;
    if(mod->config.mode_cbr && mod->config.target_bitrate_bps > 0)
    {
        bps = mod->config.target_bitrate_bps;
    }
    else
    {
        if(mod->in_bitrate_bps_ema > 0.0)
            bps = (uint64_t)mod->in_bitrate_bps_ema;
        else
            bps = mod->config.assumed_bitrate_bps;
    }

    if(bps < 100000ULL)
        bps = 100000ULL;
    if(bps > 200000000ULL)
        bps = 200000000ULL;

    return bps;
}

static inline uint64_t playout_buffer_fill_ms(module_data_t *mod, uint64_t target_bps)
{
    if(mod->count == 0)
        return 0;
    if(target_bps == 0)
        return 0;
    const uint64_t bytes = (uint64_t)mod->count * (uint64_t)TS_PACKET_SIZE;
    const uint64_t bits = bytes * 8ULL;
    return (bits * 1000ULL) / target_bps;
}

static inline void playout_make_null(uint8_t *pkt, uint8_t cc)
{
    /* NULL packet: PID=0x1FFF, payload 0xFF, continuity counter по кругу. */
    memset(pkt, 0xFF, TS_PACKET_SIZE);
    pkt[0] = 0x47;
    pkt[1] = 0x1F;
    pkt[2] = 0xFF;
    pkt[3] = 0x10 | (cc & 0x0F); /* payload only */
}

static inline void playout_send_one(module_data_t *mod, uint64_t now, uint64_t target_bps)
{
    /* Если задан min_fill_ms - не отдаём "живые" пакеты, пока буфер не набрал запас.
     * В это время выдаём NULL, чтобы транспорт был непрерывным. */
    const uint64_t fill_ms = playout_buffer_fill_ms(mod, target_bps);
    const bool prebuffer = (mod->config.min_fill_ms > 0 && fill_ms < mod->config.min_fill_ms);

    if(mod->count > 0 && !prebuffer)
    {
        const uint8_t *pkt = mod->buffer + (mod->head * TS_PACKET_SIZE);
        module_stream_send(mod, pkt);
        playout_update_out_bitrate(mod, now, TS_PACKET_SIZE);

        mod->head = (mod->head + 1) % mod->capacity;
        mod->count--;

        if(mod->in_underrun && mod->underrun_start_ts > 0)
        {
            const uint64_t delta = now > mod->underrun_start_ts ? (now - mod->underrun_start_ts) : 0;
            mod->underrun_ms_total += delta / 1000ULL;
            mod->in_underrun = false;
            mod->underrun_start_ts = 0;
        }
        return;
    }

    if(!mod->config.null_stuffing)
    {
        /* NULL stuffing отключён: просто молчим (совместимо с "старым" поведением). */
        return;
    }

    uint8_t pkt[TS_PACKET_SIZE];
    playout_make_null(pkt, mod->null_cc);
    mod->null_cc = (mod->null_cc + 1) & 0x0F;

    module_stream_send(mod, pkt);
    playout_update_out_bitrate(mod, now, TS_PACKET_SIZE);

    mod->null_packets_total++;
    if(!mod->in_underrun)
    {
        mod->underruns_total++;
        mod->in_underrun = true;
        mod->underrun_start_ts = now;
    }
}

static void playout_flush(module_data_t *mod)
{
    if(mod->capacity == 0)
        return;

    const uint64_t now = asc_utime();
    const uint64_t target_bps = playout_get_target_bps(mod);
    mod->last_target_bps = target_bps;

    if(mod->last_tick_ts == 0)
    {
        mod->last_tick_ts = now;
        return;
    }

    uint64_t delta_us = now - mod->last_tick_ts;
    mod->last_tick_ts = now;

    /* Накопим "кредит" пакетов на отправку за прошедшее время. */
    const double pkts = ((double)delta_us * (double)target_bps) / 1000000.0 / 8.0 / (double)TS_PACKET_SIZE;
    if(pkts > 0.0)
        mod->pkt_credit += pkts;

    /* Не даём обработчику зависнуть на огромном due (если таймер проснулся поздно). */
    const uint32_t max_send = 5000;
    uint32_t sent = 0;
    while(mod->pkt_credit >= 1.0 && sent < max_send)
    {
        playout_send_one(mod, now, target_bps);
        mod->pkt_credit -= 1.0;
        sent++;
    }
}

static void playout_timer(void *arg)
{
    module_data_t *mod = (module_data_t *)arg;
    playout_flush(mod);
}

static void on_ts(module_data_t *mod, const uint8_t *ts)
{
    if(mod->capacity == 0)
    {
        module_stream_send(mod, ts);
        return;
    }

    const uint64_t now = asc_utime();
    playout_update_in_bitrate(mod, now);

    if(mod->count >= mod->capacity)
    {
        /* Буфер переполнен: сбрасываем самый старый пакет. */
        mod->head = (mod->head + 1) % mod->capacity;
        mod->count--;
        mod->drops_total++;
    }

    memcpy(mod->buffer + (mod->tail * TS_PACKET_SIZE), ts, TS_PACKET_SIZE);
    mod->tail = (mod->tail + 1) % mod->capacity;
    mod->count++;

    /* Попробуем сразу "догнать" таймлайн (уменьшает задержку при burst delivery). */
    playout_flush(mod);
}

static int method_stats(module_data_t *mod)
{
    lua_newtable(lua);

    const uint64_t now = asc_utime();
    const uint64_t target_bps = playout_get_target_bps(mod);
    const uint64_t fill_ms = playout_buffer_fill_ms(mod, target_bps);

    uint64_t underrun_ms = mod->underrun_ms_total;
    if(mod->in_underrun && mod->underrun_start_ts > 0 && now > mod->underrun_start_ts)
    {
        underrun_ms += (now - mod->underrun_start_ts) / 1000ULL;
    }

    lua_pushboolean(lua, true);
    lua_setfield(lua, -2, "playout_enabled");

    lua_pushnumber(lua, (lua_Number)(target_bps / 1000ULL));
    lua_setfield(lua, -2, "target_kbps");
    lua_pushnumber(lua, (lua_Number)(mod->out_bitrate_bps_ema / 1000.0));
    lua_setfield(lua, -2, "current_kbps");

    lua_pushnumber(lua, (lua_Number)fill_ms);
    lua_setfield(lua, -2, "buffer_fill_ms");
    lua_pushnumber(lua, (lua_Number)mod->config.target_fill_ms);
    lua_setfield(lua, -2, "buffer_target_ms");
    lua_pushnumber(lua, (lua_Number)((uint64_t)mod->count * (uint64_t)TS_PACKET_SIZE));
    lua_setfield(lua, -2, "buffer_bytes");

    lua_pushnumber(lua, (lua_Number)mod->null_packets_total);
    lua_setfield(lua, -2, "null_packets_total");
    lua_pushnumber(lua, (lua_Number)mod->underruns_total);
    lua_setfield(lua, -2, "underruns_total");
    lua_pushnumber(lua, (lua_Number)underrun_ms);
    lua_setfield(lua, -2, "underrun_ms_total");
    lua_pushnumber(lua, (lua_Number)mod->drops_total);
    lua_setfield(lua, -2, "drops_total");

    return 1;
}

static void module_init(module_data_t *mod)
{
    module_stream_init(mod, on_ts);

    /* tick */
    int tick_ms = 0;
    if(module_option_number("playout_tick_ms", &tick_ms) && tick_ms > 0)
        mod->config.tick_ms = (uint32_t)tick_ms;
    else
        mod->config.tick_ms = 10;
    if(mod->config.tick_ms < 2)
        mod->config.tick_ms = 2;
    if(mod->config.tick_ms > 200)
        mod->config.tick_ms = 200;

    /* null stuffing */
    mod->config.null_stuffing = true;
    int ns = 0;
    if(module_option_number("playout_null_stuffing", &ns))
        mod->config.null_stuffing = (ns != 0);
    else if(module_option_boolean("playout_null_stuffing", &mod->config.null_stuffing))
        ; /* parsed */

    /* mode */
    mod->config.mode_cbr = false;
    const char *mode = NULL;
    module_option_string("playout_mode", &mode, NULL);
    if(mode && !strcmp(mode, "cbr"))
        mod->config.mode_cbr = true;

    /* target kbps */
    mod->config.target_bitrate_bps = 0;
    const char *target = NULL;
    module_option_string("playout_target_kbps", &target, NULL);
    if(target && strcmp(target, "auto") != 0)
    {
        const int kbps = atoi(target);
        if(kbps > 0)
            mod->config.target_bitrate_bps = (uint64_t)kbps * 1000ULL;
    }
    int target_num = 0;
    if(mod->config.target_bitrate_bps == 0 && module_option_number("playout_target_kbps", &target_num) && target_num > 0)
        mod->config.target_bitrate_bps = (uint64_t)target_num * 1000ULL;

    if(mod->config.mode_cbr && mod->config.target_bitrate_bps == 0)
    {
        /* CBR без target - бессмысленно, откатываемся в auto. */
        mod->config.mode_cbr = false;
    }

    /* assumed_mbps */
    int assumed_mbps = 0;
    if(module_option_number("assumed_mbps", &assumed_mbps) && assumed_mbps > 0)
        mod->config.assumed_bitrate_bps = (uint64_t)assumed_mbps * 1000ULL * 1000ULL;
    else
        mod->config.assumed_bitrate_bps = 6ULL * 1000ULL * 1000ULL;

    /* fill params */
    int n = 0;
    if(module_option_number("playout_min_fill_ms", &n) && n > 0)
        mod->config.min_fill_ms = (uint32_t)n;
    else
        mod->config.min_fill_ms = 0;
    if(module_option_number("playout_target_fill_ms", &n) && n > 0)
        mod->config.target_fill_ms = (uint32_t)n;
    else
        mod->config.target_fill_ms = 0;
    if(module_option_number("playout_max_fill_ms", &n) && n > 0)
        mod->config.max_fill_ms = (uint32_t)n;
    else
        mod->config.max_fill_ms = 60000;

    /* buffer mb */
    int max_mb = 0;
    if(module_option_number("playout_max_buffer_mb", &max_mb) && max_mb > 0)
        mod->config.max_buffer_bytes = (size_t)max_mb * (size_t)1024 * (size_t)1024;
    else
        mod->config.max_buffer_bytes = (size_t)(16 * 1024 * 1024);

    if(mod->config.max_buffer_bytes < (size_t)(TS_PACKET_SIZE * 64))
        mod->config.max_buffer_bytes = (size_t)(TS_PACKET_SIZE * 64);

    mod->capacity = mod->config.max_buffer_bytes / TS_PACKET_SIZE;
    if(mod->capacity < 64)
        mod->capacity = 64;

    mod->buffer = (uint8_t *)malloc(mod->capacity * TS_PACKET_SIZE);
    if(!mod->buffer)
    {
        asc_log_error(MSG("malloc failed"));
        mod->capacity = 0;
        return;
    }

    mod->head = 0;
    mod->tail = 0;
    mod->count = 0;
    mod->timer = asc_timer_init((int)mod->config.tick_ms, playout_timer, mod);

    mod->last_tick_ts = 0;
    mod->pkt_credit = 0.0;
    mod->null_cc = 0;
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
    mod->capacity = 0;
    module_stream_destroy(mod);
}

MODULE_STREAM_METHODS()
MODULE_LUA_METHODS()
{
    { "stats", method_stats },
    MODULE_STREAM_METHODS_REF()
};

MODULE_LUA_REGISTER(playout)
