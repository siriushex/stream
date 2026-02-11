/*
 * Astra Module: Utils
 * http://cesbo.com/astra
 *
 * Copyright (C) 2012-2013, Andrey Dyldin <and@cesbo.com>
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
 * Set of the additional methods and classes for lua
 *
 * Methods:
 *      utils.hostname()
 *                  - get name of the host
 *      utils.ifaddrs()
 *                  - get network interfaces list (except Win32)
 *      utils.stat(path)
 *                  - file/folder information
 *      utils.readdir(path)
 *                  - iterator to scan directory located by path
 */

#include <astra.h>
#include "core/embedded_fs.h"

#include <dirent.h>
#include <errno.h>
#include <string.h>

#ifndef _WIN32
#   include <sys/socket.h>
#   include <unistd.h>
#   include <netinet/in.h>
#   include <sys/statvfs.h>
#   ifndef __ANDROID__
#       include <ifaddrs.h>
#   endif
#   include <netdb.h>
#endif

/* hostname */

static int utils_hostname(lua_State *L)
{
    char hostname[64];
    if(gethostname(hostname, sizeof(hostname)) != 0)
        luaL_error(L, "failed to get hostname");
    lua_pushstring(L, hostname);
    return 1;
}

#ifdef HAVE_GETIFADDRS
static int utils_ifaddrs(lua_State *L)
{
    struct ifaddrs *ifaddr;
    char host[NI_MAXHOST];

    const int ret = getifaddrs(&ifaddr);
    asc_assert(ret != -1, "getifaddrs() failed");

    static const char __ipv4[] = "ipv4";
    static const char __ipv6[] = "ipv6";
#ifdef AF_LINK
    static const char __link[] = "link";
#endif

    lua_newtable(L);

    for(struct ifaddrs *i = ifaddr; i; i = i->ifa_next)
    {
        if(!i->ifa_addr)
            continue;

        lua_getfield(L, -1, i->ifa_name);
        if(lua_isnil(L, -1))
        {
            lua_pop(L, 1);
            lua_newtable(L);
            lua_pushstring(L, i->ifa_name);
            lua_pushvalue(L, -2);
            lua_settable(L, -4);
        }

        const int s = getnameinfo(i->ifa_addr, sizeof(struct sockaddr_in)
                                  , host, sizeof(host), NULL, 0
                                  , NI_NUMERICHOST);
        if(s == 0 && *host != '\0')
        {
            const char *ip_family = NULL;

            switch(i->ifa_addr->sa_family)
            {
                case AF_INET:
                    ip_family = __ipv4;
                    break;
                case AF_INET6:
                    ip_family = __ipv6;
                    break;
#ifdef AF_LINK
                case AF_LINK:
                    ip_family = __link;
                    break;
#endif
                default:
                    break;
            }

            if(ip_family)
            {
                int count = 0;
                lua_getfield(L, -1, ip_family);
                if(lua_isnil(L, -1))
                {
                    lua_pop(L, 1);
                    lua_newtable(L);
                    lua_pushstring(L, ip_family);
                    lua_pushvalue(L, -2);
                    lua_settable(L, -4);
                    count = 0;
                }
                else
                    count = luaL_len(L, -1);

                lua_pushnumber(L, count + 1);
                lua_pushstring(L, host);
                lua_settable(L, -3);
                lua_pop(L, 1);
            }
        }

        lua_pop(L, 1);
    }
    freeifaddrs(ifaddr);

    return 1;
}
#endif

static int utils_stat(lua_State *L)
{
    const char *path = luaL_checkstring(L, 1);

    lua_newtable(L);

    struct stat sb;
    if(stat(path, &sb) != 0)
    {
        lua_pushstring(L, strerror(errno));
        lua_setfield(L, -2, "error");

        memset(&sb, 0, sizeof(struct stat));
    }

    switch(sb.st_mode & S_IFMT)
    {
        case S_IFBLK: lua_pushstring(L, "block"); break;
        case S_IFCHR: lua_pushstring(L, "character"); break;
        case S_IFDIR: lua_pushstring(L, "directory"); break;
        case S_IFIFO: lua_pushstring(L, "pipe"); break;
        case S_IFREG: lua_pushstring(L, "file"); break;
#ifndef _WIN32
        case S_IFLNK: lua_pushstring(L, "symlink"); break;
        case S_IFSOCK: lua_pushstring(L, "socket"); break;
#endif
        default: lua_pushstring(L, "unknown"); break;
    }
    lua_setfield(L, -2, "type");

    lua_pushnumber(L, sb.st_uid);
    lua_setfield(L, -2, "uid");

    lua_pushnumber(L, sb.st_gid);
    lua_setfield(L, -2, "gid");

    lua_pushnumber(L, sb.st_size);
    lua_setfield(L, -2, "size");

    return 1;
}

static int utils_statvfs(lua_State *L)
{
#ifndef _WIN32
    const char *path = luaL_checkstring(L, 1);

    lua_newtable(L);

    struct statvfs sv;
    if(statvfs(path, &sv) != 0)
    {
        lua_pushstring(L, strerror(errno));
        lua_setfield(L, -2, "error");
        return 1;
    }

    const unsigned long long frsize = sv.f_frsize ? (unsigned long long)sv.f_frsize : (unsigned long long)sv.f_bsize;
    const unsigned long long total = frsize * (unsigned long long)sv.f_blocks;
    const unsigned long long free = frsize * (unsigned long long)sv.f_bfree;
    const unsigned long long avail = frsize * (unsigned long long)sv.f_bavail;
    const unsigned long long used = (total > free) ? (total - free) : 0ULL;

    double used_percent = 0.0;
    if(total > 0)
        used_percent = ((double)used / (double)total) * 100.0;

    lua_pushinteger(L, (lua_Integer)total);
    lua_setfield(L, -2, "total_bytes");
    lua_pushinteger(L, (lua_Integer)free);
    lua_setfield(L, -2, "free_bytes");
    lua_pushinteger(L, (lua_Integer)avail);
    lua_setfield(L, -2, "avail_bytes");
    lua_pushinteger(L, (lua_Integer)used);
    lua_setfield(L, -2, "used_bytes");
    lua_pushnumber(L, (lua_Number)used_percent);
    lua_setfield(L, -2, "used_percent");

    return 1;
#else
    lua_pushnil(L);
    lua_pushstring(L, "statvfs is not supported on this platform");
    return 2;
#endif
}

