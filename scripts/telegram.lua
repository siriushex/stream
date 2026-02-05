-- Telegram Alerts notifier (async, curl-based)

telegram = {
    config = {
        enabled = false,
        level = "OFF",
        token = "",
        chat_id = "",
        api_base = "https://api.telegram.org",
        dedupe_window_sec = 60,
        throttle_limit = 20,
        throttle_window_sec = 60,
        throttle_notice_sec = 300,
        retry_schedule = { 1, 5, 15 },
        queue_max = 200,
        timeout_sec = 10,
        connect_timeout_sec = 5,
        backup_enabled = false,
        backup_schedule = "OFF",
        backup_time = "03:00",
        backup_weekday = 1,
        backup_monthday = 1,
        backup_include_secrets = false,
        backup_last_ts = 0,
        summary_enabled = false,
        summary_schedule = "OFF",
        summary_time = "08:00",
        summary_weekday = 1,
        summary_monthday = 1,
        summary_include_charts = true,
        summary_last_ts = 0,
    },
    queue = {},
    inflight = nil,
    dedupe = {},
    throttle = {},
    throttle_notice_ts = 0,
    timer = nil,
    curl_available = nil,
    last_error_ts = 0,
    backup_next_ts = nil,
    summary_next_ts = nil,
}

local LEVEL_RANK = {
    OFF = 0,
    CRITICAL = 1,
    ERROR = 2,
    WARNING = 3,
    INFO = 4,
    DEBUG = 5,
}

local EVENT_SEVERITY = {
    STREAM_DOWN = "CRITICAL",
    STREAM_UP = "INFO",
    INPUT_SWITCH = "WARNING",
    INPUT_DOWN = "WARNING",
    OUTPUT_DOWN = "ERROR",
    OUTPUT_ERROR = "ERROR",
    CONFIG_RELOAD_FAILED = "CRITICAL",
    CONFIG_RELOAD_OK = "INFO",
    TRANSCODE_STALL = "ERROR",
    TRANSCODE_RESTART = "WARNING",
    TRANSCODE_RESTART_LIMIT = "ERROR",
    AUTH_DENY_BURST = "WARNING",
    AUTH_BACKEND_DOWN = "ERROR",
}

local function get_setting(key)
    if config and config.get_setting then
        return config.get_setting(key)
    end
    return nil
end

local function setting_bool(key, fallback)
    local value = get_setting(key)
    if value == nil then
        return fallback
    end
    if value == true or value == 1 or value == "1" or value == "true" then
        return true
    end
    if value == false or value == 0 or value == "0" or value == "false" then
        return false
    end
    return fallback
end

local function setting_string(key, fallback)
    local value = get_setting(key)
    if value == nil or value == "" then
        return fallback
    end
    return tostring(value)
end

local function normalize_level(value)
    if not value then
        return "OFF"
    end
    local text = tostring(value):upper()
    if LEVEL_RANK[text] then
        return text
    end
    return "OFF"
end

local function normalize_schedule(value)
    local text = tostring(value or ""):upper()
    if text == "DAILY" or text == "WEEKLY" or text == "MONTHLY" then
        return text
    end
    return "OFF"
end

local function clamp_number(value, min, max, fallback)
    local num = tonumber(value)
    if not num then
        return fallback
    end
    if min and num < min then
        return min
    end
    if max and num > max then
        return max
    end
    return num
end

local function parse_time(value, fallback)
    local text = tostring(value or "")
    local h, m = text:match("^(%d%d?):(%d%d)$")
    h = clamp_number(h, 0, 23, nil)
    m = clamp_number(m, 0, 59, nil)
    if not h or not m then
        return parse_time(fallback or "03:00")
    end
    return h, m
end

local function url_encode(value)
    local text = tostring(value or "")
    return text:gsub("([^%w%-%._~])", function(c)
        return string.format("%%%02X", string.byte(c))
    end)
end

local function days_in_month(year, month)
    local next_year = month == 12 and (year + 1) or year
    local next_month = month == 12 and 1 or (month + 1)
    local t = os.time({ year = next_year, month = next_month, day = 1, hour = 0, min = 0, sec = 0 })
    local prev = os.date("*t", t - 86400)
    return prev and prev.day or 28
