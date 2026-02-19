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

local created = { rollup = 0, prune = 0 }
timer = function(opts)
    if opts and tonumber(opts.interval) == 3600 then
        created.prune = created.prune + 1
    else
        created.rollup = created.rollup + 1
    end
    return { close = function() end }
end

local settings = {
    observability_enabled = false,
    observability_system_rollup_enabled = true,
    observability_system_rollup_interval_sec = 60,
}

config = {
    get_setting = function(key)
        return settings[key]
    end,
}

system_metrics.configure()
assert_true(system_metrics.state.collection_enabled == false, "collection must be disabled")
assert_true(created.rollup == 0 and created.prune == 0, "rollup/prune timers must not start")

local snap = system_metrics.snapshot() or {}
assert_true(snap.enabled == true, "snapshot read path should stay enabled")
assert_true(snap.collection_enabled == false, "snapshot should expose collection flag")

print("system_metrics_collection_gate_unit: ok")
astra.exit()
