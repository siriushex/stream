local function script_path(name)
    return "scripts/" .. name
end

log.set({ debug = true })

dofile(script_path("base.lua"))
dofile(script_path("ai_observability.lua"))

local function assert_true(cond, msg)
    if not cond then
        error(msg or "assert failed")
    end
end

local created = { rollup = 0, cleanup = 0 }
timer = function(opts)
    if opts and opts.interval == 86400 then
        created.cleanup = created.cleanup + 1
    else
        created.rollup = created.rollup + 1
    end
    return { close = function() end }
end

config = {
    get_setting = function(key)
        if key == "ai_metrics_on_demand" then return true end
        if key == "ai_logs_retention_days" then return 7 end
        return nil
    end,
}

ai_observability.configure()

assert_true(ai_observability.state.metrics_on_demand == true, "expected on-demand enabled")
assert_true(ai_observability.state.metrics_retention_days == 0, "expected metrics retention forced to 0")
assert_true(created.rollup == 0, "expected no rollup timer")
assert_true(created.cleanup == 1, "expected cleanup timer")

print("ai_observability_on_demand_config_unit: ok")
astra.exit()

