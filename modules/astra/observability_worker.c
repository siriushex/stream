/*
 * Stream Module: observability_worker
 * Dedicated writer thread for Observability metrics.
 */

#include <astra.h>

#ifndef _WIN32

#include <errno.h>
#include <pthread.h>
#include <stdlib.h>
#include <string.h>
#include <sys/time.h>
#include <time.h>
#include <unistd.h>
#ifdef __linux__
#include <sched.h>
#endif

#include "../sqlite/sqlite3.h"

#define OBS_WORKER_MSG "[observability_worker]"
#if defined(__linux__)
#define OBS_WORKER_HAS_AFFINITY 1
#else
#define OBS_WORKER_HAS_AFFINITY 0
#endif

typedef struct obs_metric_row_t
{
    long long ts_bucket;
    int resolution_sec;
    double value;
    int mode; /* 0=replace, 1=sum, 2=max */
    char *scope;
    char *scope_id;
    char *metric_key;
    char *tags_json;
    struct obs_metric_row_t *next;
} obs_metric_row_t;

typedef struct
{
    pthread_t thread;
    pthread_mutex_t mutex;
    pthread_cond_t cv;
    bool running;
    bool stop_requested;
    bool thread_started;
    bool affinity_mask_valid;
#if OBS_WORKER_HAS_AFFINITY
    cpu_set_t affinity_mask;
#endif
    char affinity_text[128];
    char db_path[1024];

    int batch_max;
    int flush_ms;
    int queue_max;
    int queue_depth;

    obs_metric_row_t *queue_head;
    obs_metric_row_t *queue_tail;

    sqlite3 *db;
    sqlite3_stmt *stmt_metric_upsert;

    unsigned long long rows_written;
    unsigned long long rows_dropped;
    unsigned long long db_busy_count;
    int last_flush_ms;
    char last_error[256];
} obs_worker_state_t;

static obs_worker_state_t g_worker = {0};
static bool g_worker_sync_ready = false;

static int clamp_int(int value, int min_value, int max_value)
{
    if(value < min_value)
        return min_value;
    if(value > max_value)
        return max_value;
    return value;
}

static long long now_ms(void)
{
    struct timeval tv;
    gettimeofday(&tv, NULL);
    return ((long long)tv.tv_sec * 1000LL) + (long long)(tv.tv_usec / 1000);
}

static void set_last_error(obs_worker_state_t *w, const char *text)
{
    if(!w)
        return;
    if(!text)
        text = "";
    snprintf(w->last_error, sizeof(w->last_error), "%s", text);
}

static void clear_last_error(obs_worker_state_t *w)
{
    if(!w)
        return;
    w->last_error[0] = '\0';
}

static void free_metric_row(obs_metric_row_t *row)
{
    if(!row)
        return;
    free(row->scope);
    free(row->scope_id);
    free(row->metric_key);
    free(row->tags_json);
    free(row);
}

static void free_metric_list(obs_metric_row_t *head)
{
    while(head)
    {
        obs_metric_row_t *next = head->next;
        free_metric_row(head);
        head = next;
    }
}

static void queue_push_locked(obs_worker_state_t *w, obs_metric_row_t *row)
{
    if(!w || !row)
        return;
    row->next = NULL;
    if(!w->queue_tail)
    {
        w->queue_head = row;
        w->queue_tail = row;
    }
    else
    {
        w->queue_tail->next = row;
        w->queue_tail = row;
    }
    w->queue_depth++;
}

static obs_metric_row_t *queue_pop_batch_locked(obs_worker_state_t *w, int max_rows, int *out_count)
{
    if(out_count)
        *out_count = 0;
    if(!w || max_rows <= 0 || !w->queue_head)
        return NULL;

    obs_metric_row_t *head = w->queue_head;
    obs_metric_row_t *tail = head;
    int count = 1;
    while(count < max_rows && tail->next)
    {
        tail = tail->next;
        count++;
    }

    w->queue_head = tail->next;
    if(!w->queue_head)
        w->queue_tail = NULL;
    tail->next = NULL;
    w->queue_depth -= count;
    if(w->queue_depth < 0)
        w->queue_depth = 0;
    if(out_count)
        *out_count = count;
    return head;
}

