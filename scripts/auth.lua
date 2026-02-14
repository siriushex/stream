-- Token authorization backend (Flussonic-like)

auth = {
    cache = {},
    inflight = {},
    clients = {},
    stream_clients = {},
    total_clients = 0,
    backend_inflight = 0,
    recheck_timer = nil,
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

local function extract_token_from_query(request, token_param)
    if not request or not request.query then
        return nil
    end
    local query = request.query
    token_param = token_param or "token"

    local value = query[token_param]
    if value == nil and token_param ~= "token" then
        value = query.token
    end
    if value == nil then
        value = query.access_token
    end
    if value ~= nil and tostring(value) ~= "" then
        return tostring(value)
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
    local token = params.token or params.access_token
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

local function ip_to_u32(ip)
    if not ip or ip == "" then
        return nil
    end
    local a, b, c, d = tostring(ip):match("^(%d+)%.(%d+)%.(%d+)%.(%d+)$")
    a, b, c, d = tonumber(a), tonumber(b), tonumber(c), tonumber(d)
    if not a or not b or not c or not d then
        return nil
    end
    if a > 255 or b > 255 or c > 255 or d > 255 then
        return nil
    end
    return a * 16777216 + b * 65536 + c * 256 + d
end

local function cidr_match(ip, cidr)
    local base, mask = tostring(cidr or ""):match("^(.-)/(%d+)$")
    if not base or not mask then
        return false
    end
    local ip_num = ip_to_u32(ip)
    local base_num = ip_to_u32(base)
    local bits = tonumber(mask)
    if not ip_num or not base_num or not bits or bits < 0 or bits > 32 then
        return false
    end
    if bits == 0 then
        return true
    end
    local shift = 32 - bits
    local factor = 2 ^ shift
    return math.floor(ip_num / factor) == math.floor(base_num / factor)
end

local function list_items(value)
    if value == nil then
        return {}
    end
    if type(value) == "table" then
        local out = {}
        for _, item in ipairs(value) do
            if item ~= nil then
                local text = tostring(item)
                if text ~= "" then
                    out[#out + 1] = text
                end
            end
        end
        return out
    end
    local out = {}
    local text = tostring(value)
    for item in text:gmatch("[^,%s]+") do
        out[#out + 1] = item
    end
    return out
end

local function list_has_exact(list, value)
    if not value or value == "" then
        return false
    end
    for _, item in ipairs(list or {}) do
        if tostring(item) == tostring(value) then
            return true
        end
    end
    return false
end

local function list_has_ip(list, ip)
    if not ip or ip == "" then
        return false
    end
    for _, item in ipairs(list or {}) do
        local text = tostring(item)
        if text == tostring(ip) then
            return true
        end
        if text:find("/", 1, true) then
            if cidr_match(ip, text) then
                return true
            end
        end
    end
    return false
end

local function list_has_substring(list, value)
    if not value or value == "" then
        return false
    end
    local hay = tostring(value):lower()
    for _, item in ipairs(list or {}) do
        local needle = tostring(item):lower()
        if needle ~= "" and hay:find(needle, 1, true) ~= nil then
            return true
        end
    end
    return false
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

local function get_auth_backends_setting()
    if config and config.get_setting then
        local raw = config.get_setting("auth_backends")
        if type(raw) == "table" then
            return raw
        end
    end
    return {}
end

local function parse_auth_backend_ref(spec)
    if not spec or spec == "" then
        return nil
    end
    local text = tostring(spec)
    if text:find("auth://", 1, true) ~= 1 then
        return nil
    end
    local rest = text:sub(8)
    local name = rest:match("^([^%s/?#]+)")
    if not name or name == "" then
        return nil
    end
    return name
end

local function normalize_backend_list(value)
    if value == nil then
        return {}
    end
    if type(value) == "table" then
        local out = {}
        -- list of strings or objects {url,timeout_ms,params}
        for _, item in ipairs(value) do
            if type(item) == "string" and item ~= "" then
                out[#out + 1] = { url = item }
            elseif type(item) == "table" then
                local url = item.url or item.backend or item[1]
                if url ~= nil and tostring(url) ~= "" then
                    out[#out + 1] = {
                        url = tostring(url),
                        timeout_ms = tonumber(item.timeout_ms or item.timeout) or nil,
                        params = type(item.params) == "table" and item.params or nil,
                    }
                end
            end
        end
        return out
    end
    local out = {}
    local text = tostring(value or "")
    for part in text:gmatch("[^\r\n,%s]+") do
        if part ~= "" then
            out[#out + 1] = { url = part }
        end
    end
    return out
end

local function normalize_backend_mode(value)
    local mode = tostring(value or ""):lower()
    if mode == "sequential" or mode == "seq" then
        return "sequential"
    end
    return "parallel"
end

local function resolve_backend(mode, stream_cfg)
    local spec = ""
    if stream_cfg and mode == "play" and stream_cfg.on_play and stream_cfg.on_play ~= "" then
        spec = tostring(stream_cfg.on_play)
    elseif stream_cfg and mode == "publish" and stream_cfg.on_publish and stream_cfg.on_publish ~= "" then
        spec = tostring(stream_cfg.on_publish)
    elseif mode == "play" then
        spec = setting_string("auth_on_play_url", "")
    elseif mode == "publish" then
        spec = setting_string("auth_on_publish_url", "")
    end

    if spec == nil or spec == "" then
        return nil
    end

    local backend_name = parse_auth_backend_ref(spec)
    if backend_name then
        local backends = get_auth_backends_setting()
        local cfg = backends and backends[backend_name] or nil
        return {
            kind = "auth_backend",
            name = backend_name,
            cfg = cfg,
            spec = spec,
        }
    end

    -- direct URL backend (single or comma/newline separated list)
    return {
        kind = "http_backend",
        backends = normalize_backend_list(spec),
        spec = spec,
    }
end

local function is_auth_enabled(mode, stream_cfg, backend_desc)
    if stream_cfg and stream_cfg.auth_enabled ~= nil then
        return normalize_bool(stream_cfg.auth_enabled, false)
    end
    if not backend_desc then
        return false
    end
    if backend_desc.kind == "auth_backend" then
        return backend_desc.name ~= nil and backend_desc.name ~= ""
    end
    if backend_desc.kind == "http_backend" then
        return type(backend_desc.backends) == "table" and backend_desc.backends[1] ~= nil
    end
    return false
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

local function build_session_values(ctx, session_keys)
    local values = build_values(ctx)
    local request = ctx and ctx.request or nil
    local headers = (request and request.headers) or {}
    local query = (request and request.query) or {}
    local cookies = parse_cookie(headers)

    values.host = header_value(headers, "host") or ""
    values.referer = values.referer or header_value(headers, "referer") or ""
    values.user_agent = values.user_agent or header_value(headers, "user-agent") or ""
    values.ua = values.ua or values.user_agent
    values.country = header_value(headers, "cf-ipcountry")
        or header_value(headers, "x-country")
        or header_value(headers, "x-geo-country")
        or ""

    -- Поддержка session_keys в стиле Flussonic: header.* / query.* / cookie.*
    for _, key in ipairs(session_keys or {}) do
        if values[key] == nil then
            local kind, name = tostring(key):match("^(%w+)%.(.+)$")
            if kind and name then
                kind = kind:lower()
                if kind == "header" then
                    values[key] = header_value(headers, name) or ""
                elseif kind == "query" then
                    values[key] = query[name] or ""
                elseif kind == "cookie" then
                    values[key] = cookies[name] or ""
                end
            end
        end
    end

    return values
end

local function session_from_cache(session_id, opts)
    local entry = auth.cache[session_id]
    if not entry then
        return nil
    end
    local ts = now()
    local allow_stale = false
    local stale_grace = 0
    if opts and type(opts) == "table" then
        allow_stale = opts.allow_stale == true
        stale_grace = tonumber(opts.stale_grace_sec) or 0
    end
    if stale_grace <= 0 then
        stale_grace = setting_number("auth_stale_grace_sec", 30)
        if stale_grace == nil or stale_grace < 0 then
            stale_grace = 0
        end
    end
    entry._stale = nil
    if entry.expires_at and entry.expires_at <= ts then
        local keep_until = entry.expires_at + stale_grace
        if stale_grace > 0 and keep_until > ts then
            if allow_stale then
                entry._stale = true
                return entry
            end
            return nil
        end
        auth.cache[session_id] = nil
        return nil
    end
    return entry
end

local function prune_expired()
    local ts = now()
    local stale_grace = setting_number("auth_stale_grace_sec", 30)
    if stale_grace == nil or stale_grace < 0 then
        stale_grace = 0
    end
    for session_id, entry in pairs(auth.cache) do
        if entry.expires_at and entry.expires_at <= ts then
            local keep_until = entry.expires_at + stale_grace
            if stale_grace <= 0 or keep_until <= ts then
                auth.cache[session_id] = nil
            end
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

local function sanitize_header_part(value)
    local text = tostring(value or "")
    text = text:gsub("[\r\n]+", " ")
    text = text:gsub("^%s+", ""):gsub("%s+$", "")
    return text
end

local function build_backend_request(url, params, method, body, timeout_ms, extra_headers)
    local parsed = parse_url(url)
    if not parsed then
        return nil, "invalid backend url"
    end
    if parsed.format ~= "http" and parsed.format ~= "https" then
        return nil, "unsupported backend scheme"
    end
    if parsed.format == "https" and not (astra and astra.features and astra.features.ssl) then
        return nil, "https not supported (OpenSSL not available)"
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
    if type(extra_headers) == "table" then
        for k, v in pairs(extra_headers) do
            local name = sanitize_header_part(k)
            local value = sanitize_header_part(v)
            if name ~= "" and value ~= "" and not name:find(":", 1, true) then
                table.insert(headers, name .. ": " .. value)
            end
        end
    end
    if body then
        table.insert(headers, "Content-Type: application/json")
        table.insert(headers, "Content-Length: " .. tostring(#body))
    end
    return {
        host = parsed.host,
        port = parsed.port,
        path = path,
        method = method,
        ssl = (parsed.format == "https"),
        headers = headers,
        content = body,
        timeout = tonumber(timeout_ms) or setting_number("auth_timeout_ms", 3000),
    }, nil
end

local function split_kind_name(spec)
    local text = tostring(spec or "")
    text = text:gsub("^%s+", ""):gsub("%s+$", "")
    if text == "" then
        return "", ""
    end
    local kind, name = text:match("^(%w+)%s*:%s*(.+)$")
    if kind and name then
        return tostring(kind):lower(), tostring(name):gsub("^%s+", ""):gsub("%s+$", "")
    end
    return tostring(text):lower(), ""
end

local function token_from_header(headers, header_name)
    if not headers or not header_name or header_name == "" then
        return nil
    end
    local value = header_value(headers, header_name)
    if value == nil then
        return nil
    end
    local text = tostring(value):gsub("^%s+", ""):gsub("%s+$", "")
    if text == "" then
        return nil
    end
    local lower = text:lower()
    if lower:find("bearer ", 1, true) == 1 then
        return text:sub(8):gsub("^%s+", ""):gsub("%s+$", "")
    end
    if lower:find("token ", 1, true) == 1 then
        return text:sub(7):gsub("^%s+", ""):gsub("%s+$", "")
    end
    return text
end

-- Извлечение token из запроса.
-- По умолчанию (token_source пустой) сохраняем legacy поведение:
-- - query параметр (token/auth_token_param)
-- - cookie astra_token
--
-- Дополнительно поддерживаем совместимость с Flussonic-like:
--   token_source="auto" | "query:<name>" | "header:<name>" | "cookie:<name>".
function auth.get_token(request, token_param, token_source)
    token_param = token_param or "token"
    local kind, name = split_kind_name(token_source)

    -- legacy behavior: query + cookie astra_token
    if kind == "" then
        local token = extract_token_from_query(request, token_param)
        if token and token ~= "" then
            return token
        end
        local cookies = parse_cookie(request and request.headers or {})
        if cookies.astra_token and cookies.astra_token ~= "" then
            return cookies.astra_token
        end
        return nil
    end

    local headers = request and request.headers or {}
    local query = request and request.query or {}
    local cookies = parse_cookie(headers)

    if kind == "auto" then
        local token = extract_token_from_query(request, token_param)
        if token and token ~= "" then
            return token
        end
        token = token_from_header(headers, "authorization")
        if token and token ~= "" then
            return token
        end
        if cookies.astra_token and cookies.astra_token ~= "" then
            return cookies.astra_token
        end
        local cookie_by_param = cookies[token_param]
        if cookie_by_param and cookie_by_param ~= "" then
            return tostring(cookie_by_param)
        end
        local token_cookie = cookies.token or cookies.access_token
        if token_cookie and token_cookie ~= "" then
            return tostring(token_cookie)
        end
        return nil
    end

    if kind == "query" then
        local key = name ~= "" and name or token_param
        local value = query[key]
        if value ~= nil and tostring(value) ~= "" then
            return tostring(value)
        end
        -- совместимость: если явно просят query:token, используем старый fallback token/access_token
        if key == "token" or key == token_param then
            local token = extract_token_from_query(request, token_param)
            if token and token ~= "" then
                return token
            end
        end
        return nil
    end

    if kind == "header" then
        local header_name = name ~= "" and name or "authorization"
        local token = token_from_header(headers, header_name)
        if token and token ~= "" then
            return token
        end
        return nil
    end

    if kind == "cookie" then
        local cookie_name = name ~= "" and name or "astra_token"
        local value = cookies[cookie_name]
        if value ~= nil and tostring(value) ~= "" then
            return tostring(value)
        end
        return nil
    end

    -- unknown token_source -> legacy
    local token = extract_token_from_query(request, token_param)
    if token and token ~= "" then
        return token
    end
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
    auth.total_clients = math.max(0, (tonumber(auth.total_clients) or 0) + 1)
    local cached = auth.cache and auth.cache[session_id] or nil
    local stream_id = cached and cached.stream_id or nil
    if stream_id and stream_id ~= "" then
        local cur = tonumber(auth.stream_clients[stream_id] or 0) or 0
        auth.stream_clients[stream_id] = cur + 1
    end
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
    local removed = #list - #keep
    if #keep == 0 then
        auth.clients[session_id] = nil
    else
        auth.clients[session_id] = keep
    end
    if removed > 0 then
        auth.total_clients = math.max(0, (tonumber(auth.total_clients) or 0) - removed)
        local cached = auth.cache and auth.cache[session_id] or nil
        local stream_id = cached and cached.stream_id or nil
        if stream_id and stream_id ~= "" then
            local cur = tonumber(auth.stream_clients[stream_id] or 0) or 0
            cur = cur - removed
            if cur <= 0 then
                auth.stream_clients[stream_id] = nil
            else
                auth.stream_clients[stream_id] = cur
            end
        end
    end
end

-- Снимает все HTTP-клиенты сессии и корректирует счётчики.
-- Используется при "kick" (deny/update_session), чтобы не держать лишние ссылки.
function auth.drop_all_clients(session_id)
    if not session_id then
        return nil
    end
    local list = auth.clients[session_id]
    if not list then
        return nil
    end
    auth.clients[session_id] = nil
    local removed = #list
    if removed > 0 then
        auth.total_clients = math.max(0, (tonumber(auth.total_clients) or 0) - removed)
        local cached = auth.cache and auth.cache[session_id] or nil
        local stream_id = cached and cached.stream_id or nil
        if stream_id and stream_id ~= "" then
            local cur = tonumber(auth.stream_clients[stream_id] or 0) or 0
            cur = cur - removed
            if cur <= 0 then
                auth.stream_clients[stream_id] = nil
            else
                auth.stream_clients[stream_id] = cur
            end
        end
    end
    return list
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
    entry.opened_at = entry.opened_at or entry.created_at
    entry.last_seen = now()
    entry.expires_at = now() + ttl
    entry.session_keys = ctx.session_keys
    entry.token_hash = ctx.token_hash
    entry.user_agent = ctx.user_agent
    entry.referer = ctx.referer
    entry.host = ctx.host
    entry.country = ctx.country
    entry.playback_session_id = ctx.playback_session_id
    if status == "ALLOW" and ctx.token and ctx.token ~= "" then
        entry.token = ctx.token
    end
    entry.backend_spec = ctx.backend_spec or entry.backend_spec
    entry.backend_name = ctx.backend_name or entry.backend_name
    entry.redirect_location = meta.redirect_location or entry.redirect_location
    entry.request_number = meta.request_number or entry.request_number
    entry.last_backend_ts = meta.last_backend_ts or entry.last_backend_ts
    entry.last_backend_code = meta.last_backend_code or entry.last_backend_code
    entry.last_backend_error = meta.last_backend_error or entry.last_backend_error
    entry.user_id = meta.user_id or entry.user_id
    entry.max_sessions = meta.max_sessions or entry.max_sessions
    entry.unique = meta.unique or entry.unique
    auth.cache[session_id] = entry
    return entry
end

local function backend_defaults_for(ctx)
    local allow_ttl = setting_number("auth_default_duration_sec", 180)
    local deny_ttl = setting_number("auth_deny_cache_sec", 180)
    local allow_default = setting_bool("auth_allow_default", false)

    local cfg = ctx and ctx.backend_cfg or nil
    if type(cfg) == "table" then
        if cfg.fail_policy ~= nil and cfg.allow_default == nil then
            local fp = tostring(cfg.fail_policy or ""):lower()
            if fp == "open" then
                allow_default = true
            elseif fp == "closed" then
                allow_default = false
            end
        end
        if cfg.allow_default ~= nil then
            allow_default = normalize_bool(cfg.allow_default, allow_default)
        end
        if type(cfg.cache) == "table" then
            local a = tonumber(cfg.cache.default_allow_sec)
            local d = tonumber(cfg.cache.default_deny_sec)
            if a and a > 0 then
                allow_ttl = a
            end
            if d and d > 0 then
                deny_ttl = d
            end
        end
    end

    if ctx and ctx.allow_default_override ~= nil then
        allow_default = normalize_bool(ctx.allow_default_override, allow_default)
    end

    return allow_ttl, deny_ttl, allow_default
end

local function classify_backend_error(response)
    if not response or not response.code then
        return "backend_no_response"
    end
    if response.code == 0 then
        return response.message or "backend_timeout"
    end
    if response.code >= 500 then
        return "backend_" .. tostring(response.code)
    end
    return nil
end

local function rule_decision(ctx)
    local cfg = ctx and ctx.backend_cfg or nil
    if type(cfg) ~= "table" or type(cfg.rules) ~= "table" then
        return nil
    end
    local rules = cfg.rules
    local allow = type(rules.allow) == "table" and rules.allow or {}
    local deny = type(rules.deny) == "table" and rules.deny or {}

    local token = tostring(ctx.token or "")
    local ip = tostring(ctx.ip or "")
    local country = tostring(ctx.country or "")
    local ua = tostring(ctx.user_agent or "")

    -- Приоритет как в ТЗ (Flussonic-like):
    -- allow token -> deny token -> allow ip -> deny ip -> allow country -> deny country -> allow ua -> deny ua
    if list_has_exact(list_items(allow.token or allow.tokens), token) then
        return { decision = "ALLOW", reason = "rule_allow_token" }
    end
    if list_has_exact(list_items(deny.token or deny.tokens), token) then
        return { decision = "DENY", reason = "rule_deny_token" }
    end
    if list_has_ip(list_items(allow.ip or allow.ips), ip) then
        return { decision = "ALLOW", reason = "rule_allow_ip" }
    end
    if list_has_ip(list_items(deny.ip or deny.ips), ip) then
        return { decision = "DENY", reason = "rule_deny_ip" }
    end
    if list_has_exact(list_items(allow.country or allow.countries), country) then
        return { decision = "ALLOW", reason = "rule_allow_country" }
    end
    if list_has_exact(list_items(deny.country or deny.countries), country) then
        return { decision = "DENY", reason = "rule_deny_country" }
    end
    if list_has_substring(list_items(allow.ua or allow.user_agent or allow.user_agents), ua) then
        return { decision = "ALLOW", reason = "rule_allow_ua" }
    end
    if list_has_substring(list_items(deny.ua or deny.user_agent or deny.user_agents), ua) then
        return { decision = "DENY", reason = "rule_deny_ua" }
    end

    return nil
end

local function should_log_backend_error(entry)
    local ts = now()
    if not entry.last_alert_ts or (ts - entry.last_alert_ts) > 30 then
        entry.last_alert_ts = ts
        return true
    end
    return false
end

local function backend_location(headers)
    if not headers then
        return nil
    end
    return headers.location or headers.Location or headers["Location"] or headers["location"]
end

local function check_backend_one(ctx, session_id, backend, callback)
    local backend_url = backend and backend.url or nil
    if not backend_url or backend_url == "" then
        callback({ url = "", error = "backend_url_missing" })
        return
    end

    -- Защита от всплеска запросов (DDOS/шторм сегментов HLS).
    local max_inflight = setting_number("auth_backend_max_concurrency", 0)
    if max_inflight and max_inflight > 0 then
        local cur = tonumber(auth.backend_inflight or 0) or 0
        if cur >= max_inflight then
            callback({ url = backend_url, error = "backend_overload" })
            return
        end
    end

    local request_type = tostring(ctx.request_type or "open_session")
    local request_number = tonumber(ctx.request_number) or 1

    local params = {}
    local method = (ctx.mode == "publish") and "POST" or "GET"
    local body = nil

    if ctx.mode ~= "publish" then
        params = {
            name = ctx.stream_id or "",
            ip = ctx.ip or "",
            proto = ctx.proto or "",
            token = ctx.token or "",
            session_id = session_id,
            request_type = request_type,
            request_number = request_number,
            stream_clients = tonumber(ctx.stream_clients) or 0,
            total_clients = tonumber(ctx.total_clients) or 0,
            duration = tonumber(ctx.duration_sec) or 0,
            bytes = tonumber(ctx.bytes) or 0,
            qs = ctx.qs or "",
            uri = ctx.uri or "",
            host = ctx.host or "",
            user_agent = ctx.user_agent or "",
            referer = ctx.referer or "",
            dvr = ctx.dvr == true and "1" or "0",
            playback_session_id = ctx.playback_session_id or "",
        }
        local static_params = backend.params or backend.static_params
        if type(static_params) == "table" then
            for k, v in pairs(static_params) do
                params[k] = tostring(v or "")
            end
        end
    else
        body = json.encode({
            name = ctx.stream_id or "",
            ip = ctx.ip or "",
            proto = ctx.proto or "",
            token = ctx.token or "",
            session_id = session_id,
            request_type = request_type,
            request_number = request_number,
            uri = ctx.uri or "",
            user_agent = ctx.user_agent or "",
        })
    end

    local cfg = ctx and ctx.backend_cfg or nil
    local cfg_timeout = type(cfg) == "table" and tonumber(cfg.timeout_ms) or nil
    local cfg_total_timeout = type(cfg) == "table" and tonumber(cfg.total_timeout_ms) or nil
    local timeout_ms = tonumber(backend.timeout_ms or backend.timeout) or cfg_timeout or nil
    local total_timeout_ms = cfg_total_timeout
    if total_timeout_ms and total_timeout_ms > 0 then
        if not timeout_ms or timeout_ms > total_timeout_ms then
            timeout_ms = total_timeout_ms
        end
    end
    local extra_headers = backend.static_headers or backend.headers

    local req, err = build_backend_request(backend_url, params, method, body, timeout_ms, extra_headers)
    if not req then
        callback({ url = backend_url, error = err or "backend_config_error" })
        return
    end

    auth.backend_inflight = math.max(0, (tonumber(auth.backend_inflight) or 0) + 1)
    req.callback = function(self, response)
        auth.backend_inflight = math.max(0, (tonumber(auth.backend_inflight) or 1) - 1)
        local backend_error = classify_backend_error(response)
        callback({
            url = backend_url,
            response = response,
            error = backend_error,
            location = response and backend_location(response.headers or {}) or nil,
        })
    end

    http_request(req)
end

local function check_backend_group_parallel(ctx, session_id, backends, callback)
    local pending = #backends
    local done = false
    local results = {}

    local function finish()
        if done then
            return
        end
        done = true

        local allow_res = nil
        local redirect_res = nil
        local deny_res = nil
        local all_error = true

        for _, res in ipairs(results) do
            if res and res.response and res.response.code then
                local code = tonumber(res.response.code) or 0
                if code == 200 then
                    allow_res = allow_res or res
                    all_error = false
                elseif code == 302 and res.location and res.location ~= "" then
                    redirect_res = redirect_res or res
                    all_error = false
                elseif code >= 400 and code < 500 then
                    deny_res = deny_res or res
                    all_error = false
                elseif code > 0 then
                    all_error = false
                end
            end
            if res and res.error == nil and res.response ~= nil and res.response.code ~= nil and res.response.code ~= 0 and res.response.code < 500 then
                all_error = false
            end
        end

        if redirect_res then
            callback({ decision = "REDIRECT", chosen = redirect_res, reason = "backend_redirect" })
            return
        end
        if allow_res then
            callback({ decision = "ALLOW", chosen = allow_res, reason = "backend_allow" })
            return
        end
        if deny_res then
            callback({ decision = "DENY", chosen = deny_res, reason = "backend_deny" })
            return
        end

        local allow_ttl, deny_ttl, allow_default = backend_defaults_for(ctx)
        if all_error then
            callback({
                decision = allow_default and "ALLOW_DEFAULT" or "DENY_DEFAULT",
                reason = "backend_down",
                allow_ttl = allow_ttl,
                deny_ttl = deny_ttl,
            })
            return
        end

        callback({ decision = "DENY", reason = "backend_error_code" })
    end

    for _, backend in ipairs(backends) do
        check_backend_one(ctx, session_id, backend, function(res)
            if done then
                return
            end
            table.insert(results, res)
            pending = pending - 1

            -- allow/redirect can finish early (deny must wait for possible allow).
            if res and res.response and tonumber(res.response.code) == 200 then
                finish()
                return
            end
            if res and res.response and tonumber(res.response.code) == 302 and res.location and res.location ~= "" then
                finish()
                return
            end

            if pending <= 0 then
                finish()
            end
        end)
    end
end

local function check_backend_group_sequential(ctx, session_id, backends, callback)
    local index = 1
    local results = {}
    local saw_4xx = false

    local function finalize()
        local all_error = true
        for _, res in ipairs(results) do
            if res and res.response and res.response.code then
                local code = tonumber(res.response.code) or 0
                if code > 0 and code < 500 then
                    all_error = false
                elseif code >= 500 then
                    -- keep all_error=true unless we saw something else
                end
            end
            if res and res.error == nil and res.response ~= nil and res.response.code ~= nil and res.response.code ~= 0 and res.response.code < 500 then
                all_error = false
            end
        end

        if saw_4xx then
            callback({ decision = "DENY", reason = "backend_deny" })
            return
        end

        local allow_ttl, deny_ttl, allow_default = backend_defaults_for(ctx)
        if all_error then
            callback({
                decision = allow_default and "ALLOW_DEFAULT" or "DENY_DEFAULT",
                reason = "backend_down",
                allow_ttl = allow_ttl,
                deny_ttl = deny_ttl,
            })
            return
        end

        callback({ decision = "DENY", reason = "backend_error_code" })
    end

    local function next()
        if index > #backends then
            finalize()
            return
        end
        local backend = backends[index]
        index = index + 1
        check_backend_one(ctx, session_id, backend, function(res)
            table.insert(results, res)
            if res and res.response and res.response.code then
                local code = tonumber(res.response.code) or 0
                if code == 200 then
                    callback({ decision = "ALLOW", chosen = res, reason = "backend_allow" })
                    return
                end
                if code == 302 and res.location and res.location ~= "" then
                    callback({ decision = "REDIRECT", chosen = res, reason = "backend_redirect" })
                    return
                end
                if code >= 400 and code < 500 then
                    -- 401/403 в sequential не "блокируют" сразу: пробуем следующий портал.
                    saw_4xx = true
                    next()
                    return
                end
            end
            -- timeout/5xx/invalid -> пробуем следующий
            next()
        end)
    end

    next()
end

local function check_backend_group(ctx, session_id, backend_desc, callback)
    local backends = {}
    local mode = "parallel"
    if backend_desc and backend_desc.kind == "auth_backend" then
        ctx.backend_cfg = backend_desc.cfg
        local cfg = backend_desc.cfg
        if type(cfg) == "table" then
            backends = normalize_backend_list(cfg.backends)
            mode = normalize_backend_mode(cfg.mode or cfg.backend_mode)
        end
    elseif backend_desc and backend_desc.kind == "http_backend" then
        backends = backend_desc.backends or {}
    end

    if ctx and ctx.backend_mode ~= nil then
        mode = normalize_backend_mode(ctx.backend_mode)
    end

    if type(backends) ~= "table" or backends[1] == nil then
        callback({ decision = "DENY", reason = "backend_missing" })
        return
    end

    if mode == "sequential" then
        return check_backend_group_sequential(ctx, session_id, backends, callback)
    end
    return check_backend_group_parallel(ctx, session_id, backends, callback)
end

local function handle_cache_result(ctx, entry, callback)
    if not entry then
        callback(nil, nil, "cache_miss")
        return
    end
    entry.last_seen = now()
    if entry.status == "ALLOW" then
        callback(true, entry, "cache_allow")
    elseif entry.redirect_location and entry.redirect_location ~= "" then
        callback(false, entry, "cache_redirect")
    else
        callback(false, entry, "cache_deny")
    end
end

function auth.check(ctx, callback)
    if not ctx or type(callback) ~= "function" then
        return
    end

    prune_expired()

    local backend_desc = resolve_backend(ctx.mode, ctx.stream_cfg)
    ctx.backend_desc = backend_desc
    if backend_desc and backend_desc.kind == "auth_backend" then
        ctx.backend_name = backend_desc.name
        ctx.backend_spec = backend_desc.spec
        ctx.backend_cfg = backend_desc.cfg
    elseif backend_desc then
        ctx.backend_spec = backend_desc.spec
    end

    -- Per-stream override: allow_default (optional, fail-open when all backends are down).
    if ctx.allow_default_override == nil and ctx.stream_cfg then
        ctx.allow_default_override = ctx.stream_cfg.allow_default_override
        if ctx.allow_default_override == nil then
            ctx.allow_default_override = ctx.stream_cfg.auth_allow_default
        end
    end

    if not is_auth_enabled(ctx.mode, ctx.stream_cfg, backend_desc) then
        callback(true, nil, "auth_disabled")
        return
    end

    if backend_desc and backend_desc.kind == "auth_backend" and type(ctx.backend_cfg) ~= "table" then
        if log then
            log.error("[auth] backend '" .. tostring(ctx.backend_name) .. "' is not configured (settings.auth_backends)")
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
        local token_param = ctx.token_param
            or (ctx.stream_cfg and (ctx.stream_cfg.token_param or ctx.stream_cfg.auth_token_param))
            or setting_string("auth_token_param", "token")
        ctx.token_param = token_param
        local token_source = ctx.token_source
            or (ctx.stream_cfg and (ctx.stream_cfg.token_source or ctx.stream_cfg.auth_token_source))
            or setting_string("auth_token_source", "")
        ctx.token_source = token_source
        token = auth.get_token(ctx.request, token_param, token_source)
    end
    ctx.token = token or ""

    local request = ctx.request
    local headers = request and request.headers or {}
    ctx.user_agent = ctx.user_agent or header_value(headers, "user-agent") or ""
    ctx.referer = ctx.referer or header_value(headers, "referer") or ""
    ctx.host = ctx.host or header_value(headers, "host") or ""
    ctx.country = ctx.country
        or header_value(headers, "cf-ipcountry")
        or header_value(headers, "x-country")
        or header_value(headers, "x-geo-country")
        or ""
    ctx.playback_session_id = ctx.playback_session_id
        or header_value(headers, "x-playback-session-id")
        or header_value(headers, "x_playback_session_id")
        or ""
    ctx.qs = ctx.qs or build_query(request and request.query or {})

    local session_keys_source = ctx.session_keys or (ctx.stream_cfg and ctx.stream_cfg.session_keys)
    if session_keys_source == nil and type(ctx.backend_cfg) == "table" and ctx.backend_cfg.session_keys_default ~= nil then
        session_keys_source = ctx.backend_cfg.session_keys_default
    end
    local session_keys = parse_session_keys(session_keys_source)
    local algo = normalize_algo(setting_string("auth_hash_algo", "sha1"))
    local values = build_session_values(ctx, session_keys)
    local session_id = make_session_id(session_keys, values, algo)
    ctx.session_id = session_id
    ctx.session_keys = table.concat(session_keys, ",")
    if ctx.token ~= "" then
        ctx.token_hash = hash_hex(algo, ctx.token)
    else
        ctx.token_hash = ""
    end

    -- Счётчики сессий/клиентов для порталов.
    ctx.total_clients = tonumber(auth.total_clients) or 0
    ctx.stream_clients = tonumber(auth.stream_clients[ctx.stream_id] or 0) or 0

    -- Rules (allow/deny) can bypass token requirement.
    local allow_ttl, deny_ttl, allow_default = backend_defaults_for(ctx)
    local rule = rule_decision(ctx)
    if rule and rule.decision == "ALLOW" then
        local entry = create_entry(ctx, session_id, "ALLOW", allow_ttl, {
            last_backend_ts = now(),
            last_backend_code = 0,
            last_backend_error = rule.reason,
        })
        callback(true, entry, rule.reason)
        return
    elseif rule and rule.decision == "DENY" then
        local entry = create_entry(ctx, session_id, "DENY", deny_ttl, {
            last_backend_ts = now(),
            last_backend_code = 0,
            last_backend_error = rule.reason,
        })
        callback(false, entry, rule.reason)
        return
    end

    local allow_no_token = setting_bool("auth_allow_no_token", false)
    if ctx.token == "" and not allow_no_token then
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

    -- Если запись протухла недавно, сохраняем "прошлое решение" и делаем update_session вместо open_session.
    local stale_entry = session_from_cache(session_id, { allow_stale = true })

    local already = add_inflight(session_id, function(allowed, entry, reason)
        callback(allowed, entry, reason)
    end)
    if already then
        return
    end

    if stale_entry and stale_entry._stale == true then
        ctx.request_type = "update_session"
        ctx.request_number = (tonumber(stale_entry.request_number) or 0) + 1
        if stale_entry.opened_at then
            ctx.duration_sec = now() - tonumber(stale_entry.opened_at or 0)
        end
    else
        -- First backend check opens the session.
        ctx.request_type = "open_session"
        ctx.request_number = 1
    end

    check_backend_group(ctx, session_id, backend_desc, function(result)
        local grace_ttl = 30
        local overlimit_policy = setting_string("auth_overlimit_policy", "deny_new")

        local meta = {
            last_backend_ts = now(),
            last_backend_code = 0,
            last_backend_error = result and result.reason or nil,
            request_number = tonumber(ctx.request_number) or 1,
        }

        local existing = stale_entry and stale_entry._stale == true and stale_entry or nil

        local function finish(allowed, entry, reason)
            flush_inflight(session_id, allowed, entry, reason)
        end

        if not result then
            local entry = create_entry(ctx, session_id, "DENY", deny_ttl, meta)
            finish(false, entry, "backend_no_response")
            return
        end

        local decision = tostring(result.decision or "DENY")
        local chosen = result.chosen

        if chosen and chosen.response and chosen.response.code then
            meta.last_backend_code = tonumber(chosen.response.code) or 0
            meta.last_backend_error = chosen.error or meta.last_backend_error
        end

        if decision == "REDIRECT" and chosen and chosen.location and chosen.location ~= "" then
            meta.redirect_location = tostring(chosen.location)
            local entry = create_entry(ctx, session_id, "DENY", allow_ttl, meta)
            finish(false, entry, "backend_redirect")
            return
        end

        if decision == "ALLOW" and chosen and chosen.response and tonumber(chosen.response.code) == 200 then
            local headers = parse_backend_headers(chosen.response.headers or {})
            local ttl = allow_ttl
            if headers.duration and headers.duration > 0 then
                ttl = headers.duration
            end
            meta.user_id = headers.user_id
            meta.max_sessions = headers.max_sessions
            meta.unique = headers.unique
            local entry = create_entry(ctx, session_id, "ALLOW", ttl, meta)

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
                finish(false, entry, "overlimit_deny")
                return
            end
            enforce_unique(entry, { deny_ttl = deny_ttl })
            finish(true, entry, "backend_allow")
            return
        end

        if decision == "ALLOW_DEFAULT" then
            local entry = create_entry(ctx, session_id, "ALLOW", allow_ttl, meta)
            finish(true, entry, "backend_default_allow")
            return
        end

        if decision == "DENY_DEFAULT" and existing and existing.status == "ALLOW" then
            local entry = create_entry(ctx, session_id, "ALLOW", grace_ttl, meta)
            finish(true, entry, "backend_grace_allow")
            return
        end

        -- DENY (explicit) or default deny.
        local entry = create_entry(ctx, session_id, "DENY", deny_ttl, meta)

        -- Backend health alerts (rate-limited per session).
        if (decision == "DENY_DEFAULT" or decision == "ALLOW_DEFAULT") and config and config.add_alert then
            if should_log_backend_error(entry) then
                config.add_alert("ERROR", ctx.stream_id, "AUTH_BACKEND_DOWN",
                    "auth backend down (" .. tostring(ctx.backend_spec or "") .. ")", {
                        mode = ctx.mode,
                        backend = ctx.backend_spec,
                        stream_id = ctx.stream_id,
                    })
            end
        end

        finish(false, entry, result.reason or "backend_deny")
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

local function backend_desc_for_cached_entry(entry)
    if not entry then
        return nil
    end
    local name = entry.backend_name
    local spec = entry.backend_spec
    if (not name or name == "") and spec and spec ~= "" then
        name = parse_auth_backend_ref(spec)
    end
    if name and name ~= "" then
        local backends = get_auth_backends_setting()
        local cfg = backends and backends[name] or nil
        return {
            kind = "auth_backend",
            name = name,
            cfg = cfg,
            spec = "auth://" .. tostring(name),
        }
    end
    if spec and spec ~= "" then
        return {
            kind = "http_backend",
            backends = normalize_backend_list(spec),
            spec = spec,
        }
    end
    return nil
end

local function recheck_cached_entry(entry)
    if not entry or not entry.session_id then
        return
    end
    local session_id = entry.session_id
    local backend_desc = backend_desc_for_cached_entry(entry)
    if not backend_desc then
        return
    end
    if backend_desc.kind == "auth_backend" and type(backend_desc.cfg) ~= "table" then
        -- backend удалён из настроек: не рушим текущий поток, просто не перепроверяем.
        return
    end

    local ctx = {
        mode = entry.mode or "play",
        stream_id = entry.stream_id or "",
        stream_name = entry.stream_name or entry.stream_id or "",
        ip = entry.ip or "",
        proto = entry.proto or "",
        token = entry.token or "",
        token_hash = entry.token_hash or "",
        session_id = session_id,
        session_keys = entry.session_keys or "",
        backend_spec = entry.backend_spec,
        backend_name = entry.backend_name,
        user_agent = entry.user_agent or "",
        referer = entry.referer or "",
        host = entry.host or "",
        country = entry.country or "",
        playback_session_id = entry.playback_session_id or "",
        qs = "",
        uri = "",
        dvr = false,
        request_type = "update_session",
        request_number = (tonumber(entry.request_number) or 0) + 1,
        total_clients = tonumber(auth.total_clients) or 0,
        stream_clients = tonumber(auth.stream_clients[entry.stream_id] or 0) or 0,
        duration_sec = entry.opened_at and (now() - tonumber(entry.opened_at or 0)) or 0,
        bytes = tonumber(entry.bytes) or 0,
    }

    local already = add_inflight(session_id, function(allowed, updated, reason)
        if allowed then
            return
        end
        -- Если portal запретил во время update_session — закрываем клиентов.
        if updated and updated.status == "DENY" and auth.on_kick then
            auth.on_kick(updated)
        end
    end)
    if already then
        return
    end

    check_backend_group(ctx, session_id, backend_desc, function(result)
        local grace_ttl = 30
        local allow_ttl, deny_ttl, _ = backend_defaults_for(ctx)

        local meta = {
            last_backend_ts = now(),
            last_backend_code = 0,
            last_backend_error = result and result.reason or nil,
            request_number = tonumber(ctx.request_number) or 1,
        }

        local function finish(allowed, updated, reason)
            flush_inflight(session_id, allowed, updated, reason)
        end

        if not result then
            local updated = create_entry(ctx, session_id, "DENY", deny_ttl, meta)
            finish(false, updated, "backend_no_response")
            return
        end

        local decision = tostring(result.decision or "DENY")
        local chosen = result.chosen
        if chosen and chosen.response and chosen.response.code then
            meta.last_backend_code = tonumber(chosen.response.code) or 0
            meta.last_backend_error = chosen.error or meta.last_backend_error
        end

        if decision == "REDIRECT" and chosen and chosen.location and chosen.location ~= "" then
            meta.redirect_location = tostring(chosen.location)
            local updated = create_entry(ctx, session_id, "DENY", deny_ttl, meta)
            finish(false, updated, "backend_redirect")
            return
        end

        if decision == "ALLOW" and chosen and chosen.response and tonumber(chosen.response.code) == 200 then
            local headers = parse_backend_headers(chosen.response.headers or {})
            local ttl = allow_ttl
            if headers.duration and headers.duration > 0 then
                ttl = headers.duration
            end
            meta.user_id = headers.user_id
            meta.max_sessions = headers.max_sessions
            meta.unique = headers.unique
            local updated = create_entry(ctx, session_id, "ALLOW", ttl, meta)
            finish(true, updated, "backend_allow")
            return
        end

        if decision == "ALLOW_DEFAULT" then
            local updated = create_entry(ctx, session_id, "ALLOW", allow_ttl, meta)
            finish(true, updated, "backend_default_allow")
            return
        end

        if decision == "DENY_DEFAULT" and entry.status == "ALLOW" then
            -- backend недоступен: держим прошлое решение и попробуем снова чуть позже.
            local updated = create_entry(ctx, session_id, "ALLOW", grace_ttl, meta)
            finish(true, updated, "backend_grace_allow")
            return
        end

        local updated = create_entry(ctx, session_id, "DENY", deny_ttl, meta)
        finish(false, updated, "backend_deny")
    end)
end

function auth.recheck_tick()
    local interval = setting_number("auth_recheck_interval_sec", 0) or 0
    if interval <= 0 then
        return
    end
    prune_expired()

    local max_per_tick = setting_number("auth_recheck_max_per_tick", 20)
    if not max_per_tick or max_per_tick < 1 then
        max_per_tick = 1
    elseif max_per_tick > 200 then
        max_per_tick = 200
    end

    local ahead = setting_number("auth_recheck_ahead_sec", 5)
    if not ahead or ahead < 0 then
        ahead = 0
    end
    local ts = now()

    local processed = 0
    for _, entry in pairs(auth.cache) do
        if processed >= max_per_tick then
            break
        end
        if entry and entry.status == "ALLOW" and entry.expires_at then
            local session_id = entry.session_id
            local has_clients = session_id and auth.clients and auth.clients[session_id] ~= nil
            if has_clients and (tonumber(entry.expires_at) or 0) <= (ts + ahead) then
                processed = processed + 1
                recheck_cached_entry(entry)
            end
        end
    end
end

function auth.configure_recheck_timer()
    local interval = setting_number("auth_recheck_interval_sec", 0) or 0
    if auth.recheck_timer and type(auth.recheck_timer) == "table" and auth.recheck_timer.close then
        auth.recheck_timer:close()
        auth.recheck_timer = nil
    end
    if interval <= 0 then
        return
    end
    auth.recheck_timer = timer({
        interval = interval,
        callback = function()
            auth.recheck_tick()
        end,
    })
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

-- Автоконфигурация таймера перепроверки.
-- По умолчанию выключено (auth_recheck_interval_sec=0), поэтому на поведение не влияет.
if type(timer) == "function" and auth and auth.configure_recheck_timer then
    pcall(function()
        auth.configure_recheck_timer()
    end)
end
