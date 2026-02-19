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

local created = { base = 0, highres = 0, cleanup = 0 }
timer = function(opts)
    if opts and opts.interval == 60 then
        created.base = created.base + 1
    elseif opts and opts.interval == 10 then
        created.highres = created.highres + 1
    elseif opts and opts.interval == 86400 then
        created.cleanup = created.cleanup + 1
    end
    return { close = function() end }
end

config = {
    get_setting = function(key)
        if key == "observability_enabled" then return true end
        if key == "ai_metrics_on_demand" then return false end
        if key == "ai_logs_retention_days" then return 7 end
        if key == "ai_metrics_retention_days" then return 14 end
        if key == "ai_rollup_interval_sec" then return 60 end
        return nil
    end,
    upsert_ai_metrics_batch = function(_rows)
        return true
    end,
}

ai_observability.configure()

assert_true(ai_observability.state.metrics_on_demand == false, "expected on-demand disabled")
assert_true(ai_observability.state.metrics_retention_days == 14, "expected metrics retention preserved")
assert_true(ai_observability.state.collection_enabled == true, "expected collection enabled")
assert_true(created.base == 1, "expected base rollup timer")
assert_true(created.highres == 1, "expected highres timer")
assert_true(created.cleanup == 1, "expected cleanup timer")

print("ai_observability_rollup_config_unit: ok")
astra.exit()