end

local function trim_text(text, max_len)
    local value = tostring(text or "")
    value = value:gsub("%s+$", "")
    if max_len and #value > max_len then
        return value:sub(1, max_len - 1) .. "…"
    end
    return value
end

local function shorten_text(text, max_len)
    if not text or text == "" then
        return nil
    end
    return trim_text(text, max_len or 60)
end

local function format_stream_label(stream_name, stream_id)
    local name = shorten_text(stream_name or "", 60)
    local id = stream_id and tostring(stream_id) or ""
    if name and name ~= "" then
        if id ~= "" then
            return name .. " (#" .. id .. ")"
        end
        return name
    end
    if id ~= "" then
        return "#" .. id
    end
    return "stream"
end

local function format_input_short(url)
    if not url or url == "" then
        return nil
    end
    if type(url) ~= "string" then
        return shorten_text(url, 60)
    end
    local parsed = parse_url(url)
    if not parsed then
        return shorten_text(url, 60)
    end
    if parsed.host then
        local host = parsed.host
        local path = parsed.path or ""
        if #path > 20 then
            path = "…" .. path:sub(-19)
        end
        return parsed.format .. "://" .. host .. path
    end
    return shorten_text(url, 60)
end

local function resolve_stream_name(event)
    if event and event.meta and event.meta.stream_name then
        return tostring(event.meta.stream_name)
    end
    if event and event.stream_id and config and config.get_stream then
        local row = config.get_stream(event.stream_id)
        if row and row.config and row.config.name then
            return tostring(row.config.name)
        end
    end
    return nil
end

local function resolve_severity(event)
    if event and event.code then
        local mapped = EVENT_SEVERITY[event.code]
        if mapped then
            return mapped
        end
        if event.code:find("^TRANSCODE_") then
            return "ERROR"
        end
    end
    return normalize_level(event and event.level or "ERROR")
end

local function level_allowed(min_level, event_level)
    if min_level == "OFF" then
        return false
    end
    local min_rank = LEVEL_RANK[min_level] or 0
    local evt_rank = LEVEL_RANK[event_level] or 0
    if evt_rank == 0 then
        return false
    end
    return evt_rank <= min_rank
end

local function build_message(event)
    if not event then
        return nil
    end
    local severity = resolve_severity(event)
    local stream_name = resolve_stream_name(event)
    local label = format_stream_label(stream_name, event.stream_id)
    local code = tostring(event.code or "")
    local meta = event.meta or {}
    local message = shorten_text(event.message or "", 80) or ""

    if code == "STREAM_DOWN" then
        local timeout = meta.no_data_timeout_sec or meta.no_data_timeout or nil
        local suffix = timeout and (" — нет данных " .. tostring(timeout) .. "s") or " — нет данных"
        local line1 = "🔴 DOWN: " .. label .. suffix
        local input_short = format_input_short(meta.active_input_url or meta.active_input)
        if input_short then
            return line1 .. "\n(" .. input_short .. ")"
        end
        return line1
    end

    if code == "STREAM_UP" then
        local kbps = meta.bitrate_kbps or meta.bitrate or nil
        local tail = kbps and (" — восстановлено, " .. tostring(math.floor(kbps + 0.5)) .. " kbps")
            or " — восстановлено"
        return "🟢 UP: " .. label .. tail
    end

    if code == "INPUT_SWITCH" then
        local from_idx = meta.from_index
        local to_idx = meta.to_index
        local from_label = from_idx ~= nil and tostring(from_idx + 1) or "?"
        local to_label = to_idx ~= nil and tostring(to_idx + 1) or "?"
        return "🟠 SWITCH: " .. label .. " — input" .. from_label .. " → input" .. to_label
    end

    if code == "INPUT_DOWN" then
        local idx = meta.input_index
        local idx_label = idx ~= nil and tostring(idx + 1) or "?"
        local reason = meta.reason and shorten_text(meta.reason, 40) or nil
        local tail = reason and (" — " .. reason) or ""
        return "🟠 INPUT DOWN: " .. label .. " — input" .. idx_label .. tail
    end

    if code == "OUTPUT_DOWN" or code == "OUTPUT_ERROR" then
        local idx = meta.output_index
        local idx_label = idx ~= nil and tostring(idx + 1) or "?"
        local tail = message ~= "" and (" — " .. message) or ""
        return "🟥 ERROR: " .. label .. " — output" .. idx_label .. tail
    end

    if code == "CONFIG_RELOAD_FAILED" then
        local tail = message ~= "" and (": " .. message) or ""
        return "🔴 RELOAD FAILED" .. tail
    end

    if code == "CONFIG_RELOAD_OK" then
        return "ℹ️ RELOAD: конфиг применен"
    end

    if code:find("^TRANSCODE_") then
        if code == "TRANSCODE_STALL" then
            return "🟥 ERROR: " .. label .. " — " .. (message ~= "" and message or "stall")
        end
        if code == "TRANSCODE_RESTART" then
            return "🟠 WARN: " .. label .. " — перезапуск"
        end
        local tail = message ~= "" and (" — " .. message) or ""
        return "🟥 ERROR: " .. label .. tail
    end

    if severity == "CRITICAL" then
        return "🔴 ALERT: " .. label .. (message ~= "" and (" — " .. message) or "")
    end
    if severity == "ERROR" then
        return "🟥 ERROR: " .. label .. (message ~= "" and (" — " .. message) or "")
    end
    if severity == "WARNING" then
        return "🟠 WARN: " .. label .. (message ~= "" and (" — " .. message) or "")
    end
    if severity == "INFO" then
        return "ℹ️ INFO: " .. label .. (message ~= "" and (" — " .. message) or "")
    end
    return "🐞 DEBUG: " .. (message ~= "" and message or code)
