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

local function table_is_array(value)
    if type(value) ~= "table" then
        return false
    end
    local count = 0
    local max_index = 0
    for k, _ in pairs(value) do
        if type(k) ~= "number" then
            return false
        end
        if k <= 0 or math.floor(k) ~= k then
            return false
        end
        count = count + 1
        if k > max_index then
            max_index = k
        end
    end
    return count == max_index
end

local function deep_copy(value)
    if type(value) ~= "table" then
        return value
    end
    local out = {}
    for k, v in pairs(value) do
        out[k] = deep_copy(v)
    end
    return out
end

local function merge_object_preserving_unknown(base_value, override_value)
    if type(override_value) ~= "table" then
        return deep_copy(override_value)
    end
    if type(base_value) ~= "table" then
        return deep_copy(override_value)
    end
    if table_is_array(base_value) or table_is_array(override_value) then
        return deep_copy(override_value)
    end
    local out = deep_copy(base_value)
    for key, next_value in pairs(override_value) do
        local prev_value = out[key]
        if type(prev_value) == "table"
            and type(next_value) == "table"
            and not table_is_array(prev_value)
            and not table_is_array(next_value)
        then
            out[key] = merge_object_preserving_unknown(prev_value, next_value)
        else
            out[key] = deep_copy(next_value)
        end
    end
    return out
end

local ASTRA_STRIP_TOP_LEVEL_KEYS = {
    audio_fix = true,
    transcode = true,
    radio = true,
    mpts_config = true,
    mpts_services = true,
    backup_type = true,
    backup_initial_delay = true,
    backup_initial_delay_sec = true,
    backup_start_delay = true,
    backup_start_delay_sec = true,
    backup_return_delay = true,
    backup_return_delay_sec = true,
    backup_stop_if_all_inactive_sec = true,
    backup_stall_switch_cooldown_sec = true,
    stop_if_all_inactive_sec = true,
    epg = true,
    http_keep_active = true,
    auth_enabled = true,
    auth_token_source = true,
    auth_token_param = true,
    auth_allow_default = true,
    group = true,
    dvr = true,
    observability = true,
    backup_adapter = true,
    backup_adapter_enabled = true,
    backup_adapter_config = true,
    backup_adapter_candidates = true,
    auto_signal_search_enabled = true,
    auto_signal_window_sec = true,
    auto_signal_bitrate_mode = true,
    auto_signal_bitrate_min_kbps = true,
    auto_signal_baseline_window_sec = true,
    auto_signal_baseline_drop_ratio_pct = true,
    auto_signal_cc_delta_threshold = true,
    auto_signal_probe_sec = true,
    auto_signal_confirm_sec = true,
    auto_signal_switch_cooldown_sec = true,
    auto_signal_min_streams = true,
    auto_signal_candidate_profiles = true,
    satellite_type_flip_recovery = true,
    type_flip_wait_sec = true,
    runtime = true,
    stats = true,
    remote = true,
    ui = true,
    issues = true,
}

