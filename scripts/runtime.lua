-- Runtime graph manager

runtime = {
    streams = {},
    adapters = {},
    adapter_status = {},
    started_at = os.time(),
    perf = {},
    last_refresh_ok = true,
    last_refresh_errors = {},
    influx = {},
}

local function get_setting(key)
    if config and config.get_setting then
        return config.get_setting(key)
    end
    return nil
end

local function setting_number(key, fallback)
    local value = tonumber(get_setting(key))
    if value == nil then
        return fallback
    end
    return value
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

local function url_escape(text)
    local value = tostring(text or "")
    return value:gsub("([^%w%-_%.~])", function(ch)
        return string.format("%%%02X", string.byte(ch))
    end)
end

local function join_path(base, suffix)
    if not base or base == "" then
        return suffix or ""
    end
    if not suffix or suffix == "" then
        return base
    end
    if base:sub(-1) == "/" then
        base = base:sub(1, -2)
    end
    if suffix:sub(1, 1) ~= "/" then
        suffix = "/" .. suffix
    end
    return base .. suffix
end

local function influx_escape_tag(value)
    local text = tostring(value or "")
    text = text:gsub(",", "\\,")
    text = text:gsub("=", "\\=")
    text = text:gsub(" ", "\\ ")
    return text
end

local function influx_escape_measurement(value)
    local text = tostring(value or "")
    text = text:gsub(",", "\\,")
    text = text:gsub(" ", "\\ ")
    return text
end

local function influx_build_line(measurement, tags, fields, timestamp)
    local parts = {}
    table.insert(parts, influx_escape_measurement(measurement))
    if tags then
        local tag_parts = {}
        for key, value in pairs(tags) do
            if value ~= nil and value ~= "" then
                table.insert(tag_parts, influx_escape_tag(key) .. "=" .. influx_escape_tag(value))
            end
        end
        table.sort(tag_parts)
        if #tag_parts > 0 then
            parts[1] = parts[1] .. "," .. table.concat(tag_parts, ",")
        end
    end

    local field_parts = {}
    for key, value in pairs(fields or {}) do
        if value ~= nil then
            local vtype = type(value)
            local field = nil
            if vtype == "number" then
                if math.floor(value) == value then
                    field = key .. "=" .. tostring(value) .. "i"
                else
                    field = key .. "=" .. tostring(value)
                end
            elseif vtype == "boolean" then
                field = key .. "=" .. (value and "1i" or "0i")
            else
                field = key .. "=\"" .. tostring(value):gsub('"', '\\"') .. "\""
            end
            if field then
                table.insert(field_parts, field)
            end
        end
    end
    table.sort(field_parts)
    if #field_parts == 0 then
        return nil
    end
    table.insert(parts, table.concat(field_parts, ","))
    if timestamp then
        table.insert(parts, tostring(timestamp))
    end
    return table.concat(parts, " ")
end