end

local function ensure_curl_available()
    if telegram.curl_available ~= nil then
        return telegram.curl_available
    end
    if not process or type(process.spawn) ~= "function" then
        telegram.curl_available = false
        return false
    end
    local ok, proc = pcall(process.spawn, { "curl", "--version" }, { stdout = "pipe", stderr = "pipe" })
    if not ok or not proc then
        telegram.curl_available = false
        return false
    end
    local status = proc:poll()
    if status and status.exit_code and status.exit_code ~= 0 then
        telegram.curl_available = false
    else
        telegram.curl_available = true
    end
    proc:close()
    return telegram.curl_available
end

local function prune_timestamps(list, cutoff)
    if type(list) ~= "table" then
        return {}
    end
    local out = {}
    for _, ts in ipairs(list) do
        if ts >= cutoff then
            table.insert(out, ts)
        end
    end
    return out
end

local function allow_throttle(now)
    local cfg = telegram.config
    local window = cfg.throttle_window_sec or 60
    local limit = cfg.throttle_limit or 20
    telegram.throttle = prune_timestamps(telegram.throttle, now - window)
    if #telegram.throttle >= limit then
        return false
    end
    table.insert(telegram.throttle, now)
    return true
end

local function enqueue_text(text, opts)
    local cfg = telegram.config
    if not cfg.available then
        return false, "disabled"
    end
    if not ensure_curl_available() then
        if (os.time() - telegram.last_error_ts) > 60 then
            telegram.last_error_ts = os.time()
            log.warning("[telegram] curl not available, alerts disabled")
        end
        return false, "curl unavailable"
    end

    local message = trim_text(text, 300)
    if message == "" then
        return false, "empty"
    end

    local now = os.time()
    local dedupe_window = cfg.dedupe_window_sec or 60
    if telegram.dedupe[message] and (now - telegram.dedupe[message]) < dedupe_window then
        return false, "dedupe"
    end

    local bypass_throttle = opts and opts.bypass_throttle
    if not bypass_throttle then
        if not allow_throttle(now) then
            local notice_gap = cfg.throttle_notice_sec or 300
            if (now - (telegram.throttle_notice_ts or 0)) >= notice_gap then
                telegram.throttle_notice_ts = now
                enqueue_text("⚠️ ALERTS: слишком много событий, включен троттлинг…", { bypass_throttle = true })
            end
            return false, "throttled"
        end
    end

    if #telegram.queue >= (cfg.queue_max or 200) then
        return false, "queue full"
    end

    telegram.dedupe[message] = now
    table.insert(telegram.queue, {
        text = message,
        attempts = 0,
        next_try = now,
    })
    return true
