/*
 * Astra Module: HTTP Request
 * http://cesbo.com/astra
 *
 * Copyright (C) 2012-2015, Andrey Dyldin <and@cesbo.com>
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
 *      http_request
 *
 * Module Options:
 *      host        - string, server hostname or IP address
 *      port        - number, server port (default: 80)
 *      path        - string, request path
 *      method      - string, method (default: "GET")
 *      version     - string, HTTP version (default: "HTTP/1.1")
 *      headers     - table, list of the request headers
 *      content     - string, request content
 *      stream      - boolean, true to read MPEG-TS stream
 *      sync        - boolean or number, enable stream synchronization
 *      sctp        - boolean, use sctp instead of tcp
 *      timeout     - number, request timeout
 *      connect_timeout_ms - number, connection timeout (ms)
 *      read_timeout_ms    - number, response timeout (ms)
 *      stall_timeout_ms   - number, stream stall timeout (ms)
 *      low_speed_limit_bytes_sec - number, minimum read speed (bytes/sec)
 *      low_speed_time_sec        - number, low-speed window (sec)
 *      callback    - function,
 *      upstream    - object, stream instance returned by module_instance:stream()
 */

#include "http.h"

#ifdef HAVE_OPENSSL
#include <openssl/ssl.h>
#include <openssl/err.h>
#include <openssl/x509v3.h>
#endif

#define MSG(_msg)                                       \
    "[http_request %s:%d%s] " _msg, mod->config.host    \
                                  , mod->config.port    \
                                  , mod->config.path

struct module_data_t
{
    MODULE_STREAM_DATA();

    struct
    {
        const char *host;
        int port;
        const char *path;
        bool sync;
    } config;

    int timeout_ms;
    int connect_timeout_ms;
    int response_timeout_ms;
    int stall_timeout_ms;
    int low_speed_limit;
    int low_speed_time_sec;
    uint64_t last_io_ts;
    uint64_t low_speed_start_ts;
    size_t low_speed_bytes;
    bool is_stream;

    int idx_self;

    asc_socket_t *sock;
    asc_timer_t *timeout;

    bool is_socket_busy;
    bool is_tls;
    bool tls_verify;

#ifdef HAVE_OPENSSL
    SSL_CTX *tls_ctx;
    SSL *tls;
#endif

    // request
    struct
    {
        int status; // 1 - connected, 2 - request done

        const char *buffer;
        size_t skip;
        size_t size;

        int idx_body;
    } request;

    bool is_head;
    bool is_connection_close;
    bool is_connection_keep_alive;

    // response
    char buffer[HTTP_BUFFER_SIZE];
    size_t buffer_skip;
    size_t chunk_left;

    int idx_response;
    int status_code;

    int status;         // 1 - empty line is found, 2 - request ready, 3 - release

    int idx_content;
    bool is_chunked;
    bool is_content_length;
    string_buffer_t *content;

    bool is_active;
    bool callback_failed;
    bool is_closing;

    // receiver
    struct
    {
        void *arg;
        union
        {
            void (*fn)(void *, void *, size_t);
            void *ptr;
        } callback;
    } receiver;

    // stream
    bool is_thread_started;
    asc_thread_t *thread;
    asc_thread_buffer_t *thread_output;

    struct
    {
        uint8_t *buffer;
        size_t buffer_size;
        size_t buffer_count;
        size_t buffer_read;
        size_t buffer_write;
        size_t buffer_fill;
    } sync;

    uint64_t pcr;
};

static const char __path[] = "path";
static const char __method[] = "method";
static const char __version[] = "version";
static const char __headers[] = "headers";
static const char __content[] = "content";
static const char __callback[] = "callback";
static const char __stream[] = "stream";
static const char __code[] = "code";
static const char __message[] = "message";

static const char __default_method[] = "GET";
static const char __default_path[] = "/";
static const char __default_version[] = "HTTP/1.1";

#define HTTP_REQUEST_MAX_CHUNK_SIZE (64U * 1024U * 1024U)

static const char __connection[] = "Connection: ";
static const char __close[] = "close";
static const char __keep_alive[] = "keep-alive";

static void on_close(void *);

static bool parse_match_valid(const parse_match_t *m, size_t limit)
{
    return (m->so <= m->eo && m->eo <= limit);
}

static bool parse_matches_valid(const parse_match_t *m, size_t count, size_t limit)
{
    for(size_t i = 0; i < count; ++i)
    {
        if(!parse_match_valid(&m[i], limit))
            return false;
    }
    return true;
}

static bool parse_status_code_safe(const char *src, parse_match_t match, int *code)
{
    const size_t len = match.eo - match.so;
    if(len == 0 || len >= 16)
        return false;

    char tmp[16];
    memcpy(tmp, &src[match.so], len);
    tmp[len] = '\0';

    for(size_t i = 0; i < len; ++i)
    {
        if(tmp[i] < '0' || tmp[i] > '9')
            return false;
    }

    *code = atoi(tmp);
    return (*code >= 100 && *code <= 999);
}

static void callback(module_data_t *mod)
{
    if(mod->callback_failed)
        return;
    const int response = lua_gettop(lua);
    lua_rawgeti(lua, LUA_REGISTRYINDEX, mod->idx_self);
    lua_getfield(lua, -1, "__options");
    lua_getfield(lua, -1, "callback");
    lua_pushvalue(lua, -3);
    lua_pushvalue(lua, response);
    if(lua_pcall(lua, 2, 0, 0) != 0)
    {
        const char *msg = lua_tostring(lua, -1);
        asc_log_error(MSG("callback error: %s"), msg ? msg : "unknown");
        lua_pop(lua, 1);
        mod->callback_failed = true;
    }
    lua_pop(lua, 3); // self + options + response
}

static void call_error(module_data_t *mod, const char *msg)
{
    lua_newtable(lua);
    lua_pushnumber(lua, 0);
    lua_setfield(lua, -2, __code);
    lua_pushstring(lua, msg);
    lua_setfield(lua, -2, __message);
    callback(mod);
}

static bool note_io(module_data_t *mod, size_t bytes)
{
    mod->last_io_ts = asc_utime();
    if(mod->low_speed_limit <= 0 || mod->low_speed_time_sec <= 0 || bytes == 0)
        return true;

    if(mod->low_speed_start_ts == 0)
        mod->low_speed_start_ts = mod->last_io_ts;

    mod->low_speed_bytes += bytes;
    const uint64_t elapsed_us = mod->last_io_ts - mod->low_speed_start_ts;
    if(elapsed_us < (uint64_t)mod->low_speed_time_sec * 1000000ULL)
        return true;

    const double elapsed_sec = (double)elapsed_us / 1000000.0;
    const double rate = (elapsed_sec > 0.0) ? ((double)mod->low_speed_bytes / elapsed_sec) : 0.0;
    if(rate < (double)mod->low_speed_limit)
    {
        asc_log_error(MSG("low speed %.0f B/s"), rate);
        call_error(mod, "low speed");
        on_close(mod);
        return false;
    }

    mod->low_speed_start_ts = mod->last_io_ts;
    mod->low_speed_bytes = 0;
    return true;
}

