-- AstralAI charts helper (QuickChart URLs)

ai_charts = ai_charts or {}

local function url_encode(value)
    local text = tostring(value or "")
    return text:gsub("([^%w%-%._~])", function(c)
        return string.format("%%%02X", string.byte(c))
    end)
end

local function downsample_points(points, max_points)
    if #points <= max_points then
        return points
    end
    local step = math.ceil(#points / max_points)
    local out = {}
    for i = 1, #points, step do
        table.insert(out, points[i])
    end
    return out
end

function ai_charts.build_metric_chart(metrics, metric_key, title, color, opts)
    if not metrics or #metrics == 0 then
        return nil
    end
    local points = {}
    for _, row in ipairs(metrics) do
        if row.metric_key == metric_key and row.ts_bucket then
            table.insert(points, { ts = row.ts_bucket, value = tonumber(row.value) or 0 })
        end
    end
    table.sort(points, function(a, b) return a.ts < b.ts end)
    if #points == 0 then
        return nil
    end
    points = downsample_points(points, 120)
    local labels = {}
    local values = {}
    for _, pt in ipairs(points) do
        table.insert(labels, os.date("%H:%M", pt.ts))
        table.insert(values, pt.value)
    end
    local chart = {
        type = "line",
        data = {
            labels = labels,
            datasets = {
                {
                    label = title or metric_key,
                    data = values,
                    borderColor = color or "rgb(90,170,229)",
                    backgroundColor = color and (color:gsub("rgb%((%d+),(%d+),(%d+)%)", "rgba(%1,%2,%3,0.25)"))
                        or "rgba(90,170,229,0.25)",
                    fill = true,
                    lineTension = 0.2,
                    pointRadius = 0,
                }
            }
        },
        options = {
            legend = { display = false },
            scales = {
                yAxes = { { ticks = { beginAtZero = true } } },
                xAxes = { { ticks = { maxTicksLimit = 8 } } },
            },
        },
    }
    local base = (opts and opts.base_url) or os.getenv("TELEGRAM_CHART_BASE_URL") or "https://quickchart.io/chart"
    local encoded = url_encode(json.encode(chart))
    return base .. "?c=" .. encoded .. "&w=800&h=360&format=png"
end

ai_charts._test = {
    build_metric_chart = ai_charts.build_metric_chart,
}
