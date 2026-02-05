-- FFmpeg transcode manager

transcode = {
    jobs = {},
    analyze_active = 0,
}

local error_patterns = {
    "corrupt",
    "error while decoding",
    "invalid data found",
    "non-monotonous dts",
    "past duration too large",
    "queue input is backward in time",
    "application provided invalid",
    "too many packets buffered",
    "max delay reached",
}

local UDP_PROBE_ANALYZE_US = 2000000
local UDP_PROBE_SIZE = 2000000
local ANALYZE_MAX_CONCURRENCY_DEFAULT = 4
local STDERR_TAIL_MAX = 200
local WARMUP_STDERR_MAX = 30
local WARMUP_TIMEOUT_EXTRA = 2

local function normalize_stream_type(cfg)
    local t = cfg and cfg.type
    if t == nil then
        return nil
    end
    return tostring(t):lower()
end

function transcode.is_transcode_config(cfg)
    local t = normalize_stream_type(cfg)
    return t == "transcode" or t == "ffmpeg"
end

local function ensure_list(value)
    if type(value) == "table" then
        return value
    end
    if type(value) == "string" and value ~= "" then
        return { value }
    end
    return {}
end

local function pick_input_entry(cfg, active_id, failover_enabled)
    local inputs = ensure_list(cfg and cfg.input)
    if #inputs == 0 then
        return nil, nil
    end
    if failover_enabled then
        local idx = tonumber(active_id) or 1
        if idx < 1 or idx > #inputs then
            idx = 1
        end
        return inputs[idx], idx
    end
    return inputs[1], 1
end

local function get_input_url(entry)
    if not entry then
        return nil
    end
    if type(entry) == "table" then
        if entry.url and entry.url ~= "" then
            return tostring(entry.url)
        end
        return nil
    end
    local text = tostring(entry)
    if text ~= "" then
        return text
    end
    return nil
end

local function get_active_input_url(cfg, active_id, failover_enabled)
    local entry = pick_input_entry(cfg, active_id, failover_enabled)
    return get_input_url(entry)
end

local function is_udp_url(url)
    if not url or url == "" then
        return false
    end
    local lower = string.lower(tostring(url))
    return lower:find("^udp://") or lower:find("^rtp://")
end

local function append_args(dst, args)
    if type(args) ~= "table" then
        return
    end
    for _, item in ipairs(args) do
        table.insert(dst, tostring(item))
    end
end

local function normalize_engine(tc)
    local engine = tostring((tc and tc.engine) or "cpu"):lower()
    if engine ~= "cpu" and engine ~= "nvidia" then
        log.warning("[transcode] unknown engine: " .. tostring(tc.engine) .. ", using cpu")
        engine = "cpu"
    end
    return engine
end

local function resolve_ffmpeg_path(tc)
    local prefer = nil
    if tc then
        prefer = tc.ffmpeg_path or tc.ffmpeg_bin
    end
    return resolve_tool_path("ffmpeg", {
        setting_key = "ffmpeg_path",
        env_key = "ASTRA_FFMPEG_PATH",
        prefer = prefer,
    })
end

local function resolve_ffprobe_path(tc)
    local prefer = nil
    if tc then
        prefer = tc.ffprobe_path
    end
    return resolve_tool_path("ffprobe", {
        setting_key = "ffprobe_path",
        env_key = "ASTRA_FFPROBE_PATH",
        prefer = prefer,
    })
end

local tool_version_cache = {}

local function shell_escape(value)
    local text = tostring(value or "")
    return "'" .. text:gsub("'", "'\\''") .. "'"
end

local function read_tool_version(path)
    if not path or path == "" then
        return nil
    end
    local cmd = shell_escape(path) .. " -version 2>/dev/null | head -n 1"
    local ok, handle = pcall(io.popen, cmd)
    if not ok or not handle then
        return nil
    end
    local line = handle:read("*l")
    handle:close()
    if line and line ~= "" then
        return line
    end
    return nil
end

local function cached_tool_version(key, path)
    if not path or path == "" then
        return nil
    end
    local entry = tool_version_cache[key]
    local now = os.time()
    if entry and entry.path == path and entry.checked_at and now - entry.checked_at < 300 then
        return entry.version
    end
    local version = read_tool_version(path)
    tool_version_cache[key] = {
        path = path,
        version = version,
        checked_at = now,
    }
    return version
end

local function normalize_backup_type(value, has_multiple)
    if value == nil or value == "" then
        if has_multiple then
            return "active"
        end
        return "disabled"
    end
    if type(value) == "string" then
        value = value:lower()
    end
    if value == "passive" or value == "active" then
        return value
    end
    if value == "active_stop_if_all_inactive" or value == "active_stop" or value == "active_stop_if_all" then
        return "active_stop_if_all_inactive"
    end
    if value == "disabled" or value == "none" or value == "off" then
        return "disabled"
    end
    if has_multiple then
        return "active"
    end
    return "disabled"
end

local function is_active_backup_mode(mode)
    return mode == "active" or mode == "active_stop_if_all_inactive"
end

local function default_initial_delay(format)
    if not format then
        return 10
    end
    local f = tostring(format):lower()
    if f == "udp" or f == "rtp" or f == "srt" then
        return 5
    end
    if f == "hls" or f == "http" or f == "https" or f == "rtsp" then
        return 10
    end
    if f == "dvb" then
        return 120
    end
    return 10
end

local function read_number_opt(cfg, ...)
    for i = 1, select("#", ...) do
        local key = select(i, ...)
        local value = tonumber(cfg[key])
        if value ~= nil then
            return value
        end
    end
    return nil
end

local function stat_exists(path)
    if not utils or type(utils.stat) ~= "function" then
        return nil
    end
    local stat = utils.stat(path)
    if not stat or stat.error then
        return false
    end
    if stat.type and stat.type ~= "" and stat.type ~= "none" then
        return true
    end
    return false
end

local function check_nvidia_support()
    if not utils or type(utils.stat) ~= "function" then
        return true, nil
    end
    local paths = {
        "/dev/nvidia0",
        "/dev/nvidiactl",
        "/proc/driver/nvidia/version",
    }
    for _, path in ipairs(paths) do
        if stat_exists(path) then
            return true, nil
        end
    end
    return false, "nvidia device not found"
end

local function parse_nvidia_smi_output(raw)
    if not raw or raw == "" then
        return nil
    end
    local metrics = {}
    for line in tostring(raw):gmatch("[^\r\n]+") do
        local idx, util, mem_used, mem_total = line:match("^%s*(%d+)%s*,%s*(%d+)%s*,%s*(%d+)%s*,%s*(%d+)%s*$")
        if idx then
            table.insert(metrics, {
                index = tonumber(idx),
                util = tonumber(util) or 0,
                mem_used = tonumber(mem_used) or 0,
                mem_total = tonumber(mem_total) or 0,
            })
        end
    end
    if #metrics == 0 then
        return nil
    end
    return metrics
end

local function query_nvidia_gpus()
    local cmd = "nvidia-smi --query-gpu=index,utilization.gpu,memory.used,memory.total " ..
        "--format=csv,noheader,nounits 2>/dev/null"
    local ok, handle = pcall(io.popen, cmd)
    if not ok or not handle then
        return nil, "nvidia-smi not available"
    end
    local output = handle:read("*a")
    handle:close()
    local metrics = parse_nvidia_smi_output(output)
    if not metrics then
        return nil, "no gpu metrics"
    end
    return metrics, nil
end

local function select_gpu_device(tc, metrics)
    if not tc then
        return nil
    end
    local raw = tc.gpu_device or tc.device_id or tc.nvidia_device
    if raw ~= nil and tostring(raw) ~= "" then
        local text = tostring(raw)
        if text == "auto" or text == "AUTO" then
            -- auto select below
        else
            local id = tonumber(text)
            if id ~= nil then
                return id
            end
        end
    end
    if tc.gpu_auto ~= true and tc.device_id ~= "auto" and tc.gpu_device ~= "auto" and tc.nvidia_device ~= "auto" then
        return nil
    end
    if not metrics then
        return nil
    end
    local best = nil
    local best_score = nil
    for _, gpu in ipairs(metrics) do
        local score = (tonumber(gpu.util) or 0) * 100000 + (tonumber(gpu.mem_used) or 0)
        if best_score == nil or score < best_score then
            best_score = score
            best = gpu
        end
    end
    return best and best.index or nil
end

local function check_gpu_overload(tc, metrics, gpu_id)
    if not tc or not metrics then
        return nil
    end
    local util_limit = tonumber(tc.gpu_util_limit or tc.nvidia_util_limit)
    local mem_limit = tonumber(tc.gpu_mem_limit_mb or tc.nvidia_mem_limit_mb)
    if (not util_limit or util_limit <= 0) and (not mem_limit or mem_limit <= 0) then
        return nil
    end
    local selected = nil
    if gpu_id ~= nil then
        for _, gpu in ipairs(metrics) do
            if gpu.index == gpu_id then
                selected = gpu
                break
            end
        end
    end
    if not selected then
        selected = metrics[1]
    end
    if not selected then
        return nil
    end
    local over = false
    local reason = {}
    if util_limit and util_limit > 0 and (selected.util or 0) >= util_limit then
        over = true
        reason.util = selected.util
        reason.util_limit = util_limit
    end
    if mem_limit and mem_limit > 0 and (selected.mem_used or 0) >= mem_limit then
        over = true
        reason.mem_used = selected.mem_used
        reason.mem_limit = mem_limit
    end
    if over then
        reason.gpu = selected.index
        return reason
    end
    return nil
end

local function build_ffmpeg_args(cfg, opts)
    local tc = cfg.transcode or {}
    local inputs = ensure_list(cfg.input)
    local selected_url = nil
    if #inputs > 1 then
        local entry = pick_input_entry(cfg, opts and opts.active_input_id or nil, true)
        if entry then
            inputs = { entry }
        end
    end
    if #inputs == 0 then
        return nil, "input is required", nil
    end

    local outputs = ensure_list(tc.outputs)
    if #outputs == 0 then
        return nil, "transcode.outputs is required"
    end

    local argv = {}
    local bin, bin_source, bin_exists, bin_bundled = resolve_ffmpeg_path(tc)
    local engine = normalize_engine(tc)
    local default_vcodec = engine == "nvidia" and "h264_nvenc" or "libx264"
    local default_acodec = "aac"
    table.insert(argv, bin)
    table.insert(argv, "-hide_banner")
    table.insert(argv, "-progress")
    table.insert(argv, "pipe:1")
    table.insert(argv, "-nostats")
    table.insert(argv, "-loglevel")
    table.insert(argv, "warning")

    append_args(argv, tc.ffmpeg_global_args)
    append_args(argv, tc.decoder_args)

    for _, input in ipairs(inputs) do
        if type(input) == "table" then
            if input.args then
                append_args(argv, input.args)
            end
            if input.url then
                table.insert(argv, "-i")
                table.insert(argv, tostring(input.url))
                if not selected_url then
                    selected_url = tostring(input.url)
                end
            end
        else
            table.insert(argv, "-i")
            table.insert(argv, tostring(input))
            if not selected_url then
                selected_url = tostring(input)
            end
        end
    end

    local common_output_args = tc.common_output_args or tc.common_input_args

    local gpu_device = opts and opts.gpu_device or nil
    for _, output in ipairs(outputs) do
        if type(output) ~= "table" or not output.url then
            return nil, "each transcode output requires url", nil
        end
        append_args(argv, common_output_args)
        if output.vf then
            table.insert(argv, "-vf")
            table.insert(argv, tostring(output.vf))
        end
        local vcodec = output.vcodec or default_vcodec
        local acodec = output.acodec or default_acodec
        if vcodec then
            if engine == "nvidia" and gpu_device ~= nil and tostring(vcodec):find("nvenc") then
                table.insert(argv, "-gpu")
                table.insert(argv, tostring(gpu_device))
            end
            table.insert(argv, "-c:v")
            table.insert(argv, tostring(vcodec))
        end
        append_args(argv, output.v_args)
        if acodec then
            table.insert(argv, "-c:a")
            table.insert(argv, tostring(acodec))
        end
        append_args(argv, output.a_args)
        append_args(argv, output.metadata)
        append_args(argv, output.format_args)
        table.insert(argv, tostring(output.url))
    end

    return argv, nil, selected_url, {
        path = bin,
        source = bin_source,
        exists = bin_exists,
        bundled = bin_bundled,
    }
end

local function normalize_bool(value, fallback)
    if value == nil then
        return fallback
    end
    if value == true or value == 1 or value == "1" then
        return true
    end
    local text = tostring(value):lower()
    if text == "true" or text == "yes" or text == "on" then
        return true
    end
    return false
end

local function normalize_monitor_engine(value)
    local engine = tostring(value or "auto"):lower()
    if engine == "ffprobe" then
        return "ffprobe"
    end
    if engine == "astra_analyze" or engine == "analyze" or engine == "astra" then
        return "astra_analyze"
    end
    return "auto"
end

local function resolve_monitor_engine(engine, url)
    local normalized = normalize_monitor_engine(engine)
    if normalized ~= "auto" then
        return normalized
    end
    if is_udp_url(url) then
        return "astra_analyze"
    end
    return "ffprobe"
end