static void on_read(void *arg);
static void on_tls_handshake(void *arg);
static void on_tls_connected(void *arg);

#ifdef HAVE_OPENSSL
static void tls_log_error(module_data_t *mod, const char *msg)
{
    unsigned long err = ERR_get_error();
    if(err)
    {
        char buf[256];
        ERR_error_string_n(err, buf, sizeof(buf));
        asc_log_error(MSG("%s: %s"), msg, buf);
    }
    else
    {
        asc_log_error(MSG("%s"), msg);
    }
}

static bool tls_setup_ctx(module_data_t *mod)
{
    if(mod->tls_ctx)
        return true;

    SSL_library_init();
    SSL_load_error_strings();
    OpenSSL_add_all_algorithms();

    mod->tls_ctx = SSL_CTX_new(TLS_client_method());
    if(!mod->tls_ctx)
    {
        tls_log_error(mod, "ssl ctx init failed");
        return false;
    }

    if(mod->tls_verify)
    {
        SSL_CTX_set_verify(mod->tls_ctx, SSL_VERIFY_PEER, NULL);
        SSL_CTX_set_default_verify_paths(mod->tls_ctx);
    }
    else
    {
        SSL_CTX_set_verify(mod->tls_ctx, SSL_VERIFY_NONE, NULL);
    }

    return true;
}

static bool tls_setup(module_data_t *mod)
{
    if(!tls_setup_ctx(mod))
        return false;

    if(mod->tls)
    {
        SSL_shutdown(mod->tls);
        SSL_free(mod->tls);
        mod->tls = NULL;
    }

    mod->tls = SSL_new(mod->tls_ctx);
    if(!mod->tls)
    {
        tls_log_error(mod, "ssl init failed");
        return false;
    }

    SSL_set_fd(mod->tls, asc_socket_fd(mod->sock));
    SSL_set_connect_state(mod->tls);

    if(mod->config.host)
        SSL_set_tlsext_host_name(mod->tls, mod->config.host);

    if(mod->tls_verify && mod->config.host)
    {
        X509_VERIFY_PARAM *param = SSL_get0_param(mod->tls);
        X509_VERIFY_PARAM_set1_host(param, mod->config.host, 0);
    }

    return true;
}

static bool tls_handshake_step(module_data_t *mod)
{
    int ret = SSL_connect(mod->tls);
    if(ret == 1)
        return true;

    int err = SSL_get_error(mod->tls, ret);
    if(err == SSL_ERROR_WANT_READ)
    {
        asc_socket_set_on_read(mod->sock, on_tls_handshake);
        asc_socket_set_on_ready(mod->sock, NULL);
        return false;
    }
    if(err == SSL_ERROR_WANT_WRITE)
    {
        asc_socket_set_on_ready(mod->sock, on_tls_handshake);
        return false;
    }

    tls_log_error(mod, "ssl handshake failed");
    return false;
}
#endif

static ssize_t socket_send_data(module_data_t *mod, const void *buffer, size_t size, event_callback_t retry_cb)
{
#ifdef HAVE_OPENSSL
    if(mod->is_tls)
    {
        int ret = SSL_write(mod->tls, buffer, (int)size);
        if(ret > 0)
            return ret;

        int err = SSL_get_error(mod->tls, ret);
        if(err == SSL_ERROR_WANT_READ)
        {
            asc_socket_set_on_read(mod->sock, retry_cb);
            asc_socket_set_on_ready(mod->sock, NULL);
            return 0;
        }
        if(err == SSL_ERROR_WANT_WRITE)
        {
            asc_socket_set_on_ready(mod->sock, retry_cb);
            return 0;
        }

        tls_log_error(mod, "ssl write failed");
        return -1;
    }
#endif
    return asc_socket_send(mod->sock, buffer, size);
}

static ssize_t socket_recv_data(module_data_t *mod, void *buffer, size_t size)
{
#ifdef HAVE_OPENSSL
    if(mod->is_tls)
    {
        int ret = SSL_read(mod->tls, buffer, (int)size);
        if(ret > 0)
            return ret;

        int err = SSL_get_error(mod->tls, ret);
        if(err == SSL_ERROR_WANT_READ)
            return -2;
        if(err == SSL_ERROR_WANT_WRITE)
        {
            asc_socket_set_on_ready(mod->sock, on_read);
            return -2;
        }
        if(err == SSL_ERROR_ZERO_RETURN)
            return 0;

        tls_log_error(mod, "ssl read failed");
        return -1;
    }
#endif
    return asc_socket_recv(mod->sock, buffer, size);
}

void timeout_callback(void *arg)
{
    module_data_t *mod = (module_data_t *)arg;

    asc_timer_destroy(mod->timeout);
    mod->timeout = NULL;

    if(mod->request.status == 0)
    {
        mod->status = -1;
        mod->request.status = -1;
        call_error(mod, "connection timeout");
    }
    else
    {
        mod->status = -1;
        mod->request.status = -1;
        call_error(mod, "response timeout");
    }

    on_close(mod);
}

static void on_thread_close(void *arg);

