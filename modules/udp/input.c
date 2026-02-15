/*
 * Astra Module: UDP Input
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
 *      udp_input
 *
 * Module Options:
 *      addr        - string, source IP address
 *      port        - number, source UDP port
 *      localaddr   - string, IP address of the local interface
 *      socket_size - number, socket buffer size
 *      renew       - number, renewing multicast subscription interval in seconds
 *      rtp         - boolean, use RTP instead RAW UDP
 *      read_burst  - number, how many datagrams to drain per on_read callback (default: 1)
 *      use_recvmmsg- boolean, use recvmmsg() for batched receive (Linux only, default: off)
 *      rx_batch    - number, max datagrams per recvmmsg() call (default: 32, range: 1..64)
 *
 * Module Methods:
 *      port()      - return number, random port number
 */

#include <astra.h>
#ifdef __linux__
#include <sys/socket.h>
#endif

#define UDP_BUFFER_SIZE 1460
#define RTP_HEADER_SIZE 12

#define RTP_IS_EXT(_data) ((_data[0] & 0x10))
#define RTP_EXT_SIZE(_data) \
    (((_data[RTP_HEADER_SIZE + 2] << 8) | _data[RTP_HEADER_SIZE + 3]) * 4 + 4)

#define MSG(_msg) "[udp_input %s:%d] " _msg, mod->config.addr, mod->config.port

struct module_data_t
{
    MODULE_STREAM_DATA();

    struct
    {
        const char *addr;
        int port;
        const char *localaddr;
        bool rtp;
        int read_burst;
        bool use_recvmmsg;
        int rx_batch;
    } config;

    bool is_error_message;

    asc_socket_t *sock;
    asc_timer_t *timer_renew;

    uint8_t buffer[UDP_BUFFER_SIZE];

#ifdef __linux__
    struct
    {
        struct mmsghdr *msgs;
        struct iovec *iov;
        uint8_t *buffers;
        int capacity;
    } rxmmsg;
#endif
};

static void on_close(void *arg)
{
    module_data_t *mod = (module_data_t *)arg;

    if(mod->sock)
    {
        asc_socket_multicast_leave(mod->sock);
        asc_socket_close(mod->sock);
        mod->sock = NULL;
    }

    if(mod->timer_renew)
    {
        asc_timer_destroy(mod->timer_renew);
        mod->timer_renew = NULL;
    }

#ifdef __linux__
    if(mod->rxmmsg.buffers)
    {
        free(mod->rxmmsg.buffers);
        mod->rxmmsg.buffers = NULL;
    }
    if(mod->rxmmsg.iov)
    {
        free(mod->rxmmsg.iov);
        mod->rxmmsg.iov = NULL;
    }
    if(mod->rxmmsg.msgs)
    {
        free(mod->rxmmsg.msgs);
        mod->rxmmsg.msgs = NULL;
    }
    mod->rxmmsg.capacity = 0;
#endif
}

static void on_read(void *arg)
{
    module_data_t *mod = (module_data_t *)arg;

    int burst = mod->config.read_burst;
    if(burst <= 0)
        burst = 1;

#ifdef __linux__
    if(mod->config.use_recvmmsg && mod->rxmmsg.msgs && mod->rxmmsg.iov && mod->rxmmsg.buffers)
    {
        int processed = 0;
        const int fd = asc_socket_fd(mod->sock);

        while(processed < burst)
        {
            int want = burst - processed;
            if(want > mod->config.rx_batch)
                want = mod->config.rx_batch;
            if(want <= 0)
                break;

            errno = 0;
            const int r = recvmmsg(fd, mod->rxmmsg.msgs, want, MSG_DONTWAIT, NULL);
            if(r <= 0)
            {
                if(r == 0 || errno == EAGAIN || errno == EWOULDBLOCK)
                    return;
                on_close(mod);
                return;
            }

            processed += r;

            for(int n = 0; n < r; ++n)
            {
                const int len = mod->rxmmsg.msgs[n].msg_len;
                const uint8_t *buffer = (const uint8_t *)mod->rxmmsg.iov[n].iov_base;
                if(len <= 0)
                    continue;

                int i = 0;
                if(mod->config.rtp)
                {
                    i = RTP_HEADER_SIZE;
                    if(RTP_IS_EXT(buffer))
                    {
                        if(len < RTP_HEADER_SIZE + 4)
                            continue;
                        i += RTP_EXT_SIZE(buffer);
                    }
                }

                for(; i <= len - TS_PACKET_SIZE; i += TS_PACKET_SIZE)
                    module_stream_send(mod, &buffer[i]);

                if(i != len && !mod->is_error_message)
                {
                    asc_log_error(MSG("wrong stream format. drop %d bytes"), len - i);
                    mod->is_error_message = true;
                }
            }

            if(r < want)
                break;
        }
        return;
    }
#endif

    for(int n = 0; n < burst; ++n)
    {
        int len = asc_socket_recv(mod->sock, mod->buffer, UDP_BUFFER_SIZE);
        if(len <= 0)
        {
            if(len == 0 || errno == EAGAIN || errno == EWOULDBLOCK)
                return;
            on_close(mod);
            return;
        }

        int i = 0;
        if(mod->config.rtp)
        {
            i = RTP_HEADER_SIZE;
            if(RTP_IS_EXT(mod->buffer))
            {
                if(len < RTP_HEADER_SIZE + 4)
                    continue;
                i += RTP_EXT_SIZE(mod->buffer);
            }
        }

        for(; i <= len - TS_PACKET_SIZE; i += TS_PACKET_SIZE)
            module_stream_send(mod, &mod->buffer[i]);

        if(i != len && !mod->is_error_message)
        {
            asc_log_error(MSG("wrong stream format. drop %d bytes"), len - i);
            mod->is_error_message = true;
        }
    }
}