local function normalize_watchdog_defaults(tc)
    local wd = tc.watchdog or {}
    local function num(key, fallback)
        local v = tonumber(wd[key])
        if v == nil then
            v = fallback
        end
        if v < 0 then
            v = 0
        end
        return v
    end
    return {
        restart_delay_sec = num("restart_delay_sec", 4),
        restart_jitter_sec = num("restart_jitter_sec", 2),
        restart_backoff_base_sec = num("restart_backoff_base_sec", 2),
        restart_backoff_factor = num("restart_backoff_factor", 2),
        restart_backoff_max_sec = num("restart_backoff_max_sec", 30),
        no_progress_timeout_sec = num("no_progress_timeout_sec", 8),
        max_error_lines_per_min = num("max_error_lines_per_min", 20),
        desync_threshold_ms = num("desync_threshold_ms", 500),
        desync_fail_count = num("desync_fail_count", 2),
        probe_interval_sec = num("probe_interval_sec", 3600),
        probe_duration_sec = num("probe_duration_sec", 2),
        probe_timeout_sec = num("probe_timeout_sec", 8),
        max_restarts_per_10min = num("max_restarts_per_10min", 10),
        probe_fail_count = num("probe_fail_count", 2),
        cc_error_limit = num("cc_error_limit", 0),
        pes_error_limit = num("pes_error_limit", 0),
        scrambled_limit = num("scrambled_limit", 0),
        cc_error_hold_sec = num("cc_error_hold_sec", 0),
        pes_error_hold_sec = num("pes_error_hold_sec", 0),
        scrambled_hold_sec = num("scrambled_hold_sec", 0),
        monitor_engine = normalize_monitor_engine(wd.monitor_engine),
        low_bitrate_enabled = normalize_bool(wd.low_bitrate_enabled, true),
        low_bitrate_min_kbps = num("low_bitrate_min_kbps", 400),
        low_bitrate_hold_sec = num("low_bitrate_hold_sec", 60),
        restart_cooldown_sec = num("restart_cooldown_sec", 1200),
        stop_timeout_sec = num("stop_timeout_sec", 5),
    }
end

local function normalize_output_watchdog(wd, base)
    local function pick(key)
        if type(wd) == "table" and wd[key] ~= nil then
            return wd[key]
        end
        if type(base) == "table" and base[key] ~= nil then
            return base[key]
        end
        return nil
    end
    local function num(key, fallback)
        local value = pick(key)
        local v = tonumber(value)
        if v == nil then
            v = fallback
        end
        if v < 0 then
            v = 0
        end
        return v
    end
    return {
        restart_delay_sec = num("restart_delay_sec", 4),
        restart_jitter_sec = num("restart_jitter_sec", 2),
        restart_backoff_base_sec = num("restart_backoff_base_sec", 2),
        restart_backoff_factor = num("restart_backoff_factor", 2),
        restart_backoff_max_sec = num("restart_backoff_max_sec", 30),
        no_progress_timeout_sec = num("no_progress_timeout_sec", 8),
        max_error_lines_per_min = num("max_error_lines_per_min", 20),
        desync_threshold_ms = num("desync_threshold_ms", 500),
        desync_fail_count = num("desync_fail_count", 2),
        probe_interval_sec = num("probe_interval_sec", 3600),
        probe_duration_sec = num("probe_duration_sec", 2),
        probe_timeout_sec = num("probe_timeout_sec", 8),
        max_restarts_per_10min = num("max_restarts_per_10min", 10),
        probe_fail_count = num("probe_fail_count", 2),
        cc_error_limit = num("cc_error_limit", 0),
        pes_error_limit = num("pes_error_limit", 0),
        scrambled_limit = num("scrambled_limit", 0),
        cc_error_hold_sec = num("cc_error_hold_sec", 0),
        pes_error_hold_sec = num("pes_error_hold_sec", 0),
        scrambled_hold_sec = num("scrambled_hold_sec", 0),
        monitor_engine = normalize_monitor_engine(pick("monitor_engine")),
        low_bitrate_enabled = normalize_bool(pick("low_bitrate_enabled"), true),
        low_bitrate_min_kbps = num("low_bitrate_min_kbps", 400),
        low_bitrate_hold_sec = num("low_bitrate_hold_sec", 60),
        restart_cooldown_sec = num("restart_cooldown_sec", 1200),
        stop_timeout_sec = num("stop_timeout_sec", 5),
    }
end

local function normalize_outputs(outputs, base_watchdog)
    local normalized = {}
    if type(outputs) ~= "table" then
        return normalized
    end
    for _, output in ipairs(outputs) do
        if type(output) == "table" then
            local copy = {}
            for key, value in pairs(output) do
                copy[key] = value
            end
            copy.watchdog = normalize_output_watchdog(output.watchdog, base_watchdog)
            table.insert(normalized, copy)
        end
    end
    return normalized
end

local request_stop
local schedule_restart
local build_probe_args
local parse_probe_json
local record_alert
local extract_exit_info

local function resolve_primary_format(cfg)
    local entry = pick_input_entry(cfg, 1, true)
    local url = get_input_url(entry)
    if not url or url == "" then
        return nil
    end
    local parsed = parse_url(url)
    return parsed and parsed.format or nil
end

local function normalize_failover_config(cfg, enabled)
    local inputs = ensure_list(cfg.input)
    local has_backups = #inputs > 1
    local backup_type = normalize_backup_type(cfg.backup_type, has_backups)
    local primary_format = resolve_primary_format(cfg)
    local initial_delay = read_number_opt(cfg, "backup_initial_delay_sec", "backup_initial_delay")
    if initial_delay == nil then
        initial_delay = default_initial_delay(primary_format)
    end
    local start_delay = read_number_opt(cfg, "backup_start_delay_sec", "backup_start_delay") or 5
    local return_delay = read_number_opt(cfg, "backup_return_delay_sec", "backup_return_delay") or 10
    local no_data_timeout = read_number_opt(cfg, "no_data_timeout_sec") or 3
    local probe_interval = read_number_opt(cfg, "probe_interval_sec") or 3
    local stable_ok = read_number_opt(cfg, "stable_ok_sec") or 5
    local switch_pending_timeout = read_number_opt(cfg,
        "backup_switch_pending_timeout_sec", "backup_switch_pending_timeout") or 15
    local switch_warmup = read_number_opt(cfg, "backup_switch_warmup_sec", "backup_switch_warmup") or 3
    local compat_check = normalize_bool(cfg.backup_compat_check, true)
    local compat_refresh = read_number_opt(cfg, "backup_compat_refresh_sec") or 300
    local compat_probe_sec = read_number_opt(cfg, "backup_compat_probe_sec") or 2
    local compat_probe_timeout = read_number_opt(cfg, "backup_compat_probe_timeout_sec") or 8
    local switch_warmup_min_ms = read_number_opt(cfg, "backup_switch_warmup_min_ms") or 500
    local switch_warmup_require_idr = normalize_bool(cfg.backup_switch_warmup_require_idr, false)
    local switch_warmup_probe_sec = read_number_opt(cfg, "backup_switch_warmup_probe_sec") or 2
    local switch_warmup_probe_timeout = read_number_opt(cfg, "backup_switch_warmup_probe_timeout_sec") or 6
    local stop_if_all_inactive_sec = read_number_opt(cfg,
        "stop_if_all_inactive_sec", "backup_stop_if_all_inactive_sec") or 20
    local warm_max = tonumber(cfg.backup_active_warm_max)
    if warm_max == nil then
        warm_max = config and config.get_setting and tonumber(config.get_setting("backup_active_warm_max")) or 2
    end
    if warm_max < 0 then warm_max = 0 end
    if no_data_timeout < 1 then no_data_timeout = 1 end
    if probe_interval < 0 then probe_interval = 0 end
    if stable_ok < 0 then stable_ok = 0 end
    if initial_delay < 0 then initial_delay = 0 end
    if return_delay < 0 then return_delay = 0 end
    if start_delay < 0 then start_delay = 0 end
    if switch_pending_timeout < 0 then switch_pending_timeout = 0 end
    if switch_warmup < 0 then switch_warmup = 0 end
    if compat_refresh < 0 then compat_refresh = 0 end
    if compat_probe_sec < 0 then compat_probe_sec = 0 end
    if compat_probe_timeout < 0 then compat_probe_timeout = 0 end
    if switch_warmup_min_ms < 0 then switch_warmup_min_ms = 0 end
    if switch_warmup_probe_sec < 0 then switch_warmup_probe_sec = 0 end
    if switch_warmup_probe_timeout < 0 then switch_warmup_probe_timeout = 0 end
    if stop_if_all_inactive_sec < 5 then stop_if_all_inactive_sec = 5 end

    return {
        enabled = enabled and backup_type ~= "disabled",
        has_backups = has_backups,
        mode = backup_type,
        initial_delay = initial_delay,
        start_delay = start_delay,
        return_delay = return_delay,
        switch_pending_timeout_sec = switch_pending_timeout,
        switch_warmup_sec = switch_warmup,
        switch_warmup_min_ms = switch_warmup_min_ms,
        switch_warmup_require_idr = switch_warmup_require_idr,
        switch_warmup_probe_sec = switch_warmup_probe_sec,
        switch_warmup_probe_timeout_sec = switch_warmup_probe_timeout,
        no_data_timeout = no_data_timeout,
        probe_interval = probe_interval,
        stable_ok = stable_ok,
        compat_check = compat_check,
        compat_refresh_sec = compat_refresh,
        compat_probe_sec = compat_probe_sec,
        compat_probe_timeout_sec = compat_probe_timeout,
        stop_if_all_inactive_sec = stop_if_all_inactive_sec,
        warm_max = warm_max,
        started_at = os.time(),
        paused = false,
        global_state = "RUNNING",
    }
end

local function build_failover_inputs(cfg, label)
    local inputs = ensure_list(cfg.input)
    local items = {}
    local invalid = false
    local function truthy(value)
        return value == true or value == 1 or value == "1" or value == "true" or value == "yes" or value == "on"
    end
    local function https_bridge_enabled(entry)
        if entry and (truthy(entry.https_bridge) or truthy(entry.bridge) or truthy(entry.ffmpeg)) then
            return true
        end
        if not config or not config.get_setting then
            return false
        end
        local v = config.get_setting("https_bridge_enabled")
        if v == nil then
            return false
        end
        return truthy(v)
    end
    local function https_native_supported()
        return astra and astra.features and astra.features.ssl
    end
    for idx, entry in ipairs(inputs) do
        local url = get_input_url(entry)
        if not url or url == "" then
            invalid = true
        end
        local parsed = url and parse_url(url) or nil
        if not parsed or not parsed.format or not init_input_module or not init_input_module[parsed.format] then
            invalid = true
        end
        if parsed and parsed.format == "https" and not (https_native_supported() or https_bridge_enabled(parsed)) then
            invalid = true
        end
        if parsed then
            parsed.name = tostring(label or "transcode") .. " #" .. tostring(idx)
        end
        items[idx] = {
            config = parsed,
            source_url = url,
            input = nil,
            analyze = nil,
            probing = nil,
            warm = nil,
            probe_until = nil,
        }
    end
    return items, invalid
end

local function consume_warmup_lines(warm, buffer_key, chunk, handler)
    if not chunk or chunk == "" then
        return
    end
    warm[buffer_key] = (warm[buffer_key] or "") .. chunk
    while true do
        local line, rest = warm[buffer_key]:match("^(.-)\n(.*)$")
        if not line then
            break
        end
        warm[buffer_key] = rest
        handler(line:gsub("\r$", ""))
    end
end

local function append_warmup_stderr(warm, line)
    if not line or line == "" then
        return
    end
    local tail = warm.stderr_tail
    if type(tail) ~= "table" then
        tail = {}
        warm.stderr_tail = tail
    end
    table.insert(tail, line)
    while #tail > WARMUP_STDERR_MAX do
        table.remove(tail, 1)
    end
end

local function stop_switch_warmup(job, reason)
    local fo = job and job.failover or nil
    if not fo or not fo.switch_warmup then
        return
    end
    local warm = fo.switch_warmup
    if warm.keyframe_probe and warm.keyframe_probe.proc then
        warm.keyframe_probe.proc:kill()
        warm.keyframe_probe.proc:close()
    end
    warm.keyframe_probe = nil
    if warm.proc then
        warm.proc:kill()
        warm.proc:close()
        warm.proc = nil
    end
    if warm.done == nil then
        warm.done = true
        warm.ok = false
        warm.error = reason or warm.error or "warmup stopped"
    end
end

local function warmup_enabled(fo)
    return fo and tonumber(fo.switch_warmup_sec) and tonumber(fo.switch_warmup_sec) > 0
end

local function build_switch_warmup_args(job, input_entry, warmup_sec)
    local tc = job.config and job.config.transcode or {}
    local bin = resolve_ffmpeg_path(tc)
    if not bin then
        return nil, "ffmpeg not found", nil
    end
    local url = get_input_url(input_entry)
    if not url or url == "" then
        return nil, "input url missing", nil
    end
    local argv = { bin }
    table.insert(argv, "-hide_banner")
    table.insert(argv, "-nostats")
    table.insert(argv, "-nostdin")
    table.insert(argv, "-progress")
    table.insert(argv, "pipe:1")
    table.insert(argv, "-loglevel")
    table.insert(argv, "warning")
    append_args(argv, tc.ffmpeg_global_args)
    append_args(argv, tc.decoder_args)
    if type(input_entry) == "table" and input_entry.args then
        append_args(argv, input_entry.args)
    end
    table.insert(argv, "-i")
    table.insert(argv, tostring(url))
    if warmup_sec and warmup_sec > 0 then
        table.insert(argv, "-t")
        table.insert(argv, tostring(warmup_sec))
    end
    table.insert(argv, "-map")
    table.insert(argv, "0:v:0?")
    table.insert(argv, "-map")
    table.insert(argv, "0:a:0?")
    table.insert(argv, "-f")
    table.insert(argv, "null")
    table.insert(argv, "-")
    return argv, nil, url
