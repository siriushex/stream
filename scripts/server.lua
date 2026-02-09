-- Astra API server entrypoint

local script_dir = "scripts/"
do
    local info = debug.getinfo(1, "S")
    if info and info.source then
        local src = info.source
        if src:sub(1, 1) == "@" then
            src = src:sub(2)
        end
        local dir = src:match("^(.*[/\\])")
        if dir and dir ~= "" then
            script_dir = dir
        end
    end
    if script_dir:sub(-1) ~= "/" and script_dir:sub(-1) ~= "\\" then
        script_dir = script_dir .. "/"
    end
end

local function script_path(name)
    return script_dir .. name
end

dofile(script_path("base.lua"))
dofile(script_path("auth.lua"))
dofile(script_path("stream.lua"))
dofile(script_path("config.lua"))
dofile(script_path("transcode.lua"))
dofile(script_path("splitter.lua"))
dofile(script_path("buffer.lua"))
dofile(script_path("epg.lua"))
dofile(script_path("runtime.lua"))
dofile(script_path("ai_openai_client.lua"))
dofile(script_path("ai_charts.lua"))
dofile(script_path("ai_context.lua"))
dofile(script_path("telegram.lua"))
dofile(script_path("ai_runtime.lua"))
dofile(script_path("ai_tools.lua"))
dofile(script_path("ai_prompt.lua"))
dofile(script_path("ai_telegram.lua"))
dofile(script_path("ai_observability.lua"))
dofile(script_path("watchdog.lua"))
dofile(script_path("preview.lua"))
dofile(script_path("api.lua"))

local opt = {
    addr = "0.0.0.0",
    port = 8000,
    port_set = false,
    data_dir = "./data",
    data_dir_set = false,
    db_path = nil,
    web_dir = "./web",
    web_dir_set = false,
    hls_dir = nil,
    hls_route = "/hls",
    config_path = nil,
    import_mode = "merge",
    reset_pass = false,
}

if auth then
    auth.on_kick = function(entry)
        if not entry or not entry.session_id then
            return
        end
        local list = auth.clients[entry.session_id]
        if not list then
            return
        end
        for _, item in ipairs(list) do
            if item.server and item.client then
                item.server:close(item.client)
            end
        end
        auth.clients[entry.session_id] = nil
    end
end

options_usage = [[
    -a ADDR             listen address (default: 0.0.0.0)
    -p PORT             listen port (default: 8000)
    --data-dir PATH     data directory (default: ./data or <config>.data)
    --db PATH           sqlite db path (default: data-dir/astra.db)
    --web-dir PATH      web ui directory (default: ./web)
    --hls-dir PATH      hls output directory (default: data-dir/hls)
    --hls-route PATH    hls url prefix (default: /hls)
    -c PATH             alias for --config
    -pass               reset admin password to default (admin/admin)
    --config PATH       import config (.json or .lua) before start
    --import PATH       legacy alias for --config (json)
    --import-mode MODE  import mode: merge or replace (default: merge)
]]

options = {
    ["-a"] = function(idx)
        opt.addr = argv[idx + 1]
        return 1
    end,
    ["-p"] = function(idx)
        opt.port = tonumber(argv[idx + 1])
        if not opt.port then
            log.error("[server] wrong port value")
            astra.abort()
        end
        opt.port_set = true
        return 1
    end,
    ["--data-dir"] = function(idx)
        opt.data_dir = argv[idx + 1]
        opt.data_dir_set = true
        return 1
    end,
    ["--db"] = function(idx)
        opt.db_path = argv[idx + 1]
        return 1
    end,
    ["--web-dir"] = function(idx)
        opt.web_dir = argv[idx + 1]
        opt.web_dir_set = true
        return 1
    end,
    ["--hls-dir"] = function(idx)
        opt.hls_dir = argv[idx + 1]
        return 1
    end,
    ["--hls-route"] = function(idx)
        opt.hls_route = argv[idx + 1]
        return 1
    end,
    ["-c"] = function(idx)
        opt.config_path = argv[idx + 1]
        return 1
    end,
    ["-pass"] = function(idx)
        opt.reset_pass = true
        return 0
    end,
    ["-\209\129"] = function(idx)
        opt.config_path = argv[idx + 1]
        return 1
    end,
    ["--config"] = function(idx)
        opt.config_path = argv[idx + 1]
        return 1
    end,
    ["--import"] = function(idx)
        opt.config_path = argv[idx + 1]
        return 1
    end,
    ["--import-mode"] = function(idx)
        opt.import_mode = argv[idx + 1]
        return 1
    end,
}

local function ensure_dir(path)
    local stat = utils.stat(path)
    if stat.type ~= "directory" then
        os.execute("mkdir -p " .. path)
    end
end

local function normalize_route(route)
    if not route or route == "" then
        return "/hls"
    end
    if route:sub(1, 1) ~= "/" then
        route = "/" .. route
    end
    if #route > 1 and route:sub(-1) == "/" then
        route = route:sub(1, -2)
    end
    return route
end

local function format_refresh_errors(errors)
    if type(errors) ~= "table" or #errors == 0 then
        return ""
    end
    local parts = {}
    for _, entry in ipairs(errors) do
        if type(entry) == "table" then
            table.insert(parts, tostring(entry.id or "?") .. ": " .. tostring(entry.error or "error"))
        else
            table.insert(parts, tostring(entry))
        end
    end
    return table.concat(parts, "; ")
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
    if suffix:sub(1, 1) == "/" then
        suffix = suffix:sub(2)
    end
    return base .. "/" .. suffix
end

local function split_path(path)
    if not path or path == "" then
        return ".", ""
    end
    local dir, file = path:match("^(.*)[/\\]([^/\\]+)$")
    if not dir then
        return ".", path
    end
    if dir == "" then
        dir = "."
    end
    return dir, file
end

local function escape_html(value)
    local s = tostring(value or "")
    -- Keep this minimal and dependency-free. Order matters: escape '&' first.
    s = s:gsub("&", "&amp;")
    s = s:gsub("<", "&lt;")
    s = s:gsub(">", "&gt;")
    s = s:gsub("\"", "&quot;")
    s = s:gsub("'", "&#39;")
    return s
end

local function strip_extension(name)
    if not name or name == "" then
        return name
    end
    local base = name:gsub("%.[^%.]+$", "")
    if base == "" then
        return name
    end
    return base
end

local function default_data_dir(config_path)
    local dir, file = split_path(config_path)
    local base = strip_extension(file)
    if not base or base == "" then
        base = "data"
    end
    local root = os.getenv("ASTRA_DATA_ROOT") or os.getenv("ASTRAL_DATA_ROOT")
    if not root or root == "" then
        root = "/etc/astral"
    end
    if not root or root == "" then
        return join_path(dir, base .. ".data")
    end
    return join_path(root, base .. ".data")
end

hls_session_list = hls_session_list or {}
hls_session_index = hls_session_index or {}
hls_session_next_id = hls_session_next_id or 1

local function close_softcam_list(list)
    if type(list) ~= "table" then
        return
    end
    for _, cam in ipairs(list) do
        if type(cam) == "table" then
            local opts = cam.__options or {}
            -- Close pooled split_cam clones (they are not in softcam_list).
            if type(opts.pool_clones) == "table" then
                for _, clone in pairs(opts.pool_clones) do
                    if type(clone) == "table" and clone.close then
                        pcall(function() clone:close() end)
                    end
                end
                opts.pool_clones = nil
            end
            if opts.id then
                _G[tostring(opts.id)] = nil
            end
            if cam.close then
                pcall(function() cam:close() end)
            end
        end
    end
end

local function softcam_is_truthy(value)
    return value == true or value == 1 or value == "1"
end

local function softcam_shallow_copy(entry)
    if type(entry) ~= "table" then
        return {}
    end
    local out = {}
    for k, v in pairs(entry) do
        out[k] = v
    end
    return out
end

local function softcam_entry_label(entry)
    if type(entry) ~= "table" then
        return "softcam"
    end
    if entry.id ~= nil and tostring(entry.id) ~= "" then
        return tostring(entry.id)
    end
    if entry.name ~= nil and tostring(entry.name) ~= "" then
        return tostring(entry.name)
    end
    return tostring(entry.type or "softcam")
end

local function softcam_sanitize_newcamd(entry)
    if type(entry) ~= "table" then
        return false, nil, "invalid entry"
    end

    local name = entry.name
    if name == nil or tostring(name) == "" then
        if entry.id ~= nil and tostring(entry.id) ~= "" then
            name = entry.id
        else
            name = "softcam"
        end
    end

    local host = entry.host
    if host == nil or tostring(host) == "" then
        return false, nil, "host is required"
    end

    local port = tonumber(entry.port or 0) or 0
    port = math.floor(port)
    if port <= 0 then
        return false, nil, "port is required"
    end

    local user = entry.user
    if user == nil or tostring(user) == "" then
        return false, nil, "user is required"
    end

    local pass = entry.pass
    if pass == nil or tostring(pass) == "" then
        return false, nil, "pass is required"
    end

    local cfg = softcam_shallow_copy(entry)
    cfg.name = tostring(name)
    cfg.host = tostring(host)
    cfg.port = port
    cfg.user = tostring(user)
    cfg.pass = tostring(pass)

    if entry.timeout ~= nil then
        local timeout = tonumber(entry.timeout or 0) or 0
        timeout = math.floor(timeout)
        if timeout > 0 then
            cfg.timeout = timeout
        end
    end

    if entry.key ~= nil then
        local key = tostring(entry.key or ""):gsub("%s+", "")
        if key == "" then
            cfg.key = nil
        else
            if key:sub(1, 2):lower() == "0x" then
                key = key:sub(3)
            end
            if not key:match("^[0-9a-fA-F]+$") or #key ~= 28 then
                return false, nil, "key must be 28 hex chars"
            end
            cfg.key = key:lower()
        end
    end

    if entry.caid ~= nil then
        local caid = tostring(entry.caid or ""):gsub("%s+", "")
        if caid == "" then
            cfg.caid = nil
        else
            if caid:sub(1, 2):lower() == "0x" then
                caid = caid:sub(3)
            end
            if not caid:match("^[0-9a-fA-F]+$") or #caid ~= 4 then
                return false, nil, "caid must be 4 hex chars"
            end
            cfg.caid = caid:upper()
        end
    end

    return true, cfg, nil
end

local function softcam_clone(self, tag)
    local opts = type(self) == "table" and self.__options or nil
    local raw = opts and opts.raw_cfg
    if type(raw) ~= "table" then
        return nil, "missing raw_cfg"
    end

    local cfg = softcam_shallow_copy(raw)
    -- Avoid global id collisions. Clones are not addressable by id and live only as stream attachments.
    cfg.id = nil

    local cam_type = cfg.type or (opts and opts.type)
    if not cam_type or cam_type == "" then
        return nil, "missing type"
    end
    cfg.type = cam_type

    -- Prevent accidental recursive splitting if a clone is re-used as a base cam.
    cfg.split_cam = false
    cfg.split_cam_pool_size = 0

    local base_name = cfg.name or (opts and opts.id) or raw.id or "softcam"
    cfg.name = tostring(base_name) .. "@" .. tostring(tag or "clone")

    local ctor = _G[tostring(cam_type)]
    local ctor_type = type(ctor)
    if ctor_type ~= "function" and ctor_type ~= "table" then
        return nil, "unknown type: " .. tostring(cam_type)
    end

    local ok, instance = pcall(ctor, cfg)
    if not ok or not instance then
        return nil, tostring(instance or "failed to init clone")
    end

    instance.__options = instance.__options or {}
    instance.__options.raw_cfg = cfg
    instance.__options.type = cam_type
    instance.__options.split_cam = false
    instance.__options.split_cam_pool_size = 0
    instance.__options.is_clone = true
    instance.clone = softcam_clone
    return instance
