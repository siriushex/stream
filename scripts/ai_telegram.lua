-- AstralAI Telegram integration (commands)

ai_telegram = ai_telegram or {}
ai_telegram.state = ai_telegram.state or {
    dedupe = {},
    throttle = {},
    pending = {},
    seeded = false,
}

local function trim(text)
    return (tostring(text or ""):gsub("^%s+", ""):gsub("%s+$", ""))
end

local function parse_range_seconds(value, fallback)
    local text = tostring(value or "")
    local num, unit = text:match("^(%d+)([hd])$")
    num = tonumber(num)
    if not num or not unit then
        return fallback or 24 * 3600
    end
    if unit == "h" then
        return num * 3600
    end
    if unit == "d" then
        return num * 86400
    end
    return fallback or 24 * 3600
end

local function allowed_chat(chat_id)
    if not chat_id then
        return false
    end
    local id = tostring(chat_id)
    local allowed = ai_runtime and ai_runtime.config and ai_runtime.config.allowed_chat_ids or {}
    if type(allowed) ~= "table" or #allowed == 0 then
        local fallback = telegram and telegram.config and telegram.config.chat_id
        if not fallback or fallback == "" then
            return false
        end
        return tostring(fallback) == id
    end
    for _, entry in ipairs(allowed) do
        if tostring(entry) == id then
            return true
        end
    end
    return false
end

local function throttle_ok(chat_id, text)
    local now = os.time()
    local bucket = ai_telegram.state.throttle[chat_id] or {}
    local dedupe = ai_telegram.state.dedupe[chat_id] or {}
    local window = 60
    local limit = 6
    local dedupe_window = 15
    local trimmed = trim(text)
    local last = dedupe[trimmed]
    if last and (now - last) < dedupe_window then
        return false, "duplicate"
    end
    local cleaned = {}
    for _, ts in ipairs(bucket) do
        if ts >= (now - window) then
            table.insert(cleaned, ts)
        end
    end
    if #cleaned >= limit then
        ai_telegram.state.throttle[chat_id] = cleaned
        return false, "throttled"
    end
    table.insert(cleaned, now)
    dedupe[trimmed] = now
    ai_telegram.state.throttle[chat_id] = cleaned
    ai_telegram.state.dedupe[chat_id] = dedupe
    return true
end

local function send_text(chat_id, message, opts)
    if telegram and telegram.send_text then
        return telegram.send_text(message, {
            bypass_throttle = true,
            chat_id = chat_id,
        })
    end
    return false, "telegram unavailable"
end

local function seed_random()
    if ai_telegram.state.seeded then
        return
    end
    math.randomseed(os.time())
    ai_telegram.state.seeded = true
end

local function make_confirm_token()
    seed_random()
    return tostring(math.random(100000, 999999))
end

local function pending_cleanup(chat_id)
    local now = os.time()
    local pending = ai_telegram.state.pending[chat_id]
    if type(pending) ~= "table" then
        return
    end
    for plan_id, entry in pairs(pending) do
        if not entry or not entry.ts or (now - entry.ts) > 300 then
            pending[plan_id] = nil
        end
    end
end

local function pending_find_by_token(chat_id, token)
    local pending = ai_telegram.state.pending[chat_id]
    if type(pending) ~= "table" then
        return nil
    end
    for plan_id, entry in pairs(pending) do
        if entry and entry.token == token then
            return plan_id
        end
    end
    return nil
end

local function build_summary_snapshot(range_sec)
    local on_demand = false
    if config and config.get_setting then
        local v = config.get_setting("ai_metrics_on_demand")
        if v == true or v == 1 or v == "1" or v == "true" then
            on_demand = true
        end
    end

    if on_demand and ai_observability and ai_observability.get_on_demand_metrics then
        local data = ai_observability.get_on_demand_metrics(range_sec or 86400, nil, "global")
        if not data or not data.items then
            return nil, nil, "no metrics"
        end
        return data.summary or {}, data.items, nil
    end

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
        if ai_observability and ai_observability.get_on_demand_metrics then
            local data = ai_observability.get_on_demand_metrics(range_sec or 86400, nil, "global")
            if data and data.items then
                return data.summary or {}, data.items, nil
            end
        end
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

