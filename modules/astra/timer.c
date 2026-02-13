/*
 * Astra Module: Timer
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
 *      timer
 *
 * Module Options:
 *      interval    - number|string, sets the interval between triggers, in seconds (can be fractional)
 *      callback    - function, handler is called when the timer is triggered
 */

#include <astra.h>

struct module_data_t
{
    int idx_self;
    int idx_callback;

    asc_timer_t *timer;
};

static int method_close(module_data_t *mod);

static void timer_callback(void *arg)
{
    module_data_t *mod = (module_data_t *)arg;
    lua_rawgeti(lua, LUA_REGISTRYINDEX, mod->idx_callback);
    lua_rawgeti(lua, LUA_REGISTRYINDEX, mod->idx_self);
    if(lua_pcall(lua, 1, 0, 0) != 0)
    {
        const char *msg = lua_tostring(lua, -1);
        asc_log_error("[timer] callback error: %s", msg ? msg : "unknown");
        lua_pop(lua, 1);
        method_close(mod);
    }
}

static int method_close(module_data_t *mod)
{
    if(mod->idx_callback)
    {
        luaL_unref(lua, LUA_REGISTRYINDEX, mod->idx_callback);
        mod->idx_callback = 0;
    }

    if(mod->idx_self)
    {
        luaL_unref(lua, LUA_REGISTRYINDEX, mod->idx_self);
        mod->idx_self = 0;
    }

    if(mod->timer)
    {
        asc_timer_destroy(mod->timer);
        mod->timer = NULL;
    }

    return 0;
}

static void module_init(module_data_t *mod)
{
    /*
     * Важно: в Lua-коде используются дробные интервалы (например 0.2/0.5 секунды)
     * для быстрых retry/poll циклов. module_option_number() читает int и режет "0.2" -> 0,
     * что приводило к assert/abort процесса. Читаем как lua_Number и конвертируем в ms.
     */
    double interval_sec = 0.0;
    if(lua_type(lua, MODULE_OPTIONS_IDX) == LUA_TTABLE)
    {
        lua_getfield(lua, MODULE_OPTIONS_IDX, "interval");
        const int t = lua_type(lua, -1);
        if(t == LUA_TNUMBER)
        {
            interval_sec = lua_tonumber(lua, -1);
        }
        else if(t == LUA_TSTRING)
        {
            const char *s = lua_tostring(lua, -1);
            if(s && *s)
                interval_sec = strtod(s, NULL);
        }
        else if(t == LUA_TBOOLEAN)
        {
            interval_sec = lua_toboolean(lua, -1) ? 1.0 : 0.0;
        }
        lua_pop(lua, 1);
    }

    const int interval_ms = (int)(interval_sec * 1000.0 + 0.5);
    asc_assert(interval_ms > 0, "[timer] option 'interval' must be greater than 0");

    lua_getfield(lua, MODULE_OPTIONS_IDX, "callback");
    asc_assert(lua_isfunction(lua, -1), "[timer] option 'callback' is required");
    mod->idx_callback = luaL_ref(lua, LUA_REGISTRYINDEX);

    // store self in registry
    lua_pushvalue(lua, 3);
    mod->idx_self = luaL_ref(lua, LUA_REGISTRYINDEX);

    mod->timer = asc_timer_init(interval_ms, timer_callback, mod);
}

static void module_destroy(module_data_t *mod)
{
    if(mod->idx_self)
        method_close(mod);
}

MODULE_LUA_METHODS()
{
    { "close", method_close }
};
MODULE_LUA_REGISTER(timer)
