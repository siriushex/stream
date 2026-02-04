/* Clean-room stub: http_server C module interface (not wired to runtime). */

#include <lua.h>
#include <lauxlib.h>

static int http_server_new(lua_State *L)
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

static const luaL_Reg http_server_lib[] = {
    { "new", http_server_new },
    { NULL, NULL },
};

int luaopen_http_server(lua_State *L)
{
    luaL_newlib(L, http_server_lib);
    return 1;
}
