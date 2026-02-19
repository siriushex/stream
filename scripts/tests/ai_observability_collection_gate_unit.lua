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

local wrote_logs = 0
config = {
    get_setting = function(key)
        if key == "observability_enabled" then return false end
        if key == "ai_logs_retention_days" then return 7 end
        if key == "ai_metrics_retention_days" then return 30 end
        if key == "ai_metrics_on_demand" then return true end
        return nil
    end,
    add_ai_log_event = function(_)
        wrote_logs = wrote_logs + 1
        return true
    end,
    list_ai_log_events = function(_)
        return {}
    end,
}

runtime = {
    list_status = function()
        return {
            s1 = {
                id = "s1",
                bitrate = 2500,
                on_air = true,
            },
        }
    end,
}

ai_observability.configure()
assert_true(ai_observability.state.collection_enabled == false, "expected collection disabled")
assert_true(created.base == 0 and created.highres == 0 and created.cleanup == 0, "timers must not be created")

ai_observability.ingest_alert({
    level = "ERROR",
    stream_id = "s1",
    code = "TEST",
    message = "should be ignored",
})
ai_observability.ingest_stream_sample("s1", {
    ts = os.time(),
    bitrate_kbps = 1000,
    cc_errors = 1,
    pes_errors = 1,
    on_air = true,
})
assert_true(wrote_logs == 0, "ingest must not write when collection is disabled")

local metrics = ai_observability.get_on_demand_metrics(3600, 60, "stream", "s1")
assert_true(type(metrics) == "table", "expected metrics payload")
assert_true(type(metrics.items) == "table" and #metrics.items == 0,
    "read-only mode must not inject runtime metrics")
assert_true(type(metrics.summary) == "table" and next(metrics.summary) == nil,
    "summary must remain empty when collection is disabled and no history exists")

print("ai_observability_collection_gate_unit: ok")
astra.exit()