static void timer_renew_callback(void *arg)
{
    module_data_t *mod = (module_data_t *)arg;
    asc_socket_multicast_renew(mod->sock);
}

static int method_port(module_data_t *mod)
{
    const int port = asc_socket_port(mod->sock);
    lua_pushnumber(lua, port);
    return 1;
}

static void module_init(module_data_t *mod)
{
    module_stream_init(mod, NULL);

    module_option_string("addr", &mod->config.addr, NULL);
    asc_assert(mod->config.addr != NULL, "[udp_input] option 'addr' is required");

    module_option_number("port", &mod->config.port);

    mod->sock = asc_socket_open_udp4(mod);
    asc_socket_set_reuseaddr(mod->sock, 1);
#ifdef _WIN32
    if(!asc_socket_bind(mod->sock, NULL, mod->config.port))
#else
    if(!asc_socket_bind(mod->sock, mod->config.addr, mod->config.port))
#endif
        return;

    int value;
    if(module_option_number("socket_size", &value))
        asc_socket_set_buffer(mod->sock, value, 0);

    module_option_boolean("rtp", &mod->config.rtp);
    mod->config.read_burst = 1;
    module_option_number("read_burst", &mod->config.read_burst);

    mod->config.use_recvmmsg = false;
    module_option_boolean("use_recvmmsg", &mod->config.use_recvmmsg);

    mod->config.rx_batch = 32;
    module_option_number("rx_batch", &mod->config.rx_batch);
    if(mod->config.rx_batch < 1)
        mod->config.rx_batch = 1;
    if(mod->config.rx_batch > 64)
        mod->config.rx_batch = 64;

#ifdef __linux__
    if(mod->config.use_recvmmsg)
    {
        // Важно: если включили recvmmsg, но не задали read_burst, поднимем его до rx_batch,
        // иначе профита по syscall не будет.
        if(mod->config.read_burst <= 1)
            mod->config.read_burst = mod->config.rx_batch;

        mod->rxmmsg.capacity = mod->config.rx_batch;
        mod->rxmmsg.msgs = (struct mmsghdr *)calloc(mod->rxmmsg.capacity, sizeof(struct mmsghdr));
        mod->rxmmsg.iov = (struct iovec *)calloc(mod->rxmmsg.capacity, sizeof(struct iovec));
        mod->rxmmsg.buffers = (uint8_t *)malloc((size_t)mod->rxmmsg.capacity * UDP_BUFFER_SIZE);

        if(!mod->rxmmsg.msgs || !mod->rxmmsg.iov || !mod->rxmmsg.buffers)
        {
            asc_log_error(MSG("failed to allocate recvmmsg buffers"));
            on_close(mod);
            return;
        }

        for(int i = 0; i < mod->rxmmsg.capacity; ++i)
        {
            mod->rxmmsg.iov[i].iov_base = mod->rxmmsg.buffers + ((size_t)i * UDP_BUFFER_SIZE);
            mod->rxmmsg.iov[i].iov_len = UDP_BUFFER_SIZE;
            mod->rxmmsg.msgs[i].msg_hdr.msg_iov = &mod->rxmmsg.iov[i];
            mod->rxmmsg.msgs[i].msg_hdr.msg_iovlen = 1;
        }
    }
#else
    if(mod->config.use_recvmmsg)
        asc_log_warning(MSG("use_recvmmsg is not supported on this platform; ignored"));
#endif

    asc_socket_set_on_read(mod->sock, on_read);
    asc_socket_set_on_close(mod->sock, on_close);

    module_option_string("localaddr", &mod->config.localaddr, NULL);
    asc_socket_multicast_join(mod->sock, mod->config.addr, mod->config.localaddr);

    if(module_option_number("renew", &value))
        mod->timer_renew = asc_timer_init(value * 1000, timer_renew_callback, mod);
}

static void module_destroy(module_data_t *mod)
{
    module_stream_destroy(mod);

    on_close(mod);
}

MODULE_STREAM_METHODS()

MODULE_LUA_METHODS()
{
    MODULE_STREAM_METHODS_REF(),
    { "port", method_port },
};
MODULE_LUA_REGISTER(udp_input)