static void on_close(void *arg)
{
    module_data_t *mod = (module_data_t *)arg;
    if(!mod)
        return;

    /* Защита от повторного on_close() из разных callback-путей. */
    if(mod->is_closing)
        return;
    mod->is_closing = true;

    if(mod->thread)
        on_thread_close(mod);

    if(!mod->sock)
        return;

    if(mod->receiver.callback.ptr)
    {
        mod->receiver.callback.fn(mod->receiver.arg, NULL, 0);

        mod->receiver.arg = NULL;
        mod->receiver.callback.ptr = NULL;
    }

#ifdef HAVE_OPENSSL
    if(mod->tls)
    {
        SSL_shutdown(mod->tls);
        SSL_free(mod->tls);
        mod->tls = NULL;
    }
#endif

    asc_socket_close(mod->sock);
    mod->sock = NULL;

    if(mod->timeout)
    {
        asc_timer_destroy(mod->timeout);
        mod->timeout = NULL;
    }

    if(mod->request.buffer)
    {
        if(mod->request.status == 1)
            free((void *)mod->request.buffer);
        mod->request.buffer = NULL;
    }

    if(mod->request.idx_body)
    {
        luaL_unref(lua, LUA_REGISTRYINDEX, mod->request.idx_body);
        mod->request.idx_body = 0;
    }

    if(mod->request.status == 0)
    {
        mod->request.status = -1;
        call_error(mod, "connection failed");
    }
    else if(mod->status == 0)
    {
        mod->request.status = -1;
        call_error(mod, "failed to parse response");
    }

    if(mod->status == 2)
    {
        mod->status = 3;

        lua_rawgeti(lua, LUA_REGISTRYINDEX, mod->idx_response);
        callback(mod);
    }

    if(mod->__stream.self)
    {
        module_stream_destroy(mod);

        if(mod->status == 3)
        {
            /* stream on_close */
            mod->status = -1;
            mod->request.status = -1;

            lua_pushnil(lua);
            callback(mod);
        }
    }

    if(mod->sync.buffer)
    {
        free(mod->sync.buffer);
        mod->sync.buffer = NULL;
    }

    if(mod->idx_response)
    {
        luaL_unref(lua, LUA_REGISTRYINDEX, mod->idx_response);
        mod->idx_response = 0;
    }

    if(mod->idx_content)
    {
        luaL_unref(lua, LUA_REGISTRYINDEX, mod->idx_content);
        mod->idx_content = 0;
    }

    if(mod->idx_self)
    {
        luaL_unref(lua, LUA_REGISTRYINDEX, mod->idx_self);
        mod->idx_self = 0;
    }

    if(mod->content)
    {
        string_buffer_free(mod->content);
        mod->content = NULL;
    }
}

/*
 *  oooooooo8 ooooooooooo oooooooooo  ooooooooooo      o      oooo     oooo
 * 888        88  888  88  888    888  888    88      888      8888o   888
 *  888oooooo     888      888oooo88   888ooo8       8  88     88 888o8 88
 *         888    888      888  88o    888    oo    8oooo88    88  888  88
 * o88oooo888    o888o    o888o  88o8 o888ooo8888 o88o  o888o o88o  8  o88o
 *
 */

static bool seek_pcr(  module_data_t *mod
                     , size_t *block_size, size_t *next_block
                     , uint64_t *pcr)
{
    size_t count;

    while(1)
    {
        if(mod->sync.buffer_count < 2 * TS_PACKET_SIZE)
            return false;

        count = mod->sync.buffer_read + TS_PACKET_SIZE;
        if(count >= mod->sync.buffer_size)
            count -= mod->sync.buffer_size;

        if(   mod->sync.buffer[mod->sync.buffer_read] == 0x47
           && mod->sync.buffer[count] == 0x47)
        {
            break;
        }

        ++mod->sync.buffer_read;
        if(mod->sync.buffer_read >= mod->sync.buffer_size)
            mod->sync.buffer_read = 0;

        --mod->sync.buffer_count;
    }

    uint8_t *ptr, ts[TS_PACKET_SIZE];

    size_t next_skip, skip = mod->sync.buffer_read + TS_PACKET_SIZE;
    if(skip >= mod->sync.buffer_size)
        skip -= mod->sync.buffer_size;

    for(  count = TS_PACKET_SIZE
        ; count < mod->sync.buffer_count
        ; count += TS_PACKET_SIZE)
    {
        ptr = &mod->sync.buffer[skip];

        next_skip = skip + TS_PACKET_SIZE;
        if(next_skip > mod->sync.buffer_size)
        {
            const size_t packet_head = mod->sync.buffer_size - skip;
            memcpy(ts, ptr, packet_head);
            next_skip -= mod->sync.buffer_size;
            memcpy(&ts[packet_head], mod->sync.buffer, next_skip);
            ptr = ts;
        }

        if(TS_IS_PCR(ptr))
        {
            *block_size = count;
            *next_block = skip;
            *pcr = TS_GET_PCR(ptr);

            return true;
        }

        skip = (next_skip == mod->sync.buffer_size) ? 0 : next_skip;
    }

    return false;
}

static void on_thread_close(void *arg)
{
    module_data_t *mod = (module_data_t *)arg;

    mod->is_thread_started = false;

    if(mod->thread)
    {
        asc_thread_destroy(mod->thread);
        mod->thread = NULL;
    }

    if(mod->thread_output)
    {
        asc_thread_buffer_destroy(mod->thread_output);
        mod->thread_output = NULL;
    }

    on_close(mod);
}

static void on_thread_read(void *arg)
{
    module_data_t *mod = (module_data_t *)arg;

    uint8_t ts[TS_PACKET_SIZE];
    const ssize_t r = asc_thread_buffer_read(mod->thread_output, ts, sizeof(ts));
    if(r == sizeof(ts))
        module_stream_send(mod, ts);
}

