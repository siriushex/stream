local function script_path(name)
    return "scripts/" .. name
end

log.set({ debug = true })

dofile(script_path("base.lua"))
dofile(script_path("ai_charts.lua"))

local function assert_true(cond, msg)
    if not cond then
        error(msg or "assert failed")
    end
end

local metrics = {
    { metric_key = "total_bitrate_kbps", ts_bucket = os.time(), value = 1234 },
}
local url = ai_charts.build_metric_chart(metrics, "total_bitrate_kbps", "Total bitrate", "rgb(90,170,229)")
assert_true(type(url) == "string" and url:find("quickchart"), "chart url missing")

print("ai_charts_unit: ok")
astra.exit()