end

local function build_keyframe_probe_args(url, duration_sec, ffprobe_bin)
    local bin = ffprobe_bin or "ffprobe"
    local seconds = tonumber(duration_sec) or 2
    if seconds < 1 then
        seconds = 1
    end
    return {
        bin,
        "-v", "error",
        "-print_format", "json",
        "-select_streams", "v:0",
        "-show_frames",
        "-show_entries", "frame=key_frame,pict_type",
        "-read_intervals", "%+" .. tostring(seconds),
        "-i", tostring(url),
    }
end

local function parse_keyframe_probe(payload)
    if type(payload) ~= "table" then
        return false
    end
    for _, frame in ipairs(payload.frames or {}) do
        local key = frame.key_frame
        if key == 1 or key == "1" or frame.pict_type == "I" then
            return true
        end
    end
    return false
end

local function ensure_warmup_keyframe_probe(job, warm, input_entry, now)
    if not warm or warm.require_idr ~= true then
        return
    end
    if warm.idr_seen then
        return
    end
    if warm.keyframe_probe then
        return
    end
    if warm.keyframe_retry_ts and now and now < warm.keyframe_retry_ts then
        return
    end
    if not process or type(process.spawn) ~= "function" then
        warm.keyframe_error = "ffprobe unavailable"
        return
    end
    local url = get_input_url(input_entry)
    if not url or url == "" then
        warm.keyframe_error = "input url missing"
        return
    end
    local fo = job and job.failover or nil
    local probe_sec = fo and tonumber(fo.switch_warmup_probe_sec) or 2
    local probe_timeout = fo and tonumber(fo.switch_warmup_probe_timeout_sec) or 6
    if probe_sec < 1 then
        probe_sec = 1
    end
    if probe_timeout < 1 then
        probe_timeout = 1
    end
    local ffprobe_bin = resolve_ffprobe_path(job.config.transcode)
    local args = build_keyframe_probe_args(url, probe_sec, ffprobe_bin)
    local ok, proc = pcall(process.spawn, args, { stdout = "pipe", stderr = "pipe" })
    if not ok or not proc then
        warm.keyframe_error = "ffprobe spawn failed"
        return
    end
    warm.keyframe_probe = {
        proc = proc,
        stdout_buf = "",
        stderr_buf = "",
        start_ts = now or os.time(),
        deadline_ts = (now or os.time()) + probe_timeout,
    }
end

local function tick_warmup_keyframe_probe(warm, now)
    if not warm or not warm.keyframe_probe or not warm.keyframe_probe.proc then
        return
    end
    local probe = warm.keyframe_probe
    local out_chunk = probe.proc:read_stdout()
    if out_chunk then
        probe.stdout_buf = (probe.stdout_buf or "") .. out_chunk
    end
    local err_chunk = probe.proc:read_stderr()
    if err_chunk then
        probe.stderr_buf = (probe.stderr_buf or "") .. err_chunk
    end
    local status = probe.proc:poll()
    if status then
        probe.proc:close()
        warm.keyframe_probe = nil
        local payload = nil
        local ok, parsed = pcall(parse_probe_json, probe.stdout_buf or "")
        if ok then
            payload = parsed
        end
        if payload then
            warm.idr_seen = parse_keyframe_probe(payload)
            if warm.idr_seen then
                warm.keyframe_error = nil
            else
                warm.keyframe_error = "keyframe not found"
                warm.keyframe_retry_ts = (now or os.time()) + 5
            end
        else
            warm.keyframe_error = "keyframe probe failed"
            warm.keyframe_retry_ts = (now or os.time()) + 5
        end
        return
    end
    if probe.deadline_ts and now >= probe.deadline_ts then
        probe.proc:kill()
        probe.proc:close()
        warm.keyframe_probe = nil
        warm.keyframe_error = "keyframe probe timeout"
        warm.keyframe_retry_ts = now + 5
    end
end

local function ensure_switch_warmup(job, target_id, now)
    local fo = job and job.failover or nil
    if not warmup_enabled(fo) then
        return
    end
    if not process or type(process.spawn) ~= "function" then
        return
    end
    if not fo or not fo.inputs or not fo.inputs[target_id] then
        return
    end
    local warm = fo.switch_warmup
    local warmup_sec = tonumber(fo.switch_warmup_sec) or 0
    local warmup_min_ms = tonumber(fo.switch_warmup_min_ms) or 500
    local require_idr = fo.switch_warmup_require_idr == true
    if warm and warm.target == target_id then
        if not warm.done then
            return
        end
        if warm.ok then
            return
        end
        if warm.next_retry_ts and now and now < warm.next_retry_ts then
            return
        end
    elseif warm and warm.target ~= target_id then
        stop_switch_warmup(job, "warmup replaced")
    end
    local entry = pick_input_entry(job.config, target_id, true)
    local argv, err, url = build_switch_warmup_args(job, entry, warmup_sec)
    local started_at = now or os.time()
    if not argv then
        fo.switch_warmup = {
            target = target_id,
            target_url = url,
            start_ts = started_at,
            done = true,
            ok = false,
            error = err or "warmup config error",
        }
        return
    end
    local ok, proc = pcall(process.spawn, argv, { stdout = "pipe", stderr = "pipe" })
    if not ok or not proc then
        fo.switch_warmup = {
            target = target_id,
            target_url = url,
            start_ts = started_at,
            done = true,
            ok = false,
            error = "warmup spawn failed",
        }
        return
    end
    fo.switch_warmup = {
        target = target_id,
        target_url = url,
        start_ts = started_at,
        deadline_ts = started_at + warmup_sec + WARMUP_TIMEOUT_EXTRA,
        duration_sec = warmup_sec,
        min_out_time_ms = warmup_min_ms,
        require_idr = require_idr,
        proc = proc,
        stdout_buf = "",
        stderr_buf = "",
    }
    ensure_warmup_keyframe_probe(job, fo.switch_warmup, entry, started_at)
end

local function warmup_status(fo, target_id)
    if not warmup_enabled(fo) then
        return "disabled"
    end
    local warm = fo and fo.switch_warmup or nil
    if not warm or warm.target ~= target_id then
        return "idle"
    end
    if warm.ready and (not warm.require_idr or warm.idr_seen) then
        return "ok"
    end
    if warm.done then
        return warm.ok and "ok" or "failed"
    end
    return "running"
end

local function update_warmup_progress(warm, line)
    if not line or line == "" then
        return
    end
    local key, value = line:match("^([%w_]+)=(.*)$")
    if not key then
        return
    end
    if key == "out_time_ms" then
        local ms = tonumber(value)
        if ms then
            warm.last_out_time_ms = ms
            local min_ms = tonumber(warm.min_out_time_ms) or 0
            if min_ms <= 0 then
                min_ms = 1
            end
            if ms >= min_ms then
                warm.ready = true
                warm.ready_ts = warm.ready_ts or os.time()
            end
        end
    end
end

local function tick_switch_warmup(job, now)
    local fo = job and job.failover or nil
    if not warmup_enabled(fo) then
        return
    end
    local warm = fo and fo.switch_warmup or nil
    if not warm or not warm.proc then
        return
    end
    local out_chunk = warm.proc:read_stdout()
    if out_chunk then
        consume_warmup_lines(warm, "stdout_buf", out_chunk, function(_line)
            update_warmup_progress(warm, _line)
        end)
    end
    tick_warmup_keyframe_probe(warm, now)
    if warm.require_idr and not warm.idr_seen and not warm.keyframe_probe then
        local entry = pick_input_entry(job.config, warm.target, true)
        ensure_warmup_keyframe_probe(job, warm, entry, now)
    end
    local err_chunk = warm.proc:read_stderr()
    if err_chunk then
        consume_warmup_lines(warm, "stderr_buf", err_chunk, function(line)
            append_warmup_stderr(warm, line)
        end)
    end
    local status = warm.proc:poll()
    if status then
        warm.proc:close()
        warm.proc = nil
        warm.done = true
        if warm.keyframe_probe and warm.keyframe_probe.proc then
            warm.keyframe_probe.proc:kill()
            warm.keyframe_probe.proc:close()
            warm.keyframe_probe = nil
        end
        local exit_code, exit_signal = extract_exit_info(status)
        warm.exit_code = exit_code
        warm.exit_signal = exit_signal
        if exit_code == 0 or exit_code == nil then
            warm.ok = true
            if warm.require_idr and not warm.idr_seen then
                warm.ok = false
                warm.error = warm.error or warm.keyframe_error or "keyframe not found"
            end
        else
            warm.ok = false
            warm.error = warm.error or "warmup failed"
            warm.next_retry_ts = now + math.max(5, warm.duration_sec or 0)
        end
        return
    end
    if warm.deadline_ts and now >= warm.deadline_ts then
        warm.proc:kill()
        warm.proc:close()
        warm.proc = nil
        warm.done = true
        warm.ok = false
        warm.error = "warmup timeout"
        if warm.keyframe_probe and warm.keyframe_probe.proc then
            warm.keyframe_probe.proc:kill()
            warm.keyframe_probe.proc:close()
            warm.keyframe_probe = nil
        end
        warm.next_retry_ts = now + math.max(5, warm.duration_sec or 0)
    end
end

local function extract_stream_profile(payload)
    if type(payload) ~= "table" then
        return nil
    end
    local profile = {
        video_count = 0,
        audio_count = 0,
        video_codec = nil,
        audio_codec = nil,
        audio_sample_rate = nil,
    }
    for _, stream in ipairs(payload.streams or {}) do
        if stream.codec_type == "video" then
            profile.video_count = profile.video_count + 1
            if not profile.video_codec and stream.codec_name then
                profile.video_codec = tostring(stream.codec_name)
            end
        elseif stream.codec_type == "audio" then
            profile.audio_count = profile.audio_count + 1
            if not profile.audio_codec and stream.codec_name then
                profile.audio_codec = tostring(stream.codec_name)
            end
            if not profile.audio_sample_rate and stream.sample_rate then
                profile.audio_sample_rate = tonumber(stream.sample_rate)
            end
        end
    end
    profile.has_video = profile.video_count > 0
    profile.has_audio = profile.audio_count > 0
    return profile
end

local function compare_profiles(base, candidate)
    if not base or not candidate then
        return true, nil
    end
    if base.has_video ~= candidate.has_video then
        return false, "video_presence_mismatch"
    end
    if base.has_audio ~= candidate.has_audio then
        return false, "audio_presence_mismatch"
    end
    if base.audio_count ~= candidate.audio_count then
        return false, "audio_track_count_mismatch"
    end
    if base.video_codec and candidate.video_codec and base.video_codec ~= candidate.video_codec then
        return false, "video_codec_mismatch"
    end
    if base.audio_codec and candidate.audio_codec and base.audio_codec ~= candidate.audio_codec then
        return false, "audio_codec_mismatch"
    end
    if base.audio_sample_rate and candidate.audio_sample_rate and
        base.audio_sample_rate ~= candidate.audio_sample_rate then
        return false, "audio_sample_rate_mismatch"
    end
    return true, nil
end

local function ensure_failover_compat_probe(job, input_id, now)
    local fo = job and job.failover or nil
    if not fo or fo.compat_check ~= true then
        return
    end
    if not process or type(process.spawn) ~= "function" then
        return
    end
    local input_data = fo.inputs and fo.inputs[input_id] or nil
    if not input_data or not input_data.source_url then
        return
    end
    if input_data.compat_probe then
        return
    end
    local refresh = tonumber(fo.compat_refresh_sec) or 0
    if input_data.compat and input_data.compat.checked_at and refresh > 0 then
        if now - input_data.compat.checked_at < refresh then
            return
        end
    end
    local ffprobe_bin = resolve_ffprobe_path(job.config.transcode)
    local args = build_probe_args(input_data.source_url, fo.compat_probe_sec, false, nil, ffprobe_bin)
    local ok, proc = pcall(process.spawn, args, { stdout = "pipe", stderr = "pipe" })
    if not ok or not proc then
        input_data.compat = {
            checked_at = now,
            ok = true,
            error = "ffprobe spawn failed",
        }
        input_data.incompatible = false
        return
    end
    input_data.compat_probe = {
        proc = proc,
        stdout_buf = "",
        stderr_buf = "",
        start_ts = now,
        deadline_ts = now + (tonumber(fo.compat_probe_timeout_sec) or 8),
    }
end

