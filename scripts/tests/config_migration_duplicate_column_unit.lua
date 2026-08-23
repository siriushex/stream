log.set({ debug = true })

dofile("scripts/base.lua")
dofile("scripts/config.lua")

local function assert_true(value, message)
    if not value then
        error(message or "assert_true failed")
    end
end

local tmp = "/tmp/config_migration_duplicate_column_unit"
os.execute("rm -rf " .. tmp .. " >/dev/null 2>&1 || true")
os.execute("mkdir -p " .. tmp)

config.init({
    data_dir = tmp,
    db_path = tmp .. "/stream.db",
})

local first_health_step = #config.migrations - 4
local ok, err = config.db:exec(
    "UPDATE schema_version SET version = " .. tostring(first_health_step - 1) .. ";")
assert_true(ok, "failed to rewind schema version: " .. tostring(err))

config.migrate()
local rows, query_err = config.db:query("SELECT version FROM schema_version LIMIT 1;")
assert_true(rows ~= nil, "schema version query failed: " .. tostring(query_err))
assert_true(tonumber(rows[1] and rows[1].version) == #config.migrations,
    "duplicate-column recovery did not advance schema version")

print("config_migration_duplicate_column_unit: ok")
astra.exit()
