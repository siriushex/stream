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
    stream_shard_index = nil,
    stream_shard_count = nil,
    stream_shard_source = nil, -- "cli" or "settings"
    stream_shard_pending = false, -- settings enabled, but not applied yet
    stream_shard_map = nil, -- optional: stream_id -> shard_index mapping (JSON in settings)
    stream_shard_map_raw = nil,
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

local function clamp_number(value, min_value, max_value)
    if value < min_value then
        return min_value
    end
    if value > max_value then
        return max_value
    end
    return value
end

local GC_FULL_COLLECT_INTERVAL_MS_DEFAULT = 1000
local GC_STEP_INTERVAL_MS_DEFAULT = 250
local GC_STEP_UNITS_DEFAULT = 0
local GC_FULL_COLLECT_INTERVAL_MS_MIN = 100
local GC_FULL_COLLECT_INTERVAL_MS_MAX = 60000
local GC_STEP_INTERVAL_MS_MIN = 50
local GC_STEP_INTERVAL_MS_MAX = 10000
local GC_STEP_UNITS_MIN = 0
local GC_STEP_UNITS_MAX = 10000

local function copy_table(value, seen)
    if type(value) ~= "table" then
        return value
    end
    if not seen then
        seen = {}
    elseif seen[value] then
        return seen[value]
    end
    local out = {}
    seen[value] = out
    for k, v in pairs(value) do
        out[copy_table(k, seen)] = copy_table(v, seen)
    end
    return out
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

local function load_stream_shard_map()
    if not config or type(config.get_setting) ~= "function" then
        runtime.stream_shard_map = nil
        runtime.stream_shard_map_raw = nil
        return nil
    end
    local raw = config.get_setting("stream_sharding_map")
    if raw == runtime.stream_shard_map_raw then
        return runtime.stream_shard_map
    end
    runtime.stream_shard_map_raw = raw
    runtime.stream_shard_map = nil

    if raw == nil or raw == "" then
        return nil
    end
    if not json or type(json.decode) ~= "function" then
        log.error("[runtime] stream sharding map: json.decode is unavailable")
        return nil
    end
    local ok, decoded = pcall(json.decode, raw)
    if not ok or type(decoded) ~= "table" then
        log.error("[runtime] stream sharding map: invalid json (ignored)")
        return nil
    end
    runtime.stream_shard_map = decoded
    return decoded
end

-- Deterministic shard bucket for a stream id. Used for multi-process sharding.
-- Priority:
-- 1) explicit mapping in settings (stream_sharding_map) when present
-- 2) md5(id) % shard_count (legacy deterministic mode)
local function stream_shard_bucket(id, shard_count)
    local text = tostring(id or "")
    if text == "" or not shard_count or shard_count <= 1 then
        return 0
    end
    local map = runtime.stream_shard_map
    if type(map) == "table" then
        local v = map[text]
        local idx = tonumber(v)
        if idx and idx >= 0 and idx < shard_count then
            return math.floor(idx)
        end
    end
    -- string.md5() returns binary digest (may contain \0), so convert to hex first.
    local hex = string.hex(string.md5(text))
    local head = hex and hex:sub(1, 8) or "0"
    local n = tonumber(head, 16) or 0
    return n % shard_count
end

local function reconfigure_stream_sharding_from_settings()
    if runtime.stream_shard_source == "cli" then
        runtime.stream_shard_pending = false
        return
    end
    local enabled = setting_bool("stream_sharding_enabled", false)
    local shards = math.floor(setting_number("stream_sharding_shards", 1) or 1)
    if shards < 1 then
        shards = 1
    end
    local applied_shards = math.floor(setting_number("stream_sharding_applied_shards", 0) or 0)
    local port = math.floor(setting_number("http_port", 0) or 0)
    local base_port = math.floor(setting_number("stream_sharding_base_port", 0) or 0)
    local applied_base_port = math.floor(setting_number("stream_sharding_applied_base_port", 0) or 0)
    if base_port <= 0 then
        base_port = port
    end

    local prev_i = runtime.stream_shard_index
    local prev_n = runtime.stream_shard_count
    local prev_src = runtime.stream_shard_source
    local prev_pending = runtime.stream_shard_pending

    if not enabled or shards <= 1 then
        runtime.stream_shard_index = nil
        runtime.stream_shard_count = nil
        runtime.stream_shard_source = nil
        runtime.stream_shard_pending = false
        if prev_src == "settings" and prev_n and prev_n > 1 then
            log.warning("[runtime] stream sharding disabled (settings)")
        end
        return
    end

    -- Safety: do not start filtering streams in a single-process instance until sharding
    -- is explicitly applied (which should also start/restart shard processes).
    if applied_shards < 2 then
        runtime.stream_shard_index = nil
        runtime.stream_shard_count = nil
        runtime.stream_shard_source = nil
        runtime.stream_shard_pending = true
        if not prev_pending then
            log.warning("[runtime] stream sharding enabled in settings but not applied yet; ignoring until Apply")
        end
        return
    end

    runtime.stream_shard_pending = false

    -- While settings are edited, keep using the last applied shard count/range until Apply is pressed.
    shards = applied_shards
    if applied_base_port > 0 then
        base_port = applied_base_port
    end

    local idx = port - base_port
    if idx < 0 or idx >= shards then
        idx = 0
        log.warning(string.format(
            "[runtime] stream sharding: port %d is outside base range %d..%d, falling back to shard 0/%d",
            port,
            base_port,
            base_port + shards - 1,
            shards
        ))
    end

    runtime.stream_shard_index = idx
    runtime.stream_shard_count = shards
    runtime.stream_shard_source = "settings"

    if prev_src ~= "settings" or prev_i ~= idx or prev_n ~= shards then
        log.warning(string.format(
            "[runtime] stream sharding enabled (settings): %d/%d (port=%d, base=%d)",
            idx,
            shards,
            port,
            base_port
        ))
    end
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
        "User-Agent: Stream",
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
        ssl = cfg.ssl,
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
    if parsed.format == "https" and not (astra and astra.features and astra.features.ssl) then
        log.error("[influx] https is not supported (OpenSSL not available)")
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
        port = parsed.port or (parsed.format == "https" and 443 or 80),
        ssl = (parsed.format == "https"),
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

