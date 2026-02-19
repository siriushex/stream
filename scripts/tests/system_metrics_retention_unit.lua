local function script_path(name)
    return "scripts/" .. name
end

log.set({ debug = true })

dofile(script_path("base.lua"))
dofile(script_path("system_metrics.lua"))

local function assert_true(cond, msg)
    if not cond then
        error(msg or "assert failed")
    end
end

timer = function(_opts)
    return { close = function() end }
end

local settings = {
    observability_enabled = true,
    ai_logs_retention_days = 7,
    ai_metrics_on_demand = true,
    observability_system_rollup_enabled = true,
    observability_system_rollup_interval_sec = 60,
    observability_system_include_virtual_ifaces = false,
}

config = {
    get_setting = function(key)
        return settings[key]
    end,
}

system_metrics.configure()
assert_true(system_metrics.state.collection_enabled == true, "expected collection enabled")
assert_true(system_metrics.state.retention_sec == 7 * 86400, "expected retention from logs days")
assert_true(system_metrics.state.retention_source == "logs_days", "expected logs_days retention source")

settings.observability_system_retention_sec = 3600
system_metrics.configure()
assert_true(system_metrics.state.retention_sec == 3600, "expected explicit retention")
assert_true(system_metrics.state.retention_source == "setting", "expected setting retention source")

print("system_metrics_retention_unit: ok")
astra.exit()