local function build_stream_snapshot(stream_id, range_sec)
    if not stream_id or stream_id == "" then
        return nil, "stream_id required"
    end

    local on_demand = false
    if config and config.get_setting then
        local v = config.get_setting("ai_metrics_on_demand")
        if v == true or v == 1 or v == "1" or v == "true" then
            on_demand = true
        end
    end

    if on_demand and ai_observability and ai_observability.get_on_demand_metrics then
        local data = ai_observability.get_on_demand_metrics(range_sec or 86400, nil, "stream", tostring(stream_id))
        if not data or not data.summary then
            return nil, "no metrics"
        end
        return {
            bitrate_kbps = data.summary.bitrate_kbps or 0,
            on_air = data.summary.on_air == true or tonumber(data.summary.on_air or 0) > 0,
            input_switch = data.summary.input_switch or 0,
            stream_id = tostring(stream_id),
        }, nil
    end

    if not config or not config.list_ai_metrics then
        return nil, "observability unavailable"
    end
    local since_ts = os.time() - (range_sec or 86400)
    local metrics = config.list_ai_metrics({
        since = since_ts,
        scope = "stream",
        scope_id = tostring(stream_id),
        limit = 20000,
    })
    if not metrics or #metrics == 0 then
        if ai_observability and ai_observability.get_on_demand_metrics then
            local data = ai_observability.get_on_demand_metrics(range_sec or 86400, nil, "stream", tostring(stream_id))
            if data and data.summary then
                return {
                    bitrate_kbps = data.summary.bitrate_kbps or 0,
                    on_air = data.summary.on_air == true or tonumber(data.summary.on_air or 0) > 0,
                    input_switch = data.summary.input_switch or 0,
                    stream_id = tostring(stream_id),
                }, nil
            end
        end
        return nil, "no metrics"
    end
    local last_bucket = 0
    for _, row in ipairs(metrics) do
        if row.ts_bucket and row.ts_bucket > last_bucket then
            last_bucket = row.ts_bucket
        end
    end
    local latest = { bitrate_kbps = 0, on_air = 0, input_switch = 0 }
    for _, row in ipairs(metrics) do
        if row.ts_bucket == last_bucket then
            latest[row.metric_key] = row.value
        end
    end
    return {
        bitrate_kbps = latest.bitrate_kbps or 0,
        on_air = tonumber(latest.on_air or 0) > 0,
        input_switch = latest.input_switch or 0,
        stream_id = tostring(stream_id),
    }, nil
end

local function build_error_snapshot(range_sec, stream_id)
    if not config or not config.list_ai_log_events then
        return {}
    end
    local since_ts = os.time() - (range_sec or 86400)
    local rows = config.list_ai_log_events({
        since = since_ts,
        level = "ERROR",
        stream_id = stream_id,
        limit = 15,
    })
    local out = {}
    for _, row in ipairs(rows or {}) do
        table.insert(out, {
            ts = row.ts,
            level = row.level,
            stream_id = row.stream_id,
            message = row.message,
        })
    end
    return out
end

