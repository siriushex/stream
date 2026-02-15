/*
 * Stream Hub: UDP Relay (Passthrough Data Plane)
 *
 * Цель:
 * - много UDP passthrough стримов в одном процессе
 * - распределение нагрузки по ядрам (worker threads + epoll)
 * - без Lua в горячем пути (только C)
 *
 * Важно:
 * - по умолчанию не используется (включается настройкой в Lua/runtime)
 * - поддерживает только "простые" конфиги (UDP input -> UDP outputs)
 */

#include <astra.h>

#ifdef __linux__

#include <errno.h>
#include <pthread.h>
#include <sched.h>
#include <string.h>
#include <arpa/inet.h>
#include <netinet/in.h>
#include <sys/epoll.h>
#include <sys/socket.h>
#include <unistd.h>

#define RELAY_MAX_EVENTS 64
#define RELAY_UDP_BUFFER_SIZE 1460
#define RELAY_RX_BATCH_DEFAULT 32
#define RELAY_RX_BATCH_MAX 64

#define RELAY_MSG_PREFIX "[udp_relay]"

typedef struct relay_output_t
{
    asc_socket_t *sock;
    const char *dst_addr;
    int dst_port;
    struct sockaddr_in dst_sa;
    socklen_t dst_sa_len;
    uint64_t dropped_packets;
    uint64_t last_log_us;
    int last_errno;
} relay_output_t;

typedef struct relay_ctx_t relay_ctx_t;

typedef struct
{
    pthread_t thread;
    int epoll_fd;
    int index;
    int pinned_cpu;
} relay_worker_t;

typedef struct
{
    pthread_mutex_t mu;
    bool started;
    bool affinity;
    int workers_count;
    relay_worker_t *workers;
} relay_engine_t;

static relay_engine_t g_engine;

struct relay_ctx_t
{
    // Immutable
    char *id;
    const char *input_url;

    asc_socket_t *in_sock;
    int in_fd;
    relay_output_t *outs;
    int out_count;

    // Receive batching
    int rx_batch;
    struct mmsghdr *rx_msgs;
    struct iovec *rx_iov;
    uint8_t *rx_buffers;

    // Transmit batching:
    // Linux sendmmsg() fast-path для типичного TS datagram size=1316 (7*188).
    struct mmsghdr *tx_msgs;
    struct iovec *tx_iov;

    // TS repacketization (как в udp_output: по 7 TS в датаграмму)
    uint8_t packet[RELAY_UDP_BUFFER_SIZE];
    size_t packet_skip;

    // Worker assignment
    int worker_index;

    // Lifetime
    pthread_mutex_t lock;
    bool closing;
    int refcount;

    // Stats (atomic-ish)
    uint64_t started_us;
    uint64_t last_rx_us;
    uint64_t bytes_in;
    uint64_t bytes_out;
    uint64_t datagrams_in;
    uint64_t datagrams_out;
    uint64_t bad_datagrams;
};

static bool g_sendmmsg_available = true;

static void relay_send_to_outputs(relay_ctx_t *ctx, const uint8_t *data, size_t size);

static uint32_t fnv1a_32(const char *s)
{
    uint32_t h = 2166136261u;
    if(!s)
        return h;
    for(const unsigned char *p = (const unsigned char *)s; *p; ++p)
    {
        h ^= (uint32_t)(*p);
        h *= 16777619u;
    }
    return h;
}

static void relay_log_send_error(const char *id, relay_output_t *out, const char *dst, int port, int err, uint64_t dropped_packets)
{
    const uint64_t now_us = asc_utime();
    const bool transient = (err == EAGAIN || err == EWOULDBLOCK || err == ENOBUFS);
    const bool changed_errno = (out->last_errno != err);

    if(transient)
    {
        out->dropped_packets += (dropped_packets > 0) ? dropped_packets : 1;
        if(changed_errno || now_us >= out->last_log_us + 2000000)
        {
            asc_log_warning("%s[%s] send overflow: dropped %" PRIu64 " packets; dst=%s:%d; last error [%s]",
                RELAY_MSG_PREFIX, id ? id : "stream",
                out->dropped_packets,
                dst ? dst : "?", port,
                asc_socket_error());
            out->dropped_packets = 0;
            out->last_log_us = now_us;
            out->last_errno = err;
        }
        return;
    }

    if(changed_errno || now_us >= out->last_log_us + 1000000)
    {
        asc_log_warning("%s[%s] send error: dst=%s:%d [%s]",
            RELAY_MSG_PREFIX, id ? id : "stream",
            dst ? dst : "?", port,
            asc_socket_error());
        out->last_log_us = now_us;
        out->last_errno = err;
    }
}

