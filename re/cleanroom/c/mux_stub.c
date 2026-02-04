/* Clean-room stub: mux C module interface (not wired to runtime). */

#include <lua.h>
#include <lauxlib.h>

static int mux_new(lua_State *L)
{
    if (!lua_istable(L, 1))
    {
        return luaL_error(L, "opts table required");
    }

    lua_newtable(L);
    lua_pushstring(L, "not implemented");
    lua_setfield(L, -2, "status");
    return 1;
}

static const luaL_Reg mux_lib[] = {
    { "new", mux_new },
    { NULL, NULL },
};

int luaopen_mux(lua_State *L)
{
    luaL_newlib(L, mux_lib);
    return 1;
}
