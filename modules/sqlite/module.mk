SOURCES="sqlite.c sqlite3.c"
MODULES="sqlite"

# Bundled SQLite (amalgamation) to guarantee modern features (UPSERT/WAL) on older distros.
# This avoids runtime dependency on libsqlite3 and improves stability/perf on CentOS 7.
CFLAGS="-DSQLITE_THREADSAFE=1 -DSQLITE_OMIT_LOAD_EXTENSION"
