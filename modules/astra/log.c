/*
 * Astra Module: Log
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
 * Set of the logging methods for lua
 *
 * Methods:
 *      log.set({ options })
 *                  - set logging options:
 *                    debug     - boolean, allow debug messages, false by default
 *                    level     - string, error|warning|info|debug
 *                    filename  - string, writing log to a file
 *                    rotate_max_bytes - number, rotate when file exceeds this size
 *                    rotate_keep - number, keep N rotated files (<file>.1 .. <file>.N)
 *                    syslog    - string, sending log to the syslog,
 *                                is not available under the windows
 *                    stdout    - boolean, writing log to the stdout, true by default
 *      log.get()
 *                  - get current log options (best-effort snapshot)
 *      log.error(message)
 *                  - error message
 *      log.warning(message)
 *                  - warning message
 *      log.info(message)
 *                  - information message
 *      log.debug(message)
 *                  - debug message
 */

#include <astra.h>

static bool is_debug = false;
static size_t rotate_max_bytes = 0;
static int rotate_keep = 0;
static bool opt_stdout = true;
static bool opt_color = false;
static int opt_level = ASC_LOG_LEVEL_INFO;
static char *opt_filename = NULL;
#ifndef _WIN32
static char *opt_syslog = NULL;
#endif

static const char * _level_to_str(int level)
{
    switch(level)
    {
        case ASC_LOG_LEVEL_ERROR: return "error";
        case ASC_LOG_LEVEL_WARNING: return "warning";
        case ASC_LOG_LEVEL_DEBUG: return "debug";
        case ASC_LOG_LEVEL_INFO:
        default: return "info";
    }
}

static int lua_log_set(lua_State *L)
{
    luaL_checktype(L, 1, LUA_TTABLE);

    // store in registry to prevent the gc cleaning
    lua_pushstring(L, "astra.log");
    lua_pushvalue(L, 1);
    lua_settable(L, LUA_REGISTRYINDEX);


    for(lua_pushnil(L); lua_next(L, 1); lua_pop(L, 1))
    {
        const char *var = lua_tostring(L, -2);

        if(!strcmp(var, "debug"))
        {
            luaL_checktype(L, -1, LUA_TBOOLEAN);
            is_debug = lua_toboolean(L, -1);
            asc_log_set_debug(is_debug);
            if(is_debug)
                opt_level = ASC_LOG_LEVEL_DEBUG;
            else if(opt_level == ASC_LOG_LEVEL_DEBUG)
                opt_level = ASC_LOG_LEVEL_INFO;

            lua_pushvalue(lua, -1);
            lua_setglobal(lua, "debug");
        }
        else if(!strcmp(var, "level"))
        {
            int level = ASC_LOG_LEVEL_INFO;
            if(lua_type(L, -1) == LUA_TNUMBER)
            {
                level = (int)lua_tointeger(L, -1);
            }
            else
            {
                const char *val = luaL_checkstring(L, -1);
                if(!strcasecmp(val, "error")) level = ASC_LOG_LEVEL_ERROR;
                else if(!strcasecmp(val, "warning")) level = ASC_LOG_LEVEL_WARNING;
                else if(!strcasecmp(val, "info")) level = ASC_LOG_LEVEL_INFO;
                else if(!strcasecmp(val, "debug")) level = ASC_LOG_LEVEL_DEBUG;
            }
            asc_log_set_level(level);
            opt_level = level;
            is_debug = asc_log_is_debug();
            lua_pushboolean(lua, is_debug);
            lua_setglobal(lua, "debug");
        }
        else if(!strcmp(var, "filename"))
        {
            const char *val = luaL_checkstring(L, -1);
            asc_log_set_file((*val != '\0') ? val : NULL);
            if(opt_filename)
            {
                free(opt_filename);
                opt_filename = NULL;
            }
            if(*val != '\0')
                opt_filename = strdup(val);
        }
        else if(!strcmp(var, "rotate_max_bytes"))
        {
            const lua_Integer val = luaL_checkinteger(L, -1);
            rotate_max_bytes = (val > 0) ? (size_t)val : 0;
            asc_log_set_rotate(rotate_max_bytes, rotate_keep);
        }
        else if(!strcmp(var, "rotate_keep"))
        {
            const lua_Integer val = luaL_checkinteger(L, -1);
            rotate_keep = (val > 0) ? (int)val : 0;
            asc_log_set_rotate(rotate_max_bytes, rotate_keep);
        }
#ifndef _WIN32
        else if(!strcmp(var, "syslog"))
        {
            const char *val = luaL_checkstring(L, -1);
            asc_log_set_syslog((*val != '\0') ? val : NULL);
            if(opt_syslog)
            {
                free(opt_syslog);
                opt_syslog = NULL;
            }
            if(*val != '\0')
                opt_syslog = strdup(val);
        }
#endif
        else if(!strcmp(var, "stdout"))
        {
            luaL_checktype(L, -1, LUA_TBOOLEAN);
            opt_stdout = lua_toboolean(L, -1);
            asc_log_set_stdout(opt_stdout);
        }
        else if(!strcmp(var, "color"))
        {
            luaL_checktype(L, -1, LUA_TBOOLEAN);
            opt_color = lua_toboolean(L, -1);
            asc_log_set_color(opt_color);
        }
    }

    return 0;
}

static int lua_log_get(lua_State *L)
{
    lua_newtable(L);

    lua_pushboolean(L, opt_stdout);
    lua_setfield(L, -2, "stdout");

    lua_pushboolean(L, opt_color);
    lua_setfield(L, -2, "color");

    lua_pushboolean(L, opt_level >= ASC_LOG_LEVEL_DEBUG);
    lua_setfield(L, -2, "debug");

    lua_pushstring(L, _level_to_str(opt_level));
    lua_setfield(L, -2, "level");

    lua_pushstring(L, opt_filename ? opt_filename : "");
    lua_setfield(L, -2, "filename");

#ifndef _WIN32
    lua_pushstring(L, opt_syslog ? opt_syslog : "");
    lua_setfield(L, -2, "syslog");
#endif

    lua_pushinteger(L, (lua_Integer)rotate_max_bytes);
    lua_setfield(L, -2, "rotate_max_bytes");

    lua_pushinteger(L, (lua_Integer)rotate_keep);
    lua_setfield(L, -2, "rotate_keep");

    return 1;
}

static int lua_log_error(lua_State *L)
{
    asc_log_error("%s", luaL_checkstring(L, 1));
    return 0;
}

static int lua_log_warning(lua_State *L)
{
    asc_log_warning("%s", luaL_checkstring(L, 1));
    return 0;
}

static int lua_log_info(lua_State *L)
{
    asc_log_info("%s", luaL_checkstring(L, 1));
    return 0;
}

static int lua_log_debug(lua_State *L)
{
    if(is_debug)
        asc_log_debug("%s", luaL_checkstring(L, 1));
    return 0;
}

LUA_API int luaopen_log(lua_State *L)
{
    is_debug = asc_log_is_debug();
    opt_level = is_debug ? ASC_LOG_LEVEL_DEBUG : ASC_LOG_LEVEL_INFO;

    static const luaL_Reg api[] =
    {
        { "set", lua_log_set },
        { "get", lua_log_get },
        { "error", lua_log_error },
        { "warning", lua_log_warning },
        { "info", lua_log_info },
        { "debug", lua_log_debug },
        { NULL, NULL }
    };

    luaL_newlib(L, api);
    lua_setglobal(L, "log");

    return 0;
}
