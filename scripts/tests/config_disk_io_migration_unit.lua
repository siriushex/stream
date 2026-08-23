log.set({ debug = true })

dofile("scripts/base.lua")
dofile("scripts/config.lua")

-- This fixture targets migration 17 in isolation. Stream 1.3.0 has later
-- migrations whose tables are intentionally outside this focused fixture.
local focused_migrations = {}
for index = 1, 17 do
    focused_migrations[index] = config.migrations[index]
end
config.migrations = focused_migrations

local function assert_true(cond, msg)
    if not cond then
        error(msg or "assert failed")
    end
end

local function run_case(name, has_column)
    local tmp = "/tmp/config_disk_io_migration_unit_" .. name
    os.execute("rm -rf " .. tmp .. " >/dev/null 2>&1 || true")
    os.execute("mkdir -p " .. tmp)

    local db_path = tmp .. "/stream.db"
    local db, err = sqlite.open(db_path)
    assert_true(db ~= nil, err or "sqlite open failed")

    local column_sql = has_column and ", disk_io_json TEXT" or ""
    local ok, exec_err = db:exec([[
        CREATE TABLE schema_version (version INTEGER NOT NULL);
        INSERT INTO schema_version(version) VALUES (16);
        CREATE TABLE system_metrics_rollup (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            ts_bucket INTEGER NOT NULL UNIQUE,
            cpu_usage REAL,
            mem_used_percent REAL,
            disk_used_percent REAL,
            net_json TEXT
        ]] .. column_sql .. [[
        );
    ]])
    assert_true(ok ~= nil, exec_err or "fixture creation failed")

    config.db = db
    config.db_path = db_path
    config.migrate()

    local rows, query_err = db:query("PRAGMA table_info(system_metrics_rollup);")
    assert_true(rows ~= nil, query_err or "table_info failed")
    local count = 0
    for _, row in ipairs(rows) do
        if row.name == "disk_io_json" then
            count = count + 1
        end
    end
    assert_true(count == 1, name .. ": expected exactly one disk_io_json column")

    local version_rows = db:query("SELECT version FROM schema_version LIMIT 1;")
    assert_true(tonumber(version_rows[1].version) == #config.migrations,
        name .. ": schema version was not advanced")
    db:close()
end

run_case("column_missing", false)
run_case("column_present", true)

print("config_disk_io_migration_unit: ok")
astra.exit()