static void queue_clear_locked(obs_worker_state_t *w)
{
    if(!w)
        return;
    obs_metric_row_t *head = w->queue_head;
    w->queue_head = NULL;
    w->queue_tail = NULL;
    w->queue_depth = 0;
    free_metric_list(head);
}

/* CPU affinity helpers are Linux-only. */
#if OBS_WORKER_HAS_AFFINITY
static int detect_allowed_cpus(int *out, int out_cap)
{
    if(!out || out_cap <= 0)
        return 0;
    cpu_set_t set;
    CPU_ZERO(&set);
    if(sched_getaffinity(0, sizeof(set), &set) != 0)
        return 0;

    int n = 0;
    for(int cpu = 0; cpu < CPU_SETSIZE && n < out_cap; ++cpu)
    {
        if(CPU_ISSET(cpu, &set))
            out[n++] = cpu;
    }
    return n;
}

static bool parse_cpu_set_text(const char *text, void *mask_ptr, char *desc, size_t desc_len)
{
    cpu_set_t *mask = (cpu_set_t *)mask_ptr;
    if(!text || !*text || !mask)
        return false;

    CPU_ZERO(mask);
    int added = 0;
    char buf[256];
    snprintf(buf, sizeof(buf), "%s", text);

    char *saveptr = NULL;
    char *token = strtok_r(buf, ",", &saveptr);
    while(token)
    {
        while(*token == ' ' || *token == '\t')
            token++;
        char *end = token + strlen(token);
        while(end > token && (end[-1] == ' ' || end[-1] == '\t'))
        {
            end[-1] = '\0';
            end--;
        }
        if(*token)
        {
            const int cpu = atoi(token);
            if(cpu >= 0 && cpu < CPU_SETSIZE)
            {
                CPU_SET(cpu, mask);
                added++;
            }
        }
        token = strtok_r(NULL, ",", &saveptr);
    }

    if(added <= 0)
        return false;
    if(desc && desc_len > 0)
        snprintf(desc, desc_len, "manual:%s", text);
    return true;
}

static bool build_auto_affinity_mask(int auto_cores, void *mask_ptr, char *desc, size_t desc_len)
{
    cpu_set_t *mask = (cpu_set_t *)mask_ptr;
    if(!mask)
        return false;
    int allowed[CPU_SETSIZE];
    const int allowed_n = detect_allowed_cpus(allowed, (int)(sizeof(allowed) / sizeof(allowed[0])));
    if(allowed_n <= 2)
    {
        /* For <=2 cores we do not force pinning. */
        return false;
    }

    int need = clamp_int(auto_cores, 1, 8);
    if(need > allowed_n)
        need = allowed_n;

    CPU_ZERO(mask);
    for(int i = 0; i < need; ++i)
    {
        const int cpu = allowed[allowed_n - 1 - i];
        CPU_SET(cpu, mask);
    }
    if(desc && desc_len > 0)
        snprintf(desc, desc_len, "auto:last-%d", need);
    return true;
}
#endif

static void apply_thread_affinity(obs_worker_state_t *w)
{
#if OBS_WORKER_HAS_AFFINITY
    if(!w || !w->affinity_mask_valid)
        return;
    const int rc = pthread_setaffinity_np(pthread_self(), sizeof(cpu_set_t), &w->affinity_mask);
    if(rc != 0)
    {
        char msg[256];
        snprintf(msg, sizeof(msg), "setaffinity failed: %s", strerror(rc));
        pthread_mutex_lock(&w->mutex);
        set_last_error(w, msg);
        pthread_mutex_unlock(&w->mutex);
        asc_log_warning("%s %s", OBS_WORKER_MSG, msg);
        return;
    }
    asc_log_info("%s thread affinity=%s", OBS_WORKER_MSG, w->affinity_text);
#else
    __uarg(w);
#endif
}

