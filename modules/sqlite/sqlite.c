/*
 * Astra Module: SQLite
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
#include <sqlite3.h>

#define SQLITE_DB_MT "sqlite.db"

typedef struct
{
    sqlite3 *db;
} sqlite_db_t;

static sqlite_db_t *check_db(lua_State *L)
{
    return (sqlite_db_t *)luaL_checkudata(L, 1, SQLITE_DB_MT);
}

static int db_close(lua_State *L)
{
    sqlite_db_t *db = check_db(L);
    if(db->db)
    {
        sqlite3_close(db->db);
        db->db = NULL;
    }
    lua_pushboolean(L, true);
    return 1;
}

static int db_exec(lua_State *L)
{
    sqlite_db_t *db = check_db(L);
    const char *sql = luaL_checkstring(L, 2);
    char *errmsg = NULL;

    const int rc = sqlite3_exec(db->db, sql, NULL, NULL, &errmsg);
    if(rc == SQLITE_OK)
    {
        lua_pushboolean(L, true);
        return 1;
    }

    lua_pushboolean(L, false);
    if(errmsg)
    {
        lua_pushstring(L, errmsg);
        sqlite3_free(errmsg);
    }
    else
    {
        lua_pushstring(L, sqlite3_errmsg(db->db));
    }

    return 2;
}

static void push_value(lua_State *L, sqlite3_stmt *stmt, int col)
{
    switch(sqlite3_column_type(stmt, col))
    {
        case SQLITE_INTEGER:
            lua_pushinteger(L, sqlite3_column_int64(stmt, col));
            break;
        case SQLITE_FLOAT:
            lua_pushnumber(L, sqlite3_column_double(stmt, col));
            break;
        case SQLITE_TEXT:
            lua_pushstring(L, (const char *)sqlite3_column_text(stmt, col));
            break;
        case SQLITE_NULL:
            lua_pushnil(L);
            break;
        case SQLITE_BLOB:
        default:
        {
            const void *blob = sqlite3_column_blob(stmt, col);
            const int size = sqlite3_column_bytes(stmt, col);
            lua_pushlstring(L, (const char *)blob, size);
            break;
        }
    }
}

static int db_query(lua_State *L)
{
    sqlite_db_t *db = check_db(L);
    const char *sql = luaL_checkstring(L, 2);

    sqlite3_stmt *stmt = NULL;
    if(sqlite3_prepare_v2(db->db, sql, -1, &stmt, NULL) != SQLITE_OK)
    {
        lua_pushnil(L);
        lua_pushstring(L, sqlite3_errmsg(db->db));
        return 2;
    }

    const int col_count = sqlite3_column_count(stmt);
    lua_newtable(L);
    int row_idx = 0;

    int rc = SQLITE_ROW;
    while((rc = sqlite3_step(stmt)) == SQLITE_ROW)
    {
        lua_newtable(L);
        for(int i = 0; i < col_count; ++i)
        {
            const char *name = sqlite3_column_name(stmt, i);
            push_value(L, stmt, i);
            lua_setfield(L, -2, name);
        }
        lua_rawseti(L, -2, ++row_idx);
    }

    sqlite3_finalize(stmt);

    if(rc != SQLITE_DONE)
    {
        lua_pushnil(L);
        lua_pushstring(L, sqlite3_errmsg(db->db));
        return 2;
    }

    return 1;
}

static int sqlite_open(lua_State *L)
{
    const char *path = luaL_checkstring(L, 1);

    sqlite_db_t *db = (sqlite_db_t *)lua_newuserdata(L, sizeof(*db));
    db->db = NULL;

    if(sqlite3_open(path, &db->db) != SQLITE_OK)
    {
        lua_pushnil(L);
        lua_pushstring(L, sqlite3_errmsg(db->db));
        if(db->db)
        {
            sqlite3_close(db->db);
            db->db = NULL;
        }
        return 2;
    }

    luaL_getmetatable(L, SQLITE_DB_MT);
    lua_setmetatable(L, -2);

    return 1;
}

LUA_API int luaopen_sqlite(lua_State *L)
{
    luaL_newmetatable(L, SQLITE_DB_MT);

    lua_newtable(L);
    lua_pushcfunction(L, db_exec);
    lua_setfield(L, -2, "exec");
    lua_pushcfunction(L, db_query);
    lua_setfield(L, -2, "query");
    lua_pushcfunction(L, db_close);
    lua_setfield(L, -2, "close");
    lua_setfield(L, -2, "__index");

    lua_pushcfunction(L, db_close);
    lua_setfield(L, -2, "__gc");

    lua_pop(L, 1); // metatable

    lua_newtable(L);
    lua_pushcfunction(L, sqlite_open);
    lua_setfield(L, -2, "open");
    lua_setglobal(L, "sqlite");

    return 0;
}