static void thread_loop(void *arg)
{
    module_data_t *mod = (module_data_t *)arg;

    uint8_t *ptr, ts[TS_PACKET_SIZE];

    mod->is_thread_started = true;

    while(mod->is_thread_started)
    {
        // block sync
        uint64_t   pcr
                 , system_time, system_time_check
                 , block_time, block_time_total = 0;
        size_t block_size = 0, next_block;

        bool reset = true;

        asc_log_info(MSG("buffering..."));

        // flush
        mod->sync.buffer_count = 0;
        mod->sync.buffer_write = 0;
        mod->sync.buffer_read = 0;

        // check timeout
        system_time_check = asc_utime();

        while(   mod->is_thread_started
              && mod->sync.buffer_write < mod->sync.buffer_size)
        {
            system_time = asc_utime();

            const ssize_t size = asc_socket_recv(  mod->sock
                                                 , &mod->sync.buffer[mod->sync.buffer_write]
                                                 , mod->sync.buffer_size - mod->sync.buffer_write);
            if(size > 0)
            {
                if(!note_io(mod, (size_t)size))
                    return;
                system_time_check = system_time;
                mod->sync.buffer_write += size;
            }
            else
            {
                if(system_time - system_time_check >= (uint32_t)mod->stall_timeout_ms * 1000)
                {
                    asc_log_error(MSG("receiving timeout"));
                    return;
                }
                asc_usleep(1000);
            }
        }
        mod->sync.buffer_count = mod->sync.buffer_write;
        if(mod->sync.buffer_write == mod->sync.buffer_size)
            mod->sync.buffer_write = 0;

        if(!seek_pcr(mod, &block_size, &next_block, &mod->pcr))
        {
            asc_log_error(MSG("first PCR is not found"));
            return;
        }

        mod->sync.buffer_count -= block_size;
        mod->sync.buffer_read = next_block;

        reset = true;

        while(mod->is_thread_started)
        {
            if(reset)
            {
                reset = false;
                block_time_total = asc_utime();
            }

            if(   mod->is_thread_started
               && mod->sync.buffer_count < mod->sync.buffer_size)
            {
                const size_t tail = (mod->sync.buffer_read > mod->sync.buffer_write)
                                  ? (mod->sync.buffer_read - mod->sync.buffer_write)
                                  : (mod->sync.buffer_size - mod->sync.buffer_write);

                const ssize_t l = asc_socket_recv(  mod->sock
                                                  , &mod->sync.buffer[mod->sync.buffer_write]
                                                  , tail);
                if(l > 0)
                {
                    mod->sync.buffer_write += l;
                    if(mod->sync.buffer_write >= mod->sync.buffer_size)
                        mod->sync.buffer_write = 0;
                    mod->sync.buffer_count += l;
                }
            }

            // get PCR
            if(!seek_pcr(mod, &block_size, &next_block, &pcr))
            {
                asc_log_error(MSG("next PCR is not found"));
                break;
            }
            block_time = mpegts_pcr_block_us(&mod->pcr, &pcr);
            mod->pcr = pcr;
            if(block_time == 0 || block_time > 500000)
            {
                asc_log_debug(  MSG("block time out of range: %"PRIu64"ms block_size:%lu")
                              , (uint64_t)(block_time / 1000), block_size);

                mod->sync.buffer_count -= block_size;
                mod->sync.buffer_read = next_block;

                reset = true;
                continue;
            }

            system_time = asc_utime();
            if(block_time_total > system_time + 100)
                asc_usleep(block_time_total - system_time);

            const uint32_t ts_count = block_size / TS_PACKET_SIZE;
            const uint32_t ts_sync = block_time / ts_count;
            const uint32_t block_time_tail = block_time % ts_count;

            system_time_check = asc_utime();

            while(mod->is_thread_started && mod->sync.buffer_read != next_block)
            {
                // sending
                ptr = &mod->sync.buffer[mod->sync.buffer_read];
                size_t next_packet = mod->sync.buffer_read + TS_PACKET_SIZE;
                if(next_packet < mod->sync.buffer_size)
                {
                    mod->sync.buffer_read = next_packet;
                }
                else if(next_packet > mod->sync.buffer_size)
                {
                    const size_t packet_head = mod->sync.buffer_size - mod->sync.buffer_read;
                    memcpy(ts, ptr, packet_head);
                    mod->sync.buffer_read = next_packet - mod->sync.buffer_size;
                    memcpy(&ts[packet_head], mod->sync.buffer, mod->sync.buffer_read);
                    ptr = ts;
                }
                else /* next_packet == mod->sync.buffer_size */
                {
                    mod->sync.buffer_read = 0;
                }

                const ssize_t write_size = asc_thread_buffer_write(  mod->thread_output
                                                                   , ptr
                                                                   , TS_PACKET_SIZE);
                if(write_size != TS_PACKET_SIZE)
                {
                    // overflow
                }

                system_time = asc_utime();
                block_time_total += ts_sync;

                if(  (system_time < system_time_check) /* <-0s */
                   ||(system_time > system_time_check + 1000000)) /* >+1s */
                {
                    asc_log_warning(MSG("system time changed"));

                    mod->sync.buffer_read = next_block;

                    reset = true;
                    break;
                }
                system_time_check = system_time;

                if(block_time_total > system_time + 100)
                    asc_usleep(block_time_total - system_time);
            }
            mod->sync.buffer_count -= block_size;

            if(reset)
                continue;

            system_time = asc_utime();
            if(system_time > block_time_total + 100000)
            {
                asc_log_warning(  MSG("wrong syncing time. -%"PRIu64"ms")
                                , (system_time - block_time_total) / 1000);
                reset = true;
            }

            block_time_total += block_time_tail;
        }
    }
}

static void check_is_active(void *arg)
{
    module_data_t *mod = (module_data_t *)arg;

    if(mod->is_active)
    {
        mod->is_active = false;
        return;
    }

    asc_log_error(MSG("receiving timeout"));
    on_close(mod);
}

static void on_ts_read(void *arg)
{
    module_data_t *mod = (module_data_t *)arg;

    ssize_t size = asc_socket_recv(  mod->sock
                                   , &mod->sync.buffer[mod->sync.buffer_write]
                                   , mod->sync.buffer_size - mod->sync.buffer_write);
    if(size <= 0)
    {
        on_close(mod);
        return;
    }

    if(!note_io(mod, (size_t)size))
        return;

    mod->is_active = true;
    mod->sync.buffer_write += size;
    mod->sync.buffer_read = 0;

    while(1)
    {
        while(mod->sync.buffer[mod->sync.buffer_read] != 0x47)
        {
            ++mod->sync.buffer_read;
            if(mod->sync.buffer_read >= mod->sync.buffer_write)
            {
                mod->sync.buffer_write = 0;
                return;
            }
        }

        const size_t next = mod->sync.buffer_read + TS_PACKET_SIZE;
        if(next > mod->sync.buffer_write)
        {
            const size_t tail = mod->sync.buffer_write - mod->sync.buffer_read;
            if(tail > 0)
                memmove(mod->sync.buffer, &mod->sync.buffer[mod->sync.buffer_read], tail);
            mod->sync.buffer_write = tail;
            return;
        }

        module_stream_send(mod, &mod->sync.buffer[mod->sync.buffer_read]);
        mod->sync.buffer_read += TS_PACKET_SIZE;
    }
}

/*
 * oooooooooo  ooooooooooo      o      ooooooooo
 *  888    888  888    88      888      888    88o
 *  888oooo88   888ooo8       8  88     888    888
 *  888  88o    888    oo    8oooo88    888    888
 * o888o  88o8 o888ooo8888 o88o  o888o o888ooo88
 *
 */

