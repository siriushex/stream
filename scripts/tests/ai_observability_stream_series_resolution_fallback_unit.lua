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

config = {
    list_ai_metrics = function(opts)
        local res = tonumber(opts and opts.resolution_sec) or 0
        if res == 10 then
            return {}
        end
        if res == 60 then
            local now = os.time()
            return {
                {
                    ts_bucket = now - 120,
                    scope = "stream",
                    scope_id = "s1",
                    metric_key = "stream.bitrate_kbps.avg",
                    value = 1500,
                },
                {
                    ts_bucket = now - 60,
                    scope = "stream",
                    scope_id = "s1",
                    metric_key = "stream.bitrate_kbps.avg",
                    value = 1600,
                },
            }
        end
        return {}
    end,
}

local result, err = ai_observability.get_stream_series({
    stream_id = "s1",
    range_sec = 3600,
    resolution = "auto",
    metrics = { "stream.bitrate_kbps.avg" },
    max_points = 1200,
})

assert_true(result ~= nil, err or "expected result")
assert_true(result.meta and result.meta.resolution_used == "60s",
    "expected auto fallback to 60s when 10s has no data")
local series = result.series and result.series["stream.bitrate_kbps.avg"] or {}
assert_true(type(series) == "table" and #series == 2, "expected two points from fallback resolution")

print("ai_observability_stream_series_resolution_fallback_unit: ok")
astra.exit()
