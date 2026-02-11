/*
 * Astra Module: HLS Memfd HTTP handler
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
#include "../http/http.h"
#include "hls_memfd.h"

#include <errno.h>
#include <string.h>
#include <stdlib.h>

#if defined(__linux) || defined(__APPLE__) || defined(__FreeBSD__)
#   define ASC_SENDFILE (128 * 1024)
#endif

#ifdef ASC_SENDFILE
#   include <sys/socket.h>
#   ifdef __linux
#       include <sys/sendfile.h>
#   endif
#endif

#define MSG(_msg) "[hls_memfd] " _msg

struct module_data_t
{
    int path_skip;
    size_t block_size;
    const char *ts_mime;

    int idx_m3u_headers;
    int idx_ts_headers;
};

struct http_response_t
{
    module_data_t *mod;

    int file_fd;
    int sock_fd;
    off_t file_skip;
    off_t file_size;

    hls_memfd_segment_t *segment;
    const uint8_t *segment_data;
    size_t segment_size;

    char *payload;
    size_t payload_len;
    size_t payload_skip;
};

static const char __path[] = "path";

static void apply_header_list(http_client_t *client, int idx_ref)
{
    if(idx_ref == LUA_NOREF)
        return;

    lua_rawgeti(lua, LUA_REGISTRYINDEX, idx_ref);
    if(!lua_istable(lua, -1))
    {
        lua_pop(lua, 1);
        return;
    }

    const int n = luaL_len(lua, -1);
    for(int i = 1; i <= n; ++i)
    {
        lua_rawgeti(lua, -1, i);
        if(lua_isstring(lua, -1))
            http_response_header(client, "%s", lua_tostring(lua, -1));
        lua_pop(lua, 1);
    }

    lua_pop(lua, 1);
}

static bool ends_with(const char *str, const char *suffix)
{
    if(!str || !suffix)
        return false;
    const size_t str_len = strlen(str);
    const size_t suf_len = strlen(suffix);
    if(suf_len == 0 || str_len < suf_len)
        return false;
    return strcmp(str + str_len - suf_len, suffix) == 0;
}

static void on_ready_send_buffer(void *arg)
{
    http_client_t *client = (http_client_t *)arg;
    http_response_t *response = client->response;

    const uint8_t *data = NULL;
    size_t total = 0;
    if(response->payload)
    {
        data = (const uint8_t *)response->payload;
        total = response->payload_len;
    }
    else
    {
        data = response->segment_data;
        total = response->segment_size;
    }

    if(!data || total == 0)
    {
        http_client_close(client);
        return;
    }

    const size_t remaining = total - response->payload_skip;
    const size_t send_len = (remaining > HTTP_BUFFER_SIZE) ? HTTP_BUFFER_SIZE : remaining;

    const ssize_t send_size = asc_socket_send(client->sock,
                                              (void *)&data[response->payload_skip],
                                              send_len);
    if(send_size == -1)
    {
        http_client_error(client, "failed to send content [%s]", asc_socket_error());
        http_client_close(client);
        return;
    }

    response->payload_skip += (size_t)send_size;
    if(response->payload_skip >= total)
        http_client_close(client);
}

static void on_ready_send_file(void *arg)
{
    http_client_t *client = (http_client_t *)arg;
    http_response_t *response = client->response;

    ssize_t send_size;
    bool offset_updated = false;

    if(!response->mod->block_size)
    {
        const ssize_t len = pread(response->file_fd,
                                  client->buffer,
                                  HTTP_BUFFER_SIZE,
                                  response->file_skip);
        if(len <= 0)
            send_size = -1;
        else
            send_size = asc_socket_send(client->sock, client->buffer, len);
    }
    else
    {
#if defined(__linux)
        off_t offset = response->file_skip;
        send_size = sendfile(response->sock_fd,
                             response->file_fd,
                             &offset,
                             response->mod->block_size);
        if(send_size > 0)
        {
            response->file_skip = offset;
            offset_updated = true;
        }
#elif defined(__APPLE__)
        off_t block_size = response->mod->block_size;
        const int r = sendfile(response->file_fd,
                               response->sock_fd,
                               response->file_skip,
                               &block_size, NULL, 0);
        if(r == 0 || (r == -1 && errno == EAGAIN && block_size > 0))
            send_size = block_size;
        else
            send_size = -1;
#elif defined(__FreeBSD__)
        off_t block_size = 0;
        const int r = sendfile(response->file_fd,
                               response->sock_fd,
                               response->file_skip,
                               response->mod->block_size, NULL,
                               &block_size, 0);
        if(r == 0 || (r == -1 && errno == EAGAIN && block_size > 0))
            send_size = block_size;
        else
            send_size = -1;
#else
        send_size = -1;
#endif
    }

    if(send_size == -1)
    {
        http_client_error(client, "failed to send file [%s]", asc_socket_error());
        http_client_close(client);
        return;
    }

    if(!offset_updated)
        response->file_skip += send_size;
    if(response->file_skip >= response->file_size)
        http_client_close(client);
}

/* Stack: 1 - instance, 2 - server, 3 - client, 4 - request */
static int module_call(module_data_t *mod)
{
    http_client_t *client = (http_client_t *)lua_touserdata(lua, 3);

    if(lua_isnil(lua, 4))
    {
        if(client->response)
        {
            http_response_t *response = client->response;
            if(response->segment)
                hls_memfd_segment_release(response->segment);
            if(response->payload)
                free(response->payload);
            free(response);
            client->response = NULL;
        }
        return 0;
    }

    lua_rawgeti(lua, LUA_REGISTRYINDEX, client->idx_request);
    lua_getfield(lua, -1, __path);
    const char *path = lua_tostring(lua, -1);
    lua_pop(lua, 2); // request + path

    if(!path)
    {
        http_client_abort(client, 404, NULL);
        lua_pushboolean(lua, true);
        return 1;
    }

    if(!lua_safe_path(path, strlen(path)))
    {
        http_client_abort(client, 404, NULL);
        lua_pushboolean(lua, true);
        return 1;
    }

    const size_t path_len = strlen(path);
    if((size_t)mod->path_skip > path_len)
    {
        lua_pushboolean(lua, false);
        return 1;
    }

    const char *rel = path + mod->path_skip;
    if(rel[0] == '/')
        ++rel;
    if(rel[0] == '\0')
    {
        lua_pushboolean(lua, false);
        return 1;
    }

    const char *slash = strchr(rel, '/');
    if(!slash)
    {
        lua_pushboolean(lua, false);
        return 1;
    }

    const size_t stream_len = (size_t)(slash - rel);
    if(stream_len == 0)
    {
        lua_pushboolean(lua, false);
        return 1;
    }

    char *stream_id = strndup(rel, stream_len);
    if(!stream_id)
    {
        http_client_abort(client, 500, NULL);
        lua_pushboolean(lua, true);
        return 1;
    }

    const char *file = slash + 1;
    if(!file || file[0] == '\0')
    {
        free(stream_id);
        lua_pushboolean(lua, false);
        return 1;
    }

    if(!hls_memfd_touch(stream_id))
    {
        free(stream_id);
        lua_pushboolean(lua, false);
        return 1;
    }

    const bool is_playlist = ends_with(file, ".m3u8") || ends_with(file, ".m3u");

    http_response_t *response = (http_response_t *)calloc(1, sizeof(http_response_t));
    if(!response)
    {
        free(stream_id);
        http_client_abort(client, 500, NULL);
        lua_pushboolean(lua, true);
        return 1;
    }
    response->mod = mod;
    response->sock_fd = asc_socket_fd(client->sock);

    if(is_playlist)
    {
        size_t payload_len = 0;
        char *payload = hls_memfd_copy_playlist(stream_id, &payload_len);
        if(!payload || payload_len == 0)
        {
            free(payload);
            free(stream_id);
            free(response);
            http_response_code(client, 503, NULL);
            http_response_header(client, "Retry-After: 1");
            http_response_header(client, "Content-Type: application/vnd.apple.mpegurl");
            apply_header_list(client, mod->idx_m3u_headers);
            http_response_header(client, "Content-Length: 0");
            http_response_send(client);
            lua_pushboolean(lua, true);
            return 1;
        }

        response->payload = payload;
        response->payload_len = payload_len;
        response->payload_skip = 0;

        client->response = response;
        client->on_send = NULL;
        client->on_read = NULL;
        client->on_ready = on_ready_send_buffer;

        http_response_code(client, 200, NULL);
        http_response_header(client, "Content-Length: %lu", (unsigned long)payload_len);
        http_response_header(client, "Content-Type: application/vnd.apple.mpegurl");
        http_response_header(client, "Connection: close");
        apply_header_list(client, mod->idx_m3u_headers);
        http_response_send(client);

        free(stream_id);
        lua_pushboolean(lua, true);
        return 1;
    }

    hls_memfd_segment_t *segment = hls_memfd_segment_acquire(stream_id, file);
    if(!segment)
    {
        free(stream_id);
        free(response);
        http_client_abort(client, 404, NULL);
        lua_pushboolean(lua, true);
        return 1;
    }

    response->segment = segment;
    response->file_fd = hls_memfd_segment_fd(segment);
    response->file_size = (off_t)hls_memfd_segment_size(segment);
    response->file_skip = 0;

    if(hls_memfd_segment_is_memfd(segment))
    {
        client->response = response;
        client->on_send = NULL;
        client->on_read = NULL;
        client->on_ready = on_ready_send_file;
    }
    else
    {
        response->segment_data = hls_memfd_segment_data(segment);
        response->segment_size = hls_memfd_segment_size(segment);
        client->response = response;
        client->on_send = NULL;
        client->on_read = NULL;
        client->on_ready = on_ready_send_buffer;
    }

    http_response_code(client, 200, NULL);
    http_response_header(client, "Content-Length: %lu", (unsigned long)response->file_size);
    http_response_header(client, "Content-Type: %s", mod->ts_mime);
    apply_header_list(client, mod->idx_ts_headers);
    http_response_send(client);

    free(stream_id);
    lua_pushboolean(lua, true);
    return 1;
}

