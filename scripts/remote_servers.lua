-- Remote server adapters for Stream/Astra APIs.
--
-- Exposes unified async operations:
--   probe, list_streams, get_stream, upsert_stream, delete_stream, action
--
-- Callback contract:
--   cb(ok, payload_or_nil, error_message_or_nil, status_code_or_nil)

local remote_servers = {}

local function safe_tostring(value)
    if value == nil then
        return ""
    end
    return tostring(value)
end

local function trim(value)
    return safe_tostring(value):gsub("^%s+", ""):gsub("%s+$", "")
end

local function boolish(value, fallback)
    if value == nil then
        return fallback
    end
    if value == true or value == 1 or value == "1" then
        return true
    end
    if value == false or value == 0 or value == "0" then
        return false
    end
    if type(value) == "string" then
        local v = value:lower()
        if v == "true" or v == "yes" or v == "on" then
            return true
        end
        if v == "false" or v == "no" or v == "off" then
            return false
        end
    end
    return fallback
end

local function decode_json_safe(text)
    if not text or text == "" then
        return nil
    end
    local ok, data = pcall(json.decode, text)
    if not ok then
        return nil
    end
    return data
end

local function extract_error_text(payload)
    local text = ""
    if type(payload) == "table" then
        local candidate = payload.error
            or payload.message
            or payload.detail
            or payload.reason
        if candidate ~= nil then
            text = tostring(candidate)
        end
    elseif payload ~= nil then
        text = tostring(payload)
    end
    return trim(text:gsub("%s+", " "))
end

local function classify_error_status(message, fallback_code)
    local status = tonumber(fallback_code) or 400
    local text = tostring(message or ""):lower()
    local parsed = tonumber(text:match("http%s+(%d%d%d)"))
    if parsed then
        status = parsed
    end
    if text:find("forbidden", 1, true) then
        return 403
    end
    if text:find("unauthorized", 1, true)
        or text:find("login/password incorrect", 1, true)
    then
        -- Remote auth failures must not trigger local UI unauthorized flow.
        -- Return 403 consistently for "servers/*" actions.
        return 403
    end
    if text:find("no response", 1, true)
        or text:find("timeout", 1, true)
        or text:find("connection", 1, true)
        or text:find("network", 1, true)
        or text:find("dns", 1, true)
    then
        return 502
    end
    if status == 408 or status == 429 or status >= 500 then
        return 502
    end
    if status >= 400 and status < 500 then
        return status
    end
    return 400
end

local function is_auth_error(status_or_message)
    local status = tonumber(status_or_message)
    if status == 401 or status == 403 then
        return true
    end
    local text = tostring(status_or_message or ""):lower()
    return text:find("http 401", 1, true) ~= nil
        or text:find("http 403", 1, true) ~= nil
        or text:find("unauthorized", 1, true) ~= nil
        or text:find("forbidden", 1, true) ~= nil
end

local function is_adapter_unavailable_error(message)
    local text = tostring(message or ""):lower()
    return text:find("http_request unavailable", 1, true) ~= nil
        or text:find("cesbo api client unavailable", 1, true) ~= nil
end

local function parse_cookie_from_headers(headers)
    if type(headers) ~= "table" then
        return nil
    end
    local raw = headers["set-cookie"] or headers["Set-Cookie"]
    if not raw then
        return nil
    end
    local token = tostring(raw):match("stream_session=([^;]+)")
    if token and token ~= "" then
        return "stream_session=" .. token
    end
    token = tostring(raw):match("astra_session=([^;]+)")
    if token and token ~= "" then
        return "astra_session=" .. token
    end
    return nil
end

local function build_path(cfg, path)
    local base = cfg.base_path or ""
    if base == "" then
        return path
    end
    return base .. path
end

local function normalize_api_type(value)
    local v = trim(value):lower()
    if v == "" then
        return "auto"
    end
    if v == "auto" then
        return "auto"
    end
    if v == "stream_v1" or v == "stream-v1" or v == "stream" or v == "streamer" then
        return "stream_v1"
    end
    if v == "astra_legacy" or v == "astra-legacy" or v == "astra" or v == "legacy" then
        return "astra_legacy"
    end
    return "auto"
end

local function pick_login(entry)
    local login = trim(entry and entry.login or "")
    if login ~= "" then
        return login
    end
    local user = trim(entry and entry.user or "")
    if user ~= "" then
        return user
    end
    if entry and entry.login ~= nil then
        return trim(entry.login)
    end
    if entry and entry.user ~= nil then
        return trim(entry.user)
    end
    return ""
end

local function pick_password(entry)
    if type(entry) ~= "table" then
        return ""
    end
    local password = safe_tostring(entry.password)
    if password ~= "" then
        return password
    end
    local pass = safe_tostring(entry.pass)
    if pass ~= "" then
        return pass
    end
    -- Keep explicit empty override support when both fields are explicitly empty.
    if entry.password ~= nil then
        return safe_tostring(entry.password)
    end
    if entry.pass ~= nil then
        return safe_tostring(entry.pass)
    end
    return ""
