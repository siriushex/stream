/* Clean-room stub: srt_input C module interface (not wired to runtime). */

#include <lua.h>
#include <lauxlib.h>

static int srt_input_new(lua_State *L)
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

static const luaL_Reg srt_input_lib[] = {
    { "new", srt_input_new },
    { NULL, NULL },
};

int luaopen_srt_input(lua_State *L)
{
    luaL_newlib(L, srt_input_lib);
    return 1;
}
