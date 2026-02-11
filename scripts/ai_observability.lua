-- AstralAI observability: log ingest, metrics rollup, retention

ai_observability = ai_observability or {}

ai_observability.state = {
    enabled = false,
    logs_retention_days = 7,
    metrics_retention_days = 30,
    rollup_interval_sec = 60,
    metrics_on_demand = true,
}

ai_observability.cache = ai_observability.cache or {
    metrics = {},
}

ai_observability.timer_rollup = nil
ai_observability.timer_cleanup = nil
ai_observability.last_rollup_bucket = 0

local function setting_number(key, fallback)
    if config and config.get_setting then
        local value = config.get_setting(key)
        if value == nil or value == "" then
            return fallback
        end
        local num = tonumber(value)
        if num ~= nil then
            return num
        end
    end
    return fallback
end

local function setting_bool(key, fallback)
    if config and config.get_setting then
        local value = config.get_setting(key)
        if value == nil then
            return fallback
        end
        if value == true or value == 1 or value == "1" or value == "true" then
            return true
        end
        if value == false or value == 0 or value == "0" or value == "false" then
            return false
        end
    end
    return fallback
end

local function cache_ttl_sec()
    local ttl = setting_number("ai_metrics_cache_sec", 30)
    if ttl < 0 then ttl = 0 end
    if ttl > 300 then ttl = 300 end
    return math.floor(ttl)
end

local function build_cache_key(range_sec, interval_sec, scope, scope_id)
    return table.concat({
        tostring(range_sec or 0),
        tostring(interval_sec or 0),
        tostring(scope or "global"),
        tostring(scope_id or ""),
    }, "|")
end

local function prune_cache(now)
    local ttl = cache_ttl_sec()
    if ttl <= 0 then
        ai_observability.cache.metrics = {}
        return
    end
    local metrics_cache = ai_observability.cache.metrics or {}
    for key, entry in pairs(metrics_cache) do
        if not entry or not entry.ts or (now - entry.ts) > ttl then
            metrics_cache[key] = nil
        end
    end
    ai_observability.cache.metrics = metrics_cache
end

local function calc_bucket(ts, interval)
    local base = tonumber(interval) or 60
    if base < 30 then base = 30 end
    return math.floor((ts or os.time()) / base) * base
end

local function sanitize_interval(value)
    local num = tonumber(value) or 60
    if num < 30 then num = 30 end
    if num > 3600 then num = 3600 end
    return math.floor(num)
end

local function prune_data()
    if not ai_observability.state.enabled then
        return
    end
    local now = os.time()
    local logs_days = ai_observability.state.logs_retention_days or 0
    local metrics_days = ai_observability.state.metrics_retention_days or 0
    if logs_days > 0 and config and config.prune_ai_log_events then
        local cutoff = now - (logs_days * 86400)
        config.prune_ai_log_events(cutoff)
    end
    if metrics_days > 0 and config and config.prune_ai_metrics then
        local cutoff = now - (metrics_days * 86400)
        config.prune_ai_metrics(cutoff)
    end
end