end

local function start_timer()
    if telegram.timer then
        return
    end
    telegram.timer = timer({
        interval = 1,
        callback = function(self)
            telegram.tick()
        end,
    })
end

local function write_file(path, content)
    local file, err = io.open(path, "wb")
    if not file then
        return nil, err
    end
    file:write(content or "")
    file:close()
    return true
end

local function ensure_dir(path)
    if not path or path == "" then
        return
    end
    local stat = utils and utils.stat and utils.stat(path)
    if stat and stat.type == "directory" then
        return
    end
    os.execute("mkdir -p " .. path)
end

local function mask_backup_payload(payload)
    if type(payload) ~= "table" then
        return
    end
    if type(payload.settings) == "table" then
        payload.settings.telegram_bot_token = nil
        payload.settings.influx_token = nil
    end
    if type(payload.users) == "table" then
        for _, user in pairs(payload.users) do
            if type(user) == "table" then
                user.password_hash = nil
                user.password_salt = nil
                user.cipher = nil
            end
        end
    end
    if type(payload.softcam) == "table" then
        for _, cam in ipairs(payload.softcam) do
            if type(cam) == "table" then
                cam.pass = nil
            end
        end
    end
end

local function build_backup_payload()
    if not config or not config.export_astra then
        return nil, "config export unavailable"
    end
    local payload = config.export_astra()
    if not telegram.config.backup_include_secrets then
        mask_backup_payload(payload)
    end
    return payload
end

local function create_backup_file()
    local payload, err = build_backup_payload()
    if not payload then
        return nil, err
    end
    local base = config and config.config_backup_dir or "./data/backups/config"
    ensure_dir(base)
    local stamp = os.date("%Y%m%d-%H%M%S", os.time())
    local path = base .. "/telegram_backup_" .. stamp .. ".json"
    local ok, write_err = write_file(path, json.encode(payload))
    if not ok then
        return nil, write_err
    end
    return path
end

local function enqueue_document(path, caption, opts)
    local cfg = telegram.config
    if not cfg or not cfg.available then
        return false, "telegram disabled"
    end
    if not ensure_curl_available() then
        return false, "curl unavailable"
    end
    local stat = utils and utils.stat and utils.stat(path)
    if not stat or stat.type ~= "file" then
        return false, "file missing"
    end
    if #telegram.queue >= (cfg.queue_max or 200) then
        return false, "queue full"
    end
    local now = os.time()
    table.insert(telegram.queue, {
        document_path = path,
        caption = caption,
        attempts = 0,
        next_try = now,
        bypass_throttle = opts and opts.bypass_throttle,
    })
    return true
end

local function compute_next_schedule_ts(now, schedule, time_value, weekday_value, monthday_value)
    local normalized = normalize_schedule(schedule)
    if normalized == "OFF" then
        return nil
    end
    local hour, minute = parse_time(time_value or "03:00")
    local t = os.date("*t", now)
    if normalized == "DAILY" then
        local candidate = os.time({
            year = t.year, month = t.month, day = t.day,
            hour = hour, min = minute, sec = 0
        })
        if candidate <= now then
            candidate = candidate + 86400
        end
        return candidate
    elseif normalized == "WEEKLY" then
        local weekday = clamp_number(weekday_value, 1, 7, 1)
        local target_wday = ((weekday % 7) + 1) -- 1=Mon -> 2, 7=Sun -> 1
        local today = t.wday
        local delta = (target_wday - today + 7) % 7
        local candidate = os.time({
            year = t.year, month = t.month, day = t.day,
            hour = hour, min = minute, sec = 0
        }) + delta * 86400
        if candidate <= now then
            candidate = candidate + 7 * 86400
        end
        return candidate
    elseif normalized == "MONTHLY" then
        local day = clamp_number(monthday_value, 1, 31, 1)
        local max_day = days_in_month(t.year, t.month)
        if day > max_day then
            day = max_day
        end
        local candidate = os.time({
            year = t.year, month = t.month, day = day,
            hour = hour, min = minute, sec = 0
        })
        if candidate <= now then
            local next_month = t.month == 12 and 1 or (t.month + 1)
            local next_year = t.month == 12 and (t.year + 1) or t.year
            local max_next = days_in_month(next_year, next_month)
            if day > max_next then
                day = max_next
            end
            candidate = os.time({
                year = next_year, month = next_month, day = day,
                hour = hour, min = minute, sec = 0
            })
        end
        return candidate
    end
    return nil
