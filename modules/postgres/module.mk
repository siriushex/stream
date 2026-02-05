SOURCES="postgres.c"
MODULES="postgres"
LDFLAGS="-lpq"

check_postgres()
{
    $APP_C $APP_CFLAGS $1 -x c -o /dev/null -c $MODULE/postgres.c >/dev/null 2>&1
}

check_pkgconfig()
{
    command -v pkg-config >/dev/null 2>&1
}

check_pg_config()
{
    command -v pg_config >/dev/null 2>&1
}

postgres_configure()
{
    if check_postgres "" ; then
        return 0
    fi

    if check_pkgconfig ; then
        CFLAGS="$(pkg-config --cflags libpq 2>/dev/null)"
        LDFLAGS="$(pkg-config --libs libpq 2>/dev/null)"
        if [ -n "$CFLAGS" ] && check_postgres "$CFLAGS" ; then
            return 0
        fi
    fi

    if check_pg_config ; then
        CFLAGS="$(pg_config --includedir 2>/dev/null)"
        LDFLAGS="$(pg_config --libdir 2>/dev/null)"
        if [ -n "$CFLAGS" ] && [ -n "$LDFLAGS" ] ; then
            CFLAGS="-I$CFLAGS"
            LDFLAGS="-L$LDFLAGS -lpq"
            if check_postgres "$CFLAGS" ; then
                return 0
            fi
        fi
    fi

    return 1
}

if ! postgres_configure ; then
    ERROR="PostgreSQL or libpq not found (install libpq dev libs or configure pkg-config/pg_config)"
fi