end

local function softcam_hash(text)
    -- Deterministic, stable hash without bitops (Lua numbers).
    local s = tostring(text or "")
    local h = 5381
    for i = 1, #s do
        h = (h * 33 + string.byte(s, i)) % 2147483647
    end
    return h
end

local function softcam_get_pool(self, tag)
    local opts = type(self) == "table" and self.__options or nil
    local raw = opts and opts.raw_cfg or nil
    if type(raw) ~= "table" then
        return nil, "missing raw_cfg"
    end

    local size = tonumber(raw.split_cam_pool_size or (opts and opts.split_cam_pool_size) or 0) or 0
    if size <= 1 then
        return nil, "pool disabled"
    end
    -- Safety cap: avoid accidental huge pools on misconfig.
    if size > 64 then
        size = 64
    end

    opts.split_cam_pool_size = size
    opts.pool_clones = opts.pool_clones or {}

    local idx = (softcam_hash(tag or "") % size) + 1
    local existing = opts.pool_clones[idx]
    if type(existing) == "table" and existing.cam then
        return existing
    end

    local clone, err = softcam_clone(self, "pool" .. tostring(idx))
    if not clone then
        return nil, err
    end
    clone.__options = clone.__options or {}
    clone.__options.is_pool_clone = true
    clone.__options.pool_index = idx
    clone.__options.pool_size = size
    opts.pool_clones[idx] = clone
    return clone
end

function apply_softcam_settings()
    local softcam_cfg = config.get_setting("softcam")
    if type(softcam_cfg) ~= "table" then
        close_softcam_list(softcam_list)
        softcam_list = nil
        return
    end

    local new_list = {}
    for _, entry in ipairs(softcam_cfg) do
        if type(entry) == "table" and entry.type then
            local enabled = entry.enable
            if enabled == nil or enabled == true or enabled == 1 or enabled == "1" then
                local cam_type = tostring(entry.type)
                local cfg = entry
                local raw_cfg = entry
                if cam_type == "newcamd" then
                    local ok_cfg, sanitized, cfg_err = softcam_sanitize_newcamd(entry)
                    if not ok_cfg then
                        log.error("[softcam] skip invalid newcamd (" .. softcam_entry_label(entry) .. "): " .. tostring(cfg_err))
                        cfg = nil
                    else
                        cfg = sanitized
                        raw_cfg = sanitized
                    end
                end

                if cfg == nil then
                    -- keep going
                else
                    local ctor = _G[tostring(cfg.type or cam_type)]
                    local ctor_type = type(ctor)
                    if ctor_type ~= "function" and ctor_type ~= "table" then
                        log.error("[softcam] unknown type: " .. tostring(cfg.type or cam_type))
                    else
                        local ok, instance = pcall(ctor, cfg)
                        if ok and instance then
                            table.insert(new_list, instance)
                            local id = (type(cfg) == "table" and cfg.id) or entry.id or (instance.__options and instance.__options.id)
                            if id then
                                instance.__options = instance.__options or {}
                                instance.__options.id = instance.__options.id or id
                                instance.__options.type = cfg.type or cam_type
                                instance.__options.split_cam = softcam_is_truthy(cfg.split_cam)
                                instance.__options.split_cam_pool_size = tonumber(cfg.split_cam_pool_size) or 0
                                instance.__options.raw_cfg = softcam_shallow_copy(raw_cfg)
                                instance.clone = softcam_clone
                                instance.get_pool = softcam_get_pool
                                _G[tostring(id)] = instance
                            end
                        else
                            log.error("[softcam] failed to init: " .. tostring(softcam_entry_label(entry)))
                        end
                    end
                end
            end
        end
    end

    close_softcam_list(softcam_list)
    softcam_list = new_list
end

local function header_value(headers, key)
    if not headers then return nil end
    return headers[key] or headers[string.lower(key)] or headers[string.upper(key)]
end

local function http_auth_reject(server, client, info)
    local headers = {
        "Content-Type: text/plain",
        "Connection: close",
    }
    if info and info.basic then
        local realm = info.realm or "Astra"
        table.insert(headers, 'WWW-Authenticate: Basic realm="' .. realm .. '"')
    end
    server:send(client, {
        code = 401,
        headers = headers,
        content = "unauthorized",
    })
end

local function ensure_http_auth(server, client, request)
    local ok, info = http_auth_check(request)
    if ok then
        return true
    end
    http_auth_reject(server, client, info)
    return false
end

local function auth_reject(server, client)
    server:send(client, {
        code = 403,
        headers = {
            "Content-Type: text/plain",
            "Connection: close",
        },
        content = "forbidden",
    })
end

local function build_request_uri(request)
    if not request then
        return ""
    end
    local path = request.path or ""
    local query = request.query or {}
    local parts = {}
    for key, value in pairs(query) do
        table.insert(parts, tostring(key) .. "=" .. tostring(value))
    end
    table.sort(parts)
    local uri = path
    if #parts > 0 then
        uri = uri .. "?" .. table.concat(parts, "&")
    end
    local host = header_value(request.headers or {}, "host")
    if host and host ~= "" then
        uri = "http://" .. host .. uri
    end
    return uri
end

local function ensure_token_auth(server, client, request, ctx, on_allow)
    if not auth or not auth.check_play then
        on_allow(nil)
        return true
    end
    ctx = ctx or {}
    ctx.request = request
    ctx.ip = request and request.addr or ""
    if ctx.token == nil and auth.get_token then
        ctx.token = auth.get_token(request)
    end
    local headers = request and request.headers or {}
    ctx.user_agent = ctx.user_agent or header_value(headers, "user-agent") or ""
    ctx.referer = ctx.referer or header_value(headers, "referer") or ""
    ctx.uri = ctx.uri or build_request_uri(request)
    auth.check_play(ctx, function(allowed, entry)
        if not allowed then
            auth_reject(server, client)
            return
        end
        on_allow(entry)
    end)
    return true
end

