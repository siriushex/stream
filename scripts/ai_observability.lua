-- Stream observability: events + rollups in sqlite with master-switch collection gate.

ai_observability = ai_observability or {}

ai_observability.state = ai_observability.state or {
    collection_enabled = false,
    read_only_mode = true,
    logs_retention_days = 7,
    metrics_retention_days = 30,
    metrics_on_demand = true,
    rollup_interval_sec = 60,
    base_resolution_sec = 60,
    highres_resolution_sec = 10,
    highres_max_streams = 20,
    highres_enabled = true,
    stream_detail_enabled = true,
    stream_ffmpeg_metrics_enabled = true,
    highres_disabled_until_ts = 0,
    metrics_flush_ms = 0,
    metrics_rows_written = 0,
    metrics_rows_dropped = 0,
    metrics_db_busy_count = 0,
    high_cpu_since_ts = 0,
}

ai_observability.cache = ai_observability.cache or {
    metrics = {},
}

ai_observability.stream_samples = ai_observability.stream_samples or {}
ai_observability.prev_counters = ai_observability.prev_counters or {}
ai_observability.prev_on_air = ai_observability.prev_on_air or {}
ai_observability.on_air_last_change = ai_observability.on_air_last_change or {}
ai_observability.restart_marker = ai_observability.restart_marker or {}
ai_observability.highres_pool = ai_observability.highres_pool or {}
ai_observability.last_rollup_bucket = ai_observability.last_rollup_bucket or {}

ai_observability.timer_base = ai_observability.timer_base or nil
ai_observability.timer_highres = ai_observability.timer_highres or nil
ai_observability.timer_cleanup = ai_observability.timer_cleanup or nil

local METRIC = {
    stream_bitrate = "stream.bitrate_kbps.avg",
    stream_cc_delta = "stream.cc_errors.delta",
    stream_pes_delta = "stream.pes_errors.delta",
    stream_on_air_state = "stream.on_air.state",
    stream_input_switch = "stream.input_switch.count",
    stream_ffmpeg_restart_total = "stream.ffmpeg.restart.total",
    stream_ffmpeg_restart_no_progress = "stream.ffmpeg.restart.no_progress",
    stream_ffmpeg_restart_exit_unexpected = "stream.ffmpeg.restart.exit_unexpected",
    stream_ffmpeg_restart_output_backpressure = "stream.ffmpeg.restart.output_backpressure",
    stream_ffmpeg_restart_output_probe_fail = "stream.ffmpeg.restart.output_probe_fail",
    stream_ffmpeg_spawn_fail = "stream.ffmpeg.spawn_fail.count",
}

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

local function setting_cache_ttl_sec()
    local ttl = setting_number("ai_metrics_cache_sec", 30)
    if ttl < 0 then ttl = 0 end
    if ttl > 300 then ttl = 300 end
    return math.floor(ttl)
end

local function sanitize_interval(value, min_value, max_value, fallback)
    local num = tonumber(value) or tonumber(fallback) or 60
    if num < (min_value or 1) then
        num = min_value or 1
    end
    if num > (max_value or 3600) then
        num = max_value or 3600
    end
    return math.floor(num)
end

local function calc_bucket(ts, interval_sec)
    local step = sanitize_interval(interval_sec, 1, 86400, 60)
    return math.floor((tonumber(ts) or os.time()) / step) * step
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
    local ttl = setting_cache_ttl_sec()
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

local function collection_enabled()
    return ai_observability.state.collection_enabled == true
end

function ai_observability.is_collection_enabled()
    return collection_enabled()
end

local function is_read_only_mode()
    return ai_observability.state.read_only_mode == true
end

function ai_observability.is_read_only_mode()
    return is_read_only_mode()
end

