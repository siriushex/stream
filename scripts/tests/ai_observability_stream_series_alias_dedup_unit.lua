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
    list_ai_metrics = function(opts)
        local res = tonumber(opts and opts.resolution_sec) or 0
        if res ~= 10 then
            return {}
        end
        return {
            {
                ts_bucket = now - 30,
                scope = "stream",
                scope_id = "s1",
                metric_key = "stream.bitrate_kbps.avg",
                value = 3333,
            },
            {
                ts_bucket = now - 30,
                scope = "stream",
                scope_id = "s1",
                metric_key = "bitrate_kbps",
                value = 1111,
            },
            {
                ts_bucket = now - 20,
                scope = "stream",
                scope_id = "s1",
                metric_key = "bitrate_kbps",
                value = 2222,
            },
        }
    end,
}

local result, err = ai_observability.get_stream_series({
    stream_id = "s1",
    range_sec = 3600,
    resolution = "10s",
    metrics = { "stream.bitrate_kbps.avg" },
    max_points = 1200,
})

assert_true(result ~= nil, err or "expected result")
local series = result.series and result.series["stream.bitrate_kbps.avg"] or {}
assert_true(type(series) == "table" and #series == 2, "expected alias/canonical dedup by ts")
table.sort(series, function(a, b) return (a.ts or 0) < (b.ts or 0) end)
assert_true(tonumber(series[1].value) == 3333, "expected canonical metric priority when both exist")
assert_true(tonumber(series[2].value) == 2222, "expected alias fallback when canonical is absent")

print("ai_observability_stream_series_alias_dedup_unit: ok")
astra.exit()