static void on_read(void *arg)
{
    module_data_t *mod = (module_data_t *)arg;

    ssize_t size = socket_recv_data(  mod
                                    , &mod->buffer[mod->buffer_skip]
                                    , HTTP_BUFFER_SIZE - mod->buffer_skip);
    if(size == -2)
        return;
    if(size <= 0)
    {
        on_close(mod);
        return;
    }
    if(!note_io(mod, (size_t)size))
        return;
    if(mod->timeout)
    {
        asc_timer_destroy(mod->timeout);
        mod->timeout = NULL;
    }

    if(mod->receiver.callback.ptr)
    {
        mod->receiver.callback.fn(mod->receiver.arg, &mod->buffer[mod->buffer_skip], size);
        return;
    }

    if(mod->status == 3)
    {
        asc_log_warning(MSG("received data after response"));
        return;
    }

    size_t eoh = 0; // end of headers
    size_t skip = 0;
    mod->buffer_skip += size;

    if(mod->status == 0)
    {
        // check empty line
        while(skip < mod->buffer_skip)
        {
            if(   skip + 1 < mod->buffer_skip
               && mod->buffer[skip + 0] == '\n' && mod->buffer[skip + 1] == '\n')
            {
                eoh = skip + 2;
                mod->status = 1;
                break;
            }
            else if(   skip + 3 < mod->buffer_skip
                    && mod->buffer[skip + 0] == '\r' && mod->buffer[skip + 1] == '\n'
                    && mod->buffer[skip + 2] == '\r' && mod->buffer[skip + 3] == '\n')
            {
                eoh = skip + 4;
                mod->status = 1;
                break;
            }
            ++skip;
        }

        if(mod->status != 1)
            return;
    }

    if(mod->status == 1)
    {
        parse_match_t m[4];

        skip = 0;

/*
 *     oooooooooo  ooooooooooo  oooooooo8 oooooooooo
 *      888    888  888    88  888         888    888
 *      888oooo88   888ooo8     888oooooo  888oooo88
 * ooo  888  88o    888    oo          888 888
 * 888 o888o  88o8 o888ooo8888 o88oooo888 o888o
 *
 */

        if(!http_parse_response(mod->buffer, eoh, m))
        {
            call_error(mod, "failed to parse response line");
            on_close(mod);
            return;
        }
        if(!parse_matches_valid(m, 4, eoh))
        {
            call_error(mod, "invalid response ranges");
            on_close(mod);
            return;
        }

        lua_newtable(lua);
        const int response = lua_gettop(lua);

        lua_pushvalue(lua, -1);
        if(mod->idx_response)
            luaL_unref(lua, LUA_REGISTRYINDEX, mod->idx_response);
        mod->idx_response = luaL_ref(lua, LUA_REGISTRYINDEX);

        lua_pushlstring(lua, &mod->buffer[m[1].so], m[1].eo - m[1].so);
        lua_setfield(lua, response, __version);

        if(!parse_status_code_safe(mod->buffer, m[2], &mod->status_code))
        {
            call_error(mod, "invalid response status code");
            on_close(mod);
            return;
        }
        lua_pushnumber(lua, mod->status_code);
        lua_setfield(lua, response, __code);

        lua_pushlstring(lua, &mod->buffer[m[3].so], m[3].eo - m[3].so);
        lua_setfield(lua, response, __message);

        skip += m[0].eo;

/*
 *     ooooo ooooo ooooooooooo      o      ooooooooo  ooooooooooo oooooooooo   oooooooo8
 *      888   888   888    88      888      888    88o 888    88   888    888 888
 *      888ooo888   888ooo8       8  88     888    888 888ooo8     888oooo88   888oooooo
 * ooo  888   888   888    oo    8oooo88    888    888 888    oo   888  88o           888
 * 888 o888o o888o o888ooo8888 o88o  o888o o888ooo88  o888ooo8888 o888o  88o8 o88oooo888
 *
 */

        lua_newtable(lua);
        lua_pushvalue(lua, -1);
        lua_setfield(lua, response, __headers);
        const int headers = lua_gettop(lua);

        while(skip < eoh)
        {
            if(!http_parse_header(&mod->buffer[skip], eoh - skip, m))
            {
                call_error(mod, "failed to parse response headers");
                on_close(mod);
                return;
            }

            if(m[1].eo == 0)
            { /* empty line */
                skip += m[0].eo;
                mod->status = 2;
                break;
            }
            if(!parse_matches_valid(m, 3, eoh - skip))
            {
                call_error(mod, "invalid response header ranges");
                on_close(mod);
                return;
            }

            lua_string_to_lower(&mod->buffer[skip], m[1].eo);
            lua_pushlstring(lua, &mod->buffer[skip + m[2].so], m[2].eo - m[2].so);
            lua_settable(lua, headers);

            skip += m[0].eo;
        }

        mod->chunk_left = 0;
        mod->is_content_length = false;

        if(mod->content)
        {
            string_buffer_free(mod->content);
            mod->content = NULL;
        }

        lua_getfield(lua, headers, "content-length");
        if(lua_isnumber(lua, -1))
        {
            mod->chunk_left = lua_tonumber(lua, -1);
            if(mod->chunk_left > 0)
            {
                mod->is_content_length = true;
            }
        }
        lua_pop(lua, 1); // content-length

        lua_getfield(lua, headers, "transfer-encoding");
        if(lua_isstring(lua, -1))
        {
            const char *encoding = lua_tostring(lua, -1);
            mod->is_chunked = (strcmp(encoding, "chunked") == 0);
        }
        lua_pop(lua, 1); // transfer-encoding

        if(mod->is_content_length || mod->is_chunked)
            mod->content = string_buffer_alloc();

        lua_pop(lua, 2); // headers + response

        if(   (mod->is_head)
           || (mod->status_code >= 100 && mod->status_code < 200)
           || (mod->status_code == 204)
           || (mod->status_code == 304))
        {
            mod->status = 3;

            lua_rawgeti(lua, LUA_REGISTRYINDEX, mod->idx_response);
            callback(mod);

            if(mod->is_connection_close)
                on_close(mod);

            mod->buffer_skip = 0;
            return;
        }

        if(mod->is_stream && mod->status_code == 200)
        {
            mod->status = 3;

            lua_rawgeti(lua, LUA_REGISTRYINDEX, mod->idx_response);
            lua_pushboolean(lua, mod->is_stream);
            lua_setfield(lua, -2, __stream);
            callback(mod);

            mod->sync.buffer = (uint8_t *)malloc(mod->sync.buffer_size);

            if(!mod->config.sync)
            {
                mod->timeout = asc_timer_init(mod->stall_timeout_ms, check_is_active, mod);

                asc_socket_set_on_read(mod->sock, on_ts_read);
                asc_socket_set_on_ready(mod->sock, NULL);
            }
            else
            {
                asc_socket_set_on_read(mod->sock, NULL);
                asc_socket_set_on_ready(mod->sock, NULL);
                asc_socket_set_on_close(mod->sock, NULL);

                mod->thread = asc_thread_init(mod);
                mod->thread_output = asc_thread_buffer_init(mod->sync.buffer_size);
                asc_thread_start(  mod->thread
                                 , thread_loop
                                 , on_thread_read, mod->thread_output
                                 , on_thread_close);
            }

            mod->buffer_skip = 0;
            return;
        }

        if(!mod->content)
        {
            mod->status = 3;

            lua_rawgeti(lua, LUA_REGISTRYINDEX, mod->idx_response);
            callback(mod);

            if(mod->is_connection_close)
                on_close(mod);

            mod->buffer_skip = 0;
            return;
        }
    }

/*
 *       oooooooo8   ooooooo  oooo   oooo ooooooooooo ooooooooooo oooo   oooo ooooooooooo
 *     o888     88 o888   888o 8888o  88  88  888  88  888    88   8888o  88  88  888  88
 *     888         888     888 88 888o88      888      888ooo8     88 888o88      888
 * ooo 888o     oo 888o   o888 88   8888      888      888    oo   88   8888      888
 * 888  888oooo88    88ooo88  o88o    88     o888o    o888ooo8888 o88o    88     o888o
 *
 */

    // Transfer-Encoding: chunked
    if(mod->is_chunked)
    {
        parse_match_t m[2] = { 0 };

        while(skip < mod->buffer_skip)
        {
            if(!mod->chunk_left)
            {
                if(!http_parse_chunk(&mod->buffer[skip], mod->buffer_skip - skip, m))
                {
                    call_error(mod, "invalid chunk");
                    on_close(mod);
                    return;
                }
                if(!parse_matches_valid(m, 2, mod->buffer_skip - skip))
                {
                    call_error(mod, "invalid chunk ranges");
                    on_close(mod);
                    return;
                }

                mod->chunk_left = 0;
                for(size_t i = m[1].so; i < m[1].eo; ++i)
                {
                    if(mod->chunk_left > (SIZE_MAX >> 4))
                    {
                        call_error(mod, "chunk too large");
                        on_close(mod);
                        return;
                    }
                    char c = mod->buffer[skip + i];
                    if(c >= '0' && c <= '9')
                        mod->chunk_left = (mod->chunk_left << 4) | (c - '0');
                    else if(c >= 'a' && c <= 'f')
                        mod->chunk_left = (mod->chunk_left << 4) | (c - 'a' + 0x0A);
                    else if(c >= 'A' && c <= 'F')
                        mod->chunk_left = (mod->chunk_left << 4) | (c - 'A' + 0x0A);
                }
                skip += m[0].eo;
                if(mod->chunk_left > HTTP_REQUEST_MAX_CHUNK_SIZE)
                {
                    call_error(mod, "chunk too large");
                    on_close(mod);
                    return;
                }

                if(!mod->chunk_left)
                {
                    lua_rawgeti(lua, LUA_REGISTRYINDEX, mod->idx_response);
                    string_buffer_push(lua, mod->content);
                    mod->content = NULL;
                    lua_setfield(lua, -2, __content);
                    mod->status = 3;
                    callback(mod);

                    if(mod->is_connection_close)
                    {
                        on_close(mod);
                        return;
                    }

                    break;
                }

                if(mod->chunk_left > SIZE_MAX - 2)
                {
                    call_error(mod, "chunk overflow");
                    on_close(mod);
                    return;
                }
                mod->chunk_left += 2;
            }

            const size_t tail = mod->buffer_skip - skip;
            if(mod->chunk_left <= tail)
            {
                string_buffer_addlstring(mod->content, &mod->buffer[skip], mod->chunk_left - 2);

                skip += mod->chunk_left;
                mod->chunk_left = 0;
            }
            else
            {
                string_buffer_addlstring(mod->content, &mod->buffer[skip], tail);
                mod->chunk_left -= tail;
                break;
            }
        }

        mod->buffer_skip = 0;
        return;
    }

    // Content-Length: *
    if(mod->is_content_length)
    {
        const size_t tail = mod->buffer_skip - skip;

        if(mod->chunk_left > tail)
        {
            string_buffer_addlstring(mod->content, &mod->buffer[skip], tail);
            mod->chunk_left -= tail;
        }
        else
        {
            string_buffer_addlstring(mod->content, &mod->buffer[skip], mod->chunk_left);
            mod->chunk_left = 0;

            lua_rawgeti(lua, LUA_REGISTRYINDEX, mod->idx_response);
            string_buffer_push(lua, mod->content);
            mod->content = NULL;
            lua_setfield(lua, -2, __content);
            mod->status = 3;
            callback(mod);

            if(mod->is_connection_close)
            {
                on_close(mod);
                return;
            }
        }

        mod->buffer_skip = 0;
        return;
    }
}