function runtime.configure_gc()
    local full_collect_ms = setting_number("lua_gc_full_collect_interval_ms", GC_FULL_COLLECT_INTERVAL_MS_DEFAULT)
    local step_interval_ms = setting_number("lua_gc_step_interval_ms", GC_STEP_INTERVAL_MS_DEFAULT)
    local step_units = setting_number("lua_gc_step_units", GC_STEP_UNITS_DEFAULT)

    full_collect_ms = math.floor(clamp_number(full_collect_ms, GC_FULL_COLLECT_INTERVAL_MS_MIN, GC_FULL_COLLECT_INTERVAL_MS_MAX))
    step_interval_ms = math.floor(clamp_number(step_interval_ms, GC_STEP_INTERVAL_MS_MIN, GC_STEP_INTERVAL_MS_MAX))
    step_units = math.floor(clamp_number(step_units, GC_STEP_UNITS_MIN, GC_STEP_UNITS_MAX))

    -- Эти глобальные значения читает основной цикл в main.c раз в пару секунд.
    rawset(_G, "__astra_gc_full_collect_interval_ms", full_collect_ms)
    rawset(_G, "__astra_gc_step_interval_ms", step_interval_ms)
    rawset(_G, "__astra_gc_step_units", step_units)
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

local function get_stream_clients_index()
    local now = os.time()
    local cache = runtime._stream_clients_cache
    if cache and type(cache.index) == "table" and (now - (tonumber(cache.ts) or 0)) < 2 then
        return cache.index
    end

    local index = {}
    if type(http_output_client_list) == "table" then
        for _, item in pairs(http_output_client_list) do
            local stream_id = item and item.stream_id or nil
            if stream_id ~= nil and stream_id ~= "" then
                local key = tostring(stream_id)
                index[key] = (tonumber(index[key]) or 0) + 1
            end
        end
    end

    local hls_timeout = 60
    if config and config.get_setting then
        hls_timeout = tonumber(config.get_setting("hls_session_timeout")) or hls_timeout
    end
    if type(hls_session_list) == "table" then
        local stale = nil
        for sid, item in pairs(hls_session_list) do
            local last_seen = tonumber(item and item.last_seen)
            if last_seen and (now - last_seen) > hls_timeout then
                stale = stale or {}
                stale[#stale + 1] = sid
            else
                local stream_id = item and item.stream_id or nil
                if stream_id ~= nil and stream_id ~= "" then
                    local key = tostring(stream_id)
                    index[key] = (tonumber(index[key]) or 0) + 1
                end
            end
        end
        if stale then
            for _, sid in ipairs(stale) do
                local entry = hls_session_list[sid]
                hls_session_list[sid] = nil
                if hls_session_index and entry and entry.key then
                    hls_session_index[entry.key] = nil
                end
            end
        end
    end

    runtime._stream_clients_cache = {
        ts = now,
        index = index,
    }
    return index
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

    local function normalize_net_profile(value)
        if value == nil then
            return nil
        end
        local s = tostring(value or ""):lower()
        if s == "dc" or s == "wan" or s == "bad" or s == "max" or s == "superbad" then
            return s
        end
        return nil
    end

    local function get_input_resilience_setting()
        local raw = nil
        if config and config.get_setting then
            local value = config.get_setting("input_resilience")
            if type(value) == "table" then
                raw = value
            end
        end
        local enabled = false
        local default_profile = "wan"
        if type(raw) == "table" then
            enabled = raw.enabled == true
            local dp = normalize_net_profile(raw.default_profile)
            if dp then
                default_profile = dp
            end
        end
        return {
            enabled = enabled,
            default_profile = default_profile,
        }
    end

    local function resolve_input_profile_status(input_cfg, global_cfg)
        global_cfg = global_cfg or get_input_resilience_setting()
        local configured = normalize_net_profile(input_cfg and input_cfg.net_profile)
        local enabled = (global_cfg.enabled == true) or (configured ~= nil)
        local effective = configured or global_cfg.default_profile or "wan"
        if not normalize_net_profile(effective) then
            effective = "wan"
        end
        return {
            configured = configured,
            effective = effective,
            enabled = enabled,
        }
    end

    local inputs = {}
    local now = os.time()
    local active_id = channel.active_input_id
    local resilience_global = get_input_resilience_setting()

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
        if input_data and input_data.health_state then
            entry.health_state = input_data.health_state
        end
        if input_data and input_data.health_reason then
            entry.health_reason = input_data.health_reason
        end
        if input_data and input_data.net then
            entry.net = input_data.net
        end
        if input_data and input_data.hls then
            entry.hls = input_data.hls
        end
        if input_data and input_data.input and input_data.input.jitter
            and input_data.input.jitter.stats
        then
            local ok, stats = pcall(function()
                return input_data.input.jitter:stats()
            end)
            if ok and type(stats) == "table" then
                entry.jitter = stats
            end
        end

        if input_data and input_data.input and input_data.input.playout
            and input_data.input.playout.stats
        then
            local ok, stats = pcall(function()
                return input_data.input.playout:stats()
            end)
            if ok and type(stats) == "table" then
                entry.playout = stats
            end
        end

        if input_data and input_data.stats and input_data.stats.bitrate then
            entry.bitrate_kbps = tonumber(input_data.stats.bitrate)
        else
            entry.bitrate_kbps = nil
        end

        -- Профиль сети (dc/wan/bad/max) и факт включения resilience для входа.
        -- Это нужно для UI Analyze, чтобы оператор понимал, почему вход "degraded/offline".
        if input_data and input_data.config and entry.format then
            local fmt = tostring(entry.format or ""):lower()
            if fmt == "http" or fmt == "https" or fmt == "hls" then
                local prof = resolve_input_profile_status(input_data.config, resilience_global)
                entry.net_profile_configured = prof.configured
                entry.net_profile_effective = prof.effective
                entry.resilience_enabled = prof.enabled
            end
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

        if input_data and input_data.ok_since and entry.on_air == true then
            local ok_since = tonumber(input_data.ok_since)
            if ok_since then
                entry.started_at = ok_since
                entry.uptime_sec = math.max(0, now - ok_since)
            end
        end

        if input_data and input_data.health then
            entry.health = input_data.health
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
        if conf.format == "hls" and output_data and output_data.output and output_data.output.stats then
            local ok, stats = pcall(function()
                return output_data.output:stats()
            end)
            if ok and type(stats) == "table" then
                entry.hls_segments = stats.current_segments
                entry.hls_bytes = stats.current_bytes
                entry.hls_active = stats.active
            end
        end
        -- Audio Fix теперь stream-level (channel.audio_fix) и влияет на все outputs.
        local audio_fix = channel and channel.audio_fix or nil
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
            entry.audio_fix_force_on = audio_fix.config and audio_fix.config.force_on or false
            entry.audio_fix_mode = audio_fix.config and audio_fix.config.mode or nil
            entry.audio_fix_aac_bitrate_kbps = audio_fix.config and audio_fix.config.aac_bitrate_kbps or nil
            entry.audio_fix_aac_sample_rate = audio_fix.config and audio_fix.config.aac_sample_rate or nil
            entry.audio_fix_aac_channels = audio_fix.config and audio_fix.config.aac_channels or nil
            entry.audio_fix_aac_profile = audio_fix.config and audio_fix.config.aac_profile or nil
            entry.audio_fix_aresample_async = audio_fix.config and audio_fix.config.aresample_async or nil
            entry.audio_fix_silence_fallback = audio_fix.config and audio_fix.config.silence_fallback or false
            entry.audio_fix_state = audio_fix.state or (entry.audio_fix_enabled and "PROBING" or "OFF")
            entry.audio_fix_effective_mode = audio_fix.effective_mode
            entry.audio_fix_silence_active = audio_fix.silence_active == true
            entry.audio_fix_last_restart_reason = audio_fix.last_restart_reason
            entry.audio_fix_last_drift_ms = audio_fix.last_drift_ms
            entry.audio_fix_last_drift_ts = audio_fix.last_drift_ts
            entry.detected_audio_type_hex = audio_fix.detected_audio_type_hex
            entry.last_probe_ts = audio_fix.last_probe_ts
            entry.last_error = audio_fix.last_error
            entry.last_fix_start_ts = audio_fix.last_fix_start_ts
            entry.last_restart_ts = audio_fix.last_restart_ts
            entry.cooldown_remaining_sec = remaining
            entry.audio_fix_input_probe_ts = audio_fix.input_probe_ts
            entry.audio_fix_input_probe_error = audio_fix.input_probe_error
            entry.audio_fix_input_missing = audio_fix.input_audio and audio_fix.input_audio.missing == true or false
            entry.audio_fix_input_codec = audio_fix.input_audio and audio_fix.input_audio.codec_name or nil
            entry.audio_fix_input_profile = audio_fix.input_audio and audio_fix.input_audio.profile or nil
            entry.audio_fix_input_sample_rate = audio_fix.input_audio and audio_fix.input_audio.sample_rate or nil
            entry.audio_fix_input_channels = audio_fix.input_audio and audio_fix.input_audio.channels or nil
        end
        table.insert(outputs, entry)
    end

    return outputs
end

local function attach_hls_totals(entry)
    if not entry or type(entry.outputs_status) ~= "table" then
        return
    end
    local total_segments = 0
    local total_bytes = 0
    local has = false
    for _, out in ipairs(entry.outputs_status) do
        if type(out) == "table" then
            local seg = tonumber(out.hls_segments)
            local bytes = tonumber(out.hls_bytes)
            if seg then
                total_segments = total_segments + seg
                has = true
            end
            if bytes then
                total_bytes = total_bytes + bytes
                has = true
            end
        end
    end
    if has then
        entry.hls_segments = total_segments
        entry.hls_bytes = total_bytes
        entry.current_segments = total_segments
        entry.current_bytes = total_bytes
    end
end

local function build_channel_safe(cfg)
    local ok, channel_or_err = pcall(make_channel, cfg)
    if not ok then
        log.error("[runtime] make_channel failed: " .. tostring(channel_or_err))
        return nil, channel_or_err
    end
    if not channel_or_err then
        return nil, "failed to create stream"
    end
    return channel_or_err
end

local function has_file_output(cfg)
    local outputs = cfg and cfg.output
    if type(outputs) ~= "table" then
        return false
    end
    for _, entry in ipairs(outputs) do
        if type(entry) == "string" then
            local parsed = parse_url(entry)
            if parsed and tostring(parsed.format or ""):lower() == "file" then
                return true
            end
        elseif type(entry) == "table" then
            local format = entry.format
            if not format and type(entry.url) == "string" then
                local parsed = parse_url(entry.url)
                format = parsed and parsed.format or nil
            end
            if tostring(format or ""):lower() == "file" then
                return true
            end
        end
    end
    return false
end

-- ==========================
-- Passthrough Data Plane (UDP -> UDP)
-- ==========================
--
-- Цель: для "простых" passthrough потоков (UDP input -> UDP outputs) вынести горячий путь в C workers,
-- чтобы нагрузка распределялась по ядрам CPU. По умолчанию выключено.
--
-- Важно:
-- - включается настройкой `performance_passthrough_dataplane = off|auto|force`
-- - применяется только к eligible конфигам (иначе legacy make_channel())
-- - не ломаем совместимость конфигов: если поток не подходит, работаем как раньше

local PASSTHROUGH_DP_MODE_OFF = "off"
local PASSTHROUGH_DP_MODE_AUTO = "auto"
local PASSTHROUGH_DP_MODE_FORCE = "force"

local PASSTHROUGH_DP_RX_BATCH_DEFAULT = 32
local PASSTHROUGH_DP_RX_BATCH_MIN = 1
local PASSTHROUGH_DP_RX_BATCH_MAX = 64

-- Watchdog для auto-mode:
-- если dataplane видит входящие датаграммы, но не выдаёт bytes_out (и растёт bad_datagrams),
-- считаем поток несовместимым (например, RTP/не кратно 188) и откатываемся в legacy.
local PASSTHROUGH_DP_WATCHDOG_INTERVAL_SEC = 5
local PASSTHROUGH_DP_WATCHDOG_GRACE_SEC = 3
local PASSTHROUGH_DP_WATCHDOG_COOLDOWN_SEC = 300
local PASSTHROUGH_DP_WATCHDOG_MIN_DATAGRAMS = 50

local function normalize_io_list(value)
    if type(value) == "string" then
        return { value }
    end
    if type(value) == "table" then
        -- Single object entry (e.g. { url=... } or { format=... }).
        if value.format or value.url or value.source_url or value.addr then
            return { value }
        end
        return value
    end
    return nil
end

local function parse_udp_url_entry(entry)
    if entry == nil then
        return nil
    end
    local parsed = nil
    if type(entry) == "string" then
        parsed = parse_url(entry)
    elseif type(entry) == "table" then
        -- Важно: stream configs могут хранить UDP вход/выход как table с дополнительными ключами
        -- (например socket_size, ttl). Для eligibility нужно видеть ВСЕ ключи, поэтому делаем merge.
        local merged = copy_table(entry)
        if type(entry.url) == "string" then
            local u = parse_url(entry.url)
            if type(u) == "table" then
                for k, v in pairs(u) do
                    merged[k] = v
                end
            end
        end
        parsed = merged
    end
    if type(parsed) ~= "table" then
        return nil
    end
    if tostring(parsed.format or ""):lower() ~= "udp" then
        return nil
    end
    return parsed
end

local function dp_mode_normalized()
    local text = tostring(get_setting("performance_passthrough_dataplane") or PASSTHROUGH_DP_MODE_OFF):lower()
    if text == "1" or text == "true" or text == "on" or text == "enabled" then
        return PASSTHROUGH_DP_MODE_AUTO
    end
    if text ~= PASSTHROUGH_DP_MODE_AUTO and text ~= PASSTHROUGH_DP_MODE_FORCE then
        return PASSTHROUGH_DP_MODE_OFF
    end
    return text
end

local function dataplane_available()
    return type(udp_relay) == "table" and type(udp_relay.start) == "function"
end

local function has_any_key(t, keys)
    if type(t) ~= "table" then
        return false
    end
    for _, key in ipairs(keys or {}) do
        if t[key] ~= nil then
            return true
        end
    end
    return false
end

local DP_DISALLOWED_INPUT_KEYS = {
    -- SoftCAM / BISS / CAS и похожие вещи.
    "cam",
    "cam_backup",
    "cam_backup_mode",
    "cam_backup_hedge_ms",
    "cam_prefer_primary_ms",
    "cas",
    "ecm_pid",
    "shift",
    "biss",

    -- RTP encapsulation (dataplane ожидает RAW TS, без RTP header).
    "rtp",

    -- Quality detectors / анализаторы (CPU в Lua, не поддержано в dataplane).
    "cc_limit",
    "no_audio_on",
    "stop_video",
    "stop_video_timeout_sec",
    "stop_video_freeze_sec",
    "detect_av",
    "detect_av_threshold_ms",
    "detect_av_hold_sec",
    "detect_av_stable_sec",
    "detect_av_resend_interval_sec",
    "av_threshold_ms",
    "av_hold_sec",
    "av_stable_sec",
    "av_resend_interval_sec",
    "silencedetect",
    "silencedetect_duration",
    "silencedetect_interval",
    "silencedetect_noise",
    "silence_duration",
    "silence_interval",
    "silence_noise",
}

local DP_DISALLOWED_OUTPUT_KEYS = {
    -- Пейсинг/CBR/иные режимы udp_output сейчас не реализованы в dataplane.
    "sync",
    "cbr",
    "rtp",
}

local function build_udp_relay_opts_if_eligible(stream_id, cfg, cfg_hash)
    if type(cfg) ~= "table" then
        return nil, "config required"
    end

    -- Если dataplane уже пытались применить к этому stream_id и он оказался несовместимым (не TS188),
    -- временно держим blacklist, чтобы не было рестарт-петли "dataplane -> fallback -> dataplane".
    local bl = runtime.dp_blacklist and runtime.dp_blacklist[tostring(stream_id)] or nil
    if type(bl) == "table" then
        local until_ts = tonumber(bl.until_ts) or 0
        local bl_hash = tostring(bl.hash or "")
        if cfg_hash and bl_hash ~= "" and tostring(cfg_hash) == bl_hash and os.time() < until_ts then
            return nil, "dataplane blacklisted (cooldown)"
        end
    end

    -- Простейшие SPTS потоки (без MPTS и без транскода).
    if cfg.mpts == true then
        return nil, "mpts not supported"
    end
    if type(cfg.transcode) == "table" and cfg.transcode.enabled == true then
        return nil, "transcode not supported"
    end
    -- Любые TS-манипуляции/ремап/фильтры требуют legacy pipeline.
    -- Не проверяем просто "наличие ключа", потому что UI может хранить флаги как false.
    if cfg.map ~= nil or cfg.filter ~= nil or cfg["filter~"] ~= nil then
        return nil, "stream options require legacy pipeline"
    end
    if cfg.set_pnr ~= nil or cfg.set_tsid ~= nil or cfg.pid ~= nil or cfg.pnr ~= nil then
        return nil, "service selection not supported"
    end
    if (cfg.service_provider and cfg.service_provider ~= "")
        or (cfg.service_name and cfg.service_name ~= "")
        or (cfg.service_type_id ~= nil)
    then
        return nil, "service metadata not supported"
    end
    if cfg.no_sdt == true or cfg.no_eit == true
        or cfg.pass_sdt == true or cfg.pass_eit == true or cfg.pass_nit == true or cfg.pass_tdt == true
    then
        return nil, "table passthrough flags not supported"
    end

    -- Backup/failover на первом этапе не поддерживаем (экономим CPU и упрощаем гарантию порядка).
    local backup_type = tostring(cfg.backup_type or ""):lower()
    if backup_type ~= "" and backup_type ~= "disabled" and backup_type ~= "disable" and backup_type ~= "off" and backup_type ~= "none" then
        return nil, "backup not supported"
    end

    -- Audio-fix и любые внешние процессы не поддерживаем в dataplane.
    if type(cfg.audio_fix) == "table" and cfg.audio_fix.enabled == true then
        return nil, "audio_fix not supported"
    end

    local inputs = normalize_io_list(cfg.input)
    if type(inputs) ~= "table" or #inputs ~= 1 then
        return nil, "single udp input required"
    end
    local input_parsed = parse_udp_url_entry(inputs[1])
    if not input_parsed then
        return nil, "udp input required"
    end
    if has_any_key(input_parsed, DP_DISALLOWED_INPUT_KEYS) then
        return nil, "input options require legacy pipeline"
    end

    local outputs = normalize_io_list(cfg.output)
    if type(outputs) ~= "table" or #outputs == 0 then
        return nil, "at least one udp output required"
    end

    local out_list = {}
    for _, entry in ipairs(outputs) do
        local out_parsed = parse_udp_url_entry(entry)
        if not out_parsed then
            return nil, "udp outputs required"
        end
        if has_any_key(out_parsed, DP_DISALLOWED_OUTPUT_KEYS) then
            return nil, "output options require legacy pipeline"
        end
        -- pkt_size: dataplane всегда выдаёт 1316 (7 TS). Если задано другое - не трогаем, уходим в legacy.
        local pkt = out_parsed.pkt_size or out_parsed.pkt
        if pkt ~= nil then
            local n = tonumber(pkt)
            if n ~= nil and n ~= 1316 then
                return nil, "output pkt_size not supported in dataplane"
            end
        end

        table.insert(out_list, {
            addr = out_parsed.addr,
            port = tonumber(out_parsed.port),
            localaddr = out_parsed.localaddr,
            ttl = tonumber(out_parsed.ttl) or 32,
            socket_size = tonumber(out_parsed.socket_size) or 0,
        })
    end

    local workers = setting_number("performance_passthrough_workers", 0)
    if workers < 0 then
        workers = 0
    end
    local rx_batch = setting_number("performance_passthrough_rx_batch", PASSTHROUGH_DP_RX_BATCH_DEFAULT)
    rx_batch = clamp_number(rx_batch, PASSTHROUGH_DP_RX_BATCH_MIN, PASSTHROUGH_DP_RX_BATCH_MAX)
    local affinity = setting_bool("performance_passthrough_affinity", false)
    local worker_policy = setting_string("performance_passthrough_worker_policy", "hash")
    worker_policy = tostring(worker_policy or "hash"):lower()
    if worker_policy ~= "least_loaded" then
        worker_policy = "hash"
    end

    local opts = {
        id = tostring(stream_id),
        workers = workers,
        rx_batch = rx_batch,
        affinity = affinity and true or false,
        worker_policy = worker_policy,
        input = {
            addr = input_parsed.addr,
            port = tonumber(input_parsed.port),
            localaddr = input_parsed.localaddr,
            socket_size = tonumber(input_parsed.socket_size) or 0,
            source_url = tostring(input_parsed.source_url or ""),
        },
        outputs = out_list,
    }

    return opts, nil
end

local function close_existing_stream(id, existing)
    if not existing then
        return
    end
    if existing.kind == "transcode" and transcode then
        transcode.delete(id)
        return
    end
    if existing.kind == "dataplane" then
        if existing.channel then
            kill_channel(existing.channel)
            existing.channel = nil
        end
        if existing.relay and type(existing.relay.close) == "function" then
            pcall(function() existing.relay:close() end)
        end
        return
    end
    kill_channel(existing.channel)
end

local function dataplane_watchdog_tick()
    -- Watchdog актуален только для auto-mode: в force-mode пользователь явно требует dataplane.
    if dp_mode_normalized() ~= PASSTHROUGH_DP_MODE_AUTO then
        return
    end
    if not dataplane_available() then
        return
    end

    if runtime.dp_blacklist == nil then
        runtime.dp_blacklist = {}
    end

    for id, entry in pairs(runtime.streams or {}) do
        if entry and entry.kind == "dataplane" and entry.relay and type(entry.relay.stats) == "function" then
            local ok, st = pcall(function()
                return entry.relay:stats()
            end)
            if ok and type(st) == "table" then
                local uptime = tonumber(st.uptime_sec) or 0
                if uptime < PASSTHROUGH_DP_WATCHDOG_GRACE_SEC then
                    goto continue
                end

                local d_in = tonumber(st.datagrams_in) or 0
                local b_out = tonumber(st.bytes_out) or 0
                local bad = tonumber(st.bad_datagrams) or 0

                -- Если идёт вход, но нет выхода и есть bad_datagrams — это почти всегда несовместимый формат.
                if d_in >= PASSTHROUGH_DP_WATCHDOG_MIN_DATAGRAMS and b_out == 0 and bad > 0 then
                    local sid = tostring(id)
                    runtime.dp_blacklist[sid] = {
                        until_ts = os.time() + PASSTHROUGH_DP_WATCHDOG_COOLDOWN_SEC,
                        hash = tostring(entry.hash or ""),
                    }

                    log.warning("[runtime] dataplane fallback to legacy: " .. sid
                        .. " (bad_datagrams=" .. tostring(bad) .. ")")

                    local cfg = entry.config_snapshot
                    if type(cfg) ~= "table" then
                        goto continue
                    end

                    local channel, err = build_channel_safe(cfg)
                    if not channel then
                        log.error("[runtime] dataplane fallback failed to build legacy channel: " .. sid
                            .. " (" .. tostring(err or "unknown error") .. ")")
                        goto continue
                    end

                    close_existing_stream(id, entry)
                    runtime.streams[id] = { kind = "stream", channel = channel, hash = entry.hash, config_snapshot = cfg }
                end
            end
        end
        ::continue::
    end
end

local function apply_stream(id, row, force)
    local existing = runtime.streams[id]
    local enabled = (tonumber(row.enabled) or 0) ~= 0

    if not enabled then
        if existing then
            close_existing_stream(id, existing)
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
        local job, err = transcode.upsert(id, row, force)
        if not job then
            log.error("[runtime] failed to create transcode job: " .. id .. " (" .. tostring(err or "unknown error") .. ")")
            return false, err or "failed to create transcode job"
        end
        if existing and existing.kind ~= "transcode" then
            kill_channel(existing.channel)
        end
        runtime.streams[id] = { kind = "transcode", job = job, hash = hash, config_snapshot = copy_table(cfg) }
        return true
    end

    -- Важно: dataplane - это отдельный runtime-kind. Если пользователь включил/выключил его,
    -- нужно пересоздать поток даже при одинаковом config hash.
    local dp_mode = dp_mode_normalized()
    local dp_opts, dp_err = nil, nil
    local want_dp = (dp_mode ~= PASSTHROUGH_DP_MODE_OFF)
    local dp_desired_kind = "stream"
    if want_dp and dataplane_available() then
        dp_opts, dp_err = build_udp_relay_opts_if_eligible(id, cfg, hash)
        if dp_opts then
            dp_desired_kind = "dataplane"
        elseif dp_mode == PASSTHROUGH_DP_MODE_FORCE then
            log.error("[runtime] dataplane forced but stream not eligible: " .. tostring(id) .. " (" .. tostring(dp_err or "unknown") .. ")")
            return false, dp_err or "dataplane: stream not eligible"
        end
    elseif dp_mode == PASSTHROUGH_DP_MODE_FORCE then
        log.error("[runtime] dataplane forced but udp_relay module is not available")
        return false, "dataplane: udp_relay not available"
    end

    if existing and existing.hash == hash and not force and existing.kind == dp_desired_kind then
        if not existing.config_snapshot then
            existing.config_snapshot = copy_table(cfg)
        end
        return true
    end

    if type(validate_stream_config) == "function" then
        local ok, err = validate_stream_config(cfg)
        if not ok then
            log.error("[runtime] invalid stream config: " .. id .. " (" .. tostring(err or "unknown error") .. ")")
            return false, err or "invalid stream config"
        end
    end

    local file_output = has_file_output(cfg)
    if not file_output then
        if dp_desired_kind == "dataplane" and dp_opts then
            local ok, relay_or_err = pcall(function()
                return udp_relay.start(dp_opts)
            end)
            if ok and relay_or_err then
                if runtime.dp_blacklist then
                    runtime.dp_blacklist[tostring(id)] = nil
                end
                -- Для совместимости UI (/play, Analyze) оставляем "теневой" канал без outputs.
                -- Он не держит input активным без клиентов (clients=0), но позволяет preview по /play.
                local shadow = copy_table(cfg)
                shadow.output = {}
                shadow.__internal_loop = true
                shadow.__dataplane_shadow = true
                local shadow_channel, shadow_err = build_channel_safe(shadow)
                if not shadow_channel then
                    log.warning("[runtime] dataplane shadow channel init failed: " .. tostring(id) .. " ("
                        .. tostring(shadow_err or "unknown error") .. "); /play may be unavailable")
                end

                if existing then
                    close_existing_stream(id, existing)
                end
                runtime.streams[id] = {
                    kind = "dataplane",
                    relay = relay_or_err,
                    channel = shadow_channel,
                    hash = hash,
                    config_snapshot = copy_table(cfg),
                }
                return true
            end
            local err = ok and "failed to start dataplane relay" or tostring(relay_or_err)
            if dp_mode == PASSTHROUGH_DP_MODE_FORCE then
                log.error("[runtime] dataplane start failed: " .. tostring(id) .. " (" .. tostring(err) .. ")")
                return false, "dataplane start failed: " .. tostring(err)
            end
            log.warning("[runtime] dataplane start failed, falling back to legacy: " .. tostring(id) .. " (" .. tostring(err) .. ")")
        end

        local channel, err = build_channel_safe(cfg)
        if not channel then
            log.error("[runtime] failed to create stream: " .. id .. " (" .. tostring(err or "unknown error") .. ")")
            return false, err or "failed to create stream"
        end
        if existing then
            close_existing_stream(id, existing)
        end
        runtime.streams[id] = { kind = "stream", channel = channel, hash = hash, config_snapshot = copy_table(cfg) }
        return true
    end

    if existing then
        close_existing_stream(id, existing)
    end

    local channel, err = build_channel_safe(cfg)
    if not channel then
        log.error("[runtime] failed to create stream: " .. id .. " (" .. tostring(err or "unknown error") .. ")")
        if existing and existing.kind == "stream" and existing.config_snapshot then
            local rollback_channel = build_channel_safe(existing.config_snapshot)
            if rollback_channel then
                runtime.streams[id] = {
                    kind = "stream",
                    channel = rollback_channel,
                    hash = existing.hash,
                    config_snapshot = existing.config_snapshot,
                }
                return false, "apply failed; rolled back"
            end
        end
        runtime.streams[id] = nil
        return false, err or "failed to create stream"
    end

    runtime.streams[id] = { kind = "stream", channel = channel, hash = hash, config_snapshot = copy_table(cfg) }
    return true
end

-- Проверка зависимостей MPTS (stream://) для решения о пересборке.
local function collect_mpts_inputs(cfg)
    local services = cfg.mpts_services
    if type(services) ~= "table" or #services == 0 then
        services = cfg.input
    end
    local result = {}
    if type(services) ~= "table" then
        return result
    end
    for _, item in ipairs(services) do
        if type(item) == "string" then
            table.insert(result, item)
        elseif type(item) == "table" then
            if type(item.input) == "string" then
                table.insert(result, item.input)
            elseif type(item.url) == "string" then
                table.insert(result, item.url)
            end
        end
    end
    return result
end

local function extract_stream_ref(url)
    if type(url) ~= "string" then
        return nil
    end
    local ref = url:match("^stream://(.+)$")
    if not ref then
        return nil
    end
    ref = ref:match("^([^#]+)") or ref
    return ref
end

local function mpts_depends_on_changed(cfg, changed_refs)
    if type(cfg) ~= "table" or cfg.mpts ~= true then
        return false
    end
    local inputs = collect_mpts_inputs(cfg)
    for _, input in ipairs(inputs) do
        local ref = extract_stream_ref(input)
        if ref and changed_refs[ref] then
            return true
        end
    end
    return false
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
    local shard_count = tonumber(runtime.stream_shard_count or 0) or 0
    local shard_index = tonumber(runtime.stream_shard_index or 0) or 0
    if shard_count > 1 then
        load_stream_shard_map()
        local filtered = {}
        for _, row in ipairs(rows or {}) do
            if stream_shard_bucket(row.id, shard_count) == shard_index then
                table.insert(filtered, row)
            end
        end
        rows = filtered
    end
    local desired = {}
    local ordered_spts = {}
    local ordered_mpts = {}
    local changed_refs = {}
    for _, row in ipairs(rows) do
        desired[row.id] = row
        local cfg = row.config or {}
        if cfg.mpts == true then
            table.insert(ordered_mpts, row)
        else
            table.insert(ordered_spts, row)
        end
    end

    for _, row in ipairs(ordered_spts) do
        local existing = runtime.streams[row.id]
        local hash = row.config_json or ""
        local changed = force or (not existing) or (existing.hash ~= hash)
        if changed then
            changed_refs[tostring(row.id)] = true
            local name = row.config and row.config.name
            if name and name ~= "" then
                changed_refs[tostring(name)] = true
            end
        end
    end

    http_output_keepalive = build_http_output_keepalive(rows)

    for _, row in ipairs(ordered_spts) do
        local id = row.id
        local ok, err = apply_stream(id, row, force)
        if ok == false then
            table.insert(errors, { id = id, error = err or "apply failed" })
        end
    end

    for _, row in ipairs(ordered_mpts) do
        local id = row.id
        local mpts_force = force or mpts_depends_on_changed(row.config or {}, changed_refs)
        local ok, err = apply_stream(id, row, mpts_force)
        if ok == false then
            table.insert(errors, { id = id, error = err or "apply failed" })
        end
    end

    for id, current in pairs(runtime.streams) do
        if not desired[id] then
            close_existing_stream(id, current)
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
    local shard_count = tonumber(runtime.stream_shard_count or 0) or 0
    local shard_index = tonumber(runtime.stream_shard_index or 0) or 0
    if shard_count > 1 then
        load_stream_shard_map()
    end
    if shard_count > 1 and stream_shard_bucket(row.id, shard_count) ~= shard_index then
        return false, string.format("stream %s does not belong to this shard (%d/%d)", tostring(row.id), shard_index, shard_count)
    end
    local all_rows = config.list_streams()
    http_output_keepalive = build_http_output_keepalive(all_rows)
    local ok, err = apply_stream(row.id, row, force)
    local cfg = row.config or {}
    local errors = {}
    if ok and cfg.mpts ~= true then
        local changed_refs = {}
        changed_refs[tostring(row.id)] = true
        if cfg.name and cfg.name ~= "" then
            changed_refs[tostring(cfg.name)] = true
        end
        for _, other in ipairs(all_rows) do
            local ocfg = other.config or {}
            if ocfg.mpts == true and mpts_depends_on_changed(ocfg, changed_refs) then
                local ok2, err2 = apply_stream(other.id, other, true)
                if ok2 == false then
                    table.insert(errors, { id = other.id, error = err2 or "apply failed" })
                end
            end
        end
    end
    cleanup_http_output_instances()
    http_output_keepalive = nil
    if ok == false then
        return ok, err
    end
    if #errors > 0 then
        local first = errors[1]
        return false, "dependent MPTS failed: " .. tostring(first.id) .. " (" .. tostring(first.error) .. ")"
    end
    return ok, err
end

function runtime.refresh(force)
    local start_ms = clock_ms()
    if runtime.dp_watchdog_timer == nil and timer ~= nil then
        local ok, t = pcall(function()
            return timer({
                interval = PASSTHROUGH_DP_WATCHDOG_INTERVAL_SEC,
                callback = function()
                    dataplane_watchdog_tick()
                end,
            })
        end)
        if ok and t then
            runtime.dp_watchdog_timer = t
        else
            log.warning("[runtime] failed to create dataplane watchdog timer: " .. tostring(t or "unknown error"))
        end
    end
    reconfigure_stream_sharding_from_settings()
    if (tonumber(runtime.stream_shard_count or 0) or 0) > 1 then
        load_stream_shard_map()
    else
        runtime.stream_shard_map = nil
        runtime.stream_shard_map_raw = nil
    end
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
    local entry = {
        status = tonumber(stats.status) or 0,
        signal = tonumber(stats.signal),
        snr = tonumber(stats.snr),
        ber = tonumber(stats.ber),
        unc = tonumber(stats.unc),
        updated_at = os.time(),
    }
    local meta = runtime.adapters and runtime.adapters[id]
    if meta then
        entry.adapter = meta.adapter
        entry.device = meta.device
        entry.adapter_key = meta.adapter_key
    end
    runtime.adapter_status[id] = entry
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

    local adapter_num = cfg.adapter
    local device_num = cfg.device or 0
    if instance.__options and instance.__options.adapter ~= nil then
        adapter_num = instance.__options.adapter
    end
    if instance.__options and instance.__options.device ~= nil then
        device_num = instance.__options.device
    end
    runtime.adapters[id] = {
        instance = instance,
        hash = hash,
        adapter_key = adapter_key,
        adapter = adapter_num,
        device = device_num,
    }
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

local function build_stream_status_entry(id, stream, clients_count, lite)
    if stream.kind == "transcode" and transcode then
        local tc_status = nil
        if lite and transcode.get_status_lite then
            tc_status = transcode.get_status_lite(id)
        elseif transcode.get_status then
            tc_status = transcode.get_status(id)
        end
        if not tc_status then
            return nil
        end
        return {
            on_air = tc_status.state == "RUNNING",
            transcode_state = tc_status.state,
            transcode = tc_status,
            uptime_sec = tc_status.uptime_sec,
            clients_count = clients_count,
            clients = clients_count,
            updated_at = tc_status.updated_at,
        }
    end

    if stream.kind == "dataplane" then
        local relay = stream.relay
        if not relay or type(relay.stats) ~= "function" then
            return nil
        end
        local ok, st = pcall(function()
            return relay:stats()
        end)
        if not ok or type(st) ~= "table" then
            return nil
        end

        local entry = {
            on_air = st.on_air == true,
            uptime_sec = tonumber(st.uptime_sec) or nil,
            clients_count = clients_count,
            clients = clients_count,
            updated_at = os.time(),
            dataplane = st,
        }

        entry.active_input_id = 1
        entry.active_input_index = 0
        entry.active_input_url = st.input_url or nil
        entry.inputs = {
            {
                url = st.input_url or nil,
                active = true,
                uptime_sec = tonumber(st.uptime_sec) or nil,
            },
        }
        entry.inputs_status = entry.inputs

        -- Для UI достаточно приблизительного bitrate (средний с момента старта dataplane).
        local up = tonumber(st.uptime_sec) or 0
        if up > 0 then
            local in_bytes = tonumber(st.bytes_in) or 0
            local out_bytes = tonumber(st.bytes_out) or 0
            entry.in_kbps = math.floor(((in_bytes * 8) / 1000) / up + 0.5)
            entry.out_kbps = math.floor(((out_bytes * 8) / 1000) / up + 0.5)
        end

        if not lite then
            -- Dataplane сейчас поддерживает только UDP outputs, без детального per-output status.
            entry.outputs_status = nil
        end

        return entry
    end

    local channel = stream.channel
    local stats = pick_stats(channel)
    local entry = normalize_stats(stats)
    entry.active_input_id = channel and channel.active_input_id or nil
    if entry.active_input_id and entry.active_input_id > 0 then
        entry.active_input_index = entry.active_input_id - 1
    else
        entry.active_input_index = nil
    end
    entry.active_input_url = get_active_input_url(channel)
    entry.inputs = collect_input_stats(channel)
    if type(entry.inputs) == "table" then
        local active = nil
        if entry.active_input_id and entry.active_input_id > 0 then
            active = entry.inputs[entry.active_input_id]
        end
        if not active then
            for _, input in ipairs(entry.inputs) do
                if input and input.active == true then
                    active = input
                    break
                end
            end
        end
        if active and active.uptime_sec ~= nil then
            entry.uptime_sec = tonumber(active.uptime_sec) or nil
        end
    end
    entry.last_switch = channel and channel.failover and channel.failover.last_switch or nil
    local fo = channel and channel.failover or nil
    entry.backup_type = fo and fo.mode or nil
    entry.global_state = fo and fo.global_state or "RUNNING"
    entry.inputs_status = entry.inputs
    if not lite then
        entry.outputs_status = collect_output_status(channel)
        attach_hls_totals(entry)
        if channel and channel.is_mpts and channel.mpts_mux and channel.mpts_mux.stats then
            local ok, mpts_stats = pcall(function()
                return channel.mpts_mux:stats()
            end)
            if ok and type(mpts_stats) == "table" then
                entry.mpts_stats = mpts_stats
            end
        end
    end
    entry.clients_count = clients_count
    entry.clients = clients_count
    return entry
end

local function list_status_common(lite)
    local start_ms = clock_ms()
    local status = {}
    local clients_index = get_stream_clients_index()
    for id, stream in pairs(runtime.streams) do
        local clients_count = tonumber(clients_index[id]) or 0
        local entry = build_stream_status_entry(id, stream, clients_count, lite)
        if entry then
            status[id] = entry
        end
    end
    runtime.perf.last_status_ms = math.floor((clock_ms() - start_ms) + 0.5)
    runtime.perf.last_status_ts = os.time()
    if lite then
        runtime.perf.last_status_lite_ms = runtime.perf.last_status_ms
        runtime.perf.last_status_lite_ts = runtime.perf.last_status_ts
    end
    return status
end

function runtime.list_status()
    return list_status_common(false)
end

function runtime.list_status_lite()
    return list_status_common(true)
end

local function get_stream_status_common(id, lite)
    local start_ms = clock_ms()
    local function record_perf()
        runtime.perf.last_status_one_ms = math.floor((clock_ms() - start_ms) + 0.5)
        runtime.perf.last_status_one_ts = os.time()
        if lite then
            runtime.perf.last_status_one_lite_ms = runtime.perf.last_status_one_ms
            runtime.perf.last_status_one_lite_ts = runtime.perf.last_status_one_ts
        end
    end
    local stream = runtime.streams[id]
    if not stream then
        return nil
    end
    local clients_index = get_stream_clients_index()
    local clients_count = tonumber(clients_index[id]) or 0
    local entry = build_stream_status_entry(id, stream, clients_count, lite)
    if not entry then
        return nil
    end
    record_perf()
    return entry
end

function runtime.get_stream_status(id)
    return get_stream_status_common(id, false)
end

function runtime.get_stream_status_lite(id)
    return get_stream_status_common(id, true)
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

    local stale_http = nil
    for id, item in pairs(http_output_client_list) do
        local ok = true
        if not item.server or not item.client or type(item.server.data) ~= "function" then
            ok = false
        else
            local safe, data = pcall(item.server.data, item.server, item.client)
            if not safe or data == nil then
                ok = false
            end
        end
        if not ok then
            if not stale_http then
                stale_http = {}
            end
            stale_http[id] = true
        else
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
    end
    if stale_http then
        for id in pairs(stale_http) do
            http_output_client_list[id] = nil
        end
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
            runtime._stream_clients_cache = nil
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
        runtime._stream_clients_cache = nil
        return true
    end
end