static int __module_call(lua_State *L)
{
    module_data_t *mod = (module_data_t *)lua_touserdata(L, lua_upvalueindex(1));
    return module_call(mod);
}

static int method_get_playlist(module_data_t *mod)
{
    __uarg(mod);
    const char *stream_id = luaL_checkstring(lua, 2);
    if(!hls_memfd_touch(stream_id))
        return 0;
    size_t payload_len = 0;
    char *payload = hls_memfd_copy_playlist(stream_id, &payload_len);
    if(!payload || payload_len == 0)
    {
        free(payload);
        return 0;
    }

    lua_pushlstring(lua, payload, payload_len);
    free(payload);
    return 1;
}

static int method_sweep(module_data_t *mod)
{
    __uarg(mod);
    int idle_timeout_sec = (int)luaL_optnumber(lua, 2, 0);
    hls_memfd_sweep(asc_utime(), idle_timeout_sec);
    return 0;
}

static void module_init(module_data_t *mod)
{
    lua_getfield(lua, MODULE_OPTIONS_IDX, "skip");
    if(lua_isstring(lua, -1))
        mod->path_skip = luaL_len(lua, -1);
    lua_pop(lua, 1);

#ifndef ASC_SENDFILE
    mod->block_size = 0;
#endif
#ifdef ASC_SENDFILE
    int block_size = 0;
    module_option_number("block_size", &block_size);
    mod->block_size = (block_size > 0) ? (block_size * 1024) : ASC_SENDFILE;
#endif

    mod->ts_mime = "video/MP2T";
    module_option_string("ts_mime", &mod->ts_mime, NULL);

    mod->idx_m3u_headers = LUA_NOREF;
    mod->idx_ts_headers = LUA_NOREF;

    lua_getfield(lua, MODULE_OPTIONS_IDX, "m3u_headers");
    if(lua_istable(lua, -1))
        mod->idx_m3u_headers = luaL_ref(lua, LUA_REGISTRYINDEX);
    else
        lua_pop(lua, 1);

    lua_getfield(lua, MODULE_OPTIONS_IDX, "ts_headers");
    if(lua_istable(lua, -1))
        mod->idx_ts_headers = luaL_ref(lua, LUA_REGISTRYINDEX);
    else
        lua_pop(lua, 1);

    // Set callback for http route
    lua_getmetatable(lua, 3);
    lua_pushlightuserdata(lua, (void *)mod);
    lua_pushcclosure(lua, __module_call, 1);
    lua_setfield(lua, -2, "__call");
    lua_pop(lua, 1);
}

static void module_destroy(module_data_t *mod)
{
    if(mod->idx_m3u_headers != LUA_NOREF)
        luaL_unref(lua, LUA_REGISTRYINDEX, mod->idx_m3u_headers);
    if(mod->idx_ts_headers != LUA_NOREF)
        luaL_unref(lua, LUA_REGISTRYINDEX, mod->idx_ts_headers);
}

MODULE_LUA_METHODS()
{
    { "get_playlist", method_get_playlist },
    { "sweep", method_sweep },
    { NULL, NULL }
};

MODULE_LUA_REGISTER(hls_memfd)