static void relay_send_to_outputs_mmsg(relay_ctx_t *ctx, int count)
{
    if(!ctx || count <= 0)
        return;

    if(!g_sendmmsg_available || !ctx->tx_msgs || !ctx->tx_iov)
    {
        // Fallback: старый путь sendto.
        for(int n = 0; n < count; ++n)
        {
            const uint8_t *buf = (const uint8_t *)ctx->rx_buffers + ((size_t)n * RELAY_UDP_BUFFER_SIZE);
            relay_send_to_outputs(ctx, buf, (size_t)(TS_PACKET_SIZE * 7));
        }
        return;
    }

    // Условия этого fast-path гарантируют, что у всех msg одинаковый размер 1316.
    const size_t msg_size = (size_t)(TS_PACKET_SIZE * 7);

    for(int i = 0; i < ctx->out_count; ++i)
    {
        relay_output_t *out = &ctx->outs[i];
        if(!out->sock)
            continue;

        // Подставляем destination sockaddr в каждый mmsghdr. Это дешевле, чем sendto() на каждый датаграмм.
        for(int n = 0; n < count; ++n)
        {
            ctx->tx_msgs[n].msg_hdr.msg_name = (void *)&out->dst_sa;
            ctx->tx_msgs[n].msg_hdr.msg_namelen = out->dst_sa_len;
        }

        errno = 0;
        const int fd = asc_socket_fd(out->sock);
        const int sent = sendmmsg(fd, ctx->tx_msgs, (unsigned int)count, 0);
        if(sent > 0)
        {
            __atomic_fetch_add(&ctx->bytes_out, (uint64_t)msg_size * (uint64_t)sent, __ATOMIC_RELAXED);
            __atomic_fetch_add(&ctx->datagrams_out, (uint64_t)sent, __ATOMIC_RELAXED);
        }

        if(sent == count)
            continue;

        // Error or partial send: считаем оставшиеся сообщения dropped.
        const int err = (sent < 0) ? errno : EAGAIN;
        const int dropped = (sent < 0) ? count : (count - sent);

        if(err == ENOSYS)
        {
            // На очень старом ядре sendmmsg может отсутствовать - откатываемся на sendto.
            g_sendmmsg_available = false;
            asc_log_warning("%s sendmmsg() not supported by kernel; falling back to sendto()", RELAY_MSG_PREFIX);

            for(int n = 0; n < count; ++n)
            {
                const uint8_t *buf = (const uint8_t *)ctx->rx_buffers + ((size_t)n * RELAY_UDP_BUFFER_SIZE);
                relay_send_to_outputs(ctx, buf, msg_size);
            }
            continue;
        }

        relay_log_send_error(ctx->id, out, out->dst_addr, out->dst_port, err, (uint64_t)dropped);
    }
}

static void relay_send_to_outputs(relay_ctx_t *ctx, const uint8_t *data, size_t size)
{
    for(int i = 0; i < ctx->out_count; ++i)
    {
        relay_output_t *out = &ctx->outs[i];
        if(!out->sock)
            continue;

        if(asc_socket_sendto(out->sock, data, size) != -1)
        {
            __atomic_fetch_add(&ctx->bytes_out, (uint64_t)size, __ATOMIC_RELAXED);
            __atomic_fetch_add(&ctx->datagrams_out, 1, __ATOMIC_RELAXED);
            continue;
        }

        const int err = errno;
        // best-effort logs, rate-limited
        relay_log_send_error(ctx->id, out, out->dst_addr, out->dst_port, err, 1);
    }
}

