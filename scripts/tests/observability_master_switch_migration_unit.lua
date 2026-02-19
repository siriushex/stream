log.set({ debug = true })

dofile("scripts/base.lua")
dofile("scripts/config.lua")

local function assert_true(cond, msg)
    if not cond then
        error(msg or "assert failed")
    end
end

local function run_case(name, store, expected)
    local writes = {}
    config.get_setting = function(key)
        return store[key]
    end
    config.set_setting = function(key, value)
        writes[key] = value
        store[key] = value
    end

    config.migrate_observability_master_switch()
    assert_true(store.observability_enabled == expected,
        string.format("%s: expected observability_enabled=%s got=%s",
            name, tostring(expected), tostring(store.observability_enabled)))
    assert_true(writes.observability_enabled == expected,
        string.format("%s: migration must persist computed value", name))
end

run_case("legacy-active", {
    ai_logs_retention_days = 7,
    ai_metrics_on_demand = true,
    ai_metrics_retention_days = 30,
    observability_system_rollup_enabled = false,
}, true)

run_case("legacy-inactive", {
    ai_logs_retention_days = 0,
    ai_metrics_on_demand = true,
    ai_metrics_retention_days = 0,
    observability_system_rollup_enabled = false,
}, false)

print("observability_master_switch_migration_unit: ok")
astra.exit()