local function rollup_metrics()
    if not ai_observability.state.enabled then
        return
    end
    if ai_observability.state.metrics_retention_days <= 0 then
        return
    end
    if not runtime or not runtime.list_status then
        return
    end
    local interval = ai_observability.state.rollup_interval_sec
    local bucket = calc_bucket(os.time(), interval)
    if bucket == ai_observability.last_rollup_bucket then
        return
    end
    ai_observability.last_rollup_bucket = bucket

    local status = runtime.list_status() or {}
    local total_bitrate = 0
    local streams_total = 0
    local streams_on_air = 0
    local streams_down = 0
    local switch_count = 0

    for id, entry in pairs(status) do
        streams_total = streams_total + 1
        local on_air = entry.on_air == true or entry.transcode_state == "RUNNING"
        if on_air then
            streams_on_air = streams_on_air + 1
        else
            streams_down = streams_down + 1
        end
        local bitrate = 0
        if entry.transcode and entry.transcode.output_bitrate_kbps then
            bitrate = tonumber(entry.transcode.output_bitrate_kbps) or 0
        elseif entry.transcode and entry.transcode.input_bitrate_kbps then
            bitrate = tonumber(entry.transcode.input_bitrate_kbps) or 0
        else
            bitrate = tonumber(entry.bitrate) or 0
        end
        total_bitrate = total_bitrate + bitrate

        local switched = 0
        if entry.last_switch and tonumber(entry.last_switch) then
            local ts = tonumber(entry.last_switch)
            if ts >= bucket and ts < (bucket + interval) then
                switched = 1
            end
        end
        if switched > 0 then
            switch_count = switch_count + switched
        end

        if config and config.upsert_ai_metric then
            config.upsert_ai_metric({
                ts_bucket = bucket,
                scope = "stream",
                scope_id = tostring(id),
                metric_key = "bitrate_kbps",
                value = bitrate,
            })
            config.upsert_ai_metric({
                ts_bucket = bucket,
                scope = "stream",
                scope_id = tostring(id),
                metric_key = "on_air",
                value = on_air and 1 or 0,
            })
            if switched > 0 then
                config.upsert_ai_metric({
                    ts_bucket = bucket,
                    scope = "stream",
                    scope_id = tostring(id),
                    metric_key = "input_switch",
                    value = switched,
                })
            end
        end
    end

    if config and config.upsert_ai_metric then
        config.upsert_ai_metric({
            ts_bucket = bucket,
            scope = "global",
            scope_id = "",
            metric_key = "total_bitrate_kbps",
            value = total_bitrate,
        })
        config.upsert_ai_metric({
            ts_bucket = bucket,
            scope = "global",
            scope_id = "",
            metric_key = "streams_total",
            value = streams_total,
        })
        config.upsert_ai_metric({
            ts_bucket = bucket,
            scope = "global",
            scope_id = "",
            metric_key = "streams_on_air",
            value = streams_on_air,
        })
        config.upsert_ai_metric({
            ts_bucket = bucket,
            scope = "global",
            scope_id = "",
            metric_key = "streams_down",
            value = streams_down,
        })
        if switch_count > 0 then
            config.upsert_ai_metric({
                ts_bucket = bucket,
                scope = "global",
                scope_id = "",
                metric_key = "input_switch",
                value = switch_count,
            })
        end
        if config.count_alerts then
            local errors = config.count_alerts({
                since = bucket,
                ["until"] = bucket + interval,
                levels = { "ERROR", "CRITICAL" },
            })
            config.upsert_ai_metric({
                ts_bucket = bucket,
                scope = "global",
                scope_id = "",
                metric_key = "alerts_error",
                value = errors,
            })
        end
    end
end

function ai_observability.ingest_alert(entry)
    if not ai_observability.state.enabled then
        return
    end
    if ai_observability.state.logs_retention_days <= 0 then
        return
    end
    if not config or not config.add_ai_log_event then
        return
    end
    if type(entry) ~= "table" then
        return
    end
    local ts = tonumber(entry.ts) or os.time()
    local level = tostring(entry.level or "INFO")
    local stream_id = tostring(entry.stream_id or "")
    local code = tostring(entry.code or "alert")
    local message = tostring(entry.message or "")
    -- string.md5() возвращает бинарный digest (16 байт, может содержать \0).
    -- Для хранения в sqlite используем hex, чтобы не ломать SQL строки.
    local fingerprint = string.lower(string.hex(string.md5(level .. "|" .. stream_id .. "|" .. code .. "|" .. message)))
    config.add_ai_log_event({
        ts = ts,
        level = level,
        stream_id = stream_id,
        component = code,
        message = message,
        fingerprint = fingerprint,
        tags = entry.meta,
    })
end