local function parse_command(text)
    local raw = trim(text)
    local first = raw:match("^(%S+)")
    if not first then
        return nil
    end
    local base = first:match("^/ai[@%w_]*$")
    if not base then
        return nil
    end
    local rest = raw:sub(#first + 1)
    local parts = {}
    for token in rest:gmatch("%S+") do
        table.insert(parts, token)
    end
    local sub = parts[1] or "help"
    local opts = {}
    for i = 2, #parts do
        local key, value = parts[i]:match("^(%w+)%=(.+)$")
        if key then
            opts[key] = value
        else
            opts._extra = opts._extra or {}
            table.insert(opts._extra, parts[i])
        end
    end
    return sub, opts
end

local function format_ai_result(result)
    if type(result) ~= "table" then
        return "AI summary unavailable"
    end
    local lines = { "🤖 AI summary" }
    if result.summary and result.summary ~= "" then
        table.insert(lines, result.summary)
    end
    if type(result.top_issues) == "table" and #result.top_issues > 0 then
        table.insert(lines, "Issues: " .. table.concat(result.top_issues, "; "))
    end
    if type(result.suggestions) == "table" and #result.suggestions > 0 then
        table.insert(lines, "Suggestions: " .. table.concat(result.suggestions, "; "))
    end
    return table.concat(lines, "\n")
end

local function summary_command(chat_id, range_text)
    local range_sec = parse_range_seconds(range_text, 24 * 3600)
    local summary, _, err = build_summary_snapshot(range_sec)
    if not summary then
        return send_text(chat_id, "❌ Summary unavailable: " .. tostring(err or "no data"))
    end
    local errors = build_error_snapshot(range_sec)
    if ai_runtime and ai_runtime.is_ready and ai_runtime.is_ready() then
        send_text(chat_id, "⏳ Generating AI summary…")
        ai_runtime.request_summary({
            summary = summary,
            errors = errors,
            range_sec = range_sec,
        }, function(ok, result)
            if not ok then
                send_text(chat_id, "❌ AI summary failed")
                return
            end
            send_text(chat_id, format_ai_result(result))
        end)
        return true
    end
    local message = "📊 Summary: bitrate=" .. tostring(summary.total_bitrate_kbps)
        .. " kbps, on_air=" .. tostring(summary.streams_on_air)
        .. ", down=" .. tostring(summary.streams_down)
    return send_text(chat_id, message)
end

local function report_command(chat_id, stream_id, range_text)
    if not stream_id or stream_id == "" then
        return send_text(chat_id, "❌ stream_id required")
    end
    local range_sec = parse_range_seconds(range_text, 24 * 3600)
    local summary, err = build_stream_snapshot(stream_id, range_sec)
    if not summary then
        return send_text(chat_id, "❌ Report unavailable: " .. tostring(err or "no data"))
    end
    local errors = build_error_snapshot(range_sec, stream_id)
    if ai_runtime and ai_runtime.is_ready and ai_runtime.is_ready() then
        send_text(chat_id, "⏳ Generating AI report…")
        ai_runtime.request_summary({
            summary = summary,
            errors = errors,
            scope = "stream",
            stream_id = tostring(stream_id),
        }, function(ok, result)
            if not ok then
                send_text(chat_id, "❌ AI report failed")
                return
            end
            send_text(chat_id, format_ai_result(result))
        end)
        return true
    end
    local message = "📊 Stream #" .. tostring(stream_id) .. ": bitrate=" .. tostring(summary.bitrate_kbps)
        .. " kbps, on_air=" .. tostring(summary.on_air and "YES" or "NO")
    return send_text(chat_id, message)
end

local function suggest_command(chat_id)
    if not ai_runtime or not ai_runtime.plan then
        return send_text(chat_id, "❌ AI runtime unavailable")
    end
    local prompt = "Suggest fixes for current alerts and errors. Do not apply changes."
    local job = ai_runtime.plan({ prompt = prompt }, { user = "telegram", source = "telegram" })
    if not job then
        return send_text(chat_id, "❌ AI plan failed")
    end
    return send_text(chat_id, "✅ Plan queued: id=" .. tostring(job.id))
end

local function apply_command(chat_id, plan_id, confirm_token)
    if not ai_runtime or not ai_runtime.apply then
        return send_text(chat_id, "❌ AI runtime unavailable")
    end
    if not ai_runtime.config or not ai_runtime.config.allow_apply then
        return send_text(chat_id, "❌ AI apply disabled")
    end
    local job = plan_id and ai_runtime.jobs and ai_runtime.jobs[tostring(plan_id)] or nil
    if not job then
        return send_text(chat_id, "❌ Plan not found")
    end
    if job.status ~= "done" or not job.result then
        return send_text(chat_id, "❌ Plan is not ready")
    end
    pending_cleanup(chat_id)
    local pending = ai_telegram.state.pending[chat_id]
    if not pending then
        pending = {}
        ai_telegram.state.pending[chat_id] = pending
    end
    if not confirm_token or confirm_token == "" then
        local token = make_confirm_token()
        pending[tostring(plan_id)] = { token = token, ts = os.time() }
        return send_text(chat_id,
            "⚠️ Confirm apply for plan " .. tostring(plan_id)
            .. ". Reply: /ai confirm " .. token
            .. " (valid 5 min)"
        )
    end
    local entry = pending[tostring(plan_id)]
    if not entry or entry.token ~= confirm_token then
        return send_text(chat_id, "❌ Invalid or expired confirm token")
    end
    pending[tostring(plan_id)] = nil
    local applied, err = ai_runtime.apply({
        plan_id = tostring(plan_id),
        mode = "merge",
        comment = "telegram apply",
    }, { user = "telegram", source = "telegram" })
    if not applied then
        return send_text(chat_id, "❌ Apply failed: " .. tostring(err or "error"))
    end
    return send_text(chat_id, "✅ Apply OK: revision " .. tostring(applied.result and applied.result.revision_id or ""))
end

function ai_telegram.handle(payload)
    if type(payload) ~= "table" then
        return nil, "invalid payload"
    end
    local msg = payload.message or payload.edited_message or (payload.callback_query and payload.callback_query.message) or nil
    if not msg then
        return { status = "ignored" }
    end
    local text = msg.text or ""
    local chat = msg.chat or {}
    local chat_id = chat.id and tostring(chat.id) or ""
    if chat_id == "" then
        return nil, "chat_id missing"
    end
    if not allowed_chat(chat_id) then
        return nil, "chat not allowed"
    end
    if not text or text == "" then
        return { status = "ignored" }
    end
    local ok, reason = throttle_ok(chat_id, text)
    if not ok then
        send_text(chat_id, "⏳ Command throttled (" .. tostring(reason) .. ")")
        return { status = "throttled" }
    end
    local cmd, opts = parse_command(text)
    if not cmd then
        return { status = "ignored" }
    end
    cmd = tostring(cmd):lower()
    if cmd == "summary" then
        local range_text = opts.range or (opts._extra and opts._extra[1]) or "24h"
        summary_command(chat_id, range_text)
        return { status = "ok" }
    end
    if cmd == "report" then
        local stream_id = opts.stream or opts.stream_id or opts.id or (opts._extra and opts._extra[1])
        local range_text = opts.range or (opts._extra and opts._extra[2]) or "24h"
        report_command(chat_id, stream_id, range_text)
        return { status = "ok" }
    end
    if cmd == "suggest" then
        suggest_command(chat_id)
        return { status = "ok" }
    end
    if cmd == "apply" then
        local plan_id = opts.plan_id or (opts._extra and opts._extra[1])
        local token = opts.confirm or opts.token or (opts._extra and opts._extra[2])
        apply_command(chat_id, plan_id, token)
        return { status = "ok" }
    end
    if cmd == "confirm" then
        local token = opts.token or (opts._extra and opts._extra[1])
        if not token or token == "" then
            send_text(chat_id, "❌ confirm token required")
            return { status = "ok" }
        end
        pending_cleanup(chat_id)
        local plan_id = pending_find_by_token(chat_id, token)
        if not plan_id then
            send_text(chat_id, "❌ Invalid or expired confirm token")
            return { status = "ok" }
        end
        apply_command(chat_id, plan_id, token)
        return { status = "ok" }
    end
    send_text(chat_id, "Commands: /ai summary [24h|7d], /ai report stream=<id>, /ai suggest, /ai apply plan_id=<id>, /ai confirm <token>")
    return { status = "ok" }
end