local function tick_failover_compat_probes(job, now)
    local fo = job and job.failover or nil
    if not fo or fo.compat_check ~= true or not fo.inputs then
        return
    end
    for idx, input_data in ipairs(fo.inputs) do
        local probe = input_data.compat_probe
        if probe and probe.proc then
            local out_chunk = probe.proc:read_stdout()
            if out_chunk then
                probe.stdout_buf = (probe.stdout_buf or "") .. out_chunk
            end
            local err_chunk = probe.proc:read_stderr()
            if err_chunk then
                probe.stderr_buf = (probe.stderr_buf or "") .. err_chunk
            end
            local status = probe.proc:poll()
            if status then
                probe.proc:close()
                input_data.compat_probe = nil
                local payload, err = parse_probe_json(probe.stdout_buf or "")
                local profile = payload and extract_stream_profile(payload) or nil
                if profile then
                    if idx == 1 then
                        fo.base_profile = profile
                    end
                    if job.active_input_id == idx then
                        job.active_input_profile = profile
                    end
                    local base = fo.base_profile or job.active_input_profile
                    local ok, reason = compare_profiles(base, profile)
                    input_data.compat = {
                        checked_at = now,
                        ok = ok,
                        reason = reason,
                        profile = profile,
                    }
                    if ok == false then
                        input_data.incompatible = true
                        record_alert(job, "FAILOVER_INCOMPATIBLE_INPUT", "backup input incompatible", {
                            input_index = idx - 1,
                            input_url = input_data.source_url,
                            reason = reason,
                        })
                    else
                        input_data.incompatible = false
                    end
                else
                    input_data.compat = {
                        checked_at = now,
                        ok = true,
                        error = err or "compat probe failed",
                    }
                    input_data.incompatible = false
                end
            elseif probe.deadline_ts and now >= probe.deadline_ts then
                probe.proc:kill()
                probe.proc:close()
                input_data.compat_probe = nil
                input_data.compat = {
                    checked_at = now,
                    ok = true,
                    error = "compat probe timeout",
                }
                input_data.incompatible = false
            end
        end
    end
end

local function prepare_failover_input(job, input_id, opts)
    opts = opts or {}
    local fo = job.failover
    if not fo or not fo.inputs then
        return false
    end
    local input_data = fo.inputs[input_id]
    if not input_data or not input_data.config then
        return false
    end
    if input_data.input then
        return true
    end

    local input = init_input(input_data.config)
    if not input or not input.tail then
        input_data.input = nil
        input_data.last_error = "init_failed"
        input_data.fail_count = (input_data.fail_count or 0) + 1
        if not input_data.fail_since then
            input_data.fail_since = os.time()
        end
        return false
    end

    input_data.input = input
    input_data.last_error = nil

    if input_data.config.no_analyze ~= true then
        if not fo.channel then
            fo.channel = { input = fo.inputs }
        end
        input_data.analyze = analyze({
            upstream = input_data.input.tail:stream(),
            name = input_data.config.name,
            cc_limit = input_data.config.cc_limit,
            bitrate_limit = input_data.config.bitrate_limit,
            callback = function(data)
                on_analyze_spts(fo.channel, input_id, data)
            end,
        })
    else
        local now = os.time()
        input_data.analyze = nil
        input_data.on_air = true
        input_data.last_seen_ts = now
        input_data.last_ok_ts = now
        input_data.ok_since = input_data.ok_since or now
        input_data.fail_since = nil
        input_data.fail_count = 0
        input_data.last_error = nil
    end

    if opts.probing then
        input_data.probing = true
    end
    if opts.warm then
        input_data.warm = true
    end

    return true
end

local function kill_failover_input(job, input_id)
    local fo = job.failover
    if not fo or not fo.inputs then
        return
    end
    local input_data = fo.inputs[input_id]
    if not input_data then
        return
    end
    input_data.analyze = nil
    input_data.stats = nil
    input_data.on_air = nil
    input_data.is_ok = nil
    input_data.ok_since = nil
    input_data.fail_since = nil
    input_data.last_seen_ts = nil
    input_data.probing = nil
    input_data.warm = nil
    input_data.probe_until = nil
    if input_data.compat_probe and input_data.compat_probe.proc then
        input_data.compat_probe.proc:kill()
        input_data.compat_probe.proc:close()
    end
    input_data.compat_probe = nil
    input_data.compat = nil
    input_data.incompatible = nil
    if input_data.input then
        kill_input(input_data.input)
        input_data.input = nil
    end
end

local function update_failover_input_health(input_data, now, no_data_timeout)
    if not input_data then
        return false
    end

    local ok = false
    if input_data.input then
        if input_data.analyze then
            ok = input_data.on_air == true
            if input_data.last_seen_ts and (now - input_data.last_seen_ts) > no_data_timeout then
                ok = false
            end
        else
            ok = true
            input_data.last_seen_ts = now
        end
    end

    if ok then
        input_data.is_ok = true
        input_data.ok_since = input_data.ok_since or now
        input_data.fail_since = nil
        input_data.last_ok_ts = now
    else
        input_data.is_ok = false
        input_data.ok_since = nil
        if not input_data.fail_since then
            input_data.fail_since = now
        end
    end

    return ok
end

local function update_failover_input_state(job, input_id, input_data)
    local fo = job.failover
    local state = "DOWN"
    if input_id == job.active_input_id then
        state = input_data.is_ok and "ACTIVE" or "DOWN"
    elseif input_data.input then
        if input_data.probing then
            state = "PROBING"
        elseif input_data.warm then
            state = input_data.is_ok and "STANDBY" or "PROBING"
        else
            if input_data.is_ok then
                state = (fo and is_active_backup_mode(fo.mode)) and "STANDBY" or "PROBING"
            else
                state = "DOWN"
            end
        end
    else
        state = "DOWN"
    end
    input_data.state = state
end

local function pick_next_input(inputs, active_id, prefer_ok, prefer_compat)
    local total = #inputs
    if total == 0 then
        return nil
    end
    for offset = 1, total do
        local idx = ((active_id - 1 + offset) % total) + 1
        local input_data = inputs[idx]
        if input_data then
            if prefer_compat and input_data.incompatible == true then
                -- skip incompatible input
            elseif not prefer_ok or input_data.is_ok then
                return idx
            end
        end
    end
    return nil
end

local function schedule_failover_probe(job, now, keep_connected)
    local fo = job.failover
    if not fo or not is_active_backup_mode(fo.mode) then
        return
    end
    if fo.probe_interval <= 0 then
        return
    end
    if fo.next_probe_ts and now < fo.next_probe_ts then
        return
    end

    for _, input_data in ipairs(fo.inputs) do
        if input_data.probing and input_data.input then
            return
        end
    end

    local candidates = {}
    for idx, input_data in ipairs(fo.inputs) do
        if not keep_connected[idx] and not input_data.input then
            table.insert(candidates, idx)
        end
    end
    if #candidates == 0 then
        fo.next_probe_ts = now + fo.probe_interval
        return
    end

    local cursor = fo.probe_cursor or 1
    if cursor > #candidates then
        cursor = 1
    end
    local probe_id = candidates[cursor]
    fo.probe_cursor = cursor + 1

    if prepare_failover_input(job, probe_id, { probing = true }) then
        local input_data = fo.inputs[probe_id]
        input_data.probing = true
        input_data.probe_until = now + math.max(fo.no_data_timeout, fo.stable_ok)
        keep_connected[probe_id] = true
    end

    fo.next_probe_ts = now + fo.probe_interval
end

local function update_failover_connections(job, now)
    local fo = job.failover
    if not fo then
        return
    end

    local keep_connected = {}
    local active_id = job.active_input_id or 0
    if active_id > 0 then
        keep_connected[active_id] = true
    end

    if is_active_backup_mode(fo.mode) and fo.warm_max > 0 and fo.global_state ~= "INACTIVE" then
        local count = 0
        for idx, _ in ipairs(fo.inputs) do
            if idx ~= active_id then
                keep_connected[idx] = true
                count = count + 1
                if count >= fo.warm_max then
                    break
                end
            end
        end
    end

    for idx, input_data in ipairs(fo.inputs) do
        if input_data.probing and input_data.probe_until and input_data.probe_until > now then
            keep_connected[idx] = true
        elseif input_data.probing and input_data.probe_until and input_data.probe_until <= now then
            input_data.probing = nil
            input_data.probe_until = nil
        end
    end

    schedule_failover_probe(job, now, keep_connected)

    for idx, input_data in ipairs(fo.inputs) do
        if keep_connected[idx] then
            local ok = prepare_failover_input(job, idx, {
                warm = is_active_backup_mode(fo.mode) and idx ~= active_id,
            })
            if ok then
                ensure_failover_compat_probe(job, idx, now)
                input_data.warm = (is_active_backup_mode(fo.mode) and idx ~= active_id)
            else
                input_data.warm = nil
            end
        else
            if input_data.input then
                kill_failover_input(job, idx)
            end
            input_data.warm = nil
            input_data.probing = nil
            input_data.probe_until = nil
        end
    end
end

local function schedule_failover_restart(job, reason, meta)
    if not job or job.state == "ERROR" then
        return false
    end
    if job.proc then
        schedule_restart(job, nil, "INPUT_NO_DATA", reason or "input failover", meta)
        return true
    end
    if job.state == "STARTING" or job.state == "RESTARTING" then
        return true
    end
    if job.enabled then
        transcode.start(job)
        return true
    end
    return false
end

local function activate_failover_input(job, input_id, reason)
    if not input_id or input_id <= 0 then
        return false
    end
    local prev_id = job.active_input_id or 0
    if prev_id ~= input_id then
        job.active_input_id = input_id
        local from_index = prev_id > 0 and (prev_id - 1) or -1
        local to_index = input_id - 1
        log.info("[transcode " .. tostring(job.id) .. "] switch input " ..
            tostring(from_index) .. " -> " .. tostring(to_index) .. ", reason=" .. tostring(reason))
        if job.failover then
            job.failover.last_switch = {
                from = from_index,
                to = to_index,
                reason = reason,
                ts = os.time(),
            }
        end
    end
    stop_switch_warmup(job, "switch complete")
    local input_data = job.failover and job.failover.inputs and job.failover.inputs[input_id] or nil
    local meta = {
        input_index = input_id - 1,
        input_url = input_data and input_data.source_url or nil,
        reason = reason,
    }
    return schedule_failover_restart(job, reason, meta)
end

local function activate_next_available_input(job, active_id, reason)
    local fo = job.failover
    if not fo then
        return false
    end
    local total = #fo.inputs
    if total == 0 then
        return false
    end
    local skip_incompatible = fo.compat_check == true
    for pass = 1, 2 do
        local prefer_ok = pass == 1
        for offset = 1, total do
            local idx = ((active_id - 1 + offset) % total) + 1
            local input_data = fo.inputs[idx]
            if input_data then
                if skip_incompatible and input_data.incompatible == true then
                    -- skip incompatible input
                elseif not prefer_ok or input_data.is_ok then
                    if activate_failover_input(job, idx, reason) then
                        return true
                    end
                end
            end
        end
    end
    return false
end

