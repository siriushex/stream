-- Config store and migrations (SQLite)

config = {}
config.runtime_overrides = {}

-- Runtime-only setting overrides (per-process).
-- Useful for multi-process setups (for example stream sharding on different ports),
-- where some keys must be instance-local while the DB stays shared.
function config.set_runtime_override(key, value)
    if type(key) ~= "string" or key == "" then
        return
    end
    if value == nil then
        config.runtime_overrides[key] = nil
        return
    end
    config.runtime_overrides[key] = value
end

local function ensure_dir(path)
    local stat = utils.stat(path)
    if stat.type ~= "directory" then
        os.execute("mkdir -p " .. path)
    end
end

local function copy_file(src, dst)
    local input, err = io.open(src, "rb")
    if not input then
        return nil, err
    end
    local output, err = io.open(dst, "wb")
    if not output then
        input:close()
        return nil, err
    end
    while true do
        local chunk = input:read(8192)
        if not chunk then
            break
        end
        output:write(chunk)
    end
    input:close()
    output:close()
    return true
end

local function write_file_atomic(path, content)
    if not path or path == "" then
        return nil, "empty path"
    end
    local dir = path:match("^(.*)/[^/]+$")
    if dir and dir ~= "" then
        ensure_dir(dir)
    end
    local suffix = tostring(os.time()) .. "." .. tostring(math.random(1000, 9999))
    local tmp = path .. ".tmp." .. suffix
    local file, err = io.open(tmp, "wb")
    if not file then
        return nil, err
    end
    file:write(content or "")
    file:close()
    local ok, rename_err = os.rename(tmp, path)
    if not ok then
        os.remove(tmp)
        return nil, rename_err
    end
    return true
end

local function read_file(path)
    local file, err = io.open(path, "rb")
    if not file then
        return nil, err
    end
    local content = file:read("*a")
    file:close()
    return content
end

local function read_json_file(path)
    local content, err = read_file(path)
    if not content or content == "" then
        return nil, err
    end
    local ok, payload = pcall(json.decode, content)
    if not ok then
        return nil, payload
    end
    if type(payload) ~= "table" then
        return nil, "invalid json"
    end
    return payload
end

local function write_json_file(path, value)
    local payload = json.encode(value or {})
    return write_file_atomic(path, payload)
end

local function db_exec(db, sql)
    local ok, err = db:exec(sql)
    if not ok then
        log.error("[config] sqlite exec failed: " .. tostring(err))
        astra.abort()
    end
end

local function db_exec_safe(db, sql)
    local ok, err = db:exec(sql)
    if not ok then
        return nil, err
    end
    return true
end

function config.with_transaction(fn)
    local ok, err = db_exec_safe(config.db, "BEGIN;")
    if not ok then
        return nil, err
    end
    local success, result, err2 = pcall(fn)
    if not success then
        db_exec_safe(config.db, "ROLLBACK;")
        return nil, result
    end
    if result == nil and err2 then
        db_exec_safe(config.db, "ROLLBACK;")
        return nil, err2
    end
    ok, err = db_exec_safe(config.db, "COMMIT;")
    if not ok then
        db_exec_safe(config.db, "ROLLBACK;")
        return nil, err
    end
    return result, err2
end

local function db_query(db, sql)
    local rows, err = db:query(sql)
    if not rows then
        log.error("[config] sqlite query failed: " .. tostring(err))
        astra.abort()
    end
    return rows
end

local function db_scalar(db, sql)
    local rows = db_query(db, sql)
    if #rows == 0 then
        return nil
    end
    for _, v in pairs(rows[1]) do
        return v
    end
    return nil
end

local function db_count(db, table_name, where)
    local clause = ""
    if where and where ~= "" then
        clause = " WHERE " .. where
    end
    local value = db_scalar(db, "SELECT COUNT(*) FROM " .. table_name .. clause .. ";")
    return tonumber(value) or 0
end

local function db_supports_upsert(db)
    local ok = db:exec("CREATE TABLE IF NOT EXISTS __astra_upsert_check (id INTEGER PRIMARY KEY, v TEXT);")
    if not ok then
        return false
    end
    ok = db:exec("INSERT INTO __astra_upsert_check(id, v) VALUES(1, 'a') " ..
        "ON CONFLICT(id) DO UPDATE SET v=excluded.v;")
    return ok == true
end

local VALUE_KEY = "__astra_value"

local function json_encode(value)
    if value == nil then
        return json.encode({})
    end
    if type(value) ~= "table" then
        return json.encode({ [VALUE_KEY] = value })
    end
    return json.encode(value)
end

local function json_decode(value)
    if value == nil then return nil end
    local decoded = json.decode(value)
    if type(decoded) == "table" and decoded[VALUE_KEY] ~= nil then
        return decoded[VALUE_KEY]
    end
    return decoded
end

local function parse_lnb(value)
    if value == nil then
        return nil
    end
    local str = tostring(value)
    local a, b, c = str:match("^%s*([^:]+):([^:]+):([^:]+)%s*$")
    if not a then
        return nil
    end
    if tonumber(a) == nil or tonumber(b) == nil or tonumber(c) == nil then
        return nil
    end
    return { a, b, c }
end

local function normalize_lnb_config(cfg)
    if type(cfg) ~= "table" then
        return false
    end
    local changed = false
    if cfg.lnb ~= nil and type(cfg.lnb) == "table" then
        local a, b, c = cfg.lnb[1], cfg.lnb[2], cfg.lnb[3]
        if tonumber(a) and tonumber(b) and tonumber(c) then
            cfg.lnb = string.format("%s:%s:%s", tostring(a), tostring(b), tostring(c))
            changed = true
        else
            cfg.lnb = nil
            cfg.lof1, cfg.lof2, cfg.slof = nil, nil, nil
            changed = true
        end
    end
    if cfg.lnb ~= nil then
        local parts = parse_lnb(cfg.lnb)
        if not parts then
            cfg.lnb = nil
            cfg.lof1, cfg.lof2, cfg.slof = nil, nil, nil
            return true
        end
        if cfg.lof1 ~= parts[1] or cfg.lof2 ~= parts[2] or cfg.slof ~= parts[3] then
            cfg.lof1, cfg.lof2, cfg.slof = parts[1], parts[2], parts[3]
            changed = true
        end
        return changed
    end
    if cfg.lof1 ~= nil or cfg.lof2 ~= nil or cfg.slof ~= nil then
        local a, b, c = cfg.lof1, cfg.lof2, cfg.slof
        if tonumber(a) and tonumber(b) and tonumber(c) then
            cfg.lnb = string.format("%s:%s:%s", tostring(a), tostring(b), tostring(c))
            changed = true
        else
            cfg.lof1, cfg.lof2, cfg.slof = nil, nil, nil
            changed = true
        end
    end
    return changed
end

local function sanitize_adapter_config(id, cfg)
    if type(cfg) ~= "table" then
        return cfg, false
    end
    local changed = false
    local adapter_type = tostring(cfg.type or "")
    local is_sat = adapter_type:match("^[sS]") or adapter_type:lower():find("dvb%-s", 1, true)
    if normalize_lnb_config(cfg) then
        log.warning("[config] adapter " .. tostring(id) .. " normalized lnb")
        changed = true
    end
    if is_sat and cfg.modulation ~= nil then
        local modulation = tostring(cfg.modulation)
        if modulation:upper() == "AUTO" or modulation:upper() == "QAM_AUTO" then
            log.warning("[config] adapter " .. tostring(id) .. " modulation AUTO is invalid for DVB-S/S2, clearing")
            cfg.modulation = nil
            changed = true
        end
    end
    return cfg, changed
end

local function copy_table(value)
    if type(value) ~= "table" then
        return value
    end
    local out = {}
    for k, v in pairs(value) do
        out[k] = copy_table(v)
    end
    return out
end

local function sql_escape(value)
    -- Важно: sqlite exec принимает SQL как C-string. Нулевой байт в строке
    -- обрывает запрос и приводит к ошибкам парсинга ("unrecognized token").
    -- Поэтому для любых interpolated значений удаляем \0 и экранируем кавычки.
    local s = tostring(value)
    -- Удаляем NUL байт как обычный литерал, без паттернов, для совместимости.
    s = s:gsub("\0", "")
    return s:gsub("'", "''")
end

local function normalize_bool(value, fallback)
    if value == nil then
        return fallback
    end
    if type(value) == "boolean" then
        return value
    end
    if type(value) == "number" then
        return value ~= 0
    end
    if type(value) == "string" then
        local v = value:lower()
        return v == "1" or v == "true" or v == "yes" or v == "on"
    end
    return fallback
end

local function hash_password(password, salt)
    return base64.encode(string.sha1(salt .. password))
end

local function md5_hex(value)
    local digest = string.md5(tostring(value or ""))
    return string.lower(string.hex(digest))
end