/*
 *  oooooooo8 ooooooooooo oooo   oooo ooooooooo
 * 888         888    88   8888o  88   888    88o
 *  888oooooo  888ooo8     88 888o88   888    888
 *         888 888    oo   88   8888   888    888
 * o88oooo888 o888ooo8888 o88o    88  o888ooo88
 *
 */

static void on_ready_send_content(void *arg)
{
    module_data_t *mod = (module_data_t *)arg;

    asc_assert(mod->request.size > 0, MSG("invalid content size"));

    const size_t rem = mod->request.size - mod->request.skip;
    const size_t cap = (rem > HTTP_BUFFER_SIZE) ? HTTP_BUFFER_SIZE : rem;

    const ssize_t send_size = socket_send_data(  mod
                                              , &mod->request.buffer[mod->request.skip]
                                              , cap
                                              , on_ready_send_content);
    if(send_size == 0)
        return;
    if(send_size == -1)
    {
        asc_log_error(MSG("failed to send content [%s]"), asc_socket_error());
        on_close(mod);
        return;
    }
    mod->request.skip += send_size;

    if(mod->request.skip >= mod->request.size)
    {
        mod->request.buffer = NULL;

        luaL_unref(lua, LUA_REGISTRYINDEX, mod->request.idx_body);
        mod->request.idx_body = 0;

        mod->request.status = 3;

        asc_socket_set_on_ready(mod->sock, NULL);
        asc_socket_set_on_read(mod->sock, on_read);
    }
}

static void on_ready_send_request(void *arg)
{
    module_data_t *mod = (module_data_t *)arg;

    asc_assert(mod->request.size > 0, MSG("invalid request size"));

    const size_t rem = mod->request.size - mod->request.skip;
    const size_t cap = (rem > HTTP_BUFFER_SIZE) ? HTTP_BUFFER_SIZE : rem;

    const ssize_t send_size = socket_send_data(  mod
                                              , &mod->request.buffer[mod->request.skip]
                                              , cap
                                              , on_ready_send_request);
    if(send_size == 0)
        return;
    if(send_size == -1)
    {
        asc_log_error(MSG("failed to send response [%s]"), asc_socket_error());
        on_close(mod);
        return;
    }
    mod->request.skip += send_size;

    if(mod->request.skip >= mod->request.size)
    {
        free((void *)mod->request.buffer);
        mod->request.buffer = NULL;

        if(mod->request.idx_body)
        {
            lua_rawgeti(lua, LUA_REGISTRYINDEX, mod->request.idx_body);
            mod->request.buffer = lua_tostring(lua, -1);
            mod->request.size = luaL_len(lua, -1);
            mod->request.skip = 0;
            lua_pop(lua, 1);

            mod->request.status = 2;

            asc_socket_set_on_ready(mod->sock, on_ready_send_content);
        }
        else
        {
            mod->request.status = 3;

            asc_socket_set_on_ready(mod->sock, NULL);
            asc_socket_set_on_read(mod->sock, on_read);
        }
    }
}