local function collect_metrics_snapshot()
    local now = os.time()
    local started_at = runtime.started_at or now
    local uptime = math.max(0, now - started_at)

    local stream_counts = { total = 0, enabled = 0, disabled = 0 }
    if config and config.count_streams then
        stream_counts = config.count_streams()
    elseif config and config.list_streams then
        local rows = config.list_streams()
        stream_counts.total = #rows
        for _, row in ipairs(rows) do
            if (tonumber(row.enabled) or 0) ~= 0 then
                stream_counts.enabled = stream_counts.enabled + 1
            end
        end
        stream_counts.disabled = math.max(0, stream_counts.total - stream_counts.enabled)
    end

    local adapter_counts = { total = 0, enabled = 0, disabled = 0 }
    if config and config.count_adapters then
        adapter_counts = config.count_adapters()
    elseif config and config.list_adapters then
        local rows = config.list_adapters()
        adapter_counts.total = #rows
        for _, row in ipairs(rows) do
            if (tonumber(row.enabled) or 0) ~= 0 then
                adapter_counts.enabled = adapter_counts.enabled + 1
            end
        end
        adapter_counts.disabled = math.max(0, adapter_counts.total - adapter_counts.enabled)
    end

    local status = runtime.list_status and runtime.list_status() or {}
    local on_air = 0
    for _, entry in pairs(status) do
        if entry and entry.on_air == true then
            on_air = on_air + 1
        end
    end

    local transcode_enabled = 0
    if runtime.streams then
        for _, entry in pairs(runtime.streams) do
            if entry and entry.kind == "transcode" then
                transcode_enabled = transcode_enabled + 1
            end
        end
    end

    local adapter_with_status = 0
    if runtime.list_adapter_status then
        local adapter_status = runtime.list_adapter_status()
        for _, entry in pairs(adapter_status) do
            if entry and entry.updated_at then
                adapter_with_status = adapter_with_status + 1
            end
        end
    end

    local sessions_clients = 0
    if runtime.list_sessions then
        local sessions = runtime.list_sessions()
        sessions_clients = #sessions
    end

    local sessions_auth = 0
    if config and config.count_sessions then
        sessions_auth = config.count_sessions()
    end

    return {
        uptime_seconds = uptime,
        streams_total = stream_counts.total or 0,
        streams_enabled = stream_counts.enabled or 0,
        streams_disabled = stream_counts.disabled or 0,
        adapters_total = adapter_counts.total or 0,
        adapters_enabled = adapter_counts.enabled or 0,
        adapters_disabled = adapter_counts.disabled or 0,
        sessions_clients = sessions_clients,
        sessions_auth = sessions_auth,
        on_air = on_air,
        transcode_enabled = transcode_enabled,
        adapter_with_status = adapter_with_status,
    }
end

