-- Token authorization backend (Flussonic-like)

auth = {
    cache = {},
    inflight = {},
    clients = {},
}

local function now()
    return os.time()
end

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

local function normalize_bool(value, fallback)
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

local function normalize_algo(value)
    if not value or value == "" then
        return "sha1"
    end
    local algo = tostring(value):lower()
    if algo ~= "sha1" and algo ~= "md5" then
        return "sha1"
    end
    return algo
end

local function hash_hex(algo, value)
    local payload = tostring(value or "")
    if algo == "md5" then
        return string.lower(string.hex(string.md5(payload)))
    end
    return string.lower(string.hex(string.sha1(payload)))
end

local function header_value(headers, key)
    if not headers then
        return nil
    end
    return headers[key] or headers[key:lower()] or headers[key:upper()]
end

local function parse_cookie(headers)
    local cookie = header_value(headers, "cookie")
    if not cookie then
        return {}
    end
    local out = {}
    for part in string.gmatch(cookie, "[^;]+") do
        local k, v = part:match("^%s*(.-)%s*=%s*(.*)$")
        if k and v then
            out[k] = v
        end
    end
    return out
end

local function url_encode(value)
    local text = tostring(value or "")
    return text:gsub("([^%w%-%._~])", function(c)
        return string.format("%%%02X", string.byte(c))
    end)
end

local function parse_query_string(query)
    local out = {}
    if not query or query == "" then
        return out
    end
    for part in string.gmatch(query, "[^&]+") do
        local k, v = part:match("^([^=]+)=(.*)$")
        if k then
            out[k] = v
        elseif part ~= "" then
            out[part] = ""
        end
    end
    return out
end

local function build_query(params)
    local parts = {}
    for key, value in pairs(params or {}) do
        local k = url_encode(key)
        local v = url_encode(value)
        table.insert(parts, k .. "=" .. v)
    end
    table.sort(parts)
    return table.concat(parts, "&")
end

local function split_path_query(path)
    if not path or path == "" then
        return "/", ""
    end
    local base, query = path:match("^([^?]*)%??(.*)$")
    return (base ~= "" and base or "/"), query or ""
end

local function update_query_param(url, key, value)
    if not url or url == "" then
        return url
    end
    local base, hash = url:match("^([^#]*)(#.*)$")
    if not base then
        base = url
        hash = ""
    end
    local path, query = base:match("^([^?]*)%??(.*)$")
    local params = parse_query_string(query or "")
    params[key] = tostring(value or "")
    local qs = build_query(params)
    if qs ~= "" then
        qs = "?" .. qs
    end
    return (path or "") .. qs .. (hash or "")
end

local function extract_token_from_query(request)
    if not request or not request.query then
        return nil
    end
    if request.query.token and request.query.token ~= "" then
        return request.query.token
    end
    return nil
end

local function extract_token_from_url(url)
    if not url or url == "" then
        return nil
    end
    local _, query = split_path_query(url)
    if query == "" then
        return nil
    end
    local params = parse_query_string(query)
    local token = params.token
    if token and token ~= "" then
        return token
    end
    return nil
end

local function parse_session_keys(value)
    local keys = {}
    if type(value) == "table" then
        for _, item in ipairs(value) do
            if item ~= nil and tostring(item) ~= "" then
                table.insert(keys, tostring(item))
            end
        end
    else
        local text = tostring(value or "")
        for item in text:gmatch("[^,%s]+") do
            table.insert(keys, item)
        end
    end
    if #keys == 0 then
        keys = { "ip", "name", "proto", "token" }
    end
    local present = {}
    for _, key in ipairs(keys) do
        present[key] = true
    end
    for _, req in ipairs({ "ip", "name", "proto" }) do
        if not present[req] then
            table.insert(keys, req)
        end
    end
    return keys
end

