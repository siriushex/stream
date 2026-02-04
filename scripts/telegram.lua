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
    },
    queue = {},
    inflight = nil,
    dedupe = {},
    throttle = {},
    throttle_notice_ts = 0,
    timer = nil,
    curl_available = nil,
    last_error_ts = 0,
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
    if not cfg.enabled then
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

local function spawn_send(item)
    local cfg = telegram.config
    local url = (cfg.api_base or "https://api.telegram.org")
    url = url:gsub("/+$", "")
    url = url .. "/bot" .. cfg.token .. "/sendMessage"
    local payload = json.encode({
        chat_id = cfg.chat_id,
        text = item.text,
    })
    local args = {
        "curl",
        "-sS",
        "--fail",
        "-m",
        tostring(cfg.timeout_sec or 10),
        "--connect-timeout",
        tostring(cfg.connect_timeout_sec or 5),
        "-H",
        "Content-Type: application/json",
        "-X",
        "POST",
        url,
        "-d",
        payload,
    }
    local ok, proc = pcall(process.spawn, args, { stdout = "pipe", stderr = "pipe" })
    if not ok or not proc then
        return nil, "spawn failed"
    end
    return proc, nil
end

function telegram.tick()
    local cfg = telegram.config
    if not cfg.enabled then
        return
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

    local now = os.time()
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
    local enabled = setting_bool("telegram_enabled", false)
    local level = normalize_level(setting_string("telegram_level", "OFF"))
    local token = setting_string("telegram_bot_token", "")
    local chat_id = setting_string("telegram_chat_id", "")
    local api_base = os.getenv("TELEGRAM_API_BASE_URL") or "https://api.telegram.org"

    telegram.config.enabled = enabled and token ~= "" and chat_id ~= ""
    telegram.config.level = level
    telegram.config.token = token
    telegram.config.chat_id = chat_id
    telegram.config.api_base = api_base
    telegram.curl_available = nil

    if telegram.config.enabled and not ensure_curl_available() then
        telegram.config.enabled = false
        log.warning("[telegram] curl not available, notifier disabled")
    end

    if telegram.config.enabled then
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
    if not telegram.config.enabled then
        return false, "telegram disabled"
    end
    return enqueue_text("✅ Telegram alerts: test message from Astra Clone", { bypass_throttle = true })
end

telegram._test = {
    normalize_level = normalize_level,
    resolve_severity = resolve_severity,
    level_allowed = level_allowed,
    build_message = build_message,
    enqueue_text = enqueue_text,
}