static void relay_process_datagram(relay_ctx_t *ctx, const uint8_t *buf, int len)
{
    if(len < (int)TS_PACKET_SIZE)
    {
        __atomic_fetch_add(&ctx->bad_datagrams, 1, __ATOMIC_RELAXED);
        return;
    }

    // Ожидаем ровный TS (без RTP) и размер кратный 188.
    if((len % TS_PACKET_SIZE) != 0)
    {
        __atomic_fetch_add(&ctx->bad_datagrams, 1, __ATOMIC_RELAXED);
        return;
    }

    // Fast path: большинство UDP multicast TS приходят уже как 7*188 (1316).
    // Если буфер выровнен и у нас нет накопленного хвоста - можно отправить datagram как есть,
    // избегая memcpy на каждый TS пакет.
    if(ctx->packet_skip == 0 && len == (int)(TS_PACKET_SIZE * 7))
    {
        relay_send_to_outputs(ctx, buf, (size_t)len);
        return;
    }

    int i = 0;
    for(; i <= len - (int)TS_PACKET_SIZE; i += TS_PACKET_SIZE)
    {
        memcpy(&ctx->packet[ctx->packet_skip], &buf[i], TS_PACKET_SIZE);
        ctx->packet_skip += TS_PACKET_SIZE;

        if(ctx->packet_skip > RELAY_UDP_BUFFER_SIZE - TS_PACKET_SIZE)
        {
            relay_send_to_outputs(ctx, ctx->packet, ctx->packet_skip);
            ctx->packet_skip = 0;
        }
    }
}

static void relay_ctx_on_read(relay_ctx_t *ctx)
{
    // Блокируем контекст, чтобы destroy мог безопасно дождаться окончания обработки.
    pthread_mutex_lock(&ctx->lock);
    if(ctx->closing)
    {
        pthread_mutex_unlock(&ctx->lock);
        return;
    }

    for(;;)
    {
        errno = 0;
        const int r = recvmmsg(ctx->in_fd, ctx->rx_msgs, (unsigned int)ctx->rx_batch, MSG_DONTWAIT, NULL);
        if(r <= 0)
        {
            if(r == 0 || errno == EAGAIN || errno == EWOULDBLOCK)
                break;
            // read error: считаем вход мёртвым, но не падаем процессом.
            __atomic_fetch_add(&ctx->bad_datagrams, 1, __ATOMIC_RELAXED);
            break;
        }

        const uint64_t now_us = asc_utime();
        __atomic_store_n(&ctx->last_rx_us, now_us, __ATOMIC_RELAXED);

        // Super fast-path:
        // типичный TS multicast уже приходит как 1316 bytes (7*188). Если у нас нет хвоста,
        // то можно отправить весь batch через sendmmsg(), снизив число syscalls в ~count раз.
        if(ctx->packet_skip == 0 && r >= 2)
        {
            bool can_batch = true;
            uint64_t in_bytes = 0;
            for(int n = 0; n < r; ++n)
            {
                const int len = (int)ctx->rx_msgs[n].msg_len;
                if(len != (int)(TS_PACKET_SIZE * 7))
                {
                    can_batch = false;
                    break;
                }
                in_bytes += (uint64_t)len;
            }

            if(can_batch)
            {
                __atomic_fetch_add(&ctx->bytes_in, in_bytes, __ATOMIC_RELAXED);
                __atomic_fetch_add(&ctx->datagrams_in, (uint64_t)r, __ATOMIC_RELAXED);

                relay_send_to_outputs_mmsg(ctx, r);

                if(r < ctx->rx_batch)
                    break;
                continue;
            }
        }

        for(int n = 0; n < r; ++n)
        {
            const int len = (int)ctx->rx_msgs[n].msg_len;
            const uint8_t *buf = (const uint8_t *)ctx->rx_iov[n].iov_base;
            if(len <= 0)
                continue;

            __atomic_fetch_add(&ctx->bytes_in, (uint64_t)len, __ATOMIC_RELAXED);
            __atomic_fetch_add(&ctx->datagrams_in, 1, __ATOMIC_RELAXED);

            relay_process_datagram(ctx, buf, len);
        }

        if(r < ctx->rx_batch)
            break;
    }

    pthread_mutex_unlock(&ctx->lock);
}

static void *relay_worker_loop(void *arg)
{
    relay_worker_t *w = (relay_worker_t *)arg;
    struct epoll_event events[RELAY_MAX_EVENTS];

    for(;;)
    {
        const int n = epoll_wait(w->epoll_fd, events, RELAY_MAX_EVENTS, -1);
        if(n < 0)
        {
            if(errno == EINTR)
                continue;
            asc_usleep(1000);
            continue;
        }

        for(int i = 0; i < n; ++i)
        {
            relay_ctx_t *ctx = (relay_ctx_t *)events[i].data.ptr;
            if(!ctx)
                continue;

            __atomic_fetch_add(&ctx->refcount, 1, __ATOMIC_RELAXED);
            relay_ctx_on_read(ctx);
            __atomic_fetch_sub(&ctx->refcount, 1, __ATOMIC_RELAXED);
        }
    }

    return NULL;
}