static bool sqlite_exec_ok(sqlite3 *db, const char *sql, char *errbuf, size_t errbuf_len)
{
    if(!db || !sql)
        return false;
    char *errmsg = NULL;
    const int rc = sqlite3_exec(db, sql, NULL, NULL, &errmsg);
    if(rc == SQLITE_OK)
        return true;
    if(errbuf && errbuf_len > 0)
    {
        snprintf(errbuf, errbuf_len, "sqlite exec error: %s", errmsg ? errmsg : sqlite3_errmsg(db));
    }
    if(errmsg)
        sqlite3_free(errmsg);
    return false;
}

static bool ensure_db_open(obs_worker_state_t *w)
{
    if(!w)
        return false;
    if(w->db)
        return true;

    int flags = SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE;
    sqlite3 *db = NULL;
    const int rc = sqlite3_open_v2(w->db_path, &db, flags, NULL);
    if(rc != SQLITE_OK || !db)
    {
        char msg[256];
        snprintf(msg, sizeof(msg), "sqlite open failed: %s", db ? sqlite3_errmsg(db) : "open error");
        if(db)
            sqlite3_close(db);
        pthread_mutex_lock(&w->mutex);
        set_last_error(w, msg);
        pthread_mutex_unlock(&w->mutex);
        return false;
    }

    sqlite_exec_ok(db, "PRAGMA journal_mode=WAL;", NULL, 0);
    sqlite_exec_ok(db, "PRAGMA synchronous=NORMAL;", NULL, 0);
    sqlite_exec_ok(db, "PRAGMA busy_timeout=3000;", NULL, 0);
    sqlite_exec_ok(db,
        "CREATE TABLE IF NOT EXISTS ai_metrics_rollup ("
        "id INTEGER PRIMARY KEY AUTOINCREMENT,"
        "ts_bucket INTEGER NOT NULL,"
        "scope TEXT NOT NULL,"
        "scope_id TEXT,"
        "metric_key TEXT NOT NULL,"
        "resolution_sec INTEGER NOT NULL DEFAULT 60,"
        "value REAL NOT NULL,"
        "tags_json TEXT"
        ");",
        NULL, 0);
    sqlite_exec_ok(db,
        "CREATE UNIQUE INDEX IF NOT EXISTS ai_metrics_rollup_unique2 "
        "ON ai_metrics_rollup(ts_bucket, scope, scope_id, metric_key, resolution_sec);",
        NULL, 0);
    sqlite_exec_ok(db,
        "CREATE INDEX IF NOT EXISTS ai_metrics_rollup_scope_metric_ts_res_idx "
        "ON ai_metrics_rollup(scope, scope_id, metric_key, ts_bucket, resolution_sec);",
        NULL, 0);

    const char *upsert_sql =
        "INSERT INTO ai_metrics_rollup(ts_bucket, scope, scope_id, metric_key, resolution_sec, value, tags_json) "
        "VALUES(?, ?, ?, ?, ?, ?, ?) "
        "ON CONFLICT(ts_bucket, scope, scope_id, metric_key, resolution_sec) DO UPDATE SET "
        "value = CASE ?8 "
        "WHEN 1 THEN ai_metrics_rollup.value + excluded.value "
        "WHEN 2 THEN MAX(ai_metrics_rollup.value, excluded.value) "
        "ELSE excluded.value END, "
        "tags_json = excluded.tags_json;";
    sqlite3_stmt *stmt = NULL;
    if(sqlite3_prepare_v2(db, upsert_sql, -1, &stmt, NULL) != SQLITE_OK || !stmt)
    {
        char msg[256];
        snprintf(msg, sizeof(msg), "sqlite prepare failed: %s", sqlite3_errmsg(db));
        sqlite3_close(db);
        pthread_mutex_lock(&w->mutex);
        set_last_error(w, msg);
        pthread_mutex_unlock(&w->mutex);
        return false;
    }

    w->db = db;
    w->stmt_metric_upsert = stmt;
    pthread_mutex_lock(&w->mutex);
    clear_last_error(w);
    pthread_mutex_unlock(&w->mutex);
    return true;
}