local function count_from_logs(range_sec, scope, scope_id, interval)
    if not config or not config.list_ai_log_events then
        return {}
    end
    local since_ts = os.time() - (range_sec or 86400)
    local limit = math.max(2000, math.min(50000, math.floor((range_sec or 86400) / 30)))
    local query = {
        since = since_ts,
        ["until"] = nil,
        limit = limit,
    }
    if scope == "stream" and scope_id and scope_id ~= "" then
        query.stream_id = tostring(scope_id)
    end
    local rows = config.list_ai_log_events(query) or {}
    local function to_number(value)
        if value == nil then
            return nil
        end
        local num = tonumber(value)
        if num ~= nil then
            return num
        end
        if type(value) == "string" then
            local token = value:match("(-?%d+%.?%d*)")
            if token then
                return tonumber(token)
            end
        end
        return nil
    end
    local function parse_errors_from_message(message)
        if type(message) ~= "string" then
            return nil, nil
        end
        local pes = tonumber(message:match("[Pp][Ee][Ss]%s*[:=]%s*(%d+)"))
        local cc = tonumber(message:match("[Cc][Cc]%s*[:=]%s*(%d+)"))
        return cc, pes
    end
    local function parse_bitrate_from_message(message)
        if type(message) ~= "string" then
            return nil
        end
        local value, unit = message:match("[Bb]itrate%s*[:=]%s*(-?%d+%.?%d*)%s*([KkMmGg]?)")
        local num = tonumber(value)
        if not num then
            return nil
        end
        unit = string.lower(unit or "")
        if unit == "g" then
            num = num * 1000 * 1000
        elseif unit == "m" then
            num = num * 1000
        end
        return num
    end
    local buckets = {}
    for _, row in ipairs(rows) do
        local ts = tonumber(row.ts) or os.time()
        local bucket = calc_bucket(ts, interval)
        local stat = buckets[bucket]
        if not stat then
            stat = {
                alerts_error = 0,
                input_switch = 0,
                streams_down = 0,
                cc_errors = 0,
                pes_errors = 0,
                bitrate_sum = 0,
                bitrate_samples = 0,
            }
            buckets[bucket] = stat
        end
        local level = tostring(row.level or "")
        if level == "ERROR" or level == "CRITICAL" then
            stat.alerts_error = stat.alerts_error + 1
        end
        local code = tostring(row.component or "")
        if code == "INPUT_SWITCH" then
            stat.input_switch = stat.input_switch + 1
        elseif code == "STREAM_DOWN" then
            stat.streams_down = stat.streams_down + 1
        end

        local tags = type(row.tags) == "table" and row.tags or nil
        local cc = tags and to_number(tags.cc_errors) or nil
        local pes = tags and to_number(tags.pes_errors) or nil
        local bitrate = tags and (to_number(tags.bitrate_kbps) or to_number(tags.bitrate)) or nil

        if cc == nil or pes == nil then
            local msg_cc, msg_pes = parse_errors_from_message(row.message)
            if cc == nil then
                cc = msg_cc
            end
            if pes == nil then
                pes = msg_pes
            end
        end
        if bitrate == nil then
            bitrate = parse_bitrate_from_message(row.message)
        end

        if cc and cc > 0 then
            stat.cc_errors = stat.cc_errors + cc
        end
        if pes and pes > 0 then
            stat.pes_errors = stat.pes_errors + pes
        end
        if bitrate and bitrate > 0 then
            stat.bitrate_sum = stat.bitrate_sum + bitrate
            stat.bitrate_samples = stat.bitrate_samples + 1
        end
    end
    return buckets
end

function ai_observability.build_metrics_from_logs(range_sec, interval_sec, scope, scope_id)
    local interval = sanitize_interval(interval_sec or ai_observability.state.rollup_interval_sec)
    local buckets = count_from_logs(range_sec, scope, scope_id, interval)
    local items = {}
    for bucket, stat in pairs(buckets) do
        if stat.alerts_error and stat.alerts_error > 0 then
            table.insert(items, {
                ts_bucket = bucket,
                scope = scope or "global",
                scope_id = scope_id or "",
                metric_key = "alerts_error",
                value = stat.alerts_error,
            })
        end
        if stat.input_switch and stat.input_switch > 0 then
            table.insert(items, {
                ts_bucket = bucket,
                scope = scope or "global",
                scope_id = scope_id or "",
                metric_key = "input_switch",
                value = stat.input_switch,
            })
        end
        if stat.streams_down and stat.streams_down > 0 then
            table.insert(items, {
                ts_bucket = bucket,
                scope = scope or "global",
                scope_id = scope_id or "",
                metric_key = "streams_down",
                value = stat.streams_down,
            })
        end
        if scope == "stream" and scope_id and scope_id ~= "" then
            if stat.cc_errors and stat.cc_errors > 0 then
                table.insert(items, {
                    ts_bucket = bucket,
                    scope = "stream",
                    scope_id = scope_id,
                    metric_key = "cc_errors",
                    value = stat.cc_errors,
                })
            end
            if stat.pes_errors and stat.pes_errors > 0 then
                table.insert(items, {
                    ts_bucket = bucket,
                    scope = "stream",
                    scope_id = scope_id,
                    metric_key = "pes_errors",
                    value = stat.pes_errors,
                })
            end
            if stat.bitrate_samples and stat.bitrate_samples > 0 then
                table.insert(items, {
                    ts_bucket = bucket,
                    scope = "stream",
                    scope_id = scope_id,
                    metric_key = "bitrate_kbps",
                    value = stat.bitrate_sum / stat.bitrate_samples,
                })
            end
        end
    end
    table.sort(items, function(a, b)
        if a.ts_bucket == b.ts_bucket then
            return tostring(a.metric_key) < tostring(b.metric_key)
        end
        return a.ts_bucket < b.ts_bucket
    end)
    return items