static int clamp_int(int value, int min_value, int max_value)
{
    if(value < min_value)
        return min_value;
    if(value > max_value)
        return max_value;
    return value;
}

static int detect_default_workers(void)
{
    long n = sysconf(_SC_NPROCESSORS_ONLN);
    if(n < 1)
        return 1;
    // Оставляем 1 ядро под control plane (Lua/UI/HTTP), остальное под data plane.
    if(n > 1)
        n = n - 1;
    if(n > 32)
        n = 32;
    return (int)n;
}

static int detect_allowed_cpus(int *out, int out_cap)
{
    if(!out || out_cap <= 0)
        return 0;

    cpu_set_t set;
    CPU_ZERO(&set);
    if(sched_getaffinity(0, sizeof(set), &set) != 0)
        return 0;

    int n = 0;
    for(int cpu = 0; cpu < CPU_SETSIZE && n < out_cap; ++cpu)
    {
        if(CPU_ISSET(cpu, &set))
            out[n++] = cpu;
    }
    return n;
}

static void maybe_pin_thread(pthread_t thread, int worker_index, bool enable_affinity, int workers_count)
{
    if(!enable_affinity)
        return;

    // Учитываем ограничения контейнера/cpuset: берём список разрешённых CPU.
    int allowed[CPU_SETSIZE];
    const int allowed_n = detect_allowed_cpus(allowed, (int)(sizeof(allowed) / sizeof(allowed[0])));
    if(allowed_n <= 1)
        return;

    // По умолчанию стараемся не трогать первый CPU из allowed списка, оставляя его под control plane.
    // Но если воркеров >= доступных CPU, то используем весь список (иначе получим коллизию и 100% одного ядра).
    int start = 0;
    int target_n = allowed_n;
    if(allowed_n > 1 && workers_count <= (allowed_n - 1))
    {
        start = 1;
        target_n = allowed_n - 1;
    }
    if(target_n <= 0)
        return;
    const int cpu = allowed[start + (worker_index % target_n)];

    cpu_set_t mask;
    CPU_ZERO(&mask);
    CPU_SET(cpu, &mask);

    const int rc = pthread_setaffinity_np(thread, sizeof(mask), &mask);
    if(rc != 0)
    {
        // Не критично: продолжаем работать без affinity.
        asc_log_warning("%s worker[%d/%d] setaffinity(cpu=%d) failed: %s",
            RELAY_MSG_PREFIX, worker_index, workers_count, cpu, strerror(rc));
    }
}

static bool engine_ensure_started(int requested_workers, bool affinity)
{
    pthread_mutex_lock(&g_engine.mu);
    if(g_engine.started)
    {
        pthread_mutex_unlock(&g_engine.mu);
        return true;
    }

    int workers = requested_workers;
    if(workers <= 0)
        workers = detect_default_workers();
    workers = clamp_int(workers, 1, 64);

    g_engine.workers = (relay_worker_t *)calloc((size_t)workers, sizeof(relay_worker_t));
    if(!g_engine.workers)
    {
        pthread_mutex_unlock(&g_engine.mu);
        return false;
    }

    g_engine.workers_count = workers;
    g_engine.affinity = affinity;
    for(int i = 0; i < workers; ++i)
    {
        relay_worker_t *w = &g_engine.workers[i];
        w->index = i;
        w->pinned_cpu = -1;
        w->epoll_fd = epoll_create1(0);
        if(w->epoll_fd < 0)
        {
            pthread_mutex_unlock(&g_engine.mu);
            return false;
        }
        const int rc = pthread_create(&w->thread, NULL, relay_worker_loop, w);
        if(rc != 0)
        {
            pthread_mutex_unlock(&g_engine.mu);
            return false;
        }

        // Опционально пиним воркеры, чтобы scheduler не складывал их на одно ядро
        // (это типичная причина "одно ядро 100% и дергания").
        maybe_pin_thread(w->thread, i, affinity, workers);
    }

    g_engine.started = true;
    pthread_mutex_unlock(&g_engine.mu);

    asc_log_info("%s started: workers=%d affinity=%s",
        RELAY_MSG_PREFIX, workers, affinity ? "on" : "off");
    return true;
}

static int pick_worker_index(const char *id)
{
    const int n = g_engine.workers_count;
    if(n <= 1)
        return 0;
    const uint32_t h = fnv1a_32(id ? id : "");
    return (int)(h % (uint32_t)n);
}