local function transcode_failover_tick(job, now)
    local fo = job.failover
    if not fo or fo.paused or not job.enabled or not fo.inputs or job.state == "ERROR" then
        return
    end

    local total = #fo.inputs
    if total == 0 then
        return
    end

    for _, input_data in ipairs(fo.inputs) do
        update_failover_input_health(input_data, now, fo.no_data_timeout)
    end

    if not fo.enabled then
        for idx, input_data in ipairs(fo.inputs) do
            update_failover_input_state(job, idx, input_data)
        end
        return
    end

    local active_mode = is_active_backup_mode(fo.mode)
    local stop_on_inactive = fo.mode == "active_stop_if_all_inactive"
    local any_ok = false
    for _, input_data in ipairs(fo.inputs) do
        if input_data.is_ok then
            any_ok = true
            break
        end
    end

    if stop_on_inactive then
        if not any_ok then
            fo.inactive_since = fo.inactive_since or now
            if (now - fo.inactive_since) >= fo.stop_if_all_inactive_sec then
                if fo.global_state ~= "INACTIVE" then
                    fo.global_state = "INACTIVE"
                    fo.return_pending = nil
                    for idx, input_data in ipairs(fo.inputs) do
                        if input_data.input then
                            kill_failover_input(job, idx)
                        end
                        input_data.warm = nil
                        input_data.probing = nil
                        input_data.probe_until = nil
                    end
                    job.active_input_id = 0
                    if job.proc then
                        request_stop(job)
                    end
                    job.state = "INACTIVE"
                    job.restart_due_ts = nil
                end
            end
        else
            fo.inactive_since = nil
            if fo.global_state == "INACTIVE" then
                fo.global_state = "RUNNING"
            end
        end
    else
        fo.inactive_since = nil
        fo.global_state = "RUNNING"
    end

    if fo.global_state == "INACTIVE" then
        update_failover_connections(job, now)
        for idx, input_data in ipairs(fo.inputs) do
            update_failover_input_state(job, idx, input_data)
        end
        return
    end

    local active_id = job.active_input_id or 0
    local initial_ready = now >= (fo.started_at + fo.initial_delay)

    if active_id == 0 then
        activate_next_available_input(job, 0, "start")
        active_id = job.active_input_id or 0
    end

    if active_id > 0 then
        local active_input = fo.inputs[active_id]
        local active_ok = active_input and active_input.is_ok
        local down_for = 0
        if active_input and active_input.fail_since then
            down_for = now - active_input.fail_since
        end

        local allow_switch = initial_ready or active_id ~= 1
        if not active_ok and allow_switch then
            local delay = fo.start_delay
            if down_for >= delay then
                local prefer_compat = fo.compat_check == true
                local next_id = pick_next_input(fo.inputs, active_id, true, prefer_compat)
                if not next_id then
                    next_id = pick_next_input(fo.inputs, active_id, false, prefer_compat)
                end
                if next_id then
                    if warmup_enabled(fo) then
                        ensure_switch_warmup(job, next_id, now)
                        local warm_state = warmup_status(fo, next_id)
                        if warm_state == "ok" or warm_state == "failed" or warm_state == "disabled" then
                            activate_failover_input(job, next_id, "no_data_timeout")
                            fo.switch_pending = nil
                        else
                            if not fo.switch_pending or fo.switch_pending.target ~= next_id then
                                local target = fo.inputs[next_id]
                                fo.switch_pending = {
                                    target = next_id,
                                    ready_at = now,
                                    created_at = now,
                                    reason = "no_data_timeout",
                                    target_url = target and target.source_url or nil,
                                }
                            end
                        end
                    else
                        activate_failover_input(job, next_id, "no_data_timeout")
                        fo.switch_pending = nil
                    end
                end
            end
        end
        if active_ok then
            fo.switch_pending = nil
        end
    end

    if active_id > 1 and active_mode then
        local primary = fo.inputs[1]
        if primary and primary.is_ok and primary.ok_since and
            (now - primary.ok_since) >= fo.stable_ok then
            if not fo.return_pending then
                fo.return_pending = {
                    target = 1,
                    ready_at = now + fo.return_delay,
                    reason = "return_primary",
                    target_url = primary and primary.source_url or nil,
                }
            end
        else
            fo.return_pending = nil
        end

        if fo.return_pending then
            ensure_switch_warmup(job, fo.return_pending.target, now)
        end
        if fo.return_pending and now >= fo.return_pending.ready_at then
            local warm_state = warmup_status(fo, fo.return_pending.target)
            if warm_state == "ok" or warm_state == "disabled" then
                activate_failover_input(job, fo.return_pending.target, fo.return_pending.reason)
                fo.return_pending = nil
            elseif warm_state == "failed" then
                fo.return_pending = nil
            end
        end
    else
        fo.return_pending = nil
    end

    if fo.switch_pending then
        local pending = fo.switch_pending
        local pending_timeout = tonumber(fo.switch_pending_timeout_sec) or 0
        if pending_timeout > 0 and pending.created_at and (now - pending.created_at) >= pending_timeout then
            fo.switch_pending = nil
        else
            ensure_switch_warmup(job, pending.target, now)
            local warm_state = warmup_status(fo, pending.target)
            if warm_state == "ok" or warm_state == "failed" or warm_state == "disabled" then
                activate_failover_input(job, pending.target, pending.reason or "switch_pending")
                fo.switch_pending = nil
            end
        end
    end

    if fo.switch_warmup and fo.switch_warmup.proc and not fo.switch_pending and not fo.return_pending then
        stop_switch_warmup(job, "warmup no longer needed")
    end

    update_failover_connections(job, now)

    for idx, input_data in ipairs(fo.inputs) do
        update_failover_input_state(job, idx, input_data)
    end
end

local function normalize_input_stats(stats)
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

local function collect_failover_input_stats(job)
    local fo = job.failover
    if not fo or not fo.inputs then
        return {}
    end

    local inputs = {}
    local active_id = job.active_input_id

    for idx, input_data in ipairs(fo.inputs) do
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
        entry.incompatible = input_data and input_data.incompatible == true or false
        if input_data and input_data.compat then
            entry.compat = input_data.compat
            entry.compat_checked_at = input_data.compat.checked_at
            entry.compat_ok = input_data.compat.ok
            entry.compat_reason = input_data.compat.reason
            entry.compat_error = input_data.compat.error
        end

        if active_id == idx then
            entry.active = true
        end

        if input_data and input_data.stats then
            local normalized = normalize_input_stats(input_data.stats)
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

local function prune_time_list(list, cutoff)
    local idx = 1
    while idx <= #list do
        if list[idx] < cutoff then
            table.remove(list, idx)
        else
            idx = idx + 1
        end
    end
end

local function format_alert_message(code, message)
    return tostring(code) .. ": " .. tostring(message or "")
end