end

function remote_servers.normalize(entry)
    if type(entry) ~= "table" then
        return nil, "invalid server"
    end

    local host = trim(entry.host or entry.address or "")
    if host == "" then
        return nil, "server host required"
    end

    local parsed = nil
    if host:find("://", 1, true) then
        parsed = parse_url(host)
        if not parsed then
            return nil, "invalid server url"
        end
    end

    local host_only = host
    local base_path_hint = nil
    local port_hint = nil
    if not parsed then
        local host_part, path_part = host:match("^([^/]+)(/.*)$")
        if host_part and path_part then
            host_only = host_part
            base_path_hint = path_part
        end
        local maybe_host, maybe_port = host_only:match("^(.-):(%d+)$")
        if maybe_host and maybe_port then
            host_only = maybe_host
            port_hint = tonumber(maybe_port)
        end
    end

    local scheme = parsed and parsed.format or "http"
    if scheme ~= "http" and scheme ~= "https" then
        return nil, "unsupported scheme"
    end

    local base_path = parsed and parsed.path or base_path_hint or ""
    if base_path == "/" then
        base_path = ""
    end
    if base_path ~= "" then
        base_path = base_path:gsub("/+$", "")
        if base_path == "/" then
            base_path = ""
        end
    end

    local port = tonumber(entry.port) or port_hint or (parsed and parsed.port) or (scheme == "https" and 443 or 8000)
    local insecure = boolish(entry.insecure, false)
        or boolish(entry.tls_insecure, false)

    local api_type = normalize_api_type(entry.api_type or entry.type)

    local cfg = {
        id = trim(entry.id),
        name = trim(entry.name),
        host = parsed and parsed.host or host_only,
        port = port,
        login = pick_login(entry),
        password = pick_password(entry),
        scheme = scheme,
        base_path = base_path,
        insecure = insecure == true,
        api_type = api_type,
        connect_timeout_ms = tonumber(entry.connect_timeout_ms) or 1500,
        read_timeout_ms = tonumber(entry.read_timeout_ms) or 5000,
        timeout_ms = tonumber(entry.timeout_ms) or 8000,
    }
    cfg.cache_key = table.concat({
        cfg.scheme,
        cfg.host,
        tostring(cfg.port),
        cfg.base_path,
        cfg.login,
        cfg.password,
        cfg.api_type,
    }, "|")
    return cfg
end