static bool ctx_register_in_engine(relay_ctx_t *ctx)
{
    if(!g_engine.started || !g_engine.workers || g_engine.workers_count <= 0)
        return false;

    const int widx = pick_worker_index(ctx->id);
    if(widx < 0 || widx >= g_engine.workers_count)
        return false;

    relay_worker_t *w = &g_engine.workers[widx];
    struct epoll_event ev;
    memset(&ev, 0, sizeof(ev));
    ev.events = EPOLLIN;
    ev.data.ptr = ctx;

    if(epoll_ctl(w->epoll_fd, EPOLL_CTL_ADD, ctx->in_fd, &ev) != 0)
        return false;

    ctx->worker_index = widx;
    return true;
}

static void ctx_unregister_from_engine(relay_ctx_t *ctx)
{
    if(!g_engine.started || !g_engine.workers || g_engine.workers_count <= 0)
        return;

    const int widx = ctx->worker_index;
    if(widx < 0 || widx >= g_engine.workers_count)
        return;

    relay_worker_t *w = &g_engine.workers[widx];
    epoll_ctl(w->epoll_fd, EPOLL_CTL_DEL, ctx->in_fd, NULL);
}

static void free_ctx(relay_ctx_t *ctx)
{
    if(!ctx)
        return;

    if(ctx->in_sock)
    {
        asc_socket_multicast_leave(ctx->in_sock);
        asc_socket_close(ctx->in_sock);
        ctx->in_sock = NULL;
    }

    if(ctx->outs)
    {
        for(int i = 0; i < ctx->out_count; ++i)
        {
            if(ctx->outs[i].sock)
            {
                asc_socket_close(ctx->outs[i].sock);
                ctx->outs[i].sock = NULL;
            }
        }
        free(ctx->outs);
        ctx->outs = NULL;
        ctx->out_count = 0;
    }

    if(ctx->rx_buffers)
    {
        free(ctx->rx_buffers);
        ctx->rx_buffers = NULL;
    }
    if(ctx->rx_iov)
    {
        free(ctx->rx_iov);
        ctx->rx_iov = NULL;
    }
    if(ctx->rx_msgs)
    {
        free(ctx->rx_msgs);
        ctx->rx_msgs = NULL;
    }
    if(ctx->tx_iov)
    {
        free(ctx->tx_iov);
        ctx->tx_iov = NULL;
    }
    if(ctx->tx_msgs)
    {
        free(ctx->tx_msgs);
        ctx->tx_msgs = NULL;
    }

    if(ctx->id)
    {
        free(ctx->id);
        ctx->id = NULL;
    }

    pthread_mutex_destroy(&ctx->lock);
    free(ctx);
}

static const char *table_get_string(lua_State *L, int idx, const char *key)
{
    const char *out = NULL;
    lua_getfield(L, idx, key);
    if(lua_type(L, -1) == LUA_TSTRING)
        out = lua_tostring(L, -1);
    lua_pop(L, 1);
    return out;
}

static int table_get_int(lua_State *L, int idx, const char *key, int fallback)
{
    int out = fallback;
    lua_getfield(L, idx, key);
    const int t = lua_type(L, -1);
    if(t == LUA_TNUMBER)
        out = (int)lua_tonumber(L, -1);
    else if(t == LUA_TSTRING)
        out = atoi(lua_tostring(L, -1));
    else if(t == LUA_TBOOLEAN)
        out = lua_toboolean(L, -1) ? 1 : 0;
    lua_pop(L, 1);
    return out;
}

static asc_socket_t *open_input_socket(const char *addr, int port, const char *localaddr, int socket_size)
{
    asc_socket_t *sock = asc_socket_open_udp4(NULL);
    if(!sock)
        return NULL;
    asc_socket_set_reuseaddr(sock, 1);
    if(!asc_socket_bind(sock, addr, port))
    {
        asc_socket_close(sock);
        return NULL;
    }
    if(socket_size > 0)
        asc_socket_set_buffer(sock, socket_size, 0);
    asc_socket_multicast_join(sock, addr, localaddr);
    return sock;
}

