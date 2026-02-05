-- AstralAI context collector (logs + CLI snapshots + metrics)

ai_context = ai_context or {}

ai_context.state = ai_context.state or {
    cli_inflight = 0,
    timeout_checked = false,
    timeout_available = false,
    cache = {},
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

local function setting_string(key, fallback)
    if config and config.get_setting then
        local value = config.get_setting(key)
        if value ~= nil and value ~= "" then
            return tostring(value)
        end
    end
    return fallback
end

local function parse_range_seconds(value, fallback)
    local num = tonumber(value)
    if num and num > 0 then
        return num
    end
    if type(value) == "string" then
        local lower = value:lower()
        local n = tonumber(lower:match("^(%d+)%s*h$"))
        if n then return n * 3600 end
        n = tonumber(lower:match("^(%d+)%s*d$"))
        if n then return n * 86400 end
        n = tonumber(lower:match("^(%d+)%s*m$"))
        if n then return n * 60 end
    end
    return fallback or (24 * 3600)
end

local function clamp_range_seconds(value)
    local max_range = setting_number("ai_metrics_max_range_sec", 7 * 86400)
    if max_range < 3600 then max_range = 3600 end
    local range = parse_range_seconds(value, 24 * 3600)
    if range > max_range then
        range = max_range
    end
    return range
end

local function resolve_metrics_interval(opts)
    local interval = tonumber(opts.metrics_interval_sec or opts.interval_sec)
    if not interval or interval <= 0 then
        interval = setting_number("ai_rollup_interval_sec", 60)
    end
    if interval < 30 then interval = 30 end
    if interval > 3600 then interval = 3600 end
    return math.floor(interval)
end

local function normalize_cli_list(value)
    if value == nil or value == "" then
        return {}
    end
    if value == true then
        return { "stream", "dvbls" }
    end
    local out = {}
    if type(value) == "table" then
        for _, item in ipairs(value) do
            if item and item ~= "" then
                table.insert(out, tostring(item))
            end
        end
        return out
    end
    if type(value) == "string" then
        for item in tostring(value):gmatch("[^,%s]+") do
            table.insert(out, item)
        end
    end
    return out
end

local function normalize_cli_set(list)
    local set = {}
    for _, item in ipairs(list or {}) do
        local key = tostring(item):lower()
        if key ~= "" then
            set[key] = true
        end
    end
    return set
end

local function cache_ttl_sec()
    local ttl = setting_number("ai_cli_cache_sec", 60)
    if ttl < 0 then ttl = 0 end
    if ttl > 600 then ttl = 600 end
    return math.floor(ttl)
end

local function cache_get(key)
    local ttl = cache_ttl_sec()
    if ttl <= 0 then
        return nil
    end
    local entry = ai_context.state.cache[key]
    if entry and entry.ts and (os.time() - entry.ts) <= ttl then
        return entry.data
    end
    return nil
end

local function cache_put(key, data)
    local ttl = cache_ttl_sec()
    if ttl <= 0 then
        return
    end
    ai_context.state.cache[key] = { ts = os.time(), data = data }
end

local function resolve_cli_bin()
    local configured = setting_string("ai_cli_bin_path", "")
    if configured ~= "" then
        return configured
    end
    if _G.argv and _G.argv[0] then
        return _G.argv[0]
    end
    if arg and arg[0] then
        return arg[0]
    end
    return "astral"
end

local function shell_escape(value)
    local text = tostring(value or "")
    return "'" .. text:gsub("'", "'\\''") .. "'"
end

local function has_timeout()
    if ai_context.state.timeout_checked then
        return ai_context.state.timeout_available
    end
    ai_context.state.timeout_checked = true
    local ok = os.execute("command -v timeout >/dev/null 2>&1")
    ai_context.state.timeout_available = (ok == true or ok == 0)
    return ai_context.state.timeout_available
end

local function begin_cli()
    local max = setting_number("ai_cli_max_concurrency", 1)
    if max < 1 then max = 1 end
    if ai_context.state.cli_inflight >= max then
        return nil, "cli busy"
    end
    ai_context.state.cli_inflight = ai_context.state.cli_inflight + 1
    return true
end

local function end_cli()
    if ai_context.state.cli_inflight > 0 then
        ai_context.state.cli_inflight = ai_context.state.cli_inflight - 1
    end
end

local function trim_output(text)
    if not text then
        return ""
    end
    local limit = setting_number("ai_cli_output_limit", 8000)
    if limit < 512 then limit = 512 end
    if #text > limit then
        return text:sub(1, limit) .. "\n...truncated..."
    end
    return text
end

local function run_cli_command(args, timeout_sec)
    local ok, err = begin_cli()
    if not ok then
        return nil, err
    end
    local allow_no_timeout = setting_bool("ai_cli_allow_no_timeout", false)
    local timeout_cmd = ""
    if timeout_sec and timeout_sec > 0 then
        if has_timeout() then
            timeout_cmd = "timeout " .. tostring(math.floor(timeout_sec)) .. " "
        elseif not allow_no_timeout then
            end_cli()
            return nil, "timeout tool missing"
        end
    end
    local bin = resolve_cli_bin()
    local cmd = timeout_cmd .. shell_escape(bin) .. " " .. args .. " 2>&1"
    local ok_p, handle = pcall(io.popen, cmd)
    if not ok_p or not handle then
        end_cli()
        return nil, "exec failed"
    end
    local output = handle:read("*a") or ""
    handle:close()
    end_cli()
    return trim_output(output)
end

local function collect_logs(opts)
    if not config or not config.list_ai_log_events then
        return nil
    end
    local logs_days = setting_number("ai_logs_retention_days", 0)
    if logs_days <= 0 then
        return {}
    end
    local range_sec = parse_range_seconds(opts.range_sec or opts.range, 24 * 3600)
    local limit = tonumber(opts.log_limit) or 50
    if limit < 1 then limit = 1 end
    if limit > 200 then limit = 200 end
    local since = os.time() - range_sec
    local rows = config.list_ai_log_events({
        since = since,
        level = opts.log_level,
        stream_id = opts.stream_id,
        limit = limit,
    })
    return rows or {}
end

local function downsample_metrics(items, max_items)
    local total = #items
    if total <= max_items then
        return items
    end
    local step = math.ceil(total / max_items)
    local out = {}
    local idx = 1
    while idx <= total do
        table.insert(out, items[idx])
        idx = idx + step
    end
    return out
end

local function collect_metrics(opts)
    if not ai_observability or not ai_observability.get_on_demand_metrics then
        return nil
    end
    local scope = opts.metrics_scope
    local scope_id = opts.metrics_scope_id
    if not scope then
        if opts.stream_id and opts.stream_id ~= "" then
            scope = "stream"
            scope_id = opts.stream_id
        else
            scope = "global"
            scope_id = nil
        end
    end
    local range_sec = clamp_range_seconds(opts.range_sec or opts.range)
    local interval_sec = resolve_metrics_interval(opts)
    local result = ai_observability.get_on_demand_metrics(range_sec, interval_sec, scope, scope_id)
    if not result then
        return nil
    end
    local max_items = setting_number("ai_metrics_max_items", 200)
    if max_items < 50 then max_items = 50 end
    if max_items > 500 then max_items = 500 end
    local items = result.items or {}
    local trimmed = downsample_metrics(items, max_items)
    return {
        ts = result.ts,
        mode = result.mode,
        summary = result.summary or {},
        items = trimmed,
    }
end

local function collect_stream_snapshot(stream_id)
    if not runtime or not runtime.list_status then
        return nil
    end
    local status = runtime.list_status() or {}
    if stream_id and stream_id ~= "" then
        local entry = status[stream_id]
        if not entry then
            return nil
        end
        return {
            stream_id = tostring(stream_id),
            on_air = entry.on_air == true,
            bitrate = entry.bitrate or 0,
            transcode_state = entry.transcode_state,
            active_input = entry.active_input,
        }
    end
    local total = 0
    local on_air = 0
    for _, entry in pairs(status) do
        total = total + 1
        if entry.on_air == true or entry.transcode_state == "RUNNING" then
            on_air = on_air + 1
        end
    end
    return {
        streams_total = total,
        streams_on_air = on_air,
    }
end

local function collect_dvbls()
    if not dvbls then
        return nil, "dvbls module not available"
    end
    local cached = cache_get("dvbls")
    if cached then
        return cached
    end
    local list = dvbls() or {}
    local out = {}
    for _, item in ipairs(list) do
        table.insert(out, {
            adapter = item.adapter,
            device = item.device,
            busy = item.busy == true,
            type = item.type,
            frontend = item.frontend,
            mac = item.mac,
            error = item.error,
        })
    end
    cache_put("dvbls", out)
    return out
end

local function collect_analyze(input_url)
    if not input_url or input_url == "" then
        return nil, "input_url required"
    end
    local key = "analyze:" .. tostring(input_url)
    local cached = cache_get(key)
    if cached then
        return cached
    end
    local timeout_sec = setting_number("ai_cli_timeout_sec", 3)
    local args = "--analyze -n 1 " .. shell_escape(input_url)
    local output, err = run_cli_command(args, timeout_sec)
    if not output then
        return nil, err or "analyze failed"
    end
    cache_put(key, output)
    return output
end

local function collect_femon(femon_url)
    if not femon_url or femon_url == "" then
        return nil, "femon_url required"
    end
    local key = "femon:" .. tostring(femon_url)
    local cached = cache_get(key)
    if cached then
        return cached
    end
    local timeout_sec = setting_number("ai_cli_timeout_sec", 3)
    local args = "--femon " .. shell_escape(femon_url)
    local output, err = run_cli_command(args, timeout_sec)
    if not output then
        return nil, err or "femon failed"
    end
    cache_put(key, output)
    return output
end

function ai_context.build_context(opts)
    opts = opts or {}
    local ctx = {
        ts = os.time(),
        include_logs = opts.include_logs == true,
        include_cli = normalize_cli_list(opts.include_cli),
        include_metrics = opts.include_metrics == true,
        errors = {},
    }
    if ctx.include_logs then
        ctx.logs = collect_logs(opts)
    end
    local cli_set = normalize_cli_set(ctx.include_cli)
    if next(cli_set) ~= nil then
        ctx.cli = {}
        if cli_set.stream then
            ctx.cli.stream = collect_stream_snapshot(opts.stream_id)
        end
        if cli_set.dvbls then
            local list, err = collect_dvbls()
            if list then
                ctx.cli.dvbls = list
            elseif err then
                ctx.errors.dvbls = err
            end
        end
        if cli_set.analyze then
            local output, err = collect_analyze(opts.input_url)
            if output then
                ctx.cli.analyze = output
            elseif err then
                ctx.errors.analyze = err
            end
        end
        if cli_set.femon then
            local output, err = collect_femon(opts.femon_url)
            if output then
                ctx.cli.femon = output
            elseif err then
                ctx.errors.femon = err
            end
        end
    end
    if ctx.include_metrics then
        local metrics, err = collect_metrics(opts)
        if metrics then
            ctx.metrics = metrics
        elseif err then
            ctx.errors.metrics = err
        end
    end
    if next(ctx.errors) == nil then
        ctx.errors = nil
    end
    return ctx
end