end

local function extract_entry_bitrate(entry)
    if entry.transcode and entry.transcode.output_bitrate_kbps then
        return tonumber(entry.transcode.output_bitrate_kbps) or 0
    end
    if entry.transcode and entry.transcode.input_bitrate_kbps then
        return tonumber(entry.transcode.input_bitrate_kbps) or 0
    end
    return tonumber(entry.bitrate) or 0
end

function ai_observability.build_runtime_metrics(scope, scope_id, interval_sec, range_sec)
    if not runtime or not runtime.list_status then
        return nil
    end
    local interval = sanitize_interval(interval_sec or ai_observability.state.rollup_interval_sec)
    local sample_range = interval
    if type(range_sec) == "number" and range_sec > 0 then
        sample_range = math.max(interval, math.floor(range_sec))
    end
    local bucket = calc_bucket(os.time(), interval)
    local status = runtime.list_status() or {}
    local items = {}
    local function push_point(metric_key, value, ts_bucket)
        local v = tonumber(value)
        if not v then
            return
        end
        table.insert(items, {
            ts_bucket = ts_bucket or bucket,
            scope = scope or "global",
            scope_id = scope_id or "",
            metric_key = metric_key,
            value = v,
        })
    end
    local function push_series(metric_key, value)
        local v = tonumber(value) or 0
        local total_steps = math.max(0, math.floor(sample_range / interval))
        local slots = math.max(2, math.min(60, total_steps + 1))
        local stride = math.max(1, math.floor(total_steps / math.max(1, (slots - 1))))
        local start_bucket = bucket - (total_steps * interval)
        local seen = {}

        local function push(ts_bucket)
            if not ts_bucket or seen[ts_bucket] then
                return
            end
            seen[ts_bucket] = true
            table.insert(items, {
                ts_bucket = ts_bucket,
                scope = scope or "global",
                scope_id = scope_id or "",
                metric_key = metric_key,
                value = v,
            })
        end

        if total_steps <= 0 then
            push(bucket - interval)
            push(bucket)
            return
        end

        local step = 0
        while step <= total_steps do
            push(start_bucket + (step * interval))
            step = step + stride
        end
        push(bucket)
    end

    if scope == "stream" and scope_id and scope_id ~= "" then
        local entry = status[scope_id]
        if not entry then
            return nil
        end
        local bitrate = extract_entry_bitrate(entry)
        local on_air = entry.on_air == true or entry.transcode_state == "RUNNING"
        local cc_errors = tonumber(entry.cc_errors) or 0
        local pes_errors = tonumber(entry.pes_errors) or 0
        -- For per-stream mode we keep a single runtime snapshot point.
        -- Historical series should come from logs to avoid synthetic flat lines.
        push_point("bitrate_kbps", bitrate, bucket)
        push_point("on_air", on_air and 1 or 0, bucket)
        push_point("cc_errors", cc_errors, bucket)
        push_point("pes_errors", pes_errors, bucket)
        return {
            bucket = bucket,
            summary = {
                bitrate_kbps = bitrate,
                on_air = on_air,
                input_switch = 0,
                cc_errors = cc_errors,
                pes_errors = pes_errors,
            },
            items = items,
        }
    end

    local total_bitrate = 0
    local streams_total = 0
    local streams_on_air = 0
    local streams_down = 0
    for _, entry in pairs(status) do
        streams_total = streams_total + 1
        local on_air = entry.on_air == true or entry.transcode_state == "RUNNING"
        if on_air then
            streams_on_air = streams_on_air + 1
        else
            streams_down = streams_down + 1
        end
        total_bitrate = total_bitrate + extract_entry_bitrate(entry)
    end
    push_series("total_bitrate_kbps", total_bitrate)
    push_series("streams_on_air", streams_on_air)
    push_series("streams_down", streams_down)
    push_series("streams_total", streams_total)
    return {
        bucket = bucket,
        summary = {
            total_bitrate_kbps = total_bitrate,
            streams_on_air = streams_on_air,
            streams_down = streams_down,
            streams_total = streams_total,
            input_switch = 0,
            alerts_error = 0,
        },
        items = items,
    }