static void close_db(obs_worker_state_t *w)
{
    if(!w)
        return;
    if(w->stmt_metric_upsert)
    {
        sqlite3_finalize(w->stmt_metric_upsert);
        w->stmt_metric_upsert = NULL;
    }
    if(w->db)
    {
        sqlite3_close(w->db);
        w->db = NULL;
    }
}

static bool flush_metrics(obs_worker_state_t *w, obs_metric_row_t *rows, int count, int *out_busy, int *out_elapsed_ms)
{
    if(out_busy)
        *out_busy = 0;
    if(out_elapsed_ms)
        *out_elapsed_ms = 0;
    if(!w || !rows || count <= 0)
        return true;
    if(!ensure_db_open(w))
        return false;

    const long long started = now_ms();
    int rc = sqlite3_exec(w->db, "BEGIN IMMEDIATE;", NULL, NULL, NULL);
    if(rc != SQLITE_OK)
    {
        if(rc == SQLITE_BUSY || rc == SQLITE_LOCKED)
        {
            if(out_busy) *out_busy = 1;
        }
        return false;
    }

    bool ok = true;
    obs_metric_row_t *node = rows;
    while(node)
    {
        sqlite3_reset(w->stmt_metric_upsert);
        sqlite3_clear_bindings(w->stmt_metric_upsert);

        sqlite3_bind_int64(w->stmt_metric_upsert, 1, (sqlite3_int64)node->ts_bucket);
        sqlite3_bind_text(w->stmt_metric_upsert, 2, node->scope ? node->scope : "", -1, SQLITE_TRANSIENT);
        sqlite3_bind_text(w->stmt_metric_upsert, 3, node->scope_id ? node->scope_id : "", -1, SQLITE_TRANSIENT);
        sqlite3_bind_text(w->stmt_metric_upsert, 4, node->metric_key ? node->metric_key : "", -1, SQLITE_TRANSIENT);
        sqlite3_bind_int(w->stmt_metric_upsert, 5, node->resolution_sec);
        sqlite3_bind_double(w->stmt_metric_upsert, 6, node->value);
        sqlite3_bind_text(w->stmt_metric_upsert, 7, node->tags_json ? node->tags_json : "", -1, SQLITE_TRANSIENT);
        sqlite3_bind_int(w->stmt_metric_upsert, 8, node->mode);

        rc = sqlite3_step(w->stmt_metric_upsert);
        if(rc != SQLITE_DONE)
        {
            if(rc == SQLITE_BUSY || rc == SQLITE_LOCKED)
            {
                if(out_busy) *out_busy = 1;
            }
            ok = false;
            break;
        }
        node = node->next;
    }

    if(ok)
        sqlite3_exec(w->db, "COMMIT;", NULL, NULL, NULL);
    else
        sqlite3_exec(w->db, "ROLLBACK;", NULL, NULL, NULL);

    if(out_elapsed_ms)
        *out_elapsed_ms = (int)(now_ms() - started);
    return ok;
}

static void *worker_thread_loop(void *arg)
{
    obs_worker_state_t *w = (obs_worker_state_t *)arg;
    if(!w)
        return NULL;

    apply_thread_affinity(w);

    pthread_mutex_lock(&w->mutex);
    w->thread_started = true;
    pthread_mutex_unlock(&w->mutex);

    for(;;)
    {
        int batch_size = 0;
        obs_metric_row_t *batch = NULL;

        pthread_mutex_lock(&w->mutex);
        while(!w->stop_requested && w->queue_depth == 0)
        {
            struct timespec ts;
            clock_gettime(CLOCK_REALTIME, &ts);
            long add_ns = (long)w->flush_ms * 1000000L;
            ts.tv_sec += add_ns / 1000000000L;
            ts.tv_nsec += add_ns % 1000000000L;
            if(ts.tv_nsec >= 1000000000L)
            {
                ts.tv_sec += 1;
                ts.tv_nsec -= 1000000000L;
            }
            pthread_cond_timedwait(&w->cv, &w->mutex, &ts);
            if(w->queue_depth > 0)
                break;
        }
        if(w->stop_requested && w->queue_depth == 0)
        {
            pthread_mutex_unlock(&w->mutex);
            break;
        }
        batch = queue_pop_batch_locked(w, w->batch_max, &batch_size);
        pthread_mutex_unlock(&w->mutex);

        if(!batch || batch_size <= 0)
            continue;

        int was_busy = 0;
        int flush_ms = 0;
        const bool ok = flush_metrics(w, batch, batch_size, &was_busy, &flush_ms);

        pthread_mutex_lock(&w->mutex);
        w->last_flush_ms = flush_ms;
        if(ok)
        {
            w->rows_written += (unsigned long long)batch_size;
            clear_last_error(w);
        }
        else
        {
            w->rows_dropped += (unsigned long long)batch_size;
            if(was_busy)
                w->db_busy_count++;
            set_last_error(w, "metric flush failed");
        }
        pthread_mutex_unlock(&w->mutex);

        free_metric_list(batch);
    }

    close_db(w);
    return NULL;
}