static int utils_can_bind(lua_State *L)
{
#ifndef _WIN32
    const char *host = luaL_optstring(L, 1, "0.0.0.0");
    const int port = luaL_checkinteger(L, 2);
    if(port < 0 || port > 65535)
    {
        lua_pushboolean(L, 0);
        lua_pushstring(L, "invalid port");
        return 2;
    }

    if(!host || host[0] == '\0')
        host = NULL;

    char port_str[16];
    snprintf(port_str, sizeof(port_str), "%d", port);

    struct addrinfo hints;
    memset(&hints, 0, sizeof(hints));
    hints.ai_socktype = SOCK_STREAM;
    hints.ai_family = AF_UNSPEC;
    hints.ai_flags = AI_PASSIVE;

    struct addrinfo *res = NULL;
    const int rc = getaddrinfo(host, port_str, &hints, &res);
    if(rc != 0 || !res)
    {
        lua_pushboolean(L, 0);
        lua_pushstring(L, rc != 0 ? gai_strerror(rc) : "getaddrinfo failed");
        return 2;
    }

    int last_errno = 0;
    for(struct addrinfo *p = res; p; p = p->ai_next)
    {
        const int fd = socket(p->ai_family, p->ai_socktype, p->ai_protocol);
        if(fd < 0)
        {
            last_errno = errno;
            continue;
        }

        int yes = 1;
        setsockopt(fd, SOL_SOCKET, SO_REUSEADDR, &yes, sizeof(yes));

        if(bind(fd, p->ai_addr, p->ai_addrlen) == 0)
        {
            close(fd);
            freeaddrinfo(res);
            lua_pushboolean(L, 1);
            return 1;
        }

        last_errno = errno;
        close(fd);
    }

    freeaddrinfo(res);

    lua_pushboolean(L, 0);
    lua_pushstring(L, last_errno ? strerror(last_errno) : "bind failed");
    return 2;
#else
    lua_pushboolean(L, 1);
    return 1;
#endif
}

static int utils_embedded_enabled(lua_State *L)
{
    lua_pushboolean(L, embedded_fs_enabled());
    return 1;
}

static int utils_embedded_exists(lua_State *L)
{
    const char *path = luaL_checkstring(L, 1);
    lua_pushboolean(L, embedded_fs_exists(path));
    return 1;
}

static int utils_embedded_read(lua_State *L)
{
    const char *path = luaL_checkstring(L, 1);
    const uint8_t *data = NULL;
    size_t size = 0;
    if(!embedded_fs_get(path, &data, &size))
    {
        lua_pushnil(L);
        return 1;
    }

    lua_pushlstring(L, (const char *)data, size);
    return 1;
}

/* readdir */

static const char __utils_readdir[] = "__utils_readdir";

static int utils_readdir_iter(lua_State *L)
{
    DIR *dirp = *(DIR **)lua_touserdata(L, lua_upvalueindex(1));
    struct dirent *entry;
    do
    {
        entry = readdir(dirp);
    } while(entry && entry->d_name[0] == '.');

    if(!entry)
        return 0;

    lua_pushstring(L, entry->d_name);
    return 1;
}

static int utils_readdir_init(lua_State *L)
{
    const char *path = luaL_checkstring(L, 1);
    DIR *dirp = opendir(path);
    if(!dirp)
        luaL_error(L, "cannot open %s: %s", path, strerror(errno));

    DIR **d = (DIR **)lua_newuserdata(L, sizeof(DIR *));
    *d = dirp;

    luaL_getmetatable(L, __utils_readdir);
    lua_setmetatable(L, -2);

    lua_pushcclosure(L, utils_readdir_iter, 1);
    return 1;
}

static int utils_readder_gc(lua_State *L)
{
    DIR **dirpp = (DIR **)lua_touserdata(L, 1);
    if(*dirpp)
    {
        closedir(*dirpp);
        *dirpp = NULL;
    }
    return 0;
}

/* utils */

LUA_API int luaopen_utils(lua_State *L)
{
    static const luaL_Reg api[] =
    {
        { "hostname", utils_hostname },
#ifdef HAVE_GETIFADDRS
        { "ifaddrs", utils_ifaddrs },
#endif
        { "stat", utils_stat },
        { "statvfs", utils_statvfs },
        { "can_bind", utils_can_bind },
        { "embedded_enabled", utils_embedded_enabled },
        { "embedded_exists", utils_embedded_exists },
        { "embedded_read", utils_embedded_read },
        { NULL, NULL }
    };

    luaL_newlib(L, api);
    lua_pushvalue(L, -1);
    lua_setglobal(L, "utils");

    /* readdir */
    const int table = lua_gettop(L);
    luaL_newmetatable(L, __utils_readdir);
    lua_pushcfunction(L, utils_readder_gc);
    lua_setfield(L, -2, "__gc");
    lua_pop(L, 1); // metatable
    lua_pushcfunction(L, utils_readdir_init);
    lua_setfield(L, table, "readdir");
    lua_pop(L, 1); // table

    return 0;
}