local function make_session_id(keys, values, algo)
    local parts = {}
    for _, key in ipairs(keys) do
        local value = values[key]
        if value == nil or value == "" then
            value = "undefined"
        end
        parts[#parts + 1] = tostring(value)
    end
    return hash_hex(algo, table.concat(parts, ""))
end

local function build_request_uri(request)
    if not request then
        return ""
    end
    local path = request.path or ""
    local query = request.query or {}
    local qs = build_query(query)
    local uri = path
    if qs ~= "" then
        uri = uri .. "?" .. qs
    end
    local host = header_value(request.headers or {}, "host")
    if host and host ~= "" then
        uri = "http://" .. host .. uri
    end
    return uri
end

local function resolve_backend_url(mode, stream_cfg)
    if stream_cfg and mode == "play" and stream_cfg.on_play and stream_cfg.on_play ~= "" then
        return tostring(stream_cfg.on_play)
    end
    if stream_cfg and mode == "publish" and stream_cfg.on_publish and stream_cfg.on_publish ~= "" then
        return tostring(stream_cfg.on_publish)
    end
    if mode == "play" then
        return setting_string("auth_on_play_url", "")
    end
    if mode == "publish" then
        return setting_string("auth_on_publish_url", "")
    end
    return ""
end

local function is_auth_enabled(mode, stream_cfg, backend_url)
    if stream_cfg and stream_cfg.auth_enabled ~= nil then
        return normalize_bool(stream_cfg.auth_enabled, false)
    end
    return backend_url ~= nil and backend_url ~= ""
end

local function build_values(ctx)
    return {
        name = ctx.stream_id,
        stream = ctx.stream_id,
        ip = ctx.ip,
        proto = ctx.proto,
        token = ctx.token,
        user_agent = ctx.user_agent,
        ua = ctx.user_agent,
        referer = ctx.referer,
    }
end

local function session_from_cache(session_id)
    local entry = auth.cache[session_id]
    if not entry then
        return nil
    end
    if entry.expires_at and entry.expires_at <= now() then
        auth.cache[session_id] = nil
        return nil
    end
    return entry
end

local function prune_expired()
    local ts = now()
    for session_id, entry in pairs(auth.cache) do
        if entry.expires_at and entry.expires_at <= ts then
            auth.cache[session_id] = nil
        end
    end
end

local function add_inflight(session_id, cb)
    local inflight = auth.inflight[session_id]
    if inflight then
        table.insert(inflight.callbacks, cb)
        return true
    end
    auth.inflight[session_id] = { callbacks = { cb } }
    return false
end

local function flush_inflight(session_id, allowed, entry, reason)
    local inflight = auth.inflight[session_id]
    auth.inflight[session_id] = nil
    if not inflight then
        return
    end
    for _, cb in ipairs(inflight.callbacks) do
        cb(allowed, entry, reason)
    end
end

local function parse_backend_headers(headers)
    local out = {}
    if not headers then
        return out
    end
    out.duration = tonumber(headers["x-authduration"] or headers["x-auth-duration"] or "")
    out.user_id = headers["x-userid"] or headers["x-user-id"]
    out.max_sessions = tonumber(headers["x-max-sessions"] or "")
    local unique = headers["x-unique"]
    if unique ~= nil then
        unique = tostring(unique):lower()
        out.unique = (unique == "1" or unique == "true" or unique == "yes")
    end
    return out
end

local function filter_active_sessions(user_id)
    local items = {}
    local ts = now()
    for _, entry in pairs(auth.cache) do
        if entry.user_id and tostring(entry.user_id) == tostring(user_id)
            and entry.status == "ALLOW"
            and entry.expires_at
            and entry.expires_at > ts
        then
            table.insert(items, entry)
        end
    end
    table.sort(items, function(a, b)
        return (a.created_at or 0) < (b.created_at or 0)
    end)
    return items
end

local function kick_session(entry, deny_ttl, reason)
    if not entry then
        return
    end
    entry.status = "DENY"
    entry.expires_at = now() + deny_ttl
    entry.last_backend_error = reason or entry.last_backend_error
    if auth.on_kick then
        auth.on_kick(entry)
    end
end

local function enforce_limits(entry, opts)
    if not entry.user_id or not entry.max_sessions or entry.max_sessions < 1 then
        return true
    end
    local sessions = filter_active_sessions(entry.user_id)
    if #sessions < entry.max_sessions then
        return true
    end
    local policy = opts.overlimit_policy or "deny_new"
    if policy == "kick_oldest" then
        local over = (#sessions - entry.max_sessions) + 1
        for i = 1, over do
            kick_session(sessions[i], opts.deny_ttl, "overlimit_kick")
        end
        return true
    end
    return false
end

local function enforce_unique(entry, opts)
    if not entry.unique or not entry.user_id then
        return
    end
    local sessions = filter_active_sessions(entry.user_id)
    for _, item in ipairs(sessions) do
        if item.session_id ~= entry.session_id then
            kick_session(item, opts.deny_ttl, "unique_kick")
        end
    end
end

local function build_backend_request(url, params, method, body)
    local parsed = parse_url(url)
    if not parsed then
        return nil, "invalid backend url"
    end
    if parsed.format ~= "http" then
        return nil, "unsupported backend scheme"
    end
    local base_path, query = split_path_query(parsed.path or "/")
    local existing = parse_query_string(query)
    for k, v in pairs(params or {}) do
        existing[k] = tostring(v or "")
    end
    local qs = build_query(existing)
    local path = base_path
    if qs ~= "" then
        path = path .. "?" .. qs
    end

    local headers = {
        "Host: " .. tostring(parsed.host) .. ":" .. tostring(parsed.port),
        "Connection: close",
    }
    if body then
        table.insert(headers, "Content-Type: application/json")
        table.insert(headers, "Content-Length: " .. tostring(#body))
    end
    return {
        host = parsed.host,
        port = parsed.port,
        path = path,
        method = method,
        headers = headers,
        content = body,
        timeout = setting_number("auth_timeout_ms", 3000),
    }, nil
end

function auth.get_token(request)
    local token = extract_token_from_query(request)
    if token and token ~= "" then
        return token
    end
    local cookies = parse_cookie(request and request.headers or {})
    if cookies.astra_token and cookies.astra_token ~= "" then
        return cookies.astra_token
    end
    return nil
end

function auth.get_session_cookie(request)
    local cookies = parse_cookie(request and request.headers or {})
    return cookies.astra_session
end

function auth.get_hls_rewrite_enabled()
    return setting_bool("auth_hls_rewrite_token", true)
end

function auth.get_admin_bypass_enabled()
    return setting_bool("auth_admin_bypass_enabled", true)
end

function auth.rewrite_m3u8(content, token, session_id)
    if not content or content == "" then
        return content
    end
    if not token or token == "" then
        return content
    end
    local out = {}
    for line in content:gmatch("[^\r\n]+") do
        if line:sub(1, 1) == "#" then
            table.insert(out, line)
        elseif line ~= "" then
            local updated = update_query_param(line, "token", token)
            if session_id and session_id ~= "" then
                updated = update_query_param(updated, "session_id", session_id)
            end
            table.insert(out, updated)
        else
            table.insert(out, line)
        end
    end
    return table.concat(out, "\n") .. "\n"
end

function auth.attach_token_to_url(url, token)
    if not url or url == "" or not token or token == "" then
        return url
    end
    return update_query_param(url, "token", token)
end

function auth.register_client(session_id, server, client)
    if not session_id then
        return
    end
    local list = auth.clients[session_id]
    if not list then
        list = {}
        auth.clients[session_id] = list
    end
    table.insert(list, { server = server, client = client })
end

function auth.unregister_client(session_id, server, client)
    if not session_id then
        return
    end
    local list = auth.clients[session_id]
    if not list then
        return
    end
    local keep = {}
    for _, entry in ipairs(list) do
        if entry.server ~= server or entry.client ~= client then
            table.insert(keep, entry)
        end
    end
    if #keep == 0 then
        auth.clients[session_id] = nil
    else
        auth.clients[session_id] = keep
    end
end

local function create_entry(ctx, session_id, status, ttl, meta)
    local entry = session_from_cache(session_id) or {}
    entry.session_id = session_id
    entry.stream_id = ctx.stream_id
    entry.stream_name = ctx.stream_name
    entry.ip = ctx.ip
    entry.proto = ctx.proto
    entry.mode = ctx.mode
    entry.status = status
    entry.created_at = entry.created_at or now()
    entry.last_seen = now()
    entry.expires_at = now() + ttl
    entry.session_keys = ctx.session_keys
    entry.token_hash = ctx.token_hash
    entry.last_backend_ts = meta.last_backend_ts or entry.last_backend_ts
    entry.last_backend_code = meta.last_backend_code or entry.last_backend_code
    entry.last_backend_error = meta.last_backend_error or entry.last_backend_error
    entry.user_id = meta.user_id or entry.user_id
    entry.max_sessions = meta.max_sessions or entry.max_sessions
    entry.unique = meta.unique or entry.unique
    auth.cache[session_id] = entry
    return entry
end

local function handle_backend_result(ctx, session_id, response, backend_error, callback)
    local deny_ttl = setting_number("auth_deny_cache_sec", 180)
    local allow_ttl = setting_number("auth_default_duration_sec", 180)
    local grace_ttl = 30
    local overlimit_policy = setting_string("auth_overlimit_policy", "deny_new")
    local meta = {
        last_backend_ts = now(),
        last_backend_code = response and response.code or 0,
        last_backend_error = backend_error,
    }

    local existing = session_from_cache(session_id)

    if backend_error then
        if log then
            log.warning("[auth] backend error: " .. tostring(backend_error) ..
                " stream=" .. tostring(ctx.stream_id) .. " proto=" .. tostring(ctx.proto))
        end
        local reason = "backend_error"
        if existing and existing.status == "ALLOW" then
            local entry = create_entry(ctx, session_id, "ALLOW", grace_ttl, meta)
            callback(true, entry, reason)
            return
        end
        local entry = create_entry(ctx, session_id, "DENY", deny_ttl, meta)
        callback(false, entry, reason)
        return
    end

    if not response then
        local entry = create_entry(ctx, session_id, "DENY", deny_ttl, meta)
        callback(false, entry, "backend_no_response")
        return
    end

    if response.code == 200 then
        local headers = parse_backend_headers(response.headers or {})
        if headers.duration and headers.duration > 0 then
            allow_ttl = headers.duration
        end
        meta.user_id = headers.user_id
        meta.max_sessions = headers.max_sessions
        meta.unique = headers.unique

        local entry = create_entry(ctx, session_id, "ALLOW", allow_ttl, meta)
        local ok = enforce_limits(entry, {
            deny_ttl = deny_ttl,
            overlimit_policy = overlimit_policy,
        })
        if not ok then
            entry.status = "DENY"
            entry.expires_at = now() + deny_ttl
            if log then
                log.info("[auth] deny (overlimit) stream=" .. tostring(ctx.stream_id) ..
                    " proto=" .. tostring(ctx.proto))
            end
            callback(false, entry, "overlimit_deny")
            return
        end
        enforce_unique(entry, { deny_ttl = deny_ttl })
        if log then
            log.debug("[auth] allow stream=" .. tostring(ctx.stream_id) ..
                " proto=" .. tostring(ctx.proto))
        end
        callback(true, entry, "backend_allow")
        return
    end

    if response.code == 403 then
        local entry = create_entry(ctx, session_id, "DENY", deny_ttl, meta)
        if log then
            log.info("[auth] deny stream=" .. tostring(ctx.stream_id) ..
                " proto=" .. tostring(ctx.proto))
        end
        callback(false, entry, "backend_deny")
        return
    end

    if log then
        log.warning("[auth] backend error code: " .. tostring(response.code) ..
            " stream=" .. tostring(ctx.stream_id) .. " proto=" .. tostring(ctx.proto))
    end
    local entry = create_entry(ctx, session_id, "DENY", deny_ttl, meta)
    callback(false, entry, "backend_error_code")
end

local function should_log_backend_error(entry)
    local ts = now()
    if not entry.last_alert_ts or (ts - entry.last_alert_ts) > 30 then
        entry.last_alert_ts = ts
        return true
    end
    return false
end

local function check_backend(ctx, session_id, backend_url, callback)
    local params = {}
    if ctx.mode ~= "publish" then
        params = {
            name = ctx.stream_id or "",
            ip = ctx.ip or "",
            proto = ctx.proto or "",
            token = ctx.token or "",
            session_id = session_id,
            uri = ctx.uri or "",
            user_agent = ctx.user_agent or "",
            referer = ctx.referer or "",
        }
    end
    local method = (ctx.mode == "publish") and "POST" or "GET"
    local body = nil
    if ctx.mode == "publish" then
        body = json.encode({
            name = ctx.stream_id or "",
            ip = ctx.ip or "",
            proto = ctx.proto or "",
            token = ctx.token or "",
            session_id = session_id,
            uri = ctx.uri or "",
            user_agent = ctx.user_agent or "",
        })
    end

    local req, err = build_backend_request(backend_url, params, method, body)
    if not req then
        callback(false, nil, err or "backend_config_error")
        return
    end

    req.callback = function(self, response)
        local backend_error = nil
        if not response or not response.code then
            backend_error = "backend_no_response"
        elseif response.code == 0 then
            backend_error = response.message or "backend_timeout"
        elseif response.code >= 500 then
            backend_error = "backend_" .. tostring(response.code)
        end

        handle_backend_result(ctx, session_id, response, backend_error, callback)

        if backend_error and config and config.add_alert then
            local entry = session_from_cache(session_id) or { session_id = session_id }
            if should_log_backend_error(entry) then
                config.add_alert("ERROR", ctx.stream_id, "AUTH_BACKEND_DOWN",
                    "auth backend error: " .. tostring(backend_error), {
                        mode = ctx.mode,
                        backend = backend_url,
                        stream_id = ctx.stream_id,
                    })
            end
        end
    end

    http_request(req)
end

local function handle_cache_result(ctx, entry, callback)
    if not entry then
        callback(nil, nil, "cache_miss")
        return
    end
    entry.last_seen = now()
    if entry.status == "ALLOW" then
        callback(true, entry, "cache_allow")
    else
        callback(false, entry, "cache_deny")
    end
end

function auth.check(ctx, callback)
    if not ctx or type(callback) ~= "function" then
        return
    end

    prune_expired()

    local backend_url = resolve_backend_url(ctx.mode, ctx.stream_cfg)
    if not is_auth_enabled(ctx.mode, ctx.stream_cfg, backend_url) then
        callback(true, nil, "auth_disabled")
        return
    end

    if backend_url == nil or backend_url == "" then
        if log and ctx.stream_id then
            log.error("[auth] backend url missing for stream " .. tostring(ctx.stream_id))
        end
        callback(false, nil, "backend_missing")
        return
    end

    if ctx.request and auth.get_admin_bypass_enabled() then
        local session_token = auth.get_session_cookie(ctx.request)
        if session_token and config and config.get_session then
            local session = config.get_session(session_token)
            if session and config.get_user_by_id then
                local user = config.get_user_by_id(session.user_id)
                if user and tonumber(user.is_admin) == 1 then
                    callback(true, nil, "admin_bypass")
                    return
                end
            end
        end
    end

    local token = ctx.token
    if token == nil and ctx.request then
        token = auth.get_token(ctx.request)
    end
    ctx.token = token or ""

    local session_keys = parse_session_keys(ctx.session_keys or (ctx.stream_cfg and ctx.stream_cfg.session_keys))
    local algo = normalize_algo(setting_string("auth_hash_algo", "sha1"))
    local values = build_values(ctx)
    local session_id = make_session_id(session_keys, values, algo)
    ctx.session_id = session_id
    ctx.session_keys = table.concat(session_keys, ",")
    if ctx.token ~= "" then
        ctx.token_hash = hash_hex(algo, ctx.token)
    else
        ctx.token_hash = ""
    end

    local allow_no_token = setting_bool("auth_allow_no_token", false)
    if ctx.token == "" and not allow_no_token then
        local deny_ttl = setting_number("auth_deny_cache_sec", 180)
        local entry = create_entry(ctx, session_id, "DENY", deny_ttl, {
            last_backend_ts = now(),
            last_backend_code = 0,
            last_backend_error = "no_token",
        })
        if log then
            log.info("[auth] deny (no token) stream=" .. tostring(ctx.stream_id) ..
                " proto=" .. tostring(ctx.proto))
        end
        callback(false, entry, "no_token")
        return
    end

    local cached = session_from_cache(session_id)
    if cached then
        handle_cache_result(ctx, cached, callback)
        return
    end

    local already = add_inflight(session_id, function(allowed, entry, reason)
        callback(allowed, entry, reason)
    end)
    if already then
        return
    end

    check_backend(ctx, session_id, backend_url, function(allowed, entry, reason)
        flush_inflight(session_id, allowed, entry, reason)
    end)
end

function auth.check_play(ctx, callback)
    ctx.mode = "play"
    return auth.check(ctx, callback)
end

function auth.check_publish(ctx, callback)
    ctx.mode = "publish"
    return auth.check(ctx, callback)
end

function auth.list_sessions(opts)
    opts = opts or {}
    prune_expired()
    local items = {}
    local ts = now()
    local limit = tonumber(opts.limit) or 200
    if limit < 1 then
        limit = 1
    elseif limit > 1000 then
        limit = 1000
    end
    for _, entry in pairs(auth.cache) do
        if entry.expires_at and entry.expires_at > ts then
            if opts.stream_id and tostring(opts.stream_id) ~= tostring(entry.stream_id or "") then
                -- skip
            elseif opts.status and tostring(opts.status) ~= tostring(entry.status or "") then
                -- skip
            else
                table.insert(items, {
                    session_id = entry.session_id,
                    stream_id = entry.stream_id,
                    stream_name = entry.stream_name,
                    ip = entry.ip,
                    proto = entry.proto,
                    mode = entry.mode,
                    token_hash = entry.token_hash,
                    status = entry.status,
                    expires_at = entry.expires_at,
                    user_id = entry.user_id,
                    last_backend_ts = entry.last_backend_ts,
                    last_backend_code = entry.last_backend_code,
                    last_backend_error = entry.last_backend_error,
                })
            end
        end
    end
    table.sort(items, function(a, b)
        return (a.expires_at or 0) > (b.expires_at or 0)
    end)
    local out = {}
    for i = 1, math.min(limit, #items) do
        out[i] = items[i]
    end
    return out
end

function auth.count_sessions()
    local ts = now()
    local count = 0
    for _, entry in pairs(auth.cache) do
        if entry.expires_at and entry.expires_at > ts then
            count = count + 1
        end
    end
    return count
end

function auth.debug_session(params)
    params = params or {}
    local stream_id = params.stream_id
    if not stream_id or stream_id == "" then
        return nil, "stream_id required"
    end
    local stream_cfg = params.stream_cfg or {}
    local session_keys = parse_session_keys(stream_cfg.session_keys)
    local algo = normalize_algo(setting_string("auth_hash_algo", "sha1"))
    local values = {
        name = stream_id,
        ip = params.ip or "",
        proto = params.proto or "",
        token = params.token or "",
    }
    local session_id = make_session_id(session_keys, values, algo)
    local entry = session_from_cache(session_id)
    return {
        session_id = session_id,
        session_keys = table.concat(session_keys, ","),
        values = values,
        cached = entry,
    }
end

function auth.token_from_url(url)
    return extract_token_from_url(url)
end