static int parse_mode(const char *mode)
{
    if(!mode || !*mode)
        return 0;
    if(strcmp(mode, "sum") == 0)
        return 1;
    if(strcmp(mode, "max") == 0)
        return 2;
    return 0;
}

static obs_metric_row_t *parse_row_from_lua(lua_State *L, int idx)
{
    if(lua_type(L, idx) != LUA_TTABLE)
        return NULL;

    obs_metric_row_t *row = (obs_metric_row_t *)calloc(1, sizeof(obs_metric_row_t));
    if(!row)
        return NULL;

    lua_getfield(L, idx, "ts_bucket");
    row->ts_bucket = (long long)luaL_optinteger(L, -1, 0);
    lua_pop(L, 1);

    lua_getfield(L, idx, "resolution_sec");
    row->resolution_sec = clamp_int((int)luaL_optinteger(L, -1, 60), 1, 3600);
    lua_pop(L, 1);

    lua_getfield(L, idx, "value");
    row->value = luaL_optnumber(L, -1, 0.0);
    lua_pop(L, 1);

    lua_getfield(L, idx, "mode");
    const char *mode = lua_tostring(L, -1);
    row->mode = parse_mode(mode);
    lua_pop(L, 1);

    lua_getfield(L, idx, "scope");
    const char *scope = lua_tostring(L, -1);
    row->scope = strdup(scope ? scope : "stream");
    lua_pop(L, 1);

    lua_getfield(L, idx, "scope_id");
    const char *scope_id = lua_tostring(L, -1);
    row->scope_id = strdup(scope_id ? scope_id : "");
    lua_pop(L, 1);

    lua_getfield(L, idx, "metric_key");
    const char *metric_key = lua_tostring(L, -1);
    row->metric_key = strdup(metric_key ? metric_key : "");
    lua_pop(L, 1);

    lua_getfield(L, idx, "tags_json");
    const char *tags_json = lua_tostring(L, -1);
    row->tags_json = strdup(tags_json ? tags_json : "");
    lua_pop(L, 1);

    if(!row->scope || !row->scope_id || !row->metric_key || !row->tags_json)
    {
        free_metric_row(row);
        return NULL;
    }
    return row;
}