local function send_event(payload, stream_id)
    local endpoint = config.get_setting and config.get_setting("event_request") or ""
    if type(endpoint) ~= "string" or endpoint == "" then
        return
    end

    local parsed = parse_url(endpoint)
    if not parsed or (parsed.format ~= "http" and parsed.format ~= "https") then
        return
    end

    if parsed.format == "https" and not (astra and astra.features and astra.features.ssl) then
        return
    end

    local port = parsed.port or (parsed.format == "https" and 443 or 80)
    local path = parsed.path or "/"
    local host_header = parsed.host or ""
    if port then
        host_header = host_header .. ":" .. tostring(port)
    end

    local body = json.encode(payload)
    http_request({
        host = parsed.host,
        port = port,
        path = path,
        method = "POST",
        ssl = (parsed.format == "https"),
        headers = {
            "Content-Type: application/json",
            "Content-Length: " .. tostring(#body),
            "Host: " .. host_header,
            "Connection: close",
        },
        content = body,
        callback = function(self, response)
            if response and response.code and response.code >= 400 then
                log.warning("[transcode " .. tostring(stream_id) .. "] event_request failed: " ..
                    tostring(response.code))
            end
        end,
    })
end

record_alert = function(job, code, message, meta)
    local ts = os.time()
    job.last_alert = {
        code = code,
        message = message,
        ts = ts,
    }
    if config and config.add_alert then
        config.add_alert("ERROR", job.id, code, message, meta)
    end
    log.error("[transcode " .. tostring(job.id) .. "] " .. format_alert_message(code, message))
    send_event({
        event = "transcode_alert",
        stream_id = job.id,
        code = code,
        message = message,
        ts = ts,
    }, job.id)
end

local function append_stderr_tail(job, line)
    if not line or line == "" then
        return
    end
    local tail = job.stderr_tail
    if type(tail) ~= "table" then
        tail = {}
        job.stderr_tail = tail
    end
    table.insert(tail, line)
    while #tail > STDERR_TAIL_MAX do
        table.remove(tail, 1)
    end
end

local function normalize_restart_meta(meta)
    if type(meta) == "table" then
        return meta
    end
    if meta ~= nil then
        return { detail = meta }
    end
    return {}
end

local function resolve_restart_reason_code(code)
    if not code then
        return "UNKNOWN"
    end
    local map = {
        TRANSCODE_STALL = "NO_PROGRESS",
        TRANSCODE_ERRORS_RATE = "ERROR_RATE",
        TRANSCODE_PROBE_FAILED = "OUTPUT_PROBE_FAIL",
        TRANSCODE_LOW_BITRATE = "LOW_BITRATE",
        TRANSCODE_AV_DESYNC = "AV_DESYNC",
        TRANSCODE_EXIT = "EXIT_UNEXPECTED",
        TRANSCODE_INPUT_FAILOVER = "INPUT_NO_DATA",
        CC_ERRORS = "CC_ERRORS",
        PES_ERRORS = "PES_ERRORS",
        SCRAMBLED = "SCRAMBLED",
    }
    if map[code] then
        return map[code]
    end
    return code
end

local function compute_restart_delay(watchdog, history)
    local base = watchdog and tonumber(watchdog.restart_delay_sec) or 0
    if base < 0 then
        base = 0
    end
    local jitter = watchdog and tonumber(watchdog.restart_jitter_sec) or 0
    if jitter < 0 then
        jitter = 0
    end
    local backoff_base = watchdog and tonumber(watchdog.restart_backoff_base_sec) or 0
    if backoff_base < 0 then
        backoff_base = 0
    end
    local backoff_factor = watchdog and tonumber(watchdog.restart_backoff_factor) or 2
    if backoff_factor < 1 then
        backoff_factor = 1
    end
    local backoff_max = watchdog and tonumber(watchdog.restart_backoff_max_sec) or 0
    if backoff_max < 0 then
        backoff_max = 0
    end
    local attempts = type(history) == "table" and #history or 0
    local backoff = 0
    if backoff_base > 0 and attempts > 1 then
        backoff = backoff_base * (backoff_factor ^ (attempts - 2))
        if backoff_max > 0 and backoff > backoff_max then
            backoff = backoff_max
        end
    end
    local delay = base + backoff
    if jitter > 0 then
        delay = delay + (math.random() * jitter)
    end
    return delay
end

local function mark_error_line(job, line)
    local now = os.time()
    table.insert(job.error_events, now)
    job.last_error_line = line
    job.last_error_ts = now
end

local function match_error_line(line)
    if not line or line == "" then
        return false
    end
    local lower = string.lower(line)
    for _, pat in ipairs(error_patterns) do
        if lower:find(pat, 1, true) then
            return true
        end
    end
    return false
end

local function parse_bitrate_kbps(value)
    if not value or value == "" then
        return nil
    end
    local text = tostring(value)
    if text == "N/A" or text == "n/a" then
        return nil
    end
    local num, unit = text:match("([%d%.]+)%s*([kKmMgG]?)bits/s")
    if not num then
        return nil
    end
    local rate = tonumber(num)
    if not rate then
        return nil
    end
    unit = string.lower(unit or "")
    if unit == "" then
        return rate / 1000
    elseif unit == "k" then
        return rate
    elseif unit == "m" then
        return rate * 1000
    elseif unit == "g" then
        return rate * 1000 * 1000
    end
    return rate
end

local function parse_probe_bitrate_kbps(payload)
    if type(payload) ~= "table" then
        return nil
    end
    local format = payload.format or {}
    local rate = tonumber(format.bit_rate)
    if rate and rate > 0 then
        return rate / 1000
    end
    local sum = 0
    local found = false
    local streams = payload.streams or {}
    for _, stream in ipairs(streams) do
        local stream_rate = tonumber(stream.bit_rate)
        if stream_rate and stream_rate > 0 then
            sum = sum + stream_rate
            found = true
        end
    end
    if found then
        return sum / 1000
    end
    local packets = payload.packets or {}
    if #packets > 1 then
        local total_bytes = 0
        local min_ts
        local max_ts
        for _, packet in ipairs(packets) do
            local size = tonumber(packet.size)
            local pts = tonumber(packet.pts_time)
            if size then
                total_bytes = total_bytes + size
            end
            if pts then
                if not min_ts or pts < min_ts then
                    min_ts = pts
                end
                if not max_ts or pts > max_ts then
                    max_ts = pts
                end
            end
        end
        if min_ts and max_ts and max_ts > min_ts and total_bytes > 0 then
            local bps = (total_bytes * 8) / (max_ts - min_ts)
            return bps / 1000
        end
    end
    return nil
end

build_probe_args = function(url, duration_sec, include_packets, extra_args, ffprobe_bin)
    local bin = ffprobe_bin or "ffprobe"
    local args = {
        bin,
        "-v", "error",
        "-print_format", "json",
    }
    if type(extra_args) == "table" then
        for _, item in ipairs(extra_args) do
            table.insert(args, tostring(item))
        end
    end
    if include_packets then
        table.insert(args, "-show_packets")
    end
    table.insert(args, "-show_streams")
    table.insert(args, "-show_format")
    local entries = "stream=index,codec_type,codec_name,bit_rate,sample_rate:format=bit_rate"
    if include_packets then
        entries = entries .. ":packet=pts_time,stream_index,size"
    end
    table.insert(args, "-show_entries")
    table.insert(args, entries)
    table.insert(args, "-read_intervals")
    table.insert(args, "%+" .. tostring(duration_sec))
    table.insert(args, "-i")
    table.insert(args, tostring(url))
    return args
end

local function get_analyze_concurrency_limit()
    local limit = nil
    if config and config.get_setting then
        limit = tonumber(config.get_setting("monitor_analyze_max_concurrency"))
    end
    if not limit or limit <= 0 then
        limit = ANALYZE_MAX_CONCURRENCY_DEFAULT
    end
    return limit
end

local function build_analyze_args(url, duration_sec)
    local seconds = tonumber(duration_sec) or 1
    if seconds < 1 then
        seconds = 1
    end
    return {
        "./astra",
        "scripts/analyze.lua",
        "-n",
        tostring(seconds),
        tostring(url),
    }
end

local function parse_analyze_bitrate_kbps(line)
    if not line or line == "" then
        return nil
    end
    local value = line:match("[Bb]itrate:%s*(%d+)%s*Kbit/s")
    if not value then
        return nil
    end
    return tonumber(value)
end

local function parse_analyze_error_count(line, prefix)
    if not line or line == "" or not prefix then
        return nil
    end
    if not line:find(prefix, 1, true) then
        return nil
    end
    local total = 0
    for value in line:gmatch("=%s*(%d+)") do
        total = total + (tonumber(value) or 0)
    end
    return total
end

local function should_trigger_error(now, last_ts, hold_sec)
    if not last_ts then
        return true
    end
    if not hold_sec or hold_sec <= 0 then
        return true
    end
    return (now - last_ts) >= hold_sec
end

local function is_output_monitor_enabled(wd)
    if not wd then
        return false
    end
    if (wd.probe_interval_sec or 0) > 0 then
        return true
    end
    if (wd.no_progress_timeout_sec or 0) > 0 then
        return true
    end
    if (wd.max_error_lines_per_min or 0) > 0 then
        return true
    end
    if wd.low_bitrate_enabled == true then
        return true
    end
    return false
end

local function update_progress(job, line)
    local key, value = line:match("^([^=]+)=(.*)$")
    if not key then
        return
    end

    job.last_progress = job.last_progress or {}
    job.last_progress[key] = value
    job.last_progress_ts = os.time()

    if key == "bitrate" then
        local bitrate = parse_bitrate_kbps(value)
        if bitrate then
            job.output_bitrate_kbps = bitrate
        end
    end

    if key == "out_time_ms" then
        local numeric = tonumber(value)
        if numeric and (not job.last_out_time_ms or numeric > job.last_out_time_ms) then
            job.last_out_time_ms = numeric
            job.last_out_time_ts = job.last_progress_ts
        end
    end
end

local function consume_lines(job, buffer_key, chunk, handler)
    if not chunk or chunk == "" then
        return
    end
    job[buffer_key] = (job[buffer_key] or "") .. chunk
    while true do
        local line, rest = job[buffer_key]:match("^(.-)\n(.*)$")
        if not line then
            break
        end
        job[buffer_key] = rest
        handler(line:gsub("\r$", ""))
    end
end

local function get_log_to_main_mode(tc)
    if not tc then
        return nil
    end
    local mode = tc.log_to_main
    if mode == true then
        return "all"
    end
    if type(mode) == "string" then
        mode = mode:lower()
        if mode == "all" or mode == "true" then
            return "all"
        end
        if mode == "error" or mode == "errors" then
            return "errors"
        end
    end
    return nil
end

local function read_process_output(job)
    if not job.proc then
        return
    end
    local log_mode = get_log_to_main_mode(job.config and job.config.transcode)

    local out_chunk = job.proc:read_stdout()
    consume_lines(job, "stdout_buf", out_chunk, function(line)
        update_progress(job, line)
    end)

    local err_chunk = job.proc:read_stderr()
    consume_lines(job, "stderr_buf", err_chunk, function(line)
        update_progress(job, line)
        local is_error = match_error_line(line)
        if is_error then
            mark_error_line(job, line)
        end
        append_stderr_tail(job, line)
        if log_mode == "all" then
            log.info("[transcode " .. tostring(job.id) .. "] ffmpeg: " .. line)
        elseif log_mode == "errors" and is_error then
            log.warning("[transcode " .. tostring(job.id) .. "] ffmpeg: " .. line)
        end
        if job.log_file_handle then
            job.log_file_handle:write(line .. "\n")
            job.log_file_handle:flush()
        end
    end)
end

local function close_log_file(job)
    if job.log_file_handle then
        job.log_file_handle:close()
        job.log_file_handle = nil
    end
end

local function open_log_file(job, path)
    if not path or path == "" then
        return
    end
    local handle, err = io.open(path, "a")
    if not handle then
        log.error("[transcode " .. tostring(job.id) .. "] failed to open log_file: " .. tostring(err))
        return
    end
    job.log_file_handle = handle
end

request_stop = function(job)
    if not job.proc or job.term_sent_ts then
        return
    end
    job.proc:terminate()
    job.term_sent_ts = os.time()
    local stop_timeout = tonumber(job.watchdog and job.watchdog.stop_timeout_sec) or 5
    if stop_timeout < 1 then
        stop_timeout = 1
    end
    job.kill_due_ts = job.term_sent_ts + stop_timeout
    job.kill_attempts = 0
end

extract_exit_info = function(status)
    if type(status) ~= "table" then
        return nil, nil
    end
    local exit_code = status.exit_code or status.code
    local exit_signal = status.signal or status.exit_signal
    return exit_code, exit_signal
end

local function finalize_process_exit(job, status)
    if not status then
        return
    end
    if job.proc then
        job.proc:close()
    end
    local exit_code, exit_signal = extract_exit_info(status)
    job.ffmpeg_exit_code = exit_code
    job.ffmpeg_exit_signal = exit_signal
    job.proc = nil
    job.pid = nil
    job.term_sent_ts = nil
    job.kill_due_ts = nil
    job.kill_attempts = nil
    job.last_exit = status
end

local function restart_allowed(job, output_state, watchdog)
    local now = os.time()
    local cutoff = now - 600
    local history = output_state and output_state.restart_history or job.restart_history
    if type(history) ~= "table" then
        history = {}
        if output_state then
            output_state.restart_history = history
        else
            job.restart_history = history
        end
    end
    prune_time_list(history, cutoff)
    local limit = watchdog and watchdog.max_restarts_per_10min or 0
    if limit > 0 and #history >= limit then
        record_alert(job, "TRANSCODE_RESTART_LIMIT", "restart limit exceeded", {
            limit = limit,
            output_index = output_state and output_state.index or nil,
            output_url = output_state and output_state.url or nil,
        })
        job.state = "ERROR"
        return false, history
    end
    return true, history
end

schedule_restart = function(job, output_state, code, message, meta)
    if job.state == "ERROR" or job.state == "RESTARTING" then
        return false
    end
    local watchdog = output_state and output_state.watchdog or job.watchdog
    if not watchdog then
        return false
    end
    local now = os.time()
    local cooldown = tonumber(watchdog.restart_cooldown_sec) or 0
    if output_state and cooldown > 0 and output_state.last_restart_ts then
        local note = now - output_state.last_restart_ts
        if note < cooldown then
            log.warning("[transcode " .. tostring(job.id) .. "] restart suppressed (cooldown) output #" ..
                tostring(output_state.index))
            return false
        end
    end
    local reason_code = resolve_restart_reason_code(code)
    local payload = normalize_restart_meta(meta)
    local alert_message = message
    if output_state then
        payload.output_index = output_state.index
        payload.output_url = output_state.url
        alert_message = "output #" .. tostring(output_state.index) .. ": " .. tostring(message or "")
    end
    record_alert(job, reason_code, alert_message, payload)
    local ok, history = restart_allowed(job, output_state, watchdog)
    if not ok then
        return false
    end
    table.insert(history, now)
    if history ~= job.restart_history then
        if type(job.restart_history) ~= "table" then
            job.restart_history = {}
        end
        prune_time_list(job.restart_history, now - 600)
        table.insert(job.restart_history, now)
    end
    if output_state then
        output_state.last_restart_ts = now
        output_state.last_restart_reason = reason_code
    end
    job.state = "RESTARTING"
    job.restart_due_ts = now + compute_restart_delay(watchdog, history)
    job.restart_reason = reason_code
    job.restart_reason_code = reason_code
    job.restart_reason_meta = payload
    job.restart_output_index = output_state and output_state.index or nil
    request_stop(job)
    return true
end

parse_probe_json = function(raw)
    local ok, payload = pcall(json.decode, raw)
    if not ok then
        return nil, "invalid json"
    end
    if type(payload) ~= "table" then
        return nil, "probe payload is not a table"
    end
    return payload, nil
end

local function median(list)
    if #list == 0 then
        return nil
    end
    table.sort(list)
    local mid = math.floor((#list + 1) / 2)
    return list[mid]
end

local function evaluate_probe(job, output_state, watchdog, payload)
    local streams = payload.streams or {}
    local packets = payload.packets or {}
    local video_index
    local audio_index
    for _, stream in ipairs(streams) do
        if stream.codec_type == "video" and video_index == nil then
            video_index = stream.index
        elseif stream.codec_type == "audio" and audio_index == nil then
            audio_index = stream.index
        end
    end
    if video_index == nil or audio_index == nil then
        return false, "missing audio/video streams"
    end

    local video_pts = {}
    local audio_pts = {}
    for _, packet in ipairs(packets) do
        local pts = tonumber(packet.pts_time)
        if pts then
            if packet.stream_index == video_index then
                table.insert(video_pts, pts)
            elseif packet.stream_index == audio_index then
                table.insert(audio_pts, pts)
            end
        end
    end

    local vmed = median(video_pts)
    local amed = median(audio_pts)
    if not vmed or not amed then
        return false, "insufficient pts samples"
    end
    local diff_ms = math.abs(vmed - amed) * 1000
    output_state.last_desync_ms = diff_ms
    if output_state.index == 1 then
        job.last_desync_ms = diff_ms
    end
    if diff_ms > watchdog.desync_threshold_ms then
        output_state.desync_strikes = (output_state.desync_strikes or 0) + 1
        if output_state.desync_strikes >= watchdog.desync_fail_count then
            schedule_restart(job, output_state, "AV_DESYNC", "A/V desync detected", {
                desync_ms = diff_ms,
            })
        end
        return false, "desync"
    end
    output_state.desync_strikes = 0
    return true, nil
end

local function update_output_bitrate(job, output_state, bitrate, now)
    if not bitrate then
        return
    end
    output_state.current_bitrate_kbps = bitrate
    output_state.last_bitrate_ts = now
    if output_state.index == 1 then
        job.output_bitrate_kbps = bitrate
    end

    local wd = output_state.watchdog
    if not wd or wd.low_bitrate_enabled ~= true then
        output_state.low_bitrate_active = false
        output_state.low_bitrate_since = nil
        output_state.low_bitrate_seconds = 0
        output_state.low_bitrate_trigger_ts = nil
        return
    end

    local threshold = tonumber(wd.low_bitrate_min_kbps) or 0
    if bitrate < threshold then
        if not output_state.low_bitrate_since then
            output_state.low_bitrate_since = now
        end
        output_state.low_bitrate_active = true
        output_state.low_bitrate_seconds = now - output_state.low_bitrate_since
        local hold = tonumber(wd.low_bitrate_hold_sec) or 0
        if hold > 0 and output_state.low_bitrate_seconds >= hold then
            local cooldown = tonumber(wd.restart_cooldown_sec) or 0
            if not output_state.last_restart_ts or now - output_state.last_restart_ts >= cooldown then
                local last_trigger = output_state.low_bitrate_trigger_ts or 0
                if now - last_trigger >= hold then
                    output_state.low_bitrate_trigger_ts = now
                    schedule_restart(job, output_state, "LOW_BITRATE", "low bitrate detected", {
                        bitrate_kbps = bitrate,
                        threshold_kbps = threshold,
                        hold_sec = hold,
                    })
                end
            end
        end
        return
    end

    output_state.low_bitrate_active = false
    output_state.low_bitrate_since = nil
    output_state.low_bitrate_seconds = 0
    output_state.low_bitrate_trigger_ts = nil
end

local function handle_output_probe_success(job, output_state, payload, bitrate)
    local now = os.time()
    output_state.last_probe_ts = now
    output_state.last_probe_ok = true
    output_state.last_probe_error = nil
    output_state.probe_failures = 0
    if output_state.index == 1 then
        job.output_last_ok_ts = now
        job.output_last_error = nil
    end
    if bitrate then
        update_output_bitrate(job, output_state, bitrate, now)
    end
    if payload then
        evaluate_probe(job, output_state, output_state.watchdog, payload)
    end
end

local function handle_output_probe_failure(job, output_state, err)
    local now = os.time()
    output_state.last_probe_ts = now
    output_state.last_probe_ok = false
    output_state.last_probe_error = err
    output_state.probe_failures = (output_state.probe_failures or 0) + 1
    if output_state.index == 1 then
        job.output_last_error = err
    end
    if output_state.probe_failures >= output_state.watchdog.probe_fail_count then
        schedule_restart(job, output_state, "OUTPUT_PROBE_FAIL", err or "probe failed", nil)
        output_state.probe_failures = 0
    end
end

local function handle_input_probe_result(job, payload, err)
    local now = os.time()
    if payload then
        local bitrate = parse_probe_bitrate_kbps(payload)
        job.input_last_ok_ts = now
        job.input_last_error = nil
        local profile = extract_stream_profile(payload)
        if profile then
            job.active_input_profile = profile
            if job.failover and job.active_input_id == 1 then
                job.failover.base_profile = profile
            end
        end
        if bitrate then
            job.input_bitrate_kbps = bitrate
        end
        job.input_probe_failures = 0
        return
    end

    job.input_last_error = err
    job.input_probe_failures = (job.input_probe_failures or 0) + 1
end

local function release_analyze_slot(probe)
    if not probe or probe.engine ~= "astra_analyze" then
        return
    end
    if probe.analyze_slot then
        transcode.analyze_active = math.max(0, transcode.analyze_active - 1)
        probe.analyze_slot = false
    end
end

local function tick_output_probe(job, output_state, now)
    local probe = output_state.probe
    if not probe or not probe.proc then
        return
    end

    local out_chunk = probe.proc:read_stdout()
    if out_chunk then
        if probe.engine == "astra_analyze" then
            consume_lines(probe, "stdout_buf", out_chunk, function(line)
                local bitrate = parse_analyze_bitrate_kbps(line)
                if bitrate then
                    probe.had_bitrate = true
                    probe.last_bitrate = bitrate
                    update_output_bitrate(job, output_state, bitrate, now)
                end
                local cc_errors = parse_analyze_error_count(line, "CC:")
                if cc_errors ~= nil then
                    output_state.cc_errors = cc_errors
                    output_state.cc_errors_ts = now
                    local wd = output_state.watchdog
                    if wd and wd.cc_error_limit and wd.cc_error_limit > 0 and cc_errors >= wd.cc_error_limit then
                        if should_trigger_error(now, output_state.cc_error_trigger_ts, wd.cc_error_hold_sec) then
                            output_state.cc_error_trigger_ts = now
                            schedule_restart(job, output_state, "CC_ERRORS", "CC errors detected", {
                                count = cc_errors,
                                limit = wd.cc_error_limit,
                            })
                        end
                    end
                end
                local pes_errors = parse_analyze_error_count(line, "PES:")
                if pes_errors ~= nil then
                    output_state.pes_errors = pes_errors
                    output_state.pes_errors_ts = now
                    local wd = output_state.watchdog
                    if wd and wd.pes_error_limit and wd.pes_error_limit > 0 and pes_errors >= wd.pes_error_limit then
                        if should_trigger_error(now, output_state.pes_error_trigger_ts, wd.pes_error_hold_sec) then
                            output_state.pes_error_trigger_ts = now
                            schedule_restart(job, output_state, "PES_ERRORS", "PES errors detected", {
                                count = pes_errors,
                                limit = wd.pes_error_limit,
                            })
                        end
                    end
                end
                local scrambled = parse_analyze_error_count(line, "Scrambled:")
                if scrambled ~= nil then
                    output_state.scrambled_errors = scrambled
                    output_state.scrambled_errors_ts = now
                    output_state.scrambled_active = scrambled > 0
                    local wd = output_state.watchdog
                    if wd and wd.scrambled_limit and wd.scrambled_limit > 0 and scrambled >= wd.scrambled_limit then
                        if should_trigger_error(now, output_state.scrambled_trigger_ts, wd.scrambled_hold_sec) then
                            output_state.scrambled_trigger_ts = now
                            schedule_restart(job, output_state, "SCRAMBLED", "scrambled packets detected", {
                                count = scrambled,
                                limit = wd.scrambled_limit,
                            })
                        end
                    end
                end
            end)
        else
            probe.stdout_buf = (probe.stdout_buf or "") .. out_chunk
        end
    end

    local err_chunk = probe.proc:read_stderr()
    if err_chunk then
        probe.stderr_buf = (probe.stderr_buf or "") .. err_chunk
    end

    local timeout_sec = output_state.watchdog.probe_timeout_sec
    local status = probe.proc:poll()
    if status then
        probe.proc:close()
        if probe.engine == "ffprobe" then
            local payload, err = parse_probe_json(probe.stdout_buf or "")
            if payload then
                local bitrate = parse_probe_bitrate_kbps(payload)
                handle_output_probe_success(job, output_state, payload, bitrate)
            else
                handle_output_probe_failure(job, output_state, err or "ffprobe failed")
            end
        else
            if probe.had_bitrate then
                handle_output_probe_success(job, output_state, nil, probe.last_bitrate)
            else
                handle_output_probe_failure(job, output_state, "analyze failed")
            end
        end
        release_analyze_slot(probe)
        output_state.probe = nil
        output_state.probe_inflight = false
    elseif timeout_sec > 0 and now - probe.start_ts >= timeout_sec then
        probe.proc:kill()
        probe.proc:close()
        release_analyze_slot(probe)
        output_state.probe = nil
        output_state.probe_inflight = false
        local err = probe.engine == "astra_analyze" and "analyze timeout" or "ffprobe timeout"
        handle_output_probe_failure(job, output_state, err)
    end
end

local function tick_input_probe(job, now)
    local probe = job.input_probe
    if not probe or not probe.proc then
        return
    end
    local out_chunk = probe.proc:read_stdout()
    if out_chunk then
        probe.stdout_buf = (probe.stdout_buf or "") .. out_chunk
    end
    local err_chunk = probe.proc:read_stderr()
    if err_chunk then
        probe.stderr_buf = (probe.stderr_buf or "") .. err_chunk
    end
    local status = probe.proc:poll()
    if status then
        local payload, err = parse_probe_json(probe.stdout_buf or "")
        probe.proc:close()
        job.input_probe = nil
        job.input_probe_inflight = false
        handle_input_probe_result(job, payload, err)
    elseif now - probe.start_ts >= job.watchdog.probe_timeout_sec then
        probe.proc:kill()
        probe.proc:close()
        job.input_probe = nil
        job.input_probe_inflight = false
        handle_input_probe_result(job, nil, "ffprobe timeout")
    end
end

local function tick_probes(job, now)
    for _, output_state in ipairs(job.output_monitors or {}) do
        tick_output_probe(job, output_state, now)
    end
    if job.input_probe then
        tick_input_probe(job, now)
    end
end

local function start_output_probe(job, output_state)
    if not output_state or output_state.probe_inflight then
        return
    end
    local url = output_state.url
    if not url or url == "" then
        return
    end
    local engine = resolve_monitor_engine(output_state.watchdog.monitor_engine, url)
    if engine == "astra_analyze" then
        local limit = get_analyze_concurrency_limit()
        if transcode.analyze_active >= limit then
            output_state.analyze_pending = true
            return
        end
        local args = build_analyze_args(url, output_state.watchdog.probe_duration_sec)
        local ok, proc = pcall(process.spawn, args, { stdout = "pipe", stderr = "pipe" })
        if not ok or not proc then
            handle_output_probe_failure(job, output_state, "analyze spawn failed")
            return
        end
        transcode.analyze_active = transcode.analyze_active + 1
        output_state.analyze_pending = false
        output_state.probe_inflight = true
        output_state.probe = {
            engine = "astra_analyze",
            proc = proc,
            stdout_buf = "",
            stderr_buf = "",
            start_ts = os.time(),
            had_bitrate = false,
            last_bitrate = nil,
            analyze_slot = true,
        }
        return
    end

    local ffprobe_bin = resolve_ffprobe_path(job.config.transcode)
    local args = build_probe_args(url, output_state.watchdog.probe_duration_sec, true, nil, ffprobe_bin)
    local ok, proc = pcall(process.spawn, args, { stdout = "pipe", stderr = "pipe" })
    if not ok or not proc then
        handle_output_probe_failure(job, output_state, "ffprobe spawn failed")
        return
    end
    output_state.probe_inflight = true
    output_state.probe = {
        engine = "ffprobe",
        proc = proc,
        stdout_buf = "",
        stderr_buf = "",
        start_ts = os.time(),
    }
end

local function start_input_probe(job)
    if job.input_probe_inflight then
        return
    end
    local url = get_active_input_url(job.config, job.active_input_id, job.failover and job.failover.enabled)
    if not url or url == "" then
        return
    end
    local tc = job.config.transcode or {}
    local extra_args = nil
    local include_packets = false
    if is_udp_url(url) then
        if tc.input_probe_udp ~= true then
            return
        end
        if job.proc then
            return
        end
        extra_args = {
            "-analyzeduration", tostring(UDP_PROBE_ANALYZE_US),
            "-probesize", tostring(UDP_PROBE_SIZE),
        }
        include_packets = true
    end
    local ffprobe_bin = resolve_ffprobe_path(tc)
    local args = build_probe_args(url, job.watchdog.probe_duration_sec, include_packets, extra_args, ffprobe_bin)
    local ok, proc = pcall(process.spawn, args, { stdout = "pipe", stderr = "pipe" })
    if not ok or not proc then
        handle_input_probe_result(job, nil, "ffprobe spawn failed")
        return
    end
    job.input_probe_inflight = true
    job.input_probe = {
        proc = proc,
        stdout_buf = "",
        stderr_buf = "",
        start_ts = os.time(),
    }
end

local function has_output_probe_interval(job)
    for _, output_state in ipairs(job.output_monitors or {}) do
        local wd = output_state.watchdog
        if wd and wd.probe_interval_sec > 0 then
            return true
        end
    end
    return false
end

local function should_preprobe_udp(job)
    local tc = job.config.transcode or {}
    if tc.input_probe_udp ~= true then
        return false
    end
    if not has_output_probe_interval(job) then
        return false
    end
    local url = get_active_input_url(job.config, job.active_input_id, job.failover and job.failover.enabled)
    return is_udp_url(url)
end

local function should_restart_input_probe(job)
    local tc = job.config.transcode or {}
    return should_preprobe_udp(job) and tc.input_probe_restart == true
end

local function tick_job(job)
    local now = os.time()
    read_process_output(job)

    if job.proc then
        local status = job.proc:poll()
        if status then
            finalize_process_exit(job, status)
            if job.state == "RUNNING" then
                schedule_restart(job, nil, "EXIT_UNEXPECTED", "ffmpeg exited unexpectedly", {
                    exit = status,
                })
            end
        elseif job.term_sent_ts and now >= (job.kill_due_ts or 0) then
            job.kill_attempts = (job.kill_attempts or 0) + 1
            local killed = false
            if type(job.proc.kill_tree) == "function" then
                local ok = pcall(job.proc.kill_tree, job.proc)
                killed = ok
            end
            if not killed then
                job.proc:kill()
            end
            job.kill_due_ts = now + 1
        end
    end

    prune_time_list(job.error_events, now - 60)

    if job.state == "RUNNING" then
        local input_probe_triggered = false
        for _, output_state in ipairs(job.output_monitors or {}) do
            local wd = output_state.watchdog
            if wd then
                if wd.no_progress_timeout_sec > 0 then
                    local last_ts = job.last_out_time_ts or job.last_progress_ts or job.start_ts
                    if last_ts and now - last_ts >= wd.no_progress_timeout_sec then
                        schedule_restart(job, output_state, "NO_PROGRESS", "no progress detected", {
                            timeout_sec = wd.no_progress_timeout_sec,
                        })
                    end
                end

                if wd.max_error_lines_per_min > 0 and #job.error_events >= wd.max_error_lines_per_min then
                    schedule_restart(job, output_state, "ERROR_RATE", "ffmpeg errors rate exceeded", {
                        count = #job.error_events,
                    })
                end

                if wd.probe_interval_sec > 0 then
                    if not output_state.next_probe_ts then
                        output_state.next_probe_ts = now + math.min(wd.probe_interval_sec, 5)
                    elseif now >= output_state.next_probe_ts then
                        output_state.next_probe_ts = now + wd.probe_interval_sec
                        start_output_probe(job, output_state)
                        if not input_probe_triggered then
                            if should_restart_input_probe(job) then
                                transcode.restart(job, "input probe refresh")
                            else
                                start_input_probe(job)
                            end
                            input_probe_triggered = true
                        end
                    end
                end
            end

            if output_state.analyze_pending and not output_state.probe_inflight then
                start_output_probe(job, output_state)
            end
        end
    end

    tick_probes(job, now)
    tick_switch_warmup(job, now)
    tick_failover_compat_probes(job, now)
    transcode_failover_tick(job, now)

    if job.preprobe_pending and job.state == "STARTING" and not job.input_probe_inflight and not job.input_probe then
        job.preprobe_pending = false
        transcode.start(job, { skip_preprobe = true })
    end

    if job.state == "RESTARTING" and (not job.proc) and job.restart_due_ts and now >= job.restart_due_ts then
        job.restart_due_ts = nil
        transcode.start(job)
    end
end

local function ensure_timer(job)
    if job.timer then
        return
    end
    job.timer = timer({
        interval = 1,
        callback = function(self)
            if not job then
                self:close()
                return
            end
            tick_job(job)
            if job.state == "STOPPED" and not job.proc then
                self:close()
                job.timer = nil
            end
        end,
    })
end

local function reset_output_monitor_state(output_state, now)
    output_state.probe = nil
    output_state.probe_inflight = false
    output_state.probe_failures = 0
    output_state.last_probe_ts = nil
    output_state.last_probe_ok = nil
    output_state.last_probe_error = nil
    output_state.current_bitrate_kbps = nil
    output_state.last_bitrate_ts = nil
    output_state.low_bitrate_active = false
    output_state.low_bitrate_since = nil
    output_state.low_bitrate_seconds = 0
    output_state.low_bitrate_trigger_ts = nil
    output_state.desync_strikes = 0
    output_state.last_desync_ms = nil
    output_state.cc_errors = nil
    output_state.cc_errors_ts = nil
    output_state.cc_error_trigger_ts = nil
    output_state.pes_errors = nil
    output_state.pes_errors_ts = nil
    output_state.pes_error_trigger_ts = nil
    output_state.scrambled_errors = nil
    output_state.scrambled_errors_ts = nil
    output_state.scrambled_active = nil
    output_state.scrambled_trigger_ts = nil
    output_state.next_probe_ts = nil
    output_state.analyze_pending = false
    if output_state.watchdog and output_state.watchdog.probe_interval_sec > 0 then
        output_state.next_probe_ts = now + math.min(output_state.watchdog.probe_interval_sec, 5)
    end
end

local function stop_output_monitor(output_state)
    if output_state.probe and output_state.probe.proc then
        output_state.probe.proc:kill()
        output_state.probe.proc:close()
        release_analyze_slot(output_state.probe)
    end
    output_state.probe = nil
    output_state.probe_inflight = false
    output_state.analyze_pending = false
end

function transcode.start(job, opts)
    opts = opts or {}
    if job.state == "ERROR" then
        return false
    end
    if not process or type(process.spawn) ~= "function" then
        record_alert(job, "TRANSCODE_UNSUPPORTED", "process module not available", nil)
        job.state = "ERROR"
        return false
    end
    local tc = job.config.transcode or {}
    local engine = normalize_engine(tc)
    if engine == "nvidia" then
        local ok, err = check_nvidia_support()
        if not ok then
            record_alert(job, "TRANSCODE_GPU_UNAVAILABLE", err or "nvidia device not available", {
                engine = engine,
            })
            job.state = "ERROR"
            return false
        end
        local metrics, metrics_err = query_nvidia_gpus()
        local selected_gpu = select_gpu_device(tc, metrics)
        job.gpu_metrics = metrics
        job.gpu_device = selected_gpu
        if metrics_err then
            job.gpu_metrics_error = metrics_err
        else
            job.gpu_metrics_error = nil
        end
        local overload = check_gpu_overload(tc, metrics, selected_gpu)
        if overload then
            local action = tostring(tc.gpu_overload_action or "warn"):lower()
            record_alert(job, "TRANSCODE_GPU_OVERLOAD", "gpu resource overload", overload)
            if action == "block" then
                job.state = "ERROR"
                return false
            end
        end
    end
    if not opts.skip_preprobe and should_preprobe_udp(job) then
        start_input_probe(job)
        if job.input_probe_inflight then
            job.input_bitrate_kbps = nil
            job.input_last_ok_ts = nil
            job.input_last_error = nil
            job.preprobe_pending = true
            job.state = "STARTING"
            ensure_timer(job)
            return true
        end
    end

    local argv, err, selected_url, bin_info = build_ffmpeg_args(job.config, {
        active_input_id = job.active_input_id,
        gpu_device = job.gpu_device,
    })
    if not argv then
        record_alert(job, "TRANSCODE_CONFIG_ERROR", err or "invalid config", nil)
        job.state = "ERROR"
        job.ffmpeg_input_url = nil
        return false
    end
    job.ffmpeg_input_url = selected_url
    job.ffmpeg_path_resolved = bin_info and bin_info.path or nil
    job.ffmpeg_path_source = bin_info and bin_info.source or nil
    job.ffmpeg_path_exists = bin_info and bin_info.exists or nil
    job.ffmpeg_bundled = bin_info and bin_info.bundled or nil

    close_log_file(job)
    open_log_file(job, job.log_file_path)

    local ok, proc = pcall(process.spawn, argv, { stdout = "pipe", stderr = "pipe" })
    if not ok or not proc then
        record_alert(job, "TRANSCODE_SPAWN_FAILED", "failed to start ffmpeg", nil)
        job.state = "ERROR"
        return false
    end

    job.proc = proc
    job.pid = proc:pid()
    job.start_ts = os.time()
    job.stderr_tail = {}
    job.active_input_profile = nil
    if job.failover then
        job.failover.started_at = job.start_ts
        job.failover.next_probe_ts = job.start_ts
        job.failover.inactive_since = nil
        job.failover.global_state = "RUNNING"
        job.failover.switch_pending = nil
        job.failover.return_pending = nil
        job.failover.switch_warmup = nil
        job.failover.base_profile = nil
    end
    job.last_progress = {}
    job.last_progress_ts = job.start_ts
    job.last_out_time_ts = job.start_ts
    job.last_out_time_ms = 0
    job.stdout_buf = ""
    job.stderr_buf = ""
    job.error_events = {}
    if not should_preprobe_udp(job) then
        job.input_bitrate_kbps = nil
        job.input_last_ok_ts = nil
        job.input_last_error = nil
    end
    job.output_bitrate_kbps = nil
    job.output_last_ok_ts = nil
    job.output_last_error = nil
    job.input_probe_failures = 0
    job.input_probe = nil
    job.input_probe_inflight = false
    for _, output_state in ipairs(job.output_monitors or {}) do
        reset_output_monitor_state(output_state, job.start_ts)
    end
    job.preprobe_pending = false
    job.state = "RUNNING"

    ensure_timer(job)

    return true
end

function transcode.stop(job)
    if job.proc then
        request_stop(job)
    end
    if job.failover then
        stop_switch_warmup(job, "stop")
        job.failover.switch_pending = nil
        job.failover.return_pending = nil
        if job.failover.inputs then
            for idx, _ in ipairs(job.failover.inputs) do
                kill_failover_input(job, idx)
            end
        end
    end
    for _, output_state in ipairs(job.output_monitors or {}) do
        stop_output_monitor(output_state)
    end
    if job.input_probe and job.input_probe.proc then
        job.input_probe.proc:kill()
        job.input_probe.proc:close()
    end
    job.input_probe = nil
    job.input_probe_inflight = false
    job.preprobe_pending = false
    job.state = "STOPPED"
    job.ffmpeg_input_url = nil
    close_log_file(job)
end

function transcode.restart(job, reason)
    if job.state == "ERROR" then
        return false
    end
    return schedule_restart(job, nil, "RESTART_REQUEST", reason or "manual restart", {
        reason = reason,
    })
end

function transcode.upsert(id, row, force)
    local cfg = row.config or {}
    cfg.id = id
    if not cfg.name then
        cfg.name = "Stream " .. id
    end
    local enabled = (tonumber(row.enabled) or 0) ~= 0
    if cfg.enable == false then
        enabled = false
    end

    local job = transcode.jobs[id]
    local prev_active_input_id = job and job.active_input_id or nil
    local hash = row.config_json or ""
    if job and job.hash == hash and not force then
        if enabled and job.state == "STOPPED" then
            transcode.start(job)
        elseif not enabled and job.state ~= "STOPPED" then
            transcode.stop(job)
        end
        job.enabled = enabled
        if job.failover then
            job.failover.enabled = enabled and job.failover.mode ~= "disabled"
            if job.failover.enabled and not job.failover.inputs then
                local inputs, invalid = build_failover_inputs(cfg, job.name)
                if invalid then
                    log.warning("[transcode " .. tostring(job.id) .. "] backup disabled: unsupported input format")
                    job.failover.enabled = false
                else
                    job.failover.inputs = inputs
                    job.failover.channel = { input = inputs }
                    job.active_input_id = job.active_input_id or 1
                    if job.active_input_id < 1 or job.active_input_id > #inputs then
                        job.active_input_id = 1
                    end
                end
            end
        end
        return job
    end

    if job then
        transcode.stop(job)
    end

    job = {
        id = id,
        name = cfg.name,
        config = cfg,
        hash = hash,
        state = "STOPPED",
        restart_history = {},
        error_events = {},
        last_progress = {},
    }
    job.enabled = enabled
    local tc = cfg.transcode or {}
    job.watchdog = normalize_watchdog_defaults(tc)
    job.log_file_path = tc.log_file
    job.outputs = normalize_outputs(tc.outputs, job.watchdog)
    job.output_monitors = {}
    for index, output in ipairs(job.outputs) do
        job.output_monitors[index] = {
            index = index,
            url = output.url,
            watchdog = output.watchdog,
            restart_history = {},
        }
    end
    job.failover = normalize_failover_config(cfg, enabled)
    if job.failover and job.failover.enabled then
        local inputs, invalid = build_failover_inputs(cfg, job.name)
        if invalid then
            log.warning("[transcode " .. tostring(job.id) .. "] backup disabled: unsupported input format")
            job.failover.enabled = false
            job.failover.inputs = nil
            job.failover.channel = nil
        else
            job.failover.inputs = inputs
            job.failover.channel = { input = inputs }
            job.active_input_id = prev_active_input_id or 1
            if job.active_input_id < 1 or job.active_input_id > #inputs then
                job.active_input_id = 1
            end
        end
    else
        job.active_input_id = prev_active_input_id or 1
    end
    transcode.jobs[id] = job

    if enabled then
        transcode.start(job)
    end

    return job
end

function transcode.delete(id)
    local job = transcode.jobs[id]
    if not job then
        return
    end
    transcode.stop(job)
    transcode.jobs[id] = nil
end

function transcode.list_status()
    local out = {}
    for id, job in pairs(transcode.jobs) do
        out[id] = transcode.get_status(id)
    end
    return out
end

function transcode.get_status(id)
    local job = transcode.jobs[id]
    if not job then
        return nil
    end
    local now = os.time()
    prune_time_list(job.restart_history, now - 600)
    local outputs_status = {}
    for _, output_state in ipairs(job.output_monitors or {}) do
        local wd = output_state.watchdog
        if wd then
            prune_time_list(output_state.restart_history, now - 600)
            local cooldown = tonumber(wd.restart_cooldown_sec) or 0
            local remaining = 0
            if output_state.last_restart_ts and cooldown > 0 then
                remaining = cooldown - (now - output_state.last_restart_ts)
                if remaining < 0 then
                    remaining = 0
                end
            end
            outputs_status[#outputs_status + 1] = {
                output_index = output_state.index,
                url = output_state.url,
                monitor_enabled = is_output_monitor_enabled(wd),
                monitor_engine = resolve_monitor_engine(wd.monitor_engine, output_state.url),
                last_probe_ts = output_state.last_probe_ts,
                last_probe_ok = output_state.last_probe_ok,
                last_probe_error = output_state.last_probe_error,
                current_bitrate_kbps = output_state.current_bitrate_kbps,
                cc_errors = output_state.cc_errors,
                cc_errors_ts = output_state.cc_errors_ts,
                pes_errors = output_state.pes_errors,
                pes_errors_ts = output_state.pes_errors_ts,
                scrambled_errors = output_state.scrambled_errors,
                scrambled_errors_ts = output_state.scrambled_errors_ts,
                scrambled_active = output_state.scrambled_active or false,
                low_bitrate_active = output_state.low_bitrate_active or false,
                low_bitrate_seconds_accum = output_state.low_bitrate_active and output_state.low_bitrate_seconds or 0,
                last_restart_ts = output_state.last_restart_ts,
                last_restart_reason = output_state.last_restart_reason,
                restart_cooldown_sec = cooldown,
                restart_cooldown_remaining_sec = remaining,
                restart_count_10min = #output_state.restart_history,
            }
        end
    end
    local inputs = collect_failover_input_stats(job)
    local fo = job.failover
    local active_input_url = get_active_input_url(job.config, job.active_input_id, true)
    local warm_status = nil
    if fo and fo.switch_warmup then
        local warm = fo.switch_warmup
        warm_status = {
            target = warm.target,
            target_url = warm.target_url,
            ok = warm.ok,
            done = warm.done,
            error = warm.error,
            require_idr = warm.require_idr,
            idr_seen = warm.idr_seen,
            keyframe_error = warm.keyframe_error,
            ready = warm.ready,
            last_out_time_ms = warm.last_out_time_ms,
            min_out_time_ms = warm.min_out_time_ms,
            start_ts = warm.start_ts,
            duration_sec = warm.duration_sec,
            exit_code = warm.exit_code,
            exit_signal = warm.exit_signal,
            stderr_tail = warm.stderr_tail,
        }
    end
    return {
        id = job.id,
        name = job.name,
        state = job.state,
        pid = job.pid,
        restarts_10min = #job.restart_history,
        restart_reason_code = job.restart_reason_code,
        restart_reason_meta = job.restart_reason_meta,
        last_progress = job.last_progress,
        last_progress_ts = job.last_progress_ts,
        last_error = job.last_error_line,
        last_error_ts = job.last_error_ts,
        last_alert = job.last_alert,
        stderr_tail = job.stderr_tail or {},
        ffmpeg_exit_code = job.ffmpeg_exit_code,
        ffmpeg_exit_signal = job.ffmpeg_exit_signal,
        desync_ms_last = job.last_desync_ms,
        input_bitrate_kbps = job.input_bitrate_kbps,
        output_bitrate_kbps = job.output_bitrate_kbps,
        input_last_ok_ts = job.input_last_ok_ts,
        output_last_ok_ts = job.output_last_ok_ts,
        input_last_error = job.input_last_error,
        output_last_error = job.output_last_error,
        active_input_id = job.active_input_id,
        active_input_index = job.active_input_id and job.active_input_id > 0 and (job.active_input_id - 1) or nil,
        active_input_url = active_input_url,
        ffmpeg_input_url = job.ffmpeg_input_url,
        ffmpeg_path_resolved = job.ffmpeg_path_resolved,
        ffmpeg_path_source = job.ffmpeg_path_source,
        ffmpeg_bundled = job.ffmpeg_bundled,
        gpu_device = job.gpu_device,
        gpu_metrics = job.gpu_metrics,
        gpu_metrics_error = job.gpu_metrics_error,
        backup_type = fo and fo.mode or nil,
        global_state = fo and fo.global_state or "RUNNING",
        last_switch = fo and fo.last_switch or nil,
        switch_pending = fo and fo.switch_pending or nil,
        return_pending = fo and fo.return_pending or nil,
        switch_warmup = warm_status,
        inputs = inputs,
        inputs_status = inputs,
        outputs = job.outputs,
        outputs_status = outputs_status,
        updated_at = job.last_progress_ts or job.start_ts,
    }
end

function transcode.get_tool_info(include_version)
    local ffmpeg_path, ffmpeg_source, ffmpeg_exists, ffmpeg_bundled = resolve_ffmpeg_path(nil)
    local ffprobe_path, ffprobe_source, ffprobe_exists, ffprobe_bundled = resolve_ffprobe_path(nil)
    local info = {
        ffmpeg_path_resolved = ffmpeg_path,
        ffmpeg_source = ffmpeg_source,
        ffmpeg_exists = ffmpeg_exists,
        ffmpeg_bundled = ffmpeg_bundled,
        ffprobe_path_resolved = ffprobe_path,
        ffprobe_source = ffprobe_source,
        ffprobe_exists = ffprobe_exists,
        ffprobe_bundled = ffprobe_bundled,
    }
    if include_version then
        info.ffmpeg_version = cached_tool_version("ffmpeg", ffmpeg_path)
        info.ffprobe_version = cached_tool_version("ffprobe", ffprobe_path)
    end
    return info
end