end

local function compute_next_backup_ts(now)
    local cfg = telegram.config
    if not cfg.backup_enabled then
        return nil
    end
    return compute_next_schedule_ts(now, cfg.backup_schedule, cfg.backup_time, cfg.backup_weekday, cfg.backup_monthday)
end

local function backup_due(now)
    local cfg = telegram.config
    if not cfg.backup_enabled or cfg.backup_schedule == "OFF" then
        return false
    end
    if not cfg.available then
        return false
    end
    if not telegram.backup_next_ts then
        telegram.backup_next_ts = compute_next_backup_ts(now)
    end
    return telegram.backup_next_ts and now >= telegram.backup_next_ts
end

local function run_backup(now)
    local cfg = telegram.config
    local path, err = create_backup_file()
    if not path then
        if (now - telegram.last_error_ts) > 30 then
            telegram.last_error_ts = now
            log.warning("[telegram] backup failed: " .. tostring(err or "unknown"))
        end
        return false
    end
    local stamp = os.date("%Y-%m-%d %H:%M", now)
    local caption = "🗄️ Config backup " .. stamp
    local ok = enqueue_document(path, caption, { bypass_throttle = true })
    if ok then
        cfg.backup_last_ts = now
        if config and config.set_setting then
            config.set_setting("telegram_backup_last_ts", now)
        end
        telegram.backup_next_ts = compute_next_backup_ts(now)
    end
    return ok
end

local function format_kbps(value)
    local num = tonumber(value) or 0
    if num < 0 then num = 0 end
    return tostring(math.floor(num + 0.5)) .. " kbps"
end

local function build_summary_snapshot(range_sec)
    if not config or not config.list_ai_metrics then
        return nil, nil, "observability unavailable"
    end
    local since_ts = os.time() - (range_sec or 86400)
    local metrics = config.list_ai_metrics({
        since = since_ts,
        scope = "global",
        limit = 20000,
    })
    if not metrics or #metrics == 0 then
        return nil, nil, "no metrics"
    end
    local summary = {
        total_bitrate_kbps = 0,
        streams_on_air = 0,
        streams_down = 0,
        streams_total = 0,
        input_switch = 0,
        alerts_error = 0,
    }
    local last_bucket = 0
    for _, row in ipairs(metrics) do
        if row.ts_bucket and row.ts_bucket > last_bucket then
            last_bucket = row.ts_bucket
        end
    end
    if last_bucket > 0 then
        for _, row in ipairs(metrics) do
            if row.ts_bucket == last_bucket and summary[row.metric_key] ~= nil then
                summary[row.metric_key] = row.value
            end
        end
    end
    return summary, metrics, nil
end

local function build_summary_errors(range_sec, limit)
    if not config or not config.list_ai_log_events then
        return {}
    end
    local since_ts = os.time() - (range_sec or 86400)
    local rows = config.list_ai_log_events({
        since = since_ts,
        level = "ERROR",
        limit = limit or 20,
    })
    local out = {}
    for _, row in ipairs(rows or {}) do
        table.insert(out, {
            ts = row.ts,
            level = row.level,
            stream_id = row.stream_id,
            message = shorten_text(row.message, 120),
        })
    end
    return out
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

local function build_chart_url(metrics, metric_key, title, color)
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
    local base = os.getenv("TELEGRAM_CHART_BASE_URL") or "https://quickchart.io/chart"
    local encoded = url_encode(json.encode(chart))
    return base .. "?c=" .. encoded .. "&w=800&h=360&format=png"
end

local function enqueue_photo_url(url, caption, opts)
    local cfg = telegram.config
    if not cfg.available then
        return false, "disabled"
    end
    if not ensure_curl_available() then
        return false, "curl unavailable"
    end
    if not url or url == "" then
        return false, "empty"
    end
    local now = os.time()
    local bypass_throttle = opts and opts.bypass_throttle
    if not bypass_throttle then
        if not allow_throttle(now) then
            return false, "throttled"
        end
    end
    if #telegram.queue >= (cfg.queue_max or 200) then
        return false, "queue full"
    end
    table.insert(telegram.queue, {
        photo_url = url,
        caption = caption,
        attempts = 0,
        next_try = now,
        bypass_throttle = bypass_throttle,
    })
    return true
