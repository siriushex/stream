-- AstralAI observability: log ingest, metrics rollup, retention

ai_observability = ai_observability or {}

ai_observability.state = {
    enabled = false,
    logs_retention_days = 7,
    metrics_retention_days = 30,
    rollup_interval_sec = 60,
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
                until = bucket + interval,
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
    local fingerprint = string.md5(level .. "|" .. stream_id .. "|" .. code .. "|" .. message)
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

function ai_observability.configure()
    local logs_days = setting_number("ai_logs_retention_days", 7)
    local metrics_days = setting_number("ai_metrics_retention_days", 30)
    local rollup_interval = sanitize_interval(setting_number("ai_rollup_interval_sec", 60))

    ai_observability.state.logs_retention_days = math.max(0, math.floor(logs_days or 0))
    ai_observability.state.metrics_retention_days = math.max(0, math.floor(metrics_days or 0))
    ai_observability.state.rollup_interval_sec = rollup_interval

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

    if ai_observability.state.enabled then
        ai_observability.timer_rollup = timer({
            interval = rollup_interval,
            callback = function()
                rollup_metrics()
            end,
        })
        ai_observability.timer_cleanup = timer({
            interval = 86400,
            callback = function()
                prune_data()
            end,
        })
        prune_data()
        rollup_metrics()
        log.info(string.format(
            "[observability] enabled: logs=%dd metrics=%dd rollup=%ds",
            ai_observability.state.logs_retention_days,
            ai_observability.state.metrics_retention_days,
            ai_observability.state.rollup_interval_sec
        ))
    else
        log.info("[observability] disabled")
    end
end