static bool parse_start_options(lua_State *L, int idx, obs_worker_state_t *w, char *err, size_t err_len)
{
    if(!w || lua_type(L, idx) != LUA_TTABLE)
    {
        snprintf(err, err_len, "options table required");
        return false;
    }

    lua_getfield(L, idx, "db_path");
    const char *db_path = lua_tostring(L, -1);
    lua_pop(L, 1);
    if(!db_path || !*db_path)
    {
        snprintf(err, err_len, "db_path required");
        return false;
    }
    snprintf(w->db_path, sizeof(w->db_path), "%s", db_path);

    lua_getfield(L, idx, "batch_max");
    w->batch_max = clamp_int((int)luaL_optinteger(L, -1, 400), 1, 10000);
    lua_pop(L, 1);

    lua_getfield(L, idx, "flush_ms");
    w->flush_ms = clamp_int((int)luaL_optinteger(L, -1, 20), 1, 1000);
    lua_pop(L, 1);

    lua_getfield(L, idx, "queue_max");
    w->queue_max = clamp_int((int)luaL_optinteger(L, -1, 20000), 100, 500000);
    lua_pop(L, 1);

    lua_getfield(L, idx, "affinity_enabled");
    const bool affinity_enabled = lua_toboolean(L, -1) ? true : false;
    lua_pop(L, 1);

    w->affinity_mask_valid = false;
    w->affinity_text[0] = '\0';
    if(affinity_enabled)
    {
#if OBS_WORKER_HAS_AFFINITY
        lua_getfield(L, idx, "cpu_policy");
        const char *policy = lua_tostring(L, -1);
        lua_pop(L, 1);

        lua_getfield(L, idx, "cpu_auto_cores");
        const int auto_cores = clamp_int((int)luaL_optinteger(L, -1, 2), 1, 8);
        lua_pop(L, 1);

        lua_getfield(L, idx, "cpu_set");
        const char *cpu_set = lua_tostring(L, -1);
        lua_pop(L, 1);

        if(policy && strcmp(policy, "manual") == 0)
        {
            w->affinity_mask_valid = parse_cpu_set_text(cpu_set, &w->affinity_mask, w->affinity_text, sizeof(w->affinity_text));
        }
        else if(policy && strcmp(policy, "none") == 0)
        {
            w->affinity_mask_valid = false;
        }
        else
        {
            w->affinity_mask_valid = build_auto_affinity_mask(auto_cores, &w->affinity_mask, w->affinity_text, sizeof(w->affinity_text));
        }
#else
        if(err && err_len > 0)
            snprintf(err, err_len, "cpu affinity unsupported");
        snprintf(w->affinity_text, sizeof(w->affinity_text), "unsupported");
#endif
    }
    return true;
}

static int worker_stop(lua_State *L)
{
    __uarg(L);
    obs_worker_state_t *w = &g_worker;
    if(!g_worker_sync_ready)
    {
        lua_pushboolean(L, 1);
        return 1;
    }

    pthread_mutex_lock(&w->mutex);
    const bool was_running = w->running;
    if(w->running)
    {
        w->stop_requested = true;
        pthread_cond_signal(&w->cv);
    }
    pthread_mutex_unlock(&w->mutex);

    if(was_running)
    {
        pthread_join(w->thread, NULL);
    }

    pthread_mutex_lock(&w->mutex);
    queue_clear_locked(w);
    w->running = false;
    w->stop_requested = false;
    w->thread_started = false;
    w->last_flush_ms = 0;
    close_db(w);
    pthread_mutex_unlock(&w->mutex);

    lua_pushboolean(L, 1);
    return 1;
}

