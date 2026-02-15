log.set({ debug = true })

dofile("scripts/base.lua")
dofile("scripts/config.lua")

local function assert_true(cond, msg)
    if not cond then
        error(msg or "assert failed")
    end
end

local executed = {}
config.db = {
    exec = function(self, sql)
        table.insert(executed, tostring(sql or ""))
        return true
    end,
}

-- Force compatibility path (older SQLite without UPSERT).
config.supports_upsert = false

executed = {}
config.set_setting("demo_key", { a = 1 })
assert_true(#executed == 1, "expected single statement for set_setting in compat mode")
assert_true(executed[1]:find("INSERT OR REPLACE INTO settings", 1, true) ~= nil,
    "expected INSERT OR REPLACE for settings")
assert_true(executed[1]:find("SELECT", 1, true) == nil, "unexpected SELECT in compat set_setting")

executed = {}
config.upsert_stream("demo_stream", true, { name = "Demo stream" })
assert_true(#executed == 1, "expected single statement for upsert_stream in compat mode")
assert_true(executed[1]:find("INSERT OR REPLACE INTO streams", 1, true) ~= nil,
    "expected INSERT OR REPLACE for streams")
assert_true(executed[1]:find("SELECT", 1, true) == nil, "unexpected SELECT in compat upsert_stream")

executed = {}
config.upsert_adapter("demo_adapter", true, { name = "Demo adapter" })
assert_true(#executed == 1, "expected single statement for upsert_adapter in compat mode")
assert_true(executed[1]:find("INSERT OR REPLACE INTO adapters", 1, true) ~= nil,
    "expected INSERT OR REPLACE for adapters")
assert_true(executed[1]:find("SELECT", 1, true) == nil, "unexpected SELECT in compat upsert_adapter")

print("sqlite_compat_replace_unit: ok")
astra.exit()