end

local function compute_next_summary_ts(now)
    local cfg = telegram.config
    if not cfg.summary_enabled then
        return nil
    end
    return compute_next_schedule_ts(now, cfg.summary_schedule, cfg.summary_time, cfg.summary_weekday, cfg.summary_monthday)
end

local function summary_due(now)
    local cfg = telegram.config
    if not cfg.summary_enabled or cfg.summary_schedule == "OFF" then
        return false
    end
    if not cfg.available then
        return false
    end
    if not telegram.summary_next_ts then
        telegram.summary_next_ts = compute_next_summary_ts(now)
    end
    return telegram.summary_next_ts and now >= telegram.summary_next_ts
end

local function run_summary(now)
    local cfg = telegram.config
    local summary, metrics, err = build_summary_snapshot(24 * 3600)
    if not summary then
        if (now - telegram.last_error_ts) > 60 then
            telegram.last_error_ts = now
            log.warning("[telegram] summary skipped: " .. tostring(err or "no data"))
        end
        return false
    end
    local errors = build_summary_errors(24 * 3600, 15)
    local lines = {
        "📊 Summary (24h)",
        "Bitrate: " .. format_kbps(summary.total_bitrate_kbps),
        "Streams: " .. tostring(summary.streams_on_air or 0) .. " on / " .. tostring(summary.streams_down or 0) .. " down",
        "Switches: " .. tostring(summary.input_switch or 0) .. ", Alerts: " .. tostring(summary.alerts_error or 0),
    }
    local message = table.concat(lines, "\n")
    enqueue_text(message, { bypass_throttle = true })
    local function join_list(list, max_items)
        if type(list) ~= "table" then
            return ""
        end
        local out = {}
        local limit = max_items or 3
        for idx, item in ipairs(list) do
            if idx > limit then break end
            table.insert(out, tostring(item))
        end
        return table.concat(out, "; ")
    end
    if ai_runtime and ai_runtime.request_summary and ai_runtime.is_ready and ai_runtime.is_ready() then
        ai_runtime.request_summary({
            summary = summary,
            errors = errors,
        }, function(ok, result)
            if not ok or type(result) ~= "table" then
                return
            end
            local ai_lines = { "🤖 AI summary" }
            local summary_text = shorten_text(result.summary, 220)
            if summary_text and summary_text ~= "" then
                table.insert(ai_lines, summary_text)
            end
            local issues = result.top_issues or {}
            local suggestions = result.suggestions or {}
            local issues_text = join_list(issues, 3)
            if issues_text ~= "" then
                table.insert(ai_lines, "Issues: " .. issues_text)
            end
            local suggestions_text = join_list(suggestions, 3)
            if suggestions_text ~= "" then
                table.insert(ai_lines, "Suggestions: " .. suggestions_text)
            end
            local ai_message = table.concat(ai_lines, "\n")
            enqueue_text(ai_message, { bypass_throttle = true })
        end)
    end
    if cfg.summary_include_charts then
        local chart_url = build_chart_url(metrics, "total_bitrate_kbps", "Total bitrate (kbps)", "rgb(90,170,229)")
        if chart_url then
            enqueue_photo_url(chart_url, "📈 Total bitrate (24h)", { bypass_throttle = true })
        end
        local down_url = build_chart_url(metrics, "streams_down", "Streams down", "rgb(224,102,102)")
        if down_url then
            enqueue_photo_url(down_url, "📉 Streams down (24h)", { bypass_throttle = true })
        end
    end
    cfg.summary_last_ts = now
    if config and config.set_setting then
        config.set_setting("telegram_summary_last_ts", now)
    end
    telegram.summary_next_ts = compute_next_summary_ts(now)
    return true
end