local function request_json(cfg, request, callback)
    local method = request.method or "GET"
    local headers = {
        "Host: " .. safe_tostring(cfg.host) .. ":" .. safe_tostring(cfg.port),
        "Connection: close",
        "Accept: application/json",
    }
    if request.headers and type(request.headers) == "table" then
        for _, item in ipairs(request.headers) do
            if item and item ~= "" then
                table.insert(headers, tostring(item))
            end
        end
    end

    local payload = nil
    if request.body ~= nil then
        local ok, encoded = pcall(json.encode, request.body)
        if not ok then
            return callback(false, nil, "json encode failed", 400)
        end
        payload = encoded
        table.insert(headers, "Content-Type: application/json")
        table.insert(headers, "Content-Length: " .. tostring(#payload))
    end

    local ok, err = pcall(http_request, {
        host = cfg.host,
        port = cfg.port,
        path = build_path(cfg, request.path),
        method = method,
        ssl = cfg.scheme == "https",
        tls = cfg.scheme == "https",
        tls_verify = cfg.insecure and false or true,
        timeout = cfg.timeout_ms,
        connect_timeout_ms = cfg.connect_timeout_ms,
        read_timeout_ms = cfg.read_timeout_ms,
        headers = headers,
        content = payload,
        callback = function(_, response)
            if not response then
                return callback(false, nil, "no response", 502)
            end
            local code = tonumber(response.code) or 0
            local decoded = decode_json_safe(response.content or "")
            if code < 200 or code >= 300 then
                local detail = extract_error_text(decoded)
                local text = "http " .. tostring(code)
                if detail ~= "" then
                    text = text .. ": " .. detail
                end
                return callback(false, nil, text, code, {
                    code = code,
                    data = decoded,
                    headers = response.headers,
                })
            end
            return callback(true, decoded, nil, code, {
                code = code,
                data = decoded,
                headers = response.headers,
            })
        end,
    })
    if not ok then
        callback(false, nil, "request failed: " .. tostring(err), 502)
    end
end

local STREAM_V1_CAPABILITIES = {
    streams_list = true,
    streams_get = true,
    streams_upsert = true,
    streams_delete = true,
    action_enable = true,
    action_disable = true,
    action_restart = true,
    action_switch_input = true,
    full_editor = true,
}

local ASTRA_LEGACY_CAPABILITIES = {
    streams_list = true,
    streams_get = true,
    streams_upsert = true,
    streams_delete = true,
    action_enable = true,
    action_disable = true,
    action_restart = true,
    action_switch_input = true,
    full_editor = true,
}

local session_cache = {}

local function cache_read(cfg)
    return session_cache[cfg.cache_key]
end

local function cache_write(cfg, value)
    session_cache[cfg.cache_key] = value
end

local function cache_clear(cfg)
    session_cache[cfg.cache_key] = nil
end

local function stream_v1_login(cfg, callback)
    if cfg.login == "" and cfg.password == "" then
        return callback(true, {
            auth_mode = "none",
            token = nil,
            cookie = nil,
        })
    end
    if cfg.login == "" or cfg.password == "" then
        return callback(false, nil, "login/password incorrect", 401)
    end

    local payload = {
        username = cfg.login,
        password = cfg.password,
    }
    local paths = { "/api/v1/auth/login", "/api/auth/login" }
    local index = 1

    local function attempt()
        local path = paths[index]
        request_json(cfg, {
            method = "POST",
            path = path,
            body = payload,
        }, function(ok, data, err, code, raw)
            if not ok then
                if code == 404 and index < #paths then
                    index = index + 1
                    return attempt()
                end
                if is_auth_error(code) then
                    return callback(false, nil, "login/password incorrect", code)
                end
                return callback(false, nil, err or "login failed", code)
            end
            local token = nil
            if type(data) == "table" then
                token = trim(data.token or data.session_token or "")
                if token == "" then
                    token = nil
                end
            end
            local cookie = nil
            if raw and raw.headers then
                cookie = parse_cookie_from_headers(raw.headers)
            end
            if not token and not cookie then
                -- Keep compatibility with cookie-only servers: treat as auth none if login endpoint accepted.
                return callback(true, {
                    auth_mode = "none",
                    token = nil,
                    cookie = nil,
                })
            end
            return callback(true, {
                auth_mode = token and "bearer" or "cookie",
                token = token,
                cookie = cookie,
            })
        end)
    end

    attempt()
end

local function stream_v1_request(cfg, auth, request, callback)
    local headers = {}
    if auth and auth.token then
        table.insert(headers, "Authorization: Bearer " .. tostring(auth.token))
    elseif auth and auth.cookie then
        table.insert(headers, "Cookie: " .. tostring(auth.cookie))
    end
    request.headers = request.headers or {}
    for _, h in ipairs(headers) do
        table.insert(request.headers, h)
    end
    request_json(cfg, request, callback)
end

local function detect_stream_v1(cfg, callback)
    stream_v1_login(cfg, function(ok_login, auth, login_err, login_code)
        if not ok_login then
            return callback(false, nil, login_err, login_code)
        end

        local paths = { "/api/v1/health/process", "/api/v1/health" }
        local idx = 1
        local function probe_next()
            local path = paths[idx]
            stream_v1_request(cfg, auth, {
                method = "GET",
                path = path,
            }, function(ok, data, err, code)
                if not ok then
                    if code == 404 and idx < #paths then
                        idx = idx + 1
                        return probe_next()
                    end
                    if is_auth_error(code) then
                        return callback(false, nil, "login/password incorrect", code)
                    end
                    return callback(false, nil, err or "stream_v1 probe failed", code)
                end

                local version = ""
                if type(data) == "table" then
                    version = trim(data.version or (type(data.process) == "table" and data.process.version) or "")
                end
                callback(true, {
                    api_type_effective = "stream_v1",
                    remote_version = version,
                    auth_mode = auth and auth.auth_mode or "none",
                    capabilities = STREAM_V1_CAPABILITIES,
                    auth = auth,
                })
            end)
        end

        probe_next()
    end)
end

local function ensure_cesbo_client_loaded()
    if type(CesboApiClient) == "table" and type(CesboApiClient.new) == "function" then
        return true
    end
    local ok = pcall(dofile, "scripts/cesbo_api_client.lua")
    if not ok then
        ok = pcall(require, "cesbo_api_client")
    end
    return ok and type(CesboApiClient) == "table" and type(CesboApiClient.new) == "function"
end

local function new_cesbo_client(cfg)
    if not ensure_cesbo_client_loaded() then
        return nil, "cesbo api client unavailable"
    end
    local url = string.format("%s://%s:%d", cfg.scheme, cfg.host, cfg.port)
    if cfg.base_path and cfg.base_path ~= "" then
        url = url .. cfg.base_path
    end
    local client, err = CesboApiClient.new({
        baseUrl = url,
        login = cfg.login,
        password = cfg.password,
        connect_timeout_ms = cfg.connect_timeout_ms,
        read_timeout_ms = cfg.read_timeout_ms,
        timeout_ms = cfg.timeout_ms,
        max_attempts = 2,
    })
    if not client then
        return nil, err or "failed to init cesbo client"
    end
    return client
end

local function detect_astra_legacy(cfg, callback)
    local client, err = new_cesbo_client(cfg)
    if not client then
        return callback(false, nil, err, 502)
    end

    client:GetVersion(function(ok, data, resp)
        if ok then
            local version = ""
            if type(data) == "table" then
                version = trim(data.version or data.stream_version or data.result or "")
            else
                version = trim(data)
            end
            return callback(true, {
                api_type_effective = "astra_legacy",
                remote_version = version,
                auth_mode = (cfg.login ~= "" or cfg.password ~= "") and "basic" or "none",
                capabilities = ASTRA_LEGACY_CAPABILITIES,
                client = client,
            })
        end

        local code = resp and resp.code or nil
        local msg = trim(data or err or "astra probe failed")
        if is_auth_error(code or msg) then
            return callback(false, nil, "login/password incorrect", code or 401)
        end

        -- Fallback to system-status if version command not supported.
        client:GetSystemStatus(1, function(ok2, data2, resp2)
            if ok2 then
                local version = ""
                if type(data2) == "table" then
                    version = trim(data2.version or data2.stream_version or "")
                end
                return callback(true, {
                    api_type_effective = "astra_legacy",
                    remote_version = version,
                    auth_mode = (cfg.login ~= "" or cfg.password ~= "") and "basic" or "none",
                    capabilities = ASTRA_LEGACY_CAPABILITIES,
                    client = client,
                })
            end
            local msg2 = trim(data2 or msg or "astra probe failed")
            local code2 = resp2 and resp2.code or code
            if is_auth_error(code2 or msg2) then
                return callback(false, nil, "login/password incorrect", code2 or 401)
            end
            return callback(false, nil, msg2, code2)
        end)
    end)
end

local function detect_adapter(cfg, callback)
    local cached = cache_read(cfg)
    if cached and cached.api_type_effective and cached.adapter_ctx then
        return callback(true, cached)
    end

    local function commit(ctx)
        local value = {
            api_type_effective = ctx.api_type_effective,
            remote_version = ctx.remote_version or "",
            auth_mode = ctx.auth_mode or "none",
            capabilities = ctx.capabilities or {},
            adapter_ctx = ctx,
            ts = os.time(),
        }
        cache_write(cfg, value)
        callback(true, value)
    end

    local api_type = cfg.api_type or "auto"
    if api_type == "stream_v1" then
        return detect_stream_v1(cfg, function(ok, ctx, err, code)
            if not ok then
                return callback(false, nil, err, code)
            end
            commit(ctx)
        end)
    end
    if api_type == "astra_legacy" then
        return detect_astra_legacy(cfg, function(ok, ctx, err, code)
            if not ok then
                return callback(false, nil, err, code)
            end
            commit(ctx)
        end)
    end

    detect_stream_v1(cfg, function(ok_stream, stream_ctx, stream_err, stream_code)
        if ok_stream then
            return commit(stream_ctx)
        end
        detect_astra_legacy(cfg, function(ok_astra, astra_ctx, astra_err, astra_code)
            if ok_astra then
                return commit(astra_ctx)
            end
            local stream_auth = is_auth_error(stream_code or stream_err)
            local astra_auth = is_auth_error(astra_code or astra_err)
            if stream_auth or astra_auth then
                local auth_code = 401
                if tonumber(stream_code) == 403 or tonumber(astra_code) == 403 then
                    auth_code = 403
                elseif tonumber(stream_code) == 401 or tonumber(astra_code) == 401 then
                    auth_code = 401
                end
                return callback(false, nil, "login/password incorrect", auth_code)
            end
            local err = nil
            local code = nil
            if astra_err and is_adapter_unavailable_error(astra_err) and stream_err then
                err = stream_err
                code = stream_code
            elseif stream_err and is_adapter_unavailable_error(stream_err) and astra_err then
                err = astra_err
                code = astra_code
            else
                err = astra_err or stream_err or "remote api probe failed"
                code = astra_code or stream_code
            end
            return callback(false, nil, err, code)
        end)
    end)
end

local function normalize_stream_item(row)
    if type(row) ~= "table" then
        return nil
    end
    local cfg = row.config
    if type(cfg) ~= "table" then
        cfg = row
    end
    local id = trim(cfg.id or row.id)
    if id == "" then
        return nil
    end
    local enabled = boolish(row.enabled, nil)
    if enabled == nil then
        enabled = boolish(cfg.enabled, boolish(cfg.enable, true))
    end
    return {
        id = id,
        name = trim(cfg.name or id),
        type = trim(cfg.type or ""),
        enabled = enabled == true,
        config = cfg,
    }
end

local function normalize_streams_payload(data)
    local out = {}
    local function push(item)
        local normalized = normalize_stream_item(item)
        if normalized then
            out[#out + 1] = normalized
        end
    end

    if type(data) == "table" and type(data.make_stream) == "table" then
        for _, cfg in ipairs(data.make_stream) do
            push(cfg)
        end
    elseif type(data) == "table" and type(data.items) == "table" then
        for _, item in ipairs(data.items) do
            push(item)
        end
    elseif type(data) == "table" then
        local as_array = false
        for k, _ in pairs(data) do
            if type(k) == "number" then
                as_array = true
                break
            end
        end
        if as_array then
            for _, item in ipairs(data) do
                push(item)
            end
        end
    end

    table.sort(out, function(a, b)
        return tostring(a.id or "") < tostring(b.id or "")
    end)
    return out
end

local function merge_stream_status(items, status_map)
    if type(status_map) ~= "table" then
        return
    end
    for _, item in ipairs(items) do
        local st = status_map[item.id]
        if type(st) == "table" then
            item.on_air = boolish(st.on_air, boolish(st.alive, nil))
            item.bitrate_kbps = tonumber(st.bitrate or st.bitrate_kbps or st.rate)
            item.uptime_sec = tonumber(st.uptime or st.uptime_sec)
            item.active_input = st.input_id or st.active_input or st.input or nil
            item.last_error = trim(st.last_error or st.error or "")
        end
    end
end

local function stream_v1_list_streams(cfg, adapter_ctx, include_status, callback)
    stream_v1_request(cfg, adapter_ctx.auth, {
        method = "GET",
        path = "/api/v1/streams",
    }, function(ok, data, err, code)
        if not ok then
            return callback(false, nil, err, code)
        end
        local items = normalize_streams_payload(data)
        if not include_status then
            return callback(true, items)
        end
        stream_v1_request(cfg, adapter_ctx.auth, {
            method = "GET",
            path = "/api/v1/stream-status?lite=1",
        }, function(ok2, status_data)
            if ok2 and type(status_data) == "table" then
                merge_stream_status(items, status_data)
            end
            callback(true, items)
        end)
    end)
end

local function stream_v1_get_stream(cfg, adapter_ctx, stream_id, callback)
    stream_v1_request(cfg, adapter_ctx.auth, {
        method = "GET",
        path = "/api/v1/streams/" .. tostring(stream_id),
    }, function(ok, data, err, code)
        if not ok then
            return callback(false, nil, err, code)
        end
        local item = normalize_stream_item(data)
        if not item then
            return callback(false, nil, "stream not found", 404)
        end
        callback(true, item)
    end)
end

local function stream_v1_upsert_stream(cfg, adapter_ctx, stream, mode, callback)
    local id = trim(stream and stream.id)
    if id == "" then
        return callback(false, nil, "stream.id is required", 400)
    end

    local payload = {
        id = id,
        enabled = stream.enabled ~= false,
        config = type(stream.config) == "table" and stream.config or {},
    }
    payload.config.id = id

    if mode == "create" then
        return stream_v1_request(cfg, adapter_ctx.auth, {
            method = "POST",
            path = "/api/v1/streams",
            body = payload,
        }, function(ok, data, err, code)
            if not ok then
                return callback(false, nil, err, code)
            end
            callback(true, data or { status = "ok" })
        end)
    end

    local function put_update(on_not_found)
        stream_v1_request(cfg, adapter_ctx.auth, {
            method = "PUT",
            path = "/api/v1/streams/" .. tostring(id),
            body = payload,
        }, function(ok, data, err, code)
            if not ok and code == 404 and on_not_found then
                return on_not_found()
            end
            if not ok then
                return callback(false, nil, err, code)
            end
            callback(true, data or { status = "ok" })
        end)
    end

    if mode == "update" then
        return put_update(nil)
    end

    -- upsert
    put_update(function()
        stream_v1_request(cfg, adapter_ctx.auth, {
            method = "POST",
            path = "/api/v1/streams",
            body = payload,
        }, function(ok2, data2, err2, code2)
            if not ok2 then
                return callback(false, nil, err2, code2)
            end
            callback(true, data2 or { status = "ok" })
        end)
    end)
end

local function stream_v1_delete_stream(cfg, adapter_ctx, stream_id, callback)
    stream_v1_request(cfg, adapter_ctx.auth, {
        method = "DELETE",
        path = "/api/v1/streams/" .. tostring(stream_id),
    }, function(ok, data, err, code)
        if not ok then
            return callback(false, nil, err, code)
        end
        callback(true, data or { status = "ok" })
    end)
end

local function stream_v1_action(cfg, adapter_ctx, stream_id, action, input_index, callback)
    if action == "enable" or action == "disable" then
        local enabled = action == "enable"
        return stream_v1_request(cfg, adapter_ctx.auth, {
            method = "PUT",
            path = "/api/v1/streams/" .. tostring(stream_id),
            body = { enabled = enabled },
        }, function(ok, data, err, code)
            if not ok then
                return callback(false, nil, err, code)
            end
            callback(true, data or { status = "ok" })
        end)
    end

    if action == "restart" then
        return stream_v1_request(cfg, adapter_ctx.auth, {
            method = "PUT",
            path = "/api/v1/streams/" .. tostring(stream_id),
            body = { enabled = false },
        }, function(ok, _, err, code)
            if not ok then
                return callback(false, nil, err, code)
            end
            timer({
                interval = 0.2,
                callback = function(self)
                    self:close()
                    stream_v1_request(cfg, adapter_ctx.auth, {
                        method = "PUT",
                        path = "/api/v1/streams/" .. tostring(stream_id),
                        body = { enabled = true },
                    }, function(ok2, data2, err2, code2)
                        if not ok2 then
                            return callback(false, nil, err2, code2)
                        end
                        callback(true, data2 or { status = "ok" })
                    end)
                end,
            })
            return nil
        end)
    end

    if action == "switch_input" then
        local idx = tonumber(input_index)
        if idx == nil then
            return callback(false, nil, "input_index is required", 400)
        end
        idx = math.floor(idx)
        if idx < 0 then
            return callback(false, nil, "input_index must be >= 0", 400)
        end
        return stream_v1_request(cfg, adapter_ctx.auth, {
            method = "POST",
            path = "/api/v1/streams/" .. tostring(stream_id) .. "/switch-input",
            body = { input_index = idx },
        }, function(ok, data, err, code)
            if not ok then
                if code == 404 then
                    return callback(false, nil, "switch_input unsupported for stream_v1", 400)
                end
                return callback(false, nil, err, code)
            end
            callback(true, data or {
                status = "ok",
                action = "switch_input",
                input_index = idx,
            })
        end)
    end

    callback(false, nil, "unsupported action", 400)
end

local function astra_list_streams(cfg, adapter_ctx, include_status, callback)
    local client = adapter_ctx.client
    client:GetApi("/streams", nil, function(ok, data, resp)
        if not ok then
            local code = resp and resp.code or nil
            local msg = trim(data or "fetch failed")
            if is_auth_error(code or msg) then
                return callback(false, nil, "login/password incorrect", code or 401)
            end
            return callback(false, nil, msg, code)
        end
        local items = normalize_streams_payload(data)
        if not include_status then
            return callback(true, items)
        end
        client:GetApi("/stream-status", { t = "1" }, function(ok2, status_data)
            if ok2 and type(status_data) == "table" then
                merge_stream_status(items, status_data)
            end
            callback(true, items)
        end)
    end)
end

local function astra_get_stream(cfg, adapter_ctx, stream_id, callback)
    local client = adapter_ctx.client
    client:GetStreamInfo(stream_id, function(ok, data, resp)
        if not ok then
            local code = resp and resp.code or nil
            local msg = trim(data or "stream not found")
            if is_auth_error(code or msg) then
                return callback(false, nil, "login/password incorrect", code or 401)
            end
            if (code or 0) == 404 then
                return callback(false, nil, "stream not found", 404)
            end
            return callback(false, nil, msg, code)
        end
        local item = normalize_stream_item(data)
        if not item then
            return callback(false, nil, "stream not found", 404)
        end
        callback(true, item)
    end)
end

local function astra_upsert_stream(cfg, adapter_ctx, stream, mode, callback)
    local stream_id = trim(stream and stream.id)
    if stream_id == "" then
        return callback(false, nil, "stream.id is required", 400)
    end
    local stream_cfg = type(stream.config) == "table" and stream.config or {}
    stream_cfg.id = stream_id
    stream_cfg.enable = stream.enabled ~= false

    local client = adapter_ctx.client
    if mode == "create" then
        -- Best effort create check.
        return client:GetStreamInfo(stream_id, function(ok_get, _, _)
            if ok_get then
                return callback(false, nil, "stream already exists", 409)
            end
            client:SetStream(stream_id, stream_cfg, function(ok_set, data_set, resp_set)
                if not ok_set then
                    local code = resp_set and resp_set.code or nil
                    local msg = trim(data_set or "set-stream failed")
                    if is_auth_error(code or msg) then
                        return callback(false, nil, "login/password incorrect", code or 401)
                    end
                    return callback(false, nil, msg, code)
                end
                callback(true, data_set or { status = "ok" })
            end)
        end)
    end

    client:SetStream(stream_id, stream_cfg, function(ok_set, data_set, resp_set)
        if not ok_set then
            local code = resp_set and resp_set.code or nil
            local msg = trim(data_set or "set-stream failed")
            if is_auth_error(code or msg) then
                return callback(false, nil, "login/password incorrect", code or 401)
            end
            return callback(false, nil, msg, code)
        end
        callback(true, data_set or { status = "ok" })
    end)
end

local function astra_delete_stream(cfg, adapter_ctx, stream_id, callback)
    adapter_ctx.client:RemoveStream(stream_id, function(ok, data, resp)
        if not ok then
            local code = resp and resp.code or nil
            local msg = trim(data or "remove-stream failed")
            if is_auth_error(code or msg) then
                return callback(false, nil, "login/password incorrect", code or 401)
            end
            return callback(false, nil, msg, code)
        end
        callback(true, data or { status = "ok" })
    end)
end

local function astra_toggle_to(adapter_ctx, stream_id, desired_enabled, callback)
    adapter_ctx.client:GetStreamInfo(stream_id, function(ok_get, data_get, resp_get)
        if not ok_get then
            local code = resp_get and resp_get.code or nil
            local msg = trim(data_get or "stream not found")
            if is_auth_error(code or msg) then
                return callback(false, nil, "login/password incorrect", code or 401)
            end
            return callback(false, nil, msg, code)
        end
        local item = normalize_stream_item(data_get)
        if not item then
            return callback(false, nil, "stream not found", 404)
        end
        if item.enabled == desired_enabled then
            return callback(true, { status = "ok", detail = "already " .. (desired_enabled and "enabled" or "disabled") })
        end
        adapter_ctx.client:ToggleStream(stream_id, function(ok_toggle, data_toggle, resp_toggle)
            if not ok_toggle then
                local code = resp_toggle and resp_toggle.code or nil
                local msg = trim(data_toggle or "toggle-stream failed")
                if is_auth_error(code or msg) then
                    return callback(false, nil, "login/password incorrect", code or 401)
                end
                return callback(false, nil, msg, code)
            end
            callback(true, data_toggle or { status = "ok" })
        end)
    end)
end

local function astra_action(cfg, adapter_ctx, stream_id, action, input_index, callback)
    if action == "enable" then
        return astra_toggle_to(adapter_ctx, stream_id, true, callback)
    end
    if action == "disable" then
        return astra_toggle_to(adapter_ctx, stream_id, false, callback)
    end
    if action == "restart" then
        return adapter_ctx.client:RestartStream(stream_id, function(ok, data, resp)
            if not ok then
                local code = resp and resp.code or nil
                local msg = trim(data or "restart-stream failed")
                if is_auth_error(code or msg) then
                    return callback(false, nil, "login/password incorrect", code or 401)
                end
                return callback(false, nil, msg, code)
            end
            callback(true, data or { status = "ok" })
        end)
    end
    if action == "switch_input" then
        if input_index == nil then
            return callback(false, nil, "input_index is required", 400)
        end
        return adapter_ctx.client:SetStreamInput(stream_id, input_index, function(ok, data, resp)
            if not ok then
                local code = resp and resp.code or nil
                local msg = trim(data or "set-stream-input failed")
                if is_auth_error(code or msg) then
                    return callback(false, nil, "login/password incorrect", code or 401)
                end
                return callback(false, nil, msg, code)
            end
            callback(true, data or { status = "ok" })
        end)
    end
    callback(false, nil, "unsupported action", 400)
end

function remote_servers.probe(entry, callback)
    local cfg, err = remote_servers.normalize(entry)
    if not cfg then
        return callback(false, nil, err or "invalid server", 400)
    end
    local started = os.clock()
    detect_adapter(cfg, function(ok, cached, detect_err, detect_code)
        if not ok then
            local code = classify_error_status(detect_err, detect_code)
            return callback(false, nil, detect_err or "probe failed", code)
        end
        local latency_ms = math.max(0, math.floor(((os.clock() - started) * 1000) + 0.5))
        callback(true, {
            status = "ok",
            api_type_effective = cached.api_type_effective,
            remote_version = cached.remote_version or "",
            auth_mode = cached.auth_mode or "none",
            capabilities = cached.capabilities or {},
            latency_ms = latency_ms,
            message = "ok",
        })
    end)
end

function remote_servers.list_streams(entry, opts, callback)
    local cfg, err = remote_servers.normalize(entry)
    if not cfg then
        return callback(false, nil, err or "invalid server", 400)
    end
    local include_status = not (type(opts) == "table" and opts.include_status == false)
    detect_adapter(cfg, function(ok, cached, detect_err, detect_code)
        if not ok then
            local code = classify_error_status(detect_err, detect_code)
            return callback(false, nil, detect_err or "probe failed", code)
        end
        local ctx = cached.adapter_ctx or {}
        local done = function(ok2, items, err2, code2)
            if not ok2 then
                if is_auth_error(code2 or err2) then
                    cache_clear(cfg)
                end
                local code = classify_error_status(err2, code2)
                return callback(false, nil, err2 or "list failed", code)
            end
            callback(true, {
                items = items or {},
                capabilities = cached.capabilities or {},
                api_type_effective = cached.api_type_effective,
                remote_version = cached.remote_version or "",
                auth_mode = cached.auth_mode or "none",
            })
        end
        if cached.api_type_effective == "stream_v1" then
            return stream_v1_list_streams(cfg, ctx, include_status, done)
        end
        return astra_list_streams(cfg, ctx, include_status, done)
    end)
end

function remote_servers.get_stream(entry, stream_id, callback)
    local cfg, err = remote_servers.normalize(entry)
    if not cfg then
        return callback(false, nil, err or "invalid server", 400)
    end
    local sid = trim(stream_id)
    if sid == "" then
        return callback(false, nil, "stream_id is required", 400)
    end
    detect_adapter(cfg, function(ok, cached, detect_err, detect_code)
        if not ok then
            local code = classify_error_status(detect_err, detect_code)
            return callback(false, nil, detect_err or "probe failed", code)
        end
        local ctx = cached.adapter_ctx or {}
        local done = function(ok2, item, err2, code2)
            if not ok2 then
                if is_auth_error(code2 or err2) then
                    cache_clear(cfg)
                end
                local code = classify_error_status(err2, code2)
                return callback(false, nil, err2 or "get failed", code)
            end
            callback(true, {
                id = item.id,
                enabled = item.enabled ~= false,
                config = item.config or {},
                capabilities = cached.capabilities or {},
                api_type_effective = cached.api_type_effective,
                remote_version = cached.remote_version or "",
            })
        end
        if cached.api_type_effective == "stream_v1" then
            return stream_v1_get_stream(cfg, ctx, sid, done)
        end
        return astra_get_stream(cfg, ctx, sid, done)
    end)
end

function remote_servers.upsert_stream(entry, stream, mode, callback)
    local cfg, err = remote_servers.normalize(entry)
    if not cfg then
        return callback(false, nil, err or "invalid server", 400)
    end
    local op_mode = trim(mode):lower()
    if op_mode == "" then
        op_mode = "upsert"
    end
    if op_mode ~= "create" and op_mode ~= "update" and op_mode ~= "upsert" then
        return callback(false, nil, "invalid mode", 400)
    end
    if type(stream) ~= "table" then
        return callback(false, nil, "stream payload required", 400)
    end
    detect_adapter(cfg, function(ok, cached, detect_err, detect_code)
        if not ok then
            local code = classify_error_status(detect_err, detect_code)
            return callback(false, nil, detect_err or "probe failed", code)
        end
        local ctx = cached.adapter_ctx or {}
        local done = function(ok2, result, err2, code2)
            if not ok2 then
                if is_auth_error(code2 or err2) then
                    cache_clear(cfg)
                end
                local code = classify_error_status(err2, code2)
                return callback(false, nil, err2 or "upsert failed", code)
            end
            callback(true, {
                status = "ok",
                detail = result and result.detail or "saved",
                api_type_effective = cached.api_type_effective,
                remote_version = cached.remote_version or "",
                capabilities = cached.capabilities or {},
            })
        end
        if cached.api_type_effective == "stream_v1" then
            return stream_v1_upsert_stream(cfg, ctx, stream, op_mode, done)
        end
        return astra_upsert_stream(cfg, ctx, stream, op_mode, done)
    end)
end

function remote_servers.delete_stream(entry, stream_id, callback)
    local cfg, err = remote_servers.normalize(entry)
    if not cfg then
        return callback(false, nil, err or "invalid server", 400)
    end
    local sid = trim(stream_id)
    if sid == "" then
        return callback(false, nil, "stream_id is required", 400)
    end
    detect_adapter(cfg, function(ok, cached, detect_err, detect_code)
        if not ok then
            local code = classify_error_status(detect_err, detect_code)
            return callback(false, nil, detect_err or "probe failed", code)
        end
        local ctx = cached.adapter_ctx or {}
        local done = function(ok2, result, err2, code2)
            if not ok2 then
                if is_auth_error(code2 or err2) then
                    cache_clear(cfg)
                end
                local code = classify_error_status(err2, code2)
                return callback(false, nil, err2 or "delete failed", code)
            end
            callback(true, {
                status = "ok",
                detail = result and result.detail or "deleted",
                api_type_effective = cached.api_type_effective,
                remote_version = cached.remote_version or "",
                capabilities = cached.capabilities or {},
            })
        end
        if cached.api_type_effective == "stream_v1" then
            return stream_v1_delete_stream(cfg, ctx, sid, done)
        end
        return astra_delete_stream(cfg, ctx, sid, done)
    end)
end

function remote_servers.action(entry, stream_id, action, opts, callback)
    local cfg, err = remote_servers.normalize(entry)
    if not cfg then
        return callback(false, nil, err or "invalid server", 400)
    end
    local sid = trim(stream_id)
    if sid == "" then
        return callback(false, nil, "stream_id is required", 400)
    end
    local act = trim(action):lower()
    if act ~= "enable" and act ~= "disable" and act ~= "restart" and act ~= "switch_input" then
        return callback(false, nil, "unsupported action", 400)
    end
    local input_index = nil
    if type(opts) == "table" then
        input_index = opts.input_index
    end
    detect_adapter(cfg, function(ok, cached, detect_err, detect_code)
        if not ok then
            local code = classify_error_status(detect_err, detect_code)
            return callback(false, nil, detect_err or "probe failed", code)
        end
        local ctx = cached.adapter_ctx or {}
        local done = function(ok2, result, err2, code2)
            if not ok2 then
                if is_auth_error(code2 or err2) then
                    cache_clear(cfg)
                end
                local code = classify_error_status(err2, code2)
                return callback(false, nil, err2 or "action failed", code)
            end
            local payload = {
                status = "ok",
                action = act,
                detail = result and result.detail or "ok",
                api_type_effective = cached.api_type_effective,
                remote_version = cached.remote_version or "",
                capabilities = cached.capabilities or {},
            }
            if act == "switch_input" then
                local idx = nil
                if type(result) == "table" and result.input_index ~= nil then
                    idx = tonumber(result.input_index)
                end
                if idx == nil then
                    idx = tonumber(input_index)
                end
                if idx ~= nil then
                    payload.input_index = math.floor(idx)
                end
            end
            callback(true, payload)
        end
        if cached.api_type_effective == "stream_v1" then
            return stream_v1_action(cfg, ctx, sid, act, input_index, done)
        end
        return astra_action(cfg, ctx, sid, act, input_index, done)
    end)
end

remote_servers.classify_error_status = classify_error_status

return remote_servers