static asc_socket_t *open_output_socket(const char *addr, int port, const char *localaddr, int ttl, int socket_size)
{
    asc_socket_t *sock = asc_socket_open_udp4(NULL);
    if(!sock)
        return NULL;
    asc_socket_set_reuseaddr(sock, 1);
    if(!asc_socket_bind(sock, NULL, 0))
    {
        asc_socket_close(sock);
        return NULL;
    }
    if(socket_size > 0)
        asc_socket_set_buffer(sock, 0, socket_size);
    if(localaddr && localaddr[0])
        asc_socket_set_multicast_if(sock, localaddr);
    if(ttl <= 0)
        ttl = 32;
    asc_socket_set_multicast_ttl(sock, ttl);
    asc_socket_set_sockaddr(sock, addr, port);
    return sock;
}

static relay_ctx_t *create_ctx(lua_State *L, int opts_idx)
{
    const char *id = table_get_string(L, opts_idx, "id");
    if(!id || !id[0])
        return NULL;

    // input
    lua_getfield(L, opts_idx, "input");
    if(lua_type(L, -1) != LUA_TTABLE)
    {
        lua_pop(L, 1);
        return NULL;
    }
    const int input_idx = lua_gettop(L);
    const char *in_addr = table_get_string(L, input_idx, "addr");
    const int in_port = table_get_int(L, input_idx, "port", 0);
    const char *in_local = table_get_string(L, input_idx, "localaddr");
    const int in_socket_size = table_get_int(L, input_idx, "socket_size", 0);
    const char *input_url = table_get_string(L, input_idx, "source_url");
    lua_pop(L, 1); // input

    if(!in_addr || !in_addr[0] || in_port <= 0 || in_port > 65535)
        return NULL;

    // outputs
    lua_getfield(L, opts_idx, "outputs");
    if(lua_type(L, -1) != LUA_TTABLE)
    {
        lua_pop(L, 1);
        return NULL;
    }
    const int outputs_idx = lua_gettop(L);
    const int out_len = (int)luaL_len(L, outputs_idx);
    if(out_len <= 0)
    {
        lua_pop(L, 1);
        return NULL;
    }

    relay_ctx_t *ctx = (relay_ctx_t *)calloc(1, sizeof(relay_ctx_t));
    if(!ctx)
    {
        lua_pop(L, 1);
        return NULL;
    }
    pthread_mutex_init(&ctx->lock, NULL);
    ctx->closing = false;
    ctx->refcount = 0;
    ctx->worker_index = 0;
    ctx->started_us = asc_utime();
    ctx->last_rx_us = 0;
    ctx->packet_skip = 0;

    ctx->id = strdup(id);
    ctx->input_url = input_url;

    ctx->rx_batch = table_get_int(L, opts_idx, "rx_batch", RELAY_RX_BATCH_DEFAULT);
    ctx->rx_batch = clamp_int(ctx->rx_batch, 1, RELAY_RX_BATCH_MAX);

    ctx->in_sock = open_input_socket(in_addr, in_port, in_local, in_socket_size);
    if(!ctx->in_sock)
    {
        free_ctx(ctx);
        lua_pop(L, 1);
        return NULL;
    }
    ctx->in_fd = asc_socket_fd(ctx->in_sock);

    ctx->outs = (relay_output_t *)calloc((size_t)out_len, sizeof(relay_output_t));
    if(!ctx->outs)
    {
        free_ctx(ctx);
        lua_pop(L, 1);
        return NULL;
    }
    ctx->out_count = out_len;

    for(int i = 1; i <= out_len; ++i)
    {
        lua_rawgeti(L, outputs_idx, i);
        if(lua_type(L, -1) != LUA_TTABLE)
        {
            lua_pop(L, 1);
            free_ctx(ctx);
            lua_pop(L, 1);
            return NULL;
        }
        const int out_idx = lua_gettop(L);
        const char *out_addr = table_get_string(L, out_idx, "addr");
        const int out_port = table_get_int(L, out_idx, "port", 0);
        const char *out_local = table_get_string(L, out_idx, "localaddr");
        const int out_ttl = table_get_int(L, out_idx, "ttl", 32);
        const int out_socket_size = table_get_int(L, out_idx, "socket_size", 0);

        if(!out_addr || !out_addr[0] || out_port <= 0 || out_port > 65535)
        {
            lua_pop(L, 1);
            free_ctx(ctx);
            lua_pop(L, 1);
            return NULL;
        }

        ctx->outs[i - 1].sock = open_output_socket(out_addr, out_port, out_local, out_ttl, out_socket_size);
        ctx->outs[i - 1].dst_addr = out_addr;
        ctx->outs[i - 1].dst_port = out_port;
        memset(&ctx->outs[i - 1].dst_sa, 0, sizeof(ctx->outs[i - 1].dst_sa));
        ctx->outs[i - 1].dst_sa.sin_family = AF_INET;
        ctx->outs[i - 1].dst_sa.sin_addr.s_addr = inet_addr(out_addr);
        ctx->outs[i - 1].dst_sa.sin_port = htons(out_port);
        ctx->outs[i - 1].dst_sa_len = sizeof(struct sockaddr_in);
        lua_pop(L, 1);
        if(!ctx->outs[i - 1].sock)
        {
            free_ctx(ctx);
            lua_pop(L, 1);
            return NULL;
        }
    }

    // allocate recvmmsg buffers
    ctx->rx_msgs = (struct mmsghdr *)calloc((size_t)ctx->rx_batch, sizeof(struct mmsghdr));
    ctx->rx_iov = (struct iovec *)calloc((size_t)ctx->rx_batch, sizeof(struct iovec));
    ctx->rx_buffers = (uint8_t *)malloc((size_t)ctx->rx_batch * RELAY_UDP_BUFFER_SIZE);
    if(!ctx->rx_msgs || !ctx->rx_iov || !ctx->rx_buffers)
    {
        free_ctx(ctx);
        lua_pop(L, 1);
        return NULL;
    }
    for(int i = 0; i < ctx->rx_batch; ++i)
    {
        ctx->rx_iov[i].iov_base = ctx->rx_buffers + ((size_t)i * RELAY_UDP_BUFFER_SIZE);
        ctx->rx_iov[i].iov_len = RELAY_UDP_BUFFER_SIZE;
        ctx->rx_msgs[i].msg_hdr.msg_iov = &ctx->rx_iov[i];
        ctx->rx_msgs[i].msg_hdr.msg_iovlen = 1;
    }

    // allocate sendmmsg buffers (fast-path only for 1316)
    ctx->tx_msgs = (struct mmsghdr *)calloc((size_t)ctx->rx_batch, sizeof(struct mmsghdr));
    ctx->tx_iov = (struct iovec *)calloc((size_t)ctx->rx_batch, sizeof(struct iovec));
    if(!ctx->tx_msgs || !ctx->tx_iov)
    {
        free_ctx(ctx);
        lua_pop(L, 1);
        return NULL;
    }
    for(int i = 0; i < ctx->rx_batch; ++i)
    {
        ctx->tx_iov[i].iov_base = ctx->rx_buffers + ((size_t)i * RELAY_UDP_BUFFER_SIZE);
        ctx->tx_iov[i].iov_len = (size_t)(TS_PACKET_SIZE * 7);
        ctx->tx_msgs[i].msg_hdr.msg_iov = &ctx->tx_iov[i];
        ctx->tx_msgs[i].msg_hdr.msg_iovlen = 1;
    }

    lua_pop(L, 1); // outputs
    return ctx;
}