local function random_token(len)
    local charset = "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789"
    local out = {}
    for i = 1, len do
        local idx = math.random(1, #charset)
        out[i] = charset:sub(idx, idx)
    end
    return table.concat(out)
end

local CONFIG_REVISION_MAX_DEFAULT = 20
local CONFIG_LKG_FILENAME = "config_lkg.json"
local CONFIG_BOOT_STATE_FILENAME = "boot_state.json"

config.migrations = {
    [[
    CREATE TABLE IF NOT EXISTS schema_version (
        version INTEGER NOT NULL
    );
    ]],
    [[
    CREATE TABLE IF NOT EXISTS users (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        username TEXT NOT NULL UNIQUE,
        password_hash TEXT NOT NULL,
        password_salt TEXT NOT NULL,
        is_admin INTEGER NOT NULL DEFAULT 0
    );

    CREATE TABLE IF NOT EXISTS sessions (
        token TEXT PRIMARY KEY,
        user_id INTEGER NOT NULL,
        created_at INTEGER NOT NULL,
        expires_at INTEGER NOT NULL
    );

    CREATE TABLE IF NOT EXISTS streams (
        id TEXT PRIMARY KEY,
        enabled INTEGER NOT NULL DEFAULT 1,
        config_json TEXT NOT NULL
    );

    CREATE TABLE IF NOT EXISTS adapters (
        id TEXT PRIMARY KEY,
        enabled INTEGER NOT NULL DEFAULT 1,
        config_json TEXT NOT NULL
    );

    CREATE TABLE IF NOT EXISTS settings (
        key TEXT PRIMARY KEY,
        value_json TEXT NOT NULL
    );
    ]],
    [[
    CREATE TABLE IF NOT EXISTS alerts (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        ts INTEGER NOT NULL,
        level TEXT NOT NULL,
        stream_id TEXT,
        code TEXT,
        message TEXT,
        meta_json TEXT
    );

    CREATE INDEX IF NOT EXISTS alerts_ts_idx ON alerts(ts);
    CREATE INDEX IF NOT EXISTS alerts_stream_idx ON alerts(stream_id);
    CREATE INDEX IF NOT EXISTS alerts_code_idx ON alerts(code);
    ]],
    [[
    ALTER TABLE users ADD COLUMN enabled INTEGER NOT NULL DEFAULT 1;
    ALTER TABLE users ADD COLUMN comment TEXT NOT NULL DEFAULT '';
    ALTER TABLE users ADD COLUMN created_at INTEGER NOT NULL DEFAULT 0;
    ALTER TABLE users ADD COLUMN last_login_at INTEGER NOT NULL DEFAULT 0;
    ALTER TABLE users ADD COLUMN last_login_ip TEXT NOT NULL DEFAULT '';
    ]],
    [[
    CREATE TABLE IF NOT EXISTS audit_log (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        ts INTEGER NOT NULL,
        actor_user_id INTEGER,
        actor_username TEXT,
        action TEXT NOT NULL,
        target_username TEXT,
        ip TEXT,
        ok INTEGER NOT NULL DEFAULT 1,
        message TEXT,
        meta_json TEXT
    );

    CREATE INDEX IF NOT EXISTS audit_log_ts_idx ON audit_log(ts);
    CREATE INDEX IF NOT EXISTS audit_log_action_idx ON audit_log(action);
    CREATE INDEX IF NOT EXISTS audit_log_actor_idx ON audit_log(actor_username);
    CREATE INDEX IF NOT EXISTS audit_log_target_idx ON audit_log(target_username);
    ]],
    [[
    CREATE TABLE IF NOT EXISTS splitter_instances (
        id TEXT PRIMARY KEY,
        name TEXT,
        enable INTEGER NOT NULL DEFAULT 1,
        port INTEGER NOT NULL,
        in_interface TEXT,
        out_interface TEXT,
        logtype TEXT,
        logpath TEXT,
        config_path TEXT,
        created INTEGER NOT NULL,
        updated INTEGER NOT NULL
    );

    CREATE TABLE IF NOT EXISTS splitter_links (
        id TEXT PRIMARY KEY,
        splitter_id TEXT NOT NULL,
        enable INTEGER NOT NULL DEFAULT 1,
        url TEXT NOT NULL,
        bandwidth INTEGER,
        buffering INTEGER,
        created INTEGER NOT NULL,
        updated INTEGER NOT NULL
    );

    CREATE INDEX IF NOT EXISTS splitter_links_splitter_idx ON splitter_links(splitter_id);

    CREATE TABLE IF NOT EXISTS splitter_allow (
        id TEXT PRIMARY KEY,
        splitter_id TEXT NOT NULL,
        kind TEXT NOT NULL,
        value TEXT NOT NULL,
        created INTEGER NOT NULL
    );

    CREATE INDEX IF NOT EXISTS splitter_allow_splitter_idx ON splitter_allow(splitter_id);
    ]],
    [[
    CREATE TABLE IF NOT EXISTS buffer_resources (
        id TEXT PRIMARY KEY,
        name TEXT,
        path TEXT NOT NULL UNIQUE,
        enable INTEGER NOT NULL DEFAULT 0,
        backup_type TEXT DEFAULT 'passive',
        no_data_timeout_sec INTEGER DEFAULT 3,
        backup_start_delay_sec INTEGER DEFAULT 3,
        backup_return_delay_sec INTEGER DEFAULT 10,
        backup_probe_interval_sec INTEGER DEFAULT 30,
        active_input_index INTEGER DEFAULT 0,
        buffering_sec INTEGER DEFAULT 8,
        bandwidth_kbps INTEGER DEFAULT 4000,
        client_start_offset_sec INTEGER DEFAULT 1,
        max_client_lag_ms INTEGER DEFAULT 3000,
        smart_start_enabled INTEGER DEFAULT 1,
        smart_target_delay_ms INTEGER DEFAULT 1000,
        smart_lookback_ms INTEGER DEFAULT 5000,
        smart_require_pat_pmt INTEGER DEFAULT 1,
        smart_require_keyframe INTEGER DEFAULT 1,
        smart_require_pcr INTEGER DEFAULT 0,
        smart_wait_ready_ms INTEGER DEFAULT 1500,
        smart_max_lead_ms INTEGER DEFAULT 2000,
        keyframe_detect_mode TEXT DEFAULT 'auto',
        av_pts_align_enabled INTEGER DEFAULT 1,
        av_pts_max_desync_ms INTEGER DEFAULT 500,
        paramset_required INTEGER DEFAULT 1,
        start_debug_enabled INTEGER DEFAULT 0,
        ts_resync_enabled INTEGER DEFAULT 1,
        ts_drop_corrupt_enabled INTEGER DEFAULT 1,
        ts_rewrite_cc_enabled INTEGER DEFAULT 0,
        pacing_mode TEXT DEFAULT 'none',
        created INTEGER NOT NULL,
        updated INTEGER NOT NULL
    );

    CREATE INDEX IF NOT EXISTS buffer_resources_path_idx ON buffer_resources(path);

    CREATE TABLE IF NOT EXISTS buffer_inputs (
        id TEXT PRIMARY KEY,
        resource_id TEXT NOT NULL,
        enable INTEGER NOT NULL DEFAULT 1,
        url TEXT NOT NULL,
        priority INTEGER DEFAULT 0,
        created INTEGER NOT NULL,
        updated INTEGER NOT NULL
    );

    CREATE INDEX IF NOT EXISTS buffer_inputs_resource_idx ON buffer_inputs(resource_id);

    CREATE TABLE IF NOT EXISTS buffer_allow_rules (
        id TEXT PRIMARY KEY,
        kind TEXT NOT NULL,
        value TEXT NOT NULL,
        created INTEGER NOT NULL
    );
    ]],
    [[
    CREATE TABLE IF NOT EXISTS config_revisions (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        created_ts INTEGER NOT NULL,
        created_by TEXT,
        comment TEXT,
        checksum TEXT,
        status TEXT NOT NULL DEFAULT 'PENDING',
        error_text TEXT,
        applied_ts INTEGER,
        snapshot_path TEXT
    );

    CREATE INDEX IF NOT EXISTS config_revisions_ts_idx ON config_revisions(created_ts);
    CREATE INDEX IF NOT EXISTS config_revisions_status_idx ON config_revisions(status);
    ]],
    [[
    CREATE TABLE IF NOT EXISTS ai_log_events (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        ts INTEGER NOT NULL,
        level TEXT NOT NULL,
        stream_id TEXT,
        component TEXT,
        message TEXT,
        fingerprint TEXT,
        tags_json TEXT
    );

    CREATE INDEX IF NOT EXISTS ai_log_events_ts_idx ON ai_log_events(ts);
    CREATE INDEX IF NOT EXISTS ai_log_events_stream_idx ON ai_log_events(stream_id);
    CREATE INDEX IF NOT EXISTS ai_log_events_level_idx ON ai_log_events(level);

    CREATE TABLE IF NOT EXISTS ai_metrics_rollup (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        ts_bucket INTEGER NOT NULL,
        scope TEXT NOT NULL,
        scope_id TEXT,
        metric_key TEXT NOT NULL,
        value REAL NOT NULL,
        tags_json TEXT
    );

    CREATE UNIQUE INDEX IF NOT EXISTS ai_metrics_rollup_unique
        ON ai_metrics_rollup(ts_bucket, scope, scope_id, metric_key);
    CREATE INDEX IF NOT EXISTS ai_metrics_rollup_ts_idx ON ai_metrics_rollup(ts_bucket);
    CREATE INDEX IF NOT EXISTS ai_metrics_rollup_scope_idx ON ai_metrics_rollup(scope, scope_id);
    CREATE INDEX IF NOT EXISTS ai_metrics_rollup_key_idx ON ai_metrics_rollup(metric_key);

    CREATE TABLE IF NOT EXISTS ai_alerts (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        ts INTEGER NOT NULL,
        severity TEXT NOT NULL,
        summary TEXT NOT NULL,
        details_json TEXT,
        ack_by TEXT,
        ack_ts INTEGER
    );

    CREATE INDEX IF NOT EXISTS ai_alerts_ts_idx ON ai_alerts(ts);
    CREATE INDEX IF NOT EXISTS ai_alerts_severity_idx ON ai_alerts(severity);
    ]],
}

function config.init(opts)
    opts = opts or {}
    local data_dir = opts.data_dir or "./data"
    local db_path = opts.db_path
    if not db_path or tostring(db_path) == "" then
        local preferred = data_dir .. "/stream.db"
        local legacy = data_dir .. "/astra.db"
        db_path = preferred
        if utils and type(utils.stat) == "function" then
            local st_preferred = utils.stat(preferred)
            if not st_preferred or st_preferred.type ~= "file" then
                local st_legacy = utils.stat(legacy)
                if st_legacy and st_legacy.type == "file" then
                    db_path = legacy
                end
            end
        end
    end

    ensure_dir(data_dir)
    config.data_dir = data_dir
    config.state_dir = data_dir .. "/state"
    config.backup_dir = data_dir .. "/backups"
    config.config_backup_dir = config.backup_dir .. "/config"
    ensure_dir(config.state_dir)
    ensure_dir(config.backup_dir)
    ensure_dir(config.config_backup_dir)

    local db, err = sqlite.open(db_path)
    if not db then
        log.error("[config] sqlite open failed: " .. tostring(err))
        astra.abort()
    end

    config.db = db
    config.db_path = db_path

    -- Reduce "database is locked" aborts under concurrent access.
    -- If the backend doesn't support these pragmas, ignore errors silently.
    db_exec_safe(db, "PRAGMA journal_mode=WAL;")
    db_exec_safe(db, "PRAGMA busy_timeout=3000;")

    config.migrate()
    config.supports_upsert = db_supports_upsert(db)
    if not config.supports_upsert then
        log.warning("[config] sqlite upsert not supported, using compatibility mode")
    end
    config.ensure_admin()
    config.sanitize_adapters()
end

function config.sanitize_adapters()
    local rows = db_query(config.db, "SELECT id, config_json FROM adapters;")
    local updated = 0
    for _, row in ipairs(rows) do
        local cfg = json_decode(row.config_json)
        local cleaned, changed = sanitize_adapter_config(row.id, cfg)
        if changed then
            local payload = json_encode(cleaned)
            db_exec(config.db, "UPDATE adapters SET config_json='" ..
                sql_escape(payload) .. "' WHERE id='" .. sql_escape(row.id) .. "';")
            updated = updated + 1
        end
    end
    if updated > 0 then
        log.warning("[config] sanitized adapters with invalid lnb: " .. tostring(updated))
    end
end

function config.migrate()
    local db = config.db

    db_exec(db, config.migrations[1])
    local version = db_scalar(db, "SELECT version FROM schema_version LIMIT 1;")
    if version == nil then
        db_exec(db, "INSERT INTO schema_version(version) VALUES (0);")
        version = 0
    end

    local current = tonumber(version) or 0
    if current < #config.migrations then
        local stat = utils.stat(config.db_path or "")
        if stat and not stat.error and stat.type == "file" then
            local stamp = os.date("%Y%m%d%H%M%S")
            local backup_path = tostring(config.db_path) .. ".bak." .. stamp
            local ok, err = copy_file(config.db_path, backup_path)
            if ok then
                log.info("[config] db backup: " .. backup_path)
            else
                log.warning("[config] db backup failed: " .. tostring(err))
            end
        end
    end

    local function run_migration(step, sql)
        local ok, err = db_exec_safe(db, "BEGIN;")
        if not ok then
            return nil, "begin failed: " .. tostring(err)
        end
        ok, err = db_exec_safe(db, sql)
        if not ok then
            db_exec_safe(db, "ROLLBACK;")
            return nil, err
        end
        ok, err = db_exec_safe(db, "UPDATE schema_version SET version = " .. step .. ";")
        if not ok then
            db_exec_safe(db, "ROLLBACK;")
            return nil, err
        end
        ok, err = db_exec_safe(db, "COMMIT;")
        if not ok then
            db_exec_safe(db, "ROLLBACK;")
            return nil, err
        end
        return true
    end

    for i = current + 1, #config.migrations do
        local ok, err = run_migration(i, config.migrations[i])
        if not ok then
            log.error("[config] migration failed at version " .. i .. ": " .. tostring(err))
            astra.abort()
        end
    end
end

function config.ensure_admin()
    local db = config.db
    local rows = db_query(db, "SELECT id FROM users LIMIT 1;")
    if #rows > 0 then
        return
    end

    local salt = random_token(12)
    local hash = hash_password("admin", salt)
    local now = os.time()
    db_exec(db, "INSERT INTO users(username, password_hash, password_salt, is_admin) " ..
        "VALUES('admin', '" .. sql_escape(hash) .. "', '" .. sql_escape(salt) .. "', 1);")
    db_exec(db, "UPDATE users SET enabled=1, created_at=" .. now .. " WHERE username='admin';")
    log.warning("[config] created default admin user with password 'admin'")
end

function config.get_user_by_username(username)
    local rows = db_query(config.db, "SELECT * FROM users WHERE username='" ..
        sql_escape(username) .. "' LIMIT 1;")
    return rows[1]
end

function config.get_user_by_id(user_id)
    local id = tonumber(user_id)
    if not id then
        return nil
    end
    local rows = db_query(config.db, "SELECT * FROM users WHERE id=" .. id .. " LIMIT 1;")
    return rows[1]
end

function config.list_users()
    local rows = db_query(config.db,
        "SELECT id, username, is_admin, enabled, comment, created_at, last_login_at, last_login_ip " ..
        "FROM users ORDER BY username;")
    return rows
end

function config.verify_user(username, password)
    local user = config.get_user_by_username(username)
    if not user then
        return nil
    end
    if user.enabled ~= nil and tonumber(user.enabled) == 0 then
        return nil
    end
    if user.password_salt and user.password_salt:find("^legacy:") == 1 then
        local cipher = string.lower(user.password_hash or "")
        local candidates = {
            password,
            username .. password,
            password .. username,
            username .. ":" .. password,
            password .. ":" .. username,
        }
        for _, value in ipairs(candidates) do
            if md5_hex(value) == cipher then
                return user
            end
        end
        return nil
    end
    local hash = hash_password(password, user.password_salt)
    if hash ~= user.password_hash then
        return nil
    end
    return user
end

local function password_setting_bool(key, fallback)
    if not config.get_setting then
        return fallback
    end
    local value = config.get_setting(key)
    return normalize_bool(value, fallback)
end

local function password_setting_number(key, fallback)
    if not config.get_setting then
        return fallback
    end
    local value = config.get_setting(key)
    local number = tonumber(value)
    if number == nil then
        return fallback
    end
    return number
end

function config.check_password_policy(password, username)
    if not password or password == "" then
        return false, "invalid password"
    end

    local min_len = password_setting_number("password_min_length", 8)
    local require_letter = password_setting_bool("password_require_letter", true)
    local require_number = password_setting_bool("password_require_number", true)
    local require_symbol = password_setting_bool("password_require_symbol", false)
    local require_mixed = password_setting_bool("password_require_mixed_case", false)
    local disallow_username = password_setting_bool("password_disallow_username", true)

    if #password < min_len then
        return false, "password too short (min " .. tostring(min_len) .. ")"
    end
    if password:find("%s") then
        return false, "password cannot contain spaces"
    end
    if require_letter and not password:match("%a") then
        return false, "password must include a letter"
    end
    if require_number and not password:match("%d") then
        return false, "password must include a number"
    end
    if require_symbol and not password:match("[%p]") then
        return false, "password must include a symbol"
    end
    if require_mixed and (not password:match("%l") or not password:match("%u")) then
        return false, "password must include mixed case"
    end
    if disallow_username and username and username ~= "" then
        local user = tostring(username):lower()
        if password:lower() == user then
            return false, "password cannot match username"
        end
    end

    return true
end

function config.create_user(username, password, is_admin, enabled, comment)
    if not username or username == "" then
        return false, "invalid username"
    end
    local ok, err = config.check_password_policy(password, username)
    if not ok then
        return false, err
    end
    if config.get_user_by_username(username) then
        return false, "already exists"
    end
    local salt = random_token(12)
    local hash = hash_password(password, salt)
    local admin = (is_admin and 1) or 0
    local active = (enabled == false) and 0 or 1
    local note = comment and tostring(comment) or ""
    local now = os.time()
    db_exec(config.db,
        "INSERT INTO users(username, password_hash, password_salt, is_admin, enabled, comment, created_at) " ..
        "VALUES('" .. sql_escape(username) .. "', '" .. sql_escape(hash) .. "', '" ..
        sql_escape(salt) .. "', " .. admin .. ", " .. active .. ", '" ..
        sql_escape(note) .. "', " .. now .. ");")
    return true
end

function config.update_user(username, opts)
    if not username or username == "" then
        return false
    end
    local user = config.get_user_by_username(username)
    if not user then
        return false, "user not found"
    end
    opts = opts or {}
    local fields = {}
    if opts.is_admin ~= nil then
        table.insert(fields, "is_admin=" .. (opts.is_admin and 1 or 0))
    end
    if opts.enabled ~= nil then
        table.insert(fields, "enabled=" .. (opts.enabled and 1 or 0))
    end
    if opts.comment ~= nil then
        table.insert(fields, "comment='" .. sql_escape(tostring(opts.comment)) .. "'")
    end
    if #fields == 0 then
        return true
    end
    db_exec(config.db, "UPDATE users SET " .. table.concat(fields, ", ") ..
        " WHERE username='" .. sql_escape(username) .. "';")
    return true
end

function config.set_user_password(username, password)
    if not username or username == "" then
        return false
    end
    local ok, err = config.check_password_policy(password, username)
    if not ok then
        return false, err
    end
    local user = config.get_user_by_username(username)
    if not user then
        return false, "user not found"
    end
    local salt = random_token(12)
    local hash = hash_password(password, salt)
    db_exec(config.db, "UPDATE users SET password_hash='" .. sql_escape(hash) ..
        "', password_salt='" .. sql_escape(salt) ..
        "' WHERE username='" .. sql_escape(username) .. "';")
    return true
end

function config.set_user_password_force(username, password)
    if not username or username == "" then
        return false, "invalid username"
    end
    if not password or password == "" then
        return false, "invalid password"
    end
    local user = config.get_user_by_username(username)
    if not user then
        return false, "user not found"
    end
    local salt = random_token(12)
    local hash = hash_password(password, salt)
    db_exec(config.db, "UPDATE users SET password_hash='" .. sql_escape(hash) ..
        "', password_salt='" .. sql_escape(salt) ..
        "' WHERE username='" .. sql_escape(username) .. "';")
    return true
end

function config.count_admins()
    local rows = db_query(config.db, "SELECT COUNT(*) as total FROM users WHERE is_admin=1 AND enabled=1;")
    if #rows == 0 then
        return 0
    end
    return tonumber(rows[1].total) or 0
end

function config.touch_user_login(user_id, ip)
    local id = tonumber(user_id)
    if not id then
        return false
    end
    local now = os.time()
    local addr = ip and tostring(ip) or ""
    db_exec(config.db, "UPDATE users SET last_login_at=" .. now ..
        ", last_login_ip='" .. sql_escape(addr) .. "' WHERE id=" .. id .. ";")
    return true
end

function config.upsert_user(username, password_hash, password_salt, is_admin, opts)
    if not username or username == "" then
        return false
    end
    opts = opts or {}
    local existing = config.get_user_by_username(username)
    if existing and not opts.replace then
        return false
    end
    local admin = (is_admin and 1) or 0
    if config.supports_upsert then
        db_exec(config.db,
            "INSERT INTO users(username, password_hash, password_salt, is_admin) VALUES(" ..
            "'" .. sql_escape(username) .. "', '" .. sql_escape(password_hash or "") .. "', '" ..
            sql_escape(password_salt or "") .. "', " .. admin .. ") " ..
            "ON CONFLICT(username) DO UPDATE SET " ..
            "password_hash=excluded.password_hash, password_salt=excluded.password_salt, is_admin=excluded.is_admin;")
        return true
    end
    if existing then
        db_exec(config.db, "UPDATE users SET password_hash='" .. sql_escape(password_hash or "") ..
            "', password_salt='" .. sql_escape(password_salt or "") .. "', is_admin=" .. admin ..
            " WHERE username='" .. sql_escape(username) .. "';")
    else
        db_exec(config.db,
            "INSERT INTO users(username, password_hash, password_salt, is_admin) VALUES(" ..
            "'" .. sql_escape(username) .. "', '" .. sql_escape(password_hash or "") .. "', '" ..
            sql_escape(password_salt or "") .. "', " .. admin .. ");")
    end
    return true
end

function config.create_session(user_id, ttl)
    ttl = ttl or 3600
    local now = os.time()
    local token = random_token(32)
    db_exec(config.db, "INSERT INTO sessions(token, user_id, created_at, expires_at) VALUES(" ..
        "'" .. sql_escape(token) .. "', " .. user_id .. ", " .. now .. ", " ..
        (now + ttl) .. ");")
    return token
end

function config.get_session(token)
    local rows = db_query(config.db, "SELECT * FROM sessions WHERE token='" ..
        sql_escape(token) .. "' LIMIT 1;")
    if #rows == 0 then
        return nil
    end
    local s = rows[1]
    if tonumber(s.expires_at) <= os.time() then
        config.delete_session(token)
        return nil
    end
    return s
end

function config.extend_session(token, new_expires_at)
    local t = tostring(token or "")
    if t == "" then
        return false
    end
    local expires = tonumber(new_expires_at)
    if not expires then
        return false
    end
    -- Never shorten sessions; only extend.
    db_exec(config.db, "UPDATE sessions SET expires_at=CASE WHEN expires_at < " .. expires ..
        " THEN " .. expires .. " ELSE expires_at END WHERE token='" .. sql_escape(t) .. "';")
    return true
end

function config.delete_session(token)
    db_exec(config.db, "DELETE FROM sessions WHERE token='" .. sql_escape(token) .. "';")
end

function config.delete_sessions_for_user(user_id)
    local id = tonumber(user_id)
    if not id then
        return false
    end
    db_exec(config.db, "DELETE FROM sessions WHERE user_id=" .. id .. ";")
    return true
end

function config.count_sessions()
    local now = os.time()
    return db_count(config.db, "sessions", "expires_at > " .. now)
end

function config.list_streams()
    local rows = db_query(config.db, "SELECT * FROM streams ORDER BY id;")
    for _, row in ipairs(rows) do
        row.config = json_decode(row.config_json)
    end
    return rows
end

function config.count_streams()
    local total = db_count(config.db, "streams")
    local enabled = db_count(config.db, "streams", "enabled=1")
    return {
        total = total,
        enabled = enabled,
        disabled = math.max(0, total - enabled),
    }
end

function config.get_stream(id)
    local rows = db_query(config.db, "SELECT * FROM streams WHERE id='" ..
        sql_escape(id) .. "' LIMIT 1;")
    if #rows == 0 then
        return nil
    end
    rows[1].config = json_decode(rows[1].config_json)
    return rows[1]
end

function config.upsert_stream(id, enabled, cfg)
    if type(cfg) == "table" then
        cfg.enable = enabled and true or false
    end
    local payload = json_encode(cfg)
    if config.supports_upsert then
        db_exec(config.db,
            "INSERT INTO streams(id, enabled, config_json) VALUES(" ..
            "'" .. sql_escape(id) .. "', " .. (enabled and 1 or 0) .. ", '" ..
            sql_escape(payload) .. "') " ..
            "ON CONFLICT(id) DO UPDATE SET enabled=excluded.enabled, config_json=excluded.config_json;")
        return
    end
    local exists = db_scalar(config.db, "SELECT 1 FROM streams WHERE id='" ..
        sql_escape(id) .. "' LIMIT 1;")
    if exists then
        db_exec(config.db, "UPDATE streams SET enabled=" .. (enabled and 1 or 0) ..
            ", config_json='" .. sql_escape(payload) .. "' WHERE id='" .. sql_escape(id) .. "';")
    else
        db_exec(config.db, "INSERT INTO streams(id, enabled, config_json) VALUES(" ..
            "'" .. sql_escape(id) .. "', " .. (enabled and 1 or 0) .. ", '" ..
            sql_escape(payload) .. "');")
    end
end

function config.delete_stream(id)
    db_exec(config.db, "DELETE FROM streams WHERE id='" .. sql_escape(id) .. "';")
end

function config.list_adapters()
    local rows = db_query(config.db, "SELECT * FROM adapters ORDER BY id;")
    for _, row in ipairs(rows) do
        row.config = json_decode(row.config_json)
    end
    return rows
end

function config.count_adapters()
    local total = db_count(config.db, "adapters")
    local enabled = db_count(config.db, "adapters", "enabled=1")
    return {
        total = total,
        enabled = enabled,
        disabled = math.max(0, total - enabled),
    }
end

function config.get_adapter(id)
    local rows = db_query(config.db, "SELECT * FROM adapters WHERE id='" ..
        sql_escape(id) .. "' LIMIT 1;")
    if #rows == 0 then
        return nil
    end
    rows[1].config = json_decode(rows[1].config_json)
    return rows[1]
end

function config.upsert_adapter(id, enabled, cfg)
    local cleaned = cfg
    if type(cfg) == "table" then
        local updated
        cleaned, updated = sanitize_adapter_config(id, cfg)
        if updated then
            cfg = cleaned
        end
    end
    if type(cleaned) == "table" then
        cleaned.enable = enabled and true or false
    end
    local payload = json_encode(cleaned)
    if config.supports_upsert then
        db_exec(config.db,
            "INSERT INTO adapters(id, enabled, config_json) VALUES(" ..
            "'" .. sql_escape(id) .. "', " .. (enabled and 1 or 0) .. ", '" ..
            sql_escape(payload) .. "') " ..
            "ON CONFLICT(id) DO UPDATE SET enabled=excluded.enabled, config_json=excluded.config_json;")
        return
    end
    local exists = db_scalar(config.db, "SELECT 1 FROM adapters WHERE id='" ..
        sql_escape(id) .. "' LIMIT 1;")
    if exists then
        db_exec(config.db, "UPDATE adapters SET enabled=" .. (enabled and 1 or 0) ..
            ", config_json='" .. sql_escape(payload) .. "' WHERE id='" .. sql_escape(id) .. "';")
    else
        db_exec(config.db, "INSERT INTO adapters(id, enabled, config_json) VALUES(" ..
            "'" .. sql_escape(id) .. "', " .. (enabled and 1 or 0) .. ", '" ..
            sql_escape(payload) .. "');")
    end
end

function config.delete_adapter(id)
    db_exec(config.db, "DELETE FROM adapters WHERE id='" .. sql_escape(id) .. "';")
end

function config.list_splitters()
    local rows = db_query(config.db, "SELECT * FROM splitter_instances ORDER BY id;")
    for _, row in ipairs(rows) do
        row.enable = tonumber(row.enable) or 0
        row.port = tonumber(row.port) or 0
        row.created = tonumber(row.created) or 0
        row.updated = tonumber(row.updated) or 0
    end
    return rows
end

function config.get_splitter(id)
    local rows = db_query(config.db, "SELECT * FROM splitter_instances WHERE id='" ..
        sql_escape(id) .. "' LIMIT 1;")
    if #rows == 0 then
        return nil
    end
    local row = rows[1]
    row.enable = tonumber(row.enable) or 0
    row.port = tonumber(row.port) or 0
    row.created = tonumber(row.created) or 0
    row.updated = tonumber(row.updated) or 0
    return row
end

function config.upsert_splitter(id, data)
    local now = os.time()
    local enable = normalize_bool(data.enable, true)
    local port = tonumber(data.port) or 0
    local name = tostring(data.name or "")
    local in_iface = tostring(data.in_interface or "")
    local out_iface = tostring(data.out_interface or "")
    local logtype = tostring(data.logtype or "")
    local logpath = tostring(data.logpath or "")
    local config_path = tostring(data.config_path or "")

    local exists = db_scalar(config.db, "SELECT 1 FROM splitter_instances WHERE id='" ..
        sql_escape(id) .. "' LIMIT 1;")
    if exists then
        db_exec(config.db,
            "UPDATE splitter_instances SET " ..
            "name='" .. sql_escape(name) .. "', " ..
            "enable=" .. (enable and 1 or 0) .. ", " ..
            "port=" .. port .. ", " ..
            "in_interface='" .. sql_escape(in_iface) .. "', " ..
            "out_interface='" .. sql_escape(out_iface) .. "', " ..
            "logtype='" .. sql_escape(logtype) .. "', " ..
            "logpath='" .. sql_escape(logpath) .. "', " ..
            "config_path='" .. sql_escape(config_path) .. "', " ..
            "updated=" .. now .. " " ..
            "WHERE id='" .. sql_escape(id) .. "';")
    else
        db_exec(config.db,
            "INSERT INTO splitter_instances(" ..
            "id, name, enable, port, in_interface, out_interface, logtype, logpath, config_path, created, updated" ..
            ") VALUES(" ..
            "'" .. sql_escape(id) .. "', " ..
            "'" .. sql_escape(name) .. "', " ..
            (enable and 1 or 0) .. ", " ..
            port .. ", " ..
            "'" .. sql_escape(in_iface) .. "', " ..
            "'" .. sql_escape(out_iface) .. "', " ..
            "'" .. sql_escape(logtype) .. "', " ..
            "'" .. sql_escape(logpath) .. "', " ..
            "'" .. sql_escape(config_path) .. "', " ..
            now .. ", " .. now .. ");")
    end
end

function config.delete_splitter(id)
    db_exec(config.db, "DELETE FROM splitter_links WHERE splitter_id='" .. sql_escape(id) .. "';")
    db_exec(config.db, "DELETE FROM splitter_allow WHERE splitter_id='" .. sql_escape(id) .. "';")
    db_exec(config.db, "DELETE FROM splitter_instances WHERE id='" .. sql_escape(id) .. "';")
end

function config.list_splitter_links(splitter_id)
    local rows = db_query(config.db, "SELECT * FROM splitter_links WHERE splitter_id='" ..
        sql_escape(splitter_id) .. "' ORDER BY id;")
    for _, row in ipairs(rows) do
        row.enable = tonumber(row.enable) or 0
        row.bandwidth = tonumber(row.bandwidth)
        row.buffering = tonumber(row.buffering)
        row.created = tonumber(row.created) or 0
        row.updated = tonumber(row.updated) or 0
    end
    return rows
end

function config.upsert_splitter_link(splitter_id, id, data)
    local now = os.time()
    local enable = normalize_bool(data.enable, true)
    local url = tostring(data.url or "")
    local bandwidth = tonumber(data.bandwidth)
    local buffering = tonumber(data.buffering)

    local exists = db_scalar(config.db, "SELECT 1 FROM splitter_links WHERE id='" ..
        sql_escape(id) .. "' LIMIT 1;")
    if exists then
        db_exec(config.db,
            "UPDATE splitter_links SET " ..
            "splitter_id='" .. sql_escape(splitter_id) .. "', " ..
            "enable=" .. (enable and 1 or 0) .. ", " ..
            "url='" .. sql_escape(url) .. "', " ..
            "bandwidth=" .. (bandwidth or "NULL") .. ", " ..
            "buffering=" .. (buffering or "NULL") .. ", " ..
            "updated=" .. now .. " " ..
            "WHERE id='" .. sql_escape(id) .. "';")
    else
        db_exec(config.db,
            "INSERT INTO splitter_links(" ..
            "id, splitter_id, enable, url, bandwidth, buffering, created, updated" ..
            ") VALUES(" ..
            "'" .. sql_escape(id) .. "', " ..
            "'" .. sql_escape(splitter_id) .. "', " ..
            (enable and 1 or 0) .. ", " ..
            "'" .. sql_escape(url) .. "', " ..
            (bandwidth or "NULL") .. ", " ..
            (buffering or "NULL") .. ", " ..
            now .. ", " .. now .. ");")
    end
end

function config.delete_splitter_link(splitter_id, id)
    db_exec(config.db, "DELETE FROM splitter_links WHERE splitter_id='" .. sql_escape(splitter_id) ..
        "' AND id='" .. sql_escape(id) .. "';")
end

function config.list_splitter_allow(splitter_id)
    local rows = db_query(config.db, "SELECT * FROM splitter_allow WHERE splitter_id='" ..
        sql_escape(splitter_id) .. "' ORDER BY id;")
    for _, row in ipairs(rows) do
        row.created = tonumber(row.created) or 0
    end
    return rows
end

function config.add_splitter_allow(splitter_id, id, kind, value)
    local now = os.time()
    db_exec(config.db,
        "INSERT INTO splitter_allow(id, splitter_id, kind, value, created) VALUES(" ..
        "'" .. sql_escape(id) .. "', " ..
        "'" .. sql_escape(splitter_id) .. "', " ..
        "'" .. sql_escape(kind or "") .. "', " ..
        "'" .. sql_escape(value or "") .. "', " ..
        now .. ");")
end

function config.delete_splitter_allow(splitter_id, id)
    db_exec(config.db, "DELETE FROM splitter_allow WHERE splitter_id='" .. sql_escape(splitter_id) ..
        "' AND id='" .. sql_escape(id) .. "';")
end

local function normalize_buffer_path(value)
    local path = tostring(value or "")
    if path == "" then
        return ""
    end
    if path:sub(1, 1) ~= "/" then
        path = "/" .. path
    end
    return path
end

function config.list_buffer_resources()
    local rows = db_query(config.db, "SELECT * FROM buffer_resources ORDER BY id;")
    local numeric = {
        "enable",
        "no_data_timeout_sec",
        "backup_start_delay_sec",
        "backup_return_delay_sec",
        "backup_probe_interval_sec",
        "active_input_index",
        "buffering_sec",
        "bandwidth_kbps",
        "client_start_offset_sec",
        "max_client_lag_ms",
        "smart_start_enabled",
        "smart_target_delay_ms",
        "smart_lookback_ms",
        "smart_require_pat_pmt",
        "smart_require_keyframe",
        "smart_require_pcr",
        "smart_wait_ready_ms",
        "smart_max_lead_ms",
        "av_pts_align_enabled",
        "av_pts_max_desync_ms",
        "paramset_required",
        "start_debug_enabled",
        "ts_resync_enabled",
        "ts_drop_corrupt_enabled",
        "ts_rewrite_cc_enabled",
        "created",
        "updated",
    }
    for _, row in ipairs(rows) do
        for _, key in ipairs(numeric) do
            row[key] = tonumber(row[key]) or 0
        end
    end
    return rows
end

function config.get_buffer_resource(id)
    local rows = db_query(config.db, "SELECT * FROM buffer_resources WHERE id='" ..
        sql_escape(id) .. "' LIMIT 1;")
    if #rows == 0 then
        return nil
    end
    local row = rows[1]
    local numeric = {
        "enable",
        "no_data_timeout_sec",
        "backup_start_delay_sec",
        "backup_return_delay_sec",
        "backup_probe_interval_sec",
        "active_input_index",
        "buffering_sec",
        "bandwidth_kbps",
        "client_start_offset_sec",
        "max_client_lag_ms",
        "smart_start_enabled",
        "smart_target_delay_ms",
        "smart_lookback_ms",
        "smart_require_pat_pmt",
        "smart_require_keyframe",
        "smart_require_pcr",
        "smart_wait_ready_ms",
        "smart_max_lead_ms",
        "av_pts_align_enabled",
        "av_pts_max_desync_ms",
        "paramset_required",
        "start_debug_enabled",
        "ts_resync_enabled",
        "ts_drop_corrupt_enabled",
        "ts_rewrite_cc_enabled",
        "created",
        "updated",
    }
    for _, key in ipairs(numeric) do
        row[key] = tonumber(row[key]) or 0
    end
    return row
end

function config.get_buffer_resource_by_path(path)
    local rows = db_query(config.db, "SELECT * FROM buffer_resources WHERE path='" ..
        sql_escape(path) .. "' LIMIT 1;")
    if #rows == 0 then
        return nil
    end
    local row = rows[1]
    row.enable = tonumber(row.enable) or 0
    return row
end

function config.upsert_buffer_resource(id, data)
    local now = os.time()
    local enable = normalize_bool(data.enable, false)
    local name = tostring(data.name or "")
    local path = normalize_buffer_path(data.path or "")
    local backup_type = tostring(data.backup_type or "passive")
    if backup_type ~= "active" then
        backup_type = "passive"
    end
    local keyframe_detect_mode = tostring(data.keyframe_detect_mode or "auto")
    local pacing_mode = tostring(data.pacing_mode or "none")

    local fields = {
        no_data_timeout_sec = tonumber(data.no_data_timeout_sec) or 3,
        backup_start_delay_sec = tonumber(data.backup_start_delay_sec) or 3,
        backup_return_delay_sec = tonumber(data.backup_return_delay_sec) or 10,
        backup_probe_interval_sec = tonumber(data.backup_probe_interval_sec) or 30,
        active_input_index = tonumber(data.active_input_index) or 0,
        buffering_sec = tonumber(data.buffering_sec) or 8,
        bandwidth_kbps = tonumber(data.bandwidth_kbps) or 4000,
        client_start_offset_sec = tonumber(data.client_start_offset_sec) or 1,
        max_client_lag_ms = tonumber(data.max_client_lag_ms) or 3000,
        smart_start_enabled = normalize_bool(data.smart_start_enabled, true),
        smart_target_delay_ms = tonumber(data.smart_target_delay_ms) or 1000,
        smart_lookback_ms = tonumber(data.smart_lookback_ms) or 5000,
        smart_require_pat_pmt = normalize_bool(data.smart_require_pat_pmt, true),
        smart_require_keyframe = normalize_bool(data.smart_require_keyframe, true),
        smart_require_pcr = normalize_bool(data.smart_require_pcr, false),
        smart_wait_ready_ms = tonumber(data.smart_wait_ready_ms) or 1500,
        smart_max_lead_ms = tonumber(data.smart_max_lead_ms) or 2000,
        av_pts_align_enabled = normalize_bool(data.av_pts_align_enabled, true),
        av_pts_max_desync_ms = tonumber(data.av_pts_max_desync_ms) or 500,
        paramset_required = normalize_bool(data.paramset_required, true),
        start_debug_enabled = normalize_bool(data.start_debug_enabled, false),
        ts_resync_enabled = normalize_bool(data.ts_resync_enabled, true),
        ts_drop_corrupt_enabled = normalize_bool(data.ts_drop_corrupt_enabled, true),
        ts_rewrite_cc_enabled = normalize_bool(data.ts_rewrite_cc_enabled, false),
    }

    local exists = db_scalar(config.db, "SELECT 1 FROM buffer_resources WHERE id='" ..
        sql_escape(id) .. "' LIMIT 1;")
    if exists then
        db_exec(config.db,
            "UPDATE buffer_resources SET " ..
            "name='" .. sql_escape(name) .. "', " ..
            "path='" .. sql_escape(path) .. "', " ..
            "enable=" .. (enable and 1 or 0) .. ", " ..
            "backup_type='" .. sql_escape(backup_type) .. "', " ..
            "no_data_timeout_sec=" .. fields.no_data_timeout_sec .. ", " ..
            "backup_start_delay_sec=" .. fields.backup_start_delay_sec .. ", " ..
            "backup_return_delay_sec=" .. fields.backup_return_delay_sec .. ", " ..
            "backup_probe_interval_sec=" .. fields.backup_probe_interval_sec .. ", " ..
            "active_input_index=" .. fields.active_input_index .. ", " ..
            "buffering_sec=" .. fields.buffering_sec .. ", " ..
            "bandwidth_kbps=" .. fields.bandwidth_kbps .. ", " ..
            "client_start_offset_sec=" .. fields.client_start_offset_sec .. ", " ..
            "max_client_lag_ms=" .. fields.max_client_lag_ms .. ", " ..
            "smart_start_enabled=" .. (fields.smart_start_enabled and 1 or 0) .. ", " ..
            "smart_target_delay_ms=" .. fields.smart_target_delay_ms .. ", " ..
            "smart_lookback_ms=" .. fields.smart_lookback_ms .. ", " ..
            "smart_require_pat_pmt=" .. (fields.smart_require_pat_pmt and 1 or 0) .. ", " ..
            "smart_require_keyframe=" .. (fields.smart_require_keyframe and 1 or 0) .. ", " ..
            "smart_require_pcr=" .. (fields.smart_require_pcr and 1 or 0) .. ", " ..
            "smart_wait_ready_ms=" .. fields.smart_wait_ready_ms .. ", " ..
            "smart_max_lead_ms=" .. fields.smart_max_lead_ms .. ", " ..
            "keyframe_detect_mode='" .. sql_escape(keyframe_detect_mode) .. "', " ..
            "av_pts_align_enabled=" .. (fields.av_pts_align_enabled and 1 or 0) .. ", " ..
            "av_pts_max_desync_ms=" .. fields.av_pts_max_desync_ms .. ", " ..
            "paramset_required=" .. (fields.paramset_required and 1 or 0) .. ", " ..
            "start_debug_enabled=" .. (fields.start_debug_enabled and 1 or 0) .. ", " ..
            "ts_resync_enabled=" .. (fields.ts_resync_enabled and 1 or 0) .. ", " ..
            "ts_drop_corrupt_enabled=" .. (fields.ts_drop_corrupt_enabled and 1 or 0) .. ", " ..
            "ts_rewrite_cc_enabled=" .. (fields.ts_rewrite_cc_enabled and 1 or 0) .. ", " ..
            "pacing_mode='" .. sql_escape(pacing_mode) .. "', " ..
            "updated=" .. now .. " " ..
            "WHERE id='" .. sql_escape(id) .. "';")
    else
        db_exec(config.db,
            "INSERT INTO buffer_resources(" ..
            "id, name, path, enable, backup_type, no_data_timeout_sec, backup_start_delay_sec, " ..
            "backup_return_delay_sec, backup_probe_interval_sec, active_input_index, buffering_sec, " ..
            "bandwidth_kbps, client_start_offset_sec, max_client_lag_ms, smart_start_enabled, " ..
            "smart_target_delay_ms, smart_lookback_ms, smart_require_pat_pmt, smart_require_keyframe, " ..
            "smart_require_pcr, smart_wait_ready_ms, smart_max_lead_ms, keyframe_detect_mode, " ..
            "av_pts_align_enabled, av_pts_max_desync_ms, paramset_required, start_debug_enabled, " ..
            "ts_resync_enabled, ts_drop_corrupt_enabled, ts_rewrite_cc_enabled, pacing_mode, created, updated" ..
            ") VALUES(" ..
            "'" .. sql_escape(id) .. "', " ..
            "'" .. sql_escape(name) .. "', " ..
            "'" .. sql_escape(path) .. "', " ..
            (enable and 1 or 0) .. ", " ..
            "'" .. sql_escape(backup_type) .. "', " ..
            fields.no_data_timeout_sec .. ", " ..
            fields.backup_start_delay_sec .. ", " ..
            fields.backup_return_delay_sec .. ", " ..
            fields.backup_probe_interval_sec .. ", " ..
            fields.active_input_index .. ", " ..
            fields.buffering_sec .. ", " ..
            fields.bandwidth_kbps .. ", " ..
            fields.client_start_offset_sec .. ", " ..
            fields.max_client_lag_ms .. ", " ..
            (fields.smart_start_enabled and 1 or 0) .. ", " ..
            fields.smart_target_delay_ms .. ", " ..
            fields.smart_lookback_ms .. ", " ..
            (fields.smart_require_pat_pmt and 1 or 0) .. ", " ..
            (fields.smart_require_keyframe and 1 or 0) .. ", " ..
            (fields.smart_require_pcr and 1 or 0) .. ", " ..
            fields.smart_wait_ready_ms .. ", " ..
            fields.smart_max_lead_ms .. ", " ..
            "'" .. sql_escape(keyframe_detect_mode) .. "', " ..
            (fields.av_pts_align_enabled and 1 or 0) .. ", " ..
            fields.av_pts_max_desync_ms .. ", " ..
            (fields.paramset_required and 1 or 0) .. ", " ..
            (fields.start_debug_enabled and 1 or 0) .. ", " ..
            (fields.ts_resync_enabled and 1 or 0) .. ", " ..
            (fields.ts_drop_corrupt_enabled and 1 or 0) .. ", " ..
            (fields.ts_rewrite_cc_enabled and 1 or 0) .. ", " ..
            "'" .. sql_escape(pacing_mode) .. "', " ..
            now .. ", " .. now .. ");")
    end
end

function config.delete_buffer_resource(id)
    db_exec(config.db, "DELETE FROM buffer_inputs WHERE resource_id='" .. sql_escape(id) .. "';")
    db_exec(config.db, "DELETE FROM buffer_resources WHERE id='" .. sql_escape(id) .. "';")
end

function config.list_buffer_inputs(resource_id)
    local rows = db_query(config.db, "SELECT * FROM buffer_inputs WHERE resource_id='" ..
        sql_escape(resource_id) .. "' ORDER BY priority, id;")
    for _, row in ipairs(rows) do
        row.enable = tonumber(row.enable) or 0
        row.priority = tonumber(row.priority) or 0
        row.created = tonumber(row.created) or 0
        row.updated = tonumber(row.updated) or 0
    end
    return rows
end

function config.upsert_buffer_input(resource_id, id, data)
    local now = os.time()
    local enable = normalize_bool(data.enable, true)
    local url = tostring(data.url or "")
    local priority = tonumber(data.priority) or 0

    local exists = db_scalar(config.db, "SELECT 1 FROM buffer_inputs WHERE id='" ..
        sql_escape(id) .. "' LIMIT 1;")
    if exists then
        db_exec(config.db,
            "UPDATE buffer_inputs SET " ..
            "resource_id='" .. sql_escape(resource_id) .. "', " ..
            "enable=" .. (enable and 1 or 0) .. ", " ..
            "url='" .. sql_escape(url) .. "', " ..
            "priority=" .. priority .. ", " ..
            "updated=" .. now .. " " ..
            "WHERE id='" .. sql_escape(id) .. "';")
    else
        db_exec(config.db,
            "INSERT INTO buffer_inputs(" ..
            "id, resource_id, enable, url, priority, created, updated" ..
            ") VALUES(" ..
            "'" .. sql_escape(id) .. "', " ..
            "'" .. sql_escape(resource_id) .. "', " ..
            (enable and 1 or 0) .. ", " ..
            "'" .. sql_escape(url) .. "', " ..
            priority .. ", " ..
            now .. ", " .. now .. ");")
    end
end

function config.delete_buffer_input(resource_id, id)
    db_exec(config.db, "DELETE FROM buffer_inputs WHERE resource_id='" .. sql_escape(resource_id) ..
        "' AND id='" .. sql_escape(id) .. "';")
end

function config.list_buffer_allow()
    local rows = db_query(config.db, "SELECT * FROM buffer_allow_rules ORDER BY id;")
    for _, row in ipairs(rows) do
        row.created = tonumber(row.created) or 0
    end
    return rows
end

function config.add_buffer_allow(id, kind, value)
    local now = os.time()
    db_exec(config.db,
        "INSERT INTO buffer_allow_rules(id, kind, value, created) VALUES(" ..
        "'" .. sql_escape(id) .. "', " ..
        "'" .. sql_escape(kind or "") .. "', " ..
        "'" .. sql_escape(value or "") .. "', " ..
        now .. ");")
end

function config.delete_buffer_allow(id)
    db_exec(config.db, "DELETE FROM buffer_allow_rules WHERE id='" .. sql_escape(id) .. "';")
end

function config.get_setting(key)
    if config.runtime_overrides and config.runtime_overrides[key] ~= nil then
        return config.runtime_overrides[key]
    end
    if not config.db then
        return nil
    end
    local rows = db_query(config.db, "SELECT value_json FROM settings WHERE key='" ..
        sql_escape(key) .. "' LIMIT 1;")
    if #rows == 0 then
        return nil
    end
    return json_decode(rows[1].value_json)
end

function config.list_settings()
    local rows = db_query(config.db, "SELECT key, value_json FROM settings ORDER BY key;")
    local out = {}
    for _, row in ipairs(rows) do
        out[row.key] = json_decode(row.value_json)
    end
    return out
end

function config.set_setting(key, value)
    local payload = json_encode(value)
    if config.supports_upsert then
        db_exec(config.db,
            "INSERT INTO settings(key, value_json) VALUES('" .. sql_escape(key) .. "', '" ..
            sql_escape(payload) .. "') " ..
            "ON CONFLICT(key) DO UPDATE SET value_json=excluded.value_json;")
        return
    end
    local exists = db_scalar(config.db, "SELECT 1 FROM settings WHERE key='" ..
        sql_escape(key) .. "' LIMIT 1;")
    if exists then
        db_exec(config.db, "UPDATE settings SET value_json='" .. sql_escape(payload) ..
            "' WHERE key='" .. sql_escape(key) .. "';")
    else
        db_exec(config.db, "INSERT INTO settings(key, value_json) VALUES('" ..
            sql_escape(key) .. "', '" .. sql_escape(payload) .. "');")
    end
end

local function normalize_revision_row(row)
    if not row then
        return nil
    end
    row.id = tonumber(row.id) or 0
    row.created_ts = tonumber(row.created_ts) or 0
    row.applied_ts = tonumber(row.applied_ts) or 0
    return row
end

local function config_backup_path(name)
    local base = config.config_backup_dir or "./data/backups/config"
    return base .. "/" .. name
end

function config.lkg_snapshot_path()
    return config_backup_path(CONFIG_LKG_FILENAME)
end

function config.ensure_lkg_snapshot()
    local path = config.lkg_snapshot_path()
    local stat = utils.stat(path)
    if stat and stat.type == "file" then
        return path
    end
    local ok, err = config.export_astra_file(path)
    if not ok then
        return nil, err
    end
    return path
end

function config.update_lkg_snapshot()
    local path = config.lkg_snapshot_path()
    local ok, err = config.export_astra_file(path)
    if not ok then
        return nil, err
    end
    return path
end

function config.build_snapshot_path(revision_id, ts)
    local stamp = os.date("%Y%m%d-%H%M%S", ts or os.time())
    local suffix = revision_id and ("_r" .. tostring(revision_id)) or ""
    return config_backup_path("config_" .. stamp .. suffix .. ".json")
end

function config.restore_snapshot(path)
    if not path or path == "" then
        return nil, "missing snapshot path"
    end
    local stat = utils.stat(path)
    if not stat or stat.type ~= "file" then
        return nil, "snapshot not found"
    end
    local summary, err = config.import_astra_file(path, { mode = "replace", transaction = true })
    if not summary then
        return nil, err
    end
    return summary
end

function config.create_revision(opts)
    opts = opts or {}
    local created_ts = tonumber(opts.created_ts) or os.time()
    local created_by = opts.created_by and tostring(opts.created_by) or ""
    local comment = opts.comment and tostring(opts.comment) or ""
    local checksum = opts.checksum and tostring(opts.checksum) or ""
    local status = opts.status and tostring(opts.status) or "PENDING"
    local error_text = opts.error_text and tostring(opts.error_text) or ""
    local applied_ts = tonumber(opts.applied_ts) or 0
    local snapshot_path = opts.snapshot_path and tostring(opts.snapshot_path) or ""
    db_exec(config.db,
        "INSERT INTO config_revisions(created_ts, created_by, comment, checksum, status, error_text, applied_ts, snapshot_path) VALUES(" ..
        created_ts .. ", '" .. sql_escape(created_by) .. "', '" .. sql_escape(comment) .. "', '" ..
        sql_escape(checksum) .. "', '" .. sql_escape(status) .. "', '" .. sql_escape(error_text) .. "', " ..
        applied_ts .. ", '" .. sql_escape(snapshot_path) .. "');")
    local id = db_scalar(config.db, "SELECT last_insert_rowid();")
    return tonumber(id) or 0
end

function config.update_revision(id, fields)
    local rev_id = tonumber(id)
    if not rev_id or rev_id <= 0 then
        return nil
    end
    fields = fields or {}
    local set = {}
    if fields.created_by ~= nil then
        table.insert(set, "created_by='" .. sql_escape(tostring(fields.created_by)) .. "'")
    end
    if fields.comment ~= nil then
        table.insert(set, "comment='" .. sql_escape(tostring(fields.comment)) .. "'")
    end
    if fields.checksum ~= nil then
        table.insert(set, "checksum='" .. sql_escape(tostring(fields.checksum)) .. "'")
    end
    if fields.status ~= nil then
        table.insert(set, "status='" .. sql_escape(tostring(fields.status)) .. "'")
    end
    if fields.error_text ~= nil then
        table.insert(set, "error_text='" .. sql_escape(tostring(fields.error_text)) .. "'")
    end
    if fields.applied_ts ~= nil then
        table.insert(set, "applied_ts=" .. tonumber(fields.applied_ts))
    end
    if fields.snapshot_path ~= nil then
        table.insert(set, "snapshot_path='" .. sql_escape(tostring(fields.snapshot_path)) .. "'")
    end
    if #set == 0 then
        return true
    end
    db_exec(config.db, "UPDATE config_revisions SET " .. table.concat(set, ", ") ..
        " WHERE id=" .. rev_id .. ";")
    return true
end

function config.get_revision(id)
    local rev_id = tonumber(id)
    if not rev_id then
        return nil
    end
    local rows = db_query(config.db, "SELECT * FROM config_revisions WHERE id=" .. rev_id .. " LIMIT 1;")
    if #rows == 0 then
        return nil
    end
    return normalize_revision_row(rows[1])
end

function config.delete_revision(id)
    local rev_id = tonumber(id)
    if not rev_id or rev_id <= 0 then
        return nil
    end
    local row = config.get_revision(rev_id)
    if not row then
        return nil
    end
    if row.snapshot_path and row.snapshot_path ~= "" then
        os.remove(row.snapshot_path)
    end
    db_exec(config.db, "DELETE FROM config_revisions WHERE id=" .. rev_id .. ";")
    return row
end

function config.list_revisions(limit)
    local max = tonumber(limit) or 50
    if max < 1 then
        max = 1
    elseif max > 500 then
        max = 500
    end
    local rows = db_query(config.db, "SELECT * FROM config_revisions ORDER BY id DESC LIMIT " .. max .. ";")
    for _, row in ipairs(rows) do
        normalize_revision_row(row)
    end
    return rows
end

function config.delete_all_revisions()
    local rows = db_query(config.db, "SELECT id, snapshot_path FROM config_revisions;")
    for _, row in ipairs(rows) do
        if row.snapshot_path and row.snapshot_path ~= "" then
            os.remove(row.snapshot_path)
        end
    end
    db_exec(config.db, "DELETE FROM config_revisions;")
    return #rows
end

function config.prune_revisions(max_keep)
    local limit = tonumber(max_keep)
    if not limit or limit <= 0 then
        limit = CONFIG_REVISION_MAX_DEFAULT
    end
    local rows = db_query(config.db,
        "SELECT id, snapshot_path FROM config_revisions ORDER BY id DESC LIMIT -1 OFFSET " .. limit .. ";")
    for _, row in ipairs(rows) do
        if row.snapshot_path and row.snapshot_path ~= "" then
            os.remove(row.snapshot_path)
        end
        db_exec(config.db, "DELETE FROM config_revisions WHERE id=" .. tonumber(row.id) .. ";")
    end
end

function config.write_boot_state(status, info)
    local path = config.state_dir and (config.state_dir .. "/" .. CONFIG_BOOT_STATE_FILENAME)
        or ("./data/" .. CONFIG_BOOT_STATE_FILENAME)
    local payload = info or {}
    payload.status = status
    payload.ts = os.time()
    return write_json_file(path, payload)
end

function config.read_boot_state()
    local path = config.state_dir and (config.state_dir .. "/" .. CONFIG_BOOT_STATE_FILENAME)
        or ("./data/" .. CONFIG_BOOT_STATE_FILENAME)
    return read_json_file(path)
end

function config.mark_boot_ok(revision_id)
    return config.write_boot_state("ok", { revision_id = revision_id })
end

function config.mark_boot_start(revision_id)
    return config.write_boot_state("starting", { revision_id = revision_id })
end

function config.mark_boot_failed(reason, revision_id)
    return config.write_boot_state("failed", {
        revision_id = revision_id,
        reason = tostring(reason or ""),
    })
end

function config.add_alert(level, stream_id, code, message, meta)
    local ts = os.time()
    local meta_payload = ""
    if meta ~= nil then
        meta_payload = json_encode(meta)
    end
    db_exec(config.db,
        "INSERT INTO alerts(ts, level, stream_id, code, message, meta_json) VALUES(" ..
        ts .. ", '" .. sql_escape(tostring(level or "INFO")) .. "', '" ..
        sql_escape(tostring(stream_id or "")) .. "', '" ..
        sql_escape(tostring(code or "")) .. "', '" ..
        sql_escape(tostring(message or "")) .. "', '" ..
        sql_escape(meta_payload) .. "');")
    if telegram and telegram.on_alert then
        local ok, err = pcall(telegram.on_alert, {
            ts = ts,
            level = tostring(level or "INFO"),
            stream_id = tostring(stream_id or ""),
            code = tostring(code or ""),
            message = tostring(message or ""),
            meta = meta,
        })
        if not ok then
            log.warning("[alerts] telegram notify failed")
        end
    end
    if ai_observability and ai_observability.ingest_alert then
        pcall(ai_observability.ingest_alert, {
            ts = ts,
            level = tostring(level or "INFO"),
            stream_id = tostring(stream_id or ""),
            code = tostring(code or ""),
            message = tostring(message or ""),
            meta = meta,
        })
    end
    return true
end

function config.list_alerts(opts)
    opts = opts or {}
    local since = tonumber(opts.since) or 0
    local limit = tonumber(opts.limit) or 200
    if limit < 1 then
        limit = 1
    elseif limit > 1000 then
        limit = 1000
    end

    local where = { "ts >= " .. since }
    if opts.stream_id and tostring(opts.stream_id) ~= "" then
        table.insert(where, "stream_id='" .. sql_escape(tostring(opts.stream_id)) .. "'")
    end
    if opts.code and tostring(opts.code) ~= "" then
        table.insert(where, "code='" .. sql_escape(tostring(opts.code)) .. "'")
    end
    if opts.code_prefix and tostring(opts.code_prefix) ~= "" then
        table.insert(where, "code LIKE '" .. sql_escape(tostring(opts.code_prefix)) .. "%'")
    end
    local where_sql = table.concat(where, " AND ")
    local rows = db_query(config.db, "SELECT id, ts, level, stream_id, code, message, meta_json " ..
        "FROM alerts WHERE " .. where_sql .. " ORDER BY id DESC LIMIT " .. limit .. ";")
    for _, row in ipairs(rows) do
        if row.meta_json and row.meta_json ~= "" then
            row.meta = json_decode(row.meta_json)
        else
            row.meta = nil
        end
    end
    return rows
end

function config.count_alerts(opts)
    opts = opts or {}
    local since = tonumber(opts.since) or 0
    local until_ts = tonumber(opts["until"]) or 0
    local where = { "ts >= " .. since }
    if until_ts and until_ts > 0 then
        table.insert(where, "ts < " .. until_ts)
    end
    if opts.levels and type(opts.levels) == "table" and #opts.levels > 0 then
        local parts = {}
        for _, item in ipairs(opts.levels) do
            table.insert(parts, "'" .. sql_escape(tostring(item)) .. "'")
        end
        table.insert(where, "level IN (" .. table.concat(parts, ",") .. ")")
    end
    local where_sql = table.concat(where, " AND ")
    local value = db_scalar(config.db, "SELECT COUNT(*) FROM alerts WHERE " .. where_sql .. ";")
    return tonumber(value) or 0
end

function config.add_ai_log_event(entry)
    if type(entry) ~= "table" then
        return nil, "invalid entry"
    end
    local ts = tonumber(entry.ts) or os.time()
    local level = tostring(entry.level or "INFO")
    local stream_id = tostring(entry.stream_id or "")
    local component = tostring(entry.component or "")
    local message = tostring(entry.message or "")
    local fingerprint = tostring(entry.fingerprint or "")
    local tags_json = ""
    if entry.tags ~= nil then
        tags_json = json_encode(entry.tags)
    end
    local ok, err = db_exec_safe(config.db,
        "INSERT INTO ai_log_events(ts, level, stream_id, component, message, fingerprint, tags_json) VALUES(" ..
        ts .. ", '" .. sql_escape(level) .. "', '" .. sql_escape(stream_id) .. "', '" ..
        sql_escape(component) .. "', '" .. sql_escape(message) .. "', '" ..
        sql_escape(fingerprint) .. "', '" .. sql_escape(tags_json) .. "');")
    if not ok then
        -- Observability не должна валить весь процесс из-за проблем с БД/данными.
        log.warning("[observability] failed to insert ai_log_event: " .. tostring(err))
        return nil, err
    end
    return true
end

function config.list_ai_log_events(opts)
    opts = opts or {}
    local since = tonumber(opts.since) or 0
    local until_ts = tonumber(opts["until"]) or 0
    local limit = tonumber(opts.limit) or 500
    if limit < 1 then
        limit = 1
    elseif limit > 5000 then
        limit = 5000
    end
    local where = { "ts >= " .. since }
    if until_ts and until_ts > 0 then
        table.insert(where, "ts < " .. until_ts)
    end
    if opts.level and tostring(opts.level) ~= "" then
        table.insert(where, "level='" .. sql_escape(tostring(opts.level)) .. "'")
    end
    if opts.stream_id and tostring(opts.stream_id) ~= "" then
        table.insert(where, "stream_id='" .. sql_escape(tostring(opts.stream_id)) .. "'")
    end
    local where_sql = table.concat(where, " AND ")
    local rows = db_query(config.db, "SELECT id, ts, level, stream_id, component, message, fingerprint, tags_json " ..
        "FROM ai_log_events WHERE " .. where_sql .. " ORDER BY ts DESC LIMIT " .. limit .. ";")
    for _, row in ipairs(rows) do
        if row.tags_json and row.tags_json ~= "" then
            row.tags = json_decode(row.tags_json)
        else
            row.tags = nil
        end
    end
    return rows
end

function config.prune_ai_log_events(before_ts)
    local cutoff = tonumber(before_ts) or 0
    if cutoff <= 0 then
        return 0
    end
    local res = db_exec(config.db, "DELETE FROM ai_log_events WHERE ts < " .. cutoff .. ";")
    return res and true or false
end

function config.upsert_ai_metric(entry)
    if type(entry) ~= "table" then
        return nil, "invalid entry"
    end
    local ts_bucket = tonumber(entry.ts_bucket) or 0
    if ts_bucket <= 0 then
        return nil, "invalid ts_bucket"
    end
    local scope = tostring(entry.scope or "global")
    local scope_id = tostring(entry.scope_id or "")
    local metric_key = tostring(entry.metric_key or "")
    if metric_key == "" then
        return nil, "metric_key required"
    end
    local value = tonumber(entry.value) or 0
    local tags_json = ""
    if entry.tags ~= nil then
        tags_json = json_encode(entry.tags)
    end
    local ok, err = db_exec_safe(config.db,
        "INSERT OR REPLACE INTO ai_metrics_rollup(ts_bucket, scope, scope_id, metric_key, value, tags_json) VALUES(" ..
        ts_bucket .. ", '" .. sql_escape(scope) .. "', '" .. sql_escape(scope_id) .. "', '" ..
        sql_escape(metric_key) .. "', " .. value .. ", '" .. sql_escape(tags_json) .. "');")
    if not ok then
        -- Метрики не критичны; не прерываем работу процесса.
        log.warning("[observability] failed to upsert ai_metric: " .. tostring(err))
        return nil, err
    end
    return true
end

function config.list_ai_metrics(opts)
    opts = opts or {}
    local since = tonumber(opts.since) or 0
    local until_ts = tonumber(opts["until"]) or 0
    local limit = tonumber(opts.limit) or 2000
    if limit < 1 then
        limit = 1
    elseif limit > 20000 then
        limit = 20000
    end
    local where = { "ts_bucket >= " .. since }
    if until_ts and until_ts > 0 then
        table.insert(where, "ts_bucket < " .. until_ts)
    end
    if opts.scope and tostring(opts.scope) ~= "" then
        table.insert(where, "scope='" .. sql_escape(tostring(opts.scope)) .. "'")
    end
    if opts.scope_id and tostring(opts.scope_id) ~= "" then
        table.insert(where, "scope_id='" .. sql_escape(tostring(opts.scope_id)) .. "'")
    end
    if opts.metric_key and tostring(opts.metric_key) ~= "" then
        table.insert(where, "metric_key='" .. sql_escape(tostring(opts.metric_key)) .. "'")
    end
    local where_sql = table.concat(where, " AND ")
    local rows = db_query(config.db, "SELECT ts_bucket, scope, scope_id, metric_key, value, tags_json " ..
        "FROM ai_metrics_rollup WHERE " .. where_sql .. " ORDER BY ts_bucket ASC LIMIT " .. limit .. ";")
    for _, row in ipairs(rows) do
        if row.tags_json and row.tags_json ~= "" then
            row.tags = json_decode(row.tags_json)
        else
            row.tags = nil
        end
    end
    return rows
end

function config.prune_ai_metrics(before_ts)
    local cutoff = tonumber(before_ts) or 0
    if cutoff <= 0 then
        return 0
    end
    local res = db_exec(config.db, "DELETE FROM ai_metrics_rollup WHERE ts_bucket < " .. cutoff .. ";")
    return res and true or false
end

function config.add_audit_event(action, opts)
    if not action or action == "" then
        return false
    end
    opts = opts or {}
    local ts = os.time()
    local actor_id = tonumber(opts.actor_user_id) or 0
    local actor_username = opts.actor_username or ""
    local target_username = opts.target_username or ""
    local ip = opts.ip or ""
    local ok = (opts.ok == false) and 0 or 1
    local message = opts.message or ""
    local meta_payload = ""
    if opts.meta ~= nil then
        meta_payload = json_encode(opts.meta)
    end
    db_exec(config.db,
        "INSERT INTO audit_log(ts, actor_user_id, actor_username, action, target_username, ip, ok, message, meta_json) " ..
        "VALUES(" .. ts .. ", " .. actor_id .. ", '" .. sql_escape(tostring(actor_username)) .. "', '" ..
        sql_escape(tostring(action)) .. "', '" .. sql_escape(tostring(target_username)) .. "', '" ..
        sql_escape(tostring(ip)) .. "', " .. ok .. ", '" .. sql_escape(tostring(message)) .. "', '" ..
        sql_escape(meta_payload) .. "');")
    return true
end

function config.list_audit_events(opts)
    opts = opts or {}
    local since = tonumber(opts.since) or 0
    local limit = tonumber(opts.limit) or 200
    if limit < 1 then
        limit = 1
    elseif limit > 1000 then
        limit = 1000
    end

    local where = { "ts >= " .. since }
    if opts.action and tostring(opts.action) ~= "" then
        table.insert(where, "action='" .. sql_escape(tostring(opts.action)) .. "'")
    end
    if opts.actor and tostring(opts.actor) ~= "" then
        table.insert(where, "actor_username='" .. sql_escape(tostring(opts.actor)) .. "'")
    end
    if opts.target and tostring(opts.target) ~= "" then
        table.insert(where, "target_username='" .. sql_escape(tostring(opts.target)) .. "'")
    end
    if opts.ip and tostring(opts.ip) ~= "" then
        table.insert(where, "ip='" .. sql_escape(tostring(opts.ip)) .. "'")
    end
    local ok_filter = normalize_bool(opts.ok, nil)
    if ok_filter ~= nil then
        table.insert(where, "ok=" .. (ok_filter and 1 or 0))
    end

    local where_sql = table.concat(where, " AND ")
    local rows = db_query(config.db,
        "SELECT id, ts, actor_user_id, actor_username, action, target_username, ip, ok, message, meta_json " ..
        "FROM audit_log WHERE " .. where_sql .. " ORDER BY id DESC LIMIT " .. limit .. ";")
    for _, row in ipairs(rows) do
        if row.meta_json and row.meta_json ~= "" then
            row.meta = json_decode(row.meta_json)
        else
            row.meta = nil
        end
    end
    return rows
end

local function import_list(value)
    if type(value) == "table" then
        return value
    end
    return {}
end

local function import_id(item, fallback)
    if type(item) == "table" and item.id ~= nil then
        local id = tostring(item.id)
        if id ~= "" then
            return id
        end
    end
    return fallback
end

local function path_extension(path)
    if type(path) ~= "string" then
        return nil
    end
    local ext = path:match("%.([%w_]+)$")
    if not ext or ext == "" then
        return nil
    end
    return string.lower(ext)
end

function config.set_primary_config_path(path)
    if type(path) ~= "string" or path == "" then
        config.primary_config_path = nil
        config.primary_config_ext = nil
        return
    end
    config.primary_config_path = path
    config.primary_config_ext = path_extension(path)
end

function config.get_primary_config_path()
    return config.primary_config_path
end

function config.primary_config_is_json()
    return config.primary_config_ext == "json"
end

function config.export_primary_config()
    local path = config.primary_config_path
    if not path or path == "" then
        return nil, "primary config path not set"
    end
    if config.primary_config_ext ~= "json" then
        return nil, "primary config is not json"
    end
    return config.export_astra_file(path)
end

function config.restore_primary_config_from_snapshot(snapshot_path)
    local path = config.primary_config_path
    if not path or path == "" then
        return nil, "primary config path not set"
    end
    if config.primary_config_ext ~= "json" then
        return nil, "primary config is not json"
    end
    if not snapshot_path or snapshot_path == "" then
        return nil, "missing snapshot path"
    end
    local content, err = read_file(snapshot_path)
    if not content then
        return nil, err
    end
    return write_file_atomic(path, content)
end

local function default_config_json()
    return [[
{
  "settings": {},
  "users": {},
  "make_stream": [],
  "dvb_tune": [],
  "splitters": [],
  "softcam": []
}
]]
end

local function default_config_lua()
    return [[
return {
    settings = {},
    users = {},
    make_stream = {},
    dvb_tune = {},
    splitters = {},
    softcam = {},
}
]]
end

local function write_file(path, content)
    local file, err = io.open(path, "wb")
    if not file then
        return nil, err
    end
    file:write(content)
    file:close()
    return true
end

function config.ensure_config_file(path)
    if not path or path == "" then
        return nil, "empty path"
    end
    local stat = utils.stat(path)
    if stat and not stat.error then
        if stat.type == "file" then
            return true, false
        end
        return nil, "config path is not a file"
    end

    local ext = path_extension(path)
    if ext == "lua" then
        local ok, err = write_file(path, default_config_lua())
        if not ok then
            return nil, err
        end
        return true, true
    end
    if ext == "json" then
        local ok, err = write_file(path, default_config_json())
        if not ok then
            return nil, err
        end
        return true, true
    end
    return nil, "unsupported config format"
end

local function collect_lua_payload(env, result)
    local payload = type(result) == "table" and result or {}
    if payload.gid == nil and env.gid ~= nil then
        payload.gid = env.gid
    end
    if payload.settings == nil and type(env.settings) == "table" then
        payload.settings = env.settings
    end
    if payload.users == nil and type(env.users) == "table" then
        payload.users = env.users
    end
    if payload.make_stream == nil and type(env.make_stream) == "table" then
        payload.make_stream = env.make_stream
    end
    if payload.streams == nil and type(env.streams) == "table" then
        payload.streams = env.streams
    end
    if payload.dvb_tune == nil and type(env.dvb_tune) == "table" then
        payload.dvb_tune = env.dvb_tune
    end
    if payload.adapters == nil and type(env.adapters) == "table" then
        payload.adapters = env.adapters
    end
    if payload.softcam == nil and type(env.softcam) == "table" then
        payload.softcam = env.softcam
    end
    return payload
end

local function load_lua_config(path)
    local env = setmetatable({}, { __index = _G })
    env._G = env
    env.dofile = function(value)
        local chunk, err = loadfile(value, "t", env)
        if not chunk then
            error(err, 0)
        end
        return chunk()
    end
    local chunk, err = loadfile(path, "t", env)
    if not chunk then
        return nil, err
    end
    local ok, result = pcall(chunk)
    if not ok then
        return nil, result
    end
    local payload = collect_lua_payload(env, result)
    if next(payload) == nil then
        return nil, "invalid lua config"
    end
    return payload
end

local function load_json_config(path)
    local file, err = io.open(path, "rb")
    if not file then
        return nil, err
    end
    local content = file:read("*a")
    file:close()
    if not content or content == "" then
        return nil, "empty file"
    end
    local ok, payload = pcall(json.decode, content)
    if not ok then
        return nil, "invalid json: " .. tostring(payload)
    end
    if type(payload) ~= "table" then
        return nil, "invalid json"
    end
    return payload
end

local function read_astra_payload(path)
    if not path or path == "" then
        return nil, "empty path"
    end
    local ext = path_extension(path)
    if ext == "lua" then
        return load_lua_config(path)
    end
    return load_json_config(path)
end

local function validate_astra_payload(payload)
    if type(payload) ~= "table" then
        return nil, "invalid config"
    end
    local function check_table(value, key)
        if value ~= nil and type(value) ~= "table" then
            return nil, "invalid " .. key
        end
        return true
    end
    local ok, err = check_table(payload.settings, "settings")
    if not ok then return nil, err end
    ok, err = check_table(payload.users, "users")
    if not ok then return nil, err end
    ok, err = check_table(payload.make_stream, "make_stream")
    if not ok then return nil, err end
    ok, err = check_table(payload.streams, "streams")
    if not ok then return nil, err end
    ok, err = check_table(payload.dvb_tune, "dvb_tune")
    if not ok then return nil, err end
    ok, err = check_table(payload.adapters, "adapters")
    if not ok then return nil, err end
    ok, err = check_table(payload.splitters, "splitters")
    if not ok then return nil, err end
    ok, err = check_table(payload.softcam, "softcam")
    if not ok then return nil, err end
    return true
end

function config.read_payload(path)
    return read_astra_payload(path)
end

function config.validate_payload(payload)
    return validate_astra_payload(payload)
end

local function lint_list_shape(list, label, warnings)
    if type(list) ~= "table" then
        return
    end
    if #list == 0 and next(list) ~= nil then
        warnings[#warnings + 1] = label .. " should be an array"
    end
end

local function lint_stream_list(list, label, warnings)
    if type(list) ~= "table" then
        return
    end
    lint_list_shape(list, label, warnings)
    for idx, entry in ipairs(list) do
        if type(entry) ~= "table" then
            warnings[#warnings + 1] = label .. "[" .. idx .. "] should be an object"
        else
            if entry.id == nil or tostring(entry.id) == "" then
                warnings[#warnings + 1] = label .. "[" .. idx .. "] missing id"
            end
            if entry.input ~= nil and type(entry.input) ~= "string" and type(entry.input) ~= "table" then
                warnings[#warnings + 1] = label .. "[" .. idx .. "] input should be string or array"
            end
            local stype = tostring(entry.type or ""):lower()
            if stype == "transcode" or stype == "ffmpeg" then
                local tc = entry.transcode or {}
                if type(tc.outputs) ~= "table" or #tc.outputs == 0 then
                    warnings[#warnings + 1] = label .. "[" .. idx .. "] transcode.outputs is required"
                else
                    for oidx, out in ipairs(tc.outputs) do
                        if type(out) ~= "table" or not out.url or out.url == "" then
                            warnings[#warnings + 1] = label .. "[" .. idx .. "] outputs[" .. oidx .. "] missing url"
                        end
                    end
                end
            end

            if entry.mpts == true then
                local mpts = type(entry.mpts_config) == "table" and entry.mpts_config or {}
                local nit = type(mpts.nit) == "table" and mpts.nit or {}
                local adv = type(mpts.advanced) == "table" and mpts.advanced or {}
                local spts_only = adv.spts_only ~= false

                local services = entry.mpts_services
                if type(services) ~= "table" or #services == 0 then
                    if entry.input ~= nil then
                        warnings[#warnings + 1] = label .. "[" .. idx .. "] mpts_services is empty; inputs will be used without per-service metadata"
                    else
                        warnings[#warnings + 1] = label .. "[" .. idx .. "] mpts_services is required for MPTS"
                    end
                else
                    local pnr_seen = {}
                    local input_seen = {}
                    for sidx, svc in ipairs(services) do
                        if type(svc) ~= "table" then
                            warnings[#warnings + 1] = label .. "[" .. idx .. "].mpts_services[" .. sidx .. "] should be an object"
                        else
                            local input = svc.input
                            if input == nil or tostring(input) == "" then
                                warnings[#warnings + 1] = label .. "[" .. idx .. "].mpts_services[" .. sidx .. "] missing input"
                            else
                                local key = tostring(input):lower()
                                if input_seen[key] then
                                    if spts_only then
                                        warnings[#warnings + 1] = label .. "[" .. idx .. "] duplicate mpts input (spts_only=true): " .. tostring(input)
                                    else
                                        warnings[#warnings + 1] = label .. "[" .. idx .. "] duplicate mpts input (shared socket): " .. tostring(input)
                                    end
                                end
                                input_seen[key] = true
                            end

                            local pnr = tonumber(svc.pnr)
                            if pnr then
                                if pnr_seen[pnr] then
                                    warnings[#warnings + 1] = label .. "[" .. idx .. "] duplicate PNR: " .. tostring(pnr)
                                end
                                pnr_seen[pnr] = true
                            end
                        end
                    end
                end

                local delivery = tostring(nit.delivery or ""):lower()
                local lcn_version = nit.lcn_version
                local lcn_tags = nit.lcn_descriptor_tags
                if delivery ~= "" then
                    if delivery == "cable" or delivery == "dvb-c" or delivery == "dvb_c" then
                        if nit.frequency == nil then
                            warnings[#warnings + 1] = label .. "[" .. idx .. "] nit.frequency is required for DVB-C delivery"
                        end
                        if nit.symbolrate == nil then
                            warnings[#warnings + 1] = label .. "[" .. idx .. "] nit.symbolrate is required for DVB-C delivery"
                        end
                        if nit.modulation == nil or tostring(nit.modulation) == "" then
                            warnings[#warnings + 1] = label .. "[" .. idx .. "] nit.modulation is required for DVB-C delivery"
                        end
                    else
                        warnings[#warnings + 1] = label .. "[" .. idx .. "] nit.delivery is not supported (only DVB-C is generated)"
                    end
                end
                if lcn_tags ~= nil then
                    if type(lcn_tags) == "table" then
                        for _, value in ipairs(lcn_tags) do
                            local tag = tonumber(value)
                            if tag == nil or tag < 1 or tag > 255 then
                                warnings[#warnings + 1] = label .. "[" .. idx .. "] nit.lcn_descriptor_tags contains invalid tag"
                                break
                            end
                        end
                    elseif type(lcn_tags) == "string" then
                        for token in string.gmatch(lcn_tags, "[^,%s]+") do
                            local tag = tonumber(token)
                            if tag == nil or tag < 1 or tag > 255 then
                                warnings[#warnings + 1] = label .. "[" .. idx .. "] nit.lcn_descriptor_tags contains invalid tag"
                                break
                            end
                        end
                    else
                        warnings[#warnings + 1] = label .. "[" .. idx .. "] nit.lcn_descriptor_tags should be string or array"
                    end
                    if nit.lcn_descriptor_tag ~= nil then
                        warnings[#warnings + 1] = label .. "[" .. idx .. "] nit.lcn_descriptor_tags overrides nit.lcn_descriptor_tag"
                    end
                end
                if lcn_version ~= nil then
                    local value = tonumber(lcn_version)
                    if value == nil or value < 0 or value > 31 then
                        warnings[#warnings + 1] = label .. "[" .. idx .. "] nit.lcn_version must be 0..31"
                    end
                    if adv.nit_version ~= nil then
                        warnings[#warnings + 1] = label .. "[" .. idx .. "] nit.lcn_version ignored because advanced.nit_version is set"
                    end
                end
                local pass_enabled = adv.pass_nit == true or adv.pass_sdt == true or adv.pass_eit == true or adv.pass_tdt == true
                if pass_enabled and type(entry.mpts_services) == "table" and #entry.mpts_services > 1 then
                    warnings[#warnings + 1] = label .. "[" .. idx .. "] pass_* is intended for single-service MPTS"
                end
                -- Валидация auto-probe: нужен input и допустимая длительность.
                if adv.auto_probe == true then
                    if type(entry.mpts_services) == "table" and #entry.mpts_services > 0 then
                        warnings[#warnings + 1] = label .. "[" .. idx .. "] advanced.auto_probe ignored when mpts_services is set"
                    end
                    local duration = tonumber(adv.auto_probe_duration_sec or adv.auto_probe_duration)
                    if duration and (duration < 1 or duration > 10) then
                        warnings[#warnings + 1] = label .. "[" .. idx .. "] advanced.auto_probe_duration_sec must be 1..10"
                    end
                    if entry.input == nil then
                        warnings[#warnings + 1] = label .. "[" .. idx .. "] advanced.auto_probe requires input list"
                    end
                end
            end
        end
    end
end

local function lint_adapter_list(list, label, warnings)
    if type(list) ~= "table" then
        return
    end
    lint_list_shape(list, label, warnings)
    for idx, entry in ipairs(list) do
        if type(entry) ~= "table" then
            warnings[#warnings + 1] = label .. "[" .. idx .. "] should be an object"
        else
            if entry.id == nil or tostring(entry.id) == "" then
                warnings[#warnings + 1] = label .. "[" .. idx .. "] missing id"
            end
        end
    end
end

local function lint_splitter_list(list, label, warnings)
    if type(list) ~= "table" then
        return
    end
    lint_list_shape(list, label, warnings)
    for idx, entry in ipairs(list) do
        if type(entry) ~= "table" then
            warnings[#warnings + 1] = label .. "[" .. idx .. "] should be an object"
        else
            if entry.id == nil or tostring(entry.id) == "" then
                warnings[#warnings + 1] = label .. "[" .. idx .. "] missing id"
            end
            if entry.port == nil then
                warnings[#warnings + 1] = label .. "[" .. idx .. "] missing port"
            end
            local links = entry.links
            if links ~= nil and type(links) ~= "table" then
                warnings[#warnings + 1] = label .. "[" .. idx .. "] links should be an array"
            elseif type(links) == "table" then
                lint_list_shape(links, label .. "[" .. idx .. "].links", warnings)
                for lidx, link in ipairs(links) do
                    if type(link) ~= "table" then
                        warnings[#warnings + 1] = label .. "[" .. idx .. "].links[" .. lidx .. "] should be an object"
                    else
                        if link.id == nil or tostring(link.id) == "" then
                            warnings[#warnings + 1] = label .. "[" .. idx .. "].links[" .. lidx .. "] missing id"
                        end
                        if link.url == nil or tostring(link.url) == "" then
                            warnings[#warnings + 1] = label .. "[" .. idx .. "].links[" .. lidx .. "] missing url"
                        end
                    end
                end
            end

            local allow = entry.allow
            if allow ~= nil and type(allow) ~= "table" then
                warnings[#warnings + 1] = label .. "[" .. idx .. "] allow should be an array"
            elseif type(allow) == "table" then
                lint_list_shape(allow, label .. "[" .. idx .. "].allow", warnings)
                for aidx, rule in ipairs(allow) do
                    if type(rule) ~= "table" then
                        warnings[#warnings + 1] = label .. "[" .. idx .. "].allow[" .. aidx .. "] should be an object"
                    else
                        if rule.id == nil or tostring(rule.id) == "" then
                            warnings[#warnings + 1] = label .. "[" .. idx .. "].allow[" .. aidx .. "] missing id"
                        end
                        if rule.kind == nil or tostring(rule.kind) == "" then
                            warnings[#warnings + 1] = label .. "[" .. idx .. "].allow[" .. aidx .. "] missing kind"
                        end
                        if rule.value == nil or tostring(rule.value) == "" then
                            warnings[#warnings + 1] = label .. "[" .. idx .. "].allow[" .. aidx .. "] missing value"
                        end
                    end
                end
            end
        end
    end
end

local function lint_softcam_list(list, warnings)
    if type(list) ~= "table" then
        return
    end
    lint_list_shape(list, "softcam", warnings)
    for idx, entry in ipairs(list) do
        if type(entry) ~= "table" then
            warnings[#warnings + 1] = "softcam[" .. idx .. "] should be an object"
        else
            if entry.id == nil or tostring(entry.id) == "" then
                warnings[#warnings + 1] = "softcam[" .. idx .. "] missing id"
            end
            if entry.type == nil or tostring(entry.type) == "" then
                warnings[#warnings + 1] = "softcam[" .. idx .. "] missing type"
            end
        end
    end
end

function config.lint_payload(payload)
    local errors = {}
    local warnings = {}
    local ok, err = validate_astra_payload(payload)
    if not ok then
        errors[#errors + 1] = err or "invalid config"
        return errors, warnings
    end

    if type(payload.settings) == "table" then
        for key, _ in pairs(payload.settings) do
            if type(key) ~= "string" then
                warnings[#warnings + 1] = "settings key should be string"
                break
            end
        end
    end

    if type(payload.users) == "table" then
        for username, user in pairs(payload.users) do
            if type(username) ~= "string" or username == "" then
                warnings[#warnings + 1] = "users has non-string key"
            end
            if type(user) ~= "table" then
                warnings[#warnings + 1] = "users." .. tostring(username) .. " should be an object"
            else
                if user.password == nil and user.password_hash == nil and user.cipher == nil then
                    warnings[#warnings + 1] = "users." .. tostring(username) .. " missing password/hash"
                end
            end
        end
    end

    lint_stream_list(payload.make_stream, "make_stream", warnings)
    lint_stream_list(payload.streams, "streams", warnings)
    lint_adapter_list(payload.dvb_tune, "dvb_tune", warnings)
    lint_adapter_list(payload.adapters, "adapters", warnings)
    lint_splitter_list(payload.splitters, "splitters", warnings)
    lint_softcam_list(payload.softcam, warnings)

    return errors, warnings
end

function config.import_astra(payload, opts)
    local ok, err = validate_astra_payload(payload)
    if not ok then
        return nil, err
    end

    opts = opts or {}
    local mode = opts.mode or "merge"
    local replace = (mode == "replace")
    local replace_users = replace and payload.users ~= nil
    local replace_splitters = replace and payload.splitters ~= nil

    local function do_import()
        if replace then
            db_exec(config.db, "DELETE FROM streams;")
            db_exec(config.db, "DELETE FROM adapters;")
            db_exec(config.db, "DELETE FROM settings;")
            if replace_users then
                db_exec(config.db, "DELETE FROM users;")
                db_exec(config.db, "DELETE FROM sessions;")
            end
            if replace_splitters then
                db_exec(config.db, "DELETE FROM splitter_links;")
                db_exec(config.db, "DELETE FROM splitter_allow;")
                db_exec(config.db, "DELETE FROM splitter_instances;")
            end
        end

        local summary = {
            settings = 0,
            users = 0,
            adapters = 0,
            streams = 0,
            softcam = 0,
            splitters = 0,
            splitter_links = 0,
            splitter_allow = 0,
        }

        if payload.gid ~= nil then
            config.set_setting("gid", payload.gid)
            summary.settings = summary.settings + 1
        end

        if type(payload.settings) == "table" then
            for key, value in pairs(payload.settings) do
                config.set_setting(key, value)
                summary.settings = summary.settings + 1
            end
            if payload.settings.http_play_stream ~= nil
                and payload.settings.http_play_allow == nil
            then
                config.set_setting("http_play_allow", normalize_bool(payload.settings.http_play_stream, false))
                summary.settings = summary.settings + 1
            end
        end

        if type(payload.users) == "table" then
            for key, value in pairs(payload.users) do
                local entry = value
                local username = key
                if type(value) ~= "table" then
                    entry = {}
                end
                if entry.username then
                    username = entry.username
                end
                if username and username ~= "" and normalize_bool(entry.enable, true) then
                    local is_admin = tonumber(entry.type) == 1
                    local enabled = normalize_bool(entry.enable, true)
                    local cipher = entry.cipher
                    if entry.password then
                        local salt = random_token(12)
                        local hash = hash_password(entry.password, salt)
                        if config.upsert_user(username, hash, salt, is_admin, { replace = replace_users }) then
                            summary.users = summary.users + 1
                        end
                    elseif cipher then
                        if config.upsert_user(username, string.lower(tostring(cipher)), "legacy:md5", is_admin, { replace = replace_users }) then
                            summary.users = summary.users + 1
                        end
                    elseif entry.password_hash and entry.password_salt then
                        if config.upsert_user(username, tostring(entry.password_hash), tostring(entry.password_salt), is_admin, { replace = replace_users }) then
                            summary.users = summary.users + 1
                        end
                    end
                    if config.update_user then
                        config.update_user(username, {
                            is_admin = is_admin,
                            enabled = enabled,
                            comment = entry.comment,
                        })
                    end
                end
            end
        end

        local adapters = payload.dvb_tune or payload.adapters
        if type(adapters) == "table" then
            local idx = 0
            for key, value in pairs(adapters) do
                if type(key) == "number" then
                    idx = key
                else
                    idx = idx + 1
                end
                if type(value) == "table" then
                    local fallback = (type(key) == "string" and key) or ("adapter" .. tostring(idx))
                    local id = import_id(value, fallback)
                    local enabled = normalize_bool(value.enable, true)
                    config.upsert_adapter(id, enabled, value)
                    summary.adapters = summary.adapters + 1
                end
            end
        end

        local streams = payload.make_stream or payload.streams
        if type(streams) == "table" then
            local idx = 0
            for key, value in pairs(streams) do
                if type(key) == "number" then
                    idx = key
                else
                    idx = idx + 1
                end
                if type(value) == "table" then
                    local fallback = (type(key) == "string" and key) or ("stream" .. tostring(idx))
                    local id = import_id(value, fallback)
                    local enabled = normalize_bool(value.enable, true)
                    config.upsert_stream(id, enabled, value)
                    summary.streams = summary.streams + 1
                end
            end
        end

        local splitters = payload.splitters
        if type(splitters) == "table" then
            local idx = 0
            for key, value in pairs(splitters) do
                if type(key) == "number" then
                    idx = key
                else
                    idx = idx + 1
                end
                if type(value) == "table" then
                    local fallback = (type(key) == "string" and key) or ("splitter" .. tostring(idx))
                    local id = import_id(value, fallback)
                    config.upsert_splitter(id, value)
                    summary.splitters = summary.splitters + 1

                    local links = value.links
                    if type(links) == "table" then
                        db_exec(config.db, "DELETE FROM splitter_links WHERE splitter_id='" ..
                            sql_escape(id) .. "';")
                        local link_idx = 0
                        for link_key, link in pairs(links) do
                            if type(link_key) == "number" then
                                link_idx = link_key
                            else
                                link_idx = link_idx + 1
                            end
                            if type(link) == "table" then
                                local link_fallback = (type(link_key) == "string" and link_key)
                                    or (id .. "_link" .. tostring(link_idx))
                                local link_id = import_id(link, link_fallback)
                                config.upsert_splitter_link(id, link_id, link)
                                summary.splitter_links = summary.splitter_links + 1
                            end
                        end
                    end

                    local allow = value.allow
                    if type(allow) == "table" then
                        db_exec(config.db, "DELETE FROM splitter_allow WHERE splitter_id='" ..
                            sql_escape(id) .. "';")
                        local allow_idx = 0
                        for allow_key, rule in pairs(allow) do
                            if type(allow_key) == "number" then
                                allow_idx = allow_key
                            else
                                allow_idx = allow_idx + 1
                            end
                            if type(rule) == "table" then
                                local rule_fallback = (type(allow_key) == "string" and allow_key)
                                    or (id .. "_allow" .. tostring(allow_idx))
                                local rule_id = import_id(rule, rule_fallback)
                                config.add_splitter_allow(id, rule_id, rule.kind, rule.value)
                                summary.splitter_allow = summary.splitter_allow + 1
                            end
                        end
                    end
                end
            end
        end

        local softcam = payload.softcam
        if type(softcam) == "table" then
            config.set_setting("softcam", import_list(softcam))
            summary.softcam = #softcam
        end

        config.ensure_admin()
        return summary
    end

    if opts.transaction then
        return config.with_transaction(do_import)
    end
    return do_import()
end

function config.import_astra_file(path, opts)
    local payload, err = read_astra_payload(path)
    if not payload then
        return nil, err
    end
    return config.import_astra(payload, opts)
end

function config.export_astra(opts)
    opts = opts or {}
    local include_settings = opts.include_settings ~= false
    local include_users = opts.include_users ~= false
    local include_streams = opts.include_streams ~= false
    local include_adapters = opts.include_adapters ~= false
    local include_softcam = opts.include_softcam ~= false
    local include_splitters = opts.include_splitters ~= false

    local payload = {}

    if include_settings and config.list_settings then
        local settings = copy_table(config.list_settings() or {})
        if settings.gid ~= nil then
            payload.gid = settings.gid
            settings.gid = nil
        end
        if include_softcam and settings.softcam ~= nil then
            payload.softcam = settings.softcam
            settings.softcam = nil
        end
        if next(settings) ~= nil then
            payload.settings = settings
        end
    elseif include_softcam and config.get_setting then
        local softcam = config.get_setting("softcam")
        if softcam ~= nil then
            payload.softcam = copy_table(softcam)
        end
    end

    if include_users then
        local rows = db_query(config.db,
            "SELECT username, password_hash, password_salt, is_admin, enabled, comment " ..
            "FROM users ORDER BY username;")
        local users = {}
        for _, row in ipairs(rows) do
            local entry = {
                username = row.username,
                enable = (tonumber(row.enabled) or 0) ~= 0,
                type = tonumber(row.is_admin) or 0,
            }
            if row.comment and row.comment ~= "" then
                entry.comment = row.comment
            end
            if row.password_salt and tostring(row.password_salt):find("^legacy:") == 1 then
                entry.cipher = string.lower(tostring(row.password_hash or ""))
            else
                entry.password_hash = row.password_hash
                entry.password_salt = row.password_salt
            end
            users[row.username] = entry
        end
        payload.users = users
    end

    if include_streams and config.list_streams then
        local rows = config.list_streams()
        local streams = {}
        for _, row in ipairs(rows) do
            local cfg = copy_table(row.config or {})
            cfg.id = cfg.id or row.id
            cfg.enable = (tonumber(row.enabled) or 0) ~= 0
            table.insert(streams, cfg)
        end
        payload.make_stream = streams
    end

    if include_adapters and config.list_adapters then
        local rows = config.list_adapters()
        local adapters = {}
        for _, row in ipairs(rows) do
            local cfg = copy_table(row.config or {})
            cfg.id = cfg.id or row.id
            cfg.enable = (tonumber(row.enabled) or 0) ~= 0
            table.insert(adapters, cfg)
        end
        payload.dvb_tune = adapters
    end

    if include_splitters and config.list_splitters then
        local rows = config.list_splitters()
        local splitters = {}
        for _, row in ipairs(rows) do
            local entry = {
                id = row.id,
                enable = (tonumber(row.enable) or 0) ~= 0,
                port = tonumber(row.port) or 0,
            }
            if row.name and row.name ~= "" then
                entry.name = row.name
            end
            if row.in_interface and row.in_interface ~= "" then
                entry.in_interface = row.in_interface
            end
            if row.out_interface and row.out_interface ~= "" then
                entry.out_interface = row.out_interface
            end
            if row.logtype and row.logtype ~= "" then
                entry.logtype = row.logtype
            end
            if row.logpath and row.logpath ~= "" then
                entry.logpath = row.logpath
            end
            if row.config_path and row.config_path ~= "" then
                entry.config_path = row.config_path
            end

            local links = {}
            for _, link in ipairs(config.list_splitter_links(row.id)) do
                local link_entry = {
                    id = link.id,
                    enable = (tonumber(link.enable) or 0) ~= 0,
                    url = link.url,
                }
                if link.bandwidth ~= nil then
                    link_entry.bandwidth = tonumber(link.bandwidth)
                end
                if link.buffering ~= nil then
                    link_entry.buffering = tonumber(link.buffering)
                end
                table.insert(links, link_entry)
            end
            entry.links = links

            local allow = {}
            for _, rule in ipairs(config.list_splitter_allow(row.id)) do
                table.insert(allow, {
                    id = rule.id,
                    kind = rule.kind,
                    value = rule.value,
                })
            end
            entry.allow = allow

            table.insert(splitters, entry)
        end
        payload.splitters = splitters
    end

    return payload
end

function config.export_astra_file(path, opts)
    if not path or path == "" then
        return nil, "empty path"
    end
    local payload = config.export_astra(opts)
    local encoded
    if json and type(json.encode_pretty) == "function" then
        encoded = json.encode_pretty(payload)
    else
        encoded = json.encode(payload)
    end
    local ok, err = write_file_atomic(path, encoded)
    if not ok then
        return nil, err
    end
    return payload
end