static int worker_start(lua_State *L)
{
    obs_worker_state_t *w = &g_worker;
    char err[256];

    if(lua_type(L, 1) != LUA_TTABLE)
    {
        lua_pushnil(L);
        lua_pushstring(L, "options table required");
        return 2;
    }

    /* Restart with new config if already running. */
    if(g_worker_sync_ready && w->running)
    {
        worker_stop(L);
        lua_pop(L, 1);
    }

    if(g_worker_sync_ready)
    {
        pthread_mutex_destroy(&w->mutex);
        pthread_cond_destroy(&w->cv);
        g_worker_sync_ready = false;
    }

    memset(w, 0, sizeof(*w));
    if(pthread_mutex_init(&w->mutex, NULL) != 0)
    {
        memset(w, 0, sizeof(*w));
        lua_pushnil(L);
        lua_pushstring(L, "worker mutex init failed");
        return 2;
    }
    if(pthread_cond_init(&w->cv, NULL) != 0)
    {
        pthread_mutex_destroy(&w->mutex);
        memset(w, 0, sizeof(*w));
        lua_pushnil(L);
        lua_pushstring(L, "worker condition init failed");
        return 2;
    }
    g_worker_sync_ready = true;
    w->batch_max = 400;
    w->flush_ms = 20;
    w->queue_max = 20000;

    if(!parse_start_options(L, 1, w, err, sizeof(err)))
    {
        pthread_mutex_destroy(&w->mutex);
        pthread_cond_destroy(&w->cv);
        g_worker_sync_ready = false;
        memset(w, 0, sizeof(*w));
        lua_pushnil(L);
        lua_pushstring(L, err);
        return 2;
    }

    w->running = true;
    w->stop_requested = false;
    w->rows_written = 0;
    w->rows_dropped = 0;
    w->db_busy_count = 0;
    clear_last_error(w);

    const int rc = pthread_create(&w->thread, NULL, worker_thread_loop, w);
    if(rc != 0)
    {
        char msg[256];
        snprintf(msg, sizeof(msg), "pthread_create failed: %s", strerror(rc));
        pthread_mutex_destroy(&w->mutex);
        pthread_cond_destroy(&w->cv);
        g_worker_sync_ready = false;
        memset(w, 0, sizeof(*w));
        lua_pushnil(L);
        lua_pushstring(L, msg);
        return 2;
    }

    asc_log_info("%s started: db=%s flush_ms=%d batch=%d queue=%d affinity=%s",
        OBS_WORKER_MSG, w->db_path, w->flush_ms, w->batch_max, w->queue_max,
        w->affinity_mask_valid ? w->affinity_text : "none");

    lua_pushboolean(L, 1);
    return 1;
}

static int worker_enqueue(lua_State *L)
{
    obs_worker_state_t *w = &g_worker;
    if(!g_worker_sync_ready)
    {
        lua_pushboolean(L, 0);
        lua_pushstring(L, "worker not initialized");
        return 2;
    }
    if(lua_type(L, 1) != LUA_TTABLE)
    {
        lua_pushboolean(L, 0);
        lua_pushstring(L, "row table required");
        return 2;
    }

    obs_metric_row_t *row = parse_row_from_lua(L, 1);
    if(!row)
    {
        lua_pushboolean(L, 0);
        lua_pushstring(L, "invalid row");
        return 2;
    }

    pthread_mutex_lock(&w->mutex);
    if(!w->running || w->stop_requested)
    {
        pthread_mutex_unlock(&w->mutex);
        free_metric_row(row);
        lua_pushboolean(L, 0);
        lua_pushstring(L, "worker not running");
        return 2;
    }
    if(w->queue_depth >= w->queue_max)
    {
        w->rows_dropped++;
        pthread_mutex_unlock(&w->mutex);
        free_metric_row(row);
        lua_pushboolean(L, 0);
        lua_pushstring(L, "queue full");
        return 2;
    }

    queue_push_locked(w, row);
    pthread_cond_signal(&w->cv);
    pthread_mutex_unlock(&w->mutex);
    lua_pushboolean(L, 1);
    return 1;
}

static int worker_enqueue_batch(lua_State *L)
{
    obs_worker_state_t *w = &g_worker;
    if(!g_worker_sync_ready)
    {
        lua_newtable(L);
        lua_pushinteger(L, 0);
        lua_setfield(L, -2, "accepted");
        lua_pushinteger(L, 0);
        lua_setfield(L, -2, "dropped");
        return 1;
    }
    if(lua_type(L, 1) != LUA_TTABLE)
    {
        lua_pushnil(L);
        lua_pushstring(L, "rows table required");
        return 2;
    }

    int accepted = 0;
    int dropped = 0;
    const int n = (int)luaL_len(L, 1);
    for(int i = 1; i <= n; ++i)
    {
        lua_rawgeti(L, 1, i);
        obs_metric_row_t *row = parse_row_from_lua(L, -1);
        lua_pop(L, 1);
        if(!row)
        {
            dropped++;
            continue;
        }

        bool pushed = false;
        pthread_mutex_lock(&w->mutex);
        if(w->running && !w->stop_requested && w->queue_depth < w->queue_max)
        {
            queue_push_locked(w, row);
            pthread_cond_signal(&w->cv);
            pushed = true;
        }
        else
        {
            w->rows_dropped++;
        }
        pthread_mutex_unlock(&w->mutex);

        if(pushed)
        {
            accepted++;
        }
        else
        {
            dropped++;
            free_metric_row(row);
        }
    }

    lua_newtable(L);
    lua_pushinteger(L, accepted);
    lua_setfield(L, -2, "accepted");
    lua_pushinteger(L, dropped);
    lua_setfield(L, -2, "dropped");
    return 1;
}