// Lua bindings

#define RELAY_MT "udp_relay.handle"

static relay_ctx_t *check_handle(lua_State *L)
{
    relay_ctx_t **p = (relay_ctx_t **)luaL_checkudata(L, 1, RELAY_MT);
    return p ? *p : NULL;
}

static void destroy_handle(relay_ctx_t *ctx)
{
    if(!ctx)
        return;

    pthread_mutex_lock(&ctx->lock);
    ctx->closing = true;
    pthread_mutex_unlock(&ctx->lock);

    ctx_unregister_from_engine(ctx);

    // Дожидаемся завершения возможного обработчика epoll-события.
    for(int i = 0; i < 200; ++i)
    {
        const int rc = __atomic_load_n(&ctx->refcount, __ATOMIC_RELAXED);
        if(rc <= 0)
            break;
        asc_usleep(1000);
    }

    free_ctx(ctx);
}

static int relay_handle_close(lua_State *L)
{
    relay_ctx_t **p = (relay_ctx_t **)luaL_checkudata(L, 1, RELAY_MT);
    if(p && *p)
    {
        destroy_handle(*p);
        *p = NULL;
    }
    lua_pushboolean(L, 1);
    return 1;
}

static int relay_handle_gc(lua_State *L)
{
    relay_ctx_t **p = (relay_ctx_t **)luaL_checkudata(L, 1, RELAY_MT);
    if(p && *p)
    {
        destroy_handle(*p);
        *p = NULL;
    }
    return 0;
}