end

local function summarize_log_items(items)
    local totals = {
        alerts_error = 0,
        input_switch = 0,
        streams_down = 0,
    }
    for _, item in ipairs(items or {}) do
        if totals[item.metric_key] ~= nil then
            totals[item.metric_key] = totals[item.metric_key] + (tonumber(item.value) or 0)
        end
    end
    return totals
end

function ai_observability.get_on_demand_metrics(range_sec, interval_sec, scope, scope_id)
    local ttl = cache_ttl_sec()
    local now = os.time()
    prune_cache(now)
    local key = build_cache_key(range_sec, interval_sec, scope, scope_id)
    local cached = ai_observability.cache.metrics[key]
    if cached and ttl > 0 and (now - cached.ts) <= ttl then
        return cached
    end

    local interval = sanitize_interval(interval_sec or ai_observability.state.rollup_interval_sec)
    local items = ai_observability.build_metrics_from_logs(range_sec, interval, scope, scope_id)
    local snapshot = ai_observability.build_runtime_metrics(scope, scope_id, interval, range_sec)
    local dedup = {}
    for _, item in ipairs(items) do
        dedup[(tostring(item.ts_bucket or "") .. "|" .. tostring(item.metric_key or ""))] = true
    end
    if snapshot and snapshot.items then
        for _, item in ipairs(snapshot.items) do
            local key = tostring(item.ts_bucket or "") .. "|" .. tostring(item.metric_key or "")
            if not dedup[key] then
                dedup[key] = true
                table.insert(items, item)
            end
        end
    end

    local summary = snapshot and snapshot.summary or {}
    if scope ~= "stream" then
        local totals = summarize_log_items(items)
        summary.alerts_error = totals.alerts_error
        summary.input_switch = totals.input_switch
        if not summary.streams_down or summary.streams_down == 0 then
            summary.streams_down = totals.streams_down
        end
    end

    local result = {
        ts = now,
        items = items,
        summary = summary,
        bucket = snapshot and snapshot.bucket or nil,
        mode = "on_demand",
    }
    if ttl > 0 then
        ai_observability.cache.metrics[key] = result
    end
    return result
end

function ai_observability.configure()
    -- Default to disabled unless explicitly enabled via settings.
    local logs_days = setting_number("ai_logs_retention_days", 0)
    local rollup_interval = sanitize_interval(setting_number("ai_rollup_interval_sec", 60))
    local on_demand = setting_bool("ai_metrics_on_demand", true)
    if not on_demand then
        log.info("[observability] forcing on-demand metrics to reduce load")
        on_demand = true
    end
    local metrics_days = setting_number("ai_metrics_retention_days", on_demand and 0 or 30)

    ai_observability.state.logs_retention_days = math.max(0, math.floor(logs_days or 0))
    if on_demand then
        metrics_days = 0
    end
    ai_observability.state.metrics_retention_days = math.max(0, math.floor(metrics_days or 0))
    ai_observability.state.rollup_interval_sec = rollup_interval
    ai_observability.state.metrics_on_demand = on_demand == true

    ai_observability.state.enabled = (ai_observability.state.logs_retention_days > 0)
        or (ai_observability.state.metrics_retention_days > 0)

    if ai_observability.timer_rollup then
        ai_observability.timer_rollup:close()
        ai_observability.timer_rollup = nil
    end
    if ai_observability.timer_cleanup then
        ai_observability.timer_cleanup:close()
        ai_observability.timer_cleanup = nil
    end

    if ai_observability.state.enabled and not ai_observability.state.metrics_on_demand then
        ai_observability.timer_rollup = timer({
            interval = rollup_interval,
            callback = function()
                rollup_metrics()
            end,
        })
    end
    if ai_observability.state.enabled then
        ai_observability.timer_cleanup = timer({
            interval = 86400,
            callback = function()
                prune_data()
            end,
        })
        prune_data()
        if not ai_observability.state.metrics_on_demand then
            rollup_metrics()
        end
        log.info(string.format(
            "[observability] enabled: logs=%dd metrics=%dd rollup=%ds on_demand=%s",
            ai_observability.state.logs_retention_days,
            ai_observability.state.metrics_retention_days,
            ai_observability.state.rollup_interval_sec,
            ai_observability.state.metrics_on_demand and "true" or "false"
        ))
    else
        log.info("[observability] disabled")
    end
end
