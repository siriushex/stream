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

runtime = {
    list_status = function()
        return {
            s1 = {
                id = "s1",
                on_air = true,
                bitrate = 1654,
                cc_errors = 2,
                pes_errors = 1,
                last_switch = os.time() - 90,
            },
        }
    end,
}

local built = ai_observability.build_runtime_metrics("stream", "s1", 60, 24 * 3600)
assert_true(built ~= nil, "expected stream runtime metrics")
assert_true(type(built.items) == "table", "expected items table")

local by_key = {}
for _, item in ipairs(built.items) do
    by_key[item.metric_key] = by_key[item.metric_key] or {}
    table.insert(by_key[item.metric_key], item)
end

assert_true(by_key.bitrate_kbps and #by_key.bitrate_kbps > 1, "bitrate_kbps should produce a series")
assert_true(by_key.cc_errors and #by_key.cc_errors > 1, "cc_errors should produce a series")
assert_true(by_key.pes_errors and #by_key.pes_errors > 1, "pes_errors should produce a series")
assert_true(by_key.on_air and #by_key.on_air > 1, "on_air should produce a series")

config = {
    list_ai_log_events = function(_)
        return {}
    end,
}

local result = ai_observability.get_on_demand_metrics(24 * 3600, 60, "stream", "s1")
assert_true(result and type(result.items) == "table", "expected on-demand metrics")
local count_bitrate = 0
for _, item in ipairs(result.items) do
    if item.metric_key == "bitrate_kbps" then
        count_bitrate = count_bitrate + 1
    end
end
assert_true(count_bitrate > 1, "on-demand stream bitrate should not collapse to one point")

print("ai_observability_stream_runtime_series_unit: ok")
astra.exit()