static int relay_handle_stats(lua_State *L)
{
    relay_ctx_t *ctx = check_handle(L);
    if(!ctx)
    {
        lua_pushnil(L);
        return 1;
    }

    const uint64_t now_us = asc_utime();
    const uint64_t started_us = __atomic_load_n(&ctx->started_us, __ATOMIC_RELAXED);
    const uint64_t last_rx_us = __atomic_load_n(&ctx->last_rx_us, __ATOMIC_RELAXED);
    const uint64_t bytes_in = __atomic_load_n(&ctx->bytes_in, __ATOMIC_RELAXED);
    const uint64_t bytes_out = __atomic_load_n(&ctx->bytes_out, __ATOMIC_RELAXED);
    const uint64_t d_in = __atomic_load_n(&ctx->datagrams_in, __ATOMIC_RELAXED);
    const uint64_t d_out = __atomic_load_n(&ctx->datagrams_out, __ATOMIC_RELAXED);
    const uint64_t bad = __atomic_load_n(&ctx->bad_datagrams, __ATOMIC_RELAXED);

    const bool on_air = (last_rx_us != 0) && (now_us < last_rx_us + 2000000);
    const uint64_t uptime_sec = (now_us > started_us) ? ((now_us - started_us) / 1000000) : 0;

    lua_newtable(L);

    lua_pushboolean(L, on_air ? 1 : 0);
    lua_setfield(L, -2, "on_air");

    lua_pushinteger(L, (lua_Integer)uptime_sec);
    lua_setfield(L, -2, "uptime_sec");

    lua_pushinteger(L, (lua_Integer)bytes_in);
    lua_setfield(L, -2, "bytes_in");

    lua_pushinteger(L, (lua_Integer)bytes_out);
    lua_setfield(L, -2, "bytes_out");

    lua_pushinteger(L, (lua_Integer)d_in);
    lua_setfield(L, -2, "datagrams_in");

    lua_pushinteger(L, (lua_Integer)d_out);
    lua_setfield(L, -2, "datagrams_out");

    lua_pushinteger(L, (lua_Integer)bad);
    lua_setfield(L, -2, "bad_datagrams");

    if(ctx->input_url)
    {
        lua_pushstring(L, ctx->input_url);
        lua_setfield(L, -2, "input_url");
    }

    return 1;
}

static int relay_start(lua_State *L)
{
    if(lua_type(L, 1) != LUA_TTABLE)
    {
        lua_pushnil(L);
        lua_pushstring(L, "options table required");
        return 2;
    }

    const int workers = table_get_int(L, 1, "workers", 0);
    const bool affinity = table_get_int(L, 1, "affinity", 0) ? true : false;

    if(!g_engine.started)
    {
        pthread_mutex_init(&g_engine.mu, NULL);
    }
    if(!engine_ensure_started(workers, affinity))
    {
        lua_pushnil(L);
        lua_pushstring(L, "failed to start relay engine");
        return 2;
    }

    relay_ctx_t *ctx = create_ctx(L, 1);
    if(!ctx)
    {
        lua_pushnil(L);
        lua_pushstring(L, "invalid relay config");
        return 2;
    }

    if(!ctx_register_in_engine(ctx))
    {
        free_ctx(ctx);
        lua_pushnil(L);
        lua_pushstring(L, "failed to register relay in engine");
        return 2;
    }

    relay_ctx_t **p = (relay_ctx_t **)lua_newuserdata(L, sizeof(relay_ctx_t *));
    *p = ctx;

    luaL_getmetatable(L, RELAY_MT);
    lua_setmetatable(L, -2);
    return 1;
}

LUA_API int luaopen_udp_relay(lua_State *L)
{
    static const luaL_Reg api[] =
    {
        { "start", relay_start },
        { NULL, NULL }
    };

    static const luaL_Reg meta[] =
    {
        { "stats", relay_handle_stats },
        { "close", relay_handle_close },
        { "__gc", relay_handle_gc },
        { NULL, NULL }
    };

    luaL_newmetatable(L, RELAY_MT);
    luaL_setfuncs(L, meta, 0);
    lua_pushvalue(L, -1);
    lua_setfield(L, -2, "__index");
    lua_pop(L, 1);

    luaL_newlib(L, api);
    lua_setglobal(L, "udp_relay");
    return 0;
}

#else

LUA_API int luaopen_udp_relay(lua_State *L)
{
    lua_newtable(L);
    lua_setglobal(L, "udp_relay");
    return 0;
}

#endif