local function track_hls_session(request, route_prefix)
    if not request or not request.path then
        return
    end

    local prefix = route_prefix .. "/"
    if request.path:sub(1, #prefix) ~= prefix then
        return
    end

    local rest = request.path:sub(#prefix + 1)
    local stream_id = rest:match("^([^/]+)/")
    if not stream_id then
        return
    end
    -- Ladder HLS uses composite ids like "<stream_id>~<profile_id>" for variants.
    -- For access/session tracking we want the base stream id.
    do
        local base = stream_id:match("^(.+)~[A-Za-z0-9_-]+$")
        if base and base ~= "" then
            stream_id = base
        end
    end

    local headers = request.headers or {}
    local user_agent = header_value(headers, "user-agent") or ""
    local host = header_value(headers, "host") or ""
    local login = ""
    if request.query then
        login = request.query.user or request.query.login or ""
    end

    local key = tostring(request.addr or "") .. "|" .. stream_id .. "|" .. user_agent
    local now = os.time()
    local id = hls_session_index[key]
    local entry = id and hls_session_list[id]

    if not entry then
        id = "hls-" .. tostring(hls_session_next_id)
        hls_session_next_id = hls_session_next_id + 1
        entry = {
            id = id,
            key = key,
            stream_id = stream_id,
            stream_name = stream_id,
            ip = request.addr,
            server = host,
            user_agent = user_agent,
            login = login,
            started_at = now,
        }
        hls_session_list[id] = entry
        hls_session_index[key] = id
        if access_log and type(access_log.add) == "function" then
            local stream_name = stream_id
            if runtime and runtime.streams and runtime.streams[stream_id]
                and runtime.streams[stream_id].channel
                and runtime.streams[stream_id].channel.config
                and runtime.streams[stream_id].channel.config.name then
                stream_name = runtime.streams[stream_id].channel.config.name
            end
            access_log.add({
                event = "connect",
                protocol = "hls",
                stream_id = stream_id,
                stream_name = stream_name,
                ip = request.addr,
                login = login,
                user_agent = user_agent,
                path = request.path or "",
            })
        end
    end

    entry.last_seen = now
    entry.server = host ~= "" and host or entry.server
    entry.user_agent = user_agent ~= "" and user_agent or entry.user_agent
    entry.ip = request.addr or entry.ip
    entry.login = login or entry.login
end

local function setting_number(key, fallback)
    local value = config.get_setting(key)
    local number = tonumber(value)
    if number == nil then
        return fallback
    end
    return number
end

local function setting_bool(key, fallback)
    local value = config.get_setting(key)
    if value == nil then
        return fallback
    end
    if value == true or value == 1 or value == "1" then
        return true
    end
    return false
end

local function setting_string(key, fallback)
    local value = config.get_setting(key)
    if value == nil or value == "" then
        return fallback
    end
    return tostring(value)
end

local function apply_log_settings()
    if log_store and type(log_store.configure) == "function" then
        log_store.configure({
            max_entries = config.get_setting("log_max_entries"),
            retention_sec = config.get_setting("log_retention_sec"),
        })
    end
    if access_log and type(access_log.configure) == "function" then
        access_log.configure({
            max_entries = config.get_setting("access_log_max_entries"),
            retention_sec = config.get_setting("access_log_retention_sec"),
        })
    end

    -- Runtime logs (stdout/file/syslog) are configured via settings to avoid editing systemd units.
    -- If keys are not set, keep CLI defaults untouched.
    if _G.runtime_log_baseline == nil and log and type(log.get) == "function" then
        local ok, snap = pcall(log.get)
        if ok and type(snap) == "table" then
            _G.runtime_log_baseline = snap
        end
    end
    local baseline = _G.runtime_log_baseline
    local dest_raw = config.get_setting("runtime_log_dest")
    local level_raw = config.get_setting("runtime_log_level")
    local file_raw = config.get_setting("runtime_log_file")
    local syslog_raw = config.get_setting("runtime_log_syslog")
    local color_raw = config.get_setting("runtime_log_color")
    local rotate_mb_raw = config.get_setting("runtime_log_rotate_mb")
    local rotate_keep_raw = config.get_setting("runtime_log_rotate_keep")

    if dest_raw ~= nil or level_raw ~= nil or file_raw ~= nil or syslog_raw ~= nil
        or color_raw ~= nil or rotate_mb_raw ~= nil or rotate_keep_raw ~= nil
    then
        local dest_mode = nil
        if dest_raw ~= nil then
            dest_mode = tostring(dest_raw or ""):lower()
        end
        local opts = {}

        if dest_mode == "inherit" then
            if type(baseline) == "table" then
                opts.stdout = baseline.stdout == true
                opts.filename = tostring(baseline.filename or "")
                opts.syslog = tostring(baseline.syslog or "")
                opts.color = baseline.color == true
                opts.level = tostring(baseline.level or "")
                opts.rotate_max_bytes = tonumber(baseline.rotate_max_bytes) or 0
                opts.rotate_keep = tonumber(baseline.rotate_keep) or 0
            else
                -- Safe fallback if baseline isn't available.
                opts.stdout = true
                opts.filename = ""
                opts.syslog = ""
                opts.color = false
                opts.level = "info"
                opts.rotate_max_bytes = 0
                opts.rotate_keep = 0
            end
        elseif dest_mode ~= nil and dest_mode ~= "inherit" then
            local want_stdout = true
            local want_file = false
            local want_syslog = false
            if dest_mode == "none" then
                want_stdout = false
            elseif dest_mode == "file" then
                want_stdout = false
                want_file = true
            elseif dest_mode == "stdout_file" then
                want_file = true
            elseif dest_mode == "syslog" then
                want_stdout = false
                want_syslog = true
            elseif dest_mode == "stdout_syslog" then
                want_syslog = true
            elseif dest_mode == "file_syslog" then
                want_stdout = false
                want_file = true
                want_syslog = true
            elseif dest_mode == "all" then
                want_file = true
                want_syslog = true
            else
                -- Unknown value -> fallback to stdout.
                want_stdout = true
            end

            opts.stdout = want_stdout == true
            opts.filename = want_file and tostring(file_raw or "") or ""
            opts.syslog = want_syslog and tostring(syslog_raw or "") or ""
        elseif dest_mode == nil then
            -- Backward/partial updates: allow setting file/syslog without touching stdout.
            if file_raw ~= nil then
                opts.filename = tostring(file_raw or "")
            end
            if syslog_raw ~= nil then
                opts.syslog = tostring(syslog_raw or "")
            end
        end

        if level_raw ~= nil then
            local level = tostring(level_raw or ""):lower()
            if level ~= "" and level ~= "inherit" then
                opts.level = level
            end
        end
        if color_raw ~= nil and dest_mode ~= "inherit" then
            opts.color = setting_bool("runtime_log_color", false)
        end
        if rotate_mb_raw ~= nil and dest_mode ~= "inherit" then
            local mb = tonumber(rotate_mb_raw) or 0
            if mb < 0 then mb = 0 end
            opts.rotate_max_bytes = math.floor(mb) * 1024 * 1024
        end
        if rotate_keep_raw ~= nil and dest_mode ~= "inherit" then
            local keep = tonumber(rotate_keep_raw) or 0
            if keep < 0 then keep = 0 end
            opts.rotate_keep = math.floor(keep)
        end

        if next(opts) ~= nil then
            log.set(opts)
        end
    end
end

local function escape_m3u_value(value)
    local text = tostring(value or "")
    return text:gsub('"', '\\"')
end

local function escape_xml(value)
    local text = tostring(value or "")
    text = text:gsub("&", "&amp;")
    text = text:gsub("<", "&lt;")
    text = text:gsub(">", "&gt;")
    text = text:gsub("\"", "&quot;")
    text = text:gsub("'", "&apos;")
    return text
end

local function request_base_url(request, opts)
    if not request or not request.headers then
        return ""
    end
    local proto = header_value(request.headers, "x-forwarded-proto") or "http"
    if opts and opts.force_http then
        proto = "http"
    end
    local host = header_value(request.headers, "x-forwarded-host")
    if not host or host == "" then
        host = header_value(request.headers, "host") or ""
    end
    if host == "" then
        return ""
    end
    return proto .. "://" .. host
end

local function resolve_asset_url(base, asset, fallback)
    if asset and asset ~= "" then
        if asset:find("://") then
            return asset
        end
        if base and base ~= "" then
            return join_path(base, asset)
        end
        return asset
    end
    if fallback and base and base ~= "" then
        return join_path(base, fallback)
    end
    return ""
end

local function collect_playlist_streams()
    local entries = {}
    for id, item in pairs(runtime.streams) do
        local cfg = item.channel and item.channel.config or {}
        table.insert(entries, { id = id, config = cfg })
    end
    table.sort(entries, function(a, b)
        return tostring(a.id) < tostring(b.id)
    end)
    return entries
end

local function http_play_stream_id(path)
    if not path then
        return nil
    end
    -- Some http_server builds include the query string in request.path. Be tolerant:
    -- route/id parsing must only see the path portion.
    path = path:match("^([^?]+)") or path
    local prefix = nil
    if path:sub(1, 8) == "/stream/" then
        prefix = "/stream/"
    elseif path:sub(1, 6) == "/play/" then
        prefix = "/play/"
    elseif path:sub(1, 7) == "/input/" then
        prefix = "/input/"
    else
        return nil
    end
    local rest = path:sub(#prefix + 1)
    if rest == "" then
        return nil
    end
    rest = rest:gsub("%.ts$", "")
    return rest
end

local function http_live_stream_ids(path)
    if not path then
        return nil
    end
    path = path:match("^([^?]+)") or path
    if path:sub(1, 6) ~= "/live/" then
        return nil
    end
    local rest = path:sub(7)
    if rest == "" then
        return nil
    end
    rest = rest:gsub("%.ts$", "")

    -- Prefer explicit delimiter (unambiguous): "<stream_id>~<profile_id>"
    local base, profile = rest:match("^(.+)~([A-Za-z0-9_-]+)$")
    if not base then
        -- Fallback: split by the last "_" (profile ids with "_" should use "~" form).
        base, profile = rest:match("^(.+)_([^_]+)$")
    end
    if not base or base == "" or not profile or profile == "" then
        return nil
    end
    return base, profile
end

local web_static_handler = nil

local function http_favicon(server, client, request)
    if not request or request.method ~= "GET" then
        return server:abort(client, 405)
    end
    if web_static_handler then
        local orig = request.path
        request.path = "/favicon.ico"
        local result = web_static_handler(server, client, request)
        request.path = orig
        return result
    end
    server:send(client, { code = 204, headers = { "Content-Length: 0" } })
end

function main()
    log.info("Starting " .. astra_brand_version())
    math.randomseed(os.time())

    if opt.config_path and opt.config_path ~= "" then
        if not opt.data_dir_set then
            opt.data_dir = default_data_dir(opt.config_path)
        end
        if not opt.web_dir_set then
            local env_web_dir = os.getenv("ASTRA_WEB_DIR") or os.getenv("ASTRAL_WEB_DIR")
            if env_web_dir and env_web_dir ~= "" then
                opt.web_dir = env_web_dir
            else
                local cfg_dir = split_path(opt.config_path)
                local candidate = join_path(cfg_dir, "web")
                local stat = utils.stat(candidate)
                if stat and not stat.error and stat.type == "directory" then
                    opt.web_dir = candidate
                else
                    local base = script_dir:gsub("[/\\]scripts[/\\]?$", "")
                    local root_candidate = join_path(base, "web")
                    local root_stat = utils.stat(root_candidate)
                    if root_stat and not root_stat.error and root_stat.type == "directory" then
                        opt.web_dir = root_candidate
                    end
                end
            end
        end
    end

    config.init({ data_dir = opt.data_dir, db_path = opt.db_path })
    if opt.config_path and opt.config_path ~= "" and config.set_primary_config_path then
        config.set_primary_config_path(opt.config_path)
    end
    if config.read_boot_state and config.lkg_snapshot_path and config.restore_snapshot then
        local boot_state = config.read_boot_state()
        if boot_state and boot_state.status ~= "ok" then
            local lkg_path = config.lkg_snapshot_path()
            if lkg_path then
                local summary, err = config.restore_snapshot(lkg_path)
                if summary then
                    log.warning("[server] auto rollback to LKG after failed boot")
                else
                    log.warning("[server] auto rollback failed: " .. tostring(err))
                end
            end
        end
    end
    if config.mark_boot_start then
        config.mark_boot_start(config.get_setting("config_lkg_revision_id"))
    end
    if opt.config_path and opt.config_path ~= "" then
        local ok, created = config.ensure_config_file(opt.config_path)
        if not ok then
            log.error("[server] import failed: " .. tostring(created))
            astra.abort()
        end
        if created then
            log.warning("[server] config file missing, created defaults: " .. tostring(opt.config_path))
        end
        local summary, err = config.import_astra_file(opt.config_path, { mode = opt.import_mode })
        if not summary then
            log.error("[server] import failed: " .. tostring(err))
            astra.abort()
        else
            log.info(string.format(
                "[server] import ok: settings=%d users=%d adapters=%d streams=%d softcam=%d splitters=%d splitter_links=%d splitter_allow=%d",
                summary.settings or 0,
                summary.users or 0,
                summary.adapters or 0,
                summary.streams or 0,
                summary.softcam or 0,
                summary.splitters or 0,
                summary.splitter_links or 0,
                summary.splitter_allow or 0
            ))
        end
    end

    if opt.reset_pass then
        local setter = config.set_user_password_force or config.set_user_password
        local ok, err = setter("admin", "admin")
        if not ok and err == "user not found" then
            config.ensure_admin()
            ok, err = setter("admin", "admin")
        end
        config.update_user("admin", { enabled = true, is_admin = true })
        local admin = config.get_user_by_username("admin")
        if admin and config.delete_sessions_for_user then
            config.delete_sessions_for_user(admin.id)
        end
        if ok then
            log.warning("[server] admin password reset to default (admin/admin)")
        else
            log.error("[server] admin password reset failed: " .. tostring(err))
        end
    end

    local edition = os.getenv("ASTRA_EDITION") or os.getenv("ASTRAL_EDITION")
    local tool_info = nil
    if transcode and transcode.get_tool_info then
        tool_info = transcode.get_tool_info(true)
    end
    if not edition or edition == "" then
        edition = "default"
    end
    local ffmpeg_path = tool_info and tool_info.ffmpeg_path_resolved or "ffmpeg"
    local ffmpeg_source = tool_info and tool_info.ffmpeg_source or "path"
    local ffmpeg_version = tool_info and tool_info.ffmpeg_version or "unknown"
    local ffprobe_path = tool_info and tool_info.ffprobe_path_resolved or "ffprobe"
    local ffprobe_source = tool_info and tool_info.ffprobe_source or "path"
    local ffprobe_version = tool_info and tool_info.ffprobe_version or "unknown"
    local ssl_flag = (astra and astra.features and astra.features.ssl) and "on" or "off"
    log.info(string.format(
        "[startup] edition=%s ssl=%s tools: ffmpeg=%s (%s, %s) ffprobe=%s (%s, %s)",
        tostring(edition),
        tostring(ssl_flag),
        tostring(ffmpeg_path),
        tostring(ffmpeg_source),
        tostring(ffmpeg_version),
        tostring(ffprobe_path),
        tostring(ffprobe_source),
        tostring(ffprobe_version)
    ))

    apply_log_settings()
    if runtime and runtime.configure_influx then
        runtime.configure_influx()
    end
    if telegram and telegram.configure then
        telegram.configure()
    end
    if ai_runtime and ai_runtime.configure then
        ai_runtime.configure()
    end
    if ai_observability and ai_observability.configure then
        ai_observability.configure()
    end
    if watchdog and watchdog.configure then
        watchdog.configure()
    end

    if not opt.port_set then
        local stored_port = config.get_setting("http_port")
        if stored_port then
            opt.port = tonumber(stored_port) or opt.port
        end
    end

    -- If global HLS storage is memfd, avoid creating/touching the disk HLS directory unless
    -- at least one stream explicitly uses disk storage.
    local function needs_hls_disk_dir(storage_mode)
        if storage_mode ~= "memfd" then
            return true
        end
        if not config or type(config.list_streams) ~= "function" then
            return false
        end
        local rows = config.list_streams() or {}
        for _, row in ipairs(rows) do
            local cfg = row and row.config or {}
            local outputs = cfg and cfg.output or nil
            if type(outputs) == "table" then
                for _, out in pairs(outputs) do
                    if type(out) == "table" and out.format == "hls" then
                        local s = out.storage
                        if s ~= nil and tostring(s) == "disk" then
                            return true
                        end
                    end
                end
            end
        end
        return false
    end

    local hls_storage = setting_string("hls_storage", "disk")
    local stored_hls_dir = config.get_setting("hls_dir")
    local hls_dir = opt.hls_dir or stored_hls_dir or (opt.data_dir .. "/hls")
    local hls_needs_disk = needs_hls_disk_dir(hls_storage)
    if hls_needs_disk then
        ensure_dir(hls_dir)
    end

    local stored_hls_base = config.get_setting("hls_base_url")
    if stored_hls_base and stored_hls_base ~= "" then
        opt.hls_route = stored_hls_base
    end
    opt.hls_route = normalize_route(opt.hls_route)

    local web_stat = utils.stat(opt.web_dir)
    if web_stat.type ~= "directory" then
        log.error("[server] web directory not found: " .. opt.web_dir)
        astra.abort()
    end

    config.set_setting("hls_dir", hls_dir)
    config.set_setting("hls_base_url", opt.hls_route)
    config.set_setting("http_port", opt.port)

    apply_softcam_settings()

    -- Transcode/audio-fix may use /play as a local HTTP input. During boot we must avoid
    -- starting ffmpeg before the HTTP server starts listening, otherwise ffmpeg may hang
    -- or fail to connect and never recover.
    if transcode then
        transcode.defer_start = true
    end

    if runtime.refresh_adapters then
        runtime.refresh_adapters()
    end
    local ok, errors = runtime.refresh()
    local boot_ok = ok
    local boot_error = ok and "" or format_refresh_errors(errors)
    if not ok then
        log.error("[server] refresh failed: " .. boot_error)
        if config.restore_snapshot and config.lkg_snapshot_path then
            local lkg_path = config.lkg_snapshot_path()
            if lkg_path then
                local summary, err = config.restore_snapshot(lkg_path)
                if summary then
                    log.warning("[server] rollback applied, retrying refresh")
                    if runtime.refresh_adapters then
                        runtime.refresh_adapters(true)
                    end
                    local ok2, errors2 = runtime.refresh(true)
                    if not ok2 then
                        boot_ok = false
                        boot_error = format_refresh_errors(errors2)
                        log.error("[server] refresh failed after rollback: " .. boot_error)
                    else
                        boot_ok = true
                        boot_error = ""
                    end
                else
                    boot_ok = false
                    boot_error = tostring(err or "rollback failed")
                    log.error("[server] rollback failed: " .. boot_error)
                end
            end
        end
    end
    if splitter and splitter.refresh then
        splitter.refresh()
    end
    if epg and epg.export_all then
        epg.export_all("boot")
    end
    if epg and epg.configure_timer then
        epg.configure_timer()
    end

    local hls_duration = setting_number("hls_duration", 6)
    local hls_quantity = setting_number("hls_quantity", 5)
    local hls_use_expires = setting_bool("hls_use_expires", false)
    local hls_m3u_headers = setting_bool("hls_m3u_headers", true)
    local hls_ts_headers = setting_bool("hls_ts_headers", true)
    local hls_ts_extension = setting_string("hls_ts_extension", "ts")
    if hls_ts_extension:sub(1, 1) == "." then
        hls_ts_extension = hls_ts_extension:sub(2)
    end
    if hls_ts_extension == "" then
        hls_ts_extension = "ts"
    end
    local hls_ts_mime = setting_string("hls_ts_mime", "video/MP2T")
    local hls_on_demand = setting_bool("hls_on_demand", hls_storage == "memfd")
    local hls_idle_timeout_sec = setting_number("hls_idle_timeout_sec", 30)

    local hls_max_age = math.max(1, math.floor(hls_duration * hls_quantity))
    local hls_expires = hls_use_expires and hls_max_age or 0

    local m3u_headers = nil
    if hls_m3u_headers then
        m3u_headers = {
            -- HLS playlists should not be cached by proxies/browsers.
            "Cache-Control: no-cache, no-store, must-revalidate",
            "Pragma: no-cache",
            "Expires: 0",
        }
    end

    local ts_headers = nil
    if hls_ts_headers then
        ts_headers = { "Cache-Control: public, max-age=" .. tostring(hls_max_age) }
    end

    mime = {
        html = "text/html; charset=utf-8",
        css = "text/css",
        js = "application/javascript",
        json = "application/json",
        svg = "image/svg+xml",
        png = "image/png",
        jpg = "image/jpeg",
        jpeg = "image/jpeg",
        gif = "image/gif",
        ico = "image/x-icon",
        woff = "font/woff",
        woff2 = "font/woff2",
        ttf = "font/ttf",
        m3u8 = "application/vnd.apple.mpegurl",
        mpd = "application/dash+xml",
        m4s = "video/iso.segment",
        mp4 = "video/mp4",
    }
	    mime[hls_ts_extension] = hls_ts_mime
	    if hls_ts_extension ~= "ts" then
	        mime.ts = hls_ts_mime
	    end
	
	    local dash_route = normalize_route(setting_string("dash_route", "/dash"))
	    local dash_dir = setting_string("dash_dir", opt.data_dir .. "/dash")
	    ensure_dir(dash_dir)
	
	    local embed_route = normalize_route(setting_string("embed_route", "/embed"))

    local hls_static = nil
    if hls_needs_disk then
        hls_static = http_static({
            path = hls_dir,
            skip = opt.hls_route,
            expires = hls_expires,
            m3u_headers = m3u_headers,
            ts_headers = ts_headers,
            ts_extension = hls_ts_extension,
        })
    end
    local hls_memfd_handler = nil
    if hls_memfd then
        hls_memfd_handler = hls_memfd({
            skip = opt.hls_route,
            m3u_headers = m3u_headers,
            ts_headers = ts_headers,
            ts_mime = hls_ts_mime,
        })
    end

    local dash_static = http_static({
        path = dash_dir,
        skip = dash_route,
        headers = {
            "Cache-Control: no-store",
            "Pragma: no-cache",
        },
    })
    -- Preview HLS (memfd): отдельный handler с no-store заголовками.
    local preview_memfd_handler = nil
    if hls_memfd then
        preview_memfd_handler = hls_memfd({
            skip = "/preview",
            m3u_headers = {
                "Cache-Control: no-store",
                "Pragma: no-cache",
            },
            ts_headers = {
                "Cache-Control: no-store",
                "Pragma: no-cache",
            },
            ts_mime = hls_ts_mime,
        })
    end
    local web_static = http_static({
        path = opt.web_dir,
        headers = { "Cache-Control: no-cache" },
    })
    web_static_handler = web_static
    local hls_memfd_timer = nil
    -- Всегда запускаем sweep, если доступен memfd handler:
    -- - on-demand потоки используют sweep для idle-деактивации;
    -- - если global hls_storage=disk, но отдельные потоки override'ят output.storage=memfd,
    --   sweep все равно нужен.
    if hls_memfd_handler then
        local sweep_interval = 5
        if hls_idle_timeout_sec > 0 then
            sweep_interval = math.max(2, math.min(5, hls_idle_timeout_sec))
        end
        hls_memfd_timer = timer({
            interval = sweep_interval,
            callback = function(self)
                if hls_memfd_handler and hls_memfd_handler.sweep then
                    hls_memfd_handler:sweep(hls_idle_timeout_sec)
                else
                    self:close()
                end
            end,
        })
    end
    local function web_index(server, client, request)
        if not request then
            return web_static(server, client, request)
        end
        local path = request.path or ""
        if path == "/" or path == "" then
            request.path = "/index.html"
            local result = web_static(server, client, request)
            request.path = path
            return result
        end
        return web_static(server, client, request)
    end

    local http_play_allow = setting_bool("http_play_allow", false)
    local http_play_hls = setting_bool("http_play_hls", false)
    local http_play_port = setting_number("http_play_port", opt.port)
    local http_play_logos = setting_string("http_play_logos", "")
    local http_play_screens = setting_string("http_play_screens", "")
    local http_play_playlist_name = setting_string("http_play_playlist_name", "playlist.m3u8")
    local http_play_arrange = setting_string("http_play_arrange", "tv")
    local http_play_buffer_kb = setting_number("http_play_buffer_kb", 4000)
    -- Smaller fill reduces "bursty" /play delivery and prevents long idle gaps that can cause
    -- downstream HTTP clients (ffmpeg/Astra http input) to time out.
    local http_play_buffer_fill_kb = setting_number("http_play_buffer_fill_kb", 32)
    local http_play_buffer_cap_kb = setting_number("http_play_buffer_cap_kb", 512)
    -- Buffer defaults for internal /input loopback (ffmpeg/transcode).
    -- Keep it small to reduce bursty delivery and avoid timeouts in HTTP consumers.
    local transcode_loopback_buf_kb = setting_number("transcode_loopback_buf_kb", 512)
    local transcode_loopback_buf_fill_kb = setting_number("transcode_loopback_buf_fill_kb", 16)
    local transcode_loopback_buf_cap_kb = setting_number("transcode_loopback_buf_cap_kb", 512)
    local http_play_m3u_header = setting_string("http_play_m3u_header", "")
    local http_play_xspf_title = setting_string("http_play_xspf_title", "Playlist")
    local http_play_no_tls = setting_bool("http_play_no_tls", false)
    local http_play_enabled = http_play_allow or http_play_hls

    if buffer and buffer.refresh then
        buffer.refresh({
            main_port = opt.port,
            http_play_port = http_play_port,
            addr = opt.addr,
        })
    end

    if boot_ok then
        if config.mark_boot_ok then
            config.mark_boot_ok(config.get_setting("config_lkg_revision_id"))
        end
    elseif config.mark_boot_failed then
        config.mark_boot_failed(boot_error, config.get_setting("config_lkg_revision_id"))
    end

    if http_play_playlist_name:sub(1, 1) ~= "/" then
        http_play_playlist_name = "/" .. http_play_playlist_name
    end
    local xspf_path = http_play_playlist_name:gsub("%.[^/%.]+$", "")
    if xspf_path == http_play_playlist_name then
        xspf_path = http_play_playlist_name .. ".xspf"
    else
        xspf_path = xspf_path .. ".xspf"
    end

    local function find_hls_output(cfg)
        local outputs = cfg.output or {}
        for _, out in ipairs(outputs) do
            if out.format == "hls" then
                return out
            end
        end
        return nil
    end

    local function build_stream_url(request, entry, mode, token)
        local base = request_base_url(request, { force_http = http_play_no_tls })
        local path = ""
        if mode == "hls" then
            local out = find_hls_output(entry.config or {})
            local playlist = (out and out.playlist) or "index.m3u8"
            path = join_path(opt.hls_route, entry.id .. "/" .. playlist)
        else
            path = "/stream/" .. entry.id
        end
        local url = ""
        if base ~= "" then
            url = base .. path
        end
        if url == "" then
            url = path
        end
        if token and token ~= "" and auth and auth.attach_token_to_url then
            url = auth.attach_token_to_url(url, token)
        end
        return url
    end

    local function build_m3u_playlist(request, token)
        local mode = http_play_hls and "hls" or "http"
        local lines = {}
        local header = "#EXTM3U"
        if http_play_m3u_header ~= "" then
            header = header .. " " .. http_play_m3u_header
        end
        table.insert(lines, header)

        local group_map = nil
        local function resolve_group_label(value)
            if value == nil or value == "" then
                return ""
            end
            if group_map == nil then
                group_map = {}
                local stored = config and config.get_setting and config.get_setting("groups") or nil
                if type(stored) == "table" then
                    for _, item in ipairs(stored) do
                        if type(item) == "table" then
                            local id = item.id or item.name
                            local name = item.name or item.id
                            if id and name then
                                group_map[tostring(id)] = tostring(name)
                            end
                        elseif type(item) == "string" then
                            group_map[item] = item
                        end
                    end
                end
            end
            return group_map[value] or value
        end

        for _, entry in ipairs(collect_playlist_streams()) do
            local cfg = entry.config or {}
            local name = cfg.name or entry.id
            local group = cfg.category or cfg.group or http_play_arrange or ""
            if group ~= "" then
                group = resolve_group_label(group)
            end
            local logo = resolve_asset_url(http_play_logos, cfg.logo or cfg.logo_url or cfg.icon, entry.id .. ".png")
            local screen = resolve_asset_url(http_play_screens, cfg.screenshot or cfg.screen, entry.id .. ".jpg")
            local attrs = {
                'tvg-id="' .. escape_m3u_value(entry.id) .. '"',
                'tvg-name="' .. escape_m3u_value(name) .. '"',
            }
            if group ~= "" then
                table.insert(attrs, 'group-title="' .. escape_m3u_value(group) .. '"')
            end
            if logo ~= "" then
                table.insert(attrs, 'tvg-logo="' .. escape_m3u_value(logo) .. '"')
            end
            if screen ~= "" then
                table.insert(attrs, 'tvg-screenshot="' .. escape_m3u_value(screen) .. '"')
            end
            local extinf = "#EXTINF:-1 " .. table.concat(attrs, " ") .. "," .. name
            table.insert(lines, extinf)
            table.insert(lines, build_stream_url(request, entry, mode, token))
        end

        return table.concat(lines, "\n") .. "\n"
    end

    local function build_xspf_playlist(request, token)
        local mode = http_play_hls and "hls" or "http"
        local lines = {
            "<?xml version=\"1.0\" encoding=\"UTF-8\"?>",
            "<playlist version=\"1\" xmlns=\"http://xspf.org/ns/0/\">",
            "<title>" .. escape_xml(http_play_xspf_title) .. "</title>",
            "<trackList>",
        }

        for _, entry in ipairs(collect_playlist_streams()) do
            local cfg = entry.config or {}
            local name = cfg.name or entry.id
            local logo = resolve_asset_url(http_play_logos, cfg.logo or cfg.logo_url or cfg.icon, entry.id .. ".png")
            table.insert(lines, "<track>")
            table.insert(lines, "<title>" .. escape_xml(name) .. "</title>")
            table.insert(lines, "<location>" .. escape_xml(build_stream_url(request, entry, mode, token)) .. "</location>")
            if logo ~= "" then
                table.insert(lines, "<image>" .. escape_xml(logo) .. "</image>")
            end
            table.insert(lines, "</track>")
        end

        table.insert(lines, "</trackList>")
        table.insert(lines, "</playlist>")
        return table.concat(lines, "\n")
    end

    local function http_play_playlist(server, client, request)
        if not request then
            return nil
        end
        if not ensure_http_auth(server, client, request) then
            return nil
        end
        local token = auth and auth.get_token and auth.get_token(request) or nil
        ensure_token_auth(server, client, request, {
            stream_id = "playlist",
            stream_name = "playlist",
            stream_cfg = nil,
            proto = http_play_hls and "hls_playlist" or "http_playlist",
            token = token,
        }, function()
            server:send(client, {
                code = 200,
                headers = {
                    "Content-Type: application/x-mpegURL",
                    "Connection: close",
                },
                content = build_m3u_playlist(request, token),
            })
        end)
    end

    local function http_play_xspf(server, client, request)
        if not request then
            return nil
        end
        if not ensure_http_auth(server, client, request) then
            return nil
        end
        local token = auth and auth.get_token and auth.get_token(request) or nil
        ensure_token_auth(server, client, request, {
            stream_id = "playlist",
            stream_name = "playlist",
            stream_cfg = nil,
            proto = "http_xspf",
            token = token,
        }, function()
            server:send(client, {
                code = 200,
                headers = {
                    "Content-Type: application/xspf+xml; charset=utf-8",
                    "Connection: close",
                },
                content = build_xspf_playlist(request, token),
            })
        end)
    end

	    local function http_play_stream(server, client, request)
	        local client_data = server:data(client)

	        if not request then
            if client_data.output_data and client_data.output_data.channel_data then
                local channel_data = client_data.output_data.channel_data
                channel_data.clients = channel_data.clients - 1
                if channel_data.keep_timer then
                    channel_data.keep_timer:close()
                    channel_data.keep_timer = nil
                end
                if channel_data.clients == 0 and channel_data.input[1].input ~= nil then
                    local keep_active = tonumber(channel_data.config.http_keep_active or 0) or 0
                    if keep_active == 0 then
                        for input_id, input_data in ipairs(channel_data.input) do
                            if input_data.input then
                                channel_kill_input(channel_data, input_id)
                            end
                        end
                        channel_data.active_input_id = 0
                    elseif keep_active > 0 then
                        channel_data.keep_timer = timer({
                            interval = keep_active,
                            callback = function(self)
                                self:close()
                                channel_data.keep_timer = nil
                                if channel_data.clients == 0 then
                                    for input_id, input_data in ipairs(channel_data.input) do
                                        if input_data.input then
                                            channel_kill_input(channel_data, input_id)
                                        end
                                    end
                                    channel_data.active_input_id = 0
                                end
                            end,
                        })
                    end
                end
            end

            http_output_client(server, client, nil)
            if client_data.auth_session_id and auth and auth.unregister_client then
                auth.unregister_client(client_data.auth_session_id, server, client)
                client_data.auth_session_id = nil
            end
            client_data.output_data = nil
            return nil
        end

	        -- В режиме http_upstream успешный ответ должен быть одним server:send() с upstream.
	        -- Для отказов используем server:abort(), иначе upstream-модуль вернёт 500.
	        local function is_internal_play_request(req)
	            if not req or not req.query then
	                return false
	            end
	            local flag = req.query.internal or req.query._internal
	            if flag == nil then
	                return false
	            end
	            local text = tostring(flag):lower()
	            if not (text == "1" or text == "true" or text == "yes" or text == "on") then
	                return false
	            end
	            local ip = tostring(req.addr or "")
	            local lower = ip:lower()
	            if ip == "127.0.0.1" or ip == "::1" or ip:match("^127%.") or lower:match("^::ffff:127%.") then
	                local headers = req.headers or {}
	                if headers["x-forwarded-for"] or headers["X-Forwarded-For"]
	                    or headers["forwarded"] or headers["Forwarded"]
	                    or headers["x-real-ip"] or headers["X-Real-IP"] then
	                    return false
	                end
	                return true
	            end
	            return false
	        end

		        local internal = is_internal_play_request(request)
		        -- When http_play_allow is disabled we still allow internal loopback consumers
		        -- to read /play (stream refs) and /input (raw loop channels), but hide /play from external clients.
		        if not http_play_allow and not internal then
		            server:abort(client, 404)
		            return nil
		        end

	        if not http_auth_check(request) then
	            server:abort(client, 401)
	            return nil
	        end

        local raw_stream_id = http_play_stream_id(request.path)
        if not raw_stream_id then
            server:abort(client, 404)
            return nil
        end

        local stream_id = raw_stream_id
        local loop_input_id = nil
        local base, idx = raw_stream_id:match("^(.+)~([0-9]+)$")
        if base and idx then
            stream_id = base
            loop_input_id = tonumber(idx)
        end

        local entry = runtime.streams[stream_id]
        if not entry then
            server:abort(client, 404)
            return nil
        end
        local channel = entry.channel
        local transcode_upstream = nil
        if not channel and entry.job then
            local job = entry.job
            if job.ladder_enabled == true then
                local first = job.profiles and job.profiles[1] or nil
                local pid = first and first.id or nil
                local bus = pid and job.profile_buses and job.profile_buses[pid] or nil
                if bus and bus.switch then
                    transcode_upstream = bus.switch:stream()
                else
                    server:send(client, {
                        code = 503,
                        headers = {
                            "Content-Type: text/plain",
                            "Cache-Control: no-store",
                            "Pragma: no-cache",
                            "Retry-After: 1",
                            "Connection: close",
                        },
                        content = "transcode ladder output not ready",
                    })
                    return nil
                end
            elseif job.process_per_output == true then
                local worker = job.workers and job.workers[1] or nil
                if worker and worker.proxy_enabled == true and worker.proxy_switch then
                    transcode_upstream = worker.proxy_switch:stream()
                else
                    server:send(client, {
                        code = 503,
                        headers = {
                            "Content-Type: text/plain",
                            "Cache-Control: no-store",
                            "Pragma: no-cache",
                            "Retry-After: 1",
                            "Connection: close",
                        },
                        content = "transcode output not ready (enable per-output + udp proxy)",
                    })
                    return nil
                end
            else
                -- Legacy single-process transcode does not expose a stable internal bus for /play.
                server:abort(client, 404)
                return nil
            end
        end
        if not channel and not transcode_upstream then
            server:abort(client, 404)
            return nil
        end

        local function allow_stream(session)
            if channel then
                client_data.output_data = { channel_data = channel }
            else
                client_data.output_data = {}
            end
            http_output_client(server, client, request, client_data.output_data)

            if session and session.session_id and auth and auth.register_client then
                auth.register_client(session.session_id, server, client)
                client_data.auth_session_id = session.session_id
            end

            local upstream = transcode_upstream
            if channel then
                local channel_data = channel
                if channel_data.keep_timer then
                    channel_data.keep_timer:close()
                    channel_data.keep_timer = nil
                end
                channel_data.clients = channel_data.clients + 1

                if not channel_data.input[1].input then
                    channel_init_input(channel_data, 1)
                end
                upstream = channel_data.tail:stream()
            end

            local buffer_size = math.max(128, http_play_buffer_kb)
            -- Prevent very large buffers from producing bursty /play delivery (drain -> long refill cycles).
            if http_play_buffer_cap_kb and http_play_buffer_cap_kb > 0 then
                buffer_size = math.min(buffer_size, math.floor(http_play_buffer_cap_kb))
            end
            local buffer_fill = math.floor(buffer_size / 4)
            -- Cap buffer_fill so /play is less bursty. This matters for:
            -- - players that expect near-realtime delivery
            -- - Astra http inputs with sync=0 (event-driven) which can time out on long gaps.
            if http_play_buffer_fill_kb and http_play_buffer_fill_kb > 0 then
                buffer_fill = math.min(buffer_fill, math.floor(http_play_buffer_fill_kb))
            end
            local query = request and request.query or nil
            if query then
                local qbuf = tonumber(query.buf_kb or query.buffer_kb or query.buf)
                if qbuf and qbuf > 0 then
                    buffer_size = math.max(128, math.floor(qbuf))
                    buffer_fill = math.floor(buffer_size / 4)
                    if http_play_buffer_fill_kb and http_play_buffer_fill_kb > 0 then
                        buffer_fill = math.min(buffer_fill, math.floor(http_play_buffer_fill_kb))
                    end
                end
                local qfill = tonumber(query.buf_fill_kb or query.fill_kb or query.buf_fill)
                if qfill and qfill > 0 then
                    buffer_fill = math.min(buffer_size, math.floor(qfill))
                end
            end
            server:send(client, {
                upstream = upstream,
                buffer_size = buffer_size,
                buffer_fill = buffer_fill,
            }, "video/MP2T")
	        end

	        if auth and auth.check_play then
	            -- Internal consumers must work even when play tokens are required.
	            if internal then
	                allow_stream(nil)
	                return nil
	            end
	            local stream_cfg = (entry.channel and entry.channel.config) or (entry.job and entry.job.config) or nil
	            local stream_name = (stream_cfg and stream_cfg.name) or (entry.job and entry.job.name) or stream_id
	            local headers = request.headers or {}
	            auth.check_play({
	                stream_id = stream_id,
	                stream_name = stream_name,
	                stream_cfg = stream_cfg,
	                proto = "http_ts",
	                request = request,
	                ip = request.addr,
	                token = auth.get_token and auth.get_token(request) or nil,
	                user_agent = header_value(headers, "user-agent") or "",
	                referer = header_value(headers, "referer") or "",
	                uri = build_request_uri(request),
	            }, function(allowed, session)
	                if not allowed then
	                    server:abort(client, 403)
	                    return
	                end
	                allow_stream(session)
	            end)
	            return nil
	        end

				        allow_stream(nil)
				    end

        local function http_input_stream(server, client, request)
            local client_data = server:data(client)

            if not request then
                if client_data.output_data and client_data.output_data.channel_data then
                    local channel_data = client_data.output_data.channel_data
                    channel_data.clients = channel_data.clients - 1
                    if channel_data.keep_timer then
                        channel_data.keep_timer:close()
                        channel_data.keep_timer = nil
                    end
                    if channel_data.clients == 0 and channel_data.input[1].input ~= nil then
                        local keep_active = tonumber(channel_data.config.http_keep_active or 0) or 0
                        if keep_active == 0 then
                            for input_id, input_data in ipairs(channel_data.input) do
                                if input_data.input then
                                    channel_kill_input(channel_data, input_id)
                                end
                            end
                            channel_data.active_input_id = 0
                        elseif keep_active > 0 then
                            channel_data.keep_timer = timer({
                                interval = keep_active,
                                callback = function(self)
                                    self:close()
                                    channel_data.keep_timer = nil
                                    if channel_data.clients == 0 then
                                        for input_id, input_data in ipairs(channel_data.input) do
                                            if input_data.input then
                                                channel_kill_input(channel_data, input_id)
                                            end
                                        end
                                        channel_data.active_input_id = 0
                                    end
                                end,
                            })
                        end
                    end
                end

                http_output_client(server, client, nil)
                if client_data.auth_session_id and auth and auth.unregister_client then
                    auth.unregister_client(client_data.auth_session_id, server, client)
                    client_data.auth_session_id = nil
                end
                client_data.output_data = nil
                return nil
            end

            local function is_internal_input_request(req)
                local ip = tostring(req.addr or "")
                local lower = ip:lower()
                if not (ip == "127.0.0.1" or ip == "::1" or ip:match("^127%.") or lower:match("^::ffff:127%.")) then
                    return false
                end
                local headers = req.headers or {}
                if headers["x-forwarded-for"] or headers["X-Forwarded-For"]
                    or headers["forwarded"] or headers["Forwarded"]
                    or headers["x-real-ip"] or headers["X-Real-IP"] then
                    return false
                end

                -- Prefer query parsing. Fallback to raw path parsing if needed.
                local flag = nil
                local query = req.query
                if query then
                    flag = query.internal or query._internal
                end
                if flag == nil then
                    local raw = tostring(req.path or "")
                    flag = raw:match("[?&]internal=([^&]+)") or raw:match("[?&]_internal=([^&]+)")
                end

                -- Allow loopback consumers even without ?internal=1 (still blocked from non-loopback).
                if flag == nil then
                    return true
                end
                local text = tostring(flag):lower()
                return (text == "1" or text == "true" or text == "yes" or text == "on")
            end

            local internal = is_internal_input_request(request)
            if not internal then
                server:abort(client, 404)
                return nil
            end

            if not http_auth_check(request) then
                server:abort(client, 401)
                return nil
            end

            local raw_stream_id = http_play_stream_id(request.path)
            if not raw_stream_id then
                server:abort(client, 404)
                return nil
            end

            local stream_id = raw_stream_id
            local loop_input_id = nil
            local base, idx = raw_stream_id:match("^(.+)~([0-9]+)$")
            if base and idx then
                stream_id = base
                loop_input_id = tonumber(idx)
            end

            local entry = runtime.streams[stream_id]
            local channel = entry and entry.channel or nil
            local job = entry and entry.job or nil
            if not job and transcode and transcode.jobs then
                job = transcode.jobs[stream_id]
            end
            if not channel and job then
                local n = loop_input_id or 1
                if transcode and transcode.ensure_loop_channel then
                    pcall(transcode.ensure_loop_channel, job, n)
                end
                if job.loop_channels and job.loop_channels[n] then
                    channel = job.loop_channels[n]
                elseif job.loop_channel then
                    channel = job.loop_channel
                end
            end
            if not channel then
                server:abort(client, 404)
                return nil
            end

            local function allow_stream(_session)
                client_data.output_data = { channel_data = channel }
                http_output_client(server, client, request, client_data.output_data)

                local channel_data = channel
                if channel_data.keep_timer then
                    channel_data.keep_timer:close()
                    channel_data.keep_timer = nil
                end
                channel_data.clients = channel_data.clients + 1

                if not channel_data.input[1].input then
                    channel_init_input(channel_data, 1)
                end
                -- Internal loop channels are created with no outputs, so their active input is not started
                -- until a client connects. For /input we must explicitly activate the upstream to avoid
                -- returning 200 with an empty body (NO_PROGRESS in ffmpeg).
                if (channel_data.active_input_id or 0) == 0
                    and channel_data.transmit
                    and channel_data.input
                    and channel_data.input[1]
                    and channel_data.input[1].input
                    and channel_data.input[1].input.tail
                    and type(channel_data.transmit.set_upstream) == "function" then
                    channel_data.transmit:set_upstream(channel_data.input[1].input.tail:stream())
                    channel_data.active_input_id = 1
                end
                if (channel_data.active_input_id or 0) == 0 then
                    log.warning("[http input] stream " .. tostring(stream_id) .. " has no active input")
                    server:abort(client, 503)
                    return nil
                end

                -- /input buffering is server-side; ignore query overrides so ffmpeg input URL stays stable.
                local buffer_size = math.max(128, transcode_loopback_buf_kb)
                if transcode_loopback_buf_cap_kb and transcode_loopback_buf_cap_kb > 0 then
                    buffer_size = math.min(buffer_size, math.floor(transcode_loopback_buf_cap_kb))
                end
                local buffer_fill = math.min(buffer_size, math.max(1, math.floor(transcode_loopback_buf_fill_kb)))
                server:send(client, {
                    upstream = channel_data.tail:stream(),
                    buffer_size = buffer_size,
                    buffer_fill = buffer_fill,
                }, "video/MP2T")
            end

            allow_stream(nil)
            return nil
        end

    local function update_live_stats(job, profile_id, delta, internal)
        if not job or not profile_id or profile_id == "" then
            return nil
        end
        job.publish_live_stats = job.publish_live_stats or {}
        local st = job.publish_live_stats[profile_id] or {
            clients = 0,
            internal_clients = 0,
            requests_total = 0,
        }
        local now = os.time()
        if delta and delta ~= 0 then
            st.clients = math.max(0, (st.clients or 0) + delta)
            if internal then
                st.internal_clients = math.max(0, (st.internal_clients or 0) + delta)
            end
            if delta < 0 then
                st.last_disconnect_ts = now
            end
        end
        job.publish_live_stats[profile_id] = st
        return st
    end

    local function http_live_stream(server, client, request)
        local client_data = server:data(client)
        if not request then
            local meta = client_data and client_data.live_meta or nil
            if meta and meta.stream_id and meta.profile_id then
                local job = transcode and transcode.jobs and transcode.jobs[meta.stream_id] or nil
                update_live_stats(job, meta.profile_id, -1, meta.internal)
            end
            if client_data then
                client_data.live_meta = nil
            end
            return nil
        end
        if request.method ~= "GET" then
            server:abort(client, 405)
            return nil
        end

        -- In http_upstream mode, successful response must be a single server:send() with upstream.
        if not http_auth_check(request) then
            server:abort(client, 401)
            return nil
        end

        local function is_internal_live_request(req)
            if not req or not req.query then
                return false
            end
            local flag = req.query.internal or req.query._internal
            if flag == nil then
                return false
            end
            local text = tostring(flag):lower()
            if not (text == "1" or text == "true" or text == "yes" or text == "on") then
                return false
            end
            local ip = tostring(req.addr or "")
            if ip == "127.0.0.1" or ip == "::1" or ip:match("^127%.") then
                local headers = req.headers or {}
                if headers["x-forwarded-for"] or headers["X-Forwarded-For"]
                    or headers["forwarded"] or headers["Forwarded"]
                    or headers["x-real-ip"] or headers["X-Real-IP"] then
                    return false
                end
                return true
            end
            return false
        end

        local stream_id, profile_id = http_live_stream_ids(request.path)
        if not stream_id or not profile_id then
            server:abort(client, 404)
            return nil
        end

        local job = transcode and transcode.jobs and transcode.jobs[stream_id] or nil
        if not job or job.ladder_enabled ~= true then
            server:abort(client, 404)
            return nil
        end
        local bus = job.profile_buses and job.profile_buses[profile_id] or nil
        if not bus or not bus.switch then
            server:abort(client, 404)
            return nil
        end

        local buffer_size = math.max(128, http_play_buffer_kb)
        if http_play_buffer_cap_kb and http_play_buffer_cap_kb > 0 then
            buffer_size = math.min(buffer_size, math.floor(http_play_buffer_cap_kb))
        end
        local buffer_fill = math.floor(buffer_size / 4)
        if http_play_buffer_fill_kb and http_play_buffer_fill_kb > 0 then
            buffer_fill = math.min(buffer_fill, math.floor(http_play_buffer_fill_kb))
        end

        local query = request and request.query or nil
        if query then
            local qbuf = tonumber(query.buf_kb or query.buffer_kb or query.buf)
            if qbuf and qbuf > 0 then
                buffer_size = math.max(128, math.floor(qbuf))
                buffer_fill = math.floor(buffer_size / 4)
                if http_play_buffer_fill_kb and http_play_buffer_fill_kb > 0 then
                    buffer_fill = math.min(buffer_fill, math.floor(http_play_buffer_fill_kb))
                end
            end
            local qfill = tonumber(query.buf_fill_kb or query.fill_kb or query.buf_fill)
            if qfill and qfill > 0 then
                buffer_fill = math.min(buffer_size, math.floor(qfill))
            end
        end

        local internal = is_internal_live_request(request)
        if client_data and not client_data.live_meta then
            local st = update_live_stats(job, profile_id, 1, internal)
            if st then
                st.requests_total = (st.requests_total or 0) + 1
                st.last_request_ts = os.time()
                if internal then
                    st.last_internal_ts = st.last_request_ts
                end
            end
            client_data.live_meta = {
                stream_id = stream_id,
                profile_id = profile_id,
                internal = internal == true,
            }
        end

        local function allow_stream(_session)
            server:send(client, {
                upstream = bus.switch:stream(),
                buffer_size = buffer_size,
                buffer_fill = buffer_fill,
            }, "video/MP2T")
        end

        -- /live is used both by external clients and by internal publishers (ffmpeg -c copy).
        -- External access should follow the same token auth rules as /play, but internal publishers
        -- must work even when tokens are required.
        if internal then
            allow_stream(nil)
            return nil
        end

        local token = auth and auth.get_token and auth.get_token(request) or nil
        ensure_token_auth(server, client, request, {
            stream_id = stream_id,
            stream_name = job and job.name or stream_id,
            proto = "http_ts",
            token = token,
        }, function(session)
            allow_stream(session)
        end)
        return nil
    end

    local function preview_route_handler(server, client, request)
        local client_data = server:data(client)

        if not request then
            if client_data.preview_memfd and preview_memfd_handler then
                preview_memfd_handler(server, client, request)
                client_data.preview_memfd = nil
            end
            return nil
        end

        if not preview_memfd_handler or not preview or not preview.extract_token then
            server:abort(client, 501)
            return nil
        end

        local token = preview.extract_token(request.path or "")
        if not token or not (preview.touch and preview.touch(token)) then
            server:abort(client, 404)
            return nil
        end

        -- Если preview использует внешний процесс (ffmpeg) и пишет HLS в каталог,
        -- отдаём файлы напрямую с no-store заголовками.
        if preview.get_session then
            local s = preview.get_session(token)
            if s and s.base_path then
                if not request or request.method ~= "GET" then
                    server:abort(client, 405)
                    return nil
                end
                local rel = request.path:match("^/preview/[0-9a-fA-F]+/(.+)$")
                if not rel or rel == "" or rel:find("%.%.", 1, true) or rel:find("/", 1, true) then
                    server:abort(client, 404)
                    return nil
                end
                local file_path = join_path(s.base_path, rel)
                local ext = rel:match("%.([%w]+)$") or ""
                local content_type = mime[ext] or "application/octet-stream"
                local function send_not_ready()
                    server:send(client, {
                        code = 503,
                        headers = {
                            "Content-Type: " .. content_type,
                            "Cache-Control: no-store",
                            "Pragma: no-cache",
                            "Retry-After: 1",
                            "Connection: close",
                        },
                        content = "",
                    })
                end
                local fp = io.open(file_path, "rb")
                if not fp then
                    -- ffmpeg preview может ещё не успеть записать плейлист. Для HLS клиентов
                    -- корректнее 503 (как в on-demand memfd), чем 404.
                    if ext == "m3u8" then
                        send_not_ready()
                        return nil
                    end
                    server:abort(client, 404)
                    return nil
                end
                local content = fp:read("*a")
                fp:close()
                if not content then
                    if ext == "m3u8" then
                        send_not_ready()
                        return nil
                    end
                    server:abort(client, 404)
                    return nil
                end
                -- Заглушка index.m3u8 кладётся сразу, но сегментов может ещё не быть.
                -- Не отдаём "пустой" плейлист 200, иначе Safari может зависнуть без ретраев.
                if ext == "m3u8" and not content:find("#EXTINF", 1, true) then
                    send_not_ready()
                    return nil
                end
                server:send(client, {
                    code = 200,
                    headers = {
                        "Content-Type: " .. content_type,
                        "Cache-Control: no-store",
                        "Pragma: no-cache",
                        "Connection: close",
                    },
                    content = content,
                })
                return nil
            end
        end

        local handled = preview_memfd_handler(server, client, request)
        if handled then
            client_data.preview_memfd = true
            return nil
        end

        server:abort(client, 404)
        return nil
    end

    local function hls_route_handler(server, client, request)
        local client_data = server:data(client)
        if request and not ensure_http_auth(server, client, request) then
            return nil
        end
        if not request then
            if client_data.hls_memfd and hls_memfd_handler then
                hls_memfd_handler(server, client, request)
                client_data.hls_memfd = nil
                return nil
            end
            if hls_static then
                return hls_static(server, client, request)
            end
            return nil
        end

        local prefix = opt.hls_route .. "/"
        if request.path:sub(1, #prefix) ~= prefix then
            if hls_static then
                return hls_static(server, client, request)
            end
            server:abort(client, 404)
            return nil
        end

        local rest = request.path:sub(#prefix + 1)
        local requested_id = rest:match("^([^/]+)/")
        if not requested_id then
            if hls_static then
                return hls_static(server, client, request)
            end
            server:abort(client, 404)
            return nil
        end

        local base_id = requested_id
        local profile_id = nil
        do
            local b, p = requested_id:match("^(.+)~([A-Za-z0-9_-]+)$")
            if b and b ~= "" and p and p ~= "" then
                base_id = b
                profile_id = p
            end
        end

        local entry = runtime.streams[base_id]
        local stream_cfg = entry and entry.channel and entry.channel.config or nil
        local token = auth and auth.get_token and auth.get_token(request) or nil
        ensure_token_auth(server, client, request, {
            stream_id = base_id,
            stream_name = stream_cfg and stream_cfg.name or base_id,
            stream_cfg = stream_cfg,
            proto = "hls",
            token = token,
        }, function(session)
            track_hls_session(request, opt.hls_route)

            local is_playlist = request.path:match("%.m3u8?$") ~= nil
            local can_rewrite = auth
                and auth.get_hls_rewrite_enabled
                and auth.get_hls_rewrite_enabled()
                and auth.rewrite_m3u8
            local needs_cookie = (token and token ~= "") or (session and session.session_id)

            local is_master_index = (profile_id == nil)
                and (rest == (tostring(base_id) .. "/index.m3u8") or rest == (tostring(base_id) .. "/index.m3u"))

            -- Serve ladder master playlist even when auth rewrite is disabled.
            if is_playlist and is_master_index and not (can_rewrite or needs_cookie) then
                local payload = nil
                local job = transcode and transcode.jobs and transcode.jobs[base_id] or nil
	                if job and job.ladder_enabled == true and type(job.publish) == "table" then
	                    local variant_set = {}
	                    for _, pub in ipairs(job.publish) do
	                        if pub and pub.enabled == true and tostring(pub.type or ""):lower() == "hls" then
	                            -- Empty/missing variants means "all profiles" (Flussonic-like UX).
	                            if type(pub.variants) == "table" and #pub.variants > 0 then
	                                for _, pid in ipairs(pub.variants) do
	                                    if pid and pid ~= "" then
	                                        variant_set[tostring(pid)] = true
	                                    end
	                                end
	                            else
	                                for _, p in ipairs(job.profiles or {}) do
	                                    if p and p.id then
	                                        variant_set[tostring(p.id)] = true
	                                    end
	                                end
	                            end
	                        end
	                    end
	                    local variants = {}
	                    for pid, _ in pairs(variant_set) do
	                        variants[#variants + 1] = pid
	                    end
                    if #variants > 0 then
                        local profiles_by_id = {}
                        for _, p in ipairs(job.profiles or {}) do
                            if p and p.id then
                                profiles_by_id[tostring(p.id)] = p
                            end
                        end
                        table.sort(variants, function(a, b)
                            local pa = profiles_by_id[a] or {}
                            local pb = profiles_by_id[b] or {}
                            local ba = tonumber(pa.bitrate_kbps) or 0
                            local bb = tonumber(pb.bitrate_kbps) or 0
                            if ba ~= bb then
                                return ba > bb
                            end
                            local ha = tonumber(pa.height) or 0
                            local hb = tonumber(pb.height) or 0
                            if ha ~= hb then
                                return ha > hb
                            end
                            return tostring(a) < tostring(b)
                        end)
                        local lines = {
                            "#EXTM3U",
                            "#EXT-X-VERSION:3",
                            "#EXT-X-INDEPENDENT-SEGMENTS",
                        }
                        for _, pid in ipairs(variants) do
                            local p = profiles_by_id[pid] or {}
                            local bw = tonumber(p.bitrate_kbps) or 0
                            if bw < 1 then bw = 1 end
                            bw = math.floor(bw * 1000)
                            local inf = "BANDWIDTH=" .. tostring(bw)
                            local w = tonumber(p.width)
                            local h = tonumber(p.height)
                            if w and h and w > 0 and h > 0 then
                                inf = inf .. ",RESOLUTION=" .. tostring(math.floor(w)) .. "x" .. tostring(math.floor(h))
                            end
                            table.insert(lines, "#EXT-X-STREAM-INF:" .. inf)
                            table.insert(lines, opt.hls_route .. "/" .. tostring(base_id) .. "~" .. tostring(pid) .. "/index.m3u8")
                        end
                        payload = table.concat(lines, "\n") .. "\n"
                    end
                end

                if payload then
                    local headers = {
                        "Content-Type: application/vnd.apple.mpegurl",
                        "Connection: close",
                    }
                    if m3u_headers then
                        for _, header in ipairs(m3u_headers) do
                            table.insert(headers, header)
                        end
                    end
                    server:send(client, { code = 200, headers = headers, content = payload })
                    return
                end
            end

            if is_playlist and (can_rewrite or needs_cookie) then
                local rel = rest
                if rel:find("%.%.") then
                    server:abort(client, 404)
                    return
                end
                local payload = nil
                if is_master_index then
                    local job = transcode and transcode.jobs and transcode.jobs[base_id] or nil
	                    if job and job.ladder_enabled == true and type(job.publish) == "table" then
	                        local variant_set = {}
	                        for _, pub in ipairs(job.publish) do
	                            if pub and pub.enabled == true and tostring(pub.type or ""):lower() == "hls" then
	                                -- Empty/missing variants means "all profiles" (Flussonic-like UX).
	                                if type(pub.variants) == "table" and #pub.variants > 0 then
	                                    for _, pid in ipairs(pub.variants) do
	                                        if pid and pid ~= "" then
	                                            variant_set[tostring(pid)] = true
	                                        end
	                                    end
	                                else
	                                    for _, p in ipairs(job.profiles or {}) do
	                                        if p and p.id then
	                                            variant_set[tostring(p.id)] = true
	                                        end
	                                    end
	                                end
	                            end
	                        end
	                        local variants = {}
	                        for pid, _ in pairs(variant_set) do
	                            variants[#variants + 1] = pid
	                        end
                        if #variants > 0 then
                            local profiles_by_id = {}
                            for _, p in ipairs(job.profiles or {}) do
                                if p and p.id then
                                    profiles_by_id[tostring(p.id)] = p
                                end
                            end
                            table.sort(variants, function(a, b)
                                local pa = profiles_by_id[a] or {}
                                local pb = profiles_by_id[b] or {}
                                local ba = tonumber(pa.bitrate_kbps) or 0
                                local bb = tonumber(pb.bitrate_kbps) or 0
                                if ba ~= bb then
                                    return ba > bb
                                end
                                local ha = tonumber(pa.height) or 0
                                local hb = tonumber(pb.height) or 0
                                if ha ~= hb then
                                    return ha > hb
                                end
                                return tostring(a) < tostring(b)
                            end)
                            local lines = {
                                "#EXTM3U",
                                "#EXT-X-VERSION:3",
                                "#EXT-X-INDEPENDENT-SEGMENTS",
                            }
                            for _, pid in ipairs(variants) do
                                local p = profiles_by_id[pid] or {}
                                local bw = tonumber(p.bitrate_kbps) or 0
                                if bw < 1 then bw = 1 end
                                bw = math.floor(bw * 1000)
                                local inf = "BANDWIDTH=" .. tostring(bw)
                                local w = tonumber(p.width)
                                local h = tonumber(p.height)
                                if w and h and w > 0 and h > 0 then
                                    inf = inf .. ",RESOLUTION=" .. tostring(math.floor(w)) .. "x" .. tostring(math.floor(h))
                                end
                                table.insert(lines, "#EXT-X-STREAM-INF:" .. inf)
                                table.insert(lines, opt.hls_route .. "/" .. tostring(base_id) .. "~" .. tostring(pid) .. "/index.m3u8")
                            end
                            payload = table.concat(lines, "\n") .. "\n"
                        end
                    end
                end

                if not payload and hls_memfd_handler and hls_memfd_handler.get_playlist then
                    payload = hls_memfd_handler:get_playlist(requested_id)
                end
                if not payload then
                    if hls_memfd_handler then
                        local handled = hls_memfd_handler(server, client, request)
                        if handled then
                            client_data.hls_memfd = true
                            return
                        end
                    end
                end
                if not payload and hls_static then
                    local file_path = join_path(hls_dir, rel)
                    local fp = io.open(file_path, "rb")
                    if fp then
                        payload = fp:read("*a")
                        fp:close()
                    end
                end
                if not payload then
                    if hls_static then
                        return hls_static(server, client, request)
                    end
                    server:abort(client, 404)
                    return
                end
                if can_rewrite then
                    payload = auth.rewrite_m3u8(payload, token, session and session.session_id or nil)
                end
                local headers = {
                    "Content-Type: application/vnd.apple.mpegurl",
                    "Connection: close",
                }
                if m3u_headers then
                    for _, header in ipairs(m3u_headers) do
                        table.insert(headers, header)
                    end
                end
                if token and token ~= "" then
                    table.insert(headers, "Set-Cookie: astra_token=" .. token .. "; Path=/; HttpOnly; SameSite=Lax")
                end
                if session and session.session_id then
                    table.insert(headers, "Set-Cookie: astra_sid=" .. session.session_id .. "; Path=/; HttpOnly; SameSite=Lax")
                end
                server:send(client, { code = 200, headers = headers, content = payload })
                return
            end

            if hls_memfd_handler then
                local handled = hls_memfd_handler(server, client, request)
                if handled then
                    client_data.hls_memfd = true
                    return
                end
            end

            if hls_static then
                return hls_static(server, client, request)
            end
            server:abort(client, 404)
            return
        end)
    end

	    local function dash_route_handler(server, client, request)
	        local client_data = server:data(client)
	        if request and not ensure_http_auth(server, client, request) then
	            return nil
	        end
        if not request then
            if client_data.dash_static then
                dash_static(server, client, request)
                client_data.dash_static = nil
                return nil
            end
            return nil
        end
        if request.method ~= "GET" then
            server:abort(client, 405)
            return nil
        end

        local prefix = dash_route .. "/"
        if request.path:sub(1, #prefix) ~= prefix then
            server:abort(client, 404)
            return nil
        end
        local rest = request.path:sub(#prefix + 1)
        local stream_id = rest:match("^([^/]+)/")
        if not stream_id or stream_id == "" then
            server:abort(client, 404)
            return nil
        end

        local job = transcode and transcode.jobs and transcode.jobs[stream_id] or nil
        if not job or job.ladder_enabled ~= true then
            server:abort(client, 404)
            return nil
        end

        local token = auth and auth.get_token and auth.get_token(request) or nil
	        ensure_token_auth(server, client, request, {
	            stream_id = stream_id,
	            stream_name = job.name or stream_id,
	            stream_cfg = nil,
	            proto = "dash",
	            token = token,
	        }, function(_session)
	            dash_static(server, client, request)
	            client_data.dash_static = true
	        end)
	    end
	
	    local function embed_route_handler(server, client, request)
	        if request and not ensure_http_auth(server, client, request) then
	            return nil
	        end
	        if not request then
	            return nil
	        end
	        if request.method ~= "GET" then
	            server:abort(client, 405)
	            return nil
	        end
	
	        local prefix = embed_route .. "/"
	        if request.path:sub(1, #prefix) ~= prefix then
	            server:abort(client, 404)
	            return nil
	        end
	        local rest = request.path:sub(#prefix + 1)
	        local stream_id = rest:match("^([^/]+)/?$")
	        if not stream_id or stream_id == "" then
	            server:abort(client, 404)
	            return nil
	        end
	
	        local job = transcode and transcode.jobs and transcode.jobs[stream_id] or nil
	        if not job then
	            server:abort(client, 404)
	            return nil
	        end
	
	        local token = auth and auth.get_token and auth.get_token(request) or nil
	        ensure_token_auth(server, client, request, {
	            stream_id = stream_id,
	            stream_name = job.name or stream_id,
	            stream_cfg = nil,
	            proto = "embed",
	            token = token,
	        }, function(_session)
		            local has_hls = false
		            if job and job.ladder_enabled == true and type(job.publish) == "table" then
		                for _, pub in ipairs(job.publish) do
		                    if pub and pub.enabled == true and tostring(pub.type or ""):lower() == "hls" then
		                        -- Empty/missing variants means "all profiles" (Flussonic-like UX).
		                        has_hls = true
		                        break
		                    end
		                end
		            end
	
	            local hls_url = has_hls and (opt.hls_route .. "/" .. tostring(stream_id) .. "/index.m3u8") or ""
	            local dash_url = dash_route .. "/" .. tostring(stream_id) .. "/manifest.mpd"
	            local first_profile = job and job.profiles and job.profiles[1] and job.profiles[1].id or nil
	            local live_url = (first_profile and ("/live/" .. tostring(stream_id) .. "~" .. tostring(first_profile) .. ".ts")) or ""
	
	            local title = escape_html(job.name or stream_id)
	            local payload = [[<!doctype html>
<html lang="en">
<head>
  <meta charset="utf-8" />
  <meta name="viewport" content="width=device-width, initial-scale=1" />
  <title>]] .. title .. [[</title>
  <style>
    :root { color-scheme: dark; }
    body { margin: 0; font: 14px/1.4 system-ui, -apple-system, Segoe UI, Roboto, Ubuntu, Cantarell, Arial, sans-serif; background: #0f1115; color: #e9eef6; }
    .wrap { max-width: 980px; margin: 24px auto; padding: 0 16px; }
    h1 { margin: 0 0 12px; font-size: 18px; font-weight: 600; }
    .card { background: #151924; border: 1px solid rgba(255,255,255,0.08); border-radius: 12px; padding: 14px; }
    video { width: 100%; height: auto; background: #000; border-radius: 10px; }
    .meta { margin-top: 10px; display: flex; gap: 12px; flex-wrap: wrap; font-size: 13px; opacity: 0.9; }
    .meta a { color: #9bdcff; text-decoration: none; }
    .meta a:hover { text-decoration: underline; }
    .note { margin-top: 10px; font-size: 13px; opacity: 0.85; }
    .err { color: #ffb2b2; }
  </style>
</head>
<body>
  <div class="wrap">
    <h1>]] .. title .. [[</h1>
    <div class="card">
      <video id="video" controls playsinline></video>
      <div class="meta">
        <a href="]] .. escape_html(hls_url) .. [[">HLS</a>
        <a href="]] .. escape_html(dash_url) .. [[">DASH</a>
        <a href="]] .. escape_html(live_url) .. [[">HTTP-TS</a>
      </div>
      <div id="msg" class="note"></div>
    </div>
  </div>
  <script src="/vendor/hls.min.js"></script>
  <script>
    (function () {
      var video = document.getElementById('video');
      var msg = document.getElementById('msg');
      var src = ]] .. string.format("%q", hls_url) .. [[;
      function setMsg(text, isErr) {
        msg.textContent = text || '';
        msg.className = isErr ? 'note err' : 'note';
      }
      if (!src) {
        setMsg('HLS publish is not enabled for this stream. Enable publish type \"hls\" to use embed playback.', true);
        return;
      }
      if (video.canPlayType('application/vnd.apple.mpegurl')) {
        video.src = src;
        video.play().catch(function () {});
        return;
      }
      if (window.Hls && window.Hls.isSupported()) {
        var hls = new window.Hls({
          liveSyncDurationCount: 3,
          maxLiveSyncPlaybackRate: 1.02
        });
        hls.attachMedia(video);
        hls.on(window.Hls.Events.MEDIA_ATTACHED, function () {
          hls.loadSource(src);
        });
        hls.on(window.Hls.Events.ERROR, function (_evt, data) {
          if (!data || !data.fatal) return;
          setMsg('HLS playback error: ' + (data.type || 'unknown') + ' (' + (data.details || '') + ')', true);
        });
        video.play().catch(function () {});
        return;
      }
      setMsg('HLS is not supported in this browser (no native HLS and no hls.js).', true);
    })();
  </script>
</body>
</html>
]]
	            server:send(client, {
	                code = 200,
	                headers = {
	                    "Content-Type: text/html; charset=utf-8",
	                    "Cache-Control: no-store",
	                    "Pragma: no-cache",
	                    "Connection: close",
	                },
	                content = payload,
	            })
	        end)
	    end

	    local function build_http_play_routes(include_redirect, include_hls_route, include_web)
	        local routes = {}
	        if not http_play_enabled then
	            return routes
	        end
	        -- /input is internal-only (loopback + ?internal=1 + no forwarded headers) but it must be reachable
	        -- on the http_play server too, because many deployments expose only http_play_port to ffmpeg.
	        local input_upstream = http_upstream({ callback = http_input_stream })
	        table.insert(routes, { http_play_playlist_name, http_play_playlist })
	        table.insert(routes, { xspf_path, http_play_xspf })
	        table.insert(routes, { "/play/playlist.m3u8", http_play_playlist })
	        table.insert(routes, { "/play/playlist.xspf", http_play_xspf })
	        table.insert(routes, { "/favicon.ico", http_favicon })
	        if http_play_allow then
	            local upstream = http_upstream({ callback = http_play_stream })
	            table.insert(routes, { "/stream/*", upstream })
	            table.insert(routes, { "/play/*", upstream })
	        end
	        table.insert(routes, { "/input/*", input_upstream })
	        if include_hls_route and http_play_hls then
	            table.insert(routes, { opt.hls_route .. "/*", hls_route_handler })
	        end
	        if include_redirect then
	            table.insert(routes, { "/", http_redirect({ location = http_play_playlist_name }) })
        end
        if include_web then
            table.insert(routes, { "/index.html", web_static })
            table.insert(routes, { "/*", web_index })
        end
        return routes
    end

	    local play_upstream = http_upstream({ callback = http_play_stream })
	    local input_upstream = http_upstream({ callback = http_input_stream })
	    local live_upstream = http_upstream({ callback = http_live_stream })

		    local main_routes = {
		        { "/api/*", api.handle_request },
		        { "/live/*", live_upstream },
		        { "/input/*", input_upstream },
		        { "/favicon.ico", http_favicon },
		        { "/index.html", web_static },
		    }

		    if http_play_enabled and http_play_port == opt.port then
		        for _, route in ipairs(build_http_play_routes(false, false, false)) do
		            table.insert(main_routes, route)
		        end
		    end
		
		    -- Internal-only /play (stream refs) even when external http_play is disabled.
		    -- Note: direct inputs use /input/* loopback instead of /play/*.
		    if not http_play_allow then
		        table.insert(main_routes, { "/stream/*", play_upstream })
		        table.insert(main_routes, { "/play/*", play_upstream })
		    end

		    table.insert(main_routes, { "/preview/*", preview_route_handler })
		    table.insert(main_routes, { opt.hls_route .. "/*", hls_route_handler })
		    table.insert(main_routes, { dash_route .. "/*", dash_route_handler })
		    table.insert(main_routes, { embed_route .. "/*", embed_route_handler })
	    table.insert(main_routes, { "/", web_index })
	    table.insert(main_routes, { "/*", web_index })

    http_server({
        addr = opt.addr,
        port = opt.port,
        server_name = "Astra Studio",
        route = main_routes,
    })

    if http_play_enabled and http_play_port ~= opt.port then
        http_server({
            addr = opt.addr,
            port = http_play_port,
            server_name = "Astra HTTP Play",
            route = build_http_play_routes(true, true, true),
        })
        log.info("[server] http play on " .. opt.addr .. ":" .. http_play_port)
    end

    if transcode then
        transcode.defer_start = false
        if transcode.start_deferred then
            transcode.start_deferred()
        end
    end

    log.info("[server] web ui on " .. opt.addr .. ":" .. opt.port)
end
