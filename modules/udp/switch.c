/*
 * Astral Module: UDP Switch
 *
 * Purpose:
 *   Acts as a local UDP input that can "switch" between multiple UDP senders.
 *   Only packets from the active sender are forwarded downstream.
 *
 * Module Name:
 *      udp_switch
 *
 * Module Options:
 *      addr        - string, bind address (required)
 *      port        - number, bind port (default 0, random)
 *      socket_size - number, socket buffer size
 *      rtp         - boolean, strip RTP header before TS parsing (default false)
 *
 * Module Methods:
 *      port()          - return bound UDP port number
 *      source()        - return active sender {addr, port, last_seen_ts} or nil
 *      set_source(a,p) - lock active sender to addr+port
 *      clear_source()  - clear active sender (auto-lock to next sender on traffic)
 *      senders()       - return array of known senders [{addr,port,last_seen_ts}, ...]
 */

#include <astra.h>

#define UDP_SWITCH_BUFFER_SIZE 1460
#define RTP_HEADER_SIZE 12

#define RTP_IS_EXT(_data) ((_data[0] & 0x10))
#define RTP_EXT_SIZE(_data) \
    (((_data[RTP_HEADER_SIZE + 2] << 8) | _data[RTP_HEADER_SIZE + 3]) * 4 + 4)

#define SENDERS_MAX 8

typedef struct
{
    char addr[32];
    int port;
    time_t last_seen_ts;
} udp_sender_t;

struct module_data_t
{
    MODULE_STREAM_DATA();

    struct
    {
        const char *addr;
        int port;
        bool rtp;
    } config;

    bool is_error_message;

    asc_socket_t *sock;
    uint8_t buffer[UDP_SWITCH_BUFFER_SIZE];

    bool active_set;
    char active_addr[32];
    int active_port;

    asc_list_t *senders;
};

static udp_sender_t *find_sender(module_data_t *mod, const char *addr, int port)
{
    if(!mod->senders)
        return NULL;

    asc_list_for(mod->senders)
    {
        udp_sender_t *s = (udp_sender_t *)asc_list_data(mod->senders);
        if(s && s->port == port && strcmp(s->addr, addr) == 0)
            return s;
    }
    return NULL;
}

static void ensure_sender_capacity(module_data_t *mod)
{
    if(!mod->senders)
        return;

    while(asc_list_size(mod->senders) > SENDERS_MAX)
    {
        asc_list_first(mod->senders);
        if(asc_list_eol(mod->senders))
            break;
        udp_sender_t *s = (udp_sender_t *)asc_list_data(mod->senders);
        asc_list_remove_current(mod->senders);
        free(s);
    }
}

static udp_sender_t *touch_sender(module_data_t *mod, const char *addr, int port)
{
    if(!addr || addr[0] == '\0')
        return NULL;

    if(!mod->senders)
        mod->senders = asc_list_init();

    udp_sender_t *s = find_sender(mod, addr, port);
    if(!s)
    {
        if(asc_list_size(mod->senders) >= SENDERS_MAX)
        {
            /* Drop oldest (head) entry. */
            asc_list_first(mod->senders);
            if(!asc_list_eol(mod->senders))
            {
                udp_sender_t *old = (udp_sender_t *)asc_list_data(mod->senders);
                asc_list_remove_current(mod->senders);
                free(old);
            }
        }

        s = (udp_sender_t *)calloc(1, sizeof(udp_sender_t));
        snprintf(s->addr, sizeof(s->addr), "%s", addr);
        s->port = port;
        asc_list_insert_tail(mod->senders, s);
    }
    s->last_seen_ts = time(NULL);
    ensure_sender_capacity(mod);
    return s;
}

static void on_close(void *arg)
{
    module_data_t *mod = (module_data_t *)arg;

    if(mod->sock)
    {
        asc_socket_close(mod->sock);
        mod->sock = NULL;
    }
}

static bool sender_matches_active(module_data_t *mod, const char *addr, int port)
{
    if(!mod->active_set)
        return true;
    if(mod->active_port != port)
        return false;
    return strcmp(mod->active_addr, addr) == 0;
}