local function sanitize_stream_url_list(value)
    if type(value) ~= "table" then
        return nil
    end
    local out = {}
    for _, item in ipairs(value) do
        if type(item) ~= "string" then
            goto continue
        end
        local s = trim(item)
        if s ~= "" then
            out[#out + 1] = s
        end
        ::continue::
    end
    return out
end

local function redact_url_credentials(url)
    local value = trim(url)
    if value == "" then
        return ""
    end
    local scheme_end = value:find("://", 1, true)
    if not scheme_end then
        return value
    end
    local auth_start = scheme_end + 3
    local path_start = value:find("/", auth_start, true)
    if not path_start then
        path_start = #value + 1
    end
    local at_pos = value:find("@", auth_start, true)
    if at_pos and at_pos < path_start then
        return value:sub(1, auth_start - 1) .. value:sub(at_pos + 1)
    end
    return value
end

local function sanitize_astra_map_value(value)
    if value == nil then
        return nil
    end
    local map_text = trim(value)
    if map_text == "" then
        return ""
    end
    -- Guard against accidental concatenation like:
    -- "video=214, audio=314udp://..."
    local proto_pos = map_text:find("[%a][%w+%-%.]*://")
    if proto_pos and proto_pos > 1 then
        local prefix = trim(map_text:sub(1, proto_pos - 1))
        prefix = trim(prefix:gsub("[,;]+$", ""))
        if prefix ~= "" then
            map_text = prefix
        end
    end
    return map_text
end

local function sanitize_stream_cfg_for_astra(stream_cfg)
    local out = type(stream_cfg) == "table" and deep_copy(stream_cfg) or {}
    for key, _ in pairs(ASTRA_STRIP_TOP_LEVEL_KEYS) do
        out[key] = nil
    end
    local input = sanitize_stream_url_list(out.input)
    if input ~= nil then
        out.input = input
    end
    local output = sanitize_stream_url_list(out.output)
    if output ~= nil then
        out.output = output
    end
    if out.map ~= nil then
        out.map = sanitize_astra_map_value(out.map)
    end
    if out.id ~= nil then
        out.id = trim(out.id)
    end
    if out.name ~= nil then
        out.name = trim(out.name)
    end
    return out
end

local function decode_json_safe(text)
    if not text or text == "" then
        return true, nil
    end
    local ok, data = pcall(json.decode, text)
    if not ok then
        return false, nil
    end
    return true, data
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
    if v == "dvr_v1" or v == "dvr-v1" or v == "dvr" then
        return "dvr_v1"
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
        connect_timeout_ms = tonumber(entry.connect_timeout_ms) or 2000,
        read_timeout_ms = tonumber(entry.read_timeout_ms) or 15000,
        timeout_ms = tonumber(entry.timeout_ms) or 20000,
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

    local empty_retries = tonumber(request.empty_retries)
    if empty_retries == nil then
        empty_retries = 2
    end
    if empty_retries < 0 then
        empty_retries = 0
    end
    local empty_attempt = 0

    local function do_request()
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
                local content = response.content or ""
                if code >= 200 and code < 300 and content == "" and empty_attempt < empty_retries then
                    empty_attempt = empty_attempt + 1
                    return do_request()
                end
                local decode_ok, decoded = decode_json_safe(content)
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
                if not decode_ok then
                    return callback(false, nil, "invalid json response", 502, {
                        code = code,
                        data = nil,
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

    do_request()
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

local DVR_V1_CAPABILITIES = {
    streams_list = true,
    streams_get = true,
    streams_upsert = true,
    streams_delete = true,
    action_enable = true,
    action_disable = true,
    action_restart = false,
    action_switch_input = false,
    full_editor = false,
    dvr_streams_upsert = true,
    dvr_streams_bulk_record = true,
    dvr_ingest_state = true,
    dvr_archive_read = true,
    dvr_backup_state_read = true,
    dvr_backup_cursor_reset = true,
    dvr_backup_cycle_rebuild = true,
    dvr_storage_candidates = true,
}

local session_cache = {}
local streams_cache = {}

local function cache_read(cfg)
    return session_cache[cfg.cache_key]
end

local function cache_write(cfg, value)
    session_cache[cfg.cache_key] = value
end

local function cache_clear(cfg)
    session_cache[cfg.cache_key] = nil
end

local function streams_cache_read(cfg)
    local row = streams_cache[cfg.cache_key]
    if type(row) ~= "table" then
        return nil
    end
    local items = type(row.items) == "table" and row.items or nil
    if not items or #items == 0 then
        return nil
    end
    return items
end

local function streams_cache_write(cfg, items)
    if type(items) ~= "table" or #items == 0 then
        return
    end
    local copy = {}
    for i, item in ipairs(items) do
        copy[i] = item
    end
    streams_cache[cfg.cache_key] = {
        ts = os.time(),
        items = copy,
    }
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
    end
    if auth and auth.cookie then
        table.insert(headers, "Cookie: " .. tostring(auth.cookie))
    end
    request.headers = request.headers or {}
    for _, h in ipairs(headers) do
        table.insert(request.headers, h)
    end
    request_json(cfg, request, callback)
end

local function build_auth_headers(auth, cfg)
    local headers = {}
    if type(auth) ~= "table" then
        auth = nil
    end
    local has_token = auth and auth.token and tostring(auth.token) ~= ""
    local has_cookie = auth and auth.cookie and tostring(auth.cookie) ~= ""
    if has_token then
        table.insert(headers, "Authorization: Bearer " .. tostring(auth.token))
    end
    if has_cookie then
        table.insert(headers, "Cookie: " .. tostring(auth.cookie))
    end
    if not has_token and not has_cookie then
        local login = trim(cfg and cfg.login or "")
        local password = safe_tostring(cfg and cfg.password or "")
        if login ~= "" or password ~= "" then
            table.insert(headers, "Authorization: Basic " .. base64.encode(login .. ":" .. password))
        end
    end
    return headers
end

local function astra_request(cfg, adapter_ctx, request, callback)
    request = request or {}
    request.headers = request.headers or {}
    local auth = adapter_ctx and adapter_ctx.auth or nil
    local auth_headers = build_auth_headers(auth, cfg)
    for _, h in ipairs(auth_headers) do
        table.insert(request.headers, h)
    end
    request_json(cfg, request, callback)
end

local function astra_try_paths(cfg, adapter_ctx, request, callback)
    local paths = (type(request) == "table" and type(request.paths) == "table") and request.paths or {}
    local method = (type(request) == "table" and request.method) or "GET"
    local body = type(request) == "table" and request.body or nil
    if #paths == 0 then
        return callback(false, nil, "invalid astra request paths", 400)
    end
    local index = 1
    local function attempt()
        local path = paths[index]
        astra_request(cfg, adapter_ctx, {
            method = method,
            path = path,
            body = body,
        }, function(ok, data, err, code)
            if not ok and code == 404 and index < #paths then
                index = index + 1
                return attempt()
            end
            return callback(ok, data, err, code)
        end)
    end
    attempt()
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

local function detect_dvr_v1(cfg, callback)
    stream_v1_login(cfg, function(ok_login, auth, login_err, login_code)
        if not ok_login then
            return callback(false, nil, login_err, login_code)
        end
        stream_v1_request(cfg, auth, {
            method = "GET",
            path = "/api/v1/dvr/health",
        }, function(ok, data, err, code)
            if not ok then
                if is_auth_error(code) then
                    return callback(false, nil, "login/password incorrect", code)
                end
                return callback(false, nil, err or "dvr_v1 probe failed", code)
            end
            local version = ""
            if type(data) == "table" then
                version = trim(data.version or data.stream_version or "")
            end
            callback(true, {
                api_type_effective = "dvr_v1",
                remote_version = version,
                auth_mode = auth and auth.auth_mode or "none",
                capabilities = DVR_V1_CAPABILITIES,
                auth = auth,
            })
        end)
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

local function new_cesbo_client(cfg, auth)
    if not ensure_cesbo_client_loaded() then
        return nil, "cesbo api client unavailable"
    end
    local url = string.format("%s://%s:%d", cfg.scheme, cfg.host, cfg.port)
    if cfg.base_path and cfg.base_path ~= "" then
        url = url .. cfg.base_path
    end
    local use_auth_headers = type(auth) == "table"
        and ((auth.cookie and tostring(auth.cookie) ~= "") or (auth.token and tostring(auth.token) ~= ""))
    local client, err = CesboApiClient.new({
        baseUrl = url,
        login = use_auth_headers and "" or cfg.login,
        password = use_auth_headers and "" or cfg.password,
        cookie = use_auth_headers and tostring(auth.cookie or "") or "",
        bearer_token = use_auth_headers and tostring(auth.token or "") or "",
        http_request_fn = http_request,
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
    local function build_ctx(client, auth_mode, auth, version)
        return {
            api_type_effective = "astra_legacy",
            remote_version = version or "",
            auth_mode = auth_mode or "none",
            capabilities = ASTRA_LEGACY_CAPABILITIES,
            client = client,
            auth = auth,
        }
    end

    local function probe_client(client, auth_mode, auth, done)
        client:GetVersion(function(ok, data, resp)
            if ok then
                local version = ""
                if type(data) == "table" then
                    version = trim(data.version or data.stream_version or data.result or "")
                else
                    version = trim(data)
                end
                return done(true, build_ctx(client, auth_mode, auth, version))
            end
            local code = resp and resp.code or nil
            local msg = trim(data or "astra probe failed")
            client:GetSystemStatus(1, function(ok2, data2, resp2)
                if ok2 then
                    local version = ""
                    if type(data2) == "table" then
                        version = trim(data2.version or data2.stream_version or "")
                    end
                    return done(true, build_ctx(client, auth_mode, auth, version))
                end
                local msg2 = trim(data2 or msg or "astra probe failed")
                local code2 = resp2 and resp2.code or code
                return done(false, nil, msg2, code2)
            end)
        end)
    end

    local primary_mode = (cfg.login ~= "" or cfg.password ~= "") and "basic" or "none"
    local primary_client, init_err = new_cesbo_client(cfg, nil)
    if not primary_client then
        return callback(false, nil, init_err, 502)
    end

    probe_client(primary_client, primary_mode, nil, function(ok, ctx, probe_err, probe_code)
        if ok then
            return callback(true, ctx)
        end

        if not is_auth_error(probe_code or probe_err) then
            return callback(false, nil, probe_err, probe_code)
        end

        if cfg.login == "" and cfg.password == "" then
            return callback(false, nil, "login/password incorrect", probe_code or 401)
        end

        -- Some Astra deployments require cookie/bearer auth and deny pure Basic Auth.
        stream_v1_login(cfg, function(ok_login, auth, login_err, login_code)
            if not ok_login then
                return callback(false, nil, "login/password incorrect", login_code or 401)
            end
            local has_auth = type(auth) == "table"
                and ((auth.token and tostring(auth.token) ~= "") or (auth.cookie and tostring(auth.cookie) ~= ""))
            if not has_auth then
                return callback(false, nil, "login/password incorrect", probe_code or 401)
            end

            local fallback_client, fallback_err = new_cesbo_client(cfg, auth)
            if not fallback_client then
                return callback(false, nil, fallback_err, 502)
            end
            local fallback_mode = auth.auth_mode or ((auth.token and "bearer") or "cookie")
            probe_client(fallback_client, fallback_mode, auth, function(ok2, ctx2, err2, code2)
                if ok2 then
                    return callback(true, ctx2)
                end
                if is_auth_error(code2 or err2) then
                    return callback(false, nil, "login/password incorrect", code2 or 401)
                end
                return callback(false, nil, err2, code2)
            end)
        end)
    end)
end

local function detect_adapter(cfg, callback, opts)
    if type(opts) == "table" and opts.force == true then
        cache_clear(cfg)
    end
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
    if api_type == "dvr_v1" then
        return detect_dvr_v1(cfg, function(ok, ctx, err, code)
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
    elseif type(data) == "table" and type(data.streams) == "table" then
        for _, item in ipairs(data.streams) do
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

local function apply_stream_status(item, st)
    if type(item) ~= "table" or type(st) ~= "table" then
        return
    end
    item.on_air = boolish(st.on_air, boolish(st.onair, boolish(st.active, boolish(st.alive, nil))))
    item.bitrate_kbps = nil
    local bitrate_value = st.bitrate or st.bitrate_kbps or st.rate
    local bitrate_num = tonumber(bitrate_value)
    if bitrate_num == nil and bitrate_value ~= nil then
        local text = trim(tostring(bitrate_value)):lower()
        local parsed = tonumber(text:match("([%d%.]+)"))
        if parsed ~= nil then
            if text:find("mbit", 1, true) or text:find("mbps", 1, true) then
                bitrate_num = parsed * 1000
            elseif text:find("kbit", 1, true) or text:find("kbps", 1, true) then
                bitrate_num = parsed
            elseif text:find("bit", 1, true) then
                bitrate_num = parsed / 1000
            else
                bitrate_num = parsed
            end
        end
    end
    if bitrate_num ~= nil then
        item.bitrate_kbps = bitrate_num
    end
    local raw_bitrate_num = tonumber(st.raw_bitrate_kbps or st.raw_bitrate or st.bitrate_raw)
    if raw_bitrate_num ~= nil then
        item.raw_bitrate_kbps = raw_bitrate_num
    end
    local cc_errors = tonumber(st.cc_errors)
    if cc_errors ~= nil then
        item.cc_errors = cc_errors
    end
    local pes_errors = tonumber(st.pes_errors)
    if pes_errors ~= nil then
        item.pes_errors = pes_errors
    end
    local clients_count = tonumber(st.clients_count or st.clients)
    if clients_count ~= nil then
        item.clients_count = clients_count
    end
    local updated_at = tonumber(st.updated_at or st.updated)
    if updated_at ~= nil then
        item.updated_at = updated_at
    end
    local updated_raw_at = tonumber(st.updated_raw_at or st.updated_at_raw)
    if updated_raw_at ~= nil then
        item.updated_raw_at = updated_raw_at
    end
    local scrambled = boolish(st.scrambled, nil)
    if scrambled ~= nil then
        item.scrambled = scrambled == true
    end
    item.uptime_sec = tonumber(st.uptime or st.uptime_sec)
    item.active_input = st.input_id or st.active_input or st.input or nil
    if item.active_input ~= nil and tonumber(item.active_input) == nil then
        local parsed_input = tonumber(tostring(item.active_input):match("(%d+)"))
        if parsed_input ~= nil then
            item.active_input = parsed_input
        end
    end
    if type(st.inputs) == "table" then
        item.inputs = deep_copy(st.inputs)
    end
    if type(st.transcode) == "table" then
        item.transcode = deep_copy(st.transcode)
    end
    local transcode_state = trim(st.transcode_state or st.transcode_status or (type(st.transcode) == "table" and st.transcode.state) or "")
    if transcode_state ~= "" then
        item.transcode_state = transcode_state
    end
    item.last_error = trim(st.last_error or st.error or "")
end

local function merge_stream_status(items, status_map)
    if type(status_map) ~= "table" then
        return 0
    end
    local merged = 0
    for _, item in ipairs(items) do
        local st = status_map[item.id]
        if type(st) == "table" then
            merged = merged + 1
        end
        apply_stream_status(item, st)
    end
    return merged
end

local function astra_load_streams_from_control(adapter_ctx, callback)
    local client = adapter_ctx and adapter_ctx.client or nil
    if not client or type(client.LoadConfiguration) ~= "function" then
        return callback(false, nil, "control load unavailable", 404)
    end
    client:LoadConfiguration(function(ok, data, resp)
        if not ok then
            local code = resp and resp.code or nil
            local msg = trim(data or "load config failed")
            if is_auth_error(code or msg) then
                return callback(false, nil, "login/password incorrect", code or 401)
            end
            return callback(false, nil, msg, code)
        end
        local items = normalize_streams_payload(data)
        callback(true, items)
    end)
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

local function normalize_dvr_stream_item(row)
    if type(row) ~= "table" then
        return nil
    end
    local id = trim(row.stream_id or row.id)
    if id == "" then
        return nil
    end
    local name = trim(row.name or id)
    local record_enabled = boolish(row.record_enabled, boolish(row.enabled, false))
    local retention_days = tonumber(row.retention_days)
    local archive_path = trim(row.archive_path or row.path)
    local cfg = nil
    if type(row.config) == "table" then
        cfg = deep_copy(row.config)
    elseif row.config_json ~= nil then
        local ok_cfg, decoded_cfg = decode_json_safe(tostring(row.config_json))
        if ok_cfg and type(decoded_cfg) == "table" then
            cfg = decoded_cfg
        end
    end
    if type(cfg) ~= "table" then
        cfg = {}
    end
    local source_url_raw = trim(row.source_url or "")
    if source_url_raw == "" and type(cfg.dvr) == "table" then
        source_url_raw = trim(cfg.dvr.source_url or "")
    end
    if source_url_raw == "" and type(cfg.input) == "table" and cfg.input[1] then
        source_url_raw = trim(cfg.input[1])
    end
    local source_url = redact_url_credentials(source_url_raw)
    cfg.id = id
    if trim(cfg.name) == "" then
        cfg.name = name ~= "" and name or id
    end
    if trim(cfg.type) == "" then
        cfg.type = "spts"
    end
    if type(cfg.input) == "table" then
        for idx, input_url in ipairs(cfg.input) do
            if type(input_url) == "string" then
                cfg.input[idx] = redact_url_credentials(input_url)
            end
        end
    end
    if source_url ~= "" then
        if type(cfg.input) ~= "table" then
            cfg.input = {}
        end
        cfg.input[1] = source_url
    elseif type(cfg.input) ~= "table" then
        cfg.input = {}
    end
    local cfg_dvr = type(cfg.dvr) == "table" and cfg.dvr or {}
    if cfg_dvr.source_url ~= nil then
        cfg_dvr.source_url = redact_url_credentials(trim(cfg_dvr.source_url))
    end
    cfg_dvr.enabled = record_enabled == true
    cfg_dvr.retention_days = retention_days and math.max(1, math.floor(retention_days)) or 3
    cfg_dvr.source_url = source_url
    if archive_path ~= "" then
        cfg_dvr.path = archive_path
        cfg_dvr.archive_path = archive_path
    end
    cfg.dvr = cfg_dvr
    local bitrate_kbps = tonumber(row.bitrate_kbps or row.bitrate)
    local raw_bitrate_kbps = tonumber(
        row.raw_bitrate_kbps or row.raw_bitrate or row.bitrate_raw or row.bitrate_kbps or row.bitrate
    )
    local cc_errors = tonumber(row.cc_errors)
    local pes_errors = tonumber(row.pes_errors)
    local updated_at = tonumber(row.updated_at or row.updated)
    local active_input = row.active_input
    if active_input == nil then
        active_input = row.active_input_id
    end
    active_input = tonumber(active_input) or active_input
    local active_input_url = redact_url_credentials(trim(row.active_input_url or row.input_url or ""))
    local last_error = trim(row.last_error or row.error or "")
    local on_air = row.on_air == true
    if row.on_air == nil and row.status ~= nil then
        local status_text = trim(row.status):lower()
        if status_text == "ok" or status_text == "on_air" or status_text == "online" then
            on_air = true
        elseif status_text == "offline" or status_text == "down" then
            on_air = false
        end
    end
    local item = {
        id = id,
        name = name ~= "" and name or id,
        type = "dvr",
        enabled = record_enabled == true,
        on_air = on_air == true,
        bitrate_kbps = bitrate_kbps,
        raw_bitrate_kbps = raw_bitrate_kbps,
        cc_errors = cc_errors,
        pes_errors = pes_errors,
        uptime_sec = tonumber(row.uptime_sec),
        active_input = active_input,
        active_input_url = active_input_url ~= "" and active_input_url or nil,
        last_error = last_error,
        updated_at = updated_at,
        dvr = {
            stream_id = id,
            source_url = source_url,
            archive_path = archive_path,
            record_enabled = record_enabled == true,
            recording_paused = boolish(row.recording_paused, false) == true,
            retention_days = retention_days and math.max(1, math.floor(retention_days)) or 3,
            status = trim(row.status or ""),
            last_mode = trim(row.last_mode or ""),
            last_state_seq = tonumber(row.last_state_seq),
            updated_ts = tonumber(row.updated_ts) or updated_at,
        },
        config = cfg,
    }
    return item
end

local function dvr_v1_list_streams(cfg, adapter_ctx, include_status, callback)
    stream_v1_request(cfg, adapter_ctx.auth, {
        method = "POST",
        path = "/api/v1/dvr/streams/list",
        body = {
            include_status = include_status ~= false,
        },
    }, function(ok, data, err, code)
        if not ok then
            return callback(false, nil, err, code)
        end
        local rows = {}
        if type(data) == "table" and type(data.items) == "table" then
            rows = data.items
        elseif type(data) == "table" then
            rows = data
        end
        local items = {}
        for _, row in ipairs(rows or {}) do
            local normalized = normalize_dvr_stream_item(row)
            if normalized then
                items[#items + 1] = normalized
            end
        end
        table.sort(items, function(a, b)
            return tostring(a.id or "") < tostring(b.id or "")
        end)
        callback(true, items)
    end)
end

local function dvr_v1_get_stream(cfg, adapter_ctx, stream_id, callback)
    stream_v1_request(cfg, adapter_ctx.auth, {
        method = "POST",
        path = "/api/v1/dvr/streams/get",
        body = {
            stream_id = stream_id,
        },
    }, function(ok, data, err, code)
        if not ok then
            return callback(false, nil, err, code)
        end
        local row = type(data) == "table" and (data.item or data) or {}
        local normalized = normalize_dvr_stream_item(row)
        if not normalized then
            return callback(false, nil, "stream not found", 404)
        end
        callback(true, normalized)
    end)
end

local function dvr_stream_payload_from_generic(stream)
    local id = trim(stream and stream.id)
    if id == "" then
        return nil, "stream.id is required"
    end
    local cfg_row = type(stream.config) == "table" and deep_copy(stream.config) or {}
    local dvr_cfg = type(cfg_row.dvr) == "table" and cfg_row.dvr or {}
    local source_url = trim(dvr_cfg.source_url)
    if source_url == "" and type(cfg_row.input) == "table" and cfg_row.input[1] then
        source_url = trim(cfg_row.input[1])
    end
    if source_url == "" then
        return nil, "dvr source_url is required"
    end
    local retention_days = tonumber(dvr_cfg.retention_days) or 3
    if retention_days < 1 then
        retention_days = 1
    end
    local archive_path = trim(dvr_cfg.path or dvr_cfg.archive_path)
    if archive_path == "" then
        archive_path = nil
    end
    cfg_row.id = id
    if trim(cfg_row.name) == "" then
        cfg_row.name = trim(cfg_row.name or stream.name or id)
    end
    if trim(cfg_row.type) == "" then
        cfg_row.type = "spts"
    end
    if type(cfg_row.input) ~= "table" then
        cfg_row.input = {}
    end
    cfg_row.input[1] = source_url
    local cfg_dvr = type(cfg_row.dvr) == "table" and cfg_row.dvr or {}
    cfg_dvr.enabled = stream.enabled ~= false and dvr_cfg.enabled ~= false
    cfg_dvr.retention_days = math.floor(retention_days)
    cfg_dvr.source_url = source_url
    if archive_path then
        cfg_dvr.path = archive_path
        cfg_dvr.archive_path = archive_path
    end
    cfg_row.dvr = cfg_dvr
    return {
        stream_id = id,
        name = trim(cfg_row.name or stream.name or id),
        source_url = source_url,
        archive_path = archive_path,
        record_enabled = stream.enabled ~= false and dvr_cfg.enabled ~= false,
        retention_days = math.floor(retention_days),
        segment_sec = 3600,
        config = cfg_row,
    }
end

local function dvr_v1_upsert_stream(cfg, adapter_ctx, stream, _mode, callback)
    local payload, payload_err = dvr_stream_payload_from_generic(stream)
    if not payload then
        return callback(false, nil, payload_err, 400)
    end
    stream_v1_request(cfg, adapter_ctx.auth, {
        method = "POST",
        path = "/api/v1/dvr/streams/upsert",
        body = payload,
    }, function(ok, data, err, code)
        if not ok then
            return callback(false, nil, err, code)
        end
        callback(true, data or { status = "ok" })
    end)
end

local function dvr_v1_delete_stream(cfg, adapter_ctx, stream_id, callback)
    stream_v1_request(cfg, adapter_ctx.auth, {
        method = "POST",
        path = "/api/v1/dvr/streams/delete",
        body = {
            stream_id = stream_id,
        },
    }, function(ok, data, err, code)
        if not ok then
            return callback(false, nil, err, code)
        end
        callback(true, data or { status = "ok" })
    end)
end

local function dvr_v1_action(cfg, adapter_ctx, stream_id, action, _input_index, callback)
    if action ~= "enable" and action ~= "disable" then
        return callback(false, nil, "unsupported action", 400)
    end
    stream_v1_request(cfg, adapter_ctx.auth, {
        method = "POST",
        path = "/api/v1/dvr/streams/bulk-record",
        body = {
            stream_ids = { tostring(stream_id) },
            record_enabled = action == "enable",
        },
    }, function(ok, data, err, code)
        if not ok then
            return callback(false, nil, err, code)
        end
        callback(true, data or { status = "ok" })
    end)
end

local function astra_list_streams(cfg, adapter_ctx, include_status, callback)
    astra_try_paths(cfg, adapter_ctx, {
        method = "GET",
        paths = {
            "/api/streams",
            "/api/v1/streams",
            "/api/stream-info",
        },
    }, function(ok, data, err, code)
        if not ok and code == 404 and adapter_ctx and adapter_ctx.client and adapter_ctx.client.LoadConfiguration then
            return adapter_ctx.client:LoadConfiguration(function(ok_load, data_load, resp_load)
                if not ok_load then
                    local load_code = resp_load and resp_load.code or code
                    local msg = trim(data_load or err or "fetch failed")
                    if is_auth_error(load_code or msg) then
                        return callback(false, nil, "login/password incorrect", load_code or 401)
                    end
                    return callback(false, nil, msg, load_code)
                end
                local items = normalize_streams_payload(data_load)
                if not include_status then
                    return callback(true, items)
                end
                callback(true, items)
            end)
        end
        if not ok then
            local msg = trim(err or "fetch failed")
            if is_auth_error(code or msg) then
                return callback(false, nil, "login/password incorrect", code or 401)
            end
            return callback(false, nil, msg, code)
        end
        local items = normalize_streams_payload(data)
        local function continue_with_items(items_final)
            local stream_items = items_final or {}
            if not include_status then
                return callback(true, stream_items)
            end
            local function needs_status_probe(item)
                if type(item) ~= "table" then
                    return false
                end
                local has_on_air = item.on_air ~= nil
                local has_bitrate = tonumber(item.bitrate_kbps) ~= nil
                local has_active_input = item.active_input ~= nil
                return not (has_on_air and has_bitrate and has_active_input)
            end
            local function build_probe_list()
                local out = {}
                for _, item in ipairs(stream_items) do
                    if needs_status_probe(item) then
                        out[#out + 1] = item
                    end
                end
                return out
            end
            local function request_stream_status(sid, done)
                local client = adapter_ctx and adapter_ctx.client or nil
                if client and type(client.GetStreamStatus) == "function" then
                    return client:GetStreamStatus(sid, 1, function(ok_s, status_item, resp_s)
                        if ok_s and type(status_item) == "table" and not status_item.error then
                            return done(true, status_item, nil, nil)
                        end
                        local code_s = resp_s and resp_s.code or nil
                        local err_s = trim(status_item or "stream status failed")
                        return done(false, nil, err_s, code_s)
                    end)
                end
                astra_try_paths(cfg, adapter_ctx, {
                    method = "GET",
                    paths = {
                        "/api/stream-status/" .. sid .. "?t=1",
                        "/api/v1/stream-status/" .. sid .. "?t=1",
                    },
                }, function(ok_s, status_item, err_s, code_s)
                    if ok_s and type(status_item) == "table" and not status_item.error then
                        return done(true, status_item, nil, nil)
                    end
                    return done(false, nil, err_s, code_s)
                end)
            end
            local function enrich_per_stream_status(probe_items, opts)
                local targets = type(probe_items) == "table" and probe_items or {}
                local tolerate_auth = type(opts) == "table" and opts.tolerate_auth == true
                local pending = #targets
                if pending == 0 then
                    return callback(true, stream_items)
                end
                local index = 1
                local active = 0
                local finished = false
                local max_parallel = 6
                local function finish_with_error(err_text, err_code)
                    if finished then
                        return
                    end
                    finished = true
                    callback(false, nil, err_text, err_code)
                end
                local function finish_ok()
                    if finished then
                        return
                    end
                    finished = true
                    callback(true, stream_items)
                end
                local function launch_next()
                    while not finished and active < max_parallel and index <= #targets do
                        local item = targets[index]
                        index = index + 1
                        active = active + 1
                        local sid = trim(item and item.id)
                        if sid == "" then
                            active = active - 1
                            pending = pending - 1
                        else
                            request_stream_status(sid, function(ok_s, status_item, err_s, code_s)
                                active = math.max(0, active - 1)
                                pending = pending - 1
                                if ok_s and type(status_item) == "table" then
                                    apply_stream_status(item, status_item)
                                elseif is_auth_error(code_s or err_s) then
                                    if not tolerate_auth then
                                        return finish_with_error("login/password incorrect", code_s or 401)
                                    end
                                end
                                if pending <= 0 then
                                    return finish_ok()
                                end
                                launch_next()
                            end)
                        end
                    end
                    if not finished and pending <= 0 then
                        finish_ok()
                    end
                end
                launch_next()
            end
            astra_try_paths(cfg, adapter_ctx, {
                method = "GET",
                paths = {
                    "/api/stream-status?t=1",
                    "/api/v1/stream-status?t=1",
                },
            }, function(ok2, status_data, status_err, status_code)
                if ok2 and type(status_data) == "table" and not status_data.error then
                    merge_stream_status(stream_items, status_data)
                    local probe_items = build_probe_list()
                    if #probe_items == 0 then
                        return callback(true, stream_items)
                    end
                    return enrich_per_stream_status(probe_items)
                end
                -- Older Astra variants expose only per-stream status endpoints.
                if is_auth_error(status_code or status_err) then
                    return enrich_per_stream_status(build_probe_list(), { tolerate_auth = true })
                end
                return enrich_per_stream_status(build_probe_list())
            end)
        end

        if #items == 0 then
            return astra_load_streams_from_control(adapter_ctx, function(ok_load, loaded_items, load_err, load_code)
                if ok_load and type(loaded_items) == "table" and #loaded_items > 0 then
                    return continue_with_items(loaded_items)
                end
                if not ok_load and is_auth_error(load_code or load_err) then
                    return callback(false, nil, "login/password incorrect", load_code or 401)
                end
                return continue_with_items(items)
            end)
        end
        continue_with_items(items)
    end)
end

local function astra_get_stream(cfg, adapter_ctx, stream_id, callback)
    local sid = trim(stream_id)
    -- Prefer full config from control-load to avoid losing legacy keys on edit/save.
    astra_load_streams_from_control(adapter_ctx, function(ok_load, loaded_items, load_err, load_code)
        if ok_load then
            local list = type(loaded_items) == "table" and loaded_items or {}
            for _, row in ipairs(list) do
                if trim(row.id) == sid then
                    return callback(true, row)
                end
            end
        elseif is_auth_error(load_code or load_err) then
            return callback(false, nil, "login/password incorrect", load_code or 401)
        end

        -- Fallback to stream-info endpoints for legacy nodes where control load is unavailable.
        astra_try_paths(cfg, adapter_ctx, {
            method = "GET",
            paths = {
                "/api/stream-info/" .. sid,
                "/api/v1/stream-info/" .. sid,
                "/api/stream-info?id=" .. sid,
            },
        }, function(ok, data, err, code)
            if not ok then
                local msg = trim(err or "stream not found")
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
                local list = normalize_streams_payload(data)
                for _, row in ipairs(list) do
                    if trim(row.id) == sid then
                        item = row
                        break
                    end
                end
            end
            if not item then
                return callback(false, nil, "stream not found", 404)
            end
            callback(true, item)
        end)
    end)
end

local function astra_upsert_stream(cfg, adapter_ctx, stream, mode, callback)
    local stream_id = trim(stream and stream.id)
    if stream_id == "" then
        return callback(false, nil, "stream.id is required", 400)
    end
    local requested_cfg = type(stream.config) == "table" and stream.config or {}
    local function build_stream_cfg(existing_item)
        local base_cfg = existing_item and type(existing_item.config) == "table"
            and existing_item.config
            or {}
        local merged_cfg = merge_object_preserving_unknown(base_cfg, requested_cfg)
        merged_cfg = sanitize_stream_cfg_for_astra(merged_cfg)
        merged_cfg.id = stream_id
        merged_cfg.enable = stream.enabled ~= false
        return merged_cfg
    end

    local client = adapter_ctx.client
    local function set_stream(stream_cfg)
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

    if mode == "create" then
        -- Best effort create check.
        return astra_get_stream(cfg, adapter_ctx, stream_id, function(ok_get, _, get_err, get_code)
            if ok_get then
                return callback(false, nil, "stream already exists", 409)
            end
            if is_auth_error(get_code or get_err) then
                return callback(false, nil, "login/password incorrect", get_code or 401)
            end
            if get_code and get_code ~= 404 then
                return callback(false, nil, trim(get_err or "stream check failed"), get_code)
            end
            set_stream(build_stream_cfg(nil))
        end)
    end

    astra_get_stream(cfg, adapter_ctx, stream_id, function(ok_get, existing_item, get_err, get_code)
        if ok_get then
            return set_stream(build_stream_cfg(existing_item))
        end
        if is_auth_error(get_code or get_err) then
            return callback(false, nil, "login/password incorrect", get_code or 401)
        end
        if mode == "update" then
            if get_code == 404 then
                return callback(false, nil, "stream not found", 404)
            end
            return callback(false, nil, trim(get_err or "stream check failed"), get_code)
        end
        if get_code and get_code ~= 404 then
            return callback(false, nil, trim(get_err or "stream check failed"), get_code)
        end
        return set_stream(build_stream_cfg(nil))
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

local function astra_toggle_to(cfg, adapter_ctx, stream_id, desired_enabled, callback)
    astra_get_stream(cfg, adapter_ctx, stream_id, function(ok_get, item, get_err, get_code)
        if not ok_get then
            if is_auth_error(get_code or get_err) then
                return callback(false, nil, "login/password incorrect", get_code or 401)
            end
            return callback(false, nil, trim(get_err or "stream not found"), get_code)
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
        return astra_toggle_to(cfg, adapter_ctx, stream_id, true, callback)
    end
    if action == "disable" then
        return astra_toggle_to(cfg, adapter_ctx, stream_id, false, callback)
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
    end, { force = true })
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
            local out_items = type(items) == "table" and items or {}
            if #out_items > 0 then
                streams_cache_write(cfg, out_items)
            else
                local cached_items = streams_cache_read(cfg)
                if cached_items then
                    out_items = cached_items
                end
            end
            callback(true, {
                items = out_items,
                capabilities = cached.capabilities or {},
                api_type_effective = cached.api_type_effective,
                remote_version = cached.remote_version or "",
                auth_mode = cached.auth_mode or "none",
            })
        end
        if cached.api_type_effective == "stream_v1" then
            return stream_v1_list_streams(cfg, ctx, include_status, done)
        end
        if cached.api_type_effective == "dvr_v1" then
            return dvr_v1_list_streams(cfg, ctx, include_status, done)
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
            local out = {
                id = item.id,
                enabled = item.enabled ~= false,
                config = item.config or {},
                capabilities = cached.capabilities or {},
                api_type_effective = cached.api_type_effective,
                remote_version = cached.remote_version or "",
            }
            local passthrough_keys = {
                "name",
                "type",
                "on_air",
                "bitrate_kbps",
                "raw_bitrate_kbps",
                "cc_errors",
                "pes_errors",
                "uptime_sec",
                "active_input",
                "active_input_url",
                "last_error",
                "updated_at",
                "transcode_state",
            }
            for _, key in ipairs(passthrough_keys) do
                if item[key] ~= nil then
                    out[key] = item[key]
                end
            end
            if type(item.transcode) == "table" then
                out.transcode = item.transcode
            end
            if type(item.dvr) == "table" then
                out.dvr = item.dvr
            end
            callback(true, out)
        end
        if cached.api_type_effective == "stream_v1" then
            return stream_v1_get_stream(cfg, ctx, sid, done)
        end
        if cached.api_type_effective == "dvr_v1" then
            return dvr_v1_get_stream(cfg, ctx, sid, done)
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
        if cached.api_type_effective == "dvr_v1" then
            return dvr_v1_upsert_stream(cfg, ctx, stream, op_mode, done)
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
        if cached.api_type_effective == "dvr_v1" then
            return dvr_v1_delete_stream(cfg, ctx, sid, done)
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
        if cached.api_type_effective == "dvr_v1" then
            return dvr_v1_action(cfg, ctx, sid, act, input_index, done)
        end
        return astra_action(cfg, ctx, sid, act, input_index, done)
    end)
end

function remote_servers.dvr_upsert_streams(entry, items, callback)
    if type(items) ~= "table" then
        return callback(false, nil, "items payload required", 400)
    end
    local cfg, err = remote_servers.normalize(entry)
    if not cfg then
        return callback(false, nil, err or "invalid server", 400)
    end
    detect_adapter(cfg, function(ok, cached, detect_err, detect_code)
        if not ok then
            local code = classify_error_status(detect_err, detect_code)
            return callback(false, nil, detect_err or "probe failed", code)
        end
        if cached.api_type_effective ~= "dvr_v1" then
            return callback(false, nil, "target server is not DVR API", 400)
        end
        local ctx = cached.adapter_ctx or {}
        local pending = 0
        local imported = 0
        local failed = {}
        local function done_if_finished()
            if pending > 0 then
                return
            end
            callback(true, {
                status = "ok",
                imported = imported,
                failed = failed,
                total = #items,
                capabilities = cached.capabilities or {},
                api_type_effective = cached.api_type_effective,
            })
        end
        for _, item in ipairs(items) do
            pending = pending + 1
            stream_v1_request(cfg, ctx.auth, {
                method = "POST",
                path = "/api/v1/dvr/streams/upsert",
                body = item,
            }, function(ok_call, data_call, err_call, code_call)
                if ok_call then
                    imported = imported + 1
                else
                    failed[#failed + 1] = {
                        stream_id = trim(item and item.stream_id),
                        error = err_call or "upsert failed",
                        code = code_call,
                    }
                end
                pending = pending - 1
                done_if_finished()
            end)
        end
        if pending == 0 then
            done_if_finished()
        end
    end)
end

function remote_servers.dvr_storage_candidates(entry, payload, callback)
    local cfg, err = remote_servers.normalize(entry)
    if not cfg then
        return callback(false, nil, err or "invalid server", 400)
    end
    detect_adapter(cfg, function(ok, cached, detect_err, detect_code)
        if not ok then
            local code = classify_error_status(detect_err, detect_code)
            return callback(false, nil, detect_err or "probe failed", code)
        end
        if cached.api_type_effective ~= "dvr_v1" then
            return callback(false, nil, "target server is not DVR API", 400)
        end
        local ctx = cached.adapter_ctx or {}
        local query = ""
        if type(payload) == "table" and payload.refresh == true then
            query = "?refresh=1"
        end
        stream_v1_request(cfg, ctx.auth, {
            method = "GET",
            path = "/api/v1/dvr/storage/candidates" .. query,
        }, function(ok_call, data_call, err_call, code_call)
            if not ok_call then
                return callback(false, nil, err_call or "storage candidates failed", code_call)
            end
            callback(true, data_call or {
                ok = true,
                recommended_path = nil,
                candidates = {},
            })
        end)
    end)
end

function remote_servers.dvr_bulk_record(entry, payload, callback)
    local cfg, err = remote_servers.normalize(entry)
    if not cfg then
        return callback(false, nil, err or "invalid server", 400)
    end
    detect_adapter(cfg, function(ok, cached, detect_err, detect_code)
        if not ok then
            local code = classify_error_status(detect_err, detect_code)
            return callback(false, nil, detect_err or "probe failed", code)
        end
        if cached.api_type_effective ~= "dvr_v1" then
            return callback(false, nil, "target server is not DVR API", 400)
        end
        local ctx = cached.adapter_ctx or {}
        stream_v1_request(cfg, ctx.auth, {
            method = "POST",
            path = "/api/v1/dvr/streams/bulk-record",
            body = payload,
        }, function(ok_call, data_call, err_call, code_call)
            if not ok_call then
                return callback(false, nil, err_call or "bulk record failed", code_call)
            end
            callback(true, data_call or { status = "ok" })
        end)
    end)
end

function remote_servers.dvr_ingest_state(entry, payload, callback)
    local cfg, err = remote_servers.normalize(entry)
    if not cfg then
        return callback(false, nil, err or "invalid server", 400)
    end
    detect_adapter(cfg, function(ok, cached, detect_err, detect_code)
        if not ok then
            local code = classify_error_status(detect_err, detect_code)
            return callback(false, nil, detect_err or "probe failed", code)
        end
        if cached.api_type_effective ~= "dvr_v1" then
            return callback(false, nil, "target server is not DVR API", 400)
        end
        local ctx = cached.adapter_ctx or {}
        stream_v1_request(cfg, ctx.auth, {
            method = "POST",
            path = "/api/v1/dvr/ingest-state",
            body = payload,
        }, function(ok_call, data_call, err_call, code_call)
            if not ok_call then
                return callback(false, nil, err_call or "sync state failed", code_call)
            end
            callback(true, data_call or { status = "ok" })
        end)
    end)
end

local function normalize_dvr_stream_ids(stream_ids)
    local out = {}
    local seen = {}
    if type(stream_ids) ~= "table" then
        return out
    end
    for _, value in ipairs(stream_ids) do
        local sid = trim(value)
        if sid ~= "" and not seen[sid] then
            seen[sid] = true
            out[#out + 1] = sid
        end
    end
    return out
end

local function dvr_bulk_call_per_stream(entry, stream_ids, request_builder, callback)
    local cfg, err = remote_servers.normalize(entry)
    if not cfg then
        return callback(false, nil, err or "invalid server", 400)
    end
    detect_adapter(cfg, function(ok, cached, detect_err, detect_code)
        if not ok then
            local code = classify_error_status(detect_err, detect_code)
            return callback(false, nil, detect_err or "probe failed", code)
        end
        if cached.api_type_effective ~= "dvr_v1" then
            return callback(false, nil, "target server is not DVR API", 400)
        end
        local ids = normalize_dvr_stream_ids(stream_ids)
        if #ids == 0 then
            return callback(false, nil, "stream_ids is required", 400)
        end
        local ctx = cached.adapter_ctx or {}
        local pending = #ids
        local affected = 0
        local failed = {}
        local details = {}
        local function done_if_finished()
            if pending > 0 then
                return
            end
            callback(true, {
                ok = true,
                total = #ids,
                affected = affected,
                failed = failed,
                items = details,
            })
        end
        for _, sid in ipairs(ids) do
            local req = request_builder(sid) or {}
            stream_v1_request(cfg, ctx.auth, req, function(ok_call, data_call, err_call, code_call)
                if ok_call then
                    affected = affected + 1
                    details[#details + 1] = {
                        stream_id = sid,
                        ok = true,
                        data = data_call,
                    }
                else
                    failed[#failed + 1] = {
                        stream_id = sid,
                        error = err_call or "request failed",
                        code = code_call,
                    }
                    details[#details + 1] = {
                        stream_id = sid,
                        ok = false,
                        error = err_call or "request failed",
                        code = code_call,
                    }
                end
                pending = pending - 1
                done_if_finished()
            end)
        end
    end)
end

local function dvr_backup_cursor_reset_per_stream(entry, payload, callback)
    payload = type(payload) == "table" and payload or {}
    return dvr_bulk_call_per_stream(entry, payload.stream_ids, function(stream_id)
        return {
            method = "POST",
            path = "/api/v1/dvr/backup/cursor/reset",
            body = {
                stream_id = stream_id,
            },
        }
    end, callback)
end

local function dvr_backup_cycle_rebuild_per_stream(entry, payload, callback)
    payload = type(payload) == "table" and payload or {}
    local include_partial = payload.include_partial
    local min_partial_sec = payload.min_partial_sec
    local start_mode = payload.start_mode
    local start_offset_hours = payload.start_offset_hours
    local now_ts = payload.now_ts
    return dvr_bulk_call_per_stream(entry, payload.stream_ids, function(stream_id)
        local body = {
            stream_id = stream_id,
        }
        if include_partial ~= nil then
            body.include_partial = include_partial
        end
        if min_partial_sec ~= nil then
            body.min_partial_sec = min_partial_sec
        end
        if start_mode ~= nil then
            body.start_mode = start_mode
        end
        if start_offset_hours ~= nil then
            body.start_offset_hours = start_offset_hours
        end
        if now_ts ~= nil then
            body.now_ts = now_ts
        end
        return {
            method = "POST",
            path = "/api/v1/dvr/backup/cycle/rebuild",
            body = body,
        }
    end, callback)
end

function remote_servers.dvr_backup_cursor_reset(entry, payload, callback)
    payload = type(payload) == "table" and payload or {}
    local ids = normalize_dvr_stream_ids(payload.stream_ids)
    if #ids == 0 then
        return callback(false, nil, "stream_ids is required", 400)
    end
    local cfg, err = remote_servers.normalize(entry)
    if not cfg then
        return callback(false, nil, err or "invalid server", 400)
    end
    detect_adapter(cfg, function(ok, cached, detect_err, detect_code)
        if not ok then
            local code = classify_error_status(detect_err, detect_code)
            return callback(false, nil, detect_err or "probe failed", code)
        end
        if cached.api_type_effective ~= "dvr_v1" then
            return callback(false, nil, "target server is not DVR API", 400)
        end
        local ctx = cached.adapter_ctx or {}
        stream_v1_request(cfg, ctx.auth, {
            method = "POST",
            path = "/api/v1/dvr/backup/cursor/reset-bulk",
            body = { stream_ids = ids },
        }, function(ok_call, data_call, err_call, code_call)
            if ok_call then
                return callback(true, data_call or { ok = true, total = #ids, affected = 0, failed = {}, items = {} })
            end
            if tonumber(code_call) == 404 then
                return dvr_backup_cursor_reset_per_stream(entry, { stream_ids = ids }, callback)
            end
            return callback(false, nil, err_call or "backup cursor reset failed", code_call)
        end)
    end)
end

function remote_servers.dvr_backup_cycle_rebuild(entry, payload, callback)
    payload = type(payload) == "table" and payload or {}
    local ids = normalize_dvr_stream_ids(payload.stream_ids)
    if #ids == 0 then
        return callback(false, nil, "stream_ids is required", 400)
    end
    local cfg, err = remote_servers.normalize(entry)
    if not cfg then
        return callback(false, nil, err or "invalid server", 400)
    end
    local include_partial = payload.include_partial
    local min_partial_sec = payload.min_partial_sec
    local start_mode = payload.start_mode
    local start_offset_hours = payload.start_offset_hours
    local now_ts = payload.now_ts
    detect_adapter(cfg, function(ok, cached, detect_err, detect_code)
        if not ok then
            local code = classify_error_status(detect_err, detect_code)
            return callback(false, nil, detect_err or "probe failed", code)
        end
        if cached.api_type_effective ~= "dvr_v1" then
            return callback(false, nil, "target server is not DVR API", 400)
        end
        local ctx = cached.adapter_ctx or {}
        local body = { stream_ids = ids }
        if include_partial ~= nil then
            body.include_partial = include_partial
        end
        if min_partial_sec ~= nil then
            body.min_partial_sec = min_partial_sec
        end
        if start_mode ~= nil then
            body.start_mode = start_mode
        end
        if start_offset_hours ~= nil then
            body.start_offset_hours = start_offset_hours
        end
        if now_ts ~= nil then
            body.now_ts = now_ts
        end
        stream_v1_request(cfg, ctx.auth, {
            method = "POST",
            path = "/api/v1/dvr/backup/cycle/rebuild-bulk",
            body = body,
        }, function(ok_call, data_call, err_call, code_call)
            if ok_call then
                return callback(true, data_call or { ok = true, total = #ids, affected = 0, failed = {}, items = {} })
            end
            if tonumber(code_call) == 404 then
                return dvr_backup_cycle_rebuild_per_stream(entry, {
                    stream_ids = ids,
                    include_partial = include_partial,
                    min_partial_sec = min_partial_sec,
                    start_mode = start_mode,
                    start_offset_hours = start_offset_hours,
                    now_ts = now_ts,
                }, callback)
            end
            return callback(false, nil, err_call or "backup cycle rebuild failed", code_call)
        end)
    end)
end

remote_servers.classify_error_status = classify_error_status

return remote_servers