static void lua_make_request(module_data_t *mod)
{
    lua_getfield(lua, -1, __method);
    const char *method = lua_isstring(lua, -1) ? lua_tostring(lua, -1) : __default_method;
    lua_pop(lua, 1);

    mod->is_head = (strcmp(method, "HEAD") == 0);

    lua_getfield(lua, -1, __path);
    mod->config.path = lua_isstring(lua, -1) ? lua_tostring(lua, -1) : __default_path;
    lua_pop(lua, 1);

    lua_getfield(lua, -1, __version);
    const char *version = lua_isstring(lua, -1) ? lua_tostring(lua, -1) : __default_version;
    lua_pop(lua, 1);

    string_buffer_t *buffer = string_buffer_alloc();

    string_buffer_addfstring(buffer, "%s %s %s\r\n", method, mod->config.path, version);

    lua_getfield(lua, -1, __headers);
    if(lua_istable(lua, -1))
    {
        for(lua_pushnil(lua); lua_next(lua, -2); lua_pop(lua, 1))
        {
            const char *h = lua_tostring(lua, -1);
            if(!h)
            {
                asc_log_warning(MSG("skip non-string request header"));
                continue;
            }

            if(!strncasecmp(h, __connection, sizeof(__connection) - 1))
            {
                const char *hp = &h[sizeof(__connection) - 1];
                if(!strncasecmp(hp, __close, sizeof(__close) - 1))
                    mod->is_connection_close = true;
                else if(!strncasecmp(hp, __keep_alive, sizeof(__keep_alive) - 1))
                    mod->is_connection_keep_alive = true;
            }

            string_buffer_addfstring(buffer, "%s\r\n", h);
        }
    }
    lua_pop(lua, 1); // headers

    string_buffer_addlstring(buffer, "\r\n", 2);

    mod->request.buffer = string_buffer_release(buffer, &mod->request.size);
    mod->request.skip = 0;

    if(mod->request.idx_body)
    {
        luaL_unref(lua, LUA_REGISTRYINDEX, mod->request.idx_body);
        mod->request.idx_body = 0;
    }

    lua_getfield(lua, -1, __content);
    if(lua_isstring(lua, -1))
        mod->request.idx_body = luaL_ref(lua, LUA_REGISTRYINDEX);
    else
        lua_pop(lua, 1);
}

static void on_connected(module_data_t *mod)
{
    mod->request.status = 1;

    asc_timer_destroy(mod->timeout);
    mod->timeout = asc_timer_init(mod->response_timeout_ms, timeout_callback, mod);

    lua_rawgeti(lua, LUA_REGISTRYINDEX, mod->idx_self);
    lua_getfield(lua, -1, "__options");
    lua_make_request(mod);
    lua_pop(lua, 2); // self + __options

    asc_socket_set_on_read(mod->sock, on_read);
    asc_socket_set_on_ready(mod->sock, on_ready_send_request);
}

static void on_tls_connected(void *arg)
{
    module_data_t *mod = (module_data_t *)arg;
    on_connected(mod);
}

static void on_connect(void *arg)
{
    module_data_t *mod = (module_data_t *)arg;

    if(mod->is_tls)
    {
#ifdef HAVE_OPENSSL
        if(!tls_setup(mod))
        {
            on_close(mod);
            return;
        }
        if(tls_handshake_step(mod))
            on_tls_connected(mod);
#else
        asc_log_error(MSG("ssl is not supported (compiled without OpenSSL)"));
        on_close(mod);
#endif
        return;
    }

    on_connected(mod);
}

static void on_tls_handshake(void *arg)
{
#ifdef HAVE_OPENSSL
    module_data_t *mod = (module_data_t *)arg;
    if(tls_handshake_step(mod))
        on_tls_connected(mod);
#else
    __uarg(arg);
#endif
}

static void on_upstream_ready(void *arg)
{
    module_data_t *mod = (module_data_t *)arg;

    if(mod->sync.buffer_count > 0)
    {
        size_t block_size = (mod->sync.buffer_write > mod->sync.buffer_read)
                          ? (mod->sync.buffer_write - mod->sync.buffer_read)
                          : (mod->sync.buffer_size - mod->sync.buffer_read);

        if(block_size > mod->sync.buffer_count)
            block_size = mod->sync.buffer_count;

        const ssize_t send_size = socket_send_data(  mod
                                                  , &mod->sync.buffer[mod->sync.buffer_read]
                                                  , block_size
                                                  , on_upstream_ready);
        if(send_size == 0)
            return;

        if(send_size > 0)
        {
            mod->sync.buffer_count -= send_size;
            mod->sync.buffer_read += send_size;
            if(mod->sync.buffer_read >= mod->sync.buffer_size)
                mod->sync.buffer_read = 0;
        }
        else if(send_size == -1)
        {
            asc_log_error(  MSG("failed to send ts (%lu bytes) [%s]")
                          , block_size, asc_socket_error());
            on_close(mod);
            return;
        }
    }

    if(mod->sync.buffer_count == 0)
    {
        asc_socket_set_on_ready(mod->sock, NULL);
        mod->is_socket_busy = false;
    }
}

