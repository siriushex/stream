SOURCES="sqlite.c"
MODULES="sqlite"
LDFLAGS="-lsqlite3"

check_sqlite()
{
    cat <<'EOC' | $APP_C $APP_CFLAGS -x c - -o /dev/null -lsqlite3 >/dev/null 2>&1
#include <sqlite3.h>
int main(void)
{
    sqlite3 *db = 0;
    sqlite3_open(":memory:", &db);
    sqlite3_close(db);
    return 0;
}
EOC
}

if ! check_sqlite ; then
    ERROR="sqlite3 not found"
fi