local function influx_send_snapshot()
    local influx = runtime.influx or {}
    local cfg = influx.config
    if not cfg or not cfg.enabled then
        return
    end
    if influx.request then
        return
    end
    local fields = collect_metrics_snapshot()
    local tags = {}
    if cfg.instance ~= "" then
        tags.instance = cfg.instance
    end
    local line = influx_build_line(cfg.measurement, tags, fields, os.time())
    if not line then
        return
    end
    local headers = {
        "User-Agent: Astra",
        "Host: " .. cfg.host .. ":" .. cfg.port,
        "Content-Type: text/plain",
        "Content-Length: " .. tostring(#line),
        "Connection: close",
    }
    if cfg.token and cfg.token ~= "" then
        table.insert(headers, "Authorization: Token " .. cfg.token)
    end
    influx.request = http_request({
        host = cfg.host,
        port = cfg.port,
        path = cfg.path,
        callback = function(self, response)
            influx.request = nil
            if not response then
                log.error("[influx] request failed")
                return
            end
            if response.code ~= 204 and response.code ~= 200 then
                log.error("[influx] http error: " .. tostring(response.code))
            end
        end,
    })
    influx.request:send({
        method = "POST",
        path = cfg.path,
        headers = headers,
        content = line,
    })
end

function runtime.configure_influx()
    local influx = runtime.influx or {}
    runtime.influx = influx
    if influx.timer then
        influx.timer:close()
        influx.timer = nil
    end
    if influx.request then
        influx.request:close()
        influx.request = nil
    end

    local enabled = setting_bool("influx_enabled", false)
    if not enabled then
        influx.config = { enabled = false }
        return
    end

    local url = setting_string("influx_url", "")
    local org = setting_string("influx_org", "")
    local bucket = setting_string("influx_bucket", "")
    if url == "" or org == "" or bucket == "" then
        log.error("[influx] missing url/org/bucket")
        influx.config = { enabled = false }
        return
    end

    local parsed = parse_url(url)
    if not parsed or (parsed.format ~= "http" and parsed.format ~= "https") then
        log.error("[influx] invalid url: " .. tostring(url))
        influx.config = { enabled = false }
        return
    end
    if parsed.format == "https" then
        log.error("[influx] https not supported")
        influx.config = { enabled = false }
        return
    end

    local base_path = parsed.path or ""
    local write_path = base_path
    if write_path == "" or write_path == "/" then
        write_path = "/api/v2/write"
    elseif not write_path:match("/api/v2/write") then
        write_path = join_path(write_path, "api/v2/write")
    end
    write_path = write_path .. "?org=" .. url_escape(org) .. "&bucket=" .. url_escape(bucket) .. "&precision=s"

    local interval = setting_number("influx_interval_sec", 30)
    if interval < 5 then interval = 5 end
    local instance = setting_string("influx_instance", "")
    if instance == "" then
        instance = os.getenv("HOSTNAME") or ""
    end
    local measurement = setting_string("influx_measurement", "astra_metrics")

    influx.config = {
        enabled = true,
        host = parsed.host,
        port = parsed.port or 80,
        path = write_path,
        token = setting_string("influx_token", ""),
        instance = instance,
        measurement = measurement,
    }

    influx.timer = timer({
        interval = interval,
        callback = function(self)
            influx_send_snapshot()
        end,
    })
    influx_send_snapshot()
end

local function clock_ms()
    return os.clock() * 1000
end

local function pick_stats(channel)
    if not channel or not channel.input then
        return nil
    end

    local active_id = channel.active_input_id or 0
    if active_id > 0 then
        local active = channel.input[active_id]
        if active and active.stats then
            return active.stats
        end
    end

    for _, input_data in ipairs(channel.input) do
        if input_data and input_data.on_air == true and input_data.stats then
            return input_data.stats
        end
    end

    for _, input_data in ipairs(channel.input) do
        if input_data and input_data.stats then
            return input_data.stats
        end
    end

    return nil
end

local function get_active_input_url(channel)
    if not channel or not channel.input then
        return nil
    end

    local active_id = channel.active_input_id or 0
    if active_id > 0 then
        local active = channel.input[active_id]
        if active and active.source_url then
            return active.source_url
        end
    end

    return nil
end

local function normalize_stats(stats)
    local src = stats or {}
    return {
        bitrate = tonumber(src.bitrate) or 0,
        cc_errors = tonumber(src.cc_errors) or 0,
        pes_errors = tonumber(src.pes_errors) or 0,
        scrambled = src.scrambled == true,
        on_air = src.on_air == true,
        updated_at = src.updated_at,
    }
end

local function collect_input_stats(channel)
    if not channel or not channel.input then
        return {}
    end

    local inputs = {}
    local active_id = channel.active_input_id

    for idx, input_data in ipairs(channel.input) do
        local entry = {
            id = idx,
            index = idx - 1,
        }

        if input_data and input_data.config then
            entry.name = input_data.config.name
            entry.format = input_data.config.format
        end
        if input_data and input_data.source_url then
            entry.url = input_data.source_url
        end

        if input_data and input_data.state then
            entry.state = input_data.state
        end

        if input_data and input_data.stats and input_data.stats.bitrate then
            entry.bitrate_kbps = tonumber(input_data.stats.bitrate)
        else
            entry.bitrate_kbps = nil
        end
        entry.last_ok_ts = input_data and input_data.last_ok_ts or nil
        entry.last_error = input_data and input_data.last_error or nil
        entry.fail_count = input_data and tonumber(input_data.fail_count) or 0

        if active_id == idx then
            entry.active = true
        end

        if input_data and input_data.stats then
            local normalized = normalize_stats(input_data.stats)
            entry.bitrate = normalized.bitrate
            entry.cc_errors = normalized.cc_errors
            entry.pes_errors = normalized.pes_errors
            entry.scrambled = normalized.scrambled
            entry.on_air = normalized.on_air
            entry.updated_at = normalized.updated_at
        else
            entry.on_air = input_data and input_data.on_air == true
        end

        if not entry.state then
            if active_id == idx then
                entry.state = entry.on_air == true and "ACTIVE" or "DOWN"
            elseif entry.on_air == true then
                entry.state = "STANDBY"
            else
                entry.state = "DOWN"
            end
        end

        table.insert(inputs, entry)
    end

    return inputs
end

local function format_output_status_url(conf)
    if not conf then
        return nil
    end
    if conf.url and conf.url ~= "" then
        return conf.url
    end
    local format = tostring(conf.format or ""):lower()
    if format == "udp" or format == "rtp" then
        local addr = conf.addr or ""
        local port = conf.port and tostring(conf.port) or ""
        if addr == "" or port == "" then
            return nil
        end
        local iface = ""
        if conf.localaddr and conf.localaddr ~= "" then
            iface = conf.localaddr .. "@"
        end
        return format .. "://" .. iface .. addr .. ":" .. port
    end
    if format == "http" or format == "https" then
        local host = conf.host or conf.addr or ""
        if host == "" then
            return nil
        end
        local port = conf.port and (":" .. tostring(conf.port)) or ""
        local path = conf.path or "/"
        return format .. "://" .. host .. port .. path
    end
    if format == "srt" or format == "rtsp" or format == "rtmp" then
        return conf.url
    end
    if format == "file" and conf.filename then
        return "file:" .. tostring(conf.filename)
    end
    return nil
end

local function collect_output_status(channel)
    if not channel or not channel.output then
        return {}
    end

    local outputs = {}
    local now = os.time()
    for idx, output_data in ipairs(channel.output) do
        local conf = output_data and output_data.config or {}
        local entry = {
            output_index = idx,
            type = conf.format,
            url = format_output_status_url(conf),
        }
        local audio_fix = output_data and output_data.audio_fix or nil
        if audio_fix then
            local cooldown = audio_fix.config and audio_fix.config.restart_cooldown_sec or 0
            local remaining = 0
            if audio_fix.last_restart_ts and cooldown > 0 then
                remaining = cooldown - (now - audio_fix.last_restart_ts)
                if remaining < 0 then
                    remaining = 0
                end
            end
            entry.audio_fix_enabled = audio_fix.config and audio_fix.config.enabled or false
            entry.audio_fix_state = audio_fix.state or (entry.audio_fix_enabled and "PROBING" or "OFF")
            entry.detected_audio_type_hex = audio_fix.detected_audio_type_hex
            entry.last_probe_ts = audio_fix.last_probe_ts
            entry.last_error = audio_fix.last_error
            entry.last_fix_start_ts = audio_fix.last_fix_start_ts
            entry.last_restart_ts = audio_fix.last_restart_ts
            entry.cooldown_remaining_sec = remaining
        end
        table.insert(outputs, entry)
    end

    return outputs
end

local function apply_stream(id, row, force)
    local existing = runtime.streams[id]
    local enabled = (tonumber(row.enabled) or 0) ~= 0

    if not enabled then
        if existing then
            if existing.kind == "transcode" and transcode then
                transcode.delete(id)
            else
                kill_channel(existing.channel)
            end
            runtime.streams[id] = nil
        end
        return true
    end

    local cfg = row.config or {}
    cfg.id = id
    if not cfg.name then
        cfg.name = "Stream " .. id
    end

    local is_transcode = transcode and transcode.is_transcode_config and transcode.is_transcode_config(cfg)
    local hash = row.config_json or ""
    if is_transcode then
        if existing and existing.kind ~= "transcode" then
            kill_channel(existing.channel)
        end
        local job = transcode.upsert(id, row, force)
        if not job then
            log.error("[runtime] failed to create transcode job: " .. id)
            runtime.streams[id] = nil
            return false, "failed to create transcode job"
        end
        runtime.streams[id] = { kind = "transcode", job = job, hash = hash }
        return true
    end

    if existing and existing.hash == hash and not force then
        return true
    end

    if type(validate_stream_config) == "function" then
        local ok, err = validate_stream_config(cfg)
        if not ok then
            log.error("[runtime] invalid stream config: " .. id .. " (" .. tostring(err or "unknown error") .. ")")
            return false, err or "invalid stream config"
        end
    end

    if existing then
        if existing.kind == "transcode" and transcode then
            transcode.delete(id)
        else
            kill_channel(existing.channel)
        end
    end

    local channel = make_channel(cfg)
    if not channel then
        log.error("[runtime] failed to create stream: " .. id)
        return false, "failed to create stream"
    end

    runtime.streams[id] = { kind = "stream", channel = channel, hash = hash }
    return true
end

local function normalize_output_list(value)
    if type(value) == "string" then
        return { value }
    end
    if type(value) == "table" then
        if value.format or value.url then
            return { value }
        end
        return value
    end
    return nil
end

local function resolve_http_output_instance_id(entry)
    local resolved = entry
    if type(entry) == "string" then
        resolved = parse_url(entry)
    elseif type(entry) == "table" and not entry.format and entry.url and type(entry.url) == "string" then
        resolved = parse_url(entry.url) or entry
    end
    if type(resolved) ~= "table" then
        return nil
    end
    if tostring(resolved.format or ""):lower() ~= "http" then
        return nil
    end
    local host = resolved.host or resolved.addr or "0.0.0.0"
    if host == "" then
        host = "0.0.0.0"
    end
    local port = tonumber(resolved.port)
    if not port then
        return nil
    end
    return host .. ":" .. port
end

local function build_http_output_keepalive(rows)
    local keepalive = {}
    for _, row in ipairs(rows) do
        if (tonumber(row.enabled) or 0) ~= 0 then
            local cfg = row.config or {}
            local is_transcode = transcode and transcode.is_transcode_config and transcode.is_transcode_config(cfg)
            if not is_transcode then
                local outputs = normalize_output_list(cfg.output)
                if type(outputs) == "table" then
                    for _, entry in ipairs(outputs) do
                        local instance_id = resolve_http_output_instance_id(entry)
                        if instance_id then
                            keepalive[instance_id] = true
                        end
                    end
                end
            end
        end
    end
    return keepalive
end

local function cleanup_http_output_instances()
    if type(http_output_instance_list) ~= "table" then
        return
    end
    for instance_id, instance in pairs(http_output_instance_list) do
        local channels = instance and instance.__options and instance.__options.channel_list or nil
        local empty = true
        if type(channels) == "table" then
            for _ in pairs(channels) do
                empty = false
                break
            end
        end
        if empty then
            if instance and instance.close then
                instance:close()
            end
            http_output_instance_list[instance_id] = nil
        end
    end
end

function runtime.apply_streams(rows, force)
    local errors = {}
    local desired = {}
    for _, row in ipairs(rows) do
        desired[row.id] = row
    end

    http_output_keepalive = build_http_output_keepalive(rows)

    for id, row in pairs(desired) do
        local ok, err = apply_stream(id, row, force)
        if ok == false then
            table.insert(errors, { id = id, error = err or "apply failed" })
        end
    end

    for id, current in pairs(runtime.streams) do
        if not desired[id] then
            kill_channel(current.channel)
            runtime.streams[id] = nil
        end
    end

    cleanup_http_output_instances()
    http_output_keepalive = nil
    return errors
end

function runtime.apply_stream_row(row, force)
    if not row or not row.id then
        return false, "stream row required"
    end
    local all_rows = config.list_streams()
    http_output_keepalive = build_http_output_keepalive(all_rows)
    local ok, err = apply_stream(row.id, row, force)
    cleanup_http_output_instances()
    http_output_keepalive = nil
    return ok, err
end

function runtime.refresh(force)
    local start_ms = clock_ms()
    local rows = config.list_streams()
    local errors = runtime.apply_streams(rows, force) or {}
    runtime.last_refresh_errors = errors
    runtime.last_refresh_ok = (#errors == 0)
    runtime.perf.last_refresh_ms = math.floor((clock_ms() - start_ms) + 0.5)
    runtime.perf.last_refresh_ts = os.time()
    return runtime.last_refresh_ok, errors
end

local function detach_adapter(id, entry)
    if not entry then
        return
    end
    if entry.instance then
        entry.instance:close()
    end
    if entry.adapter_key and dvb_input_instance_list then
        dvb_input_instance_list[entry.adapter_key] = nil
    end
    _G[id] = nil
    runtime.adapter_status[id] = nil
    runtime.adapters[id] = nil
end

local function update_adapter_status(id, stats)
    if type(stats) ~= "table" then
        return
    end
    runtime.adapter_status[id] = {
        status = tonumber(stats.status) or 0,
        signal = tonumber(stats.signal),
        snr = tonumber(stats.snr),
        ber = tonumber(stats.ber),
        unc = tonumber(stats.unc),
        updated_at = os.time(),
    }
end

local function apply_adapter(id, row, force)
    local existing = runtime.adapters[id]
    local enabled = (tonumber(row.enabled) or 0) ~= 0

    if not enabled then
        if existing then
            detach_adapter(id, existing)
        end
        return
    end

    local hash = row.config_json or ""
    if existing and existing.hash == hash and not force then
        return
    end

    if existing then
        detach_adapter(id, existing)
    end

    local cfg = row.config or {}
    cfg.id = id
    local user_callback = cfg.callback
    cfg.callback = function(stats)
        update_adapter_status(id, stats)
        if type(user_callback) == "function" then
            pcall(user_callback, stats)
        end
    end

    local instance = dvb_tune(cfg)
    if not instance then
        log.error("[runtime] failed to create adapter: " .. id)
        runtime.adapter_status[id] = {
            error = "failed to create adapter",
            updated_at = os.time(),
        }
        return
    end

    local adapter_key = nil
    if instance.__options and instance.__options.adapter ~= nil and instance.__options.device ~= nil then
        adapter_key = tostring(instance.__options.adapter) .. "." .. tostring(instance.__options.device)
    elseif cfg.adapter ~= nil then
        adapter_key = tostring(cfg.adapter) .. "." .. tostring(cfg.device or 0)
    end

    runtime.adapters[id] = { instance = instance, hash = hash, adapter_key = adapter_key }
    _G[id] = instance
end

function runtime.apply_adapters(rows, force)
    local desired = {}
    for _, row in ipairs(rows) do
        desired[row.id] = row
    end

    for id, row in pairs(desired) do
        apply_adapter(id, row, force)
    end

    for id, current in pairs(runtime.adapters) do
        if not desired[id] then
            detach_adapter(id, current)
        end
    end
end

function runtime.refresh_adapters(force)
    if not (config and config.list_adapters) then
        return
    end
    local start_ms = clock_ms()
    local rows = config.list_adapters()
    runtime.apply_adapters(rows, force)
    runtime.perf.last_adapter_refresh_ms = math.floor((clock_ms() - start_ms) + 0.5)
    runtime.perf.last_adapter_refresh_ts = os.time()
end

function runtime.list_adapter_status()
    return runtime.adapter_status or {}
end

function runtime.get_adapter_status(id)
    return runtime.adapter_status and runtime.adapter_status[id]
end

function runtime.list_status()
    local start_ms = clock_ms()
    local status = {}
    for id, stream in pairs(runtime.streams) do
        if stream.kind == "transcode" and transcode then
            local tc_status = transcode.get_status(id)
            if tc_status then
                status[id] = {
                    on_air = tc_status.state == "RUNNING",
                    transcode_state = tc_status.state,
                    transcode = tc_status,
                    updated_at = tc_status.updated_at,
                }
            end
        else
            local stats = pick_stats(stream.channel)
            local entry = normalize_stats(stats)
            entry.active_input_id = stream.channel and stream.channel.active_input_id or nil
            if entry.active_input_id and entry.active_input_id > 0 then
                entry.active_input_index = entry.active_input_id - 1
            else
                entry.active_input_index = nil
            end
            entry.active_input_url = get_active_input_url(stream.channel)
            entry.inputs = collect_input_stats(stream.channel)
            entry.last_switch = stream.channel and stream.channel.failover and stream.channel.failover.last_switch or nil
            local fo = stream.channel and stream.channel.failover or nil
            entry.backup_type = fo and fo.mode or nil
            entry.global_state = fo and fo.global_state or "RUNNING"
            entry.inputs_status = entry.inputs
            entry.outputs_status = collect_output_status(stream.channel)
            status[id] = entry
        end
    end
    runtime.perf.last_status_ms = math.floor((clock_ms() - start_ms) + 0.5)
    runtime.perf.last_status_ts = os.time()
    return status
end

function runtime.get_stream_status(id)
    local start_ms = clock_ms()
    local function record_perf()
        runtime.perf.last_status_one_ms = math.floor((clock_ms() - start_ms) + 0.5)
        runtime.perf.last_status_one_ts = os.time()
    end
    local stream = runtime.streams[id]
    if not stream then
        return nil
    end
    if stream.kind == "transcode" and transcode then
        local tc_status = transcode.get_status(id)
        if not tc_status then
            return nil
        end
        local result = {
            on_air = tc_status.state == "RUNNING",
            transcode_state = tc_status.state,
            transcode = tc_status,
            updated_at = tc_status.updated_at,
        }
        record_perf()
        return result
    end
    local stats = pick_stats(stream.channel)
    local entry = normalize_stats(stats)
    entry.active_input_id = stream.channel and stream.channel.active_input_id or nil
    if entry.active_input_id and entry.active_input_id > 0 then
        entry.active_input_index = entry.active_input_id - 1
    else
        entry.active_input_index = nil
    end
    entry.active_input_url = get_active_input_url(stream.channel)
    entry.inputs = collect_input_stats(stream.channel)
    entry.last_switch = stream.channel and stream.channel.failover and stream.channel.failover.last_switch or nil
    local fo = stream.channel and stream.channel.failover or nil
    entry.backup_type = fo and fo.mode or nil
    entry.global_state = fo and fo.global_state or "RUNNING"
    entry.inputs_status = entry.inputs
    entry.outputs_status = collect_output_status(stream.channel)
    record_perf()
    return entry
end

function runtime.list_transcode_status()
    if transcode and transcode.list_status then
        return transcode.list_status()
    end
    return {}
end

function runtime.get_transcode_status(id)
    if transcode and transcode.get_status then
        return transcode.get_status(id)
    end
    return nil
end

function runtime.restart_transcode(id)
    if transcode and transcode.jobs and transcode.restart then
        local job = transcode.jobs[id]
        if not job then
            return false
        end
        return transcode.restart(job, "api")
    end
    return false
end

function runtime.list_sessions()
    local sessions = {}
    local now = os.time()
    local hls_timeout = 60
    if config and config.get_setting then
        hls_timeout = tonumber(config.get_setting("hls_session_timeout")) or hls_timeout
    end
    if not http_output_client_list then
        http_output_client_list = {}
    end

    for id, item in pairs(http_output_client_list) do
        local req = item.request or {}
        local headers = req.headers or {}
        local user_agent = headers["user-agent"] or headers["User-Agent"] or ""
        local host = headers["host"] or headers["Host"] or ""

        table.insert(sessions, {
            id = id,
            server = host,
            stream_id = item.stream_id,
            stream_name = item.stream_name,
            ip = req.addr,
            login = (req.query and (req.query.user or req.query.login)) or "",
            started_at = item.st,
            user_agent = user_agent,
        })
    end

    if hls_session_list then
        for id, item in pairs(hls_session_list) do
            if item.last_seen and now - item.last_seen > hls_timeout then
                if access_log and type(access_log.add) == "function" then
                    local stream_name = item.stream_name or item.stream_id
                    local current = runtime.streams[item.stream_id]
                    if current and current.channel and current.channel.config and current.channel.config.name then
                        stream_name = current.channel.config.name
                    end
                    access_log.add({
                        event = "timeout",
                        protocol = "hls",
                        stream_id = item.stream_id,
                        stream_name = stream_name,
                        ip = item.ip,
                        login = item.login,
                        user_agent = item.user_agent,
                        reason = "timeout",
                    })
                end
                hls_session_list[id] = nil
                if hls_session_index and item.key then
                    hls_session_index[item.key] = nil
                end
            else
                local stream_name = item.stream_name or item.stream_id
                local current = runtime.streams[item.stream_id]
                if current and current.channel and current.channel.config and current.channel.config.name then
                    stream_name = current.channel.config.name
                end
                table.insert(sessions, {
                    id = id,
                    server = item.server,
                    stream_id = item.stream_id,
                    stream_name = stream_name,
                    ip = item.ip,
                    login = item.login or "",
                    started_at = item.started_at,
                    user_agent = item.user_agent,
                })
            end
        end
    end

    table.sort(sessions, function(a, b)
        return (a.started_at or 0) > (b.started_at or 0)
    end)

    return sessions
end

function runtime.close_session(id)
    if not http_output_client_list then
        http_output_client_list = {}
    end
    local key = tonumber(id) or id
    if type(key) == "string" and key:find("^hls%-") == 1 then
        if hls_session_list and hls_session_list[key] then
            local entry = hls_session_list[key]
            hls_session_list[key] = nil
            if hls_session_index and entry.key then
                hls_session_index[entry.key] = nil
            end
            return true
        end
        return false
    else
        local item = http_output_client_list[key]
        if not item then
            return false
        end
        if item.server and item.client then
            item.server:close(item.client)
        end
        http_output_client_list[key] = nil
        return true
    end
end