static void on_ts(module_data_t *mod, const uint8_t *ts)
{
    if(mod->status != 3 || mod->status_code != 200)
        return;

    if(mod->sync.buffer_count + TS_PACKET_SIZE >= mod->sync.buffer_size)
    {
        // overflow
        mod->sync.buffer_count = 0;
        mod->sync.buffer_read = 0;
        mod->sync.buffer_write = 0;
        if(mod->is_socket_busy)
        {
            asc_socket_set_on_ready(mod->sock, NULL);
            mod->is_socket_busy = false;
        }
        return;
    }

    const size_t buffer_write = mod->sync.buffer_write + TS_PACKET_SIZE;
    if(buffer_write < mod->sync.buffer_size)
    {
        memcpy(&mod->sync.buffer[mod->sync.buffer_write], ts, TS_PACKET_SIZE);
        mod->sync.buffer_write = buffer_write;
    }
    else if(buffer_write > mod->sync.buffer_size)
    {
        const size_t ts_head = mod->sync.buffer_size - mod->sync.buffer_write;
        memcpy(&mod->sync.buffer[mod->sync.buffer_write], ts, ts_head);
        mod->sync.buffer_write = TS_PACKET_SIZE - ts_head;
        memcpy(mod->sync.buffer, &ts[ts_head], mod->sync.buffer_write);
    }
    else
    {
        memcpy(&mod->sync.buffer[mod->sync.buffer_write], ts, TS_PACKET_SIZE);
        mod->sync.buffer_write = 0;
    }
    mod->sync.buffer_count += TS_PACKET_SIZE;

    if(   mod->is_socket_busy == false
       && mod->sync.buffer_count >= mod->sync.buffer_fill)
    {
        asc_socket_set_on_ready(mod->sock, on_upstream_ready);
        mod->is_socket_busy = true;
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

static int method_set_receiver(module_data_t *mod)
{
    if(lua_isnil(lua, -1))
    {
        mod->receiver.arg = NULL;
        mod->receiver.callback.ptr = NULL;
    }
    else
    {
        mod->receiver.arg = lua_touserdata(lua, -2);
        mod->receiver.callback.ptr = lua_touserdata(lua, -1);
    }
    return 0;
}

static int method_send(module_data_t *mod)
{
    mod->is_closing = false;
    mod->status = 0;

    if(mod->timeout)
        asc_timer_destroy(mod->timeout);
    mod->timeout = asc_timer_init(mod->response_timeout_ms, timeout_callback, mod);

    asc_assert(lua_istable(lua, 2), MSG(":send() table required"));
    lua_pushvalue(lua, 2);
    lua_make_request(mod);
    lua_pop(lua, 2); // :send() options

    asc_socket_set_on_read(mod->sock, on_read);
    asc_socket_set_on_ready(mod->sock, on_ready_send_request);

    return 0;
}

static int method_close(module_data_t *mod)
{
    mod->status = -1;
    mod->request.status = -1;
    on_close(mod);

    return 0;
}

static void module_init(module_data_t *mod)
{
    mod->is_closing = false;

    module_option_string("host", &mod->config.host, NULL);
    asc_assert(mod->config.host != NULL, MSG("option 'host' is required"));

    mod->config.port = 80;
    module_option_number("port", &mod->config.port);

    mod->config.path = __default_path;
    module_option_string(__path, &mod->config.path, NULL);

    lua_getfield(lua, 2, __callback);
    asc_assert(lua_isfunction(lua, -1), MSG("option 'callback' is required"));
    lua_pop(lua, 1); // callback

    // store self in registry
    lua_pushvalue(lua, 3);
    mod->idx_self = luaL_ref(lua, LUA_REGISTRYINDEX);

    module_option_boolean(__stream, &mod->is_stream);
    if(mod->is_stream)
    {
        module_stream_init(mod, NULL);

        int value = 0;
        module_option_number("sync", &value);
        if(value > 0)
            mod->config.sync = true;
        else
            value = 1;

        mod->sync.buffer_size = value * 1024 * 1024;

        int buffer_kb = 0;
        if(module_option_number("buffer_size", &buffer_kb) && buffer_kb > 0)
            mod->sync.buffer_size = buffer_kb * 1024;
    }

    lua_getfield(lua, MODULE_OPTIONS_IDX, "upstream");
    if(lua_type(lua, -1) == LUA_TLIGHTUSERDATA)
    {
        asc_assert(mod->is_stream != true, MSG("option 'upstream' is not allowed in stream mode"));

        module_stream_init(mod, on_ts);

        int value = 1024;
        module_option_number("buffer_size", &value);
        mod->sync.buffer_size = value * 1024;
        mod->sync.buffer = (uint8_t *)malloc(mod->sync.buffer_size);

        value = 128;
        module_option_number("buffer_fill", &value);
        mod->sync.buffer_fill = value * 1024;
    }
    lua_pop(lua, 1);

    mod->is_tls = false;
    mod->tls_verify = true;
    module_option_boolean("ssl", &mod->is_tls);
    module_option_boolean("https", &mod->is_tls);
    module_option_boolean("tls", &mod->is_tls);
    module_option_boolean("tls_verify", &mod->tls_verify);
    module_option_boolean("ssl_verify", &mod->tls_verify);
#ifndef HAVE_OPENSSL
    if(mod->is_tls)
    {
        asc_log_error(MSG("ssl is not supported (compiled without OpenSSL)"));
        mod->is_tls = false;
    }
#endif

    int timeout_sec = 10;
    module_option_number("timeout", &timeout_sec);
    if(timeout_sec <= 0)
        timeout_sec = 10;

    mod->connect_timeout_ms = timeout_sec * 1000;
    mod->response_timeout_ms = timeout_sec * 1000;
    mod->stall_timeout_ms = timeout_sec * 1000;

    int value_ms = 0;
    if(module_option_number("connect_timeout_ms", &value_ms) && value_ms > 0)
        mod->connect_timeout_ms = value_ms;
    if(module_option_number("read_timeout_ms", &value_ms) && value_ms > 0)
        mod->response_timeout_ms = value_ms;
    if(module_option_number("response_timeout_ms", &value_ms) && value_ms > 0)
        mod->response_timeout_ms = value_ms;
    if(module_option_number("stall_timeout_ms", &value_ms) && value_ms > 0)
        mod->stall_timeout_ms = value_ms;

    mod->timeout_ms = mod->response_timeout_ms;
    mod->timeout = asc_timer_init(mod->connect_timeout_ms, timeout_callback, mod);

    mod->low_speed_limit = 0;
    mod->low_speed_time_sec = 0;
    module_option_number("low_speed_limit_bytes_sec", &mod->low_speed_limit);
    module_option_number("low_speed_time_sec", &mod->low_speed_time_sec);

    bool sctp = false;
    module_option_boolean("sctp", &sctp);
    if(sctp == true)
        mod->sock = asc_socket_open_sctp4(mod);
    else
        mod->sock = asc_socket_open_tcp4(mod);

    asc_socket_connect(mod->sock, mod->config.host, mod->config.port, on_connect, on_close);
}

static void module_destroy(module_data_t *mod)
{
    mod->status = -1;
    mod->request.status = -1;

    on_close(mod);

#ifdef HAVE_OPENSSL
    if(mod->tls_ctx)
    {
        SSL_CTX_free(mod->tls_ctx);
        mod->tls_ctx = NULL;
    }
#endif
}

MODULE_STREAM_METHODS()
MODULE_LUA_METHODS()
{
    MODULE_STREAM_METHODS_REF(),
    { "send", method_send },
    { "close", method_close },
    { "set_receiver", method_set_receiver },
};

MODULE_LUA_REGISTER(http_request)
