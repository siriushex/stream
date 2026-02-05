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

local now = os.time()
config = {
    list_ai_log_events = function(_)
        return {
            { ts = now - 10, level = "ERROR", component = "STREAM_DOWN", stream_id = "s1" },
            { ts = now - 20, level = "INFO", component = "INPUT_SWITCH", stream_id = "s1" },
            { ts = now - 30, level = "CRITICAL", component = "OUTPUT_ERROR", stream_id = "s2" },
        }
    end,
}

local items = ai_observability.build_metrics_from_logs(3600, 60, "global", "")
assert_true(#items > 0, "expected metrics from logs")

local has_alerts = false
local has_switch = false
local has_down = false
for _, item in ipairs(items) do
    if item.metric_key == "alerts_error" then has_alerts = true end
    if item.metric_key == "input_switch" then has_switch = true end
    if item.metric_key == "streams_down" then has_down = true end
end
assert_true(has_alerts, "alerts_error missing")
assert_true(has_switch, "input_switch missing")
assert_true(has_down, "streams_down missing")

local result = ai_observability.get_on_demand_metrics(3600, 60, "global", "")
assert_true(result and result.items and #result.items > 0, "expected on-demand metrics")
assert_true(result.summary and result.summary.alerts_error ~= nil, "summary missing alerts")

print("ai_observability_unit: ok")
astra.exit()