static void on_read(void *arg)
{
    module_data_t *mod = (module_data_t *)arg;

    const int len = asc_socket_recvfrom(mod->sock, mod->buffer, UDP_SWITCH_BUFFER_SIZE);
    if(len <= 0)
    {
        if(len == 0 || errno == EAGAIN || errno == EWOULDBLOCK)
            return;
        on_close(mod);
        return;
    }

    const char *sender_addr = asc_socket_recv_addr(mod->sock);
    const int sender_port = asc_socket_recv_port(mod->sock);
    if(!sender_addr)
        sender_addr = "";

    udp_sender_t *sender = touch_sender(mod, sender_addr, sender_port);
    if(sender && !mod->active_set)
    {
        /* Default safety: lock to the first observed sender. */
        snprintf(mod->active_addr, sizeof(mod->active_addr), "%s", sender->addr);
        mod->active_port = sender->port;
        mod->active_set = true;
    }

    if(!sender_matches_active(mod, sender_addr, sender_port))
        return;

    int i = 0;
    if(mod->config.rtp)
    {
        i = RTP_HEADER_SIZE;
        if(RTP_IS_EXT(mod->buffer))
        {
            if(len < RTP_HEADER_SIZE + 4)
                return;
            i += RTP_EXT_SIZE(mod->buffer);
        }
    }

    for(; i <= len - TS_PACKET_SIZE; i += TS_PACKET_SIZE)
        module_stream_send(mod, &mod->buffer[i]);

    if(i != len && !mod->is_error_message)
    {
        asc_log_error("[udp_switch] wrong stream format. drop %d bytes", len - i);
        mod->is_error_message = true;
    }
}

static int method_port(module_data_t *mod)
{
    const int port = mod->sock ? asc_socket_port(mod->sock) : -1;
    lua_pushnumber(lua, port);
    return 1;
}

static int method_source(module_data_t *mod)
{
    if(!mod->active_set)
    {
        lua_pushnil(lua);
        return 1;
    }

    udp_sender_t *s = find_sender(mod, mod->active_addr, mod->active_port);

    lua_newtable(lua);
    lua_pushstring(lua, mod->active_addr);
    lua_setfield(lua, -2, "addr");
    lua_pushnumber(lua, mod->active_port);
    lua_setfield(lua, -2, "port");
    if(s)
    {
        lua_pushnumber(lua, (lua_Number)s->last_seen_ts);
        lua_setfield(lua, -2, "last_seen_ts");
    }
    return 1;
}

static int method_set_source(module_data_t *mod)
{
    const char *addr = lua_tostring(lua, 2);
    const int port = (int)lua_tonumber(lua, 3);
    if(!addr || addr[0] == '\0' || port <= 0 || port > 65535)
    {
        lua_pushboolean(lua, 0);
        return 1;
    }

    snprintf(mod->active_addr, sizeof(mod->active_addr), "%s", addr);
    mod->active_port = port;
    mod->active_set = true;
    touch_sender(mod, addr, port);

    lua_pushboolean(lua, 1);
    return 1;
}

static int method_clear_source(module_data_t *mod)
{
    mod->active_set = false;
    mod->active_addr[0] = '\0';
    mod->active_port = 0;
    lua_pushboolean(lua, 1);
    return 1;
}

static int method_senders(module_data_t *mod)
{
    lua_newtable(lua);
    if(!mod->senders)
        return 1;

    int idx = 1;
    asc_list_for(mod->senders)
    {
        udp_sender_t *s = (udp_sender_t *)asc_list_data(mod->senders);
        if(!s)
            continue;

        lua_newtable(lua);
        lua_pushstring(lua, s->addr);
        lua_setfield(lua, -2, "addr");
        lua_pushnumber(lua, s->port);
        lua_setfield(lua, -2, "port");
        lua_pushnumber(lua, (lua_Number)s->last_seen_ts);
        lua_setfield(lua, -2, "last_seen_ts");

        lua_rawseti(lua, -2, idx++);
    }

    return 1;
}

static void module_init(module_data_t *mod)
{
    module_stream_init(mod, NULL);

    module_option_string("addr", &mod->config.addr, NULL);
    asc_assert(mod->config.addr != NULL, "[udp_switch] option 'addr' is required");

    mod->config.port = 0;
    module_option_number("port", &mod->config.port);

    module_option_boolean("rtp", &mod->config.rtp);

    mod->sock = asc_socket_open_udp4(mod);
    asc_socket_set_reuseaddr(mod->sock, 1);
    if(!asc_socket_bind(mod->sock, mod->config.addr, mod->config.port))
        return;

    int value;
    if(module_option_number("socket_size", &value))
        asc_socket_set_buffer(mod->sock, value, 0);

    asc_socket_set_on_read(mod->sock, on_read);
    asc_socket_set_on_close(mod->sock, on_close);
}

static void module_destroy(module_data_t *mod)
{
    module_stream_destroy(mod);
    on_close(mod);

    if(mod->senders)
    {
        asc_list_for(mod->senders)
        {
            udp_sender_t *s = (udp_sender_t *)asc_list_data(mod->senders);
            free(s);
        }
        asc_list_destroy(mod->senders);
        mod->senders = NULL;
    }
}

MODULE_STREAM_METHODS()

MODULE_LUA_METHODS()
{
    MODULE_STREAM_METHODS_REF(),
    { "port", method_port },
    { "source", method_source },
    { "set_source", method_set_source },
    { "clear_source", method_clear_source },
    { "senders", method_senders },
};
MODULE_LUA_REGISTER(udp_switch)