local function push_row(rows, row)
    rows[#rows + 1] = row
end

local function metric_row(ts_bucket, scope, scope_id, metric_key, value, resolution_sec, mode, tags)
    return {
        ts_bucket = ts_bucket,
        scope = scope,
        scope_id = scope_id,
        metric_key = metric_key,
        value = tonumber(value) or 0,
        resolution_sec = resolution_sec,
        mode = mode,
        tags = tags,
    }
end

local function extract_entry_bitrate(entry)
    if entry and entry.transcode and entry.transcode.output_bitrate_kbps then
        return tonumber(entry.transcode.output_bitrate_kbps) or 0
    end
    if entry and entry.transcode and entry.transcode.input_bitrate_kbps then
        return tonumber(entry.transcode.input_bitrate_kbps) or 0
    end
    return tonumber(entry and entry.bitrate) or 0
end

local function extract_entry_on_air(entry)
    return entry and (entry.on_air == true or entry.transcode_state == "RUNNING")
end

local function extract_entry_cc_pes(entry)
    local cc = tonumber(entry and entry.cc_errors) or 0
    local pes = tonumber(entry and entry.pes_errors) or 0
    if entry and type(entry.transcode) == "table" then
        if cc <= 0 then
            cc = tonumber(entry.transcode.cc_errors) or cc
        end
        if pes <= 0 then
            pes = tonumber(entry.transcode.pes_errors) or pes
        end
    end
    return cc, pes
end

local function normalize_restart_reason(reason)
    local code = tostring(reason or ""):upper()
    if code == "" then
        return nil, nil
    end
    if code == "NO_PROGRESS" or code == "TRANSCODE_STALL" or code == "PUBLISH_NO_PROGRESS" then
        return "no_progress", METRIC.stream_ffmpeg_restart_no_progress
    end
    if code == "EXIT_UNEXPECTED" then
        return "exit_unexpected", METRIC.stream_ffmpeg_restart_exit_unexpected
    end
    if code == "OUTPUT_BACKPRESSURE" then
        return "output_backpressure", METRIC.stream_ffmpeg_restart_output_backpressure
    end
    if code == "OUTPUT_PROBE_FAIL" or code == "TRANSCODE_PROBE_FAILED" then
        return "output_probe_fail", METRIC.stream_ffmpeg_restart_output_probe_fail
    end
    if code == "TRANSCODE_SPAWN_FAILED" or code == "PUBLISH_SPAWN_FAILED" then
        return "spawn_fail", METRIC.stream_ffmpeg_spawn_fail
    end
    return string.lower(code), nil
end

local function extract_restart_event_marker(stream_id, entry, bucket)
    if not entry or type(entry.transcode) ~= "table" then
        return nil, nil
    end
    local reason = entry.transcode.restart_reason_code or entry.transcode.last_forced_restart_reason
    local reason_code, _ = normalize_restart_reason(reason)
    if not reason_code then
        return nil, nil
    end
    local ts = tonumber(entry.transcode.last_forced_restart_ts)
        or tonumber(entry.transcode.last_error_ts)
        or tonumber(entry.transcode.updated_at)
        or bucket
    local marker = tostring(stream_id or "") .. "|" .. tostring(reason_code) .. "|" .. tostring(ts)
    return marker, reason_code
end

local function compute_cc_pes_delta(stream_id, resolution_sec, cc, pes)
    local key = tostring(resolution_sec) .. "|" .. tostring(stream_id)
    local prev = ai_observability.prev_counters[key] or {}
    local prev_cc = tonumber(prev.cc) or 0
    local prev_pes = tonumber(prev.pes) or 0
    local delta_cc = (tonumber(cc) or 0) - prev_cc
    local delta_pes = (tonumber(pes) or 0) - prev_pes
    if delta_cc < 0 then delta_cc = 0 end
    if delta_pes < 0 then delta_pes = 0 end
    ai_observability.prev_counters[key] = { cc = tonumber(cc) or 0, pes = tonumber(pes) or 0 }
    return delta_cc, delta_pes
end

local function update_highres_pool_from_incidents(incidents)
    local now = os.time()
    local pool = ai_observability.highres_pool or {}
    local ttl = 3600
    local demote_grace = 1800
    local max_streams = sanitize_interval(
        setting_number("observability_stream_highres_max_streams", ai_observability.state.highres_max_streams or 20),
        1, 200, 20
    )
    ai_observability.state.highres_max_streams = max_streams

    for stream_id, severity in pairs(incidents or {}) do
        local current = pool[stream_id] or {}
        current.until_ts = math.max(tonumber(current.until_ts) or 0, now + ttl)
        current.last_incident_ts = now
        current.last_seen_ts = now
        current.severity = math.max(tonumber(current.severity) or 0, tonumber(severity) or 1)
        pool[stream_id] = current
    end

    for stream_id, item in pairs(pool) do
        local until_ts = tonumber(item.until_ts) or 0
        local last_incident_ts = tonumber(item.last_incident_ts) or 0
        if now > until_ts and (now - last_incident_ts) > demote_grace then
            pool[stream_id] = nil
        end
    end

    local ids = {}
    for stream_id, item in pairs(pool) do
        ids[#ids + 1] = {
            stream_id = stream_id,
            severity = tonumber(item.severity) or 0,
            until_ts = tonumber(item.until_ts) or 0,
            last_incident_ts = tonumber(item.last_incident_ts) or 0,
        }
    end
    table.sort(ids, function(a, b)
        if a.severity ~= b.severity then
            return a.severity > b.severity
        end
        if a.last_incident_ts ~= b.last_incident_ts then
            return a.last_incident_ts > b.last_incident_ts
        end
        return tostring(a.stream_id) < tostring(b.stream_id)
    end)
    for idx = max_streams + 1, #ids do
        pool[ids[idx].stream_id] = nil
    end
    ai_observability.highres_pool = pool
end

local function build_selected_stream_ids(status)
    local out = {}
    local pool = ai_observability.highres_pool or {}
    for stream_id, _ in pairs(pool) do
        if status[stream_id] then
            out[#out + 1] = stream_id
        end
    end
    table.sort(out)
    return out
end

local function write_rows_batch(rows)
    if not config or not config.upsert_ai_metrics_batch then
        return nil, "batch writer unavailable"
    end
    if #rows == 0 then
        return true
    end
    local started = os.clock()
    local ok, err = config.upsert_ai_metrics_batch(rows)
    local elapsed_ms = math.floor(((os.clock() - started) * 1000) + 0.5)
    ai_observability.state.metrics_flush_ms = elapsed_ms
    if ok then
        ai_observability.state.metrics_rows_written = (tonumber(ai_observability.state.metrics_rows_written) or 0) + #rows
        return true
    end
    ai_observability.state.metrics_rows_dropped = (tonumber(ai_observability.state.metrics_rows_dropped) or 0) + #rows
    if tostring(err or ""):lower():find("busy", 1, true) then
        ai_observability.state.metrics_db_busy_count = (tonumber(ai_observability.state.metrics_db_busy_count) or 0) + 1
        ai_observability.state.highres_disabled_until_ts = os.time() + 120
    end
    return nil, err
end

local function prune_data()
    if not collection_enabled() then
        return
    end
    local now = os.time()
    local logs_days = tonumber(ai_observability.state.logs_retention_days) or 0
    local metrics_days = tonumber(ai_observability.state.metrics_retention_days) or 0
    if logs_days > 0 and config and config.prune_ai_log_events then
        config.prune_ai_log_events(now - (logs_days * 86400))
    end
    if metrics_days > 0 and config and config.prune_ai_metrics then
        config.prune_ai_metrics(now - (metrics_days * 86400))
    end
end

local function collect_rollup(resolution_sec, selected_stream_ids)
    if not collection_enabled() then
        return
    end
    if (tonumber(ai_observability.state.metrics_retention_days) or 0) <= 0 then
        return
    end
    if not runtime or not runtime.list_status then
        return
    end

    local now = os.time()
    local bucket = calc_bucket(now, resolution_sec)
    local bucket_key = tostring(resolution_sec)
    if ai_observability.last_rollup_bucket[bucket_key] == bucket then
        return
    end
    ai_observability.last_rollup_bucket[bucket_key] = bucket

    local status = runtime.list_status() or {}
    local ids = {}
    if type(selected_stream_ids) == "table" then
        for _, sid in ipairs(selected_stream_ids) do
            if status[sid] then
                ids[#ids + 1] = sid
            end
        end
    else
        for sid, _ in pairs(status) do
            ids[#ids + 1] = sid
        end
        table.sort(ids)
    end

    local rows = {}
    local incidents = {}

    local global_total_bitrate = 0
    local global_streams_total = 0
    local global_streams_on_air = 0
    local global_streams_down = 0
    local global_switches = 0

    for _, stream_id in ipairs(ids) do
        local entry = status[stream_id]
        local sid = tostring(stream_id)
        local on_air = extract_entry_on_air(entry) == true
        local bitrate = extract_entry_bitrate(entry)
        local cc_abs, pes_abs = extract_entry_cc_pes(entry)
        local cc_delta, pes_delta = compute_cc_pes_delta(sid, resolution_sec, cc_abs, pes_abs)

        push_row(rows, metric_row(bucket, "stream", sid, METRIC.stream_bitrate, bitrate, resolution_sec))
        push_row(rows, metric_row(bucket, "stream", sid, "bitrate_kbps", bitrate, resolution_sec))
        push_row(rows, metric_row(bucket, "stream", sid, "on_air", on_air and 1 or 0, resolution_sec))

        local prev_on_air = ai_observability.prev_on_air[sid]
        if prev_on_air == nil or prev_on_air ~= on_air then
            push_row(rows, metric_row(bucket, "stream", sid, METRIC.stream_on_air_state, on_air and 1 or 0, resolution_sec))
            local prev_change = tonumber(ai_observability.on_air_last_change[sid]) or 0
            if prev_on_air ~= nil and prev_change > 0 and (now - prev_change) < 180 then
                incidents[sid] = math.max(tonumber(incidents[sid]) or 0, 1)
            end
            ai_observability.on_air_last_change[sid] = now
        end
        ai_observability.prev_on_air[sid] = on_air

        if cc_delta > 0 then
            push_row(rows, metric_row(bucket, "stream", sid, METRIC.stream_cc_delta, cc_delta, resolution_sec, "sum"))
            push_row(rows, metric_row(bucket, "stream", sid, "cc_errors", cc_delta, resolution_sec, "sum"))
            incidents[sid] = math.max(tonumber(incidents[sid]) or 0, 1)
        end
        if pes_delta > 0 then
            push_row(rows, metric_row(bucket, "stream", sid, METRIC.stream_pes_delta, pes_delta, resolution_sec, "sum"))
            push_row(rows, metric_row(bucket, "stream", sid, "pes_errors", pes_delta, resolution_sec, "sum"))
            incidents[sid] = math.max(tonumber(incidents[sid]) or 0, 1)
        end

        local switched = 0
        if entry and entry.last_switch then
            local switched_ts = tonumber(entry.last_switch)
            if switched_ts and switched_ts >= bucket and switched_ts < (bucket + resolution_sec) then
                switched = 1
            end
        end
        if switched > 0 then
            push_row(rows, metric_row(bucket, "stream", sid, METRIC.stream_input_switch, switched, resolution_sec, "sum"))
            push_row(rows, metric_row(bucket, "stream", sid, "input_switch", switched, resolution_sec, "sum"))
        end

        if ai_observability.state.stream_ffmpeg_metrics_enabled then
            local marker, reason_code = extract_restart_event_marker(sid, entry, bucket)
            if marker and reason_code then
                local prev_marker = ai_observability.restart_marker[sid]
                if prev_marker ~= marker then
                    ai_observability.restart_marker[sid] = marker
                    push_row(rows, metric_row(
                        bucket, "stream", sid, METRIC.stream_ffmpeg_restart_total, 1, resolution_sec, "sum",
                        { reason_code = reason_code }
                    ))
                    local _, reason_metric = normalize_restart_reason(reason_code)
                    if reason_metric then
                        push_row(rows, metric_row(
                            bucket, "stream", sid, reason_metric, 1, resolution_sec, "sum",
                            { reason_code = reason_code }
                        ))
                    end
                    incidents[sid] = math.max(tonumber(incidents[sid]) or 0, 2)
                end
            end
        end

        global_streams_total = global_streams_total + 1
        global_total_bitrate = global_total_bitrate + bitrate
        if on_air then
            global_streams_on_air = global_streams_on_air + 1
        else
            global_streams_down = global_streams_down + 1
        end
        global_switches = global_switches + switched
    end

    if type(selected_stream_ids) ~= "table" then
        push_row(rows, metric_row(bucket, "global", "", "total_bitrate_kbps", global_total_bitrate, resolution_sec))
        push_row(rows, metric_row(bucket, "global", "", "streams_total", global_streams_total, resolution_sec))
        push_row(rows, metric_row(bucket, "global", "", "streams_on_air", global_streams_on_air, resolution_sec))
        push_row(rows, metric_row(bucket, "global", "", "streams_down", global_streams_down, resolution_sec))
        if global_switches > 0 then
            push_row(rows, metric_row(bucket, "global", "", "input_switch", global_switches, resolution_sec, "sum"))
        end
        if config and config.count_alerts then
            local errors = config.count_alerts({
                since = bucket,
                ["until"] = bucket + resolution_sec,
                levels = { "ERROR", "CRITICAL" },
            })
            push_row(rows, metric_row(bucket, "global", "", "alerts_error", errors, resolution_sec))
        end
    end

    local ok, err = write_rows_batch(rows)
    if not ok then
        log.warning("[observability] metric flush failed: " .. tostring(err))
    end
    return incidents
end

local function base_rollup_tick()
    local incidents = collect_rollup(ai_observability.state.base_resolution_sec, nil) or {}
    update_highres_pool_from_incidents(incidents)
end

local function highres_rollup_tick()
    if not collection_enabled() then
        return
    end
    if ai_observability.state.highres_enabled ~= true then
        return
    end
    local now = os.time()
    if now < (tonumber(ai_observability.state.highres_disabled_until_ts) or 0) then
        return
    end
    local cpu_disable_pct = sanitize_interval(
        setting_number("observability_stream_highres_cpu_disable_pct", 80),
        1, 100, 80
    )
    local cpu_disable_window_sec = sanitize_interval(
        setting_number("observability_stream_highres_cpu_disable_window_sec", 120),
        10, 600, 120
    )
    if system_metrics and system_metrics.snapshot then
        local snap = system_metrics.snapshot()
        local cpu_usage = tonumber(snap and snap.cpu and snap.cpu.usage)
        if cpu_usage and cpu_usage > (cpu_disable_pct / 100) then
            if (tonumber(ai_observability.state.high_cpu_since_ts) or 0) <= 0 then
                ai_observability.state.high_cpu_since_ts = now
            elseif now - ai_observability.state.high_cpu_since_ts >= cpu_disable_window_sec then
                ai_observability.state.highres_disabled_until_ts = now + 120
                return
            end
        else
            ai_observability.state.high_cpu_since_ts = 0
        end
    end
    if not runtime or not runtime.list_status then
        return
    end
    local status = runtime.list_status() or {}
    local selected = build_selected_stream_ids(status)
    if #selected == 0 then
        return
    end
    collect_rollup(ai_observability.state.highres_resolution_sec, selected)
end

function ai_observability.ingest_alert(entry)
    if not collection_enabled() then
        return
    end
    if (tonumber(ai_observability.state.logs_retention_days) or 0) <= 0 then
        return
    end
    if not config or not config.add_ai_log_event or type(entry) ~= "table" then
        return
    end
    local ts = tonumber(entry.ts) or os.time()
    local level = tostring(entry.level or "INFO")
    local stream_id = tostring(entry.stream_id or "")
    local code = tostring(entry.code or "alert")
    local message = tostring(entry.message or "")
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

function ai_observability.ingest_stream_sample(stream_id, sample)
    if not collection_enabled() then
        return
    end
    if (tonumber(ai_observability.state.logs_retention_days) or 0) <= 0 then
        return
    end
    if not config or not config.add_ai_log_event then
        return
    end
    if not stream_id or stream_id == "" or type(sample) ~= "table" then
        return
    end
    local interval = sanitize_interval(
        setting_number("ai_stream_sample_interval_sec", ai_observability.state.rollup_interval_sec or 60),
        10, 3600, 60
    )
    local ts = tonumber(sample.ts) or os.time()
    local bucket = calc_bucket(ts, interval)
    local sid = tostring(stream_id)
    if ai_observability.stream_samples[sid] == bucket then
        return
    end
    ai_observability.stream_samples[sid] = bucket
    local tags = {
        bitrate_kbps = tonumber(sample.bitrate_kbps) or tonumber(sample.bitrate) or 0,
        cc_errors = tonumber(sample.cc_errors) or 0,
        pes_errors = tonumber(sample.pes_errors) or 0,
        on_air = sample.on_air == true and 1 or 0,
    }
    local fingerprint = string.lower(string.hex(string.md5("STREAM_SAMPLE|" .. sid .. "|" .. tostring(bucket))))
    config.add_ai_log_event({
        ts = bucket,
        level = "INFO",
        stream_id = sid,
        component = "STREAM_SAMPLE",
        message = "runtime sample",
        fingerprint = fingerprint,
        tags = tags,
    })
end

local function count_from_logs(range_sec, scope, scope_id, interval)
    if not config or not config.list_ai_log_events then
        return {}
    end
    local since_ts = os.time() - (range_sec or 86400)
    local span = math.max(1, tonumber(range_sec) or 86400)
    local step = math.max(1, tonumber(interval) or 60)
    local target_points = math.floor(span / step)
    local burst = (scope == "stream" and 8 or 4)
    local hard_cap = (scope == "stream" and 20000 or 50000)
    local limit = math.max(2000, math.min(hard_cap, target_points * burst))
    local query = {
        since = since_ts,
        ["until"] = nil,
        limit = limit,
    }
    if scope == "stream" and scope_id and scope_id ~= "" then
        query.stream_id = tostring(scope_id)
    end
    local rows = config.list_ai_log_events(query) or {}
    local buckets = {}
    local function to_num(v)
        local n = tonumber(v)
        if n ~= nil then
            return n
        end
        return nil
    end
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
        local cc = tags and to_num(tags.cc_errors) or nil
        local pes = tags and to_num(tags.pes_errors) or nil
        local bitrate = tags and (to_num(tags.bitrate_kbps) or to_num(tags.bitrate)) or nil
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
    local interval = sanitize_interval(interval_sec or ai_observability.state.rollup_interval_sec, 10, 3600, 60)
    local buckets = count_from_logs(range_sec, scope, scope_id, interval)
    local items = {}
    for bucket, stat in pairs(buckets) do
        if stat.alerts_error and stat.alerts_error > 0 then
            push_row(items, metric_row(bucket, scope or "global", scope_id or "", "alerts_error", stat.alerts_error, interval))
        end
        if stat.input_switch and stat.input_switch > 0 then
            push_row(items, metric_row(bucket, scope or "global", scope_id or "", "input_switch", stat.input_switch, interval))
        end
        if stat.streams_down and stat.streams_down > 0 then
            push_row(items, metric_row(bucket, scope or "global", scope_id or "", "streams_down", stat.streams_down, interval))
        end
        if scope == "stream" and scope_id and scope_id ~= "" then
            if stat.cc_errors and stat.cc_errors > 0 then
                push_row(items, metric_row(bucket, "stream", scope_id, "cc_errors", stat.cc_errors, interval))
            end
            if stat.pes_errors and stat.pes_errors > 0 then
                push_row(items, metric_row(bucket, "stream", scope_id, "pes_errors", stat.pes_errors, interval))
            end
            if stat.bitrate_samples and stat.bitrate_samples > 0 then
                push_row(items, metric_row(bucket, "stream", scope_id, "bitrate_kbps", stat.bitrate_sum / stat.bitrate_samples, interval))
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

function ai_observability.build_runtime_metrics(scope, scope_id, interval_sec, range_sec)
    if not runtime or not runtime.list_status then
        return nil
    end
    local interval = sanitize_interval(interval_sec or ai_observability.state.rollup_interval_sec, 10, 3600, 60)
    local bucket = calc_bucket(os.time(), interval)
    local sample_range = math.max(interval, math.floor(tonumber(range_sec) or interval))
    local status = runtime.list_status() or {}
    local items = {}
    local function push_point(metric_key, value, ts_bucket)
        push_row(items, metric_row(ts_bucket or bucket, scope or "global", scope_id or "", metric_key, value, interval))
    end
    local function push_series(metric_key, value)
        local v = tonumber(value) or 0
        local steps = math.max(0, math.floor(sample_range / interval))
        local slots = math.max(2, math.min(60, steps + 1))
        local stride = math.max(1, math.floor(steps / math.max(1, slots - 1)))
        local start_bucket = bucket - (steps * interval)
        local seen = {}
        local step = 0
        while step <= steps do
            local tsb = start_bucket + (step * interval)
            if not seen[tsb] then
                seen[tsb] = true
                push_point(metric_key, v, tsb)
            end
            step = step + stride
        end
        if not seen[bucket] then
            push_point(metric_key, v, bucket)
        end
    end

    if scope == "stream" and scope_id and scope_id ~= "" then
        local entry = status[scope_id]
        if not entry then
            return nil
        end
        local bitrate = extract_entry_bitrate(entry)
        local on_air = extract_entry_on_air(entry)
        local cc_errors, pes_errors = extract_entry_cc_pes(entry)
        push_series("bitrate_kbps", bitrate)
        push_series("on_air", on_air and 1 or 0)
        push_series("cc_errors", cc_errors)
        push_series("pes_errors", pes_errors)
        local switch_count = 0
        if entry.last_switch then
            local switch_ts = tonumber(entry.last_switch)
            if switch_ts and switch_ts >= (bucket - sample_range) and switch_ts <= bucket then
                switch_count = 1
                push_point("input_switch", 1, calc_bucket(switch_ts, interval))
            end
        end
        return {
            bucket = bucket,
            summary = {
                bitrate_kbps = bitrate,
                on_air = on_air,
                cc_errors = cc_errors,
                pes_errors = pes_errors,
                input_switch = switch_count,
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
        if extract_entry_on_air(entry) then
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

function ai_observability.get_on_demand_metrics(range_sec, interval_sec, scope, scope_id)
    local now = os.time()
    prune_cache(now)
    local key = build_cache_key(range_sec, interval_sec, scope, scope_id)
    local cached = ai_observability.cache.metrics[key]
    local ttl = setting_cache_ttl_sec()
    if cached and ttl > 0 and (now - cached.ts) <= ttl then
        return cached
    end
    local interval = sanitize_interval(interval_sec or ai_observability.state.rollup_interval_sec, 10, 3600, 60)
    local items = ai_observability.build_metrics_from_logs(range_sec, interval, scope, scope_id)
    local snapshot = nil
    if collection_enabled() then
        snapshot = ai_observability.build_runtime_metrics(scope, scope_id, interval, range_sec)
    end
    local dedup = {}
    for _, item in ipairs(items) do
        dedup[tostring(item.ts_bucket or "") .. "|" .. tostring(item.metric_key or "")] = true
    end
    if snapshot and snapshot.items then
        for _, item in ipairs(snapshot.items) do
            local uniq = tostring(item.ts_bucket or "") .. "|" .. tostring(item.metric_key or "")
            if not dedup[uniq] then
                dedup[uniq] = true
                items[#items + 1] = item
            end
        end
    end
    local summary = snapshot and snapshot.summary or {}
    if not summary then
        summary = {}
    end
    local has_runtime_summary = snapshot and snapshot.summary and next(snapshot.summary) ~= nil
    if not has_runtime_summary then
        local accum = {}
        local max_seen = {}
        local function add_sum(key, value)
            local num = tonumber(value) or 0
            accum[key] = (tonumber(accum[key]) or 0) + num
        end
        local function set_max(key, value)
            local num = tonumber(value)
            if num == nil then
                return
            end
            local prev = tonumber(max_seen[key])
            if prev == nil or num > prev then
                max_seen[key] = num
            end
        end
        for _, item in ipairs(items) do
            local key = tostring(item.metric_key or "")
            local value = tonumber(item.value) or 0
            if key == "alerts_error" or key == "input_switch" or key == "streams_down" then
                add_sum(key, value)
            elseif key == "bitrate_kbps" then
                set_max("bitrate_kbps", value)
            elseif key == "cc_errors" or key == "pes_errors" then
                add_sum(key, value)
            elseif key == "on_air" then
                set_max("on_air", value)
            elseif key == "total_bitrate_kbps" or key == "streams_total" or key == "streams_on_air" then
                set_max(key, value)
            end
        end
        for key, value in pairs(accum) do
            summary[key] = value
        end
        for key, value in pairs(max_seen) do
            if summary[key] == nil then
                summary[key] = value
            end
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

local function select_resolution(range_sec, requested)
    if requested == "10s" then
        return 10
    end
    if requested == "60s" then
        return 60
    end
    local range = tonumber(range_sec) or 0
    if range > 0 and range <= (72 * 3600) then
        return 10
    end
    return 60
end

local function normalize_metric_alias(metric)
    local key = tostring(metric or "")
    if key == "" then
        return nil
    end
    local map = {
        bitrate = METRIC.stream_bitrate,
        bitrate_kbps = METRIC.stream_bitrate,
        cc_errors = METRIC.stream_cc_delta,
        pes_errors = METRIC.stream_pes_delta,
        input_switch = METRIC.stream_input_switch,
        on_air = METRIC.stream_on_air_state,
        ffmpeg_restarts = METRIC.stream_ffmpeg_restart_total,
        ffmpeg_restart_total = METRIC.stream_ffmpeg_restart_total,
    }
    return map[key] or key
end

local function downsample_points_minmax(points, max_points)
    if type(points) ~= "table" then
        return {}
    end
    local total = #points
    if total <= max_points then
        return points
    end
    if max_points <= 2 then
        return { points[1], points[total] }
    end
    local bucket_count = math.max(1, math.floor(max_points / 2))
    local bucket_size = total / bucket_count
    local out = {}
    for bucket = 0, bucket_count - 1 do
        local start_idx = math.floor(bucket * bucket_size) + 1
        local end_idx = math.min(total, math.floor((bucket + 1) * bucket_size))
        local min_idx = start_idx
        local max_idx = start_idx
        for i = start_idx, end_idx do
            local y = tonumber(points[i].value)
            local min_y = tonumber(points[min_idx].value)
            local max_y = tonumber(points[max_idx].value)
            if y and (not min_y or y < min_y) then
                min_idx = i
            end
            if y and (not max_y or y > max_y) then
                max_idx = i
            end
        end
        if min_idx == max_idx then
            out[#out + 1] = points[min_idx]
        elseif min_idx < max_idx then
            out[#out + 1] = points[min_idx]
            out[#out + 1] = points[max_idx]
        else
            out[#out + 1] = points[max_idx]
            out[#out + 1] = points[min_idx]
        end
        if #out >= max_points then
            break
        end
    end
    if out[#out] ~= points[total] and #out < max_points then
        out[#out + 1] = points[total]
    end
    if #out > max_points then
        while #out > max_points do
            table.remove(out, #out - 1)
        end
    end
    return out
end

function ai_observability.get_stream_series(opts)
    opts = opts or {}
    local stream_id = tostring(opts.stream_id or "")
    if stream_id == "" then
        return nil, "stream_id required"
    end
    local range_sec = tonumber(opts.range_sec) or (24 * 3600)
    local requested = tostring(opts.resolution or "auto")
    local resolution = select_resolution(range_sec, requested)
    if resolution == 10 and ai_observability.state.highres_enabled ~= true then
        resolution = 60
    end
    local now = os.time()
    local since_ts = now - range_sec
    local max_points = sanitize_interval(opts.max_points or 1200, 50, 5000, 1200)
    local metrics = {}
    if type(opts.metrics) == "table" and #opts.metrics > 0 then
        for _, metric in ipairs(opts.metrics) do
            local key = normalize_metric_alias(metric)
            if key then
                metrics[#metrics + 1] = key
            end
        end
    end
    if #metrics == 0 then
        metrics = {
            METRIC.stream_bitrate,
            METRIC.stream_cc_delta,
            METRIC.stream_pes_delta,
            METRIC.stream_ffmpeg_restart_total,
        }
    end
    local fallback_map = {
        bitrate_kbps = METRIC.stream_bitrate,
        cc_errors = METRIC.stream_cc_delta,
        pes_errors = METRIC.stream_pes_delta,
        input_switch = METRIC.stream_input_switch,
        on_air = METRIC.stream_on_air_state,
    }
    local query_keys = {}
    local seen = {}
    for _, key in ipairs(metrics) do
        if not seen[key] then
            seen[key] = true
            query_keys[#query_keys + 1] = key
        end
    end
    for fallback_key, mapped in pairs(fallback_map) do
        if seen[mapped] and not seen[fallback_key] then
            seen[fallback_key] = true
            query_keys[#query_keys + 1] = fallback_key
        end
    end
    local rows = {}
    if config and config.list_ai_metrics then
        rows = config.list_ai_metrics({
            since = since_ts,
            ["until"] = now + 1,
            scope = "stream",
            scope_id = stream_id,
            metric_keys = query_keys,
            resolution_sec = resolution,
            limit = 200000,
        }) or {}
    end
    local series = {}
    for _, key in ipairs(metrics) do
        series[key] = {}
    end
    for _, row in ipairs(rows) do
        local key = tostring(row.metric_key or "")
        local target_key = series[key] and key or fallback_map[key]
        if target_key and series[target_key] then
            series[target_key][#series[target_key] + 1] = {
                ts = tonumber(row.ts_bucket) or 0,
                value = tonumber(row.value) or 0,
                tags = row.tags,
            }
        end
    end
    local downsampled = false
    for key, points in pairs(series) do
        table.sort(points, function(a, b) return (a.ts or 0) < (b.ts or 0) end)
        if #points > max_points then
            series[key] = downsample_points_minmax(points, max_points)
            downsampled = true
        end
    end
    return {
        series = series,
        meta = {
            resolution_used = tostring(resolution) .. "s",
            from = since_ts,
            to = now,
            downsampled = downsampled,
            collection_enabled = collection_enabled(),
            read_only_mode = is_read_only_mode(),
        },
    }
end

function ai_observability.get_stream_events(opts)
    opts = opts or {}
    local stream_id = tostring(opts.stream_id or "")
    if stream_id == "" then
        return nil, "stream_id required"
    end
    if not config or not config.list_ai_log_events then
        return {
            items = {},
            meta = {
                collection_enabled = collection_enabled(),
                read_only_mode = is_read_only_mode(),
            },
        }
    end
    local range_sec = tonumber(opts.range_sec) or (24 * 3600)
    local now = os.time()
    local since_ts = now - range_sec
    local limit = sanitize_interval(opts.limit or 300, 1, 5000, 300)
    local kinds_map = {}
    if type(opts.kinds) == "table" then
        for _, item in ipairs(opts.kinds) do
            kinds_map[tostring(item or "")] = true
        end
    else
        kinds_map.ffmpeg = true
        kinds_map.input_switch = true
        kinds_map.alerts = true
    end
    local rows = config.list_ai_log_events({
        since = since_ts,
        ["until"] = now + 1,
        stream_id = stream_id,
        limit = limit,
        order = "desc",
    }) or {}
    local items = {}
    for _, row in ipairs(rows) do
        local code = tostring(row.component or "")
        local include = false
        if kinds_map.input_switch and code == "INPUT_SWITCH" then
            include = true
        end
        local reason_code, _ = normalize_restart_reason(code)
        if kinds_map.ffmpeg and reason_code then
            include = true
        end
        if kinds_map.alerts and (row.level == "ERROR" or row.level == "CRITICAL") then
            include = true
        end
        if include then
            items[#items + 1] = {
                ts = tonumber(row.ts) or 0,
                severity = tostring(row.level or "INFO"),
                code = code,
                reason_code = reason_code,
                message = tostring(row.message or ""),
                tags = row.tags,
            }
        end
    end
    return {
        items = items,
        meta = {
            from = since_ts,
            to = now,
            collection_enabled = collection_enabled(),
            read_only_mode = is_read_only_mode(),
        },
    }
end

function ai_observability.configure()
    local master_enabled = setting_bool("observability_enabled", false)
    local logs_days = math.max(0, math.floor(setting_number("ai_logs_retention_days", 7) or 7))
    local metrics_days = math.max(0, math.floor(setting_number("ai_metrics_retention_days", 30) or 30))
    local on_demand = setting_bool("ai_metrics_on_demand", true)
    local rollup_interval = sanitize_interval(setting_number("ai_rollup_interval_sec", 60), 10, 3600, 60)
    if master_enabled and metrics_days <= 0 then
        metrics_days = 30
    end

    ai_observability.state.collection_enabled = master_enabled == true
    ai_observability.state.read_only_mode = not ai_observability.state.collection_enabled
    ai_observability.state.logs_retention_days = logs_days
    ai_observability.state.metrics_retention_days = metrics_days
    ai_observability.state.metrics_on_demand = on_demand == true
    ai_observability.state.rollup_interval_sec = rollup_interval
    ai_observability.state.base_resolution_sec = 60
    ai_observability.state.highres_resolution_sec = 10
    ai_observability.state.stream_detail_enabled = setting_bool("observability_stream_detail_enabled", true)
    ai_observability.state.highres_enabled = setting_bool("observability_stream_highres_enabled", true)
    ai_observability.state.stream_ffmpeg_metrics_enabled = setting_bool("observability_stream_ffmpeg_metrics_enabled", true)

    if ai_observability.timer_base then
        ai_observability.timer_base:close()
        ai_observability.timer_base = nil
    end
    if ai_observability.timer_highres then
        ai_observability.timer_highres:close()
        ai_observability.timer_highres = nil
    end
    if ai_observability.timer_cleanup then
        ai_observability.timer_cleanup:close()
        ai_observability.timer_cleanup = nil
    end

    if collection_enabled() then
        ai_observability.timer_base = timer({
            interval = ai_observability.state.base_resolution_sec,
            callback = function()
                base_rollup_tick()
            end,
        })
        if ai_observability.state.highres_enabled == true then
            ai_observability.timer_highres = timer({
                interval = ai_observability.state.highres_resolution_sec,
                callback = function()
                    highres_rollup_tick()
                end,
            })
        end
        ai_observability.timer_cleanup = timer({
            interval = 86400,
            callback = function()
                prune_data()
            end,
        })
        prune_data()
        base_rollup_tick()
        log.info(string.format(
            "[observability] collection enabled: logs=%dd metrics=%dd base=%ds highres=%s",
            ai_observability.state.logs_retention_days,
            ai_observability.state.metrics_retention_days,
            ai_observability.state.base_resolution_sec,
            ai_observability.state.highres_enabled and "on" or "off"
        ))
    else
        log.info("[observability] collection disabled (read-only mode)")
    end
end
