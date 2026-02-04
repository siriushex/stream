-- HTTP TS buffer manager

buffer = {
    instance = nil,
    settings = {},
}

local function get_setting(key)
    if config and config.get_setting then
        return config.get_setting(key)
    end
    return nil
end

local function setting_string(key, fallback)
    local value = get_setting(key)
    if value == nil or value == "" then
        return fallback
    end
    return tostring(value)
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
    if value == true or value == 1 then
        return true
    end
    if value == false or value == 0 then
        return false
    end
    if type(value) == "string" then
        local v = value:lower()
        if v == "1" or v == "true" or v == "yes" or v == "on" then
            return true
        end
        if v == "0" or v == "false" or v == "no" or v == "off" then
            return false
        end
    end
    return fallback
end

local function ensure_instance()
    if buffer.instance then
        return true
    end
    if type(http_buffer) ~= "table" and type(http_buffer) ~= "function" then
        log.warning("[buffer] http_buffer module is not available")
        return nil
    end
    buffer.instance = http_buffer({})
    return true
end

local function build_resources()
    local rows = config.list_buffer_resources()
    local out = {}
    for _, row in ipairs(rows) do
        local inputs = config.list_buffer_inputs(row.id)
        table.insert(out, {
            id = row.id,
            name = row.name,
            path = row.path,
            enable = row.enable ~= 0,
            backup_type = row.backup_type,
            no_data_timeout_sec = row.no_data_timeout_sec,
            backup_start_delay_sec = row.backup_start_delay_sec,
            backup_return_delay_sec = row.backup_return_delay_sec,
            backup_probe_interval_sec = row.backup_probe_interval_sec,
            active_input_index = row.active_input_index,
            buffering_sec = row.buffering_sec,
            bandwidth_kbps = row.bandwidth_kbps,
            client_start_offset_sec = row.client_start_offset_sec,
            max_client_lag_ms = row.max_client_lag_ms,
            smart_start_enabled = row.smart_start_enabled ~= 0,
            smart_target_delay_ms = row.smart_target_delay_ms,
            smart_lookback_ms = row.smart_lookback_ms,
            smart_require_pat_pmt = row.smart_require_pat_pmt ~= 0,
            smart_require_keyframe = row.smart_require_keyframe ~= 0,
            smart_require_pcr = row.smart_require_pcr ~= 0,
            smart_wait_ready_ms = row.smart_wait_ready_ms,
            smart_max_lead_ms = row.smart_max_lead_ms,
            keyframe_detect_mode = row.keyframe_detect_mode,
            av_pts_align_enabled = row.av_pts_align_enabled ~= 0,
            av_pts_max_desync_ms = row.av_pts_max_desync_ms,
            paramset_required = row.paramset_required ~= 0,
            start_debug_enabled = row.start_debug_enabled ~= 0,
            ts_resync_enabled = row.ts_resync_enabled ~= 0,
            ts_drop_corrupt_enabled = row.ts_drop_corrupt_enabled ~= 0,
            ts_rewrite_cc_enabled = row.ts_rewrite_cc_enabled ~= 0,
            pacing_mode = row.pacing_mode,
            inputs = inputs,
        })
    end
    return out
end

function buffer.refresh(opts)
    if not ensure_instance() then
        return
    end
    opts = opts or {}

    local enabled = setting_bool("buffer_enabled", false)
    local host = setting_string("buffer_listen_host", "0.0.0.0")
    local port = setting_number("buffer_listen_port", 8089)
    local source_bind = setting_string("buffer_source_bind_interface", "")
    local max_clients = setting_number("buffer_max_clients_total", 2000)
    local client_timeout = setting_number("buffer_client_read_timeout_sec", 20)
    local main_port = opts.main_port
    if main_port == nil then
        main_port = setting_number("http_port", -1)
    end
    local http_play_port = opts.http_play_port
    if http_play_port == nil then
        http_play_port = setting_number("http_play_port", main_port)
    end

    if enabled then
        if port == (main_port or -1) then
            log.error("[buffer] buffer_listen_port conflicts with http port " .. tostring(port))
            enabled = false
        elseif port == (http_play_port or -1) then
            log.error("[buffer] buffer_listen_port conflicts with http play port " .. tostring(port))
            enabled = false
        end
    end

    if source_bind == "" then
        source_bind = nil
    end

    buffer.settings = {
        enabled = enabled,
        listen_host = host,
        listen_port = port,
        source_bind_interface = source_bind,
        max_clients_total = max_clients,
        client_read_timeout_sec = client_timeout,
    }

    local resources = build_resources()
    local allow = config.list_buffer_allow()

    buffer.instance:apply_config({
        settings = buffer.settings,
        resources = resources,
        allow = allow,
    })
end

function buffer.list_status()
    if not buffer.instance or not buffer.instance.list_status then
        return {}
    end
    return buffer.instance:list_status() or {}
end

function buffer.get_status(id)
    if not buffer.instance or not buffer.instance.get_status then
        return nil
    end
    return buffer.instance:get_status(id)
end

function buffer.restart_reader(id)
    if not buffer.instance or not buffer.instance.restart_reader then
        return nil
    end
    return buffer.instance:restart_reader(id)
end