local function spawn_send(item)
    local cfg = telegram.config
    local url = (cfg.api_base or "https://api.telegram.org")
    url = url:gsub("/+$", "")
    local args = {
        "curl",
        "-sS",
        "--fail",
        "-m",
        tostring(cfg.timeout_sec or 10),
        "--connect-timeout",
        tostring(cfg.connect_timeout_sec or 5),
    }
    if item.photo_url then
        url = url .. "/bot" .. cfg.token .. "/sendPhoto"
        table.insert(args, url)
        table.insert(args, "-F")
        table.insert(args, "chat_id=" .. cfg.chat_id)
        table.insert(args, "-F")
        table.insert(args, "photo=" .. item.photo_url)
        if item.caption and item.caption ~= "" then
            table.insert(args, "-F")
            table.insert(args, "caption=" .. item.caption)
        end
    elseif item.document_path then
        url = url .. "/bot" .. cfg.token .. "/sendDocument"
        table.insert(args, url)
        table.insert(args, "-F")
        table.insert(args, "chat_id=" .. cfg.chat_id)
        table.insert(args, "-F")
        table.insert(args, "document=@" .. item.document_path)
        if item.caption and item.caption ~= "" then
            table.insert(args, "-F")
            table.insert(args, "caption=" .. item.caption)
        end
    else
        url = url .. "/bot" .. cfg.token .. "/sendMessage"
        local payload = json.encode({
            chat_id = cfg.chat_id,
            text = item.text,
        })
        table.insert(args, "-H")
        table.insert(args, "Content-Type: application/json")
        table.insert(args, "-X")
        table.insert(args, "POST")
        table.insert(args, url)
        table.insert(args, "-d")
        table.insert(args, payload)
    end
    local ok, proc = pcall(process.spawn, args, { stdout = "pipe", stderr = "pipe" })
    if not ok or not proc then
        return nil, "spawn failed"
    end
    return proc, nil
end

function telegram.tick()
    local cfg = telegram.config
    if not cfg.available then
        return
    end

    local now = os.time()
    if backup_due(now) then
        run_backup(now)
    end
    if summary_due(now) then
        run_summary(now)
    end

    if telegram.inflight then
        local inflight = telegram.inflight
        local status = inflight.proc and inflight.proc:poll() or nil
        if not status then
            return
        end
        local stdout = inflight.proc:read_stdout()
        local stderr = inflight.proc:read_stderr()
        inflight.proc:close()
        telegram.inflight = nil

        local exit_code = status.exit_code or 0
        if exit_code == 0 then
            return
        end

        local item = inflight.item
        item.attempts = item.attempts + 1
        local schedule = cfg.retry_schedule or { 1, 5, 15 }
        local delay = schedule[item.attempts] or 0
        if delay > 0 then
            item.next_try = os.time() + delay
            table.insert(telegram.queue, 1, item)
            return
        end

        if (os.time() - telegram.last_error_ts) > 30 then
            telegram.last_error_ts = os.time()
            local reason = stderr or stdout or "telegram send failed"
            reason = shorten_text(reason, 120) or "telegram send failed"
            log.warning("[telegram] send failed: " .. reason)
        end
        return
    end

    if #telegram.queue == 0 then
        return
    end
    local item = table.remove(telegram.queue, 1)
    if item.next_try and now < item.next_try then
        table.insert(telegram.queue, 1, item)
        return
    end

    local proc, err = spawn_send(item)
    if not proc then
        if (now - telegram.last_error_ts) > 30 then
            telegram.last_error_ts = now
            log.warning("[telegram] send spawn failed")
        end
        return
    end
    telegram.inflight = {
        proc = proc,
        item = item,
        started = now,
    }
end

