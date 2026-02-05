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
dofile(script_path("telegram.lua"))
dofile(script_path("watchdog.lua"))
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
            if opts.id then
                _G[tostring(opts.id)] = nil
            end
            if cam.close then
                pcall(function() cam:close() end)
            end
        end
    end
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
                local ctor = _G[tostring(entry.type)]
                local ctor_type = type(ctor)
                if ctor_type ~= "function" and ctor_type ~= "table" then
                    log.error("[softcam] unknown type: " .. tostring(entry.type))
                else
                    local ok, instance = pcall(ctor, entry)
                    if ok and instance then
                        table.insert(new_list, instance)
                        local id = entry.id or (instance.__options and instance.__options.id)
                        if id then
                            _G[tostring(id)] = instance
                        end
                    else
                        log.error("[softcam] failed to init: " .. tostring(entry.id or entry.type))
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
    local prefix = nil
    if path:sub(1, 8) == "/stream/" then
        prefix = "/stream/"
    elseif path:sub(1, 6) == "/play/" then
        prefix = "/play/"
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
    log.info(string.format(
        "[startup] edition=%s tools: ffmpeg=%s (%s, %s) ffprobe=%s (%s, %s)",
        tostring(edition),
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
    if watchdog and watchdog.configure then
        watchdog.configure()
    end

    if not opt.port_set then
        local stored_port = config.get_setting("http_port")
        if stored_port then
            opt.port = tonumber(stored_port) or opt.port
        end
    end

    local stored_hls_dir = config.get_setting("hls_dir")
    local hls_dir = opt.hls_dir or stored_hls_dir or (opt.data_dir .. "/hls")
    ensure_dir(hls_dir)

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

    local hls_max_age = math.max(1, math.floor(hls_duration * hls_quantity))
    local hls_expires = hls_use_expires and hls_max_age or 0

    local m3u_headers = nil
    if hls_m3u_headers then
        m3u_headers = {
            "Cache-Control: no-cache",
            "Pragma: no-cache",
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
    }
    mime[hls_ts_extension] = hls_ts_mime
    if hls_ts_extension ~= "ts" then
        mime.ts = hls_ts_mime
    end

    local hls_static = http_static({
        path = hls_dir,
        skip = opt.hls_route,
        expires = hls_expires,
        m3u_headers = m3u_headers,
        ts_headers = ts_headers,
        ts_extension = hls_ts_extension,
    })
    local web_static = http_static({
        path = opt.web_dir,
        headers = { "Cache-Control: no-cache" },
    })
    web_static_handler = web_static
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

        if not ensure_http_auth(server, client, request) then
            return nil
        end

        local stream_id = http_play_stream_id(request.path)
        if not stream_id then
            server:abort(client, 404)
            return nil
        end

        local entry = runtime.streams[stream_id]
        if not entry or not entry.channel then
            server:abort(client, 404)
            return nil
        end
        ensure_token_auth(server, client, request, {
            stream_id = stream_id,
            stream_name = entry.channel.config and entry.channel.config.name or stream_id,
            stream_cfg = entry.channel.config,
            proto = "http_ts",
        }, function(session)
            client_data.output_data = { channel_data = entry.channel }
            http_output_client(server, client, request, client_data.output_data)

            if session and session.session_id and auth and auth.register_client then
                auth.register_client(session.session_id, server, client)
                client_data.auth_session_id = session.session_id
            end

            local channel_data = entry.channel
            if channel_data.keep_timer then
                channel_data.keep_timer:close()
                channel_data.keep_timer = nil
            end
            channel_data.clients = channel_data.clients + 1

            if not channel_data.input[1].input then
                channel_init_input(channel_data, 1)
            end

            local buffer_size = math.max(128, http_play_buffer_kb)
            local buffer_fill = math.floor(buffer_size / 4)
            server:send(client, {
                code = 200,
                headers = {
                    "Content-Type: video/MP2T",
                    "Connection: close",
                },
                upstream = channel_data.tail:stream(),
                buffer_size = buffer_size,
                buffer_fill = buffer_fill,
            })
        end)
    end

    local function hls_route_handler(server, client, request)
        if request and not ensure_http_auth(server, client, request) then
            return nil
        end
        if not request then
            return hls_static(server, client, request)
        end

        local prefix = opt.hls_route .. "/"
        if request.path:sub(1, #prefix) ~= prefix then
            return hls_static(server, client, request)
        end

        local rest = request.path:sub(#prefix + 1)
        local stream_id = rest:match("^([^/]+)/")
        if not stream_id then
            return hls_static(server, client, request)
        end

        local entry = runtime.streams[stream_id]
        local stream_cfg = entry and entry.channel and entry.channel.config or nil
        local token = auth and auth.get_token and auth.get_token(request) or nil
        ensure_token_auth(server, client, request, {
            stream_id = stream_id,
            stream_name = stream_cfg and stream_cfg.name or stream_id,
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
            if is_playlist and (can_rewrite or needs_cookie) then
                local rel = rest
                if rel:find("%.%.") then
                    server:abort(client, 404)
                    return
                end
                local file_path = join_path(hls_dir, rel)
                local fp = io.open(file_path, "rb")
                if not fp then
                    return hls_static(server, client, request)
                end
                local content = fp:read("*a")
                fp:close()
                local payload = content
                if can_rewrite then
                    payload = auth.rewrite_m3u8(content, token, session and session.session_id or nil)
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

            return hls_static(server, client, request)
        end)
    end

    local function build_http_play_routes(include_redirect, include_hls_route, include_web)
        local routes = {}
        if not http_play_enabled then
            return routes
        end
        table.insert(routes, { http_play_playlist_name, http_play_playlist })
        table.insert(routes, { xspf_path, http_play_xspf })
        table.insert(routes, { "/play/playlist.m3u8", http_play_playlist })
        table.insert(routes, { "/play/playlist.xspf", http_play_xspf })
        table.insert(routes, { "/favicon.ico", http_favicon })
        if http_play_allow then
            table.insert(routes, { "/stream/*", http_play_stream })
            table.insert(routes, { "/play/*", http_play_stream })
        end
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

    local main_routes = {
        { "/api/*", api.handle_request },
        { "/favicon.ico", http_favicon },
        { "/index.html", web_static },
    }

    if http_play_enabled and http_play_port == opt.port then
        for _, route in ipairs(build_http_play_routes(false, false, false)) do
            table.insert(main_routes, route)
        end
    end

    table.insert(main_routes, { opt.hls_route .. "/*", hls_route_handler })
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

    log.info("[server] web ui on " .. opt.addr .. ":" .. opt.port)
end