static int worker_status(lua_State *L)
{
    obs_worker_state_t *w = &g_worker;
    if(!g_worker_sync_ready)
    {
        lua_newtable(L);
        lua_pushboolean(L, 0);
        lua_setfield(L, -2, "running");
        lua_pushboolean(L, 0);
        lua_setfield(L, -2, "thread_started");
        lua_pushinteger(L, 0);
        lua_setfield(L, -2, "queue_depth");
        lua_pushinteger(L, 0);
        lua_setfield(L, -2, "queue_max");
        lua_pushinteger(L, 0);
        lua_setfield(L, -2, "rows_written");
        lua_pushinteger(L, 0);
        lua_setfield(L, -2, "rows_dropped");
        lua_pushinteger(L, 0);
        lua_setfield(L, -2, "db_busy_count");
        lua_pushinteger(L, 0);
        lua_setfield(L, -2, "last_flush_ms");
        lua_pushstring(L, "");
        lua_setfield(L, -2, "db_path");
        lua_pushstring(L, "");
        lua_setfield(L, -2, "affinity");
        lua_pushstring(L, "");
        lua_setfield(L, -2, "last_error");
        return 1;
    }
    pthread_mutex_lock(&w->mutex);
    lua_newtable(L);
    lua_pushboolean(L, w->running ? 1 : 0);
    lua_setfield(L, -2, "running");
    lua_pushboolean(L, w->thread_started ? 1 : 0);
    lua_setfield(L, -2, "thread_started");
    lua_pushinteger(L, w->queue_depth);
    lua_setfield(L, -2, "queue_depth");
    lua_pushinteger(L, w->queue_max);
    lua_setfield(L, -2, "queue_max");
    lua_pushinteger(L, (lua_Integer)w->rows_written);
    lua_setfield(L, -2, "rows_written");
    lua_pushinteger(L, (lua_Integer)w->rows_dropped);
    lua_setfield(L, -2, "rows_dropped");
    lua_pushinteger(L, (lua_Integer)w->db_busy_count);
    lua_setfield(L, -2, "db_busy_count");
    lua_pushinteger(L, w->last_flush_ms);
    lua_setfield(L, -2, "last_flush_ms");
    lua_pushstring(L, w->db_path);
    lua_setfield(L, -2, "db_path");
    lua_pushstring(L, w->affinity_mask_valid ? w->affinity_text : "");
    lua_setfield(L, -2, "affinity");
    lua_pushstring(L, w->last_error);
    lua_setfield(L, -2, "last_error");
    pthread_mutex_unlock(&w->mutex);
    return 1;
}

static int worker_gc(lua_State *L)
{
    __uarg(L);
    lua_pushcfunction(L, worker_stop);
    lua_call(L, 0, 1);
    lua_pop(L, 1);
    if(g_worker_sync_ready)
    {
        pthread_mutex_destroy(&g_worker.mutex);
        pthread_cond_destroy(&g_worker.cv);
        g_worker_sync_ready = false;
    }
    memset(&g_worker, 0, sizeof(g_worker));
    return 0;
}

LUA_API int luaopen_observability_worker(lua_State *L)
{
    static const luaL_Reg api[] =
    {
        { "start", worker_start },
        { "stop", worker_stop },
        { "enqueue", worker_enqueue },
        { "enqueue_batch", worker_enqueue_batch },
        { "status", worker_status },
        { "__gc", worker_gc },
        { NULL, NULL }
    };

    luaL_newlib(L, api);
    lua_setglobal(L, "observability_worker");
    return 0;
}

#else

LUA_API int luaopen_observability_worker(lua_State *L)
{
    lua_newtable(L);
    lua_setglobal(L, "observability_worker");
    return 0;
}

#endif