function telegram.configure()
    local alerts_enabled = setting_bool("telegram_enabled", false)
    local level = normalize_level(setting_string("telegram_level", "OFF"))
    local token = setting_string("telegram_bot_token", "")
    local chat_id = setting_string("telegram_chat_id", "")
    local api_base = os.getenv("TELEGRAM_API_BASE_URL") or "https://api.telegram.org"
    local backup_enabled = setting_bool("telegram_backup_enabled", false)
    local backup_schedule = normalize_schedule(setting_string("telegram_backup_schedule", "OFF"))
    local backup_time = setting_string("telegram_backup_time", "03:00")
    local backup_weekday = clamp_number(get_setting("telegram_backup_weekday"), 1, 7, 1)
    local backup_monthday = clamp_number(get_setting("telegram_backup_monthday"), 1, 31, 1)
    local backup_include_secrets = setting_bool("telegram_backup_include_secrets", false)
    local backup_last_ts = tonumber(get_setting("telegram_backup_last_ts") or 0) or 0
    local summary_enabled = setting_bool("telegram_summary_enabled", false)
    local summary_schedule = normalize_schedule(setting_string("telegram_summary_schedule", "OFF"))
    local summary_time = setting_string("telegram_summary_time", "08:00")
    local summary_weekday = clamp_number(get_setting("telegram_summary_weekday"), 1, 7, 1)
    local summary_monthday = clamp_number(get_setting("telegram_summary_monthday"), 1, 31, 1)
    local summary_include_charts = setting_bool("telegram_summary_include_charts", true)
    local summary_last_ts = tonumber(get_setting("telegram_summary_last_ts") or 0) or 0

    telegram.config.alerts_enabled = alerts_enabled
    telegram.config.available = token ~= "" and chat_id ~= ""
    telegram.config.level = level
    telegram.config.token = token
    telegram.config.chat_id = chat_id
    telegram.config.api_base = api_base
    telegram.curl_available = nil
    telegram.config.backup_enabled = backup_enabled
    if backup_enabled and backup_schedule == "OFF" then
        backup_schedule = "DAILY"
    end
    telegram.config.backup_schedule = backup_schedule
    telegram.config.backup_time = backup_time
    telegram.config.backup_weekday = backup_weekday
    telegram.config.backup_monthday = backup_monthday
    telegram.config.backup_include_secrets = backup_include_secrets
    telegram.config.backup_last_ts = backup_last_ts
    telegram.config.summary_enabled = summary_enabled
    if summary_enabled and summary_schedule == "OFF" then
        summary_schedule = "DAILY"
    end
    telegram.config.summary_schedule = summary_schedule
    telegram.config.summary_time = summary_time
    telegram.config.summary_weekday = summary_weekday
    telegram.config.summary_monthday = summary_monthday
    telegram.config.summary_include_charts = summary_include_charts
    telegram.config.summary_last_ts = summary_last_ts

    if telegram.config.available and not ensure_curl_available() then
        telegram.config.available = false
        log.warning("[telegram] curl not available, notifier disabled")
    end

    telegram.backup_next_ts = nil
    telegram.summary_next_ts = nil

    if telegram.config.available and (telegram.config.alerts_enabled or telegram.config.backup_enabled or telegram.config.summary_enabled) then
        start_timer()
    end
end

function telegram.mask_token(token)
    local value = tostring(token or "")
    if value == "" then
        return ""
    end
    local prefix = value:match("^([^:]+):")
    if not prefix then
        prefix = value:sub(1, 6)
    end
    if #prefix > 6 then
        prefix = prefix:sub(1, 6)
    end
    return prefix .. ":***"
end

function telegram.on_alert(event)
    if not event then
        return false
    end
    if not telegram.config.alerts_enabled or not telegram.config.available then
        return false
    end
    local severity = resolve_severity(event)
    local min_level = telegram.config.level or "OFF"
    if not level_allowed(min_level, severity) then
        return false
    end
    local message = build_message(event)
    if not message then
        return false
    end
    return enqueue_text(message)
end

function telegram.send_test()
    if not telegram.config.available then
        return false, "telegram disabled"
    end
    return enqueue_text("✅ Telegram alerts: test message from Astra Clone", { bypass_throttle = true })
end

function telegram.send_backup_now()
    if not telegram.config.available then
        return false, "telegram disabled"
    end
    local now = os.time()
    local ok = run_backup(now)
    if not ok then
        return false, "backup failed"
    end
    return true
end

function telegram.send_summary_now()
    if not telegram.config.available then
        return false, "telegram disabled"
    end
    local now = os.time()
    local ok = run_summary(now)
    if not ok then
        return false, "summary failed"
    end
    return true
end

telegram._test = {
    normalize_level = normalize_level,
    resolve_severity = resolve_severity,
    level_allowed = level_allowed,
    build_message = build_message,
    enqueue_text = enqueue_text,
}
