-- REST API layer

api = {}

local API_HTTP_METRIC_WINDOW_SEC = 60
local API_HTTP_METRIC_SAMPLE_MAX = 256
local API_HTTP_METRIC_ROUTE_LIMIT = 40
local API_HTTP_AUTH_LOG_INTERVAL_SEC = 30

local api_request_context = {}
local api_request_seq = 0
local api_auth_log_state = {}

local api_http_metrics = {
    totals = {
        requests = 0,
        errors = 0,
    },
    status_codes = {},
    auth_codes = {
        [401] = 0,
        [403] = 0,
        [302] = 0,
    },
    buckets = {},
    routes = {},
}

local function metric_now_sec()
    return os.time()
end

local function metric_now_ms()
    return os.clock() * 1000
end

local function next_request_id()
    api_request_seq = api_request_seq + 1
    local seq = api_request_seq
    if seq > 999999999 then
        seq = 1
        api_request_seq = 1
    end
    return string.format("req-%d-%06d", os.time(), seq % 1000000)
end

local function client_ctx_key(client)
    return tostring(client or "")
end

local function normalize_metric_path(path)
    local out = tostring(path or "/")
    local query_idx = out:find("?", 1, true)
    if query_idx then
        out = out:sub(1, query_idx - 1)
    end
    if out == "" then
        out = "/"
    end

    out = out
        :gsub("^(/api/v1/streams/)[%w%-%_%.]+", "%1:id")
        :gsub("^(/api/v1/stream%-status/)[%w%-%_%.]+", "%1:id")
        :gsub("^(/api/v1/adapters/)[%w%-%_%.]+", "%1:id")
        :gsub("^(/api/v1/splitters/)[%w%-%_%.]+", "%1:id")
        :gsub("^(/api/v1/buffers/resources/)[%w%-%_%.]+", "%1:id")
        :gsub("^(/api/v1/buffer%-status/)[%w%-%_%.]+", "%1:id")
        :gsub("^(/api/v1/transcode%-status/)[%w%-%_%.]+", "%1:id")
        :gsub("^(/api/v1/transcode/)[%w%-%_%.]+", "%1:id")
        :gsub("^(/api/v1/sessions/)[%w%-%_%.]+", "%1:id")
        :gsub("^(/api/v1/users/)[%w%-%_%.]+", "%1:id")
        :gsub("^(/api/v1/dvb%-scan/)[%w%-%_%.]+", "%1:id")
        :gsub("^(/api/v1/dvb%-full%-scan/)[%w%-%_%.]+", "%1:id")
        :gsub("^(/api/v1/pngts/jobs/)[%w%-%_%.]+", "%1:id")
    return out
end

local function metric_bucket_inc(buckets, ts_sec)
    if type(buckets) ~= "table" then
        return
    end
    local key = tonumber(ts_sec) or metric_now_sec()
    buckets[key] = (tonumber(buckets[key]) or 0) + 1
end

local function metric_bucket_sum_window(buckets, now_sec, window_sec)
    if type(buckets) ~= "table" then
        return 0
    end
    local total = 0
    for ts, count in pairs(buckets) do
        local sec = tonumber(ts) or 0
        if (now_sec - sec) <= window_sec then
            total = total + (tonumber(count) or 0)
        elseif (now_sec - sec) > (window_sec * 2) then
            buckets[ts] = nil
        end
    end
    return total
end

local function metric_latency_push(route, latency_ms)
    if type(route) ~= "table" then
        return
    end
    local value = tonumber(latency_ms) or 0
    if value < 0 then
        value = 0
    end
    route.lat_idx = (tonumber(route.lat_idx) or 0) + 1
    if route.lat_idx > API_HTTP_METRIC_SAMPLE_MAX then
        route.lat_idx = 1
    end
    route.latencies = route.latencies or {}
    route.latencies[route.lat_idx] = value
end

local function metric_percentile(samples, ratio)
    if type(samples) ~= "table" then
        return 0
    end
    local sorted = {}
    for _, value in pairs(samples) do
        local n = tonumber(value)
        if n then
            sorted[#sorted + 1] = n
        end
    end
    local count = #sorted
    if count == 0 then
        return 0
    end
    table.sort(sorted)
    local idx = math.floor((count - 1) * ratio + 1.5)
    if idx < 1 then
        idx = 1
    elseif idx > count then
        idx = count
    end
    return sorted[idx]
end

local function metric_error_rate_pct(errors, requests)
    local req = tonumber(requests) or 0
    if req <= 0 then
        return 0
    end
    local err = tonumber(errors) or 0
    return (err * 100.0) / req
end

local function record_api_request_metric(ctx, status_code)
    if type(ctx) ~= "table" then
        return
    end
    local code = tonumber(status_code) or 0
    local now_sec = metric_now_sec()
    local elapsed_ms = math.max(0, metric_now_ms() - (tonumber(ctx.started_ms) or 0))
    local method = tostring(ctx.method or "GET")
    local endpoint = tostring(ctx.endpoint or "/")
    local route_key = method .. " " .. endpoint

    local m = api_http_metrics
    m.totals.requests = (tonumber(m.totals.requests) or 0) + 1
    if code >= 400 then
        m.totals.errors = (tonumber(m.totals.errors) or 0) + 1
    end
    m.status_codes[code] = (tonumber(m.status_codes[code]) or 0) + 1
    if code == 401 or code == 403 or code == 302 then
        m.auth_codes[code] = (tonumber(m.auth_codes[code]) or 0) + 1
    end
    metric_bucket_inc(m.buckets, now_sec)

    local route = m.routes[route_key]
    if not route then
        route = {
            method = method,
            endpoint = endpoint,
            requests = 0,
            errors = 0,
            status_codes = {},
            buckets = {},
            latencies = {},
            lat_idx = 0,
            last_latency_ms = 0,
            last_seen_ts = 0,
        }
        m.routes[route_key] = route
    end

    route.requests = (tonumber(route.requests) or 0) + 1
    if code >= 400 then
        route.errors = (tonumber(route.errors) or 0) + 1
    end
    route.status_codes[code] = (tonumber(route.status_codes[code]) or 0) + 1
    route.last_latency_ms = elapsed_ms
    route.last_seen_ts = now_sec
    metric_bucket_inc(route.buckets, now_sec)
    metric_latency_push(route, elapsed_ms)

    if code >= 400 or elapsed_ms >= 1000 then
        local req_id = tostring(ctx.request_id or "")
        if (code == 401 or code == 403 or code == 302) and elapsed_ms < 1000 then
            local auth_key = route_key .. "#" .. tostring(code)
            local st = api_auth_log_state[auth_key]
            if not st then
                st = { last_ts = 0, suppressed = 0 }
                api_auth_log_state[auth_key] = st
            end
            if (now_sec - (tonumber(st.last_ts) or 0)) >= API_HTTP_AUTH_LOG_INTERVAL_SEC then
                local suppressed = tonumber(st.suppressed) or 0
                local suffix = ""
                if suppressed > 0 then
                    suffix = string.format(" (suppressed=%d)", suppressed)
                end
                log.info(string.format("[api] req=%s %s %s -> %d in %.0fms%s",
                    req_id, method, endpoint, code, elapsed_ms, suffix))
                st.last_ts = now_sec
                st.suppressed = 0
            else
                st.suppressed = (tonumber(st.suppressed) or 0) + 1
            end
        else
            log.warning(string.format("[api] req=%s %s %s -> %d in %.0fms",
                req_id, method, endpoint, code, elapsed_ms))
        end
    end
end

local function api_http_metrics_snapshot(limit)
    local now_sec = metric_now_sec()
    local top_limit = tonumber(limit) or API_HTTP_METRIC_ROUTE_LIMIT
    if top_limit < 1 then
        top_limit = 1
    elseif top_limit > 200 then
        top_limit = 200
    end

    local m = api_http_metrics
    local total_rps = metric_bucket_sum_window(m.buckets, now_sec, API_HTTP_METRIC_WINDOW_SEC) / API_HTTP_METRIC_WINDOW_SEC
    local routes = {}

    for _, route in pairs(m.routes) do
        local route_rps = metric_bucket_sum_window(route.buckets, now_sec, API_HTTP_METRIC_WINDOW_SEC) / API_HTTP_METRIC_WINDOW_SEC
        routes[#routes + 1] = {
            method = route.method,
            endpoint = route.endpoint,
            requests = tonumber(route.requests) or 0,
            errors = tonumber(route.errors) or 0,
            error_rate_pct = metric_error_rate_pct(route.errors, route.requests),
            rps = route_rps,
            p50_ms = metric_percentile(route.latencies, 0.50),
            p95_ms = metric_percentile(route.latencies, 0.95),
            p99_ms = metric_percentile(route.latencies, 0.99),
            last_latency_ms = tonumber(route.last_latency_ms) or 0,
            status_codes = route.status_codes or {},
        }
    end

    table.sort(routes, function(a, b)
        if (a.requests or 0) == (b.requests or 0) then
            return tostring(a.endpoint or "") < tostring(b.endpoint or "")
        end
        return (a.requests or 0) > (b.requests or 0)
    end)

    local out_routes = {}
    local max_idx = math.min(#routes, top_limit)
    for i = 1, max_idx do
        out_routes[i] = routes[i]
    end

    return {
        window_sec = API_HTTP_METRIC_WINDOW_SEC,
        totals = {
            requests = tonumber(m.totals.requests) or 0,
            errors = tonumber(m.totals.errors) or 0,
            error_rate_pct = metric_error_rate_pct(m.totals.errors, m.totals.requests),
            rps = total_rps,
            status_codes = m.status_codes or {},
            auth_codes = m.auth_codes or {},
        },
        endpoints = out_routes,
    }
end

local function ensure_server_send_wrapper(server)
    if type(server) ~= "table" then
        return
    end
    if server.__api_send_wrapped then
        return
    end
    local original_send = server.send
    if type(original_send) ~= "function" then
        return
    end
    server.send = function(self, client, payload)
        local key = client_ctx_key(client)
        local ctx = api_request_context[key]
        if ctx and type(payload) == "table" then
            payload.headers = payload.headers or {}
            local has_req_id = false
            if type(payload.headers) == "table" then
                for _, h in ipairs(payload.headers) do
                    if type(h) == "string" and h:lower():find("^x%-request%-id:%s*") then
                        has_req_id = true
                        break
                    end
                end
            end
            if (not has_req_id) and ctx.request_id and ctx.request_id ~= "" then
                table.insert(payload.headers, "X-Request-Id: " .. tostring(ctx.request_id))
            end
            if not ctx.completed then
                ctx.completed = true
                record_api_request_metric(ctx, payload.code)
                api_request_context[key] = nil
            end
        end
        return original_send(self, client, payload)
    end
    server.__api_send_wrapped = true
end

function json_response(server, client, code, payload)
    server:send(client, {
        code = code,
        headers = {
            "Content-Type: application/json",
            "Cache-Control: no-cache",
            "Connection: close",
        },
        content = json.encode(payload or {}),
    })
end

function error_response(server, client, code, message)
    json_response(server, client, code, { error = message })
end

local function rate_limit_response(server, client, retry_after, message)
    local headers = {
        "Content-Type: application/json",
        "Cache-Control: no-cache",
        "Connection: close",
    }
    if retry_after and retry_after > 0 then
        table.insert(headers, "Retry-After: " .. tostring(retry_after))
    end
    server:send(client, {
        code = 429,
        headers = headers,
        content = json.encode({ error = message or "rate limited" }),
    })
end

function parse_json_body(request)
    if not request or not request.content then
        return nil
    end
    return json.decode(request.content)
end

function safe_tostring(value)
    if value == nil then
        return ""
    end
    return tostring(value)
end

local function shell_escape(value)
    local text = tostring(value or "")
    return "'" .. text:gsub("'", "'\\''") .. "'"
end

local function has_timeout()
    local ok = os.execute("command -v timeout >/dev/null 2>&1")
    return ok == true or ok == 0
end

local function run_command(cmd, timeout_sec)
    local timeout_cmd = ""
    if timeout_sec and timeout_sec > 0 then
        if has_timeout() then
            timeout_cmd = "timeout " .. tostring(math.floor(timeout_sec)) .. " "
        else
            return nil, "timeout tool missing"
        end
    end
    local ok, handle = pcall(io.popen, timeout_cmd .. cmd .. " 2>&1")
    if not ok or not handle then
        return nil, "exec failed"
    end
    local output = handle:read("*a") or ""
    handle:close()
    return output
end

local function get_header(headers, key)
    if not headers then
        return nil
    end
    return headers[key] or headers[string.lower(key)]
end

local function setting_number(key, fallback)
    if not config or not config.get_setting then
        return fallback
    end
    local value = config.get_setting(key)
    local number = tonumber(value)
    if number == nil then
        return fallback
    end
    return number
end

local function setting_bool(key, fallback)
    if not config or not config.get_setting then
        return fallback
    end
    local value = config.get_setting(key)
    if value == nil then
        return fallback
    end
    if value == true or value == 1 or value == "1" then
        return true
    end
    return false
end

local function auth_enabled()
    return setting_bool("http_auth_enabled", false)
end

local function setting_string(key, fallback)
    if not config or not config.get_setting then
        return fallback
    end
    local value = config.get_setting(key)
    if value == nil or value == "" then
        return fallback
    end
    return tostring(value)
end

local remote_servers = nil
do
    local function load_remote_servers()
        local injected = rawget(_G, "__stream_remote_servers")
        if type(injected) == "table" then
            return injected
        end

        local ok, mod = pcall(require, "remote_servers")
        if ok and type(mod) == "table" then
            return mod
        end

        local candidates = {
            "scripts/remote_servers.lua",
            "remote_servers.lua",
        }
        local dbg = (type(debug) == "table") and debug or nil
        local src = dbg and dbg.getinfo and dbg.getinfo(1, "S")
        if src and type(src.source) == "string" and src.source:sub(1, 1) == "@" then
            local api_path = src.source:sub(2)
            local api_dir = api_path:match("^(.*[\\/])[^\\/]+$")
            if api_dir and api_dir ~= "" then
                table.insert(candidates, api_dir .. "remote_servers.lua")
            end
        end

        local last_err = tostring(mod)
        for _, path in ipairs(candidates) do
            local loaded, payload = pcall(dofile, path)
            if loaded and type(payload) == "table" then
                return payload
            end
            last_err = tostring(payload)
        end
        return nil, last_err
    end

    local mod, err = load_remote_servers()
    if type(mod) == "table" then
        remote_servers = mod
    else
        log.warning("[servers] remote adapters unavailable: " .. tostring(err))
    end
end

local dvr_store = nil
do
    local function load_dvr_store()
        local injected = rawget(_G, "__stream_dvr")
        if type(injected) == "table" then
            return injected
        end
        if type(rawget(_G, "dvr")) == "table" then
            return rawget(_G, "dvr")
        end
        local ok, mod = pcall(require, "dvr")
        if ok and type(mod) == "table" then
            return mod
        end
        local candidates = {
            "scripts/dvr.lua",
            "dvr.lua",
        }
        local dbg = (type(debug) == "table") and debug or nil
        local src = dbg and dbg.getinfo and dbg.getinfo(1, "S")
        if src and type(src.source) == "string" and src.source:sub(1, 1) == "@" then
            local api_path = src.source:sub(2)
            local api_dir = api_path:match("^(.*[\\/])[^\\/]+$")
            if api_dir and api_dir ~= "" then
                table.insert(candidates, api_dir .. "dvr.lua")
            end
        end
        local last_err = ""
        for _, path in ipairs(candidates) do
            local loaded, payload = pcall(dofile, path)
            if loaded and type(payload) == "table" then
                return payload
            end
            if type(rawget(_G, "dvr")) == "table" then
                return rawget(_G, "dvr")
            end
            last_err = tostring(payload)
        end
        return nil, last_err
    end

    local mod, err = load_dvr_store()
    if type(mod) == "table" then
        dvr_store = mod
    else
        log.warning("[dvr] module unavailable: " .. tostring(err))
    end
end

local function is_state_change(method)
    return method == "POST" or method == "PUT" or method == "DELETE" or method == "PATCH"
end

local function has_bearer_auth(request)
    local auth = request and request.headers and get_header(request.headers, "authorization") or nil
    return auth and auth:find("Bearer ") == 1
end

local function parse_cookie(headers)
    local cookie = get_header(headers, "cookie")
    if not cookie then
        return nil
    end
    local out = {}
    for part in string.gmatch(cookie, "[^;]+") do
        local key, value = part:match("^%s*(.-)%s*=%s*(.*)$")
        if key and value then
            out[key] = value
        end
    end
    return out
end

local function get_token(request)
    local auth = get_header(request.headers, "authorization")
    if auth and auth:find("Bearer ") == 1 then
        return auth:sub(8)
    end

    local cookies = parse_cookie(request.headers)
    if cookies then
        if cookies.stream_session then
            return cookies.stream_session
        end
        if cookies.astra_session then
            return cookies.astra_session
        end
    end

    return nil
end

local function csrf_required(request)
    if not auth_enabled() then
        return false
    end
    if not request or not is_state_change(request.method or "GET") then
        return false
    end
    if has_bearer_auth(request) then
        return false
    end
    return setting_bool("http_csrf_enabled", true)
end

local function check_csrf(request, session)
    if not csrf_required(request) then
        return true
    end
    local header = get_header(request.headers, "x-csrf-token")
    if not header or header == "" then
        return false
    end
    return session and session.token and header == session.token
end

local rate_limits = {
    login = {},
    remote_actions = {},
    counter = 0,
}

local auth_session_ttl_cache = {
    ts = 0,
    value = nil,
}

local function get_auth_session_ttl()
    local now = os.time()
    local cached = auth_session_ttl_cache.value
    if cached ~= nil and (now - auth_session_ttl_cache.ts) < 10 then
        return cached
    end
    local ttl = setting_number("auth_session_ttl_sec", 3600)
    if ttl < 300 then
        ttl = 300
    end
    auth_session_ttl_cache.ts = now
    auth_session_ttl_cache.value = ttl
    return ttl
end

local dvb_scan = {
    seq = 0,
    jobs = {},
}

local stream_analyze = {
    seq = 0,
    jobs = {},
    active = 0,
}

local dvb_autosearch = {
    timer = nil,
    queue = {},
    queue_index = {},
    active = nil,
    seq = 0,
    adapter_history = {},
    adapter_state = {},
    stream_fault_state = {},
    attempts = {},
    recent_attempts = {},
    frozen_until_ts = 0,
    lock_owner = "",
    lock_ts = 0,
}

local dvb_full_scan = {
    seq = 0,
    jobs = {},
    active_id = nil,
}

local DVB_ADAPTER_TUNE_FIELDS = {
    "type",
    "tp",
    "lnb",
    "lof1",
    "lof2",
    "slof",
    "diseqc",
    "tone",
    "rolloff",
    "uni_scr",
    "uni_frequency",
    "frequency",
    "polarization",
    "symbolrate",
    "bandwidth",
    "guardinterval",
    "transmitmode",
    "hierarchy",
    "modulation",
    "stream_id",
    "budget",
}

local function deep_copy(value, seen)
    if type(value) ~= "table" then
        return value
    end
    seen = seen or {}
    if seen[value] then
        return seen[value]
    end
    local out = {}
    seen[value] = out
    for k, v in pairs(value) do
        out[deep_copy(k, seen)] = deep_copy(v, seen)
    end
    return out
end

local function clamp_number(value, min_value, max_value)
    local n = tonumber(value)
    if n == nil then
        return nil
    end
    if min_value ~= nil and n < min_value then
        n = min_value
    end
    if max_value ~= nil and n > max_value then
        n = max_value
    end
    return n
end

local function normalize_bool(value, fallback)
    if value == nil then
        return fallback
    end
    if value == true or value == 1 or value == "1" or value == "true" or value == "yes" or value == "on" then
        return true
    end
    if value == false or value == 0 or value == "0" or value == "false" or value == "no" or value == "off" then
        return false
    end
    return fallback
end

local function sql_escape(value)
    return tostring(value or ""):gsub("'", "''")
end

local function db_exec_safe(sql)
    if not (config and config.db and sql and sql ~= "") then
        return nil, "database unavailable"
    end
    local ok, err = config.db:exec(sql)
    if ok ~= true then
        return nil, tostring(err or "exec failed")
    end
    return true
end

local function db_query_safe(sql)
    if not (config and config.db and sql and sql ~= "") then
        return nil, "database unavailable"
    end
    local rows, err = config.db:query(sql)
    if not rows then
        return nil, tostring(err or "query failed")
    end
    return rows
end

local function db_scalar_safe(sql)
    local rows, err = db_query_safe(sql)
    if not rows then
        return nil, err
    end
    if #rows == 0 then
        return nil, nil
    end
    for _, value in pairs(rows[1]) do
        return value, nil
    end
    return nil, nil
end

local function mpts_scan(server, client, request)
    local body = parse_json_body(request)
    if not body or not body.input then
        return error_response(server, client, 400, "input required")
    end
    local input = tostring(body.input or "")
    if input == "" then
        return error_response(server, client, 400, "input required")
    end
    if #input > 512 then
        return error_response(server, client, 400, "input too long")
    end

    local cfg = parse_url(input)
    if not cfg or not cfg.format then
        return error_response(server, client, 400, "invalid input")
    end
    local format = tostring(cfg.format or ""):lower()
    if format ~= "udp" and format ~= "rtp" then
        return error_response(server, client, 400, "only udp/rtp inputs supported")
    end
    local addr = tostring(cfg.addr or "")
    local port = tonumber(cfg.port)
    if addr == "" or not port then
        return error_response(server, client, 400, "invalid input addr/port")
    end

    local duration = tonumber(body.duration) or 3
    if duration < 1 then duration = 1 end
    if duration > 10 then duration = 10 end

    local script_path = "tools/mpts_pat_scan.py"
    local handle = io.open(script_path, "r")
    if not handle then
        return error_response(server, client, 500, "mpts_pat_scan.py not found")
    end
    handle:close()

    local cmd = table.concat({
        "python3",
        shell_escape(script_path),
        "--addr",
        shell_escape(addr),
        "--port",
        shell_escape(port),
        "--duration",
        shell_escape(duration),
        "--input",
        shell_escape(input),
        "--pretty",
    }, " ")
    local output, err = run_command(cmd, duration + 2)
    if not output or output == "" then
        return error_response(server, client, 500, err or "empty output")
    end
    local ok, parsed = pcall(json.decode, output)
    if not ok or type(parsed) ~= "table" then
        return error_response(server, client, 500, "scan failed: invalid output")
    end
    local services = parsed.services or {}
    return json_response(server, client, 200, { services = services })
end

function dvb_scan_cleanup()
    local now = os.time()
    for id, job in pairs(dvb_scan.jobs) do
        if job and job.status ~= "running" and job.finished_at and (now - job.finished_at) > 300 then
            dvb_scan.jobs[id] = nil
        end
    end
end

local function stream_analyze_cleanup()
    local now = os.time()
    for id, job in pairs(stream_analyze.jobs) do
        if job and job.status ~= "running" and job.finished_at and (now - job.finished_at) > 300 then
            stream_analyze.jobs[id] = nil
        end
    end
end

local function rate_limit_check(bucket, key, limit, window_sec)
    if limit <= 0 then
        return true, nil
    end
    local now = os.time()
    local entry = bucket[key]
    if not entry or (now - entry.window_start) >= window_sec then
        entry = { window_start = now, count = 0 }
        bucket[key] = entry
    end
    entry.count = entry.count + 1
    if entry.count > limit then
        return false, entry
    end
    return true, entry
end

local function prune_rate_limits(bucket, window_sec)
    local now = os.time()
    for key, entry in pairs(bucket) do
        if not entry or (now - entry.window_start) >= (window_sec * 2) then
            bucket[key] = nil
        end
    end
end

local function require_auth(request)
    if not auth_enabled() then
        -- В режиме "без авторизации" (например --no-web-auth) API открыто.
        -- Возвращаем "виртуальную" сессию admin, чтобы require_admin() тоже работал.
        local admin = config and config.get_user_by_username and config.get_user_by_username("admin") or nil
        local admin_id = admin and tonumber(admin.id) or 0
        return {
            user_id = admin_id,
            expires_at = os.time() + 365 * 24 * 3600,
            token = "",
        }
    end

    local token = get_token(request)
    if not token then
        return nil
    end
    local session = config.get_session(token)
    if not session then
        return nil
    end

    -- Sliding expiration: extend session on activity to reduce repeated logins.
    -- Update is throttled (only when remaining TTL is below 50%).
    if config.extend_session then
        local ttl = get_auth_session_ttl()
        local exp = tonumber(session.expires_at) or 0
        local now = os.time()
        local remaining = exp - now
        if remaining < math.floor(ttl * 0.5) then
            local new_exp = now + ttl
            config.extend_session(token, new_exp)
            session.expires_at = new_exp
        end
    end

    return session
end

local function require_admin(request)
    local session = require_auth(request)
    if not session then
        return nil
    end
    local user = config.get_user_by_id and config.get_user_by_id(session.user_id)
    if not user then
        return nil
    end
    if tonumber(user.is_admin) ~= 1 then
        return nil
    end
    return user
end

local function is_internal_loopback(request)
    if not request then
        return false
    end
    local ip = tostring(request.addr or "")
    local lower = ip:lower()
    if not (ip == "127.0.0.1" or ip == "::1" or ip:match("^127%.") or lower:match("^::ffff:127%.")) then
        return false
    end
    local headers = request.headers or {}
    if headers["x-forwarded-for"] or headers["X-Forwarded-For"]
        or headers["forwarded"] or headers["Forwarded"]
        or headers["x-real-ip"] or headers["X-Real-IP"] then
        return false
    end
    return true
end

local function audit_event(action, request, opts)
    if not config.add_audit_event or not config.db then
        return
    end
    opts = opts or {}
    opts.ip = opts.ip or (request and request.addr) or ""
    local ok, err = pcall(config.add_audit_event, action, opts)
    if not ok then
        log.warning("[api] audit skipped: " .. tostring(err))
    end
end

local function get_request_user(request)
    local session = require_auth(request)
    if not session then
        return nil
    end
    return config.get_user_by_id and config.get_user_by_id(session.user_id)
end

local function format_refresh_errors(errors)
    if type(errors) ~= "table" or #errors == 0 then
        return nil
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

local function read_text_file(path)
    local file, err = io.open(path, "rb")
    if not file then
        return nil, err
    end
    local content = file:read("*a")
    file:close()
    return content
end

local function detect_license(text)
    if not text or text == "" then
        return "Unknown", nil
    end
    if text:find("GNU GENERAL PUBLIC LICENSE") then
        local version = text:match("Version%s+([0-9%.]+)")
        local spdx = "GPL"
        if version then
            spdx = "GPL-" .. version
            if not version:find("%.") then
                spdx = spdx .. ".0"
            end
            return "GNU General Public License v" .. version, spdx
        end
        return "GNU General Public License", spdx
    end
    if text:find("GNU LESSER GENERAL PUBLIC LICENSE") then
        local version = text:match("Version%s+([0-9%.]+)")
        local spdx = "LGPL"
        if version then
            spdx = "LGPL-" .. version
            if not version:find("%.") then
                spdx = spdx .. ".0"
            end
            return "GNU Lesser General Public License v" .. version, spdx
        end
        return "GNU Lesser General Public License", spdx
    end
    return "Custom License", nil
end

local function license_info(server, client)
    local path = "COPYING"
    local text, err = read_text_file(path)
    if not text then
        return error_response(server, client, 500, "license file not found")
    end
    local name, spdx = detect_license(text)
    json_response(server, client, 200, {
        name = name,
        spdx = spdx,
        path = path,
        text = text,
    })
end

local function reload_runtime(force)
    local errors = {}
    if runtime and runtime.refresh_adapters then
        runtime.refresh_adapters(force)
    end
    local ok, stream_errors = runtime.refresh(force)
    if ok == false then
        local detail = format_refresh_errors(stream_errors) or "stream refresh failed"
        table.insert(errors, detail)
    end
    if splitter and splitter.refresh then
        splitter.refresh(force)
    end
    if buffer and buffer.refresh then
        buffer.refresh()
    end
    if #errors > 0 then
        return nil, table.concat(errors, "; "), stream_errors
    end
    return true
end

local function validate_config_payload(payload)
    local errors = {}
    local warnings = {}
    local ok, err = config.validate_payload(payload)
    if not ok then
        table.insert(errors, { path = "config", message = err or "invalid config" })
        return errors, warnings
    end

    local lint_errors, lint_warnings = config.lint_payload(payload)
    for _, item in ipairs(lint_errors or {}) do
        table.insert(errors, { path = "config", message = item })
    end
    for _, item in ipairs(lint_warnings or {}) do
        table.insert(warnings, { path = "config", message = item })
    end

    local function check_stream_list(list, label)
        if type(list) ~= "table" then
            return
        end
        local seen = {}
        for idx, entry in ipairs(list) do
            if type(entry) == "table" then
                local id = tostring(entry.id or "")
                if id ~= "" then
                    if seen[id] then
                        table.insert(errors, { path = label .. "[" .. idx .. "]", message = "duplicate id: " .. id })
                    else
                        seen[id] = true
                    end
                end
                if type(validate_stream_config) == "function" then
                    local ok, err = validate_stream_config(entry)
                    if not ok then
                        table.insert(errors, { path = label .. "[" .. idx .. "]", message = err or "invalid stream config" })
                    end
                end
            end
        end
    end

    check_stream_list(payload.make_stream, "make_stream")
    check_stream_list(payload.streams, "streams")

    return errors, warnings
end

-- Async export helper (separate chunk to avoid Lua's "too many locals" limit in this file).
pcall(dofile, "scripts/export_async.lua")

local function apply_config_change(server, client, request, opts)
    opts = opts or {}
    local defer_export = opts.defer_export == true
    if defer_export then
        -- Async export is supported only on the primary writer (shard 0 / single instance).
        -- Other shards must keep synchronous exports to avoid races and "missing snapshot" states.
        if not (config and config.is_primary_writer == true) then
            defer_export = false
        elseif not (stream_export_async and type(stream_export_async.request) == "function") then
            defer_export = false
        end
    end
    local t_start = os.clock()
    local timing = {
        backup_ms = nil,
        apply_ms = nil,
        export_ms = nil,
        snapshot_ms = nil,
        reload_ms = nil,
        lkg_ms = nil,
        after_ms = nil,
    }
    local actor = opts.actor
    if not actor then
        local user = get_request_user(request)
        actor = user and user.username or ""
    end

    if type(opts.validate) == "function" then
        local ok, err, details = opts.validate()
        if ok == false then
            return json_response(server, client, 400, {
                error = err or "validation failed",
                errors = details,
            })
        end
    end

    local revision_id = 0
    if config and config.create_revision then
        revision_id = config.create_revision({
            created_by = actor,
            comment = opts.comment or "",
            status = "PENDING",
        })
    end

    local lkg_path = nil
    if config and config.ensure_lkg_snapshot then
        local t0 = os.clock()
        local ok, err = config.ensure_lkg_snapshot()
        timing.backup_ms = (os.clock() - t0) * 1000
        if ok then
            lkg_path = ok
        else
            if revision_id > 0 then
                config.update_revision(revision_id, {
                    status = "BAD",
                    error_text = "backup failed: " .. tostring(err),
                })
            end
            return error_response(server, client, 500, "backup failed: " .. tostring(err))
        end
    end

    local primary_exported = false
    local function rollback_primary_config()
        if not primary_exported then
            return
        end
        if config and config.restore_primary_config_from_snapshot and lkg_path then
            local ok, err = config.restore_primary_config_from_snapshot(lkg_path)
            if not ok then
                log.error("[api] primary config rollback failed: " .. tostring(err))
            end
        end
    end

    local apply_result = nil
    if type(opts.apply) == "function" then
        local t0 = os.clock()
        local ok, res, res_err = pcall(function()
            if opts.transaction == false
                or not config
                or type(config.with_transaction) ~= "function"
            then
                return opts.apply()
            end
            return config.with_transaction(opts.apply)
        end)
        timing.apply_ms = (os.clock() - t0) * 1000
        if not ok then
            if revision_id > 0 then
                config.update_revision(revision_id, { status = "BAD", error_text = tostring(res) })
            end
            return error_response(server, client, 500, "apply failed: " .. tostring(res))
        end
        if res == nil and res_err ~= nil then
            if revision_id > 0 then
                config.update_revision(revision_id, { status = "BAD", error_text = tostring(res_err) })
            end
            return error_response(server, client, 500, "apply failed: " .. tostring(res_err))
        end
        if res == false then
            if revision_id > 0 then
                config.update_revision(revision_id, { status = "BAD", error_text = tostring(opts.apply_error or "apply failed") })
            end
            return error_response(server, client, 500, tostring(opts.apply_error or "apply failed"))
        end
        apply_result = res
    end

    local export_payload = nil
    local export_encoded = nil
    local function ensure_export_payload()
        if export_payload ~= nil then
            return export_payload, export_encoded
        end
        if not config then
            return nil, "config missing"
        end
        if type(config.export_astra_encoded) == "function" then
            local safe, payload, encoded = pcall(config.export_astra_encoded)
            if not safe then
                return nil, payload
            end
            export_payload = payload
            export_encoded = encoded
            return export_payload, export_encoded
        end
        if type(config.export_astra) ~= "function" then
            return nil, "config export unavailable"
        end
        local safe, payload = pcall(config.export_astra)
        if not safe then
            return nil, payload
        end
        local encoded
        if json and type(json.encode_pretty) == "function" then
            encoded = json.encode_pretty(payload)
        else
            encoded = json.encode(payload)
        end
        export_payload = payload
        export_encoded = encoded
        return export_payload, export_encoded
    end

    if not defer_export
        and config and config.primary_config_is_json and config.primary_config_is_json()
        and config.get_primary_config_path and config.get_primary_config_path()
        and config.export_astra_file
    then
        local t0 = os.clock()
        local payload, encoded_or_err = ensure_export_payload()
        if not payload then
            local err = encoded_or_err
            if revision_id > 0 then
                config.update_revision(revision_id, {
                    status = "BAD",
                    error_text = "config export failed: " .. tostring(err),
                })
            end
            if lkg_path then
                config.restore_snapshot(lkg_path)
                rollback_primary_config()
                reload_runtime(true)
            end
            return error_response(server, client, 500, "config export failed: " .. tostring(err))
        end
        local ok, err = config.export_astra_file(config.get_primary_config_path(), {
            payload = payload,
            encoded = encoded_or_err,
        })
        timing.export_ms = (os.clock() - t0) * 1000
        if not ok then
            if revision_id > 0 then
                config.update_revision(revision_id, {
                    status = "BAD",
                    error_text = "config export failed: " .. tostring(err),
                })
            end
            if lkg_path then
                config.restore_snapshot(lkg_path)
                rollback_primary_config()
                reload_runtime(true)
            end
            return error_response(server, client, 500, "config export failed: " .. tostring(err))
        end
        primary_exported = true
    end

    local snapshot_path = nil
    if revision_id > 0 and config and config.build_snapshot_path then
        snapshot_path = config.build_snapshot_path(revision_id)
    end
    if not defer_export and snapshot_path and config and config.export_astra_file then
        local t0 = os.clock()
        local payload, encoded_or_err = ensure_export_payload()
        if not payload then
            local snap_err = encoded_or_err
            config.update_revision(revision_id, {
                status = "BAD",
                error_text = "snapshot failed: " .. tostring(snap_err),
                snapshot_path = snapshot_path,
            })
            if lkg_path then
                config.restore_snapshot(lkg_path)
                rollback_primary_config()
                reload_runtime(true)
            end
            return error_response(server, client, 500, "snapshot failed: " .. tostring(snap_err))
        end
        local payload_ok, snap_err = config.export_astra_file(snapshot_path, {
            payload = payload,
            encoded = encoded_or_err,
        })
        timing.snapshot_ms = (os.clock() - t0) * 1000
        if not payload_ok then
            config.update_revision(revision_id, {
                status = "BAD",
                error_text = "snapshot failed: " .. tostring(snap_err),
                snapshot_path = snapshot_path,
            })
            if lkg_path then
                config.restore_snapshot(lkg_path)
                rollback_primary_config()
                reload_runtime(true)
            end
            return error_response(server, client, 500, "snapshot failed: " .. tostring(snap_err))
        end
    end

    local ok = true
    local reload_err = nil
    if type(opts.runtime_apply) == "function" then
        local t0 = os.clock()
        local apply_ok, apply_err
        local safe, res_ok, res_err = pcall(opts.runtime_apply)
        if not safe then
            apply_ok = false
            apply_err = res_ok
        else
            apply_ok = (res_ok ~= false)
            apply_err = res_err
        end
        ok = apply_ok
        reload_err = apply_err
        timing.reload_ms = (os.clock() - t0) * 1000
    else
        local t0 = os.clock()
        ok, reload_err = reload_runtime(true)
        timing.reload_ms = (os.clock() - t0) * 1000
    end
    if not ok then
        if revision_id > 0 then
            config.update_revision(revision_id, {
                status = "BAD",
                error_text = tostring(reload_err or "reload failed"),
                snapshot_path = snapshot_path,
            })
        end
        if config and config.add_alert then
            config.add_alert("CRITICAL", "", "CONFIG_RELOAD_FAILED",
                tostring(reload_err or "reload failed"),
                { revision_id = revision_id })
        end
        if lkg_path then
            config.restore_snapshot(lkg_path)
            rollback_primary_config()
            reload_runtime(true)
        end
        return json_response(server, client, 409, {
            error = "Config rejected, rolled back",
            detail = reload_err,
            revision_id = revision_id,
        })
    end

    if revision_id > 0 then
        config.update_revision(revision_id, {
            status = "ACTIVE",
            applied_ts = os.time(),
            snapshot_path = snapshot_path,
        })
        config.set_setting("config_active_revision_id", revision_id)
        config.set_setting("config_lkg_revision_id", revision_id)
        if not defer_export and config and config.export_astra_file then
            local t0 = os.clock()
            local lkg_target = lkg_path
            if not lkg_target and config.lkg_snapshot_path then
                lkg_target = config.lkg_snapshot_path()
            end
            if lkg_target and lkg_target ~= "" then
                local payload = export_payload
                if not payload then
                    payload = config.export_astra()
                end
                if type(payload) == "table" then
                    if payload.settings == nil then
                        payload.settings = {}
                    end
                    if type(payload.settings) == "table" then
                        payload.settings.config_active_revision_id = revision_id
                        payload.settings.config_lkg_revision_id = revision_id
                    end
                    local safe, _, lkg_encoded = pcall(config.export_astra_encoded, { payload = payload })
                    if safe and lkg_encoded then
                        local ok_lkg, err_lkg = config.export_astra_file(lkg_target, {
                            payload = payload,
                            encoded = lkg_encoded,
                        })
                        if not ok_lkg then
                            log.error("[api] lkg snapshot update failed: " .. tostring(err_lkg))
                        end
                    else
                        log.error("[api] lkg snapshot encode failed")
                    end
                end
            end
            timing.lkg_ms = (os.clock() - t0) * 1000
        end
        local max_keep = config.get_setting("config_max_revisions")
        config.prune_revisions(max_keep)
        if config.mark_boot_ok then
            config.mark_boot_ok(revision_id)
        end
    end
    if defer_export then
        local primary_path = nil
        if config and config.primary_config_is_json and config.primary_config_is_json()
            and config.get_primary_config_path
        then
            primary_path = config.get_primary_config_path()
        end
        local lkg_target = lkg_path
        if not lkg_target and config and config.lkg_snapshot_path then
            lkg_target = config.lkg_snapshot_path()
        end
        local export_paths = {
            primary_path = primary_path,
            lkg_path = lkg_target,
            snapshot_path = snapshot_path,
        }
        local async_ok = false
        local async_err = nil
        if stream_export_async and type(stream_export_async.request) == "function" then
            local safe, res = pcall(stream_export_async.request, export_paths)
            async_ok = safe and (res ~= false and res ~= nil)
            if not async_ok then
                async_err = safe and "request returned nil/false" or tostring(res)
            end
        else
            async_err = "async exporter unavailable"
        end
        if not async_ok then
            local payload, encoded_or_err = ensure_export_payload()
            if payload then
                local function write_target(path, label)
                    if not path or path == "" then
                        return true
                    end
                    local ok_export, err_export = config.export_astra_file(path, {
                        payload = payload,
                        encoded = encoded_or_err,
                    })
                    if not ok_export then
                        return nil, tostring(label) .. " export failed: " .. tostring(err_export)
                    end
                    return true
                end
                local ok_export, export_err = write_target(export_paths.primary_path, "primary")
                if ok_export then
                    ok_export, export_err = write_target(export_paths.snapshot_path, "snapshot")
                end
                if ok_export then
                    ok_export, export_err = write_target(export_paths.lkg_path, "lkg")
                end
                if not ok_export then
                    log.error("[api] deferred export fallback failed: " .. tostring(export_err))
                    if config and config.add_alert then
                        config.add_alert("WARNING", "", "CONFIG_EXPORT_FALLBACK_FAILED", tostring(export_err), {
                            revision_id = revision_id,
                            async_error = tostring(async_err or ""),
                        })
                    end
                else
                    log.warning("[api] deferred export fallback used: " .. tostring(async_err or "unknown async error"))
                end
            else
                local text = "config export failed: " .. tostring(encoded_or_err)
                log.error("[api] deferred export fallback failed: " .. text)
                if config and config.add_alert then
                    config.add_alert("WARNING", "", "CONFIG_EXPORT_FALLBACK_FAILED", text, {
                        revision_id = revision_id,
                        async_error = tostring(async_err or ""),
                    })
                end
            end
        end
    end
    if config and config.add_alert then
        config.add_alert("INFO", "", "CONFIG_RELOAD_OK", "config applied", {
            revision_id = revision_id,
        })
    end

    -- In sharded setups other processes must reload runtime to pick up DB changes.
    -- This is best-effort and should not block config apply.
    if opts.broadcast_reload ~= false
        and sharding and type(sharding.broadcast_reload) == "function"
    then
        pcall(sharding.broadcast_reload, opts.broadcast_force)
    end

    local body = nil
    if type(opts.success_builder) == "function" then
        body = opts.success_builder(apply_result, revision_id)
    else
        body = { status = "ok", revision_id = revision_id }
    end
    if type(opts.after) == "function" then
        local t0 = os.clock()
        local ok, err = pcall(opts.after, apply_result, revision_id, { export_payload = export_payload })
        timing.after_ms = (os.clock() - t0) * 1000
        if not ok then
            log.error("[api] after hook failed: " .. tostring(err))
        end
    end
    local total_ms = (os.clock() - t_start) * 1000
    local slow_threshold_ms = tonumber(opts.slow_threshold_ms) or 1500
    if total_ms > slow_threshold_ms then
        local req_id = request and request.request_id or ""
        log.warning(string.format("[api] req=%s slow config apply: %.0fms backup=%.0fms apply=%.0fms export=%.0fms snapshot=%.0fms reload=%.0fms lkg=%.0fms after=%.0fms",
            tostring(req_id),
            total_ms,
            timing.backup_ms or 0,
            timing.apply_ms or 0,
            timing.export_ms or 0,
            timing.snapshot_ms or 0,
            timing.reload_ms or 0,
            timing.lkg_ms or 0,
            timing.after_ms or 0))
    end
    json_response(server, client, 200, body)
end

function api._collect_stream_status_lite_map(ids)
    local map = {}
    if type(ids) ~= "table" or #ids == 0 then
        return map
    end
    if runtime and type(runtime.list_status_lite_ids) == "function" then
        local ok_runtime, runtime_map = pcall(runtime.list_status_lite_ids, ids)
        if ok_runtime and type(runtime_map) == "table" then
            map = runtime_map
        end
    elseif runtime and type(runtime.list_status_lite) == "function" then
        local ok_runtime, runtime_map = pcall(runtime.list_status_lite)
        if ok_runtime and type(runtime_map) == "table" then
            for _, sid in ipairs(ids) do
                if type(runtime_map[sid]) == "table" then
                    map[sid] = runtime_map[sid]
                end
            end
        end
    end
    if dvr_store and type(dvr_store.list_runtime_status) == "function" then
        local ok_dvr, dvr_map = pcall(dvr_store.list_runtime_status, ids)
        if ok_dvr and type(dvr_map) == "table" then
            for sid, row in pairs(dvr_map) do
                if type(row) == "table" then
                    if type(map[sid]) ~= "table" then
                        map[sid] = row
                    else
                        local merged = map[sid]
                        if merged.on_air == nil then merged.on_air = row.on_air end
                        if merged.bitrate_kbps == nil then merged.bitrate_kbps = row.bitrate_kbps or row.bitrate end
                        if merged.raw_bitrate_kbps == nil then
                            merged.raw_bitrate_kbps = row.raw_bitrate_kbps or row.bitrate_kbps or row.bitrate
                        end
                        if merged.cc_errors == nil then merged.cc_errors = row.cc_errors end
                        if merged.pes_errors == nil then merged.pes_errors = row.pes_errors end
                        if merged.active_input_id == nil then merged.active_input_id = row.active_input_id end
                        if merged.active_input_index == nil then merged.active_input_index = row.active_input_index end
                        if merged.active_input_url == nil then merged.active_input_url = row.active_input_url end
                        if merged.uptime_sec == nil then merged.uptime_sec = row.uptime_sec end
                        if merged.updated_at == nil then merged.updated_at = row.updated_at end
                        if (merged.last_error == nil or tostring(merged.last_error or "") == "")
                            and tostring(row.last_error or "") ~= ""
                        then
                            merged.last_error = row.last_error
                        end
                    end
                end
            end
        end
    end
    return map
end

function api._apply_stream_runtime_status(item, status)
    if type(item) ~= "table" then
        return
    end
    if type(status) == "table" then
        item.on_air = status.on_air == true
        item.bitrate_kbps = tonumber(status.bitrate_kbps or status.bitrate) or 0
        item.raw_bitrate_kbps = tonumber(status.raw_bitrate_kbps or status.bitrate_kbps or status.bitrate) or 0
        item.cc_errors = tonumber(status.cc_errors) or 0
        item.pes_errors = tonumber(status.pes_errors) or 0
        item.uptime_sec = tonumber(status.uptime_sec or status.uptime) or 0
        if status.active_input_id ~= nil then
            item.active_input = tonumber(status.active_input_id) or status.active_input_id
        elseif status.active_input ~= nil then
            item.active_input = tonumber(status.active_input) or status.active_input
        end
        if status.active_input_url ~= nil then
            item.active_input_url = tostring(status.active_input_url or "")
        end
        item.last_error = status.last_error and tostring(status.last_error) or nil
        item.updated_at = tonumber(status.updated_at) or os.time()
    end
    if item.on_air == nil then item.on_air = false end
    if item.bitrate_kbps == nil then item.bitrate_kbps = 0 end
    if item.raw_bitrate_kbps == nil then item.raw_bitrate_kbps = 0 end
    if item.cc_errors == nil then item.cc_errors = 0 end
    if item.pes_errors == nil then item.pes_errors = 0 end
    if item.uptime_sec == nil then item.uptime_sec = 0 end
    if item.active_input_url == nil then item.active_input_url = "" end
    if item.updated_at == nil then item.updated_at = os.time() end
end

local function list_streams(server, client)
    local rows = config.list_streams()
    local result = {}
    local seen_ids = {}
    local dvr_rows_by_id = {}
    if dvr_store and type(dvr_store.list_streams) == "function" then
        local dvr_rows = dvr_store.list_streams({ limit = 10000 }) or {}
        for _, dvr_row in ipairs(dvr_rows) do
            local sid = tostring(dvr_row and dvr_row.stream_id or "")
            if sid ~= "" then
                dvr_rows_by_id[sid] = dvr_row
            end
        end
    end
    local shard_active = sharding
        and type(sharding.is_active) == "function"
        and sharding.is_active()
    local shard_get_port = shard_active
        and type(sharding.get_stream_shard_port) == "function"
        and sharding.get_stream_shard_port
        or nil
    local shard_get_index = shard_active
        and type(sharding.get_stream_shard_index) == "function"
        and sharding.get_stream_shard_index
        or nil
    for _, row in ipairs(rows) do
        local item = {
            id = row.id,
            enabled = (tonumber(row.enabled) or 0) ~= 0,
            config = row.config,
        }
        local dvr_row = dvr_rows_by_id[tostring(row.id)]
        if type(dvr_row) == "table" then
            item.dvr = {
                record_enabled = dvr_row.record_enabled == true,
                recording_paused = dvr_row.recording_paused == true,
                retention_days = tonumber(dvr_row.retention_days) or 0,
                last_mode = tostring(dvr_row.last_mode or "LIVE"),
                last_state_seq = tonumber(dvr_row.last_state_seq) or 0,
                updated_ts = tonumber(dvr_row.updated_ts) or 0,
            }
        end
        if shard_get_port then
            local port = shard_get_port(row.id)
            if port then
                item.shard_port = port
            end
        end
        if shard_get_index then
            local idx = shard_get_index(row.id)
            if idx ~= nil then
                item.shard_index = idx
            end
        end
        seen_ids[tostring(row.id)] = true
        table.insert(result, item)
    end

    local dvr_only_ids = {}
    for sid, _ in pairs(dvr_rows_by_id) do
        if not seen_ids[sid] then
            dvr_only_ids[#dvr_only_ids + 1] = sid
        end
    end
    table.sort(dvr_only_ids)
    for _, sid in ipairs(dvr_only_ids) do
        local dvr_row = dvr_rows_by_id[sid]
        local source_url = tostring(dvr_row and dvr_row.source_url or "")
        local name = tostring(dvr_row and dvr_row.name or sid)
        local archive_path = dvr_row and dvr_row.archive_path or nil
        if archive_path ~= nil then
            archive_path = tostring(archive_path)
            if archive_path == "" then
                archive_path = nil
            end
        end
        local dvr_meta = {
            record_enabled = dvr_row and dvr_row.record_enabled == true or false,
            recording_paused = dvr_row and dvr_row.recording_paused == true or false,
            retention_days = tonumber(dvr_row and dvr_row.retention_days) or 0,
            last_mode = tostring((dvr_row and dvr_row.last_mode) or "LIVE"),
            last_state_seq = tonumber(dvr_row and dvr_row.last_state_seq) or 0,
            updated_ts = tonumber(dvr_row and dvr_row.updated_ts) or 0,
        }
        local cfg = type(dvr_row and dvr_row.config) == "table" and deep_copy(dvr_row.config) or {
            id = sid,
            name = name,
            type = "spts",
            input = source_url ~= "" and { source_url } or {},
            dvr = {},
        }
        cfg.id = sid
        if tostring(cfg.name or "") == "" then
            cfg.name = name
        end
        if tostring(cfg.type or "") == "" then
            cfg.type = "spts"
        end
        if source_url ~= "" then
            if type(cfg.input) ~= "table" then
                cfg.input = {}
            end
            cfg.input[1] = source_url
        elseif type(cfg.input) ~= "table" then
            cfg.input = {}
        end
        local cfg_dvr_existing = type(cfg.dvr) == "table" and cfg.dvr or {}
        cfg_dvr_existing.enabled = dvr_meta.record_enabled == true
        cfg_dvr_existing.retention_days = dvr_meta.retention_days
        cfg_dvr_existing.source_url = source_url
        if archive_path then
            cfg_dvr_existing.path = archive_path
            cfg_dvr_existing.archive_path = archive_path
        end
        cfg.dvr = cfg_dvr_existing
        table.insert(result, {
            id = sid,
            enabled = dvr_meta.record_enabled == true,
            dvr_only = true,
            dvr = dvr_meta,
            config = cfg,
        })
    end
    local ids = {}
    for _, item in ipairs(result) do
        local sid = tostring(item and item.id or "")
        if sid ~= "" then
            ids[#ids + 1] = sid
        end
    end
    local status_map = api._collect_stream_status_lite_map(ids)
    for _, item in ipairs(result) do
        local sid = tostring(item and item.id or "")
        api._apply_stream_runtime_status(item, status_map[sid])
    end
    json_response(server, client, 200, result)
end

local function get_stream(server, client, id)
    local row = config.get_stream(id)
    local dvr_row = nil
    if dvr_store and type(dvr_store.get_stream) == "function" then
        dvr_row = dvr_store.get_stream(id)
    end
    if not row and type(dvr_row) ~= "table" then
        return error_response(server, client, 404, "stream not found")
    end

    local payload = nil
    if row then
        payload = {
            id = row.id,
            enabled = (tonumber(row.enabled) or 0) ~= 0,
            config = row.config,
        }
    else
        local source_url = tostring(dvr_row and dvr_row.source_url or "")
        local name = tostring(dvr_row and dvr_row.name or id)
        local archive_path = dvr_row and dvr_row.archive_path or nil
        if archive_path ~= nil then
            archive_path = tostring(archive_path)
            if archive_path == "" then
                archive_path = nil
            end
        end
        local cfg = type(dvr_row and dvr_row.config) == "table" and deep_copy(dvr_row.config) or {
            id = id,
            name = name,
            type = "spts",
            input = source_url ~= "" and { source_url } or {},
            dvr = {},
        }
        cfg.id = id
        if tostring(cfg.name or "") == "" then
            cfg.name = name
        end
        if tostring(cfg.type or "") == "" then
            cfg.type = "spts"
        end
        if source_url ~= "" then
            if type(cfg.input) ~= "table" then
                cfg.input = {}
            end
            cfg.input[1] = source_url
        elseif type(cfg.input) ~= "table" then
            cfg.input = {}
        end
        local cfg_dvr_existing = type(cfg.dvr) == "table" and cfg.dvr or {}
        cfg_dvr_existing.enabled = dvr_row and dvr_row.record_enabled == true or false
        cfg_dvr_existing.retention_days = tonumber(dvr_row and dvr_row.retention_days) or 0
        cfg_dvr_existing.source_url = source_url
        if archive_path then
            cfg_dvr_existing.path = archive_path
            cfg_dvr_existing.archive_path = archive_path
        end
        cfg.dvr = cfg_dvr_existing
        payload = {
            id = id,
            enabled = dvr_row and dvr_row.record_enabled == true or false,
            dvr_only = true,
            config = cfg,
        }
    end

    if type(dvr_row) == "table" then
        payload.dvr = {
            record_enabled = dvr_row.record_enabled == true,
            recording_paused = dvr_row.recording_paused == true,
            retention_days = tonumber(dvr_row.retention_days) or 0,
            last_mode = tostring(dvr_row.last_mode or "LIVE"),
            last_state_seq = tonumber(dvr_row.last_state_seq) or 0,
            updated_ts = tonumber(dvr_row.updated_ts) or 0,
        }
    end
    local shard_active = sharding
        and type(sharding.is_active) == "function"
        and sharding.is_active()
    if row and shard_active and type(sharding.get_stream_shard_port) == "function" then
        local port = sharding.get_stream_shard_port(id)
        if port then
            payload.shard_port = port
        end
    end
    if row and shard_active and type(sharding.get_stream_shard_index) == "function" then
        local idx = sharding.get_stream_shard_index(id)
        if idx ~= nil then
            payload.shard_index = idx
        end
    end
    local status_map = api._collect_stream_status_lite_map({ tostring(id) })
    api._apply_stream_runtime_status(payload, status_map[tostring(id)])
    json_response(server, client, 200, payload)
end

local function start_stream_preview(server, client, request, stream_id)
    if not preview or not preview.start then
        return error_response(server, client, 501, "preview unavailable")
    end
    local opts = {}
    local q = request and request.query or {}
    local vo = q.video_only or q.videoonly or q.vo or nil
    if vo ~= nil then
        local v = tostring(vo):lower()
        opts.video_only = (v == "1" or v == "true" or v == "yes" or v == "on")
    end
    local aa = q.audio_aac or q.audioaac or q.aac or nil
    if aa ~= nil then
        local v = tostring(aa):lower()
        opts.audio_aac = (v == "1" or v == "true" or v == "yes" or v == "on")
    end
    local audio = q.audio or q.a or nil
    if audio ~= nil then
        local v = tostring(audio):lower()
        if v == "aac" then
            opts.audio_aac = true
        end
    end
    local h264 = q.h264 or q.video_h264 or q.vh264 or nil
    if h264 ~= nil then
        local v = tostring(h264):lower()
        opts.video_h264 = (v == "1" or v == "true" or v == "yes" or v == "on")
    end
    if opts.video_only then
        -- video_only уже подразумевает "без аудио", поэтому игнорируем audio_aac.
        opts.audio_aac = false
    end
    local result, err, code = preview.start(stream_id, opts)
    if not result then
        return error_response(server, client, code or 500, err or "preview failed")
    end
    if result.mode == "hls" then
        return json_response(server, client, 200, {
            url = result.url,
            mode = "hls",
        })
    end
    return json_response(server, client, 200, {
        url = result.url,
        token = result.token,
        expires_in_sec = result.expires_in_sec,
        mode = "preview",
        reused = result.reused == true,
    })
end

local function stop_stream_preview(server, client, request, stream_id)
    if not preview or not preview.stop then
        return error_response(server, client, 501, "preview unavailable")
    end
    preview.stop(stream_id)
    return json_response(server, client, 200, { status = "ok" })
end

-- PNGTS/Radio API handlers are loaded from api_media.lua.

-- In multi-process sharding, a stream config can be updated from any API port (shared sqlite),
-- but runtime.apply_stream_row() can only be executed on the owning shard.
-- For master-only UI/API workflows we treat "wrong shard" errors as success and rely on
-- sharding.broadcast_reload() (triggered by apply_config_change) to refresh the owning shard.
local function apply_stream_row_sharded_safe(row, force)
    if not runtime or not runtime.apply_stream_row then
        return false, "runtime apply not available"
    end
    local ok, err = runtime.apply_stream_row(row, force)
    if ok == false
        and tostring(err or ""):find("does not belong to this shard", 1, true) ~= nil
        and sharding
        and type(sharding.is_active) == "function"
        and sharding.is_active()
    then
        return true
    end
    return ok, err
end

local function boolish(value)
    if value == true or value == 1 then
        return true
    end
    local text = tostring(value or ""):lower()
    return text == "1" or text == "true" or text == "yes" or text == "on"
end

local function build_local_dvr_play_url(stream_id)
    local http_port = tonumber(config and config.get_setting and config.get_setting("http_port") or nil) or 8000
    local play_port = tonumber(config and config.get_setting and config.get_setting("http_play_port") or nil) or http_port
    if not play_port or play_port < 1 or play_port > 65535 then
        play_port = http_port
    end
    return "http://127.0.0.1:" .. tostring(play_port) .. "/dvr/internal/play/" .. tostring(stream_id) .. "?internal=1"
end

local function ensure_stream_dvr_backup_input(cfg, stream_id)
    if type(cfg) ~= "table" then
        return
    end
    local dvr_cfg = type(cfg.dvr) == "table" and cfg.dvr or nil
    if type(dvr_cfg) ~= "table" or not boolish(dvr_cfg.backup_enabled) then
        return
    end
    if type(cfg.input) ~= "table" then
        cfg.input = {}
    end
    local backup_input_url = build_local_dvr_play_url(stream_id)
    local backup_input_url_no_flag = backup_input_url:gsub("%?internal=1$", "")
    local legacy_internal_url = backup_input_url:gsub("/dvr/internal/play/", "/dvr/play/")
    local legacy_backup_input_url = legacy_internal_url:gsub("%?internal=1$", "")
    local exists = false
    for idx = #cfg.input, 1, -1 do
        local raw = tostring(cfg.input[idx] or "")
        if raw == backup_input_url then
            if exists then
                table.remove(cfg.input, idx)
            else
                exists = true
            end
        elseif raw == backup_input_url_no_flag or raw == legacy_internal_url or raw == legacy_backup_input_url then
            table.remove(cfg.input, idx)
        end
    end
    if not exists then
        table.insert(cfg.input, backup_input_url)
    end
    -- DVR backup input must be failover-only; active backup mode keeps
    -- /dvr/play running even while primary input is healthy.
    if tostring(cfg.backup_type or ""):lower() ~= "passive" then
        cfg.backup_type = "passive"
    end
end

function api._dvr_parse_input_binding(cfg, stream_id)
    if type(cfg) ~= "table" or type(cfg.input) ~= "table" then
        return nil
    end
    for _, raw in ipairs(cfg.input) do
        if type(raw) == "string" and raw ~= "" then
            local parsed = parse_url(raw)
            if type(parsed) == "table" then
                local input_type = tostring(parsed.input_type or ""):lower()
                local server_id = api._dvr_trim_text(parsed.dvr_server_id or parsed.server_id)
                if input_type == "dvr" and server_id ~= "" then
                    local path = tostring(parsed.path or "")
                    local remote_stream_id = api._dvr_trim_text(parsed.dvr_stream_id)
                    if remote_stream_id == "" then
                        remote_stream_id = api._dvr_trim_text(path:match("^/dvr/internal/play/([^/?#]+)"))
                        if remote_stream_id == "" then
                            remote_stream_id = api._dvr_trim_text(path:match("^/dvr/archive/play/([^/?#]+)"))
                        end
                    end
                    if remote_stream_id == "" then
                        remote_stream_id = api._dvr_trim_text(path:match("^/dvr/play/([^/?#]+)"))
                        if remote_stream_id == "" then
                            remote_stream_id = api._dvr_trim_text(path:match("^/play/([^/?#]+)"))
                        end
                    end
                    if remote_stream_id == "" then
                        remote_stream_id = api._dvr_trim_text(stream_id)
                    end
                    return {
                        server_id = server_id,
                        remote_stream_id = remote_stream_id,
                    }
                end
            end
        end
    end
    return nil
end

function api._dvr_apply_binding_from_inputs(cfg, stream_id)
    local binding = api._dvr_parse_input_binding(cfg, stream_id)
    if type(binding) ~= "table" then
        return
    end
    local entry = api._dvr_find_server_entry(binding.server_id)
    if type(entry) ~= "table" then
        return
    end
    local stype = tostring(entry.api_type or entry.type or ""):lower()
    if stype ~= "dvr_v1" and stype ~= "dvr-v1" and stype ~= "dvr" then
        return
    end
    local dvr_cfg = type(cfg.dvr) == "table" and cfg.dvr or {}
    local mode = api._dvr_trim_text(dvr_cfg.mode):lower()
    local server_id = api._dvr_trim_text(dvr_cfg.remote_server_id)
    if mode ~= "remote" or server_id == "" then
        dvr_cfg.mode = "remote"
        dvr_cfg.remote_server_id = binding.server_id
    end
    if api._dvr_trim_text(dvr_cfg.remote_stream_id) == "" then
        dvr_cfg.remote_stream_id = binding.remote_stream_id
    end
    if dvr_cfg.remote_channel_enabled == nil then
        dvr_cfg.remote_channel_enabled = true
    end
    cfg.dvr = dvr_cfg
end

local function ensure_stream_sharding_map_assignments(stream_ids)
    if type(stream_ids) ~= "table" then
        return
    end
    if not (config and config.get_setting and config.set_setting) then
        return
    end
    if not json or type(json.decode) ~= "function" or type(json.encode) ~= "function" then
        return
    end
    local init = config.get_setting("stream_sharding_map_initialized")
    if not (init == true or init == 1 or init == "1" or init == "true") then
        return
    end

    local map_raw = config.get_setting("stream_sharding_map")
    local map = {}
    if map_raw and map_raw ~= "" then
        local ok, decoded = pcall(json.decode, map_raw)
        if ok and type(decoded) == "table" then
            map = decoded
        end
    end

    local map_shards = tonumber(config.get_setting("stream_sharding_map_shards") or 0) or 0
    local applied = tonumber(config.get_setting("stream_sharding_applied_shards") or 0) or 0
    local desired = tonumber(config.get_setting("stream_sharding_shards") or 0) or 0
    local shard_count = math.floor(math.max(map_shards, applied, desired))
    if shard_count < 2 then
        return
    end

    local counts = {}
    for i = 0, shard_count - 1 do
        counts[i] = 0
    end
    for _, v in pairs(map) do
        local idx = tonumber(v)
        if idx and idx >= 0 and idx < shard_count then
            idx = math.floor(idx)
            counts[idx] = (counts[idx] or 0) + 1
        end
    end

    local function pick_least_loaded()
        local best = 0
        local best_count = counts[0] or 0
        for i = 1, shard_count - 1 do
            local c = counts[i] or 0
            if c < best_count then
                best = i
                best_count = c
            end
        end
        return best
    end

    local changed = false
    for _, id in ipairs(stream_ids) do
        local sid = tostring(id or "")
        if sid ~= "" then
            local cur = tonumber(map[sid])
            if not cur or cur < 0 or cur >= shard_count then
                local best = pick_least_loaded()
                map[sid] = best
                counts[best] = (counts[best] or 0) + 1
                changed = true
            end
        end
    end

    if not changed then
        return
    end
    local ok, encoded = pcall(json.encode, map)
    if ok and encoded then
        config.set_setting("stream_sharding_map", encoded)
    end
end

local function upsert_stream(server, client, id, request)
    local body = parse_json_body(request)
    if not body then
        return error_response(server, client, 400, "invalid json")
    end

    local function config_is_empty(tbl)
        if type(tbl) ~= "table" then
            return true
        end
        return next(tbl) == nil
    end

    local function is_enabled_only_patch(payload)
        if type(payload) ~= "table" then
            return false
        end
        for k, _ in pairs(payload) do
            if k ~= "enabled" and k ~= "id" and k ~= "config" then
                return false
            end
        end
        return true
    end

    local existing = nil
    if config and config.get_stream then
        existing = config.get_stream(id)
    end

    -- For updates, treat missing `enabled` as "keep current" (avoids accidental re-enable).
    -- For new streams, keep the historical default: enabled unless explicitly `false`.
    local enabled = nil
    if body.enabled == nil and existing then
        enabled = (tonumber(existing.enabled) or 0) ~= 0
    else
        enabled = (body.enabled ~= false)
    end

    local cfg = nil
    if not config_is_empty(body.config) then
        cfg = body.config
    elseif existing and is_enabled_only_patch(body) then
        -- Allow enabled-only patches without requiring clients to re-send the full stream config.
        cfg = existing.config or {}
    else
        -- Legacy behavior: accept stream config fields on the top-level object.
        cfg = body
        cfg.enabled = nil
        cfg.config = nil
    end
    cfg.id = id

    if not cfg.name then
        cfg.name = "Stream " .. id
    end
    if type(sanitize_stream_config) == "function" then
        sanitize_stream_config(cfg)
    end
    api._dvr_apply_binding_from_inputs(cfg, id)
    ensure_stream_dvr_backup_input(cfg, id)
    apply_config_change(server, client, request, {
        comment = "stream " .. id,
        -- Streams are user-facing and often edited live; keep on-disk JSON in sync
        -- immediately to avoid runtime/file drift after save.
        defer_export = false,
        validate = function()
            if enabled and type(validate_stream_config) == "function" then
                local ok, err = validate_stream_config(cfg)
                if not ok then
                    return false, err or "invalid stream config", {
                        { path = "stream", message = err or "invalid stream config" },
                    }
                end
            end
            return true
        end,
        apply = function()
            ensure_stream_sharding_map_assignments({ id })
            config.upsert_stream(id, enabled, cfg)
        end,
        runtime_apply = function()
            local row = config.get_stream(id)
            if not row then
                return false, "stream not found after update"
            end
            return apply_stream_row_sharded_safe(row, true)
        end,
        after = function()
            if epg then
                if epg.request_export then
                    epg.request_export("stream change")
                elseif epg.export_all then
                    epg.export_all("stream change")
                end
            end
            api._dvr_sync_remote_stream_after_upsert(id, cfg, request, function(sync_ok, _payload, sync_err)
                if sync_ok then
                    return
                end
                local message = tostring(sync_err or "remote dvr sync failed")
                log.warning("[dvr] remote stream sync failed for " .. tostring(id) .. ": " .. message)
                if config and type(config.add_alert) == "function" then
                    config.add_alert("WARNING", tostring(id), "DVR_REMOTE_SYNC_FAILED", message, {
                        stream_id = tostring(id),
                        stage = "stream_upsert_after",
                    })
                end
            end)
        end,
    })
end

local function delete_stream(server, client, id, request)
    apply_config_change(server, client, request, {
        comment = "stream " .. id .. " delete",
        defer_export = false,
        apply = function()
            config.delete_stream(id)
        end,
        runtime_apply = function()
            return apply_stream_row_sharded_safe({ id = id, enabled = 0, config = {} }, true)
        end,
        after = function()
            if epg then
                if epg.request_export then
                    epg.request_export("stream delete")
                elseif epg.export_all then
                    epg.export_all("stream delete")
                end
            end
        end,
    })
end

local function purge_disabled_streams(server, client, request)
    local admin = require_admin(request)
    if not admin then
        return error_response(server, client, 403, "forbidden")
    end

    local rows = config.list_streams()
    local ids = {}
    for _, row in ipairs(rows) do
        if (tonumber(row.enabled) or 0) == 0 then
            table.insert(ids, row.id)
        end
    end
    if #ids == 0 then
        return json_response(server, client, 200, { status = "ok", deleted = 0 })
    end
    table.sort(ids)

    apply_config_change(server, client, request, {
        actor = admin.username,
        comment = "purge disabled streams",
        defer_export = false,
        apply = function()
            for _, id in ipairs(ids) do
                config.delete_stream(id)
            end
            return { deleted = #ids }
        end,
        runtime_apply = function()
            for _, id in ipairs(ids) do
                local ok, err = apply_stream_row_sharded_safe({ id = id, enabled = 0, config = {} }, true)
                if ok == false then
                    return false, err or ("runtime delete failed: " .. id)
                end
            end
            return true
        end,
        after = function()
            if epg then
                if epg.request_export then
                    epg.request_export("stream purge disabled")
                elseif epg.export_all then
                    epg.export_all("stream purge disabled")
                end
            end
        end,
        success_builder = function(res, revision_id)
            return {
                status = "ok",
                deleted = res and (tonumber(res.deleted) or 0) or 0,
                revision_id = revision_id,
            }
        end,
    })
end

local function detect_nvidia_available()
    local ok, handle = pcall(io.popen, "nvidia-smi -L 2>/dev/null")
    if not ok or not handle then
        return false
    end
    local out = handle:read("*a") or ""
    handle:close()
    return out:match("GPU%s+%d+") ~= nil
end

local function transcode_supported()
    return astra and astra.features and astra.features.transcode == true
end

local function build_default_transcode_ladder(base_id, base_name)
    local engine = detect_nvidia_available() and "nvidia" or "cpu"
    local tc = {
        engine = engine,
        ffmpeg_global_args = { "-fflags", "+genpts" },
        profiles = {
            {
                id = "SD",
                name = "540p",
                width = 960,
                height = 540,
                fps = 25,
                bitrate_kbps = 1200,
                maxrate_kbps = 1500,
            },
        },
        publish = {
            {
                type = "hls",
                enabled = true,
                variants = { "SD" },
                storage = "memfd",
            },
        },
        watchdog = {
            restart_delay_sec = 1,
            restart_jitter_sec = 1,
            restart_backoff_base_sec = 1,
            restart_backoff_max_sec = 10,
            no_progress_timeout_sec = 30,
            max_error_lines_per_min = 200,
            probe_interval_sec = 0,
            max_restarts_per_10min = 10,
            restart_cooldown_sec = 0,
            error_rearm_sec = 120,
        },
    }
    if engine == "nvidia" then
        -- Auto-distribute across GPUs by picking the least busy device at runtime.
        tc.gpu_device = "auto"
    end
    return {
        id = base_id,
        name = (base_name and ("Transcode " .. tostring(base_name))) or ("Transcode " .. tostring(base_id)),
        type = "transcode",
        input = { "stream://" .. tostring(base_id) },
        transcode = tc,
    }
end

local function transcode_all_streams(server, client, request)
    local admin = require_admin(request)
    if not admin then
        return error_response(server, client, 403, "forbidden")
    end
    if not transcode_supported() then
        return error_response(server, client, 501, "transcode disabled in this build")
    end

    local body = parse_json_body(request) or {}
    local enable_requested = body and (body.enable == true or body.enable == 1 or body.enable == "1")
    -- Safety first: avoid CPU/RAM spikes. We only create streams disabled by default.
    if enable_requested then
        enable_requested = false
    end

    local rows = config.list_streams()
    local by_id = {}
    for _, row in ipairs(rows) do
        by_id[row.id] = row
    end

    local targets = {}
    local skipped = 0
    for _, row in ipairs(rows) do
        local enabled = (tonumber(row.enabled) or 0) ~= 0
        if enabled then
            local cfg = row.config or {}
            local stype = tostring(cfg.type or ""):lower()
            if stype ~= "transcode" and stype ~= "ffmpeg" then
                local base_id = row.id
                local tc_id = "tc_" .. tostring(base_id)
                if by_id[tc_id] then
                    skipped = skipped + 1
                else
                    table.insert(targets, { base_id = base_id, tc_id = tc_id, base_name = cfg.name })
                end
            end
        end
    end

    if #targets == 0 then
        return json_response(server, client, 200, { status = "ok", created = 0, skipped = skipped })
    end

    table.sort(targets, function(a, b) return tostring(a.tc_id) < tostring(b.tc_id) end)

    apply_config_change(server, client, request, {
        actor = admin.username,
        comment = "transcode all streams",
        defer_export = true,
        validate = function()
            for _, item in ipairs(targets) do
                local cfg = build_default_transcode_ladder(item.base_id, item.base_name)
                cfg.id = item.tc_id
                if type(validate_stream_config) == "function" then
                    local ok, err = validate_stream_config(cfg)
                    if not ok then
                        return false, err or ("invalid transcode config: " .. tostring(item.tc_id)), {
                            { path = "stream", message = err or "invalid transcode config" },
                        }
                    end
                end
            end
            return true
        end,
        apply = function()
            local new_ids = {}
            for _, item in ipairs(targets) do
                local cfg = build_default_transcode_ladder(item.base_id, item.base_name)
                cfg.id = item.tc_id
                config.upsert_stream(item.tc_id, false, cfg)
                new_ids[#new_ids + 1] = item.tc_id
            end
            ensure_stream_sharding_map_assignments(new_ids)
            return { created = #targets, skipped = skipped }
        end,
        runtime_apply = function()
            for _, item in ipairs(targets) do
                local row = config.get_stream(item.tc_id)
                if row then
                    local ok, err = apply_stream_row_sharded_safe(row, true)
                    if ok == false then
                        return false, err or ("runtime apply failed: " .. tostring(item.tc_id))
                    end
                end
            end
            return true
        end,
        success_builder = function(res, revision_id)
            return {
                status = "ok",
                created = res and (tonumber(res.created) or 0) or 0,
                skipped = res and (tonumber(res.skipped) or 0) or 0,
                revision_id = revision_id,
            }
        end,
    })
end

local function list_adapters(server, client)
    local rows = config.list_adapters()
    local result = {}
    for _, row in ipairs(rows) do
        table.insert(result, {
            id = row.id,
            enabled = (tonumber(row.enabled) or 0) ~= 0,
            config = row.config,
        })
    end
    json_response(server, client, 200, result)
end

local function get_adapter(server, client, id)
    local row = config.get_adapter(id)
    if not row then
        return error_response(server, client, 404, "adapter not found")
    end
    json_response(server, client, 200, {
        id = row.id,
        enabled = (tonumber(row.enabled) or 0) ~= 0,
        config = row.config,
    })
end

local function upsert_adapter(server, client, id, request)
    local body = parse_json_body(request)
    if not body then
        return error_response(server, client, 400, "invalid json")
    end

    local function config_is_empty(tbl)
        if type(tbl) ~= "table" then
            return true
        end
        return next(tbl) == nil
    end

    local function is_enabled_only_patch(payload)
        if type(payload) ~= "table" then
            return false
        end
        for k, _ in pairs(payload) do
            if k ~= "enabled" and k ~= "id" and k ~= "config" then
                return false
            end
        end
        return true
    end

    local existing = nil
    if config and config.get_adapter then
        existing = config.get_adapter(id)
    end

    -- For updates, treat missing `enabled` as "keep current" (avoids accidental re-enable).
    -- For new adapters, keep the historical default: enabled unless explicitly `false`.
    local enabled = nil
    if body.enabled == nil and existing then
        enabled = (tonumber(existing.enabled) or 0) ~= 0
    else
        enabled = (body.enabled ~= false)
    end

    local cfg = nil
    if not config_is_empty(body.config) then
        cfg = body.config
    elseif existing and is_enabled_only_patch(body) then
        -- Allow enabled-only patches without requiring clients to re-send the full adapter config.
        cfg = existing.config or {}
    else
        -- Legacy behavior: accept adapter config fields on the top-level object.
        cfg = body
        cfg.enabled = nil
        cfg.config = nil
    end
    cfg.id = id

    apply_config_change(server, client, request, {
        comment = "adapter " .. id,
        defer_export = true,
        apply = function()
            config.upsert_adapter(id, enabled, cfg)
        end,
    })
end

local function delete_adapter(server, client, id, request)
    apply_config_change(server, client, request, {
        comment = "adapter " .. id .. " delete",
        defer_export = true,
        apply = function()
            config.delete_adapter(id)
        end,
    })
end

local function generate_id(prefix)
    local stamp = os.time()
    local rand = math.random(1000, 9999)
    return tostring(prefix or "id") .. "_" .. tostring(stamp) .. "_" .. tostring(rand)
end

local function splitter_row_payload(row, links_count)
    return {
        id = row.id,
        name = row.name,
        enable = (tonumber(row.enable) or 0) ~= 0,
        port = tonumber(row.port) or 0,
        in_interface = row.in_interface,
        out_interface = row.out_interface,
        logtype = row.logtype,
        logpath = row.logpath,
        config_path = row.config_path,
        links_count = links_count or 0,
        created = row.created,
        updated = row.updated,
    }
end

local function list_splitters(server, client)
    local rows = config.list_splitters()
    local result = {}
    for _, row in ipairs(rows) do
        local links = config.list_splitter_links(row.id)
        table.insert(result, splitter_row_payload(row, #links))
    end
    json_response(server, client, 200, result)
end

local function get_splitter(server, client, id)
    local row = config.get_splitter(id)
    if not row then
        return error_response(server, client, 404, "splitter not found")
    end
    local links = config.list_splitter_links(id)
    json_response(server, client, 200, splitter_row_payload(row, #links))
end

local function upsert_splitter(server, client, id, request)
    local body = parse_json_body(request)
    if not body then
        return error_response(server, client, 400, "invalid json")
    end

    local port = tonumber(body.port)
    if not port or port < 1 or port > 65535 then
        return error_response(server, client, 400, "invalid port")
    end

    apply_config_change(server, client, request, {
        comment = "splitter " .. id,
        defer_export = true,
        apply = function()
            config.upsert_splitter(id, body)
        end,
        success_builder = function(_, revision_id)
            return { status = "ok", id = id, revision_id = revision_id }
        end,
    })
end

local function delete_splitter(server, client, id, request)
    apply_config_change(server, client, request, {
        comment = "splitter " .. id .. " delete",
        defer_export = true,
        apply = function()
            config.delete_splitter(id)
        end,
    })
end

local function list_splitter_links(server, client, splitter_id)
    if not config.get_splitter(splitter_id) then
        return error_response(server, client, 404, "splitter not found")
    end
    local rows = config.list_splitter_links(splitter_id)
    local result = {}
    for _, row in ipairs(rows) do
        table.insert(result, {
            id = row.id,
            splitter_id = row.splitter_id,
            enable = (tonumber(row.enable) or 0) ~= 0,
            url = row.url,
            bandwidth = row.bandwidth,
            buffering = row.buffering,
            created = row.created,
            updated = row.updated,
        })
    end
    json_response(server, client, 200, result)
end

local function upsert_splitter_link(server, client, splitter_id, link_id, request)
    if not config.get_splitter(splitter_id) then
        return error_response(server, client, 404, "splitter not found")
    end
    local body = parse_json_body(request)
    if not body then
        return error_response(server, client, 400, "invalid json")
    end
    local url = tostring(body.url or "")
    local parsed = parse_url(url)
    if not parsed or parsed.format ~= "http" then
        return error_response(server, client, 400, "hlssplitter supports http urls only")
    end
    apply_config_change(server, client, request, {
        comment = "splitter " .. splitter_id .. " link " .. link_id,
        defer_export = true,
        apply = function()
            config.upsert_splitter_link(splitter_id, link_id, body)
        end,
        success_builder = function(_, revision_id)
            return { status = "ok", id = link_id, revision_id = revision_id }
        end,
    })
end

local function delete_splitter_link(server, client, splitter_id, link_id, request)
    if not config.get_splitter(splitter_id) then
        return error_response(server, client, 404, "splitter not found")
    end
    apply_config_change(server, client, request, {
        comment = "splitter " .. splitter_id .. " link " .. link_id .. " delete",
        defer_export = true,
        apply = function()
            config.delete_splitter_link(splitter_id, link_id)
        end,
    })
end

local function list_splitter_allow(server, client, splitter_id)
    if not config.get_splitter(splitter_id) then
        return error_response(server, client, 404, "splitter not found")
    end
    local rows = config.list_splitter_allow(splitter_id)
    local result = {}
    for _, row in ipairs(rows) do
        table.insert(result, {
            id = row.id,
            splitter_id = row.splitter_id,
            kind = row.kind,
            value = row.value,
            created = row.created,
        })
    end
    json_response(server, client, 200, result)
end

local function parse_ipv4(value)
    if not value then
        return nil
    end
    local a, b, c, d = tostring(value):match("^%s*(%d+)%.(%d+)%.(%d+)%.(%d+)%s*$")
    if not a then
        return nil
    end
    a = tonumber(a)
    b = tonumber(b)
    c = tonumber(c)
    d = tonumber(d)
    if not a or not b or not c or not d then
        return nil
    end
    if a > 255 or b > 255 or c > 255 or d > 255 then
        return nil
    end
    return true
end

local function parse_cidr(value)
    local base, prefix = tostring(value or ""):match("^%s*(.-)%s*/%s*(%d+)%s*$")
    if not base then
        return false
    end
    local num = tonumber(prefix)
    if not num or num < 0 or num > 32 then
        return false
    end
    return parse_ipv4(base) ~= nil
end

local function parse_allow_range(value)
    local text = tostring(value or "")
    local from_ip, to_ip = text:match("^%s*([^%s,%-]+)%s*[,%-]%s*([^%s,%-]+)%s*$")
    if not from_ip then
        from_ip, to_ip = text:match("^%s*([^%s]+)%s*%.%.%s*([^%s]+)%s*$")
    end
    if not from_ip or not to_ip then
        return false
    end
    if not parse_ipv4(from_ip) or not parse_ipv4(to_ip) then
        return false
    end
    return true
end

local function add_splitter_allow(server, client, splitter_id, request)
    if not config.get_splitter(splitter_id) then
        return error_response(server, client, 404, "splitter not found")
    end
    local body = parse_json_body(request)
    if not body then
        return error_response(server, client, 400, "invalid json")
    end
    local kind = tostring(body.kind or "")
    if kind ~= "allow" and kind ~= "allowRange" then
        return error_response(server, client, 400, "invalid allow kind")
    end
    local value = tostring(body.value or "")
    if value == "" then
        return error_response(server, client, 400, "allow value required")
    end
    if kind == "allowRange" then
        if not parse_cidr(value) and not parse_allow_range(value) then
            return error_response(server, client, 400, "invalid allowRange value")
        end
    end
    local id = body.id or generate_id("allow")
    apply_config_change(server, client, request, {
        comment = "splitter " .. splitter_id .. " allow " .. id,
        defer_export = true,
        apply = function()
            config.add_splitter_allow(splitter_id, id, kind, value)
        end,
        success_builder = function(_, revision_id)
            return { status = "ok", id = id, revision_id = revision_id }
        end,
    })
end

local function delete_splitter_allow(server, client, splitter_id, rule_id, request)
    if not config.get_splitter(splitter_id) then
        return error_response(server, client, 404, "splitter not found")
    end
    apply_config_change(server, client, request, {
        comment = "splitter " .. splitter_id .. " allow " .. rule_id .. " delete",
        defer_export = true,
        apply = function()
            config.delete_splitter_allow(splitter_id, rule_id)
        end,
    })
end

local function start_splitter(server, client, id)
    local ok = splitter and splitter.start and splitter.start(id)
    if not ok then
        return error_response(server, client, 404, "splitter not found")
    end
    json_response(server, client, 200, { status = "ok" })
end

local function stop_splitter(server, client, id)
    local ok = splitter and splitter.stop and splitter.stop(id)
    if not ok then
        return error_response(server, client, 404, "splitter not found")
    end
    json_response(server, client, 200, { status = "ok" })
end

local function restart_splitter(server, client, id)
    local ok = splitter and splitter.restart and splitter.restart(id)
    if not ok then
        return error_response(server, client, 404, "splitter not found")
    end
    json_response(server, client, 200, { status = "ok" })
end

local function apply_splitter_config(server, client, id)
    local ok = splitter and splitter.apply_config and splitter.apply_config(id)
    if not ok then
        return error_response(server, client, 404, "splitter not found")
    end
    json_response(server, client, 200, { status = "ok" })
end

local function get_splitter_config(server, client, id)
    if not config.get_splitter(id) then
        return error_response(server, client, 404, "splitter not found")
    end
    if not splitter or not splitter.render_config then
        return error_response(server, client, 500, "splitter config unavailable")
    end
    local xml, err = splitter.render_config(id)
    if not xml then
        return error_response(server, client, 404, err or "splitter not found")
    end
    server:send(client, {
        code = 200,
        headers = {
            "Content-Type: application/xml; charset=utf-8",
            "Cache-Control: no-cache",
            "Connection: close",
        },
        content = xml,
    })
end

local status_list_cache = {
    splitter = { ts = 0, payload = nil },
    buffer = { ts = 0, payload = nil },
    adapter = { ts = 0, payload = nil },
}

local function status_cache_ttl_sec()
    local ttl = tonumber(setting_number("api_status_cache_ttl_sec", 1)) or 1
    if ttl < 0 then
        ttl = 0
    elseif ttl > 5 then
        ttl = 5
    end
    return ttl
end

local function status_cache_read(key)
    local cache = status_list_cache[key]
    if not cache then
        return nil
    end
    local ttl = status_cache_ttl_sec()
    if ttl <= 0 then
        return nil
    end
    local now = os.time()
    if cache.payload and (now - (tonumber(cache.ts) or 0)) <= ttl then
        return cache.payload
    end
    return nil
end

local function status_cache_write(key, payload)
    local cache = status_list_cache[key]
    if not cache then
        return
    end
    cache.ts = os.time()
    cache.payload = payload
end

local function list_splitter_status(server, client)
    local cached = status_cache_read("splitter")
    if cached then
        return json_response(server, client, 200, cached)
    end
    local status = splitter and splitter.list_status and splitter.list_status() or {}
    status_cache_write("splitter", status)
    json_response(server, client, 200, status)
end

local function get_splitter_status(server, client, id)
    local status = splitter and splitter.get_status and splitter.get_status(id)
    if not status then
        return error_response(server, client, 404, "splitter not found")
    end
    json_response(server, client, 200, status)
end

local function normalize_buffer_path(value)
    local path = tostring(value or "")
    if path == "" then
        return ""
    end
    if path:sub(1, 1) ~= "/" then
        path = "/" .. path
    end
    return path
end

local function buffer_output_url(path)
    local host = setting_string("buffer_listen_host", "0.0.0.0")
    local port = setting_number("buffer_listen_port", 8089)
    local display_host = host
    if display_host == "" or display_host == "0.0.0.0" then
        display_host = "<server_ip>"
    end
    local normalized = normalize_buffer_path(path or "")
    return "http://" .. display_host .. ":" .. tostring(port) .. normalized
end

local function buffer_resource_payload(row)
    return {
        id = row.id,
        name = row.name,
        path = row.path,
        enable = (tonumber(row.enable) or 0) ~= 0,
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
        created = row.created,
        updated = row.updated,
    }
end

local function buffer_input_payload(row)
    return {
        id = row.id,
        resource_id = row.resource_id,
        enable = (tonumber(row.enable) or 0) ~= 0,
        url = row.url,
        priority = row.priority,
        created = row.created,
        updated = row.updated,
    }
end

local function buffer_allow_payload(row)
    return {
        id = row.id,
        kind = row.kind,
        value = row.value,
        created = row.created,
    }
end

local function list_buffer_resources(server, client)
    local rows = config.list_buffer_resources()
    local result = {}
    for _, row in ipairs(rows) do
        table.insert(result, buffer_resource_payload(row))
    end
    json_response(server, client, 200, result)
end

local function get_buffer_resource(server, client, id)
    local row = config.get_buffer_resource(id)
    if not row then
        return error_response(server, client, 404, "buffer resource not found")
    end
    json_response(server, client, 200, buffer_resource_payload(row))
end

local function upsert_buffer_resource(server, client, id, body, request)
    if not body then
        return error_response(server, client, 400, "invalid json")
    end
    local body_id = tostring(body.id or "")
    if body_id == "" then
        return error_response(server, client, 400, "buffer id required")
    end
    if body_id ~= id then
        return error_response(server, client, 400, "buffer id mismatch")
    end
    log.debug("[buffers] save resource id=" .. id .. " payload=" .. json.encode(body))
    local path = normalize_buffer_path(body.path or "")
    if path == "" then
        return error_response(server, client, 400, "path required")
    end
    local by_path = config.get_buffer_resource_by_path(path)
    if by_path and by_path.id ~= id then
        return error_response(server, client, 400, "path already in use")
    end
    body.path = path
    apply_config_change(server, client, request, {
        comment = "buffer resource " .. id,
        defer_export = true,
        validate = function()
            if path == "" then
                return false, "path required", { { path = "path", message = "path required" } }
            end
            return true
        end,
        apply = function()
            config.upsert_buffer_resource(id, body)
        end,
        success_builder = function(_, revision_id)
            local row = config.get_buffer_resource(id)
            if not row then
                return { status = "ok", revision_id = revision_id }
            end
            local payload = buffer_resource_payload(row)
            payload.revision_id = revision_id
            return payload
        end,
    })
end

local function delete_buffer_resource(server, client, id, request)
    apply_config_change(server, client, request, {
        comment = "buffer resource " .. id .. " delete",
        defer_export = true,
        apply = function()
            config.delete_buffer_resource(id)
        end,
    })
end

local function list_buffer_inputs(server, client, resource_id)
    if not config.get_buffer_resource(resource_id) then
        return error_response(server, client, 404, "buffer resource not found")
    end
    local rows = config.list_buffer_inputs(resource_id)
    local result = {}
    for _, row in ipairs(rows) do
        table.insert(result, buffer_input_payload(row))
    end
    json_response(server, client, 200, result)
end

local function upsert_buffer_input(server, client, resource_id, input_id, body, request)
    if not config.get_buffer_resource(resource_id) then
        return error_response(server, client, 404, "buffer resource not found")
    end
    if not body then
        return error_response(server, client, 400, "invalid json")
    end
    log.debug("[buffers] save input resource=" .. resource_id .. " id=" .. input_id ..
        " payload=" .. json.encode(body))
    local url = tostring(body.url or "")
    local parsed = parse_url(url)
    if not parsed or parsed.format ~= "http" then
        return error_response(server, client, 400, "buffer supports http urls only")
    end
    apply_config_change(server, client, request, {
        comment = "buffer input " .. resource_id .. "/" .. input_id,
        defer_export = true,
        apply = function()
            config.upsert_buffer_input(resource_id, input_id, body)
        end,
        success_builder = function(_, revision_id)
            local row = nil
            local rows = config.list_buffer_inputs(resource_id)
            for _, item in ipairs(rows) do
                if item.id == input_id then
                    row = item
                    break
                end
            end
            if not row then
                return { status = "ok", revision_id = revision_id }
            end
            local payload = buffer_input_payload(row)
            payload.revision_id = revision_id
            return payload
        end,
    })
end

local function delete_buffer_input(server, client, resource_id, input_id, request)
    if not config.get_buffer_resource(resource_id) then
        return error_response(server, client, 404, "buffer resource not found")
    end
    apply_config_change(server, client, request, {
        comment = "buffer input " .. resource_id .. "/" .. input_id .. " delete",
        defer_export = true,
        apply = function()
            config.delete_buffer_input(resource_id, input_id)
        end,
    })
end

local function list_buffer_allow(server, client)
    local rows = config.list_buffer_allow()
    local result = {}
    for _, row in ipairs(rows) do
        table.insert(result, buffer_allow_payload(row))
    end
    json_response(server, client, 200, result)
end

local function add_buffer_allow(server, client, body, request)
    if not body then
        return error_response(server, client, 400, "invalid json")
    end
    local kind = tostring(body.kind or "")
    if kind ~= "allow" and kind ~= "allowRange" then
        return error_response(server, client, 400, "invalid allow kind")
    end
    local value = tostring(body.value or "")
    if value == "" then
        return error_response(server, client, 400, "allow value required")
    end
    local id = body.id or generate_id("allow")
    log.debug("[buffers] save allow id=" .. id .. " payload=" .. json.encode(body))
    apply_config_change(server, client, request, {
        comment = "buffer allow " .. id,
        defer_export = true,
        apply = function()
            config.add_buffer_allow(id, kind, value)
        end,
        success_builder = function(_, revision_id)
            local row = nil
            local rows = config.list_buffer_allow()
            for _, item in ipairs(rows) do
                if item.id == id then
                    row = item
                    break
                end
            end
            if row then
                local payload = buffer_allow_payload(row)
                payload.revision_id = revision_id
                return payload
            end
            return { id = id, kind = kind, value = value, revision_id = revision_id }
        end,
    })
end

local function delete_buffer_allow(server, client, rule_id, request)
    apply_config_change(server, client, request, {
        comment = "buffer allow " .. rule_id .. " delete",
        defer_export = true,
        apply = function()
            config.delete_buffer_allow(rule_id)
        end,
    })
end

local function reload_buffers(server, client)
    if buffer and buffer.refresh then
        buffer.refresh()
    end
    json_response(server, client, 200, { status = "ok" })
end

local function restart_buffer_reader(server, client, id)
    local ok = buffer and buffer.restart_reader and buffer.restart_reader(id)
    if not ok then
        return error_response(server, client, 404, "buffer resource not found")
    end
    json_response(server, client, 200, { status = "ok" })
end

local function list_buffer_status(server, client)
    local cached = status_cache_read("buffer")
    if cached then
        return json_response(server, client, 200, cached)
    end
    local status = buffer and buffer.list_status and buffer.list_status() or {}
    for _, row in ipairs(status) do
        row.output_url = buffer_output_url(row.path)
    end
    status_cache_write("buffer", status)
    json_response(server, client, 200, status)
end

local function get_buffer_status(server, client, id)
    local status = buffer and buffer.get_status and buffer.get_status(id)
    if not status then
        return error_response(server, client, 404, "buffer resource not found")
    end
    status.output_url = buffer_output_url(status.path)
    json_response(server, client, 200, status)
end

local function list_adapter_status(server, client)
    local cached = status_cache_read("adapter")
    if cached then
        return json_response(server, client, 200, cached)
    end
    local status = runtime and runtime.list_adapter_status and runtime.list_adapter_status() or {}
    status_cache_write("adapter", status)
    json_response(server, client, 200, status)
end

local function list_dvb_adapters(server, client)
    if not dvbls then
        return error_response(server, client, 501, "dvbls module is not found")
    end
    local ok, result = pcall(dvbls)
    if not ok then
        return error_response(server, client, 500, "failed to list dvb adapters")
    end
    json_response(server, client, 200, result or {})
end

function dvb_scan_collect_cas(descriptors)
    local cas = {}
    if type(descriptors) ~= "table" then
        return cas
    end
    for _, desc in ipairs(descriptors) do
        if type(desc) == "table" and desc.type_name == "cas" then
            local entry = {
                caid = tonumber(desc.caid),
                pid = tonumber(desc.pid),
                data = desc.data,
            }
            table.insert(cas, entry)
        end
    end
    return cas
end

function dvb_scan_merge_cas(target, items)
    target = target or {}
    local seen = {}
    for _, entry in ipairs(target) do
        if entry.caid then
            local key = tostring(entry.caid) .. ":" .. tostring(entry.pid or "")
            seen[key] = true
        end
    end
    for _, entry in ipairs(items or {}) do
        if entry.caid then
            local key = tostring(entry.caid) .. ":" .. tostring(entry.pid or "")
            if not seen[key] then
                table.insert(target, entry)
                seen[key] = true
            end
        end
    end
    return target
end

function dvb_scan_find_lang(descriptors)
    if type(descriptors) ~= "table" then
        return nil
    end
    for _, desc in ipairs(descriptors) do
        if type(desc) == "table" and desc.type_name == "lang" and desc.lang ~= nil then
            return tostring(desc.lang)
        end
    end
    return nil
end

function dvb_scan_find_descriptor(descriptors, type_ids)
    if type(descriptors) ~= "table" then
        return nil
    end
    local wanted = {}
    if type(type_ids) == "table" then
        for _, value in ipairs(type_ids) do
            local id = tonumber(value)
            if id then
                wanted[id] = true
            end
        end
    else
        local id = tonumber(type_ids)
        if id then
            wanted[id] = true
        end
    end
    if next(wanted) == nil then
        return nil
    end
    for _, desc in ipairs(descriptors) do
        if type(desc) == "table" then
            local id = tonumber(desc.type_id)
            if id and wanted[id] and desc.data ~= nil then
                return tostring(desc.data)
            end
        end
    end
    return nil
end

function dvb_scan_add_pat(job, data)
    if type(data.programs) ~= "table" then
        return
    end
    if data.tsid ~= nil then
        job.pat_tsid = tonumber(data.tsid)
    end
    if data.crc32 ~= nil then
        job.pat_crc32 = tonumber(data.crc32)
    end
    job.programs = job.programs or {}
    for _, program in ipairs(data.programs) do
        local pnr = tonumber(program.pnr)
        local pid = tonumber(program.pid)
        if pnr and pnr ~= 0 then
            local entry = job.programs[pnr] or { pnr = pnr }
            entry.pmt_pid = pid or entry.pmt_pid
            job.programs[pnr] = entry
        end
    end
end

function dvb_scan_add_pmt(job, data)
    local pnr = tonumber(data.pnr)
    if not pnr then
        return
    end
    job.programs = job.programs or {}
    local entry = job.programs[pnr] or { pnr = pnr }
    entry.pmt_pid = entry.pmt_pid or tonumber(data.pid)
    entry.pcr = tonumber(data.pcr)
    entry.crc32 = tonumber(data.crc32) or entry.crc32
    entry.streams = {}
    entry.cas = dvb_scan_merge_cas(entry.cas, dvb_scan_collect_cas(data.descriptors))

    if type(data.streams) == "table" then
        for _, stream in ipairs(data.streams) do
            local item = {
                pid = tonumber(stream.pid),
                type_id = tonumber(stream.type_id),
                type_name = stream.type_name,
                lang = dvb_scan_find_lang(stream.descriptors),
                cas = dvb_scan_collect_cas(stream.descriptors),
            }
            local desc = dvb_scan_find_descriptor(stream.descriptors, { 0x59, 0x56 })
            if desc ~= nil then
                item.descriptor = desc
            end
            entry.streams[#entry.streams + 1] = item
            entry.cas = dvb_scan_merge_cas(entry.cas, item.cas)
        end
    end
    job.programs[pnr] = entry
end

function dvb_scan_add_sdt(job, data)
    if type(data.services) ~= "table" then
        return
    end
    if data.tsid ~= nil then
        job.sdt_tsid = tonumber(data.tsid)
    end
    if data.crc32 ~= nil then
        job.sdt_crc32 = tonumber(data.crc32)
    end
    job.services = job.services or {}
    for _, service in ipairs(data.services) do
        local sid = tonumber(service.sid)
        if sid then
            local name, provider = nil, nil
            if type(service.descriptors) == "table" then
                for _, desc in ipairs(service.descriptors) do
                    if type(desc) == "table" and desc.type_name == "service" then
                        name = desc.service_name or name
                        provider = desc.service_provider or provider
                    end
                end
            end
            job.services[sid] = { name = name, provider = provider }
        end
    end
end

function dvb_scan_build_channels(job)
    local channels = {}
    for pnr, entry in pairs(job.programs or {}) do
        if pnr and tonumber(pnr) ~= 0 then
            local service = (job.services and job.services[pnr]) or {}
            local channel = {
                pnr = tonumber(pnr),
                name = service.name,
                provider = service.provider,
                pmt_pid = entry.pmt_pid,
                cas = entry.cas or {},
                video = {},
                audio = {},
            }
            for _, stream in ipairs(entry.streams or {}) do
                local type_name = tostring(stream.type_name or "")
                local lower = type_name:lower()
                if lower:find("video", 1, true) then
                    table.insert(channel.video, {
                        pid = stream.pid,
                        type = type_name,
                        type_id = stream.type_id,
                    })
                elseif lower:find("audio", 1, true) then
                    table.insert(channel.audio, {
                        pid = stream.pid,
                        lang = stream.lang,
                        type = type_name,
                        type_id = stream.type_id,
                    })
                end
            end
            table.insert(channels, channel)
        end
    end
    table.sort(channels, function(a, b)
        return (a.pnr or 0) < (b.pnr or 0)
    end)
    job.channels = channels
end

function dvb_scan_finish(job, status, err)
    if job.timer then
        job.timer:close()
        job.timer = nil
    end
    if job.analyze then
        job.analyze = nil
    end
    if job.input then
        kill_input(job.input)
        job.input = nil
    end
    job.finished_at = os.time()
    job.status = status
    if err then
        job.error = err
    end
    job.signal = runtime and runtime.get_adapter_status and runtime.get_adapter_status(job.adapter_id) or nil
    dvb_scan_build_channels(job)
    dvb_scan_cleanup()
end

local function stream_analyze_finish(job, status, err)
    if job.timer then
        job.timer:close()
        job.timer = nil
    end
    if job.analyze then
        job.analyze = nil
    end
    if job.input then
        kill_input(job.input)
        job.input = nil
    end
    if job.retained and job.channel_data and _G.channel_release then
        -- Analyze can temporarily retain a live stream pipeline so it stays active without viewers.
        -- Release the retain when the job finishes, even on errors.
        pcall(_G.channel_release, job.channel_data, "analyze")
        job.retained = nil
    end
    -- Даже если retain не делали, не держим ссылки на канал в finished job.
    job.channel_data = nil
    job.finished_at = os.time()
    job.status = status
    if err then
        job.error = err
    end
    dvb_scan_build_channels(job)
    do
        local list = {}
        for _, channel in ipairs(job.channels or {}) do
            if type(channel) == "table" then
                table.insert(list, {
                    pnr = channel.pnr,
                    pmt_pid = channel.pmt_pid,
                    pcr = channel.pcr,
                    name = channel.name,
                    provider = channel.provider,
                })
            end
        end
        table.sort(list, function(a, b)
            return (tonumber(a.pnr) or 0) < (tonumber(b.pnr) or 0)
        end)
        job.program_list = list
    end
    local program_count = 0
    for _ in pairs(job.programs or {}) do
        program_count = program_count + 1
    end
    job.summary = {
        programs = program_count,
        channels = job.channels and #job.channels or 0,
        bitrate = job.totals and job.totals.bitrate or nil,
        cc_errors = job.totals and job.totals.cc_errors or nil,
        pes_errors = job.totals and job.totals.pes_errors or nil,
        scrambled = job.totals and job.totals.scrambled or nil,
    }
    stream_analyze_cleanup()
    stream_analyze.active = math.max(0, stream_analyze.active - 1)
end

local function get_analyze_limit()
    local limit = setting_number("monitor_analyze_max_concurrency", 2)
    if not limit or limit < 1 then
        limit = 1
    end
    return limit
end

local function resolve_stream_input_url(stream_id)
    local status = runtime and runtime.get_stream_status and runtime.get_stream_status(stream_id) or nil
    if status and status.transcode_state then
        return nil, "transcode stream is not supported"
    end
    if status and status.active_input_url then
        return status.active_input_url
    end
    local row = config.get_stream(stream_id)
    if not row then
        return nil, "stream not found"
    end
    local cfg = row.config or {}
    local inputs = cfg.input
    if type(inputs) == "table" and #inputs > 0 then
        return inputs[1]
    end
    if type(inputs) == "string" and inputs ~= "" then
        return inputs
    end
    return nil, "no input url"
end

local function stream_analyze_payload(job)
    if not job then
        return nil
    end
    local include_scan_details = (job.status ~= "running")

    local function copy_cas_rows(rows)
        local out = {}
        for _, row in ipairs(rows or {}) do
            if type(row) == "table" then
                table.insert(out, {
                    caid = tonumber(row.caid),
                    pid = tonumber(row.pid),
                })
            end
        end
        return out
    end

    local function copy_stream_rows(rows)
        local out = {}
        for _, row in ipairs(rows or {}) do
            if type(row) == "table" then
                table.insert(out, {
                    pid = tonumber(row.pid),
                    type_name = row.type,
                    type_id = tonumber(row.type_id),
                    lang = row.lang,
                    cas = copy_cas_rows(row.cas),
                })
            end
        end
        return out
    end

    local channels = nil
    local programs = nil
    local program_list = nil
    if include_scan_details then
        channels = {}
        programs = {}
        program_list = {}
        for _, channel in ipairs(job.channels or {}) do
            if type(channel) == "table" then
                local video = copy_stream_rows(channel.video)
                local audio = copy_stream_rows(channel.audio)
                local channel_copy = {
                    pnr = tonumber(channel.pnr),
                    name = channel.name,
                    provider = channel.provider,
                    pmt_pid = tonumber(channel.pmt_pid),
                    pcr = tonumber(channel.pcr),
                    cas = copy_cas_rows(channel.cas),
                    video = video,
                    audio = audio,
                }
                table.insert(channels, channel_copy)
                table.insert(program_list, {
                    pnr = channel_copy.pnr,
                    pmt_pid = channel_copy.pmt_pid,
                    pcr = channel_copy.pcr,
                    name = channel_copy.name,
                    provider = channel_copy.provider,
                })

                local streams = {}
                for _, row in ipairs(video) do
                    table.insert(streams, {
                        pid = row.pid,
                        type_name = row.type_name,
                        type_id = row.type_id,
                    })
                end
                for _, row in ipairs(audio) do
                    table.insert(streams, {
                        pid = row.pid,
                        type_name = row.type_name,
                        type_id = row.type_id,
                        lang = row.lang,
                    })
                end
                table.insert(programs, {
                    pnr = channel_copy.pnr,
                    pmt_pid = channel_copy.pmt_pid,
                    pcr = channel_copy.pcr,
                    name = channel_copy.name,
                    provider = channel_copy.provider,
                    cas = copy_cas_rows(channel.cas),
                    streams = streams,
                })
            end
        end
        table.sort(channels, function(a, b)
            return (a.pnr or 0) < (b.pnr or 0)
        end)
        table.sort(programs, function(a, b)
            return (a.pnr or 0) < (b.pnr or 0)
        end)
        table.sort(program_list, function(a, b)
            return (a.pnr or 0) < (b.pnr or 0)
        end)
    end

    local pids = {}
    for _, row in ipairs(job.pids or {}) do
        if type(row) == "table" then
            table.insert(pids, {
                pid = tonumber(row.pid),
                bitrate = tonumber(row.bitrate),
                cc_error = tonumber(row.cc_error) or 0,
                pes_error = tonumber(row.pes_error) or 0,
                sc_error = tonumber(row.sc_error) or 0,
            })
        end
    end

    local totals = nil
    if type(job.totals) == "table" then
        totals = {
            bitrate = tonumber(job.totals.bitrate) or 0,
            cc_errors = tonumber(job.totals.cc_errors) or 0,
            pes_errors = tonumber(job.totals.pes_errors) or 0,
            scrambled = job.totals.scrambled == true,
        }
    end

    local summary = nil
    if type(job.summary) == "table" then
        summary = {
            programs = tonumber(job.summary.programs) or 0,
            channels = tonumber(job.summary.channels) or 0,
            bitrate = tonumber(job.summary.bitrate) or 0,
            cc_errors = tonumber(job.summary.cc_errors) or 0,
            pes_errors = tonumber(job.summary.pes_errors) or 0,
            scrambled = job.summary.scrambled == true,
        }
    end

    return {
        id = job.id,
        status = job.status,
        stream_id = job.stream_id,
        stream_name = job.stream_name,
        input_url = job.input_url,
        duration_sec = job.duration_sec,
        started_at = job.started_at,
        finished_at = job.finished_at,
        error = job.error,
        totals = totals,
        summary = summary,
        pids = pids,
        programs = programs,
        program_list = program_list,
        channels = channels,
        pat_tsid = job.pat_tsid,
        pat_crc32 = job.pat_crc32,
        sdt_tsid = job.sdt_tsid,
        sdt_crc32 = job.sdt_crc32,
        last_update = job.last_update,
    }
end

local function build_local_play_url(stream_id)
    local http_port = tonumber(config and config.get_setting and config.get_setting("http_port") or nil) or 8000
    local play_port = tonumber(config and config.get_setting and config.get_setting("http_play_port") or nil) or http_port
    if not play_port or play_port == 0 then
        play_port = http_port
    end
    -- internal=1: loopback-анализ должен работать даже если /play скрыт для внешних клиентов
    -- или включён http_auth (см. server.lua: is_internal_play_request()).
    return "http://127.0.0.1:" .. tostring(play_port) .. "/play/" .. tostring(stream_id) .. "?internal=1#sync"
end

local function start_stream_analyze(server, client, request, stream_id_override)
    if not require_auth(request) then
        return error_response(server, client, 401, "unauthorized")
    end
    if not analyze then
        return error_response(server, client, 501, "analyze module is not found")
    end
    local body = parse_json_body(request) or {}
    local input_url_override = body.input_url or body.input
    if input_url_override ~= nil and type(input_url_override) ~= "string" then
        return error_response(server, client, 400, "input_url must be a string")
    end
    if input_url_override ~= nil and input_url_override == "" then
        input_url_override = nil
    end
    local stream_id = stream_id_override or body.stream_id or body.id
    if not stream_id or stream_id == "" then
        return error_response(server, client, 400, "stream_id is required")
    end
    local limit = get_analyze_limit()
    if stream_analyze.active >= limit then
        return error_response(server, client, 429, "analyze busy")
    end
    local duration = tonumber(body.duration_sec) or 3
    if duration < 2 then duration = 2 end
    if duration > 10 then duration = 10 end

    local analyze_key = input_url_override and tostring(input_url_override) or "__live__"
    for _, job in pairs(stream_analyze.jobs) do
        local job_key = job and (job.analyze_key or "__live__") or nil
        if job and job.status == "running" and job.stream_id == tostring(stream_id) and job_key == analyze_key then
            return json_response(server, client, 200, { id = job.id, status = job.status, stream_id = job.stream_id })
        end
    end

    local input_url = nil
    local input_err = nil
    if input_url_override then
        input_url = tostring(input_url_override)
    else
        input_url, input_err = resolve_stream_input_url(stream_id)
    end

    -- Prefer analyzing the live stream pipeline (post-remap, same as /play) when available.
    -- This avoids SSRF/allowlist problems for remote inputs and works for stream:// sources.
    local entry = runtime and runtime.streams and runtime.streams[tostring(stream_id)] or nil
    local channel_data = entry and entry.channel or nil
    local active_id = channel_data and tonumber(channel_data.active_input_id or 0) or 0
    -- stream.lua экспортирует удержание канала как _G.channel_retain/_G.channel_release
    -- (локальные channel_retain/channel_release не видны отсюда).
    -- Если retain недоступен, но канал уже активен (active_input_id!=0) - можем анализировать без удержания.
    local can_retain = (channel_data and _G.channel_retain and _G.channel_release) and true or false
    local can_tail = channel_data and channel_data.tail or nil
    local can_attach_live = (not input_url_override) and can_tail and (can_retain or active_id ~= 0)

    if not can_attach_live and not input_url then
        return error_response(server, client, 400, input_err or "input url not found")
    end

    local stream_name = tostring(stream_id)
    local row = config and config.get_stream and config.get_stream(stream_id)
    if row and row.config and row.config.name and row.config.name ~= "" then
        stream_name = row.config.name
    end

    stream_analyze.seq = stream_analyze.seq + 1
    local id = tostring(stream_analyze.seq)
    local job = {
        id = id,
        stream_id = tostring(stream_id),
        stream_name = stream_name,
        input_url = input_url and tostring(input_url) or nil,
        analyze_key = analyze_key,
        status = "running",
        started_at = os.time(),
        duration_sec = duration,
        programs = {},
        services = {},
        channels = {},
        totals = {},
        pids = {},
    }

    local analyze_name = "stream-analyze-" .. tostring(stream_id) .. "-" .. tostring(id)
    local upstream = nil

    -- If the stream exists in runtime but is idle, channel_data.tail can be nil until we activate inputs.
    -- Try to retain first (when available) to bring the pipeline up, then re-check tail.
    if (not input_url_override) and channel_data and can_retain and not can_tail then
        job.channel_data = channel_data
        local ok, retained = pcall(_G.channel_retain, channel_data, "analyze")
        if ok and retained then
            job.retained = true
        end
        can_tail = channel_data.tail
        if can_tail then
            can_attach_live = true
        end
    end

    if can_attach_live then
        job.channel_data = channel_data
        if can_retain and not job.retained then
            local ok, retained = pcall(_G.channel_retain, channel_data, "analyze")
            if ok and retained then
                job.retained = true
            end
        end
        upstream = channel_data.tail:stream()
    else
        if input_url_override and input_url then
            local conf = parse_url(input_url)
            if not conf then
                return error_response(server, client, 400, "invalid input url")
            end
            conf.name = analyze_name

            local input = init_input(conf)
            if not input then
                return error_response(server, client, 500, "failed to init input")
            end
            job.input = input
            upstream = input.tail:stream()
        else
        -- Fallback: analyze through loopback /play. This avoids SSRF allowlist issues for remote inputs
        -- and ensures the analyzed TS matches what external clients see.
        -- Даже если канал ещё не активен (нет viewers / on-demand), loopback /play
        -- безопаснее, чем прямой http_request к input_url: не упираемся в allowlist
        -- и получаем ровно тот TS, который видит внешний клиент.
        local url = build_local_play_url(stream_id)
        local conf = parse_url(url)
        if not conf then
            return error_response(server, client, 400, "invalid input url")
        end
        conf.name = analyze_name

        local input = init_input(conf)
        if not input and input_url then
            -- Loopback can fail if /play is disabled or stream is missing in runtime; try the raw input URL.
            conf = parse_url(input_url)
            if not conf then
                return error_response(server, client, 400, "invalid input url")
            end
            conf.name = analyze_name
            input = init_input(conf)
        end
        if not input then
            return error_response(server, client, 500, "failed to init input")
        end
        job.input = input
        upstream = input.tail:stream()
        end
    end

    stream_analyze.active = stream_analyze.active + 1
    job.analyze = analyze({
        upstream = upstream,
        name = analyze_name,
        join_pid = true,
        callback = function(data)
            if type(data) ~= "table" then
                return
            end
            if data.error then
                job.error = data.error
                return
            end
            if data.psi == "pat" then
                dvb_scan_add_pat(job, data)
            elseif data.psi == "pmt" then
                dvb_scan_add_pmt(job, data)
            elseif data.psi == "sdt" then
                dvb_scan_add_sdt(job, data)
            elseif data.analyze and data.total then
                local total = data.total or {}
                -- Keep a plain snapshot table to avoid json.encode races on mutable analyzer internals.
                job.totals = {
                    bitrate = tonumber(total.bitrate) or 0,
                    cc_errors = tonumber(total.cc_errors) or 0,
                    pes_errors = tonumber(total.pes_errors) or 0,
                    scrambled = total.scrambled == true,
                }
                job.last_update = os.time()
                if type(data.analyze) == "table" then
                    local list = {}
                    for _, item in ipairs(data.analyze) do
                        if type(item) == "table" then
                            local pid = tonumber(item.pid)
                            if pid then
                                table.insert(list, {
                                    pid = pid,
                                    bitrate = tonumber(item.bitrate),
                                    cc_error = tonumber(item.cc_error) or 0,
                                    pes_error = tonumber(item.pes_error) or 0,
                                    sc_error = tonumber(item.sc_error) or 0,
                                })
                            end
                        end
                    end
                    table.sort(list, function(a, b)
                        return (a.pid or 0) < (b.pid or 0)
                    end)
                    job.pids = list
                end
            end
        end,
    })

    job.timer = timer({
        interval = duration,
        callback = function(self)
            self:close()
            stream_analyze_finish(job, "done")
        end,
    })

    stream_analyze.jobs[id] = job
    json_response(server, client, 200, { id = job.id, status = job.status, stream_id = job.stream_id })
end

local function get_stream_analyze(server, client, request, id)
    if not require_auth(request) then
        return error_response(server, client, 401, "unauthorized")
    end
    local job = stream_analyze.jobs[id]
    if not job then
        return error_response(server, client, 404, "analyze job not found")
    end
    json_response(server, client, 200, stream_analyze_payload(job))
end

function dvb_scan_config_from_adapter(adapter_id)
    local row = config.get_adapter(adapter_id)
    if not row then
        return nil, "adapter not found"
    end
    local cfg = row.config or {}
    if cfg.adapter == nil then
        return nil, "adapter index is required"
    end
    local conf = {
        name = "dvb-scan-" .. tostring(adapter_id),
        format = "dvb",
        adapter = cfg.adapter,
        device = cfg.device or 0,
        type = cfg.type,
        tp = cfg.tp,
        lnb = cfg.lnb,
        lof1 = cfg.lof1,
        lof2 = cfg.lof2,
        slof = cfg.slof,
        diseqc = cfg.diseqc,
        tone = cfg.tone,
        rolloff = cfg.rolloff,
        uni_scr = cfg.uni_scr,
        uni_frequency = cfg.uni_frequency,
        frequency = cfg.frequency,
        polarization = cfg.polarization,
        symbolrate = cfg.symbolrate,
        bandwidth = cfg.bandwidth,
        guardinterval = cfg.guardinterval,
        transmitmode = cfg.transmitmode,
        hierarchy = cfg.hierarchy,
        modulation = cfg.modulation,
        budget = cfg.budget,
    }
    if (not conf.tp or conf.tp == "") and conf.frequency and conf.polarization and conf.symbolrate then
        conf.tp = tostring(conf.frequency) .. ":" .. tostring(conf.polarization) .. ":" .. tostring(conf.symbolrate)
    end
    return conf, nil
end

local function start_dvb_scan(server, client, request)
    local user = require_admin(request)
    if not user then
        return error_response(server, client, 401, "unauthorized")
    end
    if not analyze then
        return error_response(server, client, 501, "analyze module is not found")
    end
    local body = parse_json_body(request) or {}
    local adapter_id = body.adapter_id or body.id
    if not adapter_id or adapter_id == "" then
        return error_response(server, client, 400, "adapter_id is required")
    end
    local duration = tonumber(body.duration_sec) or 8
    if duration < 2 then duration = 2 end
    if duration > 30 then duration = 30 end

    for _, job in pairs(dvb_scan.jobs) do
        if job and job.status == "running" and job.adapter_id == adapter_id then
            return json_response(server, client, 200, { id = job.id, status = job.status, adapter_id = adapter_id })
        end
    end

    local conf, err = dvb_scan_config_from_adapter(adapter_id)
    if not conf then
        return error_response(server, client, 400, err or "invalid adapter config")
    end

    dvb_scan.seq = dvb_scan.seq + 1
    local id = tostring(dvb_scan.seq)
    local job = {
        id = id,
        adapter_id = adapter_id,
        status = "running",
        started_at = os.time(),
        programs = {},
        services = {},
        channels = {},
    }

    local input = init_input(conf)
    if not input then
        return error_response(server, client, 500, "failed to init dvb input")
    end
    job.input = input
    job.analyze = analyze({
        upstream = input.tail:stream(),
        name = conf.name,
        join_pid = true,
        callback = function(data)
            if type(data) ~= "table" then
                return
            end
            if data.error then
                job.error = data.error
                return
            end
            if data.psi == "pat" then
                dvb_scan_add_pat(job, data)
            elseif data.psi == "pmt" then
                dvb_scan_add_pmt(job, data)
            elseif data.psi == "sdt" then
                dvb_scan_add_sdt(job, data)
            end
        end,
    })

    job.timer = timer({
        interval = duration,
        callback = function(self)
            self:close()
            dvb_scan_finish(job, "done")
        end,
    })

    dvb_scan.jobs[id] = job
    json_response(server, client, 200, { id = id, status = job.status, adapter_id = adapter_id })
end

local function get_dvb_scan(server, client, request, id)
    local job = dvb_scan.jobs[id]
    if not job then
        return error_response(server, client, 404, "scan not found")
    end
    local payload = {
        id = job.id,
        status = job.status,
        adapter_id = job.adapter_id,
        started_at = job.started_at,
        finished_at = job.finished_at,
        error = job.error,
        signal = job.signal,
        channels = job.channels,
    }
    if job.status == "running" and (runtime and runtime.get_adapter_status) then
        payload.signal = runtime.get_adapter_status(job.adapter_id) or payload.signal
    end
    json_response(server, client, 200, payload)
end

function dvb_autosearch_enabled()
    return setting_bool("dvb_autosearch_enabled", true)
end

function dvb_autosearch_lock_ttl_sec()
    return clamp_number(setting_number("dvb_autosearch_lock_ttl_sec", 30), 10, 120) or 30
end

function dvb_autosearch_is_leader()
    if sharding and type(sharding.is_active) == "function" and sharding.is_active() then
        if type(sharding.is_master) == "function" then
            return sharding.is_master()
        end
        return false
    end
    return true
end

function dvb_autosearch_lock_ok()
    if not dvb_autosearch_is_leader() then
        return false
    end
    local now = os.time()
    local ttl = dvb_autosearch_lock_ttl_sec()
    local owner = tostring(os.getenv("HOSTNAME") or "stream") .. ":" .. tostring(setting_number("http_port", 0) or 0)
    if dvb_autosearch.lock_owner == "" or (now - (tonumber(dvb_autosearch.lock_ts) or 0)) >= ttl then
        dvb_autosearch.lock_owner = owner
        dvb_autosearch.lock_ts = now
        return true
    end
    if dvb_autosearch.lock_owner == owner then
        dvb_autosearch.lock_ts = now
        return true
    end
    return false
end

function dvb_extract_adapter_id(url)
    if type(url) ~= "string" then
        return nil
    end
    local id = url:match("^dvb://([^#%?]+)")
    if not id or id == "" then
        return nil
    end
    return tostring(id)
end

function dvb_autosearch_adapter_cfg(row)
    local cfg = row and row.config or {}
    return {
        enabled = normalize_bool(cfg.auto_signal_search_enabled, false),
        window_sec = clamp_number(cfg.auto_signal_window_sec, 60, 1800) or 300,
        mode = tostring(cfg.auto_signal_bitrate_mode or "both"),
        bitrate_min_kbps = clamp_number(cfg.auto_signal_bitrate_min_kbps, 1, 100000) or 500,
        baseline_window_sec = clamp_number(cfg.auto_signal_baseline_window_sec, 300, 7200) or 1800,
        baseline_drop_ratio_pct = clamp_number(cfg.auto_signal_baseline_drop_ratio_pct, 1, 99) or 70,
        cc_delta_threshold = clamp_number(cfg.auto_signal_cc_delta_threshold, 1, 100000) or 50,
        probe_sec = clamp_number(cfg.auto_signal_probe_sec, 5, 120) or 30,
        confirm_sec = clamp_number(cfg.auto_signal_confirm_sec, 10, 180) or 60,
        switch_cooldown_sec = clamp_number(cfg.auto_signal_switch_cooldown_sec, 30, 3600) or 180,
        min_streams = clamp_number(cfg.auto_signal_min_streams, 1, 2000) or 1,
        candidate_profiles = type(cfg.auto_signal_candidate_profiles) == "table" and cfg.auto_signal_candidate_profiles or {},
        allow_type_flip = normalize_bool(cfg.auto_signal_type_flip_enabled, false),
        type_flip_s2_hold_sec = clamp_number(cfg.auto_signal_type_flip_s2_hold_sec, 1, 120) or 10,
        type_flip_wait_sec = clamp_number(cfg.auto_signal_type_flip_wait_sec, 5, 120) or 20,
        type_flip_confirm_sec = clamp_number(cfg.auto_signal_type_flip_confirm_sec, 30, 600) or 180,
        type_flip_cc_window_sec = clamp_number(cfg.auto_signal_type_flip_cc_window_sec, 10, 600) or 60,
        type_flip_cc_threshold = clamp_number(cfg.auto_signal_type_flip_cc_threshold, 1, 100000) or 50,
        -- Standalone type-flip trigger (S2->S->S2) uses CC+PES deltas over a 60s window.
        type_flip_fault_window_sec = clamp_number(cfg.auto_signal_type_flip_fault_window_sec, 10, 600)
            or clamp_number(cfg.auto_signal_type_flip_cc_window_sec, 10, 600)
            or 60,
        -- Legacy no_data threshold is kept for backward compatibility but no longer used
        -- by standalone type-flip trigger logic.
        type_flip_no_data_threshold = clamp_number(cfg.auto_signal_type_flip_no_data_threshold, 1, 100000) or 40,
        type_flip_pes_threshold = clamp_number(cfg.auto_signal_type_flip_pes_threshold, 1, 100000) or 50,
    }
end

function dvb_autosearch_collect_runtime()
    local out = {}
    local status = runtime and runtime.list_status_lite and runtime.list_status_lite() or {}
    local now = os.time()
    local seen_streams = {}
    for stream_id, entry in pairs(status or {}) do
        local sid = tostring(stream_id or "")
        if sid ~= "" then
            seen_streams[sid] = true
        end
        local adapter_id = dvb_extract_adapter_id(entry and entry.active_input_url)
        if not adapter_id and sid ~= "" then
            dvb_autosearch.stream_fault_state[sid] = nil
        end
        if adapter_id then
            local row = out[adapter_id]
            if not row then
                row = {
                    adapter_id = adapter_id,
                    streams = 0,
                    streams_on_air = 0,
                    bitrate_kbps = 0,
                    cc_total = 0,
                    pes_total = 0,
                    no_data_fault_events = 0,
                    stream_ids = {},
                }
                out[adapter_id] = row
            end

            row.streams = row.streams + 1
            row.stream_ids[#row.stream_ids + 1] = tostring(stream_id)
            if entry.on_air == true then
                row.streams_on_air = row.streams_on_air + 1
            end

            local active = nil
            if type(entry.inputs) == "table" and tonumber(entry.active_input_id) and tonumber(entry.active_input_id) > 0 then
                active = entry.inputs[tonumber(entry.active_input_id)]
            end
            local bitrate = tonumber(active and active.bitrate_kbps) or tonumber(entry.input_bitrate_kbps)
                or tonumber(entry.bitrate) or 0
            if bitrate < 0 then
                bitrate = 0
            end
            row.bitrate_kbps = row.bitrate_kbps + bitrate
            row.cc_total = row.cc_total + (tonumber(active and active.cc_errors) or 0)
            row.pes_total = row.pes_total + (tonumber(active and active.pes_errors) or 0)

            if sid ~= "" then
                local last_error = tostring(active and active.last_error or "")
                local is_no_data = (last_error == "no_data")
                local prev = dvb_autosearch.stream_fault_state[sid]
                local prev_is_no_data = prev
                    and tostring(prev.adapter_id or "") == tostring(adapter_id)
                    and prev.is_no_data == true
                if is_no_data and not prev_is_no_data then
                    row.no_data_fault_events = row.no_data_fault_events + 1
                end
                dvb_autosearch.stream_fault_state[sid] = {
                    adapter_id = tostring(adapter_id),
                    is_no_data = is_no_data,
                    ts = now,
                }
            end
        end
    end
    for sid, meta in pairs(dvb_autosearch.stream_fault_state or {}) do
        if not seen_streams[sid] then
            dvb_autosearch.stream_fault_state[sid] = nil
        elseif type(meta) == "table" and (now - (tonumber(meta.ts) or now)) > 7200 then
            dvb_autosearch.stream_fault_state[sid] = nil
        end
    end
    return out
end

function dvb_autosearch_push_history(snapshot)
    local now = os.time()
    local max_window = 7200
    for adapter_id, item in pairs(snapshot or {}) do
        local list = dvb_autosearch.adapter_history[adapter_id]
        if type(list) ~= "table" then
            list = {}
            dvb_autosearch.adapter_history[adapter_id] = list
        end
        local prev_no_data_total = tonumber(list[#list] and list[#list].no_data_fault_total) or 0
        local no_data_fault_events = tonumber(item.no_data_fault_events) or 0
        if no_data_fault_events < 0 then
            no_data_fault_events = 0
        end
        local no_data_fault_total = prev_no_data_total + no_data_fault_events
        list[#list + 1] = {
            ts = now,
            streams = tonumber(item.streams) or 0,
            streams_on_air = tonumber(item.streams_on_air) or 0,
            bitrate_kbps = tonumber(item.bitrate_kbps) or 0,
            cc_total = tonumber(item.cc_total) or 0,
            pes_total = tonumber(item.pes_total) or 0,
            no_data_fault_events = no_data_fault_events,
            no_data_fault_total = no_data_fault_total,
        }
        local st = dvb_autosearch.adapter_state[adapter_id] or {}
        st.no_data_fault_total = no_data_fault_total
        dvb_autosearch.adapter_state[adapter_id] = st
        while #list > 0 and (now - (tonumber(list[1].ts) or 0)) > max_window do
            table.remove(list, 1)
        end
    end
end

function dvb_autosearch_degradation(adapter_id, row, opts)
    opts = type(opts) == "table" and opts or {}
    local cfg = dvb_autosearch_adapter_cfg(row)
    local list = dvb_autosearch.adapter_history[adapter_id] or {}
    if #list < 2 then
        return false, "insufficient-history", { streams = 0 }
    end
    local now = os.time()
    local window_sec = clamp_number(opts.window_sec, 10, 3600) or cfg.window_sec
    local cc_threshold = clamp_number(opts.cc_threshold, 1, 100000) or cfg.cc_delta_threshold
    local cc_only = normalize_bool(opts.cc_only, false)
    local cc_pes_only = normalize_bool(opts.cc_pes_only, false) or normalize_bool(opts.no_data_pes_only, false)
    local window_from = now - window_sec
    local base_from = now - cfg.baseline_window_sec
    local since_ts = tonumber(opts.since_ts) or 0
    if since_ts > window_from then
        window_from = since_ts
    end
    local window = {}
    local baseline = {}
    for _, item in ipairs(list) do
        local ts = tonumber(item.ts) or 0
        if ts >= window_from then
            window[#window + 1] = item
        end
        if ts >= base_from then
            baseline[#baseline + 1] = item
        end
    end
    if #window < 2 then
        return false, "insufficient-window", { streams = 0 }
    end
    local latest = window[#window]
    local oldest = window[1]
    local streams = tonumber(latest.streams) or 0
    if streams < cfg.min_streams then
        return false, "not-enough-streams", { streams = streams }
    end
    local avg_kbps = (tonumber(latest.bitrate_kbps) or 0) / math.max(1, streams)
    local window_span_sec = math.max(1, (tonumber(window[#window].ts) or now) - (tonumber(window[1].ts) or now))

    if cc_pes_only then
        local cc_sum_threshold = clamp_number(opts.cc_threshold, 1, 100000) or cfg.type_flip_cc_threshold or 50
        local pes_threshold = clamp_number(opts.pes_threshold, 1, 100000) or cfg.type_flip_pes_threshold or 50
        local cc_delta = 0
        local pes_delta = 0
        for i = 2, #window do
            local prev_cc = tonumber(window[i - 1].cc_total) or 0
            local cur_cc = tonumber(window[i].cc_total) or 0
            local cc_step = cur_cc - prev_cc
            if cc_step >= 0 then
                cc_delta = cc_delta + cc_step
            else
                cc_delta = cc_delta + math.max(0, cur_cc)
            end

            local prev_pes = tonumber(window[i - 1].pes_total) or 0
            local cur_pes = tonumber(window[i].pes_total) or 0
            local pes_step = cur_pes - prev_pes
            if pes_step >= 0 then
                pes_delta = pes_delta + pes_step
            else
                pes_delta = pes_delta + math.max(0, cur_pes)
            end
        end

        local cc_bad = cc_delta > cc_sum_threshold
        local pes_bad = pes_delta > pes_threshold
        local degraded = cc_bad and pes_bad
        local reason = degraded and "cc_pes" or "ok"
        return degraded, reason, {
            streams = streams,
            streams_on_air = tonumber(latest.streams_on_air) or 0,
            avg_bitrate_kbps = avg_kbps,
            cc_delta = cc_delta,
            cc_threshold = cc_sum_threshold,
            pes_delta = pes_delta,
            pes_threshold = pes_threshold,
            window_sec = window_sec,
            window_span_sec = window_span_sec,
            cc_bad = cc_bad,
            pes_bad = pes_bad,
        }
    end

    -- CC counters can reset on adapter/input restarts. Build an effective delta that
    -- tolerates resets so sustained CC degradation is still detected.
    local cc_delta = 0
    for i = 2, #window do
        local prev_cc = tonumber(window[i - 1].cc_total) or 0
        local cur_cc = tonumber(window[i].cc_total) or 0
        local step = cur_cc - prev_cc
        if step >= 0 then
            cc_delta = cc_delta + step
        else
            cc_delta = cc_delta + math.max(0, cur_cc)
        end
    end
    local bitrate_abs_bad = avg_kbps < cfg.bitrate_min_kbps

    local baseline_sum = 0
    local baseline_count = 0
    for _, item in ipairs(baseline) do
        local s = math.max(1, tonumber(item.streams) or 0)
        baseline_sum = baseline_sum + ((tonumber(item.bitrate_kbps) or 0) / s)
        baseline_count = baseline_count + 1
    end
    local baseline_avg = baseline_count > 0 and (baseline_sum / baseline_count) or 0
    local baseline_limit = baseline_avg * (1 - (cfg.baseline_drop_ratio_pct / 100))
    local bitrate_rel_bad = baseline_avg > 0 and avg_kbps < baseline_limit

    local bitrate_bad = false
    if cfg.mode == "absolute" then
        bitrate_bad = bitrate_abs_bad
    elseif cfg.mode == "relative" then
        bitrate_bad = bitrate_rel_bad
    else
        bitrate_bad = bitrate_abs_bad or bitrate_rel_bad
    end
    local cc_bad = cc_delta >= cc_threshold
    local degraded = cc_only and cc_bad or (bitrate_bad or cc_bad)
    local reason = degraded and (cc_bad and "cc" or "bitrate") or "ok"
    return degraded, reason, {
        streams = streams,
        streams_on_air = tonumber(latest.streams_on_air) or 0,
        avg_bitrate_kbps = avg_kbps,
        baseline_avg_kbps = baseline_avg,
        cc_delta = cc_delta,
        cc_threshold = cc_threshold,
        window_sec = window_sec,
        window_span_sec = window_span_sec,
        bitrate_abs_bad = bitrate_abs_bad,
        bitrate_rel_bad = bitrate_rel_bad,
        cc_bad = cc_bad,
    }
end

function dvb_autosearch_alert(level, code, message, meta)
    if config and config.add_alert then
        pcall(config.add_alert, level, "", code, message, meta or {})
    end
end

function dvb_autosearch_record_attempt(task, ok, reason, meta)
    local now = os.time()
    local entry = {
        ts = now,
        adapter_id = task and task.adapter_id or "",
        ok = ok == true,
        reason = tostring(reason or ""),
        meta = meta or {},
    }
    dvb_autosearch.recent_attempts[#dvb_autosearch.recent_attempts + 1] = entry
    while #dvb_autosearch.recent_attempts > 120 do
        table.remove(dvb_autosearch.recent_attempts, 1)
    end
    dvb_autosearch.attempts[#dvb_autosearch.attempts + 1] = { ts = now, ok = ok == true }
    local window = clamp_number(setting_number("dvb_autosearch_breaker_window_sec", 600), 60, 7200) or 600
    local cutoff = now - window
    while #dvb_autosearch.attempts > 0 and (tonumber(dvb_autosearch.attempts[1].ts) or 0) < cutoff do
        table.remove(dvb_autosearch.attempts, 1)
    end
    local fail_count = 0
    local success_count = 0
    for _, item in ipairs(dvb_autosearch.attempts) do
        if item.ok then
            success_count = success_count + 1
        else
            fail_count = fail_count + 1
        end
    end
    local fail_limit = clamp_number(setting_number("dvb_autosearch_breaker_fail_count", 3), 1, 20) or 3
    if fail_count >= fail_limit then
        local freeze_sec = clamp_number(setting_number("dvb_autosearch_breaker_freeze_sec", 300), 30, 3600) or 300
        dvb_autosearch.frozen_until_ts = now + freeze_sec
        dvb_autosearch_alert("ERROR", "DVB_AUTOSEARCH_FROZEN",
            "auto signal search frozen by circuit breaker",
            { freeze_sec = freeze_sec, failures = fail_count, successes = success_count })
    elseif (fail_count + success_count) >= 4 and (success_count / math.max(1, fail_count + success_count)) < 0.25 then
        local freeze_sec = clamp_number(setting_number("dvb_autosearch_breaker_freeze_sec", 300), 30, 3600) or 300
        dvb_autosearch.frozen_until_ts = now + freeze_sec
        dvb_autosearch_alert("ERROR", "DVB_AUTOSEARCH_FROZEN",
            "auto signal search frozen due to low success ratio",
            { freeze_sec = freeze_sec, failures = fail_count, successes = success_count })
    end
end

local function dvb_autosearch_reset_adapter_counters(adapter_id)
    local id = tostring(adapter_id or "")
    if id == "" then
        return
    end
    dvb_autosearch.adapter_history[id] = {}
    local st = dvb_autosearch.adapter_state[id] or {}
    st.no_data_fault_total = 0
    st.type_flip_last_reset_ts = os.time()
    dvb_autosearch.adapter_state[id] = st
    for stream_id, meta in pairs(dvb_autosearch.stream_fault_state or {}) do
        if type(meta) == "table" and tostring(meta.adapter_id or "") == id then
            dvb_autosearch.stream_fault_state[stream_id] = nil
        end
    end
end

function dvb_autosearch_task_score(details, queued_at)
    local streams_on_air = tonumber(details and details.streams_on_air) or 0
    local cc_delta = tonumber(details and details.cc_delta) or 0
    local bitrate_deficit = 0
    if details and details.avg_bitrate_kbps and details.expected_bitrate_kbps then
        bitrate_deficit = math.max(0, tonumber(details.expected_bitrate_kbps) - tonumber(details.avg_bitrate_kbps))
    end
    local age_bonus = math.max(0, os.time() - (tonumber(queued_at) or os.time()))
    return streams_on_air * 100 + cc_delta + math.floor(bitrate_deficit) + math.floor(age_bonus / 10)
end

function dvb_autosearch_enqueue(adapter_id, reason, details, opts)
    opts = type(opts) == "table" and opts or {}
    if not adapter_id or adapter_id == "" then
        return false
    end
    local now = os.time()
    local st = dvb_autosearch.adapter_state[adapter_id] or {}
    local reenqueue_sec = clamp_number(setting_number("dvb_autosearch_reenqueue_sec", 60), 1, 3600) or 60
    if not opts.force and st.last_enqueue_ts and (now - (tonumber(st.last_enqueue_ts) or 0)) < reenqueue_sec then
        local existing_cooldown = dvb_autosearch.queue_index[adapter_id]
        if existing_cooldown then
            existing_cooldown.reason = reason or existing_cooldown.reason
            existing_cooldown.details = details or existing_cooldown.details
            existing_cooldown.score = dvb_autosearch_task_score(existing_cooldown.details, existing_cooldown.queued_at)
        end
        st.last_enqueue_reason = tostring(reason or st.last_enqueue_reason or "")
        st.last_enqueue_blocked_ts = now
        dvb_autosearch.adapter_state[adapter_id] = st
        return false
    end
    local existing = dvb_autosearch.queue_index[adapter_id]
    if existing then
        existing.reason = reason or existing.reason
        existing.details = details or existing.details
        existing.score = dvb_autosearch_task_score(existing.details, existing.queued_at)
        return false
    end
    local max_queue = clamp_number(setting_number("dvb_autosearch_queue_max", 32), 1, 512) or 32
    if #dvb_autosearch.queue >= max_queue then
        return false
    end
    dvb_autosearch.seq = dvb_autosearch.seq + 1
    local task = {
        id = "as-" .. tostring(dvb_autosearch.seq),
        adapter_id = tostring(adapter_id),
        reason = tostring(reason or "degraded"),
        details = details or {},
        queued_at = os.time(),
        state = "queued",
        type_flip_only = opts.type_flip_only == true,
    }
    task.score = dvb_autosearch_task_score(task.details, task.queued_at)
    dvb_autosearch.queue[#dvb_autosearch.queue + 1] = task
    dvb_autosearch.queue_index[adapter_id] = task
    st.last_enqueue_ts = now
    st.last_enqueue_reason = task.reason
    dvb_autosearch.adapter_state[adapter_id] = st
    return true
end

function dvb_autosearch_dequeue()
    if #dvb_autosearch.queue == 0 then
        return nil
    end
    table.sort(dvb_autosearch.queue, function(a, b)
        local sa = tonumber(a.score) or 0
        local sb = tonumber(b.score) or 0
        if sa == sb then
            return (tonumber(a.queued_at) or 0) < (tonumber(b.queued_at) or 0)
        end
        return sa > sb
    end)
    local task = nil
    local last_adapter_id = tostring(dvb_autosearch.last_dequeued_adapter_id or "")
    if #dvb_autosearch.queue > 1 and last_adapter_id ~= "" and tostring(dvb_autosearch.queue[1].adapter_id or "") == last_adapter_id then
        task = table.remove(dvb_autosearch.queue, 2)
    else
        task = table.remove(dvb_autosearch.queue, 1)
    end
    if task then
        dvb_autosearch.queue_index[task.adapter_id] = nil
        dvb_autosearch.last_dequeued_adapter_id = task.adapter_id
    end
    return task
end

function dvb_autosearch_adapter_busy_keys()
    local busy = {}
    if not dvbls then
        return busy
    end
    local ok, list = pcall(dvbls)
    if not ok or type(list) ~= "table" then
        return busy
    end
    for _, item in ipairs(list) do
        if type(item) == "table" and item.adapter ~= nil and item.device ~= nil and item.busy == true then
            busy[tostring(item.adapter) .. "." .. tostring(item.device)] = true
        end
    end
    return busy
end

function dvb_autosearch_merge_tp_fields(conf)
    if (not conf.tp or conf.tp == "") and conf.frequency and conf.polarization and conf.symbolrate then
        conf.tp = tostring(conf.frequency) .. ":" .. tostring(conf.polarization) .. ":" .. tostring(conf.symbolrate)
    end
end

function dvb_autosearch_apply_profile(base_cfg, profile)
    local cfg = deep_copy(base_cfg or {})
    profile = type(profile) == "table" and profile or {}
    if profile.adapter ~= nil then cfg.adapter = profile.adapter end
    if profile.device ~= nil then cfg.device = profile.device end
    for _, key in ipairs(DVB_ADAPTER_TUNE_FIELDS) do
        if profile[key] ~= nil then
            cfg[key] = profile[key]
        end
    end
    dvb_autosearch_merge_tp_fields(cfg)
    return cfg
end

function dvb_autosearch_build_candidates(row)
    local cfg = dvb_autosearch_adapter_cfg(row)
    local base = row and row.config or {}
    local busy = dvb_autosearch_adapter_busy_keys()
    local out = {}
    for _, item in ipairs(cfg.candidate_profiles or {}) do
        if type(item) == "table" then
            local key = nil
            if item.adapter ~= nil then
                key = tostring(item.adapter) .. "." .. tostring(item.device or 0)
            end
            if key == nil or busy[key] ~= true then
                local profile = dvb_autosearch_apply_profile(base, item)
                out[#out + 1] = {
                    kind = "profile",
                    name = tostring(item.name or ("adapter " .. tostring(profile.adapter) .. "." .. tostring(profile.device or 0))),
                    cfg = profile,
                }
            end
        end
    end
    return out, cfg
end

function dvb_autosearch_probe(conf, duration, done_cb)
    local input = init_input(conf)
    if not input then
        done_cb({
            ok = false,
            error = "failed to init probe input",
        })
        return
    end
    local job = {
        input = input,
        programs = {},
        services = {},
        channels = {},
        total = { bitrate = 0, cc_errors = 0, pes_errors = 0 },
    }
    job.analyze = analyze({
        upstream = input.tail:stream(),
        name = tostring(conf.name or "dvb-autosearch-probe"),
        join_pid = true,
        callback = function(data)
            if type(data) ~= "table" then
                return
            end
            if data.psi == "pat" then
                dvb_scan_add_pat(job, data)
            elseif data.psi == "pmt" then
                dvb_scan_add_pmt(job, data)
            elseif data.psi == "sdt" then
                dvb_scan_add_sdt(job, data)
            elseif data.analyze and data.total then
                job.total.bitrate = tonumber(data.total.bitrate) or job.total.bitrate
                job.total.cc_errors = tonumber(data.total.cc_errors) or job.total.cc_errors
                job.total.pes_errors = tonumber(data.total.pes_errors) or job.total.pes_errors
            end
        end,
    })

    local finished = false
    local function finalize(result)
        if finished then
            return
        end
        finished = true
        if job.analyze then
            job.analyze = nil
        end
        if job.input then
            kill_input(job.input)
            job.input = nil
        end
        done_cb(result)
    end

    job.timer = timer({
        interval = duration,
        callback = function(self)
            self:close()
            dvb_scan_build_channels(job)
            finalize({
                ok = true,
                channels = job.channels or {},
                bitrate = tonumber(job.total.bitrate) or 0,
                cc_errors = tonumber(job.total.cc_errors) or 0,
                pes_errors = tonumber(job.total.pes_errors) or 0,
            })
        end,
    })
end

local function dvb_autosearch_get_adapter(adapter_id, fallback)
    if not (config and config.get_adapter and adapter_id ~= nil) then
        return fallback
    end
    local ok, row = pcall(config.get_adapter, adapter_id)
    if not ok then
        return fallback
    end
    if row == nil then
        return fallback
    end
    return row
end

function dvb_autosearch_apply_adapter_config(adapter_id, next_cfg)
    local row = dvb_autosearch_get_adapter(adapter_id, nil)
    if not row then
        return nil, "adapter not found"
    end
    local merged_cfg = deep_copy(next_cfg or {})
    local current_cfg = type(row.config) == "table" and row.config or {}
    for key, value in pairs(current_cfg) do
        if tostring(key):match("^auto_signal_") then
            merged_cfg[key] = deep_copy(value)
        end
    end
    local enabled = (tonumber(row.enabled) or 0) ~= 0
    config.upsert_adapter(adapter_id, enabled, merged_cfg)
    if runtime and runtime.refresh_adapters then
        runtime.refresh_adapters(true)
    end
    return row, nil
end

function dvb_autosearch_confirm_degradation(adapter_id, row, opts)
    local degraded, reason, details = dvb_autosearch_degradation(adapter_id, row, opts)
    return degraded == true, reason, details
end

function dvb_autosearch_start_task(task)
    local row = dvb_autosearch_get_adapter(task.adapter_id, nil)
    if not row then
        task.state = "failed"
        task.error = "adapter not found"
        dvb_autosearch_record_attempt(task, false, task.error)
        return
    end
    local candidates, cfg = dvb_autosearch_build_candidates(row)
    if task.type_flip_only == true then
        candidates = {}
    end
    local can_type_flip = false
    if cfg and cfg.allow_type_flip then
        local cur_type = tostring((row.config and row.config.type) or ""):upper()
        can_type_flip = (cur_type == "S2")
    end
    if #candidates == 0 and not can_type_flip then
        task.state = "failed"
        task.error = "no free candidate FE profiles"
        dvb_autosearch_alert("WARNING", "DVB_AUTOSEARCH_NO_FREE_FE",
            "auto signal search skipped: no free FE candidates",
            { adapter_id = task.adapter_id })
        dvb_autosearch_record_attempt(task, false, task.error)
        return
    end
    task.state = "running"
    task.started_at = os.time()
    task.row = row
    task.cfg = cfg
    task.candidates = candidates
    task.candidate_index = 1
    if #candidates == 0 and can_type_flip then
        task.no_candidate_profiles = true
        task.last_error = "no free candidate FE profiles; trying type flip recovery"
        dvb_autosearch_alert("WARNING", "DVB_AUTOSEARCH_NO_FREE_FE",
            "no free FE candidates, trying type flip recovery",
            { adapter_id = task.adapter_id })
    end
end

function dvb_autosearch_step_task(task)
    if not task or task.state ~= "running" then
        return true
    end
    if task.wait_until and os.time() < task.wait_until then
        return false
    end
    if task.phase == "confirm" then
        local still_bad = false
        local reason = "ok"
        local details = {}
        if task.row then
            local confirm_opts = {
                since_ts = task.switch_applied_ts,
            }
            if task.type_flip_only then
                confirm_opts.window_sec = 60
                confirm_opts.cc_threshold = task.cfg and task.cfg.type_flip_cc_threshold or 50
                confirm_opts.pes_threshold = task.cfg and task.cfg.type_flip_pes_threshold or 50
                confirm_opts.cc_pes_only = true
            end
            still_bad, reason, details = dvb_autosearch_confirm_degradation(task.adapter_id, task.row, confirm_opts)
        end
        if still_bad then
            -- rollback and continue next candidate
            if task.prev_cfg then
                pcall(dvb_autosearch_apply_adapter_config, task.adapter_id, task.prev_cfg)
            end
            if task.type_flip_only == true or task.type_flip_tried == true then
                dvb_autosearch_reset_adapter_counters(task.adapter_id)
            end
            task.phase = nil
            task.wait_until = nil
            task.candidate_index = (tonumber(task.candidate_index) or 1) + 1
            task.last_error = "confirm failed: " .. tostring(reason)
            task.last_details = details
            return false
        end

        task.state = "done"
        task.finished_at = os.time()
        if task.type_flip_only == true or task.type_flip_tried == true then
            dvb_autosearch_reset_adapter_counters(task.adapter_id)
        end
        dvb_autosearch_alert("INFO", "DVB_AUTOSEARCH_SWITCH_OK",
            "auto signal search switched adapter successfully",
            { adapter_id = task.adapter_id, candidate = task.applied_candidate and task.applied_candidate.name })
        dvb_autosearch_record_attempt(task, true, "switch-ok", {
            candidate = task.applied_candidate and task.applied_candidate.name,
        })
        local st = dvb_autosearch.adapter_state[task.adapter_id] or {}
        st.last_switch_ts = os.time()
        st.last_ok_ts = os.time()
        st.last_reason = "switch-ok"
        dvb_autosearch.adapter_state[task.adapter_id] = st
        return true
    end

    if task.phase == "type-flip-pre-wait" and task.prev_cfg then
        local flip = deep_copy(task.prev_cfg)
        flip.type = "S"
        local ok_apply_s, switched = pcall(dvb_autosearch_apply_adapter_config, task.adapter_id, flip)
        if not ok_apply_s or switched == nil then
            dvb_autosearch_reset_adapter_counters(task.adapter_id)
            task.state = "failed"
            task.finished_at = os.time()
            task.error = "type-flip apply S failed"
            dvb_autosearch_record_attempt(task, false, task.error)
            return true
        end
        task.phase = "type-flip-return"
        task.wait_until = os.time() + (task.cfg.type_flip_wait_sec or 20)
        return false
    end

    if task.phase == "wait-probe" then
        if task.waiting_probe then
            return false
        end
        local candidate = task.probe_candidate
        local result = task.probe_result
        task.phase = nil
        task.probe_candidate = nil
        task.probe_result = nil
        if not candidate or not result or result.ok ~= true then
            task.candidate_index = (tonumber(task.candidate_index) or 1) + 1
            task.last_error = "probe failed"
            return false
        end
        local has_channels = type(result.channels) == "table" and #result.channels > 0
        local bitrate = tonumber(result.bitrate) or 0
        if (not has_channels) or bitrate < task.cfg.bitrate_min_kbps then
            task.candidate_index = (tonumber(task.candidate_index) or 1) + 1
            task.last_error = "probe criteria not met"
            task.last_details = {
                channels = has_channels and #result.channels or 0,
                bitrate = bitrate,
            }
            return false
        end
        local prev_row = dvb_autosearch_get_adapter(task.adapter_id, nil)
        if not prev_row then
            task.candidate_index = (tonumber(task.candidate_index) or 1) + 1
            task.last_error = "adapter disappeared"
            return false
        end
        task.prev_cfg = deep_copy(prev_row.config or {})
        local next_cfg = dvb_autosearch_apply_profile(prev_row.config or {}, candidate.cfg)
        local ok_apply, prev_row_after = pcall(dvb_autosearch_apply_adapter_config, task.adapter_id, next_cfg)
        if not ok_apply or prev_row_after == nil then
            task.candidate_index = (tonumber(task.candidate_index) or 1) + 1
            task.last_error = "apply candidate failed"
            return false
        end
        task.applied_candidate = candidate
        task.switch_applied_ts = os.time()
        task.phase = "confirm"
        task.wait_until = os.time() + task.cfg.confirm_sec
        return false
    end

    if task.phase == "type-flip-return" and task.prev_cfg then
        local restore = deep_copy(task.prev_cfg)
        restore.type = task.prev_cfg.type or "S2"
        local ok_restore, switched = pcall(dvb_autosearch_apply_adapter_config, task.adapter_id, restore)
        if not ok_restore or switched == nil then
            dvb_autosearch_reset_adapter_counters(task.adapter_id)
            task.state = "failed"
            task.finished_at = os.time()
            task.error = "type-flip restore S2 failed"
            dvb_autosearch_record_attempt(task, false, task.error)
            return true
        end
        task.switch_applied_ts = os.time()
        task.wait_until = os.time() + (task.cfg.type_flip_confirm_sec or 180)
        task.phase = "confirm"
        task.applied_candidate = { name = "type-flip S2->S->S2" }
        return false
    end

    local candidate = task.candidates and task.candidates[task.candidate_index]
    if not candidate then
        -- Last chance recovery: satellite type flip S2 -> S -> S2.
        if task.cfg and task.cfg.allow_type_flip and not task.type_flip_tried then
            local cur_type = tostring((task.row and task.row.config and task.row.config.type) or ""):upper()
            if cur_type == "S2" then
                task.type_flip_tried = true
                local live_row = dvb_autosearch_get_adapter(task.adapter_id, task.row)
                local original = deep_copy((live_row and live_row.config) or task.row.config or {})
                if original and next(original) ~= nil then
                    task.prev_cfg = original
                    task.phase = "type-flip-pre-wait"
                    task.wait_until = os.time() + (task.cfg.type_flip_s2_hold_sec or 10)
                    task.applied_candidate = { name = "type-flip S2->S->S2" }
                    return false
                end
            end
        end

        task.state = "failed"
        task.finished_at = os.time()
        if task.type_flip_only == true or task.type_flip_tried == true then
            dvb_autosearch_reset_adapter_counters(task.adapter_id)
        end
        task.error = task.last_error or "all candidates failed"
        dvb_autosearch_alert("ERROR", "DVB_AUTOSEARCH_SWITCH_FAIL",
            "auto signal search failed to switch adapter",
            { adapter_id = task.adapter_id, error = task.error })
        dvb_autosearch_record_attempt(task, false, task.error, { details = task.last_details })
        return true
    end

    local probe_done = false
    local probe_result = nil
    local probe_conf = dvb_scan_config_from_adapter(task.adapter_id)
    if not probe_conf then
        task.candidate_index = task.candidate_index + 1
        task.last_error = "failed to build probe conf"
        return false
    end
    probe_conf = dvb_autosearch_apply_profile(probe_conf, candidate.cfg)
    probe_conf.name = "dvb-autosearch-probe-" .. tostring(task.adapter_id)
    dvb_autosearch_probe(probe_conf, task.cfg.probe_sec, function(result)
        probe_done = true
        probe_result = result or { ok = false, error = "probe failed" }
    end)
    if not probe_done then
        task.phase = "wait-probe"
        task.waiting_probe = true
        task.probe_candidate = candidate
        task.probe_result = nil
        task.probe_poll = timer({
            interval = 0.2,
            callback = function(self)
                if probe_done then
                    self:close()
                    task.waiting_probe = nil
                    task.probe_result = probe_result
                    task.wait_until = os.time()
                end
            end,
        })
        return false
    end

    local result = task.probe_result or probe_result
    if task.waiting_probe then
        return false
    end
    if not result or result.ok ~= true then
        task.candidate_index = task.candidate_index + 1
        task.last_error = "probe failed"
        return false
    end
    local has_channels = type(result.channels) == "table" and #result.channels > 0
    local bitrate = tonumber(result.bitrate) or 0
    if (not has_channels) or bitrate < task.cfg.bitrate_min_kbps then
        task.candidate_index = task.candidate_index + 1
        task.last_error = "probe criteria not met"
        task.last_details = {
            channels = has_channels and #result.channels or 0,
            bitrate = bitrate,
        }
        return false
    end

    local prev_row = dvb_autosearch_get_adapter(task.adapter_id, nil)
    if not prev_row then
        task.candidate_index = task.candidate_index + 1
        task.last_error = "adapter disappeared"
        return false
    end
    task.prev_cfg = deep_copy(prev_row.config or {})
    local next_cfg = dvb_autosearch_apply_profile(prev_row.config or {}, candidate.cfg)
    local ok_apply, prev_row_after = pcall(dvb_autosearch_apply_adapter_config, task.adapter_id, next_cfg)
    if not ok_apply or prev_row_after == nil then
        task.candidate_index = task.candidate_index + 1
        task.last_error = "apply candidate failed"
        return false
    end
    task.applied_candidate = candidate
    task.switch_applied_ts = os.time()
    task.phase = "confirm"
    task.wait_until = os.time() + task.cfg.confirm_sec
    return false
end

function dvb_autosearch_tick()
    local now = os.time()
    if not dvb_autosearch_enabled() then
        return
    end
    if now < (tonumber(dvb_autosearch.frozen_until_ts) or 0) then
        return
    end
    if not dvb_autosearch_lock_ok() then
        return
    end

    local warmup = clamp_number(setting_number("dvb_autosearch_detection_warmup_sec", 120), 0, 3600) or 120
    local detection_allowed = true
    if runtime and runtime.started_at and (now - runtime.started_at) < warmup then
        detection_allowed = false
    end

    if detection_allowed then
        local snapshot = dvb_autosearch_collect_runtime()
        dvb_autosearch_push_history(snapshot)

        local adapters = config and config.list_adapters and config.list_adapters() or {}
        for _, row in ipairs(adapters) do
            local adapter_id = row and row.id and tostring(row.id) or nil
            if adapter_id then
                local cfg = dvb_autosearch_adapter_cfg(row)
                if cfg.enabled or cfg.allow_type_flip then
                    local state = dvb_autosearch.adapter_state[adapter_id] or {}
                    local cooldown_ok = true
                    if state.last_switch_ts then
                        cooldown_ok = (now - (tonumber(state.last_switch_ts) or 0)) >= cfg.switch_cooldown_sec
                    end
                    if cooldown_ok then
                        local type_flip_only = (cfg.enabled ~= true) and (cfg.allow_type_flip == true)
                        local degraded, reason, details = nil, "ok", {}
                        if type_flip_only then
                            degraded, reason, details = dvb_autosearch_degradation(adapter_id, row, {
                                window_sec = 60,
                                cc_threshold = cfg.type_flip_cc_threshold,
                                pes_threshold = cfg.type_flip_pes_threshold,
                                cc_pes_only = true,
                            })
                        else
                            degraded, reason, details = dvb_autosearch_degradation(adapter_id, row)
                        end
                        if degraded then
                            if not type_flip_only then
                                details.expected_bitrate_kbps = cfg.bitrate_min_kbps
                            end
                            if dvb_autosearch_enqueue(adapter_id, reason, details, { type_flip_only = type_flip_only }) then
                                dvb_autosearch_alert("WARNING", "DVB_AUTOSEARCH_DEGRADED",
                                    "adapter signal degradation detected",
                                    { adapter_id = adapter_id, reason = reason, details = details, type_flip_only = type_flip_only })
                            end
                        end
                    end
                end
            end
        end
    end

    if dvb_autosearch.active and dvb_autosearch.active.state == "running" then
        local active_row = dvb_autosearch_get_adapter(dvb_autosearch.active.adapter_id, nil)
        local active_cfg = active_row and dvb_autosearch_adapter_cfg(active_row) or nil
        local active_allowed = active_cfg and (active_cfg.enabled or active_cfg.allow_type_flip) or false
        local active_type_flip_allowed = active_cfg and active_cfg.allow_type_flip or false
        if (not active_allowed) or (dvb_autosearch.active.type_flip_only == true and not active_type_flip_allowed) then
            dvb_autosearch.active.state = "failed"
            dvb_autosearch.active.finished_at = os.time()
            dvb_autosearch.active.error = "manually disabled"
            dvb_autosearch_record_attempt(dvb_autosearch.active, false, dvb_autosearch.active.error)
            dvb_autosearch.active = nil
            return
        end
        local done = dvb_autosearch_step_task(dvb_autosearch.active)
        if done then
            dvb_autosearch.active = nil
        end
        return
    end
    if dvb_autosearch.active and (dvb_autosearch.active.state == "done" or dvb_autosearch.active.state == "failed") then
        dvb_autosearch.active = nil
    end

    if dvb_full_scan.active_id then
        return
    end

    local min_gap = clamp_number(setting_number("dvb_autosearch_global_switch_min_gap_sec", 20), 1, 600) or 20
    local last_switch = tonumber(dvb_autosearch.adapter_state.__last_global_switch_ts) or 0
    if last_switch > 0 and (now - last_switch) < min_gap then
        return
    end

    local task = dvb_autosearch_dequeue()
    if not task then
        return
    end
    dvb_autosearch.active = task
    dvb_autosearch_start_task(task)
    if task.state == "running" then
        dvb_autosearch.adapter_state.__last_global_switch_ts = now
    else
        dvb_autosearch.active = nil
    end
end

function dvb_autosearch_status_payload()
    local queue = {}
    for _, item in ipairs(dvb_autosearch.queue or {}) do
        queue[#queue + 1] = {
            id = item.id,
            adapter_id = item.adapter_id,
            reason = item.reason,
            score = item.score,
            queued_at = item.queued_at,
            details = item.details,
        }
    end
    table.sort(queue, function(a, b)
        return (tonumber(a.score) or 0) > (tonumber(b.score) or 0)
    end)
    local adapters = {}
    for adapter_id, state in pairs(dvb_autosearch.adapter_state or {}) do
        if adapter_id ~= "__last_global_switch_ts" then
            adapters[#adapters + 1] = {
                adapter_id = adapter_id,
                last_switch_ts = state.last_switch_ts,
                last_ok_ts = state.last_ok_ts,
                last_reason = state.last_reason,
                last_enqueue_ts = state.last_enqueue_ts,
                last_enqueue_reason = state.last_enqueue_reason,
                last_enqueue_blocked_ts = state.last_enqueue_blocked_ts,
            }
        end
    end
    table.sort(adapters, function(a, b) return tostring(a.adapter_id) < tostring(b.adapter_id) end)
    return {
        enabled = dvb_autosearch_enabled(),
        coordinator_leader = dvb_autosearch_is_leader(),
        lock_owner = dvb_autosearch.lock_owner,
        lock_ts = dvb_autosearch.lock_ts,
        queue_depth = #queue,
        queue = queue,
        active_task = dvb_autosearch.active,
        frozen_until_ts = dvb_autosearch.frozen_until_ts,
        recent_attempts = dvb_autosearch.recent_attempts,
        adapters = adapters,
    }
end

local function get_dvb_autosearch_status(server, client, request)
    if not require_admin(request) then
        return error_response(server, client, 403, "forbidden")
    end
    -- Safety fallback: process one scheduler step on demand.
    -- This keeps auto-search/type-flip operational even if periodic timer is delayed.
    local ok, err = pcall(dvb_autosearch_tick)
    if not ok then
        log.warning("[dvb-autosearch] on-demand status tick failed: " .. tostring(err))
    end
    return json_response(server, client, 200, dvb_autosearch_status_payload())
end

local function trigger_dvb_autosearch(server, client, request)
    if not require_admin(request) then
        return error_response(server, client, 403, "forbidden")
    end
    local body = parse_json_body(request) or {}
    local adapter_id = tostring(body.adapter_id or "")
    local dry_run = normalize_bool(body.dry_run, false)
    if adapter_id == "" then
        return error_response(server, client, 400, "adapter_id is required")
    end
    local row = dvb_autosearch_get_adapter(adapter_id, nil)
    if not row then
        return error_response(server, client, 404, "adapter not found")
    end
    local cfg = dvb_autosearch_adapter_cfg(row)
    local type_flip_only = (cfg.enabled ~= true) and (cfg.allow_type_flip == true)
    local degraded, reason, details = nil, "ok", {}
    if type_flip_only then
        degraded, reason, details = dvb_autosearch_degradation(adapter_id, row, {
            window_sec = 60,
            cc_threshold = cfg.type_flip_cc_threshold,
            pes_threshold = cfg.type_flip_pes_threshold,
            cc_pes_only = true,
        })
    else
        degraded, reason, details = dvb_autosearch_degradation(adapter_id, row)
    end
    if dry_run then
        return json_response(server, client, 200, {
            status = "dry-run",
            adapter_id = adapter_id,
            degraded = degraded,
            reason = reason,
            details = details,
            type_flip_only = type_flip_only,
        })
    end
    local queued = dvb_autosearch_enqueue(adapter_id, reason, details, {
        force = true,
        type_flip_only = type_flip_only,
    })
    if queued then
        -- Start processing immediately for manual trigger UX.
        local ok_tick, err_tick = pcall(dvb_autosearch_tick)
        if not ok_tick then
            log.warning("[dvb-autosearch] on-demand trigger tick failed: " .. tostring(err_tick))
        end
    end
    return json_response(server, client, 200, {
        status = queued and "queued" or "already_queued",
        adapter_id = adapter_id,
        degraded = degraded,
        reason = reason,
        details = details,
        type_flip_only = type_flip_only,
    })
end

local function clear_dvb_autosearch_queue(server, client, request)
    if not require_admin(request) then
        return error_response(server, client, 403, "forbidden")
    end
    dvb_autosearch.queue = {}
    dvb_autosearch.queue_index = {}
    return json_response(server, client, 200, { status = "ok" })
end

local function unfreeze_dvb_autosearch(server, client, request)
    if not require_admin(request) then
        return error_response(server, client, 403, "forbidden")
    end
    dvb_autosearch.frozen_until_ts = 0
    return json_response(server, client, 200, { status = "ok" })
end

function dvb_scan_presets_default()
    return {
        version = "builtin-1",
        source_url = "builtin",
        satellites = {
            { id = "sat_13e", name = "13E", transponders = {} },
            { id = "sat_19e", name = "19E", transponders = {} },
            { id = "sat_42e", name = "42E", transponders = {} },
            { id = "sat_53e", name = "53E", transponders = {} },
            { id = "sat_36e", name = "36E", transponders = {} },
            { id = "sat_75e", name = "75E", transponders = {} },
            { id = "sat_80e", name = "80E", transponders = {} },
            { id = "sat_16e", name = "16E", transponders = {} },
            { id = "sat_5e", name = "5E", transponders = {} },
        },
        cable = {
            { id = "dvb_c_8mhz", name = "DVB-C 8MHz", step_mhz = 8, frequencies = {} },
        },
        terrestrial = {
            { id = "dvb_t_8mhz", name = "DVB-T/T2 8MHz", step_mhz = 8, frequencies = {} },
        },
    }
end

function dvb_scan_presets_validate(payload)
    if type(payload) ~= "table" then
        return nil, "invalid presets payload"
    end
    local out = {
        version = tostring(payload.version or ""),
        source_url = tostring(payload.source_url or ""),
        satellites = type(payload.satellites) == "table" and payload.satellites or {},
        cable = type(payload.cable) == "table" and payload.cable or {},
        terrestrial = type(payload.terrestrial) == "table" and payload.terrestrial or {},
    }
    if out.version == "" then
        out.version = "unknown"
    end
    return out
end

function dvb_scan_presets_load_cached()
    local row = db_query_safe("SELECT version, source_url, fetched_ts, payload_json FROM dvb_scan_presets_cache WHERE key='default' LIMIT 1;")
    if not row or #row == 0 then
        return nil
    end
    local data = nil
    local ok = pcall(function()
        data = json.decode(row[1].payload_json or "{}")
    end)
    if not ok or type(data) ~= "table" then
        return nil
    end
    local validated = dvb_scan_presets_validate(data)
    if not validated then
        return nil
    end
    validated.fetched_ts = tonumber(row[1].fetched_ts) or 0
    validated.source_url = tostring(row[1].source_url or validated.source_url or "")
    validated.version = tostring(row[1].version or validated.version or "unknown")
    return validated
end

function dvb_scan_presets_store(payload, source_url)
    local valid, err = dvb_scan_presets_validate(payload)
    if not valid then
        return nil, err
    end
    local ts = os.time()
    local json_payload = json.encode(valid)
    local sql = "INSERT OR REPLACE INTO dvb_scan_presets_cache(key, version, source_url, fetched_ts, payload_json) VALUES(" ..
        "'default', '" .. sql_escape(valid.version) .. "', '" .. sql_escape(source_url or valid.source_url or "") .. "', " ..
        tostring(ts) .. ", '" .. sql_escape(json_payload) .. "');"
    local ok, exec_err = db_exec_safe(sql)
    if not ok then
        return nil, exec_err
    end
    valid.fetched_ts = ts
    valid.source_url = source_url or valid.source_url
    return valid, nil
end

function dvb_scan_presets_get_effective()
    local cached = dvb_scan_presets_load_cached()
    if cached then
        return cached
    end
    local defaults = dvb_scan_presets_default()
    local stored = dvb_scan_presets_store(defaults, "builtin")
    return stored or defaults
end

function dvb_scan_presets_refresh(server, client, request)
    if not require_admin(request) then
        return error_response(server, client, 403, "forbidden")
    end
    local url = setting_string("dvb_scan_presets_url", "https://stream.centv.ru/dvb-presets.json")
    local cmd = "curl -fsSL " .. shell_escape(url)
    local output, err = run_command(cmd, 20)
    if not output or output == "" then
        dvb_autosearch_alert("WARNING", "DVB_FULLSCAN_PRESET_SOURCE_DOWN",
            "dvb scan presets source unavailable; cache/manual mode active",
            { source = url, error = err })
        return error_response(server, client, 502, "failed to download presets")
    end
    local ok, parsed = pcall(json.decode, output)
    if not ok then
        return error_response(server, client, 502, "invalid presets json")
    end
    local saved, save_err = dvb_scan_presets_store(parsed, url)
    if not saved then
        return error_response(server, client, 502, save_err or "failed to store presets")
    end
    return json_response(server, client, 200, saved)
end

local function get_dvb_scan_presets(server, client, request)
    if not require_admin(request) then
        return error_response(server, client, 403, "forbidden")
    end
    return json_response(server, client, 200, dvb_scan_presets_get_effective())
end

local function set_dvb_scan_presets_manual(server, client, request)
    if not require_admin(request) then
        return error_response(server, client, 403, "forbidden")
    end
    local body = parse_json_body(request) or {}
    local payload = body.payload or body
    if type(payload) == "string" and payload ~= "" then
        local ok_decode, parsed = pcall(json.decode, payload)
        if not ok_decode or type(parsed) ~= "table" then
            return error_response(server, client, 400, "invalid presets payload")
        end
        payload = parsed
    end
    if type(payload) ~= "table" then
        return error_response(server, client, 400, "invalid presets payload")
    end
    local source = tostring(body.source_url or body.source or "manual")
    if source == "" then
        source = "manual"
    end
    local saved, save_err = dvb_scan_presets_store(payload, source)
    if not saved then
        return error_response(server, client, 400, save_err or "failed to store presets")
    end
    return json_response(server, client, 200, saved)
end

function dvb_full_scan_cleanup_memory()
    local now = os.time()
    for id, job in pairs(dvb_full_scan.jobs or {}) do
        if job and job.status ~= "running" and (now - (tonumber(job.finished_ts) or now)) > 1800 then
            dvb_full_scan.jobs[id] = nil
        end
    end
end

function dvb_full_scan_update_job_db(job)
    local sql = "UPDATE dvb_scan_jobs SET status='" .. sql_escape(job.status or "") ..
        "', finished_ts=" .. tostring(tonumber(job.finished_ts) or 0) ..
        ", progress=" .. tostring(tonumber(job.progress) or 0) ..
        ", total_steps=" .. tostring(tonumber(job.total_steps) or 0) ..
        ", error_text='" .. sql_escape(job.error_text or "") .. "'" ..
        " WHERE id='" .. sql_escape(job.id) .. "';"
    db_exec_safe(sql)
end

function dvb_full_scan_insert_grid(job, step_no, step, probe)
    local status = runtime and runtime.get_adapter_status and runtime.get_adapter_status(job.adapter_id) or nil
    local channels_count = type(probe.channels) == "table" and #probe.channels or 0
    local sql = "INSERT INTO dvb_scan_grid(job_id, step_no, frequency, tp, status, signal, snr, ber, unc, bitrate_kbps, channels_count, ts, meta_json) VALUES(" ..
        "'" .. sql_escape(job.id) .. "', " .. tostring(step_no) .. ", " ..
        tostring(tonumber(step.frequency) or "NULL") .. ", '" .. sql_escape(step.tp or "") .. "', '" ..
        sql_escape((probe.ok and "done") or "error") .. "', " ..
        tostring(tonumber(status and status.signal) or "NULL") .. ", " ..
        tostring(tonumber(status and status.snr) or "NULL") .. ", " ..
        tostring(tonumber(status and status.ber) or "NULL") .. ", " ..
        tostring(tonumber(status and status.unc) or "NULL") .. ", " ..
        tostring(tonumber(probe.bitrate) or 0) .. ", " ..
        tostring(channels_count) .. ", " .. tostring(os.time()) .. ", '" ..
        sql_escape(json.encode({
            adapter = step.adapter,
            device = step.device,
            type = step.type,
        })) .. "');"
    db_exec_safe(sql)
end

function dvb_full_scan_insert_channels(job, step_no, step, channels)
    if type(channels) ~= "table" then
        return
    end
    local max_rows = clamp_number(setting_number("dvb_scan_rows_max_per_job", 50000), 100, 500000) or 50000
    local current = tonumber(db_scalar_safe("SELECT COUNT(*) FROM dvb_scan_channels WHERE job_id='" ..
        sql_escape(job.id) .. "';")) or 0
    for _, channel in ipairs(channels) do
        if current >= max_rows then
            break
        end
        local sql = "INSERT INTO dvb_scan_channels(job_id, step_no, pnr, name, provider, cas_json, video_json, audio_json, frequency, tp, meta_json) VALUES(" ..
            "'" .. sql_escape(job.id) .. "', " .. tostring(step_no) .. ", " .. tostring(tonumber(channel.pnr) or "NULL") .. ", '" ..
            sql_escape(channel.name or "") .. "', '" .. sql_escape(channel.provider or "") .. "', '" ..
            sql_escape(json.encode(channel.cas or {})) .. "', '" ..
            sql_escape(json.encode(channel.video or {})) .. "', '" ..
            sql_escape(json.encode(channel.audio or {})) .. "', " ..
            tostring(tonumber(step.frequency) or "NULL") .. ", '" .. sql_escape(step.tp or "") .. "', '" ..
            sql_escape(json.encode({
                adapter = step.adapter,
                device = step.device,
            })) .. "');"
        db_exec_safe(sql)
        current = current + 1
    end
end

function dvb_full_scan_finish(job, status, err)
    job.status = status
    job.error_text = err
    job.finished_ts = os.time()
    dvb_full_scan.active_id = nil
    dvb_full_scan_update_job_db(job)
    dvb_full_scan_cleanup_memory()
end

function dvb_full_scan_run_step(job)
    if not job or job.status ~= "running" then
        return
    end
    if job.cancel_requested then
        dvb_full_scan_finish(job, "cancelled", "")
        return
    end
    local step_no = (tonumber(job.progress) or 0) + 1
    local step = job.plan and job.plan[step_no]
    if not step then
        dvb_full_scan_finish(job, "done", "")
        return
    end
    local conf = dvb_autosearch_apply_profile(job.base_conf, step)
    conf.name = "dvb-full-scan-" .. tostring(job.id) .. "-" .. tostring(step_no)
    dvb_autosearch_probe(conf, job.step_duration_sec, function(probe)
        dvb_full_scan_insert_grid(job, step_no, step, probe or { ok = false })
        dvb_full_scan_insert_channels(job, step_no, step, probe and probe.channels or {})
        job.progress = step_no
        dvb_full_scan_update_job_db(job)
        timer({
            interval = 0.1,
            callback = function(self)
                self:close()
                dvb_full_scan_run_step(job)
            end,
        })
    end)
end

function dvb_flatten_profiles(presets, group_key)
    local list = {}
    local src = presets and presets[group_key]
    if type(src) ~= "table" then
        return list
    end
    for _, item in ipairs(src) do
        if type(item) == "table" then
            list[#list + 1] = item
        end
    end
    return list
end

function dvb_plan_from_profile(row, body)
    local presets = dvb_scan_presets_get_effective()
    local cfg = row and row.config or {}
    local type_name = tostring(cfg.type or ""):upper()
    local group_key = "satellites"
    if type_name:find("^C") then
        group_key = "cable"
    elseif type_name:find("^T") or type_name == "ATSC" then
        group_key = "terrestrial"
    end
    local profile_id = tostring(body.profile_id or "")
    local profiles = dvb_flatten_profiles(presets, group_key)
    local selected = nil
    if profile_id ~= "" then
        for _, item in ipairs(profiles) do
            if tostring(item.id or "") == profile_id then
                selected = item
                break
            end
        end
    else
        selected = profiles[1]
    end
    if not selected then
        return nil, "profile not found"
    end
    local plan = {}
    if type(selected.transponders) == "table" and #selected.transponders > 0 then
        for _, tp in ipairs(selected.transponders) do
            if type(tp) == "table" then
                local step = deep_copy(tp)
                step.tp = step.tp or ((step.frequency and step.polarization and step.symbolrate)
                    and (tostring(step.frequency) .. ":" .. tostring(step.polarization) .. ":" .. tostring(step.symbolrate)) or nil)
                plan[#plan + 1] = step
            end
        end
    elseif type(selected.frequencies) == "table" and #selected.frequencies > 0 then
        for _, freq in ipairs(selected.frequencies) do
            plan[#plan + 1] = {
                frequency = tonumber(freq),
                symbolrate = tonumber(selected.symbolrate),
                modulation = selected.modulation,
                bandwidth = selected.bandwidth,
            }
        end
    end
    return plan, nil
end

function dvb_plan_from_custom(row, body)
    local custom = type(body.custom) == "table" and body.custom or {}
    local cfg = row and row.config or {}
    local type_name = tostring(custom.type or cfg.type or "S2"):upper()
    local from = tonumber(custom.frequency_from)
    local to = tonumber(custom.frequency_to)
    local step = tonumber(custom.step)
    if type_name:find("^C") or type_name:find("^T") then
        if step == nil then
            step = 8000
        end
    elseif step == nil then
        step = 1000
    end
    if not from or not to or not step or step <= 0 then
        return nil, "custom scan requires frequency_from/frequency_to/step"
    end
    if from > to then
        from, to = to, from
    end
    local plan = {}
    local max_steps = clamp_number(setting_number("dvb_scan_max_steps", 20000), 10, 200000) or 20000
    local symbolrates = {}
    if type(custom.symbolrates) == "table" then
        for _, sr in ipairs(custom.symbolrates) do
            local n = tonumber(sr)
            if n and n > 0 then
                symbolrates[#symbolrates + 1] = n
            end
        end
    end
    if #symbolrates == 0 and tonumber(custom.symbolrate) then
        symbolrates[1] = tonumber(custom.symbolrate)
    end
    local pols = {}
    if type(custom.polarizations) == "table" then
        for _, p in ipairs(custom.polarizations) do
            local t = tostring(p or ""):upper()
            if t ~= "" then
                pols[#pols + 1] = t
            end
        end
    end
    if #pols == 0 then
        pols = { "H", "V" }
    end

    local freq = from
    while freq <= to do
        if type_name:find("^S") then
            local sr_list = (#symbolrates > 0) and symbolrates or { tonumber(cfg.symbolrate) or 27500 }
            for _, sr in ipairs(sr_list) do
                for _, pol in ipairs(pols) do
                    plan[#plan + 1] = {
                        type = type_name,
                        frequency = math.floor(freq),
                        polarization = pol,
                        symbolrate = sr,
                        tp = tostring(math.floor(freq)) .. ":" .. tostring(pol) .. ":" .. tostring(sr),
                        modulation = custom.modulation or cfg.modulation,
                    }
                    if #plan > max_steps then
                        return nil, "scan plan too large"
                    end
                end
            end
        else
            plan[#plan + 1] = {
                type = type_name,
                frequency = math.floor(freq),
                symbolrate = tonumber(custom.symbolrate) or tonumber(cfg.symbolrate),
                bandwidth = tonumber(custom.bandwidth) or tonumber(cfg.bandwidth),
                modulation = custom.modulation or cfg.modulation,
            }
            if #plan > max_steps then
                return nil, "scan plan too large"
            end
        end
        freq = freq + step
    end
    return plan, nil
end

local function start_dvb_full_scan(server, client, request)
    if not require_admin(request) then
        return error_response(server, client, 403, "forbidden")
    end
    if not analyze then
        return error_response(server, client, 501, "analyze module is not found")
    end
    local body = parse_json_body(request) or {}
    local adapter_id = tostring(body.adapter_id or "")
    if adapter_id == "" then
        return error_response(server, client, 400, "adapter_id is required")
    end
    if dvb_full_scan.active_id then
        return error_response(server, client, 409, "another full scan is running")
    end
    local row = dvb_autosearch_get_adapter(adapter_id, nil)
    if not row then
        return error_response(server, client, 404, "adapter not found")
    end
    local mode = tostring(body.mode or "profile")
    local plan = nil
    local err = nil
    if mode == "custom" then
        plan, err = dvb_plan_from_custom(row, body)
    else
        plan, err = dvb_plan_from_profile(row, body)
    end
    if not plan then
        return error_response(server, client, 400, err or "failed to build scan plan")
    end
    if #plan == 0 then
        return error_response(server, client, 400, "scan plan is empty")
    end

    dvb_full_scan.seq = dvb_full_scan.seq + 1
    local id = tostring(dvb_full_scan.seq)
    local step_duration = clamp_number(body.step_duration_sec, 1, 15) or 3
    local base_conf, conf_err = dvb_scan_config_from_adapter(adapter_id)
    if not base_conf then
        return error_response(server, client, 400, conf_err or "invalid adapter config")
    end
    local job = {
        id = id,
        adapter_id = adapter_id,
        status = "running",
        started_ts = os.time(),
        finished_ts = 0,
        progress = 0,
        total_steps = #plan,
        mode = mode,
        step_duration_sec = step_duration,
        base_conf = base_conf,
        plan = plan,
    }
    local sql = "INSERT INTO dvb_scan_jobs(id, adapter_id, mode, status, started_ts, finished_ts, progress, total_steps, params_json, error_text) VALUES(" ..
        "'" .. sql_escape(job.id) .. "', '" .. sql_escape(job.adapter_id) .. "', '" .. sql_escape(job.mode) .. "', 'running', " ..
        tostring(job.started_ts) .. ", 0, 0, " .. tostring(job.total_steps) .. ", '" ..
        sql_escape(json.encode({
            mode = mode,
            profile_id = body.profile_id,
            custom = body.custom,
        })) .. "', '');"
    local ok, exec_err = db_exec_safe(sql)
    if not ok then
        return error_response(server, client, 500, "failed to create scan job: " .. tostring(exec_err))
    end

    db_exec_safe("DELETE FROM dvb_scan_grid WHERE job_id='" .. sql_escape(job.id) .. "';")
    db_exec_safe("DELETE FROM dvb_scan_channels WHERE job_id='" .. sql_escape(job.id) .. "';")

    dvb_full_scan.jobs[id] = job
    dvb_full_scan.active_id = id
    dvb_full_scan_run_step(job)
    return json_response(server, client, 200, {
        id = id,
        status = job.status,
        adapter_id = adapter_id,
        progress = job.progress,
        total_steps = job.total_steps,
    })
end

function dvb_full_scan_query_paging(query)
    query = query or {}
    local page = clamp_number(query.page, 1, 100000) or 1
    local per_page = clamp_number(query.per_page, 10, 500) or 100
    local offset = (page - 1) * per_page
    return page, per_page, offset
end

function dvb_full_scan_load_job(id)
    local job = dvb_full_scan.jobs[id]
    if job then
        return job
    end
    local rows, err = db_query_safe("SELECT * FROM dvb_scan_jobs WHERE id='" .. sql_escape(id) .. "' LIMIT 1;")
    if not rows then
        return nil, err
    end
    if #rows == 0 then
        return nil, "job not found"
    end
    local row = rows[1]
    return {
        id = tostring(row.id or ""),
        adapter_id = tostring(row.adapter_id or ""),
        mode = tostring(row.mode or ""),
        status = tostring(row.status or ""),
        started_ts = tonumber(row.started_ts) or 0,
        finished_ts = tonumber(row.finished_ts) or 0,
        progress = tonumber(row.progress) or 0,
        total_steps = tonumber(row.total_steps) or 0,
        error_text = row.error_text,
    }, nil
end

local function get_dvb_full_scan(server, client, request, id)
    if not require_admin(request) then
        return error_response(server, client, 403, "forbidden")
    end
    local job, err = dvb_full_scan_load_job(id)
    if not job then
        return error_response(server, client, 404, err or "job not found")
    end
    local query = request and request.query or {}
    local page, per_page, offset = dvb_full_scan_query_paging(query)

    local grid_sort = tostring(query.grid_sort or "step_no")
    local grid_order = tostring(query.grid_order or "asc"):lower() == "desc" and "DESC" or "ASC"
    local grid_sort_whitelist = {
        step_no = true,
        frequency = true,
        bitrate_kbps = true,
        channels_count = true,
        ts = true,
    }
    if not grid_sort_whitelist[grid_sort] then
        grid_sort = "step_no"
    end
    local grid_rows = db_query_safe("SELECT * FROM dvb_scan_grid WHERE job_id='" .. sql_escape(id) ..
        "' ORDER BY " .. grid_sort .. " " .. grid_order .. " LIMIT " .. tostring(per_page) ..
        " OFFSET " .. tostring(offset) .. ";") or {}
    local grid_total = tonumber(db_scalar_safe("SELECT COUNT(*) FROM dvb_scan_grid WHERE job_id='" ..
        sql_escape(id) .. "';")) or 0

    local channels_sort = tostring(query.channels_sort or "pnr")
    local channels_order = tostring(query.channels_order or "asc"):lower() == "desc" and "DESC" or "ASC"
    local channels_sort_whitelist = {
        pnr = true,
        name = true,
        provider = true,
        frequency = true,
    }
    if not channels_sort_whitelist[channels_sort] then
        channels_sort = "pnr"
    end
    local channels_rows = db_query_safe("SELECT * FROM dvb_scan_channels WHERE job_id='" .. sql_escape(id) ..
        "' ORDER BY " .. channels_sort .. " " .. channels_order .. " LIMIT " .. tostring(per_page) ..
        " OFFSET " .. tostring(offset) .. ";") or {}
    local channels_total = tonumber(db_scalar_safe("SELECT COUNT(*) FROM dvb_scan_channels WHERE job_id='" ..
        sql_escape(id) .. "';")) or 0

    return json_response(server, client, 200, {
        job = job,
        progress = {
            done = job.progress,
            total = job.total_steps,
            pct = job.total_steps > 0 and math.floor((job.progress / job.total_steps) * 100) or 0,
        },
        grid_page = {
            page = page,
            per_page = per_page,
            total = grid_total,
            items = grid_rows,
        },
        channels_page = {
            page = page,
            per_page = per_page,
            total = channels_total,
            items = channels_rows,
        },
    })
end

local function cancel_dvb_full_scan(server, client, request, id)
    if not require_admin(request) then
        return error_response(server, client, 403, "forbidden")
    end
    local job = dvb_full_scan.jobs[id]
    if not job then
        return error_response(server, client, 404, "job not found")
    end
    job.cancel_requested = true
    return json_response(server, client, 200, { status = "cancel_requested", id = id })
end

local function export_dvb_full_scan(server, client, request, id)
    if not require_admin(request) then
        return error_response(server, client, 403, "forbidden")
    end
    local query = request and request.query or {}
    local format = tostring(query.format or "json")
    local grid_rows = db_query_safe("SELECT * FROM dvb_scan_grid WHERE job_id='" .. sql_escape(id) .. "' ORDER BY step_no ASC;") or {}
    local channels_rows = db_query_safe("SELECT * FROM dvb_scan_channels WHERE job_id='" .. sql_escape(id) .. "' ORDER BY pnr ASC;") or {}
    if format == "csv" then
        local lines = { "type,step_no,pnr,name,provider,frequency,tp,bitrate_kbps,channels_count,status" }
        for _, row in ipairs(grid_rows) do
            lines[#lines + 1] = table.concat({
                "grid",
                tostring(row.step_no or ""),
                "",
                "",
                "",
                tostring(row.frequency or ""),
                tostring(row.tp or ""),
                tostring(row.bitrate_kbps or ""),
                tostring(row.channels_count or ""),
                tostring(row.status or ""),
            }, ",")
        end
        for _, row in ipairs(channels_rows) do
            lines[#lines + 1] = table.concat({
                "channel",
                tostring(row.step_no or ""),
                tostring(row.pnr or ""),
                tostring(row.name or ""):gsub(",", " "),
                tostring(row.provider or ""):gsub(",", " "),
                tostring(row.frequency or ""),
                tostring(row.tp or ""),
                "",
                "",
                "",
            }, ",")
        end
        return server:send(client, {
            code = 200,
            headers = {
                "Content-Type: text/csv",
                "Cache-Control: no-cache",
                "Connection: close",
            },
            content = table.concat(lines, "\n"),
        })
    end
    return json_response(server, client, 200, {
        id = id,
        grid = grid_rows,
        channels = channels_rows,
    })
end

local function slugify_stream_id(name)
    local text = tostring(name or ""):lower()
    text = text:gsub("[^%w_%-]+", "_")
    text = text:gsub("_+", "_")
    text = text:gsub("^_+", "")
    text = text:gsub("_+$", "")
    if text == "" then
        text = "dvb_stream"
    end
    return text
end

local function create_streams_from_dvb_full_scan(server, client, request, id)
    if not require_admin(request) then
        return error_response(server, client, 403, "forbidden")
    end
    local body = parse_json_body(request) or {}
    local selected = type(body.selected) == "table" and body.selected or {}
    if #selected == 0 then
        return error_response(server, client, 400, "selected list is empty")
    end
    local job, err = dvb_full_scan_load_job(id)
    if not job then
        return error_response(server, client, 404, err or "job not found")
    end
    local ids = {}
    for _, value in ipairs(selected) do
        local n = tonumber(value)
        if n then
            ids[#ids + 1] = tostring(math.floor(n))
        end
    end
    if #ids == 0 then
        return error_response(server, client, 400, "selected list must contain channel row ids")
    end
    local rows = db_query_safe("SELECT id, pnr, name FROM dvb_scan_channels WHERE job_id='" .. sql_escape(id) ..
        "' AND id IN (" .. table.concat(ids, ",") .. ");") or {}
    if #rows == 0 then
        return error_response(server, client, 404, "selected channels not found")
    end
    local created = {}
    local skipped = {}
    for _, row in ipairs(rows) do
        local pnr = tonumber(row.pnr)
        if pnr then
            local base_id = slugify_stream_id(row.name or ("pnr_" .. tostring(pnr)))
            local stream_id = base_id
            local idx = 2
            while config.get_stream(stream_id) do
                stream_id = base_id .. "_" .. tostring(idx)
                idx = idx + 1
            end
            local payload = {
                name = row.name or ("PNR " .. tostring(pnr)),
                type = "spts",
                input = { "dvb://" .. tostring(job.adapter_id) .. "#pnr=" .. tostring(pnr) },
                output = {},
            }
            if config.get_stream(stream_id) then
                skipped[#skipped + 1] = stream_id
            else
                config.upsert_stream(stream_id, true, payload)
                created[#created + 1] = stream_id
            end
        end
    end
    if runtime and runtime.refresh then
        pcall(runtime.refresh, false)
    end
    return json_response(server, client, 200, {
        status = "ok",
        created = created,
        skipped = skipped,
    })
end

local function get_adapter_status(server, client, id)
    local status = runtime and runtime.get_adapter_status and runtime.get_adapter_status(id)
    if not status then
        return error_response(server, client, 404, "adapter status not found")
    end
    json_response(server, client, 200, status)
end

local stream_status_cache = {
    full = { ts = 0, payload = nil },
    lite = { ts = 0, payload = nil },
}

local function sharding_master_enabled()
    return sharding
        and type(sharding.is_active) == "function"
        and type(sharding.is_master) == "function"
        and sharding.is_active()
        and sharding.is_master()
end

local function sharding_port_for_stream_id(stream_id)
    if not stream_id or stream_id == "" then
        return nil
    end
    if not sharding or type(sharding.get_stream_shard_port) ~= "function" then
        return nil
    end
    return sharding.get_stream_shard_port(stream_id)
end

local function proxy_api_request(server, client, request, target_port, path_override)
    if not http_request then
        return error_response(server, client, 500, "http_request unavailable")
    end
    if not request then
        return error_response(server, client, 400, "request required")
    end

    local method = request.method or "GET"
    local path = path_override or (request.path or "/")
    local body = request.content or ""
    if method == "GET" or method == "HEAD" then
        body = ""
    elseif method == "POST" and body == "" then
        body = "{}"
    end
    local content_type = get_header(request.headers, "content-type") or "application/json"

    local extra = {}
    if body ~= "" then
        extra[#extra + 1] = "Content-Type: " .. tostring(content_type)
        extra[#extra + 1] = "Content-Length: " .. tostring(#body)
    end

    local headers = sharding.forward_auth_headers and sharding.forward_auth_headers(request, target_port, extra)
        or {
            "Host: 127.0.0.1:" .. tostring(target_port),
            "Connection: close",
            extra[1],
            extra[2],
        }

    local req_opts = {
        host = "127.0.0.1",
        port = target_port,
        path = path,
        method = method,
        headers = headers,
        connect_timeout_ms = 200,
        read_timeout_ms = 800,
        callback = function(self, response)
            if not response then
                return error_response(server, client, 503, "shard unavailable")
            end
            local code = tonumber(response.code) or 0
            if code <= 0 then
                return error_response(server, client, 503, tostring(response.message or "shard error"))
            end
            local resp_headers = response.headers or {}
            local resp_type = resp_headers["content-type"] or resp_headers["Content-Type"] or "application/json"
            server:send(client, {
                code = code,
                headers = {
                    "Content-Type: " .. tostring(resp_type),
                    "Cache-Control: no-cache",
                    "Connection: close",
                },
                content = response.content or "",
            })
        end,
    }
    if body ~= "" then
        req_opts.content = body
    end

    local ok, err = pcall(http_request, req_opts)
    if not ok then
        return error_response(server, client, 503, "shard request failed: " .. tostring(err))
    end
    return nil
end

local function query_truthy(value)
    if value == true then
        return true
    end
    if value == nil then
        return false
    end
    local s = tostring(value):lower()
    return s == "1" or s == "true" or s == "yes" or s == "on"
end

local function parse_stream_status_ids(raw)
    if raw == nil then
        return nil
    end
    local text = tostring(raw or "")
    if text == "" then
        return nil
    end
    local ids = {}
    local seen = {}
    for token in string.gmatch(text, "[^,]+") do
        local id = tostring(token or ""):gsub("^%s+", ""):gsub("%s+$", "")
        if id ~= "" and not seen[id] then
            ids[#ids + 1] = id
            seen[id] = true
            if #ids >= 256 then
                break
            end
        end
    end
    if #ids == 0 then
        return nil
    end
    return ids
end

local function build_stream_status_path(lite, ids)
    local params = {}
    if lite then
        params[#params + 1] = "lite=1"
    end
    if type(ids) == "table" and #ids > 0 then
        params[#params + 1] = "ids=" .. table.concat(ids, ",")
    end
    if #params == 0 then
        return "/api/v1/stream-status"
    end
    return "/api/v1/stream-status?" .. table.concat(params, "&")
end

local function collect_runtime_stream_status(lite, ids)
    local function merge_dvr_status(target, source)
        if type(target) ~= "table" or type(source) ~= "table" then
            return
        end
        for sid, row in pairs(source) do
            if type(row) == "table" then
                if type(target[sid]) ~= "table" then
                    target[sid] = row
                else
                    local merged = target[sid]
                    if merged.on_air == nil then
                        merged.on_air = row.on_air
                    end
                    if merged.bitrate == nil then
                        merged.bitrate = row.bitrate
                    end
                    if merged.bitrate_kbps == nil then
                        merged.bitrate_kbps = row.bitrate_kbps or row.bitrate
                    end
                    if merged.raw_bitrate_kbps == nil then
                        merged.raw_bitrate_kbps = row.raw_bitrate_kbps or row.bitrate_kbps or row.bitrate
                    end
                    if merged.cc_errors == nil then
                        merged.cc_errors = row.cc_errors
                    end
                    if merged.pes_errors == nil then
                        merged.pes_errors = row.pes_errors
                    end
                    if merged.active_input_id == nil then
                        merged.active_input_id = row.active_input_id
                    end
                    if merged.active_input_index == nil then
                        merged.active_input_index = row.active_input_index
                    end
                    if merged.active_input_url == nil then
                        merged.active_input_url = row.active_input_url
                    end
                    if merged.last_error == nil or tostring(merged.last_error or "") == "" then
                        merged.last_error = row.last_error
                    end
                    if merged.uptime_sec == nil then
                        merged.uptime_sec = row.uptime_sec
                    end
                    if merged.updated_at == nil then
                        merged.updated_at = row.updated_at
                    end
                end
            end
        end
    end

    local function get_dvr_runtime(ids_filter)
        if not (dvr_store and type(dvr_store.list_runtime_status) == "function") then
            return {}
        end
        local ok, rows = pcall(dvr_store.list_runtime_status, ids_filter)
        if not ok or type(rows) ~= "table" then
            return {}
        end
        return rows
    end

    if type(ids) == "table" and #ids > 0 then
        local status = {}
        if lite and runtime.list_status_lite_ids then
            status = runtime.list_status_lite_ids(ids) or {}
        elseif (not lite) and runtime.list_status_ids then
            status = runtime.list_status_ids(ids) or {}
        else
            for _, sid in ipairs(ids) do
                local id = tostring(sid or "")
                if id ~= "" then
                    local entry = nil
                    if lite and runtime.get_stream_status_lite then
                        entry = runtime.get_stream_status_lite(id)
                    elseif runtime.get_stream_status then
                        entry = runtime.get_stream_status(id)
                    end
                    if entry then
                        status[id] = entry
                    end
                end
            end
        end
        merge_dvr_status(status, get_dvr_runtime(ids))
        return status
    end

    local status = {}
    if lite and runtime.list_status_lite then
        status = runtime.list_status_lite() or {}
    elseif runtime.list_status then
        status = runtime.list_status() or {}
    end
    merge_dvr_status(status, get_dvr_runtime(nil))
    return status
end

local function list_stream_status(server, client, request)
    local now = os.time()
    local query = request and request.query or {}
    local lite = query_truthy(query and query.lite)
    local ids = parse_stream_status_ids(query and query.ids)
    local ids_requested = type(ids) == "table" and #ids > 0
    local cache_key = lite and "lite" or "full"
    local cache = stream_status_cache[cache_key] or { ts = 0, payload = nil }

    if (not ids_requested) and cache.payload and (now - (cache.ts or 0)) <= 1 then
        return json_response(server, client, 200, cache.payload)
    end

    -- Sharding master aggregates status from all shard processes.
    if sharding_master_enabled() and sharding and type(sharding.get_cluster_ports) == "function" then
        local merged = {}
        local ports = sharding.get_cluster_ports() or {}
        local local_port = tonumber(config and config.get_setting and config.get_setting("http_port") or 0) or 0
        local base_port = sharding.get_base_port and sharding.get_base_port() or nil

        local shard_ids = nil
        local local_ids = nil
        if ids_requested then
            shard_ids = {}
            local_ids = {}
            for _, sid in ipairs(ids) do
                local stream_id = tostring(sid or "")
                if stream_id ~= "" then
                    local port = sharding_port_for_stream_id(stream_id) or local_port
                    if port == local_port then
                        local_ids[#local_ids + 1] = stream_id
                    else
                        if not shard_ids[port] then
                            shard_ids[port] = {}
                        end
                        shard_ids[port][#shard_ids[port] + 1] = stream_id
                    end
                end
            end
            if #local_ids == 0 then
                local_ids = nil
            end
        end

        -- Local shard data (avoid self-http recursion).
        local local_status = collect_runtime_stream_status(lite, local_ids)
        for id, entry in pairs(local_status) do
            if type(entry) == "table" then
                entry.shard_port = local_port
                entry.shard_index = sharding.get_shard_index and sharding.get_shard_index() or 0
            end
            merged[id] = entry
        end

        local pending = 0
        local done = false

        local function finish()
            if done then
                return
            end
            done = true
            if not ids_requested then
                stream_status_cache[cache_key] = { ts = now, payload = merged }
            end
            json_response(server, client, 200, merged)
        end

        local function on_shard_response(port, payload)
            if type(payload) == "table" then
                local idx = nil
                if base_port and port then
                    idx = tonumber(port) - tonumber(base_port)
                end
                for id, entry in pairs(payload) do
                    if type(entry) == "table" then
                        entry.shard_port = port
                        entry.shard_index = idx
                    end
                    merged[id] = entry
                end
            end
            pending = pending - 1
            if pending <= 0 then
                finish()
            end
        end

        local function request_port(port, ids_for_port)
            if port == local_port then
                return
            end
            pending = pending + 1
            local path = build_stream_status_path(lite, ids_for_port)
            local headers = sharding.forward_auth_headers and sharding.forward_auth_headers(request, port) or {
                "Host: 127.0.0.1:" .. tostring(port),
                "Connection: close",
            }
            local ok, _req = pcall(http_request, {
                host = "127.0.0.1",
                port = port,
                path = path,
                method = "GET",
                headers = headers,
                connect_timeout_ms = 200,
                read_timeout_ms = 800,
                callback = function(self, response)
                    if not response or tonumber(response.code) ~= 200 then
                        return on_shard_response(port, nil)
                    end
                    local ok_decode, decoded = pcall(json.decode, response.content or "")
                    if not ok_decode then
                        return on_shard_response(port, nil)
                    end
                    on_shard_response(port, decoded)
                end,
            })
            if not ok then
                on_shard_response(port, nil)
            end
        end

        if ids_requested then
            for port, ids_for_port in pairs(shard_ids or {}) do
                request_port(port, ids_for_port)
            end
        else
            for _, port in ipairs(ports) do
                request_port(port, nil)
            end
        end

        if pending <= 0 then
            finish()
        end
        return nil
    end

    local status = collect_runtime_stream_status(lite, ids)
    if not ids_requested then
        stream_status_cache[cache_key] = { ts = now, payload = status }
    end
    json_response(server, client, 200, status)
end

local function get_stream_status(server, client, request, id)
    local query = request and request.query or {}
    local lite = query_truthy(query and query.lite)
    local status = nil
    if lite and runtime.get_stream_status_lite then
        status = runtime.get_stream_status_lite(id)
    elseif runtime.get_stream_status then
        status = runtime.get_stream_status(id)
    end
    if not status then
        if dvr_store and type(dvr_store.get_runtime_status) == "function" then
            local ok_dvr, dvr_status = pcall(dvr_store.get_runtime_status, id)
            if ok_dvr and type(dvr_status) == "table" then
                status = dvr_status
            end
        end
    end
    if not status then
        -- If requested on the master shard, proxy to the owning shard.
        if sharding_master_enabled() then
            local port = sharding_port_for_stream_id(tostring(id))
            local local_port = tonumber(config and config.get_setting and config.get_setting("http_port") or 0) or 0
            if port and port ~= local_port then
                local path = "/api/v1/stream-status/" .. tostring(id)
                if lite then
                    path = path .. "?lite=1"
                end
                local headers = sharding.forward_auth_headers and sharding.forward_auth_headers(request, port) or {
                    "Host: 127.0.0.1:" .. tostring(port),
                    "Connection: close",
                }
                local ok, err = pcall(http_request, {
                    host = "127.0.0.1",
                    port = port,
                    path = path,
                    method = "GET",
                    headers = headers,
                    connect_timeout_ms = 200,
                    read_timeout_ms = 800,
                    callback = function(self, response)
                        if not response or tonumber(response.code) ~= 200 then
                            return error_response(server, client, 404, "stream not found")
                        end
                        local ok2, entry = pcall(json.decode, response.content or "")
                        if not ok2 or type(entry) ~= "table" then
                            return error_response(server, client, 503, "shard decode failed")
                        end
                        if type(entry) == "table" then
                            entry.shard_port = port
                            local base = sharding.get_base_port and sharding.get_base_port() or nil
                            if base then
                                entry.shard_index = tonumber(port) - tonumber(base)
                            end
                        end
                        json_response(server, client, 200, entry)
                    end,
                })
                if not ok then
                    return error_response(server, client, 503, "shard request failed: " .. tostring(err))
                end
                return nil
            end
        end
        return error_response(server, client, 404, "stream not found")
    end
    json_response(server, client, 200, status)
end

local function get_stream_cam_stats(server, client, request, id)
    local entry = runtime and runtime.streams and runtime.streams[tostring(id)] or nil
    if not entry or entry.kind ~= "stream" or not entry.channel then
        if sharding_master_enabled() then
            local port = sharding_port_for_stream_id(tostring(id))
            local local_port = tonumber(config and config.get_setting and config.get_setting("http_port") or 0) or 0
            if port and port ~= local_port then
                return proxy_api_request(server, client, request, port, "/api/v1/streams/" .. tostring(id) .. "/cam-stats")
            end
        end
        return error_response(server, client, 404, "stream not found")
    end

    local channel = entry.channel
    local active_id = tonumber(channel.active_input_id or 0) or 0

    local inputs = {}
    for input_id, input_data in ipairs(channel.input or {}) do
        local item = {
            input_id = input_id,
            active = (active_id == input_id),
            name = input_data.config and input_data.config.name or nil,
            format = input_data.config and input_data.config.format or nil,
        }

        local input = input_data.input
        -- Best-effort: expose which softcam id is attached to this input (if any).
        local softcam_id = nil
        if input and input.__softcam_id then
            softcam_id = tostring(input.__softcam_id)
        else
            local cam_cfg = input_data.config and input_data.config.cam or nil
            if type(cam_cfg) == "string" or type(cam_cfg) == "number" then
                softcam_id = tostring(cam_cfg)
            elseif type(cam_cfg) == "table" then
                local opts = cam_cfg.__options or {}
                if opts.id then
                    softcam_id = tostring(opts.id)
                end
            end
        end
        if softcam_id and softcam_id ~= "" then
            item.softcam_id = softcam_id
        end

        -- Best-effort: backup softcam id (dual-CAM redundancy).
        local softcam_backup_id = nil
        if input and input.__softcam_backup_id then
            softcam_backup_id = tostring(input.__softcam_backup_id)
        else
            local cam_cfg = input_data.config and input_data.config.cam_backup or nil
            if type(cam_cfg) == "string" or type(cam_cfg) == "number" then
                softcam_backup_id = tostring(cam_cfg)
            elseif type(cam_cfg) == "table" then
                local opts = cam_cfg.__options or {}
                if opts.id then
                    softcam_backup_id = tostring(opts.id)
                end
            end
        end
        if softcam_backup_id and softcam_backup_id ~= "" then
            item.softcam_backup_id = softcam_backup_id
        end

        local decrypt = input and input.decrypt or nil
        if decrypt and decrypt.stats then
            local ok, data = pcall(function()
                return decrypt:stats()
            end)
            if ok then
                item.decrypt = data
            else
                item.decrypt_error = tostring(data)
            end
        end

        -- CAM connection stats (if the softcam module supports it, e.g. newcamd:stats()).
        local cam = nil
        if input and type(input.__softcam_clone) == "table" and input.__softcam_clone.stats then
            cam = input.__softcam_clone
        elseif input and type(input.__softcam_instance) == "table" and input.__softcam_instance.stats then
            cam = input.__softcam_instance
        elseif softcam_id then
            local shared = _G[tostring(softcam_id)]
            if type(shared) == "table" and shared.stats then
                cam = shared
            elseif type(softcam_list) == "table" then
                for _, entry in ipairs(softcam_list) do
                    if type(entry) == "table" and entry.stats and entry.__options and tostring(entry.__options.id) == tostring(softcam_id) then
                        cam = entry
                        break
                    end
                end
            end
        end
        if cam and cam.stats then
            local ok, data = pcall(function()
                return cam:stats()
            end)
            if ok then
                if type(cam) == "table" and type(cam.__options) == "table" then
                    local opts = cam.__options
                    if opts.pool_index ~= nil then
                        data.pool_index = tonumber(opts.pool_index) or opts.pool_index
                    end
                    if opts.pool_size ~= nil then
                        data.pool_size = tonumber(opts.pool_size) or opts.pool_size
                    end
                end
                item.cam = data
            else
                item.cam_error = tostring(data)
            end
        end

        -- Backup CAM connection stats (dual-CAM redundancy).
        local cam_backup = nil
        if input and type(input.__softcam_backup_clone) == "table" and input.__softcam_backup_clone.stats then
            cam_backup = input.__softcam_backup_clone
        elseif input and type(input.__softcam_backup_instance) == "table" and input.__softcam_backup_instance.stats then
            cam_backup = input.__softcam_backup_instance
        elseif softcam_backup_id then
            local shared = _G[tostring(softcam_backup_id)]
            if type(shared) == "table" and shared.stats then
                cam_backup = shared
            elseif type(softcam_list) == "table" then
                for _, entry in ipairs(softcam_list) do
                    if type(entry) == "table" and entry.stats and entry.__options and tostring(entry.__options.id) == tostring(softcam_backup_id) then
                        cam_backup = entry
                        break
                    end
                end
            end
        end
        if cam_backup and cam_backup.stats then
            local ok, data = pcall(function()
                return cam_backup:stats()
            end)
            if ok then
                if type(cam_backup) == "table" and type(cam_backup.__options) == "table" then
                    local opts = cam_backup.__options
                    if opts.pool_index ~= nil then
                        data.pool_index = tonumber(opts.pool_index) or opts.pool_index
                    end
                    if opts.pool_size ~= nil then
                        data.pool_size = tonumber(opts.pool_size) or opts.pool_size
                    end
                end
                item.cam_backup = data
            else
                item.cam_backup_error = tostring(data)
            end
        end

        inputs[#inputs + 1] = item
    end

    json_response(server, client, 200, {
        stream_id = tostring(id),
        active_input_id = active_id,
        inputs = inputs,
    })
end

local function list_sessions(server, client, request)
    local query = request and request.query or {}
    local mode = query.type or query.kind
    if mode and tostring(mode) == "auth" then
        local sessions = auth and auth.list_sessions and auth.list_sessions(query) or {}
        return json_response(server, client, 200, sessions)
    end
    local stream_filter = tostring(query.stream_id or query.stream or ""):lower()
    local login_filter = tostring(query.login or ""):lower()
    local ip_filter = tostring(query.ip or ""):lower()
    local text_filter = tostring(query.text or ""):lower()
    local raw_limit = query.limit and tonumber(query.limit) or nil
    local raw_offset = query.offset and tonumber(query.offset) or nil
    local use_paging = raw_limit ~= nil or raw_offset ~= nil
    local limit = raw_limit and math.max(1, math.min(raw_limit, 1000)) or 200
    local offset = raw_offset and math.max(0, raw_offset) or 0
    local sessions = runtime.list_sessions and runtime.list_sessions() or {}
    local filtered = {}

    local function matches_text(value, needle)
        if not needle or needle == "" then
            return true
        end
        if not value then
            return false
        end
        return tostring(value):lower():find(needle, 1, true) ~= nil
    end

    for _, session in ipairs(sessions) do
        if stream_filter ~= "" then
            local stream_ok = matches_text(session.stream_id, stream_filter)
            if not stream_ok then
                stream_ok = matches_text(session.stream_name, stream_filter)
            end
            if not stream_ok then
                goto continue
            end
        end
        if login_filter ~= "" and not matches_text(session.login, login_filter) then
            goto continue
        end
        if ip_filter ~= "" and not matches_text(session.ip, ip_filter) then
            goto continue
        end
        if text_filter ~= "" then
            local hay = table.concat({
                session.server or "",
                session.stream_name or "",
                session.stream_id or "",
                session.ip or "",
                session.login or "",
                session.user_agent or "",
            }, " ")
            if not matches_text(hay, text_filter) then
                goto continue
            end
        end
        table.insert(filtered, session)
        ::continue::
    end

    if use_paging then
        local slice = {}
        local last = math.min(#filtered, offset + limit)
        for idx = offset + 1, last do
            table.insert(slice, filtered[idx])
        end
        filtered = slice
    end

    json_response(server, client, 200, filtered)
end

local function auth_debug_session(server, client, request)
    if not require_admin(request) then
        return error_response(server, client, 403, "forbidden")
    end
    if not auth or not auth.debug_session then
        return error_response(server, client, 404, "auth module not available")
    end
    local query = request and request.query or {}
    local stream_id = query.stream_id or query.stream
    if not stream_id or stream_id == "" then
        return error_response(server, client, 400, "stream_id required")
    end
    local stream = config.get_stream and config.get_stream(stream_id)
    if not stream then
        return error_response(server, client, 404, "stream not found")
    end
    local result, err = auth.debug_session({
        stream_id = stream_id,
        stream_cfg = stream.config or {},
        ip = query.ip or (request and request.addr) or "",
        proto = query.proto or "hls",
        token = query.token or "",
    })
    if not result then
        return error_response(server, client, 400, err or "invalid request")
    end
    json_response(server, client, 200, result)
end

local function delete_session(server, client, id)
    if not (runtime.close_session and runtime.close_session(id)) then
        return error_response(server, client, 404, "session not found")
    end
    json_response(server, client, 200, { status = "ok" })
end

local function list_logs(server, client, request)
    local query = request and request.query or {}
    local since = tonumber(query.since) or 0
    local limit = tonumber(query.limit) or 200
    local level = query.level
    local text = query.text
    local stream_id = query.stream_id or query.stream
    local entries = log_store and log_store.list and log_store.list(since, limit, level, text, stream_id) or {}
    local next_id = (log_store and log_store.next_id) or 1
    json_response(server, client, 200, { entries = entries, next_id = next_id })
end

local function list_access_log(server, client, request)
    local query = request and request.query or {}
    local since = tonumber(query.since) or 0
    local limit = tonumber(query.limit) or 200
    local event = query.event
    local stream_id = query.stream_id or query.stream
    local ip = query.ip
    local login = query.login
    local text = query.text
    local entries = access_log and access_log.list and access_log.list(
        since,
        limit,
        event,
        stream_id,
        ip,
        login,
        text
    ) or {}
    local next_id = (access_log and access_log.next_id) or 1
    json_response(server, client, 200, { entries = entries, next_id = next_id })
end

local function list_alerts(server, client, request)
    local query = request and request.query or {}
    local code_prefix = nil
    if query.type and tostring(query.type) == "auth" then
        code_prefix = "AUTH_"
    end
    local rows = config.list_alerts and config.list_alerts({
        since = query.since,
        limit = query.limit,
        stream_id = query.stream_id,
        code = query.code,
        code_prefix = code_prefix,
    }) or {}
    json_response(server, client, 200, rows)
end

local function list_tools(server, client)
    if transcode and transcode.get_tool_info then
        local info = transcode.get_tool_info(true) or {}
        info.build_transcode = astra and astra.features and astra.features.transcode == true
        info.build_variant = info.build_transcode and "full" or "lite"
        return json_response(server, client, 200, info)
    end
    return json_response(server, client, 200, {
        build_transcode = astra and astra.features and astra.features.transcode == true,
        build_variant = (astra and astra.features and astra.features.transcode == true) and "full" or "lite",
    })
end

local function list_metrics(server, client, request)
    local now = os.time()
    local started_at = (runtime and runtime.started_at) or now
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

    local status = runtime and runtime.list_status and runtime.list_status() or {}
    local on_air = 0
    for _, entry in pairs(status) do
        if entry and entry.on_air == true then
            on_air = on_air + 1
        end
    end

    local transcode_enabled = 0
    if runtime and runtime.streams then
        for _, entry in pairs(runtime.streams) do
            if entry and entry.kind == "transcode" then
                transcode_enabled = transcode_enabled + 1
            end
        end
    end

    local adapter_with_status = 0
    if runtime and runtime.list_adapter_status then
        local adapter_status = runtime.list_adapter_status()
        for _, entry in pairs(adapter_status) do
            if entry and entry.updated_at then
                adapter_with_status = adapter_with_status + 1
            end
        end
    end

    local sessions_active = 0
    if runtime and runtime.list_sessions then
        local sessions = runtime.list_sessions()
        sessions_active = #sessions
    end
    local auth_sessions = (config and config.count_sessions) and config.count_sessions() or 0
    local lua_mem_kb = nil
    if collectgarbage then
        lua_mem_kb = math.floor(collectgarbage("count") + 0.5)
    end
    local perf = (runtime and runtime.perf) or {}
    local dataplane_engine = nil
    if type(udp_relay) == "table" and type(udp_relay.engine_stats) == "function" then
        local ok, st = pcall(function()
            return udp_relay.engine_stats()
        end)
        if ok and type(st) == "table" then
            dataplane_engine = st
        end
    end

    local mpts_metrics = nil
    for id, entry in pairs(status) do
        if entry and entry.mpts_stats then
            if not mpts_metrics then
                mpts_metrics = {}
            end
            mpts_metrics[id] = entry.mpts_stats
        end
    end

    local payload = {
        ts = now,
        version = astra and astra.version or "",
        uptime_sec = uptime,
        streams = {
            total = stream_counts.total,
            enabled = stream_counts.enabled,
            disabled = stream_counts.disabled,
            on_air = on_air,
            transcode_enabled = transcode_enabled,
        },
        adapters = {
            total = adapter_counts.total,
            enabled = adapter_counts.enabled,
            disabled = adapter_counts.disabled,
            with_status = adapter_with_status,
        },
        sessions = {
            auth = auth_sessions,
            clients = sessions_active,
        },
        lua_mem_kb = lua_mem_kb,
        perf = {
            refresh_ms = perf.last_refresh_ms,
            refresh_ts = perf.last_refresh_ts,
            status_ms = perf.last_status_ms,
            status_ts = perf.last_status_ts,
            status_one_ms = perf.last_status_one_ms,
            status_one_ts = perf.last_status_one_ts,
            adapter_refresh_ms = perf.last_adapter_refresh_ms,
            adapter_refresh_ts = perf.last_adapter_refresh_ts,
        },
    }
    payload.http_api = api_http_metrics_snapshot(API_HTTP_METRIC_ROUTE_LIMIT)
    if dataplane_engine then
        payload.dataplane = {
            engine = dataplane_engine,
        }
    end
    if mpts_metrics then
        payload.mpts = mpts_metrics
    end

    local format = ""
    if request and request.query and request.query.format then
        format = tostring(request.query.format):lower()
    end
    if format == "prometheus" or format == "prom" then
        local lines = {
            "stream_uptime_seconds " .. tostring(payload.uptime_sec or 0),
            "stream_streams_total " .. tostring(payload.streams.total or 0),
            "stream_streams_enabled " .. tostring(payload.streams.enabled or 0),
            "stream_streams_disabled " .. tostring(payload.streams.disabled or 0),
            "stream_streams_on_air " .. tostring(payload.streams.on_air or 0),
            "stream_streams_transcode_enabled " .. tostring(payload.streams.transcode_enabled or 0),
            "stream_adapters_total " .. tostring(payload.adapters.total or 0),
            "stream_adapters_enabled " .. tostring(payload.adapters.enabled or 0),
            "stream_adapters_disabled " .. tostring(payload.adapters.disabled or 0),
            "stream_adapters_with_status " .. tostring(payload.adapters.with_status or 0),
            "stream_sessions_auth " .. tostring(payload.sessions.auth or 0),
            "stream_sessions_clients " .. tostring(payload.sessions.clients or 0),
        }
        if payload.http_api and payload.http_api.totals then
            local http_totals = payload.http_api.totals
            table.insert(lines, "stream_api_requests_total " .. tostring(http_totals.requests or 0))
            table.insert(lines, "stream_api_errors_total " .. tostring(http_totals.errors or 0))
            table.insert(lines, "stream_api_rps " .. tostring(http_totals.rps or 0))
            local auth_codes = http_totals.auth_codes or {}
            table.insert(lines, "stream_api_status_401_total " .. tostring(auth_codes[401] or 0))
            table.insert(lines, "stream_api_status_403_total " .. tostring(auth_codes[403] or 0))
            table.insert(lines, "stream_api_status_302_total " .. tostring(auth_codes[302] or 0))
        end
        if lua_mem_kb then
            table.insert(lines, "stream_lua_mem_kb " .. tostring(lua_mem_kb))
        end
        if perf.last_refresh_ms then
            table.insert(lines, "stream_perf_refresh_ms " .. tostring(perf.last_refresh_ms))
        end
        if perf.last_status_ms then
            table.insert(lines, "stream_perf_status_ms " .. tostring(perf.last_status_ms))
        end
        if perf.last_status_one_ms then
            table.insert(lines, "stream_perf_status_one_ms " .. tostring(perf.last_status_one_ms))
        end
        if perf.last_adapter_refresh_ms then
            table.insert(lines, "stream_perf_adapter_refresh_ms " .. tostring(perf.last_adapter_refresh_ms))
        end
        if dataplane_engine then
            table.insert(lines, "stream_dataplane_workers_count " .. tostring(dataplane_engine.workers_count or 0))
            table.insert(lines, "stream_dataplane_sendmmsg_available " .. tostring((dataplane_engine.sendmmsg_available == true) and 1 or 0))
            if type(dataplane_engine.workers) == "table" then
                for _, w in ipairs(dataplane_engine.workers) do
                    local widx = tonumber(w.index) or 0
                    local label = string.format("{worker=\"%d\"}", widx)
                    table.insert(lines, "stream_dataplane_worker_active_streams" .. label .. " " .. tostring(w.active_streams or 0))
                    if w.pinned_cpu ~= nil then
                        table.insert(lines, "stream_dataplane_worker_pinned_cpu" .. label .. " " .. tostring(w.pinned_cpu))
                    end
                end
            end
        end
        if mpts_metrics then
            for stream_id, stats in pairs(mpts_metrics) do
                local label = string.format("{stream_id=\"%s\"}", tostring(stream_id):gsub("\"", "\\\""))
                if stats.bitrate_bps then
                    table.insert(lines, "stream_mpts_bitrate_bps" .. label .. " " .. tostring(stats.bitrate_bps))
                end
                if stats.null_percent then
                    table.insert(lines, "stream_mpts_null_percent" .. label .. " " .. tostring(stats.null_percent))
                end
                if stats.psi_interval_ms then
                    table.insert(lines, "stream_mpts_psi_interval_ms" .. label .. " " .. tostring(stats.psi_interval_ms))
                end
            end
        end
        server:send(client, {
            code = 200,
            headers = {
                "Content-Type: text/plain; version=0.0.4",
                "Cache-Control: no-cache",
                "Connection: close",
            },
            content = table.concat(lines, "\n") .. "\n",
        })
        return
    end

    json_response(server, client, 200, payload)
end

local function list_http_api_metrics(server, client, request)
    local admin = require_admin(request)
    if not admin then
        return error_response(server, client, 403, "forbidden")
    end
    local query = request and request.query or {}
    local limit = tonumber(query.limit) or API_HTTP_METRIC_ROUTE_LIMIT
    json_response(server, client, 200, api_http_metrics_snapshot(limit))
end

local function health_summary(server, client)
    local counts = nil
    if config and config.count_streams then
        counts = config.count_streams()
    end
    local uptime = runtime and runtime.started_at and (os.time() - runtime.started_at) or 0
    local refresh_ok = runtime and runtime.last_refresh_ok ~= false
    json_response(server, client, 200, {
        ok = refresh_ok and config and config.db ~= nil,
        db_ok = config and config.db ~= nil,
        http_ok = true,
        streams_loaded = counts and counts.enabled or 0,
        streams_total = counts and counts.total or 0,
        uptime_sec = uptime,
        last_refresh_ok = refresh_ok,
        last_refresh_errors = runtime and runtime.last_refresh_errors or {},
    })
end

local function health_process(server, client)
    local now = os.time()
    local started_at = (runtime and runtime.started_at) or now
    local uptime = math.max(0, now - started_at)
    json_response(server, client, 200, {
        status = "ok",
        ts = now,
        version = astra and astra.version or "",
        started_at = started_at,
        uptime_sec = uptime,
    })
end

local function health_inputs(server, client)
    local now = os.time()
    local status = runtime and runtime.list_status and runtime.list_status() or {}
    local summary = {
        streams_total = 0,
        streams_with_inputs = 0,
        streams_without_inputs = 0,
        streams_all_down = 0,
    }
    local inputs = {
        total = 0,
        active = 0,
        standby = 0,
        down = 0,
        probing = 0,
        unknown = 0,
    }
    local unhealthy = {}

    for id, entry in pairs(status) do
        if entry.inputs then
            summary.streams_total = summary.streams_total + 1
            local list = entry.inputs or {}
            local total = #list
            if total == 0 then
                summary.streams_without_inputs = summary.streams_without_inputs + 1
                table.insert(unhealthy, {
                    id = id,
                    name = (runtime.streams[id]
                        and runtime.streams[id].channel
                        and runtime.streams[id].channel.config
                        and runtime.streams[id].channel.config.name)
                        or id,
                    active_input_index = entry.active_input_index,
                    reason = "no_inputs",
                })
            else
                summary.streams_with_inputs = summary.streams_with_inputs + 1
                local ok_inputs = 0
                local down_inputs = 0
                for _, input in ipairs(list) do
                    local state = input.state
                    if not state then
                        if input.on_air == true then
                            if input.active == true then
                                state = "ACTIVE"
                            else
                                state = "STANDBY"
                            end
                        else
                            state = "DOWN"
                        end
                    end
                    inputs.total = inputs.total + 1
                    if state == "ACTIVE" then
                        inputs.active = inputs.active + 1
                        ok_inputs = ok_inputs + 1
                    elseif state == "STANDBY" then
                        inputs.standby = inputs.standby + 1
                        ok_inputs = ok_inputs + 1
                    elseif state == "PROBING" then
                        inputs.probing = inputs.probing + 1
                    elseif state == "DOWN" then
                        inputs.down = inputs.down + 1
                        down_inputs = down_inputs + 1
                    else
                        inputs.unknown = inputs.unknown + 1
                    end
                end
                if ok_inputs == 0 then
                    summary.streams_all_down = summary.streams_all_down + 1
                    table.insert(unhealthy, {
                        id = id,
                        name = (runtime.streams[id]
                            and runtime.streams[id].channel
                            and runtime.streams[id].channel.config
                            and runtime.streams[id].channel.config.name)
                            or id,
                        active_input_index = entry.active_input_index,
                        inputs_total = total,
                        inputs_down = down_inputs,
                        reason = "all_down",
                    })
                end
            end
        end
    end

    json_response(server, client, 200, {
        ts = now,
        streams = summary,
        inputs = inputs,
        unhealthy_streams = unhealthy,
    })
end

local function health_outputs(server, client)
    local now = os.time()
    local status = runtime and runtime.list_status and runtime.list_status() or {}
    local total = 0
    local on_air = 0
    local down = 0
    local unhealthy = {}

    for id, entry in pairs(status) do
        total = total + 1
        local ok = entry.on_air == true
        if entry.transcode_state then
            ok = entry.transcode_state == "RUNNING"
        end
        if ok then
            on_air = on_air + 1
        else
            down = down + 1
            table.insert(unhealthy, {
                id = id,
                name = (runtime.streams[id]
                    and runtime.streams[id].channel
                    and runtime.streams[id].channel.config
                    and runtime.streams[id].channel.config.name)
                    or id,
                state = entry.transcode_state or (entry.on_air == true and "RUNNING" or "DOWN"),
            })
        end
    end

    json_response(server, client, 200, {
        ts = now,
        streams = {
            total = total,
            on_air = on_air,
            down = down,
        },
        unhealthy_streams = unhealthy,
    })
end

local function list_audit_events(server, client, request)
    if not require_admin(request) then
        return error_response(server, client, 403, "forbidden")
    end
    local query = request and request.query or {}
    local rows = config.list_audit_events and config.list_audit_events({
        since = query.since,
        limit = query.limit,
        action = query.action,
        actor = query.actor,
        target = query.target,
        ip = query.ip,
        ok = query.ok,
    }) or {}
    json_response(server, client, 200, rows)
end

local function list_transcode_status(server, client, request)
    if not transcode_supported() then
        return error_response(server, client, 501, "transcode disabled in this build")
    end
    -- Sharding master aggregates transcode status from all shard processes.
    if sharding_master_enabled() and sharding and type(sharding.get_cluster_ports) == "function" and http_request then
        local merged = {}
        local ports = sharding.get_cluster_ports() or {}
        local local_port = tonumber(config and config.get_setting and config.get_setting("http_port") or 0) or 0
        local base_port = sharding.get_base_port and sharding.get_base_port() or nil

        local local_status = runtime.list_transcode_status and runtime.list_transcode_status() or {}
        for id, entry in pairs(local_status) do
            if type(entry) == "table" then
                entry.shard_port = local_port
                entry.shard_index = sharding.get_shard_index and sharding.get_shard_index() or 0
            end
            merged[id] = entry
        end

        local pending = 0
        local done = false

        local function finish()
            if done then
                return
            end
            done = true
            json_response(server, client, 200, merged)
        end

        local function on_shard_response(port, payload)
            if type(payload) == "table" then
                local idx = nil
                if base_port and port then
                    idx = tonumber(port) - tonumber(base_port)
                end
                for id, entry in pairs(payload) do
                    if type(entry) == "table" then
                        entry.shard_port = port
                        entry.shard_index = idx
                    end
                    merged[id] = entry
                end
            end
            pending = pending - 1
            if pending <= 0 then
                finish()
            end
        end

        for _, port in ipairs(ports) do
            if port ~= local_port then
                pending = pending + 1
                local headers = sharding.forward_auth_headers and sharding.forward_auth_headers(request, port) or {
                    "Host: 127.0.0.1:" .. tostring(port),
                    "Connection: close",
                }
                local ok, _req = pcall(http_request, {
                    host = "127.0.0.1",
                    port = port,
                    path = "/api/v1/transcode-status",
                    method = "GET",
                    headers = headers,
                    connect_timeout_ms = 200,
                    read_timeout_ms = 800,
                    callback = function(self, response)
                        if not response or tonumber(response.code) ~= 200 then
                            return on_shard_response(port, nil)
                        end
                        local ok, decoded = pcall(json.decode, response.content or "")
                        if not ok then
                            return on_shard_response(port, nil)
                        end
                        on_shard_response(port, decoded)
                    end,
                })
                if not ok then
                    on_shard_response(port, nil)
                end
            end
        end

        if pending <= 0 then
            finish()
        end
        return nil
    end

    local status = runtime.list_transcode_status and runtime.list_transcode_status() or {}
    json_response(server, client, 200, status)
end

local function get_transcode_status(server, client, request, id)
    if not transcode_supported() then
        return error_response(server, client, 501, "transcode disabled in this build")
    end
    local status = runtime.get_transcode_status and runtime.get_transcode_status(id)
    if not status then
        if sharding_master_enabled() then
            local port = sharding_port_for_stream_id(tostring(id))
            local local_port = tonumber(config and config.get_setting and config.get_setting("http_port") or 0) or 0
            if port and port ~= local_port then
                local headers = sharding.forward_auth_headers and sharding.forward_auth_headers(request, port) or {
                    "Host: 127.0.0.1:" .. tostring(port),
                    "Connection: close",
                }
                local ok, err = pcall(http_request, {
                    host = "127.0.0.1",
                    port = port,
                    path = "/api/v1/transcode-status",
                    method = "GET",
                    headers = headers,
                    connect_timeout_ms = 200,
                    read_timeout_ms = 800,
                    callback = function(self, response)
                        if not response or tonumber(response.code) ~= 200 then
                            return error_response(server, client, 404, "transcode not found")
                        end
                        local ok2, payload = pcall(json.decode, response.content or "")
                        if not ok2 or type(payload) ~= "table" then
                            return error_response(server, client, 503, "shard decode failed")
                        end
                        local entry = payload[tostring(id)]
                        if not entry then
                            return error_response(server, client, 404, "transcode not found")
                        end
                        if type(entry) == "table" then
                            entry.shard_port = port
                            local base = sharding.get_base_port and sharding.get_base_port() or nil
                            if base then
                                entry.shard_index = tonumber(port) - tonumber(base)
                            end
                        end
                        json_response(server, client, 200, entry)
                    end,
                })
                if not ok then
                    return error_response(server, client, 503, "shard request failed: " .. tostring(err))
                end
                return nil
            end
        end
        return error_response(server, client, 404, "transcode not found")
    end
    json_response(server, client, 200, status)
end

local function restart_transcode(server, client, request, id)
    if not transcode_supported() then
        return error_response(server, client, 501, "transcode disabled in this build")
    end
    local ok = runtime.restart_transcode and runtime.restart_transcode(id)
    if not ok then
        if sharding_master_enabled() then
            local port = sharding_port_for_stream_id(tostring(id))
            local local_port = tonumber(config and config.get_setting and config.get_setting("http_port") or 0) or 0
            if port and port ~= local_port then
                return proxy_api_request(server, client, request, port, "/api/v1/transcode/" .. tostring(id) .. "/restart")
            end
        end
        return error_response(server, client, 404, "transcode not found")
    end
    json_response(server, client, 200, { status = "restarting" })
end

local function switch_stream_input(server, client, request, id)
    local body = parse_json_body(request)
    if not body then
        return error_response(server, client, 400, "invalid json")
    end
    local raw_index = body.input_index
    local input_index = tonumber(raw_index)
    if input_index == nil then
        return error_response(server, client, 400, "input_index is required")
    end
    input_index = math.floor(input_index)
    if input_index < 0 then
        return error_response(server, client, 400, "input_index must be >= 0")
    end

    local ok, err = nil, nil
    if runtime and runtime.switch_stream_input then
        ok, err = runtime.switch_stream_input(id, input_index)
    else
        ok, err = false, "switch input unsupported"
    end
    if not ok then
        if sharding_master_enabled() then
            local port = sharding_port_for_stream_id(tostring(id))
            local local_port = tonumber(config and config.get_setting and config.get_setting("http_port") or 0) or 0
            if port and port ~= local_port then
                return proxy_api_request(server, client, request, port,
                    "/api/v1/streams/" .. tostring(id) .. "/switch-input")
            end
        end
        local message = tostring(err or "switch input failed")
        local code = (message == "stream not found") and 404 or 400
        return error_response(server, client, code, message)
    end
    json_response(server, client, 200, {
        status = "ok",
        action = "switch_input",
        input_index = input_index,
    })
end

local function kill_known_child_processes()
    local function process_ref_key(ref)
        local t = type(ref)
        if t ~= "table" and t ~= "userdata" then
            return nil
        end
        return t .. ":" .. tostring(ref)
    end

    local function killable_process(ref)
        local t = type(ref)
        if t ~= "table" and t ~= "userdata" then
            return false
        end
        local ok, method = pcall(function()
            return ref and ref.kill
        end)
        return ok and type(method) == "function"
    end

    local stats = { killed = 0, failed = 0 }
    local seen = {}

    local function visit(node, depth)
        if depth > 8 then
            return
        end
        local t = type(node)
        if t ~= "table" and t ~= "userdata" then
            return
        end

        local key = process_ref_key(node)
        if key and seen[key] then
            return
        end
        if key then
            seen[key] = true
        end

        if killable_process(node) then
            local ok = pcall(function()
                node:kill()
            end)
            if ok then
                stats.killed = stats.killed + 1
            else
                stats.failed = stats.failed + 1
            end
        end

        if t == "table" then
            for _, value in pairs(node) do
                visit(value, depth + 1)
            end
        end
    end

    if transcode and type(transcode.jobs) == "table" then
        visit(transcode.jobs, 0)
    end
    if radio and type(radio.jobs) == "table" then
        visit(radio.jobs, 0)
    end

    if stats.killed > 0 then
        if stats.failed > 0 then
            log.warning("[restart] child process cleanup: killed=" .. tostring(stats.killed)
                .. " failed=" .. tostring(stats.failed))
        else
            log.info("[restart] child process cleanup: killed=" .. tostring(stats.killed))
        end
    elseif stats.failed > 0 then
        log.warning("[restart] child process cleanup failed for " .. tostring(stats.failed) .. " process(es)")
    else
        log.info("[restart] child process cleanup: no known process handles")
    end
end

local function reload_service(server, client, request)
    if not require_admin(request) then
        return error_response(server, client, 403, "forbidden")
    end
    local ok, err = reload_runtime(true)
    if not ok then
        return json_response(server, client, 500, { error = "reload failed", detail = err })
    end
    json_response(server, client, 200, { status = "ok" })
end

local function restart_service(server, client, request)
    if not require_admin(request) then
        return error_response(server, client, 403, "forbidden")
    end
    local mode = request and request.query and request.query.mode or "soft"
    if mode ~= "hard" then
        return reload_service(server, client, request)
    end
    local supervisor_enabled = setting_bool("supervisor_enabled", false)
        or (os.getenv("ASTRA_SUPERVISOR") == "1")
        or (os.getenv("INVOCATION_ID") ~= nil)
    if not supervisor_enabled then
        return error_response(server, client, 400, "hard restart disabled (no supervisor)")
    end
    json_response(server, client, 200, { status = "restarting" })
    kill_known_child_processes()
    timer({
        interval = 0.2,
        callback = function(self)
            self:close()
            astra.exit()
        end,
    })
end

local function apply_sharding(server, client, request)
    if not require_admin(request) then
        return error_response(server, client, 403, "forbidden")
    end
    if not setting_bool("stream_sharding_enabled", false) then
        return json_response(server, client, 200, {
            status = "disabled",
            message = "stream sharding is disabled; nothing to apply",
        })
    end
    if not sharding or type(sharding.apply_systemd) ~= "function" then
        return error_response(server, client, 400, "sharding module unavailable")
    end
    if type(sharding.preflight_systemd) == "function" then
        local ok, info_or_err = sharding.preflight_systemd()
        if not ok then
            local msg = tostring(info_or_err or "systemd unit not detected")
            if msg:find("systemd unit not detected", 1, true) then
                msg = "systemd unit not detected (run under systemd: stream@<instance>.service)"
            end
            return error_response(server, client, 400, msg)
        end
    end
    json_response(server, client, 200, { status = "applying" })
    timer({
        interval = 0.2,
        callback = function(self)
            self:close()
            local ok, err = sharding.apply_systemd()
            if not ok then
                log.error("[sharding] apply failed: " .. tostring(err))
                if config and config.add_alert then
                    config.add_alert("ERROR", "", "SHARDING_APPLY_FAILED",
                        tostring(err),
                        {})
                end
                return
            end
            log.warning("[sharding] apply ok (services restarted)")
        end,
    })
end

local function get_settings(server, client)
    local rows = config.list_settings and config.list_settings() or {}
    if rows.hls_storage == nil or tostring(rows.hls_storage) == "" then
        rows.hls_storage = "memfd"
    end
    if rows.hls_on_demand == nil then
        rows.hls_on_demand = tostring(rows.hls_storage) == "memfd"
    end
    if rows.http_play_allow == nil then
        rows.http_play_allow = true
    end
    if rows.ui_polling_interval_sec == nil then
        rows.ui_polling_interval_sec = 1
    end
    if rows.dvb_autosearch_enabled == nil then
        rows.dvb_autosearch_enabled = true
    end
    if rows.dvb_autosearch_queue_max == nil then
        rows.dvb_autosearch_queue_max = 32
    end
    if rows.dvb_autosearch_global_switch_min_gap_sec == nil then
        rows.dvb_autosearch_global_switch_min_gap_sec = 20
    end
    if rows.dvb_autosearch_reenqueue_sec == nil then
        rows.dvb_autosearch_reenqueue_sec = 60
    end
    if rows.dvb_autosearch_detection_warmup_sec == nil then
        rows.dvb_autosearch_detection_warmup_sec = 120
    end
    if rows.dvb_autosearch_breaker_window_sec == nil then
        rows.dvb_autosearch_breaker_window_sec = 600
    end
    if rows.dvb_autosearch_breaker_fail_count == nil then
        rows.dvb_autosearch_breaker_fail_count = 3
    end
    if rows.dvb_autosearch_breaker_freeze_sec == nil then
        rows.dvb_autosearch_breaker_freeze_sec = 300
    end
    if rows.dvb_scan_jobs_retention_days == nil then
        rows.dvb_scan_jobs_retention_days = 14
    end
    if rows.dvb_scan_rows_max_per_job == nil then
        rows.dvb_scan_rows_max_per_job = 50000
    end
    if rows.dvb_scan_presets_url == nil or tostring(rows.dvb_scan_presets_url) == "" then
        rows.dvb_scan_presets_url = "https://stream.centv.ru/dvb-presets.json"
    end
    rows.build_transcode = astra and astra.features and astra.features.transcode == true
    rows.build_variant = rows.build_transcode and "full" or "lite"
    local token = rows.telegram_bot_token
    if token ~= nil and tostring(token) ~= "" then
        local masked = token
        local prefix = tostring(token):match("^([^:]+):") or tostring(token):sub(1, 6)
        if #prefix > 6 then
            prefix = prefix:sub(1, 6)
        end
        masked = prefix .. ":***"
        rows.telegram_bot_token_masked = masked
        rows.telegram_bot_token_set = true
    else
        rows.telegram_bot_token_masked = ""
        rows.telegram_bot_token_set = false
    end
    rows.telegram_bot_token = nil

    local ai_key = rows.ai_api_key
    if ai_key ~= nil and tostring(ai_key) ~= "" then
        local prefix = tostring(ai_key):sub(1, 6)
        if #prefix < 3 then
            prefix = tostring(ai_key)
        end
        rows.ai_api_key_masked = prefix .. "***"
        rows.ai_api_key_set = true
    else
        rows.ai_api_key_masked = ""
        rows.ai_api_key_set = false
    end
    rows.ai_api_key = nil
    json_response(server, client, 200, rows)
end

local function apply_log_settings_patch(body)
    if type(body) ~= "table" then
        return
    end
    if log_store and type(log_store.configure) == "function" then
        if body.log_store_enabled ~= nil or body.log_max_entries ~= nil or body.log_retention_sec ~= nil then
            log_store.configure({
                enabled = body.log_store_enabled,
                max_entries = body.log_max_entries,
                retention_sec = body.log_retention_sec,
            })
        end
    end
    if access_log and type(access_log.configure) == "function" then
        if body.access_log_enabled ~= nil or body.access_log_max_entries ~= nil or body.access_log_retention_sec ~= nil then
            access_log.configure({
                enabled = body.access_log_enabled,
                max_entries = body.access_log_max_entries,
                retention_sec = body.access_log_retention_sec,
            })
        end
    end

    -- Apply runtime log options (stdout/file/syslog) on-the-fly.
    if body.runtime_log_dest ~= nil
        or body.runtime_log_level ~= nil
        or body.runtime_log_file ~= nil
        or body.runtime_log_syslog ~= nil
        or body.runtime_log_color ~= nil
        or body.runtime_log_rotate_mb ~= nil
        or body.runtime_log_rotate_keep ~= nil
    then
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
                want_stdout = true
            end

            opts.stdout = want_stdout == true
            opts.filename = want_file and tostring(file_raw or "") or ""
            opts.syslog = want_syslog and tostring(syslog_raw or "") or ""
        elseif dest_mode == nil then
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
            local enabled = (color_raw == true or color_raw == 1 or color_raw == "1" or color_raw == "true")
            opts.color = enabled == true
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

local function settings_patch_skip_runtime_reload(body)
    if type(body) ~= "table" then
        return false
    end
    local fast_keys = {
        servers = true,
        groups = true,
        auth_backends = true,
        users = true,
        softcam = true,
        observability_enabled = true,
        ai_logs_retention_days = true,
        ai_metrics_retention_days = true,
        ai_rollup_interval_sec = true,
        ai_metrics_on_demand = true,
        observability_db_path = true,
        observability_writer_batch_max = true,
        observability_writer_flush_ms = true,
        observability_writer_max_queue = true,
        observability_affinity_enabled = true,
        observability_cpu_policy = true,
        observability_cpu_auto_cores = true,
        observability_cpu_set = true,
        observability_stream_detail_enabled = true,
        observability_stream_highres_enabled = true,
        observability_stream_ffmpeg_metrics_enabled = true,
        observability_system_rollup_enabled = true,
        observability_system_rollup_interval_sec = true,
        observability_system_retention_sec = true,
        observability_system_include_virtual_ifaces = true,
        dvb_autosearch_enabled = true,
        dvb_autosearch_queue_max = true,
        dvb_autosearch_global_switch_min_gap_sec = true,
        dvb_autosearch_reenqueue_sec = true,
        dvb_autosearch_detection_warmup_sec = true,
        dvb_autosearch_breaker_window_sec = true,
        dvb_autosearch_breaker_fail_count = true,
        dvb_autosearch_breaker_freeze_sec = true,
        dvb_scan_jobs_retention_days = true,
        dvb_scan_rows_max_per_job = true,
        dvb_scan_presets_url = true,
    }
    local has_keys = false
    for k, _ in pairs(body) do
        if type(k) == "string" then
            has_keys = true
            if not fast_keys[k] then
                return false
            end
        end
    end
    return has_keys
end

local function settings_values_equal(a, b, depth)
    depth = tonumber(depth) or 0
    if a == b then
        return true
    end
    if depth > 16 then
        return false
    end
    local ta = type(a)
    local tb = type(b)
    if ta ~= tb then
        return false
    end
    if ta ~= "table" then
        return false
    end
    local count_a = 0
    for k, v in pairs(a) do
        count_a = count_a + 1
        if not settings_values_equal(v, b[k], depth + 1) then
            return false
        end
    end
    local count_b = 0
    for k, _ in pairs(b) do
        count_b = count_b + 1
        if a[k] == nil then
            return false
        end
    end
    return count_a == count_b
end

local function settings_patch_is_noop(body)
    if type(body) ~= "table" then
        return false
    end
    if not config or type(config.get_setting) ~= "function" then
        return false
    end
    local has_keys = false
    for k, v in pairs(body) do
        if type(k) == "string" then
            has_keys = true
            local current = config.get_setting(k)
            if not settings_values_equal(current, v, 0) then
                return false
            end
        end
    end
    return has_keys
end

local function set_settings(server, client, request)
    local body = parse_json_body(request)
    if not body then
        return error_response(server, client, 400, "invalid json")
    end
    local query = request and request.query or {}
    local softcam_apply = true
    if query.softcam_apply ~= nil then
        local v = tostring(query.softcam_apply or ""):lower()
        if v == "0" or v == "false" or v == "no" or v == "off" then
            softcam_apply = false
        end
    end
    if body.telegram_bot_token ~= nil then
        local token = tostring(body.telegram_bot_token or "")
        if token == "" then
            body.telegram_bot_token = nil
        end
    end
    if body.ai_api_key ~= nil then
        local key = tostring(body.ai_api_key or "")
        if key == "" then
            body.ai_api_key = nil
        end
    end
    body.telegram_bot_token_masked = nil
    body.telegram_bot_token_set = nil
    body.ai_api_key_masked = nil
    body.ai_api_key_set = nil

    if settings_patch_is_noop(body) then
        return json_response(server, client, 200, {
            status = "ok",
            unchanged = true,
            message = "settings unchanged",
        })
    end

    local skip_runtime_reload = settings_patch_skip_runtime_reload(body)
    apply_config_change(server, client, request, {
        comment = "settings update",
        slow_threshold_ms = 500,
        -- Keep Save fast and avoid blocking the main event loop on large configs.
        -- Config file + snapshots are exported asynchronously by a helper process.
        defer_export = true,
        apply = function()
            local reset_detector_defaults = false
            for k, v in pairs(body) do
                if type(k) == "string" then
                    if k == "telegram_enabled" or k:match("^telegram_detectors_") then
                        reset_detector_defaults = true
                    end
                end
                config.set_setting(k, v)
            end
            if config and config.init_observability_db
                and (body.observability_db_path ~= nil)
            then
                config.init_observability_db({
                    observability_db_path = body.observability_db_path,
                })
            end
            if reset_detector_defaults and type(stream_reset_global_detector_defaults_cache) == "function" then
                stream_reset_global_detector_defaults_cache()
            end
            if softcam_apply and type(apply_softcam_settings) == "function" and body.softcam ~= nil then
                apply_softcam_settings()
            end
            apply_log_settings_patch(body)
            if runtime and runtime.configure_influx
                and (body.influx_enabled ~= nil or body.influx_url ~= nil or body.influx_org ~= nil
                    or body.influx_bucket ~= nil or body.influx_token ~= nil
                    or body.influx_interval_sec ~= nil or body.influx_instance ~= nil
                    or body.influx_measurement ~= nil)
            then
                runtime.configure_influx()
            end
            if runtime and runtime.configure_gc
                and (body.lua_gc_full_collect_interval_ms ~= nil
                    or body.lua_gc_step_interval_ms ~= nil
                    or body.lua_gc_step_units ~= nil)
            then
                runtime.configure_gc()
            end
            if body.performance_aggregate_stream_timers ~= nil
                and type(stream_reconfigure_timer_mode) == "function"
            then
                stream_reconfigure_timer_mode()
            end
            if body.performance_aggregate_transcode_timers ~= nil
                and transcode and transcode.reconfigure_timer_mode
            then
                transcode.reconfigure_timer_mode()
            end
            if telegram and telegram.configure
                and (body.telegram_enabled ~= nil or body.telegram_level ~= nil
                    or body.telegram_bot_token ~= nil or body.telegram_chat_id ~= nil
                    or body.telegram_backup_enabled ~= nil or body.telegram_backup_schedule ~= nil
                    or body.telegram_backup_time ~= nil or body.telegram_backup_weekday ~= nil
                    or body.telegram_backup_monthday ~= nil or body.telegram_backup_include_secrets ~= nil
                    or body.telegram_summary_enabled ~= nil or body.telegram_summary_schedule ~= nil
                    or body.telegram_summary_time ~= nil or body.telegram_summary_weekday ~= nil
                    or body.telegram_summary_monthday ~= nil or body.telegram_summary_include_charts ~= nil)
            then
                telegram.configure()
            end
            if ai_runtime and ai_runtime.configure
                and (body.ai_enabled ~= nil or body.ai_model ~= nil or body.ai_max_tokens ~= nil
                    or body.ai_temperature ~= nil or body.ai_store ~= nil
                    or body.ai_allow_apply ~= nil or body.ai_telegram_allowed_chat_ids ~= nil)
            then
                ai_runtime.configure()
            end
            if ai_observability and ai_observability.configure
                and (body.observability_enabled ~= nil
                    or body.ai_logs_retention_days ~= nil or body.ai_metrics_retention_days ~= nil
                    or body.ai_rollup_interval_sec ~= nil
                    or body.observability_db_path ~= nil
                    or body.observability_writer_batch_max ~= nil
                    or body.observability_writer_flush_ms ~= nil
                    or body.observability_writer_max_queue ~= nil
                    or body.observability_affinity_enabled ~= nil
                    or body.observability_cpu_policy ~= nil
                    or body.observability_cpu_auto_cores ~= nil
                    or body.observability_cpu_set ~= nil
                    or body.observability_stream_highres_enabled ~= nil
                    or body.observability_stream_detail_enabled ~= nil
                    or body.observability_stream_ffmpeg_metrics_enabled ~= nil)
            then
                ai_observability.configure()
            end
            if system_metrics and system_metrics.configure
                and (body.observability_enabled ~= nil
                    or body.ai_logs_retention_days ~= nil or body.ai_metrics_retention_days ~= nil
                    or body.ai_rollup_interval_sec ~= nil
                    or body.observability_system_rollup_enabled ~= nil
                    or body.observability_system_rollup_interval_sec ~= nil
                    or body.observability_system_retention_sec ~= nil
                    or body.observability_system_include_virtual_ifaces ~= nil
                    or body.observability_db_path ~= nil)
            then
                system_metrics.configure()
            end
            if watchdog and watchdog.configure
                and (body.resource_watchdog_enabled ~= nil or body.resource_watchdog_interval_sec ~= nil
                    or body.resource_watchdog_cpu_pct ~= nil or body.resource_watchdog_rss_mb ~= nil
                    or body.resource_watchdog_rss_pct ~= nil or body.resource_watchdog_max_strikes ~= nil
                    or body.resource_watchdog_min_uptime_sec ~= nil or body.resource_watchdog_action ~= nil)
            then
                watchdog.configure()
            end
        end,
        after = function()
            if epg and epg.configure_timer then
                epg.configure_timer()
            end
        end,
        -- Для настроек используем мягкий refresh без force:
        -- stream/adapters с тем же hash не пересобираются, uptime не сбрасывается.
        runtime_apply = function()
            if skip_runtime_reload then
                return true
            end
            return reload_runtime(false)
        end,
        -- Для metadata-only патчей reload не нужен, поэтому не рассылаем broadcast.
        broadcast_reload = not skip_runtime_reload,
        -- В шардах также нужен мягкий refresh, чтобы не дергать все стримы.
        broadcast_force = false,
    })
end

local function telegram_test(server, client)
    if not telegram or not telegram.send_test then
        return error_response(server, client, 400, "telegram notifier unavailable")
    end
    local ok, err = telegram.send_test()
    if not ok then
        return error_response(server, client, 400, err or "telegram disabled")
    end
    json_response(server, client, 200, { status = "queued" })
end

local function telegram_backup(server, client)
    if not telegram or not telegram.send_backup_now then
        return error_response(server, client, 400, "telegram notifier unavailable")
    end
    local ok, err = telegram.send_backup_now()
    if not ok then
        return error_response(server, client, 400, err or "telegram disabled")
    end
    json_response(server, client, 200, { status = "queued" })
end

local function telegram_summary(server, client)
    if not telegram or not telegram.send_summary_now then
        return error_response(server, client, 400, "telegram notifier unavailable")
    end
    local ok, err = telegram.send_summary_now()
    if not ok then
        return error_response(server, client, 400, err or "telegram disabled")
    end
    json_response(server, client, 200, { status = "queued" })
end

local function telegram_status(server, client)
    if not telegram or not telegram.status then
        return error_response(server, client, 400, "telegram notifier unavailable")
    end
    return json_response(server, client, 200, telegram.status())
end

local function telegram_triggers(server, client)
    if not telegram or not telegram.send_triggers_preview then
        return error_response(server, client, 400, "telegram notifier unavailable")
    end
    local ok, err = telegram.send_triggers_preview()
    if not ok then
        return error_response(server, client, 400, err or "telegram disabled")
    end
    json_response(server, client, 200, { status = "queued" })
end

local function ai_status(server, client)
    if not ai_runtime or not ai_runtime.status then
        return json_response(server, client, 200, { enabled = false, ready = false })
    end
    json_response(server, client, 200, ai_runtime.status())
end

local function ai_jobs(server, client)
    if not ai_runtime or not ai_runtime.list_jobs then
        return json_response(server, client, 200, { status = ai_runtime and ai_runtime.status and ai_runtime.status() or {}, jobs = {} })
    end
    json_response(server, client, 200, { status = ai_runtime.status(), jobs = ai_runtime.list_jobs() })
end

local function parse_range_seconds(value, fallback)
    if value == nil or value == "" then
        return fallback
    end
    local text = tostring(value)
    local num, unit = text:match("^(%d+)%s*([smhdwSMHDW]?)$")
    if not num then
        return fallback
    end
    local n = tonumber(num)
    if not n or n <= 0 then
        return fallback
    end
    unit = (unit or ""):lower()
    if unit == "m" then
        return n * 60
    elseif unit == "h" or unit == "" then
        return n * 3600
    elseif unit == "d" then
        return n * 86400
    elseif unit == "w" then
        return n * 604800
    end
    return fallback
end

local function observability_collector_status()
    local status = {}
    if ai_observability and ai_observability.get_collector_status then
        local ok, payload = pcall(ai_observability.get_collector_status)
        if ok and type(payload) == "table" then
            status = payload
        end
    end
    if status.collection_enabled == nil then
        status.collection_enabled = setting_bool("observability_enabled", false)
    end
    if status.read_only_mode == nil then
        status.read_only_mode = not (status.collection_enabled == true)
    end
    return status
end

local function ai_logs(server, client, request)
    if not require_admin(request) then
        return error_response(server, client, 403, "forbidden")
    end
    if not config or not config.list_ai_log_events then
        return error_response(server, client, 400, "observability unavailable")
    end
    local query = request and request.query or {}
    local range = parse_range_seconds(query.range, 24 * 3600)
    local since_ts = os.time() - range
    local until_ts = nil
    local level = query.level
    local stream_id = query.stream_id or query.stream
    local limit = tonumber(query.limit) or 500
    local rows = config.list_ai_log_events({
        since = since_ts,
        ["until"] = until_ts,
        level = level,
        stream_id = stream_id,
        limit = limit,
    })
    local collector = observability_collector_status()
    local collection_enabled = collector.collection_enabled == true
    json_response(server, client, 200, {
        since = since_ts,
        range = range,
        items = rows,
        collection_enabled = collection_enabled,
        read_only_mode = not collection_enabled,
        worker_isolated = collector.worker_isolated == true,
        worker_affinity = collector.worker_affinity,
        worker_backend = collector.worker_backend,
        writer_db = collector.writer_db,
        degrade_mode = collector.degrade_mode == true,
    })
end

local function ai_metrics(server, client, request)
    if not require_admin(request) then
        return error_response(server, client, 403, "forbidden")
    end
    if not config or not config.list_ai_metrics then
        return error_response(server, client, 400, "observability unavailable")
    end
    local query = request and request.query or {}
    local range = parse_range_seconds(query.range, 24 * 3600)
    local since_ts = os.time() - range
    local scope = query.scope or "global"
    local scope_id = query.id or query.stream_id or ""
    local metric_key = query.metric or ""
    local limit = tonumber(query.limit) or 2000
    local collector = observability_collector_status()
    local collection_enabled = collector.collection_enabled == true
    local on_demand = setting_bool("ai_metrics_on_demand", true)
    if ai_observability and ai_observability.state and ai_observability.state.metrics_on_demand then
        on_demand = true
    end
    if on_demand and ai_observability and ai_observability.build_metrics_from_logs then
        local base_interval = setting_number("ai_rollup_interval_sec", 60)
        local target_points = 240
        local adaptive = math.floor(range / target_points)
        local interval = math.max(base_interval, adaptive > 0 and adaptive or base_interval)
        local result = ai_observability.get_on_demand_metrics
            and ai_observability.get_on_demand_metrics(range, interval, scope, scope_id)
            or { items = ai_observability.build_metrics_from_logs(range, interval, scope, scope_id), mode = "on_demand" }
        local items = result.items or {}
        if metric_key and metric_key ~= "" then
            local filtered = {}
            for _, item in ipairs(items) do
                if item.metric_key == metric_key then
                    table.insert(filtered, item)
                end
            end
            items = filtered
        end
        table.sort(items, function(a, b)
            if a.ts_bucket == b.ts_bucket then
                return tostring(a.metric_key) < tostring(b.metric_key)
            end
            return (a.ts_bucket or 0) < (b.ts_bucket or 0)
        end)
        json_response(server, client, 200, {
            since = since_ts,
            range = range,
            items = items,
            mode = result.mode or "on_demand",
            collection_enabled = collection_enabled,
            read_only_mode = not collection_enabled,
            worker_isolated = collector.worker_isolated == true,
            worker_affinity = collector.worker_affinity,
            worker_backend = collector.worker_backend,
            writer_db = collector.writer_db,
            degrade_mode = collector.degrade_mode == true,
        })
        return
    end

    local rows = config.list_ai_metrics({
        since = since_ts,
        scope = scope,
        scope_id = scope_id,
        metric_key = metric_key,
        limit = limit,
    })
    json_response(server, client, 200, {
        since = since_ts,
        range = range,
        items = rows,
        mode = "rollup",
        collection_enabled = collection_enabled,
        read_only_mode = not collection_enabled,
        worker_isolated = collector.worker_isolated == true,
        worker_affinity = collector.worker_affinity,
        worker_backend = collector.worker_backend,
        writer_db = collector.writer_db,
        degrade_mode = collector.degrade_mode == true,
    })
end

local function parse_csv_list(text)
    local out = {}
    local seen = {}
    local raw = tostring(text or "")
    if raw == "" then
        return out
    end
    for token in raw:gmatch("([^,]+)") do
        local item = tostring(token):gsub("^%s+", ""):gsub("%s+$", "")
        if item ~= "" and not seen[item] then
            seen[item] = true
            out[#out + 1] = item
        end
    end
    return out
end

local function system_metrics_snapshot(server, client, request)
    if not require_admin(request) then
        return error_response(server, client, 403, "forbidden")
    end
    if not system_metrics or not system_metrics.snapshot then
        return error_response(server, client, 400, "system metrics unavailable")
    end

    local snap = system_metrics.snapshot() or {}
    local now_ms = (snap.ts or os.time()) * 1000
    snap.ts_ms = now_ms
    local collector = observability_collector_status()
    local collection_enabled = collector.collection_enabled == true

    json_response(server, client, 200, {
        now = now_ms,
        snapshot = snap,
        flags = {
            enabled = true,
            collection_enabled = collection_enabled,
            read_only_mode = not collection_enabled,
            rollup = (system_metrics.state and system_metrics.state.rollup_enabled) == true,
            rollup_interval_sec = system_metrics.state and system_metrics.state.rollup_interval_sec or nil,
            retention_sec = system_metrics.state and system_metrics.state.retention_sec or nil,
            retention_source = system_metrics.state and system_metrics.state.retention_source or nil,
            worker_isolated = collector.worker_isolated == true,
            worker_affinity = collector.worker_affinity,
            worker_backend = collector.worker_backend,
            writer_db = collector.writer_db,
            degrade_mode = collector.degrade_mode == true,
        },
    })
end

local function system_metrics_timeseries(server, client, request)
    if not require_admin(request) then
        return error_response(server, client, 403, "forbidden")
    end
    if not system_metrics or not system_metrics.get_timeseries then
        return error_response(server, client, 400, "system metrics unavailable")
    end

    local query = request and request.query or {}
    local range = parse_range_seconds(query.range, 24 * 3600)
    local result = system_metrics.get_timeseries(range) or {}
    local items = result.items or {}

    local series = {
        cpu_usage = {},
        mem_used_percent = {},
        disk_used_percent = {},
        net_rx_bps = {},
        net_tx_bps = {},
    }

    for _, pt in ipairs(items) do
        local t = pt.t_ms
        if t then
            if pt.cpu_usage ~= nil then
                table.insert(series.cpu_usage, { t, pt.cpu_usage })
            end
            if pt.mem_used_percent ~= nil then
                table.insert(series.mem_used_percent, { t, pt.mem_used_percent })
            end
            if pt.disk_used_percent ~= nil then
                table.insert(series.disk_used_percent, { t, pt.disk_used_percent })
            end
            if pt.net then
                for iface, v in pairs(pt.net) do
                    if v and v.rx_bps ~= nil then
                        series.net_rx_bps[iface] = series.net_rx_bps[iface] or {}
                        table.insert(series.net_rx_bps[iface], { t, v.rx_bps })
                    end
                    if v and v.tx_bps ~= nil then
                        series.net_tx_bps[iface] = series.net_tx_bps[iface] or {}
                        table.insert(series.net_tx_bps[iface], { t, v.tx_bps })
                    end
                end
            end
        end
    end

    local now_ms = os.time() * 1000
    local collector = observability_collector_status()
    local collection_enabled = collector.collection_enabled == true
    json_response(server, client, 200, {
        now = now_ms,
        timeseries = series,
        flags = {
            enabled = true,
            collection_enabled = collection_enabled,
            read_only_mode = not collection_enabled,
            rollup = result.rollup == true,
            rollup_enabled = (system_metrics.state and system_metrics.state.rollup_enabled) == true,
            rollup_interval_sec = system_metrics.state and system_metrics.state.rollup_interval_sec or nil,
            retention_sec = system_metrics.state and system_metrics.state.retention_sec or nil,
            retention_source = system_metrics.state and system_metrics.state.retention_source or nil,
            worker_isolated = collector.worker_isolated == true,
            worker_affinity = collector.worker_affinity,
            worker_backend = collector.worker_backend,
            writer_db = collector.writer_db,
            degrade_mode = collector.degrade_mode == true,
        },
    })
end

local function observability_stream_series(server, client, request)
    if not require_admin(request) then
        return error_response(server, client, 403, "forbidden")
    end
    if not ai_observability or not ai_observability.get_stream_series then
        return error_response(server, client, 400, "observability stream series unavailable")
    end
    local query = request and request.query or {}
    local stream_id = query.stream_id or query.id
    if not stream_id or tostring(stream_id) == "" then
        return error_response(server, client, 400, "stream_id required")
    end
    local range = parse_range_seconds(query.range, 24 * 3600)
    local metrics = parse_csv_list(query.metrics or "")
    local result, err = ai_observability.get_stream_series({
        stream_id = tostring(stream_id),
        range_sec = range,
        resolution = query.resolution or "auto",
        metrics = metrics,
        max_points = tonumber(query.max_points) or 1200,
    })
    if not result then
        return error_response(server, client, 400, err or "failed to load stream series")
    end
    json_response(server, client, 200, result)
end

local function observability_stream_events(server, client, request)
    if not require_admin(request) then
        return error_response(server, client, 403, "forbidden")
    end
    if not ai_observability or not ai_observability.get_stream_events then
        return error_response(server, client, 400, "observability stream events unavailable")
    end
    local query = request and request.query or {}
    local stream_id = query.stream_id or query.id
    if not stream_id or tostring(stream_id) == "" then
        return error_response(server, client, 400, "stream_id required")
    end
    local kinds = parse_csv_list(query.kinds or "")
    if #kinds == 0 then
        kinds = { "ffmpeg", "input_switch", "alerts" }
    end
    local range = parse_range_seconds(query.range, 24 * 3600)
    local result, err = ai_observability.get_stream_events({
        stream_id = tostring(stream_id),
        range_sec = range,
        kinds = kinds,
        limit = tonumber(query.limit) or 300,
    })
    if not result then
        return error_response(server, client, 400, err or "failed to load stream events")
    end
    json_response(server, client, 200, result)
end

local function observability_collector_debug(server, client, request)
    if not require_admin(request) then
        return error_response(server, client, 403, "forbidden")
    end
    json_response(server, client, 200, observability_collector_status())
end

local function ai_summary(server, client, request)
    if not require_admin(request) then
        return error_response(server, client, 403, "forbidden")
    end
    if not config or not config.list_ai_metrics then
        return error_response(server, client, 400, "observability unavailable")
    end
    local query = request and request.query or {}
    local include_logs = false
    if query.include_logs ~= nil then
        local value = tostring(query.include_logs)
        if value == "1" or value == "true" then
            include_logs = true
        end
    end
    local include_cli = query.include_cli or query.cli
    local cli_stream_id = query.stream_id or query.id
    local cli_input_url = query.input_url or query.url
    local cli_femon_url = query.femon_url
    local cli_log_limit = tonumber(query.log_limit) or nil
    local range = parse_range_seconds(query.range, 24 * 3600)
    local since_ts = os.time() - range
    local on_demand = setting_bool("ai_metrics_on_demand", true)
    if ai_observability and ai_observability.state and ai_observability.state.metrics_on_demand then
        on_demand = true
    end
    local summary = {
        total_bitrate_kbps = 0,
        streams_on_air = 0,
        streams_down = 0,
        streams_total = 0,
        input_switch = 0,
        alerts_error = 0,
    }
    local last_bucket = 0
    local metrics = {}
    if on_demand and ai_observability and ai_observability.build_metrics_from_logs then
        local base_interval = setting_number("ai_rollup_interval_sec", 60)
        local target_points = 240
        local adaptive = math.floor(range / target_points)
        local interval = math.max(base_interval, adaptive > 0 and adaptive or base_interval)
        local result = ai_observability.get_on_demand_metrics
            and ai_observability.get_on_demand_metrics(range, interval, "global", "")
            or nil
        if result then
            metrics = result.items or {}
            summary = result.summary or summary
            last_bucket = result.bucket or 0
        end
    else
        metrics = config.list_ai_metrics({
            since = since_ts,
            scope = "global",
            limit = 10000,
        })
        for _, row in ipairs(metrics) do
            if row.ts_bucket and row.ts_bucket > last_bucket then
                last_bucket = row.ts_bucket
            end
        end
        if last_bucket > 0 then
            for _, row in ipairs(metrics) do
                if row.ts_bucket == last_bucket then
                    if summary[row.metric_key] ~= nil then
                        summary[row.metric_key] = row.value
                    end
                end
            end
        end
    end

    local want_ai = query.ai == "1" or query.ai == "true" or query.mode == "ai"
    if not want_ai then
        return json_response(server, client, 200, {
            range = range,
            latest_bucket = last_bucket,
            summary = summary,
            note = "AI summary not enabled; returning latest rollup snapshot",
        })
    end
    if not ai_runtime or not ai_runtime.is_ready or not ai_runtime.is_ready() then
        return json_response(server, client, 200, {
            range = range,
            latest_bucket = last_bucket,
            summary = summary,
            ai = nil,
            note = "AI not configured",
        })
    end
    if include_logs and (not config or not config.list_ai_log_events) then
        return json_response(server, client, 200, {
            range = range,
            latest_bucket = last_bucket,
            summary = summary,
            ai = nil,
            note = "AI log events unavailable",
        })
    end
    local errors = {}
    if include_logs and config and config.list_ai_log_events then
        errors = config.list_ai_log_events({
            since = since_ts,
            level = "ERROR",
            limit = 20,
        })
    end
    local responded = false
    ai_runtime.request_summary({
        summary = summary,
        errors = errors,
        range_sec = range,
        include_logs = include_logs,
        include_cli = include_cli,
        stream_id = cli_stream_id,
        input_url = cli_input_url,
        femon_url = cli_femon_url,
        log_limit = cli_log_limit,
    }, function(ok, result)
        if responded then return end
        responded = true
        if not ok then
            return json_response(server, client, 200, {
                range = range,
                latest_bucket = last_bucket,
                summary = summary,
                ai = nil,
                note = "AI summary failed",
            })
        end
        json_response(server, client, 200, {
            range = range,
            latest_bucket = last_bucket,
            summary = summary,
            ai = result,
            note = "AI summary",
        })
    end)
end

local function ai_plan(server, client, request)
    if not require_admin(request) then
        return error_response(server, client, 403, "forbidden")
    end
    if not ai_runtime or not ai_runtime.plan then
        return error_response(server, client, 400, "ai runtime unavailable")
    end
    local body = parse_json_body(request)
    if not body then
        return error_response(server, client, 400, "invalid json")
    end
    local user = get_request_user(request)
    local job = ai_runtime.plan(body, {
        user = user and user.username or (request and request.user or ""),
        user_id = user and user.id or 0,
        ip = request and request.addr or "",
    })
    if not job then
        return error_response(server, client, 500, "ai plan failed")
    end
    json_response(server, client, 200, job)
end

local function ai_apply(server, client, request)
    if not require_admin(request) then
        return error_response(server, client, 403, "forbidden")
    end
    if not ai_runtime or not ai_runtime.apply then
        return error_response(server, client, 400, "ai runtime unavailable")
    end
    if not ai_runtime.is_enabled or not ai_runtime.is_enabled() then
        return error_response(server, client, 400, "ai disabled")
    end
    if not (ai_runtime.config and ai_runtime.config.allow_apply) then
        return error_response(server, client, 403, "ai apply disabled")
    end
    local body = parse_json_body(request)
    if not body then
        return error_response(server, client, 400, "invalid json")
    end
    local ok, err = ai_runtime.apply(body, { user = request and request.user or "" })
    if not ok then
        return error_response(server, client, 501, err or "ai apply not implemented")
    end
    json_response(server, client, 200, ok)
end

local function ai_telegram(server, client, request)
    if not require_admin(request) then
        return error_response(server, client, 403, "forbidden")
    end
    if not ai_runtime or not ai_runtime.handle_telegram then
        return error_response(server, client, 400, "ai runtime unavailable")
    end
    local body = parse_json_body(request)
    if not body then
        return error_response(server, client, 400, "invalid json")
    end
    local ok, err = ai_runtime.handle_telegram(body)
    if not ok then
        return error_response(server, client, 501, err or "ai telegram not implemented")
    end
    json_response(server, client, 200, ok)
end

local function resolve_server_entry(body)
    if type(body) ~= "table" then
        return nil, "invalid json"
    end
    local server_id = body.id
    if server_id == nil or tostring(server_id or "") == "" then
        server_id = body.server_id
    end
    if server_id and config and config.get_setting then
        local list = config.get_setting("servers")
        if type(list) == "table" then
            for _, item in ipairs(list) do
                if type(item) == "table" and tostring(item.id or "") == tostring(server_id or "") then
                    local merged = {}
                    for k, v in pairs(item) do
                        merged[k] = v
                    end
                    -- Allow unsaved form test payload to override saved fields,
                    -- including explicit empty values (for auth-none checks).
                    for k, v in pairs(body) do
                        if k ~= "id" then
                            merged[k] = v
                        end
                    end
                    return merged
                end
            end
        end
        return nil, "server not found"
    end
    return body
end

function normalize_server_host(entry)
    if type(entry) ~= "table" then
        return nil, "invalid server"
    end
    local host = entry.host or entry.address or ""
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
        -- Allow host/path without scheme.
        -- Examples:
        -- - 127.0.0.1
        -- - 127.0.0.1:8000
        -- - 127.0.0.1/base
        -- - 127.0.0.1:8000/base
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
    local port = tonumber(entry.port) or port_hint or (parsed and parsed.port) or (scheme == "https" and 443 or 8000)
    local hostname = parsed and parsed.host or host_only
    local base_path = parsed and parsed.path or base_path_hint or ""
    if base_path == "/" then
        base_path = ""
    end
    if base_path ~= "" then
        base_path = tostring(base_path):gsub("/+$", "")
        if base_path == "/" then
            base_path = ""
        end
    end
    local insecure = (entry.insecure == true or entry.insecure == 1 or entry.insecure == "1"
        or entry.tls_insecure == true or entry.tls_insecure == 1 or entry.tls_insecure == "1")
    local function pick_login(src)
        local login = tostring(src and src.login or ""):gsub("^%s+", ""):gsub("%s+$", "")
        if login ~= "" then
            return login
        end
        local user = tostring(src and src.user or ""):gsub("^%s+", ""):gsub("%s+$", "")
        if user ~= "" then
            return user
        end
        if src and src.login ~= nil then
            return tostring(src.login):gsub("^%s+", ""):gsub("%s+$", "")
        end
        if src and src.user ~= nil then
            return tostring(src.user):gsub("^%s+", ""):gsub("%s+$", "")
        end
        return ""
    end

    local function pick_password(src)
        if type(src) ~= "table" then
            return ""
        end
        local password = tostring(src.password or "")
        if password ~= "" then
            return password
        end
        local pass = tostring(src.pass or "")
        if pass ~= "" then
            return pass
        end
        if src.password ~= nil then
            return tostring(src.password or "")
        end
        if src.pass ~= nil then
            return tostring(src.pass or "")
        end
        return ""
    end

    return {
        host = hostname,
        port = port,
        login = pick_login(entry),
        password = pick_password(entry),
        scheme = scheme,
        base_path = base_path,
        insecure = insecure == true,
    }
end

function slugify_server_id(value)
    local text = tostring(value or ""):lower()
    text = text:gsub("[^%w_-]+", "_")
    text = text:gsub("_+", "_")
    text = text:gsub("^_+", ""):gsub("_+$", "")
    return text
end

function get_server_id(entry)
    if type(entry) ~= "table" then
        return nil
    end
    local id = tostring(entry.id or "")
    if id ~= "" then
        return id
    end
    local seed = entry.name or entry.host or entry.address or ""
    local slug = slugify_server_id(seed)
    if slug == "" then
        return nil
    end
    return slug
end

local function normalize_server_api_type(value)
    local raw = tostring(value or ""):gsub("^%s+", ""):gsub("%s+$", ""):lower()
    if raw == "" or raw == "auto" then
        return "auto"
    end
    if raw == "stream_v1" or raw == "stream-v1" or raw == "stream" then
        return "stream_v1"
    end
    if raw == "astra_legacy" or raw == "astra-legacy" or raw == "astra" or raw == "legacy" then
        return "astra_legacy"
    end
    if raw == "dvr_v1" or raw == "dvr-v1" or raw == "dvr" then
        return "dvr_v1"
    end
    return "auto"
end

function build_server_path(cfg, path)
    local base = cfg.base_path or ""
    if base == "" then
        return path
    end
    return base .. path
end

function decode_json_safe(text)
    if not text or text == "" then
        return nil
    end
    local ok, data = pcall(json.decode, text)
    if not ok then
        return nil
    end
    return data
end

function api._servers_extract_error_text(payload)
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
    text = tostring(text or ""):gsub("%s+", " "):gsub("^%s+", ""):gsub("%s+$", "")
    return text
end

function api._servers_http_error_text(code, payload)
    local code_num = tonumber(code)
    local prefix = code_num and ("http " .. tostring(math.floor(code_num))) or "http error"
    local detail = api._servers_extract_error_text(payload)
    if detail ~= "" then
        return prefix .. ": " .. detail
    end
    return prefix
end

function api._servers_classify_error_status(message, fallback_code)
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
        -- Remote auth failures should not be treated as local session expiry.
        return 403
    end
    if text:find("no response", 1, true)
        or text:find("timeout", 1, true)
        or text:find("curl failed", 1, true)
        or text:find("curl unavailable", 1, true)
        or text:find("curl spawn failed", 1, true)
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

function parse_cookie_from_headers(headers)
    if not headers then
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

function ensure_curl_available()
    if not process or type(process.spawn) ~= "function" then
        return false
    end
    local ok, proc = pcall(process.spawn, { "curl", "--version" }, { stdout = "pipe", stderr = "pipe" })
    if not ok or not proc then
        return false
    end
    if proc and proc.close then
        proc:close()
    end
    return true
end

function run_curl(args, callback)
    if not ensure_curl_available() then
        callback(nil, nil, "curl unavailable")
        return
    end
    local ok, proc = pcall(process.spawn, args, { stdout = "pipe", stderr = "pipe" })
    if not ok or not proc then
        callback(nil, nil, "curl spawn failed")
        return
    end
    local start_ts = os.time()
    local poller = nil
    poller = timer({
        interval = 0.2,
        callback = function()
            local status = proc:poll()
            if not status then
                if os.time() - start_ts > 15 then
                    proc:terminate()
                    proc:kill()
                    proc:close()
                    if poller then poller:close() end
                    callback(nil, nil, "curl timeout")
                end
                return
            end
            if poller then poller:close() end
            local stdout = proc:read_stdout()
            local stderr = proc:read_stderr()
            proc:close()
            callback(status, stdout, stderr)
        end,
    })
end

function parse_curl_body_code(output)
    if not output then
        return nil, nil
    end
    local code = output:match("ASTRA_HTTP_CODE:(%d+)%s*$")
    local body = output:gsub("\nASTRA_HTTP_CODE:%d+%s*$", "")
    if code then
        return tonumber(code), body
    end
    return nil, output
end

function split_headers_body(text)
    if not text then
        return "", ""
    end
    local marker = "\r\n\r\n"
    local idx = text:find(marker, 1, true)
    if not idx then
        return text, ""
    end
    local head = text:sub(1, idx - 1)
    local body = text:sub(idx + #marker)
    return head, body
end

function parse_status_from_headers(text)
    if not text then
        return nil
    end
    local code = text:match("HTTP/%d%.%d%s+(%d%d%d)")
    if code then
        return tonumber(code)
    end
    return nil
end

function parse_cookie_from_header_text(text)
    if not text then
        return nil
    end
    local cookie = text:match("[Ss]et%-[Cc]ookie:%s*([^\r\n]+)")
    if not cookie then
        return nil
    end
    local token = cookie:match("stream_session=([^;]+)")
    if token and token ~= "" then
        return "stream_session=" .. token
    end
    token = cookie:match("astra_session=([^;]+)")
    if token and token ~= "" then
        return "astra_session=" .. token
    end
    return nil
end

function remote_http_login(cfg, callback)
    if not cfg.login or cfg.login == "" or not cfg.password or cfg.password == "" then
        callback(true, nil, nil, nil)
        return
    end
    local payload = json.encode({ username = cfg.login, password = cfg.password })
    local headers = {
        "Content-Type: application/json",
        "Content-Length: " .. tostring(#payload),
        "Host: " .. tostring(cfg.host) .. ":" .. tostring(cfg.port),
        "Connection: close",
    }
    local paths = {
        "/api/v1/auth/login",
        "/api/auth/login",
    }
    local idx = 1
    local function attempt()
        local path = build_server_path(cfg, paths[idx])
        http_request({
            host = cfg.host,
            port = cfg.port,
            path = path,
            method = "POST",
            headers = headers,
            content = payload,
            callback = function(self, response)
                if not response then
                    return callback(false, nil, "login failed (no response)", nil)
                end
                local code = response.code or 0
                if (code == 404 or code == 403) and idx < #paths then
                    idx = idx + 1
                    return attempt()
                end
                if not code or code >= 400 then
                    local data = decode_json_safe(response.content or "")
                    local detail = api._servers_extract_error_text(data)
                    if detail ~= "" then
                        return callback(false, nil, "login failed (" .. tostring(code or "unknown") ..
                            ": " .. detail .. ")", code)
                    end
                    return callback(false, nil, "login failed (" .. tostring(code or "unknown") .. ")", code)
                end
                local cookie = parse_cookie_from_headers(response.headers)
                if not cookie then
                    return callback(false, nil, "login failed (no session cookie)", code)
                end
                callback(true, cookie, nil, code)
            end,
        })
    end
    attempt()
end

function remote_http_fetch_json(cfg, path, cookie, method, body, callback)
    local headers = {
        "Host: " .. tostring(cfg.host) .. ":" .. tostring(cfg.port),
        "Connection: close",
    }
    if cookie and cookie ~= "" then
        table.insert(headers, "Cookie: " .. cookie)
    end
    local payload = body or nil
    if payload then
        table.insert(headers, "Content-Type: application/json")
        table.insert(headers, "Content-Length: " .. tostring(#payload))
    end
    http_request({
        host = cfg.host,
        port = cfg.port,
        path = build_server_path(cfg, path),
        method = method or "GET",
        headers = headers,
        content = payload,
        callback = function(self, response)
            if not response then
                return callback(false, nil, "no response")
            end
            local code = response.code or 0
            if code >= 400 then
                local data = decode_json_safe(response.content or "")
                return callback(false, nil, api._servers_http_error_text(code, data), code)
            end
            local data = decode_json_safe(response.content or "")
            if not data then
                return callback(false, nil, "invalid json", code)
            end
            callback(true, data, nil, code)
        end,
    })
end

function remote_https_login(cfg, callback)
    if not cfg.login or cfg.login == "" or not cfg.password or cfg.password == "" then
        callback(true, nil, nil, nil)
        return
    end
    local payload = json.encode({ username = cfg.login, password = cfg.password })
    local paths = {
        "/api/v1/auth/login",
        "/api/auth/login",
    }
    local idx = 1
    local function attempt()
        local url = string.format("https://%s:%d%s", cfg.host, cfg.port, build_server_path(cfg, paths[idx]))
        local args = {
            "curl",
            "-sS",
            cfg.insecure == true and "-k" or nil,
            "-D",
            "-",
            "-o",
            "-",
            "-H",
            "Content-Type: application/json",
            "-X",
            "POST",
            url,
            "-d",
            payload,
        }
        local filtered = {}
        for _, item in ipairs(args) do
            if item ~= nil then
                table.insert(filtered, item)
            end
        end
        args = filtered
        run_curl(args, function(status, stdout, stderr)
            if not status then
                return callback(false, nil, stderr or "login failed", nil)
            end
            local head, body = split_headers_body(stdout or "")
            local code = parse_status_from_headers(head) or 0
            if (code == 404 or code == 403) and idx < #paths then
                idx = idx + 1
                return attempt()
            end
            if not code or code >= 400 then
                local data = decode_json_safe(body or "")
                local detail = api._servers_extract_error_text(data)
                if detail ~= "" then
                    return callback(false, nil, "login failed (" .. tostring(code or "unknown") ..
                        ": " .. detail .. ")", code)
                end
                return callback(false, nil, "login failed (" .. tostring(code or "unknown") .. ")", code)
            end
            local cookie = parse_cookie_from_header_text(head)
            if not cookie then
                return callback(false, nil, "login failed (no session cookie)", code)
            end
            callback(true, cookie, nil, code)
        end)
    end
    attempt()
end

function remote_https_fetch_json(cfg, path, cookie, method, body, callback)
    local url = string.format("https://%s:%d%s", cfg.host, cfg.port, build_server_path(cfg, path))
    local args = { "curl", "-sS", "-w", "\nASTRA_HTTP_CODE:%{http_code}\n" }
    if cfg.insecure == true then
        table.insert(args, "-k")
    end
    if cookie and cookie ~= "" then
        table.insert(args, "-H")
        table.insert(args, "Cookie: " .. cookie)
    end
    if body then
        table.insert(args, "-H")
        table.insert(args, "Content-Type: application/json")
        table.insert(args, "-X")
        table.insert(args, method or "POST")
        table.insert(args, "-d")
        table.insert(args, body)
    else
        if method and method ~= "GET" then
            table.insert(args, "-X")
            table.insert(args, method)
        end
    end
    table.insert(args, url)
    run_curl(args, function(status, stdout, stderr)
        if not status then
            return callback(false, nil, stderr or "curl failed")
        end
        local code, bodyText = parse_curl_body_code(stdout or "")
        if not code then
            return callback(false, nil, "no http code")
        end
        if code >= 400 then
            local data = decode_json_safe(bodyText or "")
            return callback(false, nil, api._servers_http_error_text(code, data), code)
        end
        local data = decode_json_safe(bodyText or "")
        if not data then
            return callback(false, nil, "invalid json", code)
        end
        callback(true, data, nil, code)
    end)
end

function remote_login(cfg, callback)
    if cfg.scheme == "https" then
        return remote_https_login(cfg, callback)
    end
    return remote_http_login(cfg, callback)
end

function remote_fetch_json(cfg, path, cookie, method, body, callback)
    if cfg.scheme == "https" then
        return remote_https_fetch_json(cfg, path, cookie, method, body, callback)
    end
    return remote_http_fetch_json(cfg, path, cookie, method, body, callback)
end

function remote_health_check(cfg, callback)
    local function do_health(cookie, path)
        remote_fetch_json(cfg, path, cookie, "GET", nil, function(ok, data, err, code)
            if ok then
                return callback(true, "health ok", code)
            end
            if err == "invalid json" and code and code >= 200 and code < 300 then
                return callback(true, "health ok", code)
            end
            if code == 404 and path == "/api/v1/health/process" then
                return do_health(cookie, "/api/v1/health")
            end
            return callback(false, err or "health check failed", code)
        end)
    end
    remote_login(cfg, function(ok, cookie, err, code)
        if not ok then
            return callback(false, err or "login failed", code)
        end
        do_health(cookie, "/api/v1/health/process")
    end)
end

function api._servers_boolish(value, fallback)
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

function api._servers_fetch_streams(cfg, cookie, callback)
    local paths = { "/api/v1/streams", "/api/streams" }
    local idx = 1
    local function fetch_next()
        local path = paths[idx]
        remote_fetch_json(cfg, path, cookie, "GET", nil, function(ok, data, fetch_err, code)
            if not ok then
                if code == 404 and idx < #paths then
                    idx = idx + 1
                    return fetch_next()
                end
                return callback(false, nil, fetch_err or "fetch failed", code)
            end
            callback(true, data, nil, code)
        end)
    end
    fetch_next()
end

function api._servers_extract_stream_summaries(data)
    local out = {}

    local function push_cfg(cfg, enabled_hint)
        if type(cfg) ~= "table" then
            return
        end
        local id = tostring(cfg.id or "")
        if id == "" then
            return
        end
        local name = tostring(cfg.name or cfg.id or "")
        local stype = tostring(cfg.type or "")
        local enabled = enabled_hint
        if enabled == nil then
            enabled = api._servers_boolish(cfg.enabled, api._servers_boolish(cfg.enable, true))
        end
        table.insert(out, {
            id = id,
            name = name,
            type = stype,
            enabled = enabled == true,
        })
    end

    if type(data) == "table" and type(data.make_stream) == "table" then
        for _, cfg in ipairs(data.make_stream) do
            push_cfg(cfg, nil)
        end
    elseif type(data) == "table" then
        local list = data
        if type(data.items) == "table" then
            list = data.items
        end
        if type(list) == "table" then
            for _, row in ipairs(list) do
                if type(row) == "table" and type(row.config) == "table" then
                    push_cfg(row.config, api._servers_boolish(row.enabled, nil))
                end
            end
        end
    end

    table.sort(out, function(a, b)
        return tostring(a.id or "") < tostring(b.id or "")
    end)
    return out
end

local function server_test(server, client, request)
    local admin = require_admin(request)
    if not admin then
        return error_response(server, client, 403, "forbidden")
    end
    if not (remote_servers and type(remote_servers.probe) == "function") then
        return error_response(server, client, 500, "remote servers api is unavailable")
    end
    local body = parse_json_body(request)
    if not body then
        return error_response(server, client, 400, "invalid json")
    end
    local entry, err = resolve_server_entry(body)
    if not entry then
        return error_response(server, client, 404, err or "server not found")
    end
    remote_servers.probe(entry, function(ok, payload, probe_err, remote_code)
        if ok then
            return json_response(server, client, 200, payload or { status = "ok", message = "ok" })
        end
        local text = tostring(probe_err or "failed")
        local code = remote_servers.classify_error_status
            and remote_servers.classify_error_status(text, remote_code)
            or api._servers_classify_error_status(text, remote_code)
        return error_response(server, client, code, text)
    end)
end

local function softcam_test(server, client, request)
    local admin = require_admin(request)
    if not admin then
        return error_response(server, client, 403, "forbidden")
    end
    local body = parse_json_body(request)
    if not body then
        return error_response(server, client, 400, "invalid json")
    end

    local host = tostring(body.host or ""):gsub("^%s+", ""):gsub("%s+$", "")
    local port = tonumber(body.port or 0) or 0
    local user = tostring(body.user or ""):gsub("^%s+", ""):gsub("%s+$", "")
    local pass = tostring(body.pass or "")
    local key = tostring(body.key or ""):gsub("%s+", "")
    local caid = tostring(body.caid or ""):gsub("%s+", "")

    if host == "" then
        return error_response(server, client, 400, "host is required")
    end
    if port <= 0 then
        return error_response(server, client, 400, "port is required")
    end
    if user == "" then
        return error_response(server, client, 400, "user is required")
    end
    if pass == "" then
        return error_response(server, client, 400, "pass is required")
    end

    if key ~= "" then
        if key:sub(1, 2):lower() == "0x" then
            key = key:sub(3)
        end
        if not key:match("^[0-9a-fA-F]+$") or #key ~= 28 then
            return error_response(server, client, 400, "key must be 28 hex chars")
        end
        key = key:lower()
    end

    if caid ~= "" then
        if caid:sub(1, 2):lower() == "0x" then
            caid = caid:sub(3)
        end
        if not caid:match("^[0-9a-fA-F]+$") or #caid ~= 4 then
            return error_response(server, client, 400, "caid must be 4 hex chars")
        end
        caid = caid:upper()
    end

    local timeout = tonumber(body.timeout or 0) or 0
    if timeout <= 0 then
        local timeout_ms = tonumber(body.timeout_ms or 0) or 0
        if timeout_ms > 0 then
            timeout = math.floor(timeout_ms / 1000)
        end
    end
    if timeout <= 0 then
        timeout = 8
    end

    local ctor = _G["newcamd"]
    if type(ctor) ~= "function" and type(ctor) ~= "table" then
        return error_response(server, client, 500, "newcamd module unavailable")
    end

    local cfg = {
        name = "Softcam test",
        type = "newcamd",
        host = host,
        port = port,
        user = user,
        pass = pass,
        timeout = timeout,
        disable_emm = true,
    }
    if key ~= "" then
        cfg.key = key
    end
    if caid ~= "" then
        cfg.caid = caid
    end

    local ok, cam = pcall(ctor, cfg)
    if not ok or not cam then
        return error_response(server, client, 400, "softcam init failed")
    end
    if type(cam) ~= "table" or type(cam.stats) ~= "function" then
        pcall(function()
            if cam and cam.close then cam:close() end
        end)
        return error_response(server, client, 500, "softcam stats unavailable")
    end

    local responded = false
    local poller = nil
    local tries = 0
    local last_stats = nil

    local function finish_ok(message, stats)
        if responded then return end
        responded = true
        if poller then poller:close() end
        pcall(function()
            if cam and cam.close then cam:close() end
        end)
        json_response(server, client, 200, {
            status = "ok",
            message = message or "ok",
            cam = stats,
        })
    end

    local function finish_err(code, message, stats)
        if responded then return end
        responded = true
        if poller then poller:close() end
        pcall(function()
            if cam and cam.close then cam:close() end
        end)
        json_response(server, client, code or 400, {
            error = message or "softcam test failed",
            cam = stats,
        })
    end

    local max_wait_sec = tonumber(body.max_wait_sec or 3) or 3
    if max_wait_sec < 0.5 then max_wait_sec = 0.5 end
    if max_wait_sec > 10 then max_wait_sec = 10 end
    local max_tries = math.max(3, math.floor((max_wait_sec / 0.1) + 0.5))

    poller = timer({
        interval = 0.1,
        callback = function()
            tries = tries + 1
            local ok2, stats = pcall(function()
                return cam:stats()
            end)
            if ok2 and type(stats) == "table" then
                last_stats = stats
                if stats.ready == true then
                    return finish_ok("ready", stats)
                end
            end
            if tries >= max_tries then
                local err = "timeout"
                if last_stats and last_stats.last_error then
                    err = tostring(last_stats.last_error)
                end
                return finish_err(400, "softcam not ready: " .. err, last_stats)
            end
        end,
    })
end

local function list_server_entries(filter_id)
    local list = (config and config.get_setting) and config.get_setting("servers") or nil
    if type(list) ~= "table" then
        return {}
    end
    if not filter_id then
        return list
    end
    local out = {}
    for _, entry in ipairs(list) do
        local entry_id = get_server_id(entry)
        if entry_id and tostring(entry_id) == tostring(filter_id) then
            table.insert(out, entry)
            break
        end
    end
    return out
end

local function servers_import_enabled()
    local value = config and config.get_setting and config.get_setting("servers_import_enabled") or nil
    return value == true or value == 1 or value == "1" or tostring(value or ""):lower() == "true"
end

local function ensure_remote_servers_available(server, client)
    if remote_servers and type(remote_servers.probe) == "function" then
        return true
    end
    error_response(server, client, 500, "remote servers api is unavailable")
    return false
end

local function ensure_dvr_available(server, client)
    if dvr_store and type(dvr_store.upsert_stream) == "function" then
        return true
    end
    error_response(server, client, 500, "dvr api is unavailable")
    return false
end

local function check_remote_action_rate_limit(server, client, request, action, server_id)
    local ip = (request and request.addr) or "unknown"
    local limit = setting_number("rate_limit_remote_actions_per_min", 60)
    local window = setting_number("rate_limit_remote_actions_window_sec", 60)
    local key = tostring(ip) .. "|" .. tostring(action or "") .. "|" .. tostring(server_id or "")
    local ok, entry = rate_limit_check(rate_limits.remote_actions, key, limit, window)
    rate_limits.counter = (rate_limits.counter or 0) + 1
    if (rate_limits.counter % 200) == 0 then
        prune_rate_limits(rate_limits.remote_actions, window)
    end
    if ok then
        return true
    end
    local retry_after = (entry and entry.window_start)
        and math.max(1, (entry.window_start + window) - os.time())
        or window
    rate_limit_response(server, client, retry_after, "rate limited")
    return false
end

local function server_status_list(server, client, request)
    local admin = require_admin(request)
    if not admin then
        return error_response(server, client, 403, "forbidden")
    end
    if not ensure_remote_servers_available(server, client) then
        return
    end
    local filter_id = request and request.query and request.query.id or nil
    local list = list_server_entries(filter_id)
    if #list == 0 then
        return json_response(server, client, 200, { items = {} })
    end
    local results = {}
    local pending = #list
    local responded = false
    local function finish()
        if responded then return end
        responded = true
        json_response(server, client, 200, { items = results })
    end
    local function done(entry, ok, message, extra)
        local id = get_server_id(entry)
        if id then
            local row = {
                id = id,
                ok = ok and true or false,
                message = message or "",
                ts = os.time(),
            }
            if type(extra) == "table" then
                if extra.api_type_effective then
                    row.api_type_effective = extra.api_type_effective
                end
                if extra.remote_version then
                    row.remote_version = extra.remote_version
                end
            end
            local server_type = normalize_server_api_type(entry and (entry.api_type or entry.type) or "")
            if server_type == "dvr_v1" and dvr_store and type(dvr_store.get_remote_sync_health) == "function" then
                local health_ok, health = pcall(dvr_store.get_remote_sync_health, id)
                if health_ok and type(health) == "table" then
                    row.dvr_sync = health
                end
            end
            table.insert(results, row)
        end
        pending = pending - 1
        if pending <= 0 then
            finish()
        end
    end
    local max_parallel = 4
    local active = 0
    local index = 1

    local function launch_next()
        while active < max_parallel and index <= #list do
            local entry = list[index]
            index = index + 1
            if entry.enable == false or entry.enabled == false then
                done(entry, false, "disabled")
            else
                active = active + 1
                remote_servers.probe(entry, function(ok, payload, err, code)
                    active = math.max(0, active - 1)
                    if ok then
                        done(entry, true, "ok", payload)
                    else
                        local text = tostring(err or "error")
                        local status = remote_servers.classify_error_status
                            and remote_servers.classify_error_status(text, code)
                            or api._servers_classify_error_status(text, code)
                        done(entry, false, "http " .. tostring(status) .. ": " .. text)
                    end
                    if pending > 0 then
                        launch_next()
                    end
                end)
            end
        end
    end

    launch_next()
end

function api._servers_pull_streams(server, client, request)
    local admin = require_admin(request)
    if not admin then
        return error_response(server, client, 403, "forbidden")
    end
    if not servers_import_enabled() then
        return error_response(server, client, 410, "legacy servers pull is disabled (set settings.servers_import_enabled=true)")
    end
    local body = parse_json_body(request)
    if not body then
        return error_response(server, client, 400, "invalid json")
    end
    local entry, err = resolve_server_entry(body)
    if not entry then
        return error_response(server, client, 404, err or "server not found")
    end
    local cfg, cfg_err = normalize_server_host(entry)
    if not cfg then
        return error_response(server, client, 400, cfg_err or "invalid server")
    end
    local mode = tostring(body.mode or "merge")
    if mode ~= "merge" then
        return error_response(server, client, 400, "unsupported mode")
    end
    if not config or not config.import_astra then
        return error_response(server, client, 500, "config import unavailable")
    end

    remote_login(cfg, function(ok, cookie, login_err, login_code)
        if not ok then
            local text = tostring(login_err or "login failed")
            local code = api._servers_classify_error_status(text, login_code)
            return error_response(server, client, code, text)
        end
        api._servers_fetch_streams(cfg, cookie, function(ok2, data, fetch_err, fetch_code)
            if not ok2 then
                local text = tostring(fetch_err or "fetch failed")
                local code = api._servers_classify_error_status(text, fetch_code)
                return error_response(server, client, code, text)
            end

            local payload = { make_stream = {} }
            if type(data) == "table" and type(data.make_stream) == "table" then
                payload.make_stream = data.make_stream
            elseif type(data) == "table" then
                local list = data
                if type(data.items) == "table" then
                    list = data.items
                end
                for _, row in ipairs(list or {}) do
                    if type(row) == "table" and type(row.config) == "table" then
                        local cfgRow = row.config
                        cfgRow.enable = row.enabled
                        table.insert(payload.make_stream, cfgRow)
                    end
                end
            end

            if #payload.make_stream == 0 then
                return error_response(server, client, 400, "no streams received")
            end
            apply_config_change(server, client, request, {
                comment = "pull streams",
                defer_export = true,
                apply = function()
                    return config.import_astra(payload, { mode = "merge", transaction = true })
                end,
                success_builder = function(summary, revision_id)
                    return { status = "ok", revision_id = revision_id, summary = summary }
                end,
            })
        end)
    end)
end

function api._servers_list_streams(server, client, request)
    local admin = require_admin(request)
    if not admin then
        return error_response(server, client, 403, "forbidden")
    end
    if not ensure_remote_servers_available(server, client) then
        return
    end
    local body = parse_json_body(request)
    if not body then
        return error_response(server, client, 400, "invalid json")
    end
    local entry, err = resolve_server_entry(body)
    if not entry then
        return error_response(server, client, 404, err or "server not found")
    end
    local include_status = body.include_status ~= false

    remote_servers.list_streams(entry, {
        include_status = include_status,
    }, function(ok, payload, list_err, list_code)
        if not ok then
            local text = tostring(list_err or "fetch failed")
            local code = remote_servers.classify_error_status
                and remote_servers.classify_error_status(text, list_code)
                or api._servers_classify_error_status(text, list_code)
            return error_response(server, client, code, text)
        end
        local items = (type(payload) == "table" and type(payload.items) == "table") and payload.items or {}
        json_response(server, client, 200, {
            status = "ok",
            items = items,
            count = #items,
            capabilities = payload and payload.capabilities or {},
            api_type_effective = payload and payload.api_type_effective or "",
            remote_version = payload and payload.remote_version or "",
            auth_mode = payload and payload.auth_mode or "",
        })
    end)
end

function api._servers_get_stream(server, client, request)
    local admin = require_admin(request)
    if not admin then
        return error_response(server, client, 403, "forbidden")
    end
    if not ensure_remote_servers_available(server, client) then
        return
    end
    local body = parse_json_body(request)
    if not body then
        return error_response(server, client, 400, "invalid json")
    end
    local entry, err = resolve_server_entry(body)
    if not entry then
        return error_response(server, client, 404, err or "server not found")
    end
    local stream_id = tostring(body.stream_id or "")
    if stream_id == "" then
        return error_response(server, client, 400, "stream_id is required")
    end

    remote_servers.get_stream(entry, stream_id, function(ok, payload, fetch_err, fetch_code)
        if not ok then
            local text = tostring(fetch_err or "fetch failed")
            local code = remote_servers.classify_error_status
                and remote_servers.classify_error_status(text, fetch_code)
                or api._servers_classify_error_status(text, fetch_code)
            return error_response(server, client, code, text)
        end
        json_response(server, client, 200, payload or {
            id = stream_id,
            enabled = false,
            config = {},
        })
    end)
end

function api._servers_upsert_stream(server, client, request)
    local admin = require_admin(request)
    if not admin then
        return error_response(server, client, 403, "forbidden")
    end
    if not ensure_remote_servers_available(server, client) then
        return
    end
    local body = parse_json_body(request)
    if not body then
        return error_response(server, client, 400, "invalid json")
    end
    local entry, err = resolve_server_entry(body)
    if not entry then
        return error_response(server, client, 404, err or "server not found")
    end
    local stream = body.stream
    if type(stream) ~= "table" then
        return error_response(server, client, 400, "stream payload required")
    end
    local mode = tostring(body.mode or "upsert")
    if not check_remote_action_rate_limit(server, client, request, "upsert", tostring(entry.id or body.id or "")) then
        return
    end

    remote_servers.upsert_stream(entry, stream, mode, function(ok, payload, upsert_err, upsert_code)
        if not ok then
            local text = tostring(upsert_err or "upsert failed")
            local code = remote_servers.classify_error_status
                and remote_servers.classify_error_status(text, upsert_code)
                or api._servers_classify_error_status(text, upsert_code)
            return error_response(server, client, code, text)
        end
        audit_event("remote_stream_upsert", request, {
            actor_user_id = admin.id,
            actor_username = admin.username,
            ok = true,
            target = tostring(stream.id or ""),
            message = tostring(entry.id or body.id or ""),
        })
        json_response(server, client, 200, payload or { status = "ok" })
    end)
end

function api._servers_delete_stream(server, client, request)
    local admin = require_admin(request)
    if not admin then
        return error_response(server, client, 403, "forbidden")
    end
    if not ensure_remote_servers_available(server, client) then
        return
    end
    local body = parse_json_body(request)
    if not body then
        return error_response(server, client, 400, "invalid json")
    end
    local entry, err = resolve_server_entry(body)
    if not entry then
        return error_response(server, client, 404, err or "server not found")
    end
    local stream_id = tostring(body.stream_id or "")
    if stream_id == "" then
        return error_response(server, client, 400, "stream_id is required")
    end
    if not check_remote_action_rate_limit(server, client, request, "delete", tostring(entry.id or body.id or "")) then
        return
    end

    remote_servers.delete_stream(entry, stream_id, function(ok, payload, delete_err, delete_code)
        if not ok then
            local text = tostring(delete_err or "delete failed")
            local code = remote_servers.classify_error_status
                and remote_servers.classify_error_status(text, delete_code)
                or api._servers_classify_error_status(text, delete_code)
            return error_response(server, client, code, text)
        end
        audit_event("remote_stream_delete", request, {
            actor_user_id = admin.id,
            actor_username = admin.username,
            ok = true,
            target = stream_id,
            message = tostring(entry.id or body.id or ""),
        })
        json_response(server, client, 200, payload or { status = "ok" })
    end)
end

function api._servers_action_stream(server, client, request)
    local admin = require_admin(request)
    if not admin then
        return error_response(server, client, 403, "forbidden")
    end
    if not ensure_remote_servers_available(server, client) then
        return
    end
    local body = parse_json_body(request)
    if not body then
        return error_response(server, client, 400, "invalid json")
    end
    local entry, err = resolve_server_entry(body)
    if not entry then
        return error_response(server, client, 404, err or "server not found")
    end
    local stream_id = tostring(body.stream_id or "")
    if stream_id == "" then
        return error_response(server, client, 400, "stream_id is required")
    end
    local action = tostring(body.action or "")
    if action == "" then
        return error_response(server, client, 400, "action is required")
    end
    if not check_remote_action_rate_limit(server, client, request, action, tostring(entry.id or body.id or "")) then
        return
    end

    remote_servers.action(entry, stream_id, action, {
        input_index = body.input_index,
    }, function(ok, payload, action_err, action_code)
        if not ok then
            local text = tostring(action_err or "action failed")
            local code = remote_servers.classify_error_status
                and remote_servers.classify_error_status(text, action_code)
                or api._servers_classify_error_status(text, action_code)
            return error_response(server, client, code, text)
        end
        audit_event("remote_stream_action", request, {
            actor_user_id = admin.id,
            actor_username = admin.username,
            ok = true,
            target = stream_id,
            message = tostring(entry.id or body.id or "") .. ":" .. tostring(action),
        })
        json_response(server, client, 200, payload or { status = "ok", action = action })
    end)
end

function api._dvr_trim_text(value)
    return tostring(value or ""):gsub("^%s+", ""):gsub("%s+$", "")
end

function api._dvr_clone_json_table(value)
    if type(value) ~= "table" then
        return nil
    end
    local ok_encode, encoded = pcall(json.encode, value)
    if not ok_encode or type(encoded) ~= "string" or encoded == "" then
        return nil
    end
    local ok_decode, decoded = pcall(json.decode, encoded)
    if not ok_decode or type(decoded) ~= "table" then
        return nil
    end
    return decoded
end

function api._dvr_build_stream_config(stream_id, name, source_url, archive_path, retention_days, record_enabled, base_config)
    local sid = api._dvr_trim_text(stream_id)
    local src = api._dvr_trim_text(source_url)
    local title = api._dvr_trim_text(name)
    if title == "" then
        title = sid
    end
    local keep_days = math.max(1, math.floor(tonumber(retention_days) or 3))
    local enabled = record_enabled == true

    local base = api._dvr_clone_json_table(base_config) or {}
    local stream_type = api._dvr_trim_text(base.type)
    if stream_type == "" then
        stream_type = "spts"
    end

    -- Remote DVR channel must stay minimal and deterministic:
    -- one ingest source URL + local DVR metadata only.
    local cfg = {
        id = sid,
        name = title,
        type = stream_type,
        input = {},
        enable = enabled,
        enabled = enabled,
        backup_type = "disabled",
    }
    if src ~= "" then
        cfg.input[1] = src
    end

    local dvr_cfg = {}
    dvr_cfg.enabled = enabled
    dvr_cfg.retention_days = keep_days
    dvr_cfg.source_url = src
    dvr_cfg.mode = "local"
    dvr_cfg.backup_enabled = false
    if archive_path and api._dvr_trim_text(archive_path) ~= "" then
        dvr_cfg.path = archive_path
        dvr_cfg.archive_path = archive_path
    end
    cfg.dvr = dvr_cfg
    return cfg
end

function api._dvr_collect_stream_status_map(stream_ids)
    local ids = {}
    if type(stream_ids) == "table" then
        for _, value in ipairs(stream_ids) do
            local sid = api._dvr_trim_text(value)
            if sid ~= "" then
                ids[#ids + 1] = sid
            end
        end
    end
    if #ids == 0 then
        return {}
    end
    local map = {}
    if runtime and type(runtime.list_status_lite_ids) == "function" then
        local ok_runtime, runtime_map = pcall(runtime.list_status_lite_ids, ids)
        if ok_runtime and type(runtime_map) == "table" then
            map = runtime_map
        end
    end
    if dvr_store and type(dvr_store.list_runtime_status) == "function" then
        local ok_dvr, dvr_map = pcall(dvr_store.list_runtime_status, ids)
        if ok_dvr and type(dvr_map) == "table" then
            for sid, row in pairs(dvr_map) do
                if type(row) == "table" then
                    if type(map[sid]) ~= "table" then
                        map[sid] = row
                    else
                        local merged = map[sid]
                        if merged.on_air == nil then
                            merged.on_air = row.on_air
                        end
                        if merged.bitrate_kbps == nil then
                            merged.bitrate_kbps = row.bitrate_kbps or row.bitrate
                        end
                        if merged.raw_bitrate_kbps == nil then
                            merged.raw_bitrate_kbps = row.raw_bitrate_kbps or row.bitrate_kbps or row.bitrate
                        end
                        if merged.cc_errors == nil then
                            merged.cc_errors = row.cc_errors
                        end
                        if merged.pes_errors == nil then
                            merged.pes_errors = row.pes_errors
                        end
                        if merged.active_input_id == nil then
                            merged.active_input_id = row.active_input_id
                        end
                        if merged.active_input_index == nil then
                            merged.active_input_index = row.active_input_index
                        end
                        if merged.active_input_url == nil then
                            merged.active_input_url = row.active_input_url
                        end
                        if merged.uptime_sec == nil then
                            merged.uptime_sec = row.uptime_sec
                        end
                        if merged.updated_at == nil then
                            merged.updated_at = row.updated_at
                        end
                        if (merged.last_error == nil or api._dvr_trim_text(merged.last_error) == "")
                            and api._dvr_trim_text(row.last_error) ~= ""
                        then
                            merged.last_error = row.last_error
                        end
                    end
                end
            end
        end
    end
    return map
end

function api._dvr_apply_stream_status_row(item, status)
    if type(item) ~= "table" or type(status) ~= "table" then
        return
    end
    item.on_air = status.on_air == true
    item.bitrate_kbps = tonumber(status.bitrate_kbps or status.bitrate) or 0
    item.raw_bitrate_kbps = tonumber(status.raw_bitrate_kbps or status.bitrate_kbps or status.bitrate) or 0
    item.cc_errors = tonumber(status.cc_errors) or 0
    item.pes_errors = tonumber(status.pes_errors) or 0
    item.uptime_sec = tonumber(status.uptime_sec or status.uptime) or 0
    if status.active_input_id ~= nil then
        item.active_input = tonumber(status.active_input_id) or status.active_input_id
    elseif status.active_input ~= nil then
        item.active_input = tonumber(status.active_input) or status.active_input
    end
    if status.active_input_url ~= nil then
        item.active_input_url = tostring(status.active_input_url or "")
    end
    item.last_error = status.last_error and tostring(status.last_error) or nil
    item.updated_at = tonumber(status.updated_at) or os.time()
end

function api._dvr_collect_stream_ids(raw_ids)
    if type(raw_ids) ~= "table" then
        return {}
    end
    local ids = {}
    local seen = {}
    for _, value in ipairs(raw_ids) do
        local sid = api._dvr_trim_text(value)
        if sid ~= "" and not seen[sid] then
            ids[#ids + 1] = sid
            seen[sid] = true
        end
    end
    return ids
end

function api._dvr_normalize_origin_base_url(value)
    local raw = api._dvr_trim_text(value)
    if raw == "" then
        return nil, "origin_url is required"
    end
    if not raw:find("://", 1, true) then
        raw = "http://" .. raw
    end
    local parsed = parse_url(raw)
    if not parsed or not parsed.host then
        return nil, "invalid origin_url"
    end
    local scheme = tostring(parsed.format or "http"):lower()
    if scheme ~= "http" and scheme ~= "https" then
        return nil, "origin_url must be http or https"
    end
    local port = tonumber(parsed.port) or (scheme == "https" and 443 or 80)
    local path = tostring(parsed.path or "")
    if path == "/" then
        path = ""
    else
        path = path:gsub("/+$", "")
    end
    return scheme .. "://" .. tostring(parsed.host) .. ":" .. tostring(port) .. path
end

function api._dvr_is_self_origin_for_server(entry, normalized_origin_url)
    if type(entry) ~= "table" then
        return false
    end
    local target_host = api._dvr_trim_text(entry.host):lower()
    if target_host == "" then
        return false
    end
    local target_proto = api._dvr_trim_text(entry.proto):lower()
    if target_proto ~= "https" then
        target_proto = "http"
    end
    local target_port = tonumber(entry.port)
    if not target_port then
        target_port = target_proto == "https" and 443 or 80
    end

    local parsed_origin = parse_url(api._dvr_trim_text(normalized_origin_url))
    if not parsed_origin then
        return false
    end
    local origin_host = api._dvr_trim_text(parsed_origin.host):lower()
    if origin_host == "" then
        return false
    end
    local origin_proto = api._dvr_trim_text(parsed_origin.format or "http"):lower()
    if origin_proto ~= "https" then
        origin_proto = "http"
    end
    local origin_port = tonumber(parsed_origin.port)
    if not origin_port then
        origin_port = origin_proto == "https" and 443 or 80
    end

    return origin_host == target_host and origin_port == target_port
end

function api._dvr_encode_uri_component(value)
    local text = tostring(value or "")
    return (text:gsub("([^%w%-_%.~])", function(ch)
        return string.format("%%%02X", string.byte(ch))
    end))
end

function api._dvr_build_origin_play_url(origin_base, stream_id)
    local base = tostring(origin_base or ""):gsub("/+$", "")
    return base .. "/play/" .. api._dvr_encode_uri_component(stream_id)
end

function api._dvr_resolve_origin_url_from_entry(entry)
    local cfg, err = normalize_server_host(entry)
    if not cfg then
        return nil, err
    end
    local base_path = tostring(cfg.base_path or ""):gsub("/+$", "")
    return tostring(cfg.scheme or "http") .. "://" .. tostring(cfg.host) .. ":" .. tostring(cfg.port) .. base_path
end

function api._dvr_first_token(raw)
    if raw == nil then
        return nil
    end
    if type(raw) == "table" then
        for _, value in ipairs(raw) do
            local token = api._dvr_trim_text(value)
            if token ~= "" then
                return token
            end
        end
        return nil
    end
    local text = tostring(raw or "")
    for token in text:gmatch("([^,;]+)") do
        local trimmed = api._dvr_trim_text(token)
        if trimmed ~= "" then
            return trimmed
        end
    end
    return nil
end

function api._dvr_select_origin_play_token(body, entry)
    local explicit = nil
    if type(body) == "table" then
        explicit = api._dvr_trim_text(body.origin_play_token or body.origin_token or body.play_token)
        if explicit ~= "" then
            return explicit, "request"
        end
    end

    if type(entry) == "table" then
        local from_entry = api._dvr_trim_text(entry.origin_play_token or entry.origin_token or entry.play_token)
        if from_entry ~= "" then
            return from_entry, "server"
        end
    end

    local global_token = api._dvr_first_token(config and config.get_setting and config.get_setting("dvr_origin_play_token"))
    if global_token and global_token ~= "" then
        return global_token, "setting:dvr_origin_play_token"
    end

    local http_auth_token = api._dvr_first_token(config and config.get_setting and config.get_setting("http_auth_tokens"))
    if http_auth_token and http_auth_token ~= "" then
        return http_auth_token, "setting:http_auth_tokens"
    end
    return nil, "none"
end

function api._dvr_build_origin_play_url_with_token(origin_base, stream_id, token)
    local url = api._dvr_build_origin_play_url(origin_base, stream_id)
    local play_token = api._dvr_trim_text(token)
    if play_token == "" then
        return url
    end
    local separator = url:find("?", 1, true) and "&" or "?"
    return url .. separator .. "token=" .. api._dvr_encode_uri_component(play_token)
end

function api._dvr_select_origin_basic_auth(body, target_entry, origin_entry)
    local function pick(login, password, source)
        local user = api._dvr_trim_text(login)
        if user == "" then
            return nil, nil, nil
        end
        local pass = api._dvr_trim_text(password)
        return user, pass, source
    end

    if type(body) == "table" then
        local explicit_user = body.origin_login or body.origin_user or body.origin_username
        local explicit_pass = body.origin_password or body.origin_pass
        local user, pass, source = pick(explicit_user, explicit_pass, "request")
        if user then
            return user, pass, source
        end
    end

    if type(origin_entry) == "table" then
        local user, pass, source = pick(origin_entry.login, origin_entry.password, "origin_server")
        if user then
            return user, pass, source
        end
    end

    if type(target_entry) == "table" then
        local user, pass, source = pick(target_entry.origin_login, target_entry.origin_password, "server_origin")
        if user then
            return user, pass, source
        end
        user, pass, source = pick(target_entry.login, target_entry.password, "server")
        if user then
            return user, pass, source
        end
    end

    return nil, nil, "none"
end

function api._dvr_build_origin_play_url_with_auth(origin_base, stream_id, token, login, password)
    local play_token = api._dvr_trim_text(token)
    local user = api._dvr_trim_text(login)
    if user == "" then
        return api._dvr_build_origin_play_url_with_token(origin_base, stream_id, play_token)
    end

    local parsed = parse_url(origin_base)
    if not parsed or not parsed.host then
        return api._dvr_build_origin_play_url_with_token(origin_base, stream_id, play_token)
    end
    local scheme = tostring(parsed.format or "http"):lower()
    if scheme ~= "http" and scheme ~= "https" then
        scheme = "http"
    end
    local host = tostring(parsed.host or "")
    if host == "" then
        return api._dvr_build_origin_play_url_with_token(origin_base, stream_id, play_token)
    end
    local port = tonumber(parsed.port) or (scheme == "https" and 443 or 80)
    local path = tostring(parsed.path or "")
    if path == "/" then
        path = ""
    else
        path = path:gsub("/+$", "")
    end

    local auth = api._dvr_encode_uri_component(user)
    local pass = api._dvr_trim_text(password)
    if pass ~= "" then
        auth = auth .. ":" .. api._dvr_encode_uri_component(pass)
    end
    local base = scheme .. "://" .. auth .. "@" .. host .. ":" .. tostring(port) .. path
    return api._dvr_build_origin_play_url_with_token(base, stream_id, play_token)
end

function api._dvr_resolve_origin_url_from_request(request)
    local headers = request and request.headers or nil
    if type(headers) ~= "table" then
        return nil
    end

    local host = api._dvr_trim_text(get_header(headers, "x-forwarded-host") or get_header(headers, "host"))
    if host == "" then
        return nil
    end
    host = (host:match("^([^,%s]+)") or host)
    if host == "" then
        return nil
    end

    local proto = api._dvr_trim_text(
        get_header(headers, "x-forwarded-proto")
        or get_header(headers, "x-forwarded-scheme")
        or get_header(headers, "x-scheme")
    )
    if proto == "" then
        proto = "http"
    else
        proto = proto:match("^([^,%s]+)") or proto
    end
    proto = tostring(proto):lower()
    if proto ~= "http" and proto ~= "https" then
        proto = "http"
    end

    local normalized, _ = api._dvr_normalize_origin_base_url(proto .. "://" .. host)
    return normalized
end

function api._dvr_find_server_entry(server_id)
    local sid = api._dvr_trim_text(server_id)
    if sid == "" then
        return nil
    end
    if not (config and type(config.get_setting) == "function") then
        return nil
    end
    local rows = config.get_setting("servers")
    if type(rows) ~= "table" then
        return nil
    end
    for _, item in ipairs(rows) do
        if type(item) == "table" and api._dvr_trim_text(item.id) == sid then
            return item
        end
    end
    return nil
end

function api._dvr_is_stream_not_found_error(message, code)
    if tonumber(code) == 404 then
        return true
    end
    local text = tostring(message or ""):lower()
    return text:find("stream not found", 1, true) ~= nil
end

function api._dvr_sync_remote_stream_after_upsert(stream_id, cfg, request, callback)
    callback = callback or function() end
    local sid = api._dvr_trim_text(stream_id)
    if sid == "" then
        callback(false, nil, "stream id is required")
        return
    end
    if not remote_servers then
        callback(false, nil, "remote servers unavailable")
        return
    end
    if type(cfg) ~= "table" then
        callback(true, { skipped = true, reason = "missing config" })
        return
    end
    local dvr_cfg = type(cfg.dvr) == "table" and cfg.dvr or nil
    if type(dvr_cfg) ~= "table" then
        callback(true, { skipped = true, reason = "dvr config missing" })
        return
    end
    if api._dvr_trim_text(dvr_cfg.mode):lower() ~= "remote" then
        callback(true, { skipped = true, reason = "dvr mode is not remote" })
        return
    end
    local server_id = api._dvr_trim_text(dvr_cfg.remote_server_id)
    if server_id == "" then
        callback(false, nil, "remote dvr server is not selected")
        return
    end
    if type(remote_servers.dvr_bulk_record) ~= "function" then
        callback(false, nil, "remote dvr bulk record api unavailable")
        return
    end
    local entry = api._dvr_find_server_entry(server_id)
    if type(entry) ~= "table" then
        callback(false, nil, "remote dvr server not found: " .. server_id)
        return
    end
    local stype = normalize_server_api_type(entry.api_type or entry.type)
    if stype ~= "dvr_v1" then
        callback(false, nil, "target server must have type DVR")
        return
    end

    local retention_days = math.max(1, math.floor(tonumber(dvr_cfg.retention_days) or 3))
    local archive_path = api._dvr_trim_text(dvr_cfg.path or dvr_cfg.archive_path)
    if archive_path == "" then
        archive_path = nil
    end
    local remote_channel_enabled = true
    if dvr_cfg.remote_channel_enabled ~= nil then
        remote_channel_enabled = boolish(dvr_cfg.remote_channel_enabled)
    end
    local archive_enabled = boolish(dvr_cfg.enabled) or boolish(dvr_cfg.archive_enabled)
    local backup_enabled = boolish(dvr_cfg.backup_enabled)
    local remote_stream_id = api._dvr_trim_text(dvr_cfg.remote_stream_id)
    if remote_stream_id == "" then
        remote_stream_id = sid
    end
    local should_record = remote_channel_enabled and (archive_enabled or backup_enabled)

    local origin_url = api._dvr_resolve_origin_url_from_request(request) or ""
    if origin_url == "" then
        local default_port = tonumber(config and config.get_setting and config.get_setting("http_play_port") or nil)
            or tonumber(config and config.get_setting and config.get_setting("http_port") or nil)
            or 8000
        origin_url = "http://127.0.0.1:" .. tostring(default_port)
    end
    local normalized_origin, origin_err = api._dvr_normalize_origin_base_url(origin_url)
    if not normalized_origin then
        callback(false, nil, origin_err or "invalid origin url")
        return
    end
    local origin_play_token, _ = api._dvr_select_origin_play_token(dvr_cfg, entry)
    local origin_login, origin_password = api._dvr_select_origin_basic_auth(dvr_cfg, entry, nil)
    if api._dvr_trim_text(origin_play_token) ~= "" then
        origin_login = nil
        origin_password = nil
    end
    local source_url = api._dvr_build_origin_play_url_with_auth(
        normalized_origin,
        sid,
        origin_play_token,
        origin_login,
        origin_password
    )
    local stream_name = api._dvr_trim_text(cfg.name or sid)
    local stream_payload = {
        stream_id = remote_stream_id,
        name = stream_name ~= "" and stream_name or sid,
        source_url = source_url,
        record_enabled = should_record,
        retention_days = retention_days,
        segment_sec = 3600,
        config = api._dvr_build_stream_config(
            remote_stream_id,
            stream_name,
            source_url,
            archive_path,
            retention_days,
            should_record,
            cfg
        ),
    }
    if archive_path then
        stream_payload.archive_path = archive_path
    end

    local function run_bulk_record()
        remote_servers.dvr_bulk_record(entry, {
            stream_ids = { remote_stream_id },
            record_enabled = should_record,
            retention_days = retention_days,
        }, function(ok_record, payload_record, record_err, record_code)
            if not ok_record then
                if (not remote_channel_enabled)
                    and api._dvr_is_stream_not_found_error(record_err, record_code)
                then
                    return callback(true, {
                        ok = true,
                        skipped = true,
                        warning = "remote stream not found",
                    })
                end
                return callback(false, nil, tostring(record_err or "remote dvr record sync failed"))
            end
            if remote_channel_enabled
                and dvr_store
                and type(dvr_store.upsert_remote_link) == "function"
            then
                dvr_store.upsert_remote_link({
                    stream_id = sid,
                    dvr_server_id = server_id,
                    dvr_stream_id = remote_stream_id,
                    source_play_url = source_url,
                    updated_ts = os.time(),
                })
            end
            callback(true, payload_record or {
                ok = true,
                affected = 1,
            })
        end)
    end

    if not remote_channel_enabled then
        run_bulk_record()
        return
    end

    if type(remote_servers.dvr_upsert_streams) ~= "function" then
        callback(false, nil, "remote dvr import api unavailable")
        return
    end
    remote_servers.dvr_upsert_streams(entry, { stream_payload }, function(ok_import, payload_import, import_err)
        if not ok_import then
            return callback(false, nil, tostring(import_err or "remote dvr import failed"))
        end
        run_bulk_record()
    end)
end

function api._dvr_get_storage_candidates(refresh)
    if not dvr_store or type(dvr_store.storage_candidates) ~= "function" then
        return {
            recommended_path = nil,
            candidates = {},
        }
    end
    local payload = dvr_store.storage_candidates({
        refresh = refresh == true,
    })
    if type(payload) ~= "table" then
        return {
            recommended_path = nil,
            candidates = {},
        }
    end
    local candidates = type(payload.candidates) == "table" and payload.candidates or {}
    local recommended = api._dvr_trim_text(payload.recommended_path)
    if recommended == "" and #candidates > 0 then
        recommended = api._dvr_trim_text(candidates[1] and candidates[1].path)
    end
    if recommended == "" then
        recommended = nil
    end
    return {
        recommended_path = recommended,
        candidates = candidates,
    }
end

function api._dvr_health(server, client, request)
    if not require_admin(request) then
        return error_response(server, client, 403, "forbidden")
    end
    if not ensure_dvr_available(server, client) then
        return
    end
    json_response(server, client, 200, {
        status = "ok",
        service = "dvr_v1",
        version = astra.version,
        ts = os.time(),
    })
end

function api._dvr_storage_candidates_get(server, client, request)
    if not require_admin(request) then
        return error_response(server, client, 403, "forbidden")
    end
    if not ensure_dvr_available(server, client) then
        return
    end
    local refresh = false
    if request and request.query and request.query.refresh ~= nil then
        refresh = tostring(request.query.refresh or "") == "1"
            or tostring(request.query.refresh or ""):lower() == "true"
    end
    local payload = api._dvr_get_storage_candidates(refresh)
    json_response(server, client, 200, {
        ok = true,
        recommended_path = payload.recommended_path,
        candidates = payload.candidates,
    })
end

function api._dvr_streams_upsert(server, client, request)
    if not require_admin(request) then
        return error_response(server, client, 403, "forbidden")
    end
    if not ensure_dvr_available(server, client) then
        return
    end
    local body = parse_json_body(request)
    if not body then
        return error_response(server, client, 400, "invalid json")
    end
    local stream_id = api._dvr_trim_text(body.stream_id or body.id)
    local source_url = api._dvr_trim_text(body.source_url)
    local archive_path = api._dvr_trim_text(body.archive_path or body.path)
    if stream_id == "" then
        return error_response(server, client, 400, "stream_id is required")
    end
    if source_url == "" then
        return error_response(server, client, 400, "source_url is required")
    end
    if archive_path == "" then
        local storage = api._dvr_get_storage_candidates(false)
        archive_path = api._dvr_trim_text(storage and storage.recommended_path)
    end
    if archive_path == "" then
        archive_path = nil
    end
    local retention_days = tonumber(body.retention_days) or 3
    local record_enabled = body.record_enabled == true or body.record_enabled == 1 or body.record_enabled == "1"
    local base_config = nil
    if type(body.config) == "table" then
        base_config = body.config
    elseif body.config_json ~= nil then
        local text = api._dvr_trim_text(body.config_json)
        if text ~= "" then
            local ok_cfg, decoded_cfg = pcall(json.decode, text)
            if ok_cfg and type(decoded_cfg) == "table" then
                base_config = decoded_cfg
            end
        end
    end
    local normalized_config = api._dvr_build_stream_config(
        stream_id,
        body.name or stream_id,
        source_url,
        archive_path,
        retention_days,
        record_enabled,
        base_config
    )
    local res, err = dvr_store.upsert_stream({
        stream_id = stream_id,
        name = body.name or stream_id,
        source_url = source_url,
        archive_path = archive_path,
        config = normalized_config,
        retention_days = math.max(1, math.floor(retention_days)),
        record_enabled = record_enabled,
        segment_sec = 3600,
        recording_paused = body.recording_paused == true,
        last_mode = body.last_mode,
        last_state_seq = body.last_state_seq,
        last_reason = body.last_reason,
    })
    if not res then
        return error_response(server, client, 400, tostring(err or "upsert failed"))
    end
    local item = dvr_store.get_stream(stream_id)
    json_response(server, client, 200, {
        ok = true,
        status = "ok",
        stream_id = stream_id,
        created = res.created == true,
        updated = res.updated == true,
        item = item,
    })
end

function api._dvr_streams_get(server, client, request)
    if not require_admin(request) then
        return error_response(server, client, 403, "forbidden")
    end
    if not ensure_dvr_available(server, client) then
        return
    end
    local stream_id = request and request.query and request.query.stream_id or nil
    if (not stream_id or stream_id == "") and request and request.method == "POST" then
        local body = parse_json_body(request)
        if body then
            stream_id = body.stream_id or body.id
        end
    end
    stream_id = api._dvr_trim_text(stream_id)
    if stream_id == "" then
        return error_response(server, client, 400, "stream_id is required")
    end
    local item = dvr_store.get_stream(stream_id)
    if not item then
        return error_response(server, client, 404, "stream not found")
    end
    item.config = api._dvr_build_stream_config(
        stream_id,
        item.name or stream_id,
        item.source_url,
        item.archive_path,
        item.retention_days,
        item.record_enabled == true,
        item.config
    )
    local status_map = api._dvr_collect_stream_status_map({ stream_id })
    local status = status_map[stream_id]
    if type(status) == "table" then
        api._dvr_apply_stream_status_row(item, status)
    end
    json_response(server, client, 200, { ok = true, item = item })
end

function api._dvr_streams_list(server, client, request)
    if not require_admin(request) then
        return error_response(server, client, 403, "forbidden")
    end
    if not ensure_dvr_available(server, client) then
        return
    end
    local body = parse_json_body(request) or {}
    local include_status = body.include_status ~= false
    local stream_ids = type(body.stream_ids) == "table" and body.stream_ids or nil
    local limit = tonumber(body.limit) or 5000
    local items = dvr_store.list_streams({
        stream_ids = stream_ids,
        limit = limit,
    }) or {}
    local ids = {}
    for _, item in ipairs(items) do
        ids[#ids + 1] = item.stream_id
        item.config = api._dvr_build_stream_config(
            item.stream_id,
            item.name or item.stream_id,
            item.source_url,
            item.archive_path,
            item.retention_days,
            item.record_enabled == true,
            item.config
        )
    end
    if include_status then
        local status_map = api._dvr_collect_stream_status_map(ids)
        for _, item in ipairs(items) do
            local status = status_map[item.stream_id]
            if type(status) == "table" then
                api._dvr_apply_stream_status_row(item, status)
            end
        end
    end
    json_response(server, client, 200, {
        ok = true,
        status = "ok",
        items = items,
        total = #items,
        api_type_effective = "dvr_v1",
    })
end

function api._dvr_streams_delete(server, client, request)
    if not require_admin(request) then
        return error_response(server, client, 403, "forbidden")
    end
    if not ensure_dvr_available(server, client) then
        return
    end
    local body = parse_json_body(request)
    if not body then
        return error_response(server, client, 400, "invalid json")
    end
    local stream_id = api._dvr_trim_text(body.stream_id or body.id)
    if stream_id == "" then
        return error_response(server, client, 400, "stream_id is required")
    end
    local ok, err = dvr_store.delete_stream(stream_id)
    if not ok then
        return error_response(server, client, 400, tostring(err or "delete failed"))
    end
    json_response(server, client, 200, { ok = true, status = "ok", stream_id = stream_id })
end

function api._dvr_streams_bulk_record(server, client, request)
    if not require_admin(request) then
        return error_response(server, client, 403, "forbidden")
    end
    if not ensure_dvr_available(server, client) then
        return
    end
    local body = parse_json_body(request)
    if not body then
        return error_response(server, client, 400, "invalid json")
    end
    local stream_ids = type(body.stream_ids) == "table" and body.stream_ids or {}
    if #stream_ids == 0 then
        return error_response(server, client, 400, "stream_ids is required")
    end
    local has_record_enabled = body.record_enabled ~= nil
    local record_enabled = nil
    if has_record_enabled then
        record_enabled = body.record_enabled == true or body.record_enabled == 1 or body.record_enabled == "1"
    end
    if not has_record_enabled and body.retention_days == nil then
        return error_response(server, client, 400, "record_enabled or retention_days is required")
    end
    local result = dvr_store.bulk_record({
        stream_ids = stream_ids,
        record_enabled = record_enabled,
        retention_days = body.retention_days,
    })
    json_response(server, client, 200, result or {
        ok = false,
        affected = 0,
        errors = { { error = "bulk record failed" } },
    })
end

function api._dvr_ingest_state(server, client, request)
    if not require_admin(request) then
        return error_response(server, client, 403, "forbidden")
    end
    if not ensure_dvr_available(server, client) then
        return
    end
    local body = parse_json_body(request)
    if not body then
        return error_response(server, client, 400, "invalid json")
    end
    local result, err = dvr_store.apply_ingest_state(body)
    if not result then
        return error_response(server, client, 400, tostring(err or "ingest-state failed"))
    end
    json_response(server, client, 200, {
        ok = true,
        applied = result.applied == true,
        ignored_duplicate = result.ignored_duplicate == true,
        current_mode = result.mode or "LIVE",
        recording_paused = result.recording_paused == true,
        state = result,
    })
end

function api._dvr_backup_state_get(server, client, request)
    if not require_admin(request) then
        return error_response(server, client, 403, "forbidden")
    end
    if not ensure_dvr_available(server, client) then
        return
    end
    local stream_id = api._dvr_trim_text(request and request.query and request.query.stream_id)
    if stream_id == "" then
        return error_response(server, client, 400, "stream_id is required")
    end
    local state_row = dvr_store.get_backup_state_for_api(stream_id)
    json_response(server, client, 200, state_row or { stream_id = stream_id, mode = "LIVE" })
end

function api._dvr_archive_get(server, client, request)
    if not require_admin(request) then
        return error_response(server, client, 403, "forbidden")
    end
    if not ensure_dvr_available(server, client) then
        return
    end
    local stream_id = api._dvr_trim_text(request and request.query and request.query.stream_id)
    if stream_id == "" then
        return error_response(server, client, 400, "stream_id is required")
    end
    local from_ts = tonumber(request and request.query and request.query.from)
    local to_ts = tonumber(request and request.query and request.query.to)
    local include_partial = (request and request.query and request.query.include_partial) == "1"
    local limit = tonumber(request and request.query and request.query.limit) or 1000
    local items = dvr_store.list_segments(stream_id, from_ts, to_ts, include_partial, limit) or {}
    json_response(server, client, 200, {
        items = items,
        total = #items,
    })
end

function api._dvr_backup_cursor_reset(server, client, request)
    if not require_admin(request) then
        return error_response(server, client, 403, "forbidden")
    end
    if not ensure_dvr_available(server, client) then
        return
    end
    local body = parse_json_body(request)
    if not body then
        return error_response(server, client, 400, "invalid json")
    end
    local stream_id = api._dvr_trim_text(body.stream_id)
    if stream_id == "" then
        return error_response(server, client, 400, "stream_id is required")
    end
    local state_row, err = dvr_store.cursor_reset(stream_id)
    if not state_row then
        return error_response(server, client, 400, tostring(err or "cursor reset failed"))
    end
    json_response(server, client, 200, {
        ok = true,
        state = state_row,
    })
end

function api._dvr_backup_cycle_rebuild(server, client, request)
    if not require_admin(request) then
        return error_response(server, client, 403, "forbidden")
    end
    if not ensure_dvr_available(server, client) then
        return
    end
    local body = parse_json_body(request)
    if not body then
        return error_response(server, client, 400, "invalid json")
    end
    local stream_id = api._dvr_trim_text(body.stream_id)
    if stream_id == "" then
        return error_response(server, client, 400, "stream_id is required")
    end
    local state_row, err = dvr_store.rebuild_cycle_and_set_cursor(stream_id, {
        include_partial = body.include_partial ~= false,
        min_partial_sec = body.min_partial_sec,
        start_mode = body.start_mode,
        start_offset_hours = body.start_offset_hours,
        now_ts = body.now_ts,
    })
    if not state_row then
        return error_response(server, client, 400, tostring(err or "cycle rebuild failed"))
    end
    json_response(server, client, 200, {
        ok = true,
        cycle_id = state_row.cycle_id,
        first_seg_start_ts = state_row.cursor_seg_start_ts,
        state = state_row,
    })
end

function api._dvr_backup_cursor_reset_bulk(server, client, request)
    if not require_admin(request) then
        return error_response(server, client, 403, "forbidden")
    end
    if not ensure_dvr_available(server, client) then
        return
    end
    local body = parse_json_body(request)
    if not body then
        return error_response(server, client, 400, "invalid json")
    end
    local stream_ids = api._dvr_collect_stream_ids(body.stream_ids)
    if #stream_ids == 0 then
        return error_response(server, client, 400, "stream_ids is required")
    end
    local items = {}
    local failed = {}
    local affected = 0
    for _, stream_id in ipairs(stream_ids) do
        local state_row, err = dvr_store.cursor_reset(stream_id)
        if state_row then
            affected = affected + 1
            items[#items + 1] = {
                stream_id = stream_id,
                state = state_row,
            }
        else
            failed[#failed + 1] = {
                stream_id = stream_id,
                error = tostring(err or "cursor reset failed"),
            }
        end
    end
    json_response(server, client, 200, {
        ok = true,
        total = #stream_ids,
        affected = affected,
        failed = failed,
        items = items,
    })
end

function api._dvr_backup_cycle_rebuild_bulk(server, client, request)
    if not require_admin(request) then
        return error_response(server, client, 403, "forbidden")
    end
    if not ensure_dvr_available(server, client) then
        return
    end
    local body = parse_json_body(request)
    if not body then
        return error_response(server, client, 400, "invalid json")
    end
    local stream_ids = api._dvr_collect_stream_ids(body.stream_ids)
    if #stream_ids == 0 then
        return error_response(server, client, 400, "stream_ids is required")
    end
    local items = {}
    local failed = {}
    local affected = 0
    local include_partial = body.include_partial ~= false
    local min_partial_sec = body.min_partial_sec
    local start_mode = body.start_mode
    local start_offset_hours = body.start_offset_hours
    local now_ts = body.now_ts
    for _, stream_id in ipairs(stream_ids) do
        local state_row, err = dvr_store.rebuild_cycle_and_set_cursor(stream_id, {
            include_partial = include_partial,
            min_partial_sec = min_partial_sec,
            start_mode = start_mode,
            start_offset_hours = start_offset_hours,
            now_ts = now_ts,
        })
        if state_row then
            affected = affected + 1
            items[#items + 1] = {
                stream_id = stream_id,
                cycle_id = state_row.cycle_id,
                first_seg_start_ts = state_row.cursor_seg_start_ts,
                state = state_row,
            }
        else
            failed[#failed + 1] = {
                stream_id = stream_id,
                error = tostring(err or "cycle rebuild failed"),
            }
        end
    end
    json_response(server, client, 200, {
        ok = true,
        total = #stream_ids,
        affected = affected,
        failed = failed,
        items = items,
    })
end

function api._dvr_backup_next_segment(server, client, request)
    if not require_admin(request) then
        return error_response(server, client, 403, "forbidden")
    end
    if not ensure_dvr_available(server, client) then
        return
    end
    local body = nil
    local stream_id = api._dvr_trim_text(request and request.query and request.query.stream_id)
    if request and request.method == "POST" then
        body = parse_json_body(request)
        if body and stream_id == "" then
            stream_id = api._dvr_trim_text(body.stream_id)
        end
    end
    if stream_id == "" then
        return error_response(server, client, 400, "stream_id is required")
    end
    local include_partial = true
    local min_partial_sec = nil
    local allow_cycle_restart = true
    local start_mode = nil
    local start_offset_hours = nil
    local now_ts = nil
    if request and request.query then
        if request.query.include_partial ~= nil then
            include_partial = request.query.include_partial ~= "0"
        end
        min_partial_sec = tonumber(request.query.min_partial_sec)
        if request.query.allow_cycle_restart ~= nil then
            allow_cycle_restart = request.query.allow_cycle_restart ~= "0"
        end
        if request.query.start_mode ~= nil then
            start_mode = tostring(request.query.start_mode)
        end
        if request.query.start_offset_hours ~= nil then
            start_offset_hours = tonumber(request.query.start_offset_hours)
        end
        if request.query.now_ts ~= nil then
            now_ts = tonumber(request.query.now_ts)
        end
    end
    if body then
        if body.include_partial ~= nil then
            include_partial = body.include_partial ~= false
        end
        if body.min_partial_sec ~= nil then
            min_partial_sec = tonumber(body.min_partial_sec)
        end
        if body.allow_cycle_restart ~= nil then
            allow_cycle_restart = body.allow_cycle_restart ~= false
        end
        if body.start_mode ~= nil then
            start_mode = tostring(body.start_mode)
        end
        if body.start_offset_hours ~= nil then
            start_offset_hours = tonumber(body.start_offset_hours)
        end
        if body.now_ts ~= nil then
            now_ts = tonumber(body.now_ts)
        end
    end
    local selected, err = dvr_store.backup_select_segment(stream_id, {
        include_partial = include_partial,
        min_partial_sec = min_partial_sec,
        allow_cycle_restart = allow_cycle_restart,
        start_mode = start_mode,
        start_offset_hours = start_offset_hours,
        now_ts = now_ts,
    })
    if not selected then
        return error_response(server, client, 404, tostring(err or "no backup segment available"))
    end
    json_response(server, client, 200, {
        ok = true,
        stream_id = stream_id,
        cycle_restarted = selected.cycle_restarted == true,
        segment = selected.segment,
        state = selected.state,
    })
end

function api._dvr_backup_progress(server, client, request)
    if not require_admin(request) then
        return error_response(server, client, 403, "forbidden")
    end
    if not ensure_dvr_available(server, client) then
        return
    end
    local body = parse_json_body(request)
    if not body then
        return error_response(server, client, 400, "invalid json")
    end
    local stream_id = api._dvr_trim_text(body.stream_id)
    if stream_id == "" then
        return error_response(server, client, 400, "stream_id is required")
    end
    local result, err = dvr_store.backup_commit_progress(stream_id, {
        seg_start_ts = body.seg_start_ts,
        played_sec = body.played_sec,
        done = body.done,
        skip = body.skip,
        include_partial = body.include_partial,
        min_partial_sec = body.min_partial_sec,
        allow_cycle_restart = body.allow_cycle_restart,
        segment_guard_sec = body.segment_guard_sec,
        start_mode = body.start_mode,
        start_offset_hours = body.start_offset_hours,
        now_ts = body.now_ts,
    })
    if not result then
        return error_response(server, client, 400, tostring(err or "progress commit failed"))
    end
    json_response(server, client, 200, result)
end

function api._dvr_resolve_server_entry(body)
    local entry, err = resolve_server_entry(body)
    if not entry then
        return nil, err
    end
    local stype = normalize_server_api_type(entry.api_type or entry.type)
    if stype ~= "dvr_v1" then
        return nil, "target server must have type DVR"
    end
    return entry
end

function api._servers_dvr_storage_candidates(server, client, request)
    local admin = require_admin(request)
    if not admin then
        return error_response(server, client, 403, "forbidden")
    end
    if not ensure_remote_servers_available(server, client) then
        return
    end
    local body = parse_json_body(request)
    if not body then
        return error_response(server, client, 400, "invalid json")
    end
    local entry, err = api._dvr_resolve_server_entry(body)
    if not entry then
        return error_response(server, client, 400, err or "server not found")
    end
    remote_servers.dvr_storage_candidates(entry, {
        refresh = body.refresh == true,
    }, function(ok, payload, action_err, action_code)
        if not ok then
            local text = tostring(action_err or "storage candidates failed")
            local code = remote_servers.classify_error_status
                and remote_servers.classify_error_status(text, action_code)
                or api._servers_classify_error_status(text, action_code)
            return error_response(server, client, code, text)
        end
        local data = type(payload) == "table" and payload or {}
        json_response(server, client, 200, {
            ok = true,
            recommended_path = api._dvr_trim_text(data.recommended_path),
            candidates = type(data.candidates) == "table" and data.candidates or {},
        })
    end)
end

function api._servers_dvr_import_streams(server, client, request)
    local admin = require_admin(request)
    if not admin then
        return error_response(server, client, 403, "forbidden")
    end
    if not ensure_remote_servers_available(server, client) then
        return
    end
    if not ensure_dvr_available(server, client) then
        return
    end
    local body = parse_json_body(request)
    if not body then
        return error_response(server, client, 400, "invalid json")
    end
    local entry, err = api._dvr_resolve_server_entry(body)
    if not entry then
        return error_response(server, client, 400, err or "server not found")
    end
    local origin_url = api._dvr_trim_text(body.origin_url)
    local origin_entry = nil
    if origin_url == "" and body.origin_server_id and config and config.get_setting then
        local servers = config.get_setting("servers")
        if type(servers) == "table" then
            for _, item in ipairs(servers) do
                if tostring(item and item.id or "") == tostring(body.origin_server_id) then
                    origin_entry = item
                    origin_url = api._dvr_resolve_origin_url_from_entry(item) or ""
                    break
                end
            end
        end
    end
    if origin_url == "" then
        origin_url = api._dvr_resolve_origin_url_from_request(request) or ""
    end
    local normalized_origin, origin_err = api._dvr_normalize_origin_base_url(origin_url)
    if not normalized_origin then
        return error_response(server, client, 400, origin_err or "invalid origin_url")
    end
    if body.allow_self_origin ~= true
        and api._dvr_is_self_origin_for_server(entry, normalized_origin)
    then
        return error_response(server, client, 400,
            "origin_url points to selected DVR server; choose origin stream server")
    end
    local rows = config and config.list_streams and config.list_streams() or {}
    local descriptors = {}
    local selected_ids = {}
    local origin_play_token, origin_play_token_source = api._dvr_select_origin_play_token(body, entry)
    local origin_login, origin_password, origin_auth_source = api._dvr_select_origin_basic_auth(body, entry, origin_entry)
    if api._dvr_trim_text(origin_play_token) ~= "" then
        origin_login = nil
        origin_password = nil
        origin_auth_source = "token"
    end
    local explicit_archive_path = api._dvr_trim_text(body.archive_path or body.path)
    if type(body.stream_ids) == "table" and #body.stream_ids > 0 then
        for _, value in ipairs(body.stream_ids) do
            local sid = api._dvr_trim_text(value)
            if sid ~= "" then
                selected_ids[sid] = true
            end
        end
    end
    local import_all = body.import_all == true or next(selected_ids) == nil
    for _, row in ipairs(rows) do
        local cfg_row = type(row and row.config) == "table" and row.config or {}
        local sid_row = api._dvr_trim_text(row and row.id)
        local sid_cfg = api._dvr_trim_text(cfg_row and cfg_row.id)
        local sid_effective = sid_row
        local selected = import_all

        if not import_all then
            if sid_row ~= "" and selected_ids[sid_row] == true then
                sid_effective = sid_row
                selected = true
            elseif sid_cfg ~= "" and selected_ids[sid_cfg] == true then
                sid_effective = sid_cfg
                selected = true
            end
        else
            if sid_effective == "" then
                sid_effective = sid_cfg
            end
        end

        if selected and sid_effective ~= "" then
            local dvr_cfg = type(cfg_row.dvr) == "table" and cfg_row.dvr or {}
            descriptors[#descriptors + 1] = {
                stream_id = sid_effective,
                name = api._dvr_trim_text(cfg_row.name or sid_effective),
                source_url = api._dvr_build_origin_play_url_with_auth(
                    normalized_origin,
                    sid_effective,
                    origin_play_token,
                    origin_login,
                    origin_password
                ),
                local_archive_path = api._dvr_trim_text(dvr_cfg.path or dvr_cfg.archive_path),
                config = api._dvr_clone_json_table(cfg_row),
            }
        end
    end
    if #descriptors == 0 then
        return error_response(server, client, 400, "no streams selected")
    end

    local function build_import_items(default_archive_path)
        local items = {}
        for _, item in ipairs(descriptors) do
            local archive_path = explicit_archive_path
            if archive_path == "" then
                archive_path = item.local_archive_path
            end
            if archive_path == "" then
                archive_path = api._dvr_trim_text(default_archive_path)
            end
            local retention_days = tonumber(body.retention_days) or 3
            local payload = {
                stream_id = item.stream_id,
                name = item.name,
                source_url = item.source_url,
                record_enabled = false,
                retention_days = retention_days,
                segment_sec = 3600,
                config = api._dvr_build_stream_config(
                    item.stream_id,
                    item.name,
                    item.source_url,
                    archive_path ~= "" and archive_path or nil,
                    retention_days,
                    false,
                    item.config
                ),
            }
            if archive_path ~= "" then
                payload.archive_path = archive_path
            end
            items[#items + 1] = payload
        end
        return items
    end

    local function execute_import(default_archive_path, storage_source, storage_warning)
        local selected = build_import_items(default_archive_path)
        remote_servers.dvr_upsert_streams(entry, selected, function(ok, payload, upsert_err, upsert_code)
            if not ok then
                local text = tostring(upsert_err or "import failed")
                local code = remote_servers.classify_error_status
                    and remote_servers.classify_error_status(text, upsert_code)
                    or api._servers_classify_error_status(text, upsert_code)
                return error_response(server, client, code, text)
            end
            local imported = tonumber(payload and payload.imported) or 0
            local failed = type(payload and payload.failed) == "table" and payload.failed or {}
            local failed_map = {}
            for _, item in ipairs(failed) do
                local fsid = api._dvr_trim_text(item and item.stream_id)
                if fsid ~= "" then
                    failed_map[fsid] = true
                end
            end
            for _, row in ipairs(selected) do
                if not failed_map[row.stream_id] then
                    dvr_store.upsert_remote_link({
                        stream_id = row.stream_id,
                        dvr_server_id = tostring(entry.id or body.id or ""),
                        dvr_stream_id = row.stream_id,
                        source_play_url = row.source_url,
                        updated_ts = os.time(),
                    })
                end
            end
            json_response(server, client, 200, {
                ok = true,
                total = #selected,
                imported = imported,
                skipped = math.max(0, #selected - imported - #failed),
                failed = failed,
                origin_url = normalized_origin,
                archive_default_path = default_archive_path,
                archive_path_source = storage_source,
                origin_play_token_source = origin_play_token_source,
                origin_auth_source = origin_auth_source,
                storage_warning = storage_warning,
            })
        end)
    end

    local auto_archive_path = body.auto_archive_path ~= false
    if explicit_archive_path ~= "" or auto_archive_path == false then
        return execute_import(nil, explicit_archive_path ~= "" and "request" or "disabled", nil)
    end

    remote_servers.dvr_storage_candidates(entry, {
        refresh = body.storage_refresh == true,
    }, function(ok_storage, storage_payload, storage_err)
        local recommended = nil
        if ok_storage and type(storage_payload) == "table" then
            recommended = api._dvr_trim_text(storage_payload.recommended_path)
        end
        if recommended == "" then
            recommended = nil
        end
        local storage_warning = nil
        local storage_source = nil
        if recommended then
            storage_source = "remote_auto"
        elseif not ok_storage then
            storage_warning = tostring(storage_err or "remote storage detection failed")
            storage_source = "fallback"
        else
            storage_source = "none"
        end
        execute_import(recommended, storage_source, storage_warning)
    end)
end

function api._servers_dvr_record_bulk(server, client, request)
    local admin = require_admin(request)
    if not admin then
        return error_response(server, client, 403, "forbidden")
    end
    if not ensure_remote_servers_available(server, client) then
        return
    end
    local body = parse_json_body(request)
    if not body then
        return error_response(server, client, 400, "invalid json")
    end
    local entry, err = api._dvr_resolve_server_entry(body)
    if not entry then
        return error_response(server, client, 400, err or "server not found")
    end
    local stream_ids = type(body.stream_ids) == "table" and body.stream_ids or {}
    if #stream_ids == 0 then
        return error_response(server, client, 400, "stream_ids is required")
    end
    local has_record_enabled = body.record_enabled ~= nil
    local record_enabled = nil
    if has_record_enabled then
        record_enabled = body.record_enabled == true or body.record_enabled == 1 or body.record_enabled == "1"
    end
    if not has_record_enabled and body.retention_days == nil then
        return error_response(server, client, 400, "record_enabled or retention_days is required")
    end
    remote_servers.dvr_bulk_record(entry, {
        stream_ids = stream_ids,
        record_enabled = record_enabled,
        retention_days = body.retention_days,
    }, function(ok, payload, action_err, action_code)
        if not ok then
            local text = tostring(action_err or "record bulk failed")
            local code = remote_servers.classify_error_status
                and remote_servers.classify_error_status(text, action_code)
                or api._servers_classify_error_status(text, action_code)
            return error_response(server, client, code, text)
        end
        json_response(server, client, 200, payload or { ok = true, affected = 0 })
    end)
end

function api._servers_dvr_backup_cursor_reset(server, client, request)
    local admin = require_admin(request)
    if not admin then
        return error_response(server, client, 403, "forbidden")
    end
    if not ensure_remote_servers_available(server, client) then
        return
    end
    local body = parse_json_body(request)
    if not body then
        return error_response(server, client, 400, "invalid json")
    end
    local entry, err = api._dvr_resolve_server_entry(body)
    if not entry then
        return error_response(server, client, 400, err or "server not found")
    end
    local stream_ids = type(body.stream_ids) == "table" and body.stream_ids or {}
    if #stream_ids == 0 then
        return error_response(server, client, 400, "stream_ids is required")
    end
    remote_servers.dvr_backup_cursor_reset(entry, {
        stream_ids = stream_ids,
    }, function(ok, payload, action_err, action_code)
        if not ok then
            local text = tostring(action_err or "backup cursor reset failed")
            local code = remote_servers.classify_error_status
                and remote_servers.classify_error_status(text, action_code)
                or api._servers_classify_error_status(text, action_code)
            return error_response(server, client, code, text)
        end
        json_response(server, client, 200, payload or {
            ok = true,
            total = #stream_ids,
            affected = 0,
            failed = {},
            items = {},
        })
    end)
end

function api._servers_dvr_backup_cycle_rebuild(server, client, request)
    local admin = require_admin(request)
    if not admin then
        return error_response(server, client, 403, "forbidden")
    end
    if not ensure_remote_servers_available(server, client) then
        return
    end
    local body = parse_json_body(request)
    if not body then
        return error_response(server, client, 400, "invalid json")
    end
    local entry, err = api._dvr_resolve_server_entry(body)
    if not entry then
        return error_response(server, client, 400, err or "server not found")
    end
    local stream_ids = type(body.stream_ids) == "table" and body.stream_ids or {}
    if #stream_ids == 0 then
        return error_response(server, client, 400, "stream_ids is required")
    end
    remote_servers.dvr_backup_cycle_rebuild(entry, {
        stream_ids = stream_ids,
        include_partial = body.include_partial,
        min_partial_sec = body.min_partial_sec,
        start_mode = body.start_mode,
        start_offset_hours = body.start_offset_hours,
        now_ts = body.now_ts,
    }, function(ok, payload, action_err, action_code)
        if not ok then
            local text = tostring(action_err or "backup cycle rebuild failed")
            local code = remote_servers.classify_error_status
                and remote_servers.classify_error_status(text, action_code)
                or api._servers_classify_error_status(text, action_code)
            return error_response(server, client, code, text)
        end
        json_response(server, client, 200, payload or {
            ok = true,
            total = #stream_ids,
            affected = 0,
            failed = {},
            items = {},
        })
    end)
end

function api._dvr_outbox_next_delay_sec(retries)
    local n = tonumber(retries) or 0
    if n <= 0 then
        return 3
    end
    local delay = 3 * (2 ^ math.min(n, 6))
    if delay > 300 then
        delay = 300
    end
    return delay
end

function api._dvr_outbox_try_send_one(row, callback)
    callback = callback or function() end
    if type(row) ~= "table" then
        return callback(false, "invalid outbox row")
    end
    local servers = config and config.get_setting and config.get_setting("servers") or {}
    local target = nil
    for _, entry in ipairs(servers or {}) do
        if tostring(entry and entry.id or "") == tostring(row.dvr_server_id or "") then
            target = entry
            break
        end
    end
    if not target then
        local err = "dvr server not found: " .. tostring(row.dvr_server_id or "")
        dvr_store.outbox_mark_retry(row.id, err, api._dvr_outbox_next_delay_sec(row.retries))
        return callback(false, err)
    end
    remote_servers.dvr_ingest_state(target, row.payload, function(ok, payload, send_err, send_code)
        if ok then
            dvr_store.outbox_mark_sent(row.id)
            dvr_store.upsert_remote_sync_state({
                stream_id = row.payload and row.payload.stream_id,
                dvr_server_id = row.dvr_server_id,
                last_state_seq = row.payload and row.payload.state_seq,
                last_mode = row.payload and row.payload.mode,
                updated_ts = os.time(),
            })
            return callback(true, payload)
        end
        local err = tostring(send_err or "dvr sync failed")
        local retry_delay = api._dvr_outbox_next_delay_sec((tonumber(row.retries) or 0) + 1)
        dvr_store.outbox_mark_retry(row.id, err, retry_delay)
        return callback(false, err, send_code)
    end)
end

function api._dvr_outbox_flush(limit)
    if not dvr_store or type(dvr_store.list_outbox_ready) ~= "function" then
        return
    end
    local items = dvr_store.list_outbox_ready(limit or 20) or {}
    for _, row in ipairs(items) do
        if row and row.event_type == "ingest_state" then
            api._dvr_outbox_try_send_one(row, function() end)
        else
            dvr_store.outbox_mark_sent(row.id)
        end
    end
end

function api._dvr_local_mode_hint(stream_id)
    if not dvr_store or type(dvr_store.get_stream) ~= "function" then
        return nil
    end
    local sid = api._dvr_trim_text(stream_id)
    if sid == "" then
        return nil
    end
    local row = dvr_store.get_stream(sid)
    if type(row) ~= "table" then
        return nil
    end
    local mode = api._dvr_trim_text(row.last_mode):upper()
    if mode ~= "LIVE" and mode ~= "FAIL_CONFIRMED" and mode ~= "DVR_ACTIVE" and mode ~= "RECOVERING_TO_LIVE" then
        return nil
    end
    local updated_ts = tonumber(row.updated_ts) or 0
    local now = os.time()
    if updated_ts > 0 and (now - updated_ts) > 30 then
        return nil
    end
    local reason = api._dvr_trim_text(row.last_reason)
    if reason == "" then
        reason = nil
    end
    return {
        mode = mode,
        reason = reason,
    }
end

function api._dvr_mode_from_status(stream_id, status)
    local hint = api._dvr_local_mode_hint(stream_id)
    if hint then
        return hint.mode, hint.reason or "local_state"
    end
    if type(status) ~= "table" then
        return "DVR_ACTIVE", "status_missing"
    end
    if status.on_air ~= true then
        local last_error = api._dvr_trim_text(status.last_error)
        if last_error == "" then
            last_error = "no_data"
        end
        return "DVR_ACTIVE", last_error
    end
    return "LIVE", "on_air"
end

function api._dvr_auto_sync_tick()
    if not dvr_store then
        return
    end
    if not (dvr_store.list_remote_links and dvr_store.get_remote_sync_state and dvr_store.enqueue_remote_outbox) then
        return
    end
    local links = dvr_store.list_remote_links()
    if type(links) ~= "table" or #links == 0 then
        return
    end
    local ids = {}
    local seen = {}
    for _, link in ipairs(links) do
        local stream_id = api._dvr_trim_text(link and link.stream_id)
        if stream_id ~= "" and not seen[stream_id] then
            ids[#ids + 1] = stream_id
            seen[stream_id] = true
        end
    end
    if #ids == 0 then
        return
    end
    local status_map = {}
    if runtime and runtime.list_status_lite_ids then
        status_map = runtime.list_status_lite_ids(ids) or {}
    end
    for _, link in ipairs(links) do
        local stream_id = api._dvr_trim_text(link and link.stream_id)
        local dvr_server_id = api._dvr_trim_text(link and link.dvr_server_id)
        if stream_id ~= "" and dvr_server_id ~= "" then
            local mode, reason = api._dvr_mode_from_status(stream_id, status_map[stream_id])
            local sync_state = dvr_store.get_remote_sync_state(stream_id, dvr_server_id)
            local last_mode = sync_state and api._dvr_trim_text(sync_state.last_mode):upper() or ""
            if last_mode ~= mode then
                local last_seq = tonumber(sync_state and sync_state.last_state_seq) or 0
                dvr_store.enqueue_remote_outbox({
                    stream_id = stream_id,
                    dvr_server_id = dvr_server_id,
                    event_type = "ingest_state",
                    payload = {
                        stream_id = stream_id,
                        mode = mode,
                        reason = reason,
                        ts = os.time(),
                        state_seq = last_seq + 1,
                    },
                })
            end
        end
    end
end

function api._servers_dvr_sync_state(server, client, request)
    local admin = require_admin(request)
    if not admin then
        return error_response(server, client, 403, "forbidden")
    end
    if not ensure_remote_servers_available(server, client) then
        return
    end
    if not ensure_dvr_available(server, client) then
        return
    end
    local body = parse_json_body(request)
    if not body then
        return error_response(server, client, 400, "invalid json")
    end
    local entry, err = api._dvr_resolve_server_entry(body)
    if not entry then
        return error_response(server, client, 400, err or "server not found")
    end
    local stream_id = api._dvr_trim_text(body.stream_id)
    if stream_id == "" then
        return error_response(server, client, 400, "stream_id is required")
    end
    local mode = api._dvr_trim_text(body.mode):upper()
    if mode == "" then
        return error_response(server, client, 400, "mode is required")
    end
    local server_id = api._dvr_trim_text(body.id)
    local queue_enabled = server_id ~= ""
    local dvr_server_id = queue_enabled and tostring(entry.id or body.id or "") or ""
    local sync_state = nil
    if queue_enabled then
        sync_state = dvr_store.get_remote_sync_state(stream_id, dvr_server_id)
    end
    local next_seq = tonumber(body.state_seq)
    if not next_seq or next_seq <= 0 then
        if queue_enabled then
            next_seq = (tonumber(sync_state and sync_state.last_state_seq) or 0) + 1
        else
            -- Ad-hoc sync has no persisted outbox state; use a high monotonic-ish
            -- sequence to avoid immediate duplicate rejection on remote.
            next_seq = os.time()
        end
    end
    local payload = {
        stream_id = stream_id,
        mode = mode,
        reason = body.reason,
        ts = os.time(),
        state_seq = math.floor(next_seq),
    }
    if not queue_enabled then
        if body.defer == true then
            return error_response(server, client, 400, "defer requires saved server id")
        end
        remote_servers.dvr_ingest_state(entry, payload, function(sent_ok, sent_payload, sent_err, sent_code)
            if not sent_ok then
                local text = tostring(sent_err or "dvr sync failed")
                local code = remote_servers.classify_error_status
                    and remote_servers.classify_error_status(text, sent_code)
                    or api._servers_classify_error_status(text, sent_code)
                return error_response(server, client, code, text)
            end
            json_response(server, client, 200, {
                ok = true,
                queued = false,
                sent = true,
                state_seq = payload.state_seq,
                remote = sent_payload,
            })
        end)
        return
    end
    local queued, queue_err = dvr_store.enqueue_remote_outbox({
        stream_id = stream_id,
        dvr_server_id = dvr_server_id,
        event_type = "ingest_state",
        payload = payload,
    })
    if not queued then
        return error_response(server, client, 500, tostring(queue_err or "outbox enqueue failed"))
    end

    local deferred = body.defer == true
    if deferred then
        return json_response(server, client, 200, {
            ok = true,
            queued = true,
            sent = false,
            outbox_id = queued.id,
            state_seq = payload.state_seq,
        })
    end

    api._dvr_outbox_try_send_one({
        id = queued.id,
        dvr_server_id = dvr_server_id,
        retries = 0,
        event_type = "ingest_state",
        payload = payload,
    }, function(sent_ok, sent_payload, sent_err)
        json_response(server, client, 200, {
            ok = true,
            queued = true,
            sent = sent_ok == true,
            outbox_id = queued.id,
            state_seq = payload.state_seq,
            error = sent_ok and nil or tostring(sent_err or ""),
            remote = sent_ok and sent_payload or nil,
        })
    end)
end

local function import_server_config(server, client, request)
    local admin = require_admin(request)
    if not admin then
        return error_response(server, client, 403, "forbidden")
    end
    if not servers_import_enabled() then
        return error_response(server, client, 410, "legacy servers import is disabled (set settings.servers_import_enabled=true)")
    end
    local body = parse_json_body(request)
    if not body then
        return error_response(server, client, 400, "invalid json")
    end
    local entry, err = resolve_server_entry(body)
    if not entry then
        return error_response(server, client, 404, err or "server not found")
    end
    local cfg, cfg_err = normalize_server_host(entry)
    if not cfg then
        return error_response(server, client, 400, cfg_err or "invalid server")
    end
    local mode = tostring(body.mode or "merge")
    if mode ~= "merge" and mode ~= "replace" then
        return error_response(server, client, 400, "invalid mode")
    end
    if not config or not config.import_astra then
        return error_response(server, client, 500, "config import unavailable")
    end
    local include_users = body.include_users == true
    local include_settings = body.include_settings == true
    local include_streams = body.include_streams ~= false
    local include_adapters = body.include_adapters ~= false
    local include_softcam = body.include_softcam ~= false
    local include_splitters = body.include_splitters ~= false

    local query = string.format(
        "/api/v1/export?include_users=%s&include_settings=%s&include_streams=%s&include_adapters=%s&include_softcam=%s&include_splitters=%s",
        include_users and "1" or "0",
        include_settings and "1" or "0",
        include_streams and "1" or "0",
        include_adapters and "1" or "0",
        include_softcam and "1" or "0",
        include_splitters and "1" or "0"
    )
    local legacy_query = string.format(
        "/api/export?users=%s&settings=%s&streams=%s&adapters=%s&softcam=%s&splitters=%s",
        include_users and "1" or "0",
        include_settings and "1" or "0",
        include_streams and "1" or "0",
        include_adapters and "1" or "0",
        include_softcam and "1" or "0",
        include_splitters and "1" or "0"
    )

    remote_login(cfg, function(ok, cookie, login_err, login_code)
        if not ok then
            local text = tostring(login_err or "login failed")
            local code = api._servers_classify_error_status(text, login_code)
            return error_response(server, client, code, text)
        end
        local paths = { query, legacy_query }
        local idx = 1
        local function fetch_next()
            local path = paths[idx]
            remote_fetch_json(cfg, path, cookie, "GET", nil, function(ok2, data, fetch_err, code)
                if not ok2 then
                    if code == 404 and idx < #paths then
                        idx = idx + 1
                        return fetch_next()
                    end
                    local text = tostring(fetch_err or "fetch failed")
                    local status = api._servers_classify_error_status(text, code)
                    return error_response(server, client, status, text)
                end
                if type(data) ~= "table" or next(data) == nil then
                    return error_response(server, client, 400, "empty config")
                end
                apply_config_change(server, client, request, {
                    comment = "import remote config",
                    defer_export = true,
                    apply = function()
                        return config.import_astra(data, { mode = mode, transaction = true })
                    end,
                    success_builder = function(summary, revision_id)
                        return { status = "ok", revision_id = revision_id, summary = summary }
                    end,
                })
            end)
        end
        fetch_next()
    end)
end

local function login(server, client, request)
    local body = parse_json_body(request)
    if not body or not body.username or not body.password then
        return error_response(server, client, 400, "invalid json")
    end
    local ip = (request and request.addr) or "unknown"
    local limit = setting_number("rate_limit_login_per_min", 30)
    local window = setting_number("rate_limit_login_window_sec", 60)
    local ok, entry = rate_limit_check(rate_limits.login, ip, limit, window)
    rate_limits.counter = (rate_limits.counter or 0) + 1
    if (rate_limits.counter % 200) == 0 then
        prune_rate_limits(rate_limits.login, window)
    end
    if not ok then
        local retry_after = (entry and entry.window_start)
            and math.max(1, (entry.window_start + window) - os.time())
            or window
        return rate_limit_response(server, client, retry_after, "rate limited")
    end

    local user = config.verify_user(body.username, body.password)
    if not user then
        audit_event("login", request, {
            actor_username = tostring(body.username or ""),
            ok = false,
            message = "invalid credentials",
        })
        return error_response(server, client, 401, "invalid credentials")
    end

    local ttl = setting_number("auth_session_ttl_sec", 3600)
    if ttl < 300 then
        ttl = 300
    end
    local token = config.create_session(user.id, ttl)
    if config.touch_user_login then
        config.touch_user_login(user.id, request and request.addr)
    end
    audit_event("login", request, {
        actor_user_id = user.id,
        actor_username = user.username,
        ok = true,
    })
    local cookie = "stream_session=" .. token .. "; Path=/; HttpOnly; SameSite=Lax; Max-Age=" .. ttl
    server:send(client, {
        code = 200,
        headers = {
            "Content-Type: application/json",
            "Set-Cookie: " .. cookie,
            "Connection: close",
        },
        content = json.encode({
            token = token,
            user = { id = user.id, username = user.username, is_admin = user.is_admin },
        }),
    })
end

local function list_users(server, client, request)
    if not require_admin(request) then
        return error_response(server, client, 403, "forbidden")
    end
    local rows = config.list_users and config.list_users() or {}
    local out = {}
    for _, row in ipairs(rows) do
        table.insert(out, {
            id = row.id,
            username = row.username,
            is_admin = (tonumber(row.is_admin) or 0) == 1,
            enabled = row.enabled == nil or (tonumber(row.enabled) or 0) ~= 0,
            comment = row.comment or "",
            created_at = tonumber(row.created_at) or 0,
            last_login_at = tonumber(row.last_login_at) or 0,
            last_login_ip = row.last_login_ip or "",
        })
    end
    json_response(server, client, 200, out)
end

local function create_user(server, client, request)
    local admin = require_admin(request)
    if not admin then
        return error_response(server, client, 403, "forbidden")
    end
    local body = parse_json_body(request)
    if not body or not body.username or not body.password then
        return error_response(server, client, 400, "invalid json")
    end
    local username = tostring(body.username)
    local password = tostring(body.password)
    local is_admin = body.is_admin == true
    local enabled = body.enabled ~= false
    local comment = body.comment
    local ok, err = config.create_user and config.create_user(username, password, is_admin, enabled, comment)
    if not ok then
        local message = err or "user create failed"
        if not err and config.check_password_policy then
            local policy_ok, policy_err = config.check_password_policy(password, username)
            if not policy_ok and policy_err then
                message = policy_err
            end
        end
        audit_event("user_create", request, {
            actor_user_id = admin.id,
            actor_username = admin.username,
            target_username = username,
            ok = false,
            message = message,
        })
        return error_response(server, client, 400, message)
    end
    audit_event("user_create", request, {
        actor_user_id = admin.id,
        actor_username = admin.username,
        target_username = username,
        ok = true,
        meta = {
            is_admin = is_admin,
            enabled = enabled,
        },
    })
    json_response(server, client, 200, { status = "ok" })
end

local function update_user(server, client, request, username)
    local admin = require_admin(request)
    if not admin then
        return error_response(server, client, 403, "forbidden")
    end
    local body = parse_json_body(request)
    if not body then
        return error_response(server, client, 400, "invalid json")
    end
    local target = config.get_user_by_username and config.get_user_by_username(username)
    if not target then
        return error_response(server, client, 404, "user not found")
    end

    local new_admin = body.is_admin
    local new_enabled = body.enabled
    if (new_admin == false or new_enabled == false)
        and tonumber(target.is_admin) == 1 then
        local admins = config.count_admins and config.count_admins() or 1
        if admins <= 1 then
            audit_event("user_update", request, {
                actor_user_id = admin.id,
                actor_username = admin.username,
                target_username = username,
                ok = false,
                message = "cannot disable last admin",
            })
            return error_response(server, client, 400, "cannot disable last admin")
        end
    end

    if not (config.update_user and config.update_user(username, {
        is_admin = body.is_admin,
        enabled = body.enabled,
        comment = body.comment,
    })) then
        audit_event("user_update", request, {
            actor_user_id = admin.id,
            actor_username = admin.username,
            target_username = username,
            ok = false,
            message = "user update failed",
        })
        return error_response(server, client, 400, "user update failed")
    end

    if new_enabled == false and config.delete_sessions_for_user then
        config.delete_sessions_for_user(target.id)
    end
    audit_event("user_update", request, {
        actor_user_id = admin.id,
        actor_username = admin.username,
        target_username = username,
        ok = true,
        meta = {
            is_admin = body.is_admin,
            enabled = body.enabled,
            comment = body.comment,
        },
    })

    json_response(server, client, 200, { status = "ok" })
end

local function reset_user_password(server, client, request, username)
    local admin = require_admin(request)
    if not admin then
        return error_response(server, client, 403, "forbidden")
    end
    local body = parse_json_body(request)
    if not body or not body.password then
        return error_response(server, client, 400, "invalid json")
    end
    local ok, err = config.set_user_password and config.set_user_password(username, tostring(body.password))
    if not ok then
        local message = err or "user not found"
        local status = (message == "user not found") and 404 or 400
        audit_event("password_reset", request, {
            actor_user_id = admin.id,
            actor_username = admin.username,
            target_username = username,
            ok = false,
            message = message,
        })
        return error_response(server, client, status, message)
    end
    local target = config.get_user_by_username and config.get_user_by_username(username)
    if target and config.delete_sessions_for_user then
        config.delete_sessions_for_user(target.id)
    end
    audit_event("password_reset", request, {
        actor_user_id = admin.id,
        actor_username = admin.username,
        target_username = username,
        ok = true,
    })
    json_response(server, client, 200, { status = "ok" })
end

local function logout(server, client, request)
    local token = get_token(request)
    if token then
        local session = config.get_session(token)
        if session and not check_csrf(request, session) then
            return error_response(server, client, 403, "csrf required")
        end
        config.delete_session(token)
    end
    server:send(client, {
        code = 200,
        headers = {
            "Content-Type: application/json",
            "Set-Cookie: stream_session=; Path=/; HttpOnly; SameSite=Lax; Max-Age=0",
            "Connection: close",
        },
        content = json.encode({ status = "ok" }),
    })
end

local function import_config(server, client, request)
    local body = parse_json_body(request)
    if not body then
        return error_response(server, client, 400, "invalid json")
    end
    local mode = body.mode or "merge"
    local payload = body.config or body
    apply_config_change(server, client, request, {
        comment = "import config",
        validate = function()
            local errors, warnings = validate_config_payload(payload)
            if #errors > 0 then
                return false, "validation failed", errors, warnings
            end
            return true
        end,
        apply = function()
            local summary, err = config.import_astra(payload, { mode = mode, transaction = true })
            if not summary then
                error(err or "import failed")
            end
            if type(apply_softcam_settings) == "function" then
                apply_softcam_settings()
            end
            return summary
        end,
        success_builder = function(summary, revision_id)
            return { status = "ok", revision_id = revision_id, summary = summary }
        end,
    })
end

local function export_config(server, client, request)
    local admin = require_admin(request)
    if not admin then
        return error_response(server, client, 403, "forbidden")
    end

    local function query_bool(value, fallback)
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

    local query = request and request.query or {}
    local include_users = query_bool(query.include_users, true)
    local include_settings = query_bool(query.include_settings, true)
    local include_streams = query_bool(query.include_streams, true)
    local include_adapters = query_bool(query.include_adapters, true)
    local include_softcam = query_bool(query.include_softcam, true)
    local include_splitters = query_bool(query.include_splitters, true)
    local download = query_bool(query.download, false)

    local payload = config.export_astra and config.export_astra({
        include_users = include_users,
        include_settings = include_settings,
        include_streams = include_streams,
        include_adapters = include_adapters,
        include_softcam = include_softcam,
        include_splitters = include_splitters,
    }) or {}

    local headers = {
        "Content-Type: application/json",
        "Cache-Control: no-cache",
        "Connection: close",
    }
    if download then
        table.insert(headers, "Content-Disposition: attachment; filename=stream-export.json")
    end
    local encoded
    if json and type(json.encode_pretty) == "function" then
        encoded = json.encode_pretty(payload)
    else
        encoded = json.encode(payload)
    end
    server:send(client, {
        code = 200,
        headers = headers,
        content = encoded,
    })
end

function api._validate_config(server, client, request)
    local body = parse_json_body(request)
    local payload = nil
    if body then
        payload = body.config or body
    end
    if not payload or next(payload) == nil then
        payload = config.export_astra and config.export_astra({}) or {}
    end
    local errors, warnings = validate_config_payload(payload)
    local ok = (#errors == 0)
    json_response(server, client, 200, {
        ok = ok,
        errors = errors,
        warnings = warnings,
    })
end

function api._list_config_revisions(server, client, request)
    local admin = require_admin(request)
    if not admin then
        return error_response(server, client, 403, "forbidden")
    end
    local query = request and request.query or {}
    local limit = tonumber(query.limit) or 50
    local rows = config.list_revisions(limit)
    json_response(server, client, 200, {
        active_revision_id = config.get_setting("config_active_revision_id"),
        lkg_revision_id = config.get_setting("config_lkg_revision_id"),
        revisions = rows,
    })
end

function api._restore_config_revision(server, client, request, rev_id)
    local admin = require_admin(request)
    if not admin then
        return error_response(server, client, 403, "forbidden")
    end
    local row = config.get_revision(rev_id)
    if not row then
        return error_response(server, client, 404, "revision not found")
    end
    if not row.snapshot_path or row.snapshot_path == "" then
        return error_response(server, client, 400, "snapshot not available")
    end
    apply_config_change(server, client, request, {
        comment = "restore revision " .. tostring(row.id),
        apply = function()
            local summary, err = config.restore_snapshot(row.snapshot_path)
            if not summary then
                error(err or "restore failed")
            end
            return summary
        end,
        success_builder = function(summary, revision_id)
            return {
                status = "ok",
                revision_id = revision_id,
                restored_from = row.id,
                summary = summary,
            }
        end,
    })
end

function api._delete_config_revision(server, client, request, rev_id)
    local admin = require_admin(request)
    if not admin then
        return error_response(server, client, 403, "forbidden")
    end
    if not config or not config.delete_revision then
        return error_response(server, client, 501, "config revisions are unavailable")
    end
    local row = config.delete_revision(rev_id)
    if not row then
        return error_response(server, client, 404, "revision not found")
    end
    local active_id = config.get_setting("config_active_revision_id")
    local lkg_id = config.get_setting("config_lkg_revision_id")
    if active_id and tonumber(active_id) == tonumber(rev_id) then
        config.set_setting("config_active_revision_id", 0)
    end
    if lkg_id and tonumber(lkg_id) == tonumber(rev_id) then
        config.set_setting("config_lkg_revision_id", 0)
    end
    json_response(server, client, 200, { status = "ok", deleted = tonumber(rev_id) })
end

function api._delete_all_config_revisions(server, client, request)
    local admin = require_admin(request)
    if not admin then
        return error_response(server, client, 403, "forbidden")
    end
    if not config or not config.delete_all_revisions then
        return error_response(server, client, 501, "config revisions are unavailable")
    end
    local count = config.delete_all_revisions()
    config.set_setting("config_active_revision_id", 0)
    config.set_setting("config_lkg_revision_id", 0)
    json_response(server, client, 200, { status = "ok", deleted = tonumber(count) or 0 })
end

function api.handle_request(server, client, request)
    if not request then
        return nil
    end

    local method = request.method or "GET"
    local path = request.path or "/"
    ensure_server_send_wrapper(server)
    local req_id = next_request_id()
    request.request_id = req_id
    local ctx_key = client_ctx_key(client)
    api_request_context[ctx_key] = {
        request_id = req_id,
        method = method,
        endpoint = normalize_metric_path(path),
        started_ms = metric_now_ms(),
        completed = false,
    }

    if method == "OPTIONS" then
        return json_response(server, client, 200, { status = "ok" })
    end

    if path == "/api/v1/auth/login" and method == "POST" then
        return login(server, client, request)
    end

    if path == "/api/v1/auth/logout" and method == "POST" then
        return logout(server, client, request)
    end

    if (path == "/health" or path == "/api/v1/health") and method == "GET" then
        return health_summary(server, client)
    end

    -- Internal-only reload hook for sharded setups (no auth/csrf).
    -- Used by sharding.broadcast_reload() to refresh peers after DB changes.
    if path == "/api/v1/reload-internal" and method == "POST" then
        if not is_internal_loopback(request) then
            return error_response(server, client, 403, "forbidden")
        end
        local q = request and request.query or {}
        local force = true
        if q.force ~= nil then
            local v = tostring(q.force or ""):lower()
            if v == "0" or v == "false" or v == "no" or v == "off" then
                force = false
            end
        end
        local ok, err = reload_runtime(force)
        if not ok then
            return json_response(server, client, 500, { error = "reload failed", detail = err })
        end
        return json_response(server, client, 200, { status = "ok", force = force })
    end

    -- Security hardening:
    -- when web auth is disabled, allow API only from trusted loopback by default.
    -- Explicitly opt out with http_allow_public_noauth=1 for legacy/test setups.
    if (not auth_enabled()) and (not setting_bool("http_allow_public_noauth", true)) then
        if not is_internal_loopback(request) then
            return error_response(
                server,
                client,
                403,
                "public API disabled without auth; enable http_auth_enabled or set http_allow_public_noauth=1"
            )
        end
    end

    local session = require_auth(request)
    if not session then
        return error_response(server, client, 401, "unauthorized")
    end
    if not check_csrf(request, session) then
        return error_response(server, client, 403, "csrf required")
    end

    if path == "/api/v1/streams" and method == "GET" then
        return list_streams(server, client)
    end
    if path == "/api/v1/streams" and method == "POST" then
        local body = parse_json_body(request)
        if not body or not body.id then
            return error_response(server, client, 400, "stream id required")
        end
        return upsert_stream(server, client, body.id, request)
    end
    if path == "/api/v1/streams/purge-disabled" and method == "POST" then
        return purge_disabled_streams(server, client, request)
    end
    if path == "/api/v1/streams/transcode-all" and method == "POST" then
        return transcode_all_streams(server, client, request)
    end

    local stream_id = path:match("^/api/v1/streams/([%w%-%_]+)$")
    if stream_id and method == "GET" then
        return get_stream(server, client, stream_id)
    end
    if stream_id and method == "PUT" then
        return upsert_stream(server, client, stream_id, request)
    end
    if stream_id and method == "DELETE" then
        return delete_stream(server, client, stream_id, request)
    end

    local stream_switch_input_id = path:match("^/api/v1/streams/([%w%-%_]+)/switch%-input$")
    if stream_switch_input_id and method == "POST" then
        return switch_stream_input(server, client, request, stream_switch_input_id)
    end

    local stream_cam_stats = path:match("^/api/v1/streams/([%w%-%_]+)/cam%-stats$")
    if stream_cam_stats and method == "GET" then
        return get_stream_cam_stats(server, client, request, stream_cam_stats)
    end

    local stream_analyze_id = path:match("^/api/v1/streams/analyze/([%w%-%_]+)$")
    if stream_analyze_id and method == "GET" then
        return get_stream_analyze(server, client, request, stream_analyze_id)
    end
    if path == "/api/v1/streams/analyze" and method == "POST" then
        return start_stream_analyze(server, client, request)
    end
    local stream_analyze_stream = path:match("^/api/v1/streams/([%w%-%_]+)/analyze$")
    if stream_analyze_stream and method == "POST" then
        return start_stream_analyze(server, client, request, stream_analyze_stream)
    end
    if path == "/api/v1/mpts/scan" and method == "POST" then
        return mpts_scan(server, client, request)
    end

    local stream_preview_start = path:match("^/api/v1/streams/([%w%-%_]+)/preview/start$")
    if stream_preview_start and method == "POST" then
        return start_stream_preview(server, client, request, stream_preview_start)
    end
    local stream_preview_stop = path:match("^/api/v1/streams/([%w%-%_]+)/preview/stop$")
    if stream_preview_stop and method == "POST" then
        return stop_stream_preview(server, client, request, stream_preview_stop)
    end

    local pngts_ffprobe_id = path:match("^/api/v1/streams/([%w%-%_]+)/pngts/ffprobe$")
    if pngts_ffprobe_id and method == "POST" then
        return api.pngts_ffprobe(server, client, request, pngts_ffprobe_id)
    end
    local pngts_generate_id = path:match("^/api/v1/streams/([%w%-%_]+)/pngts/generate$")
    if pngts_generate_id and method == "POST" then
        return api.pngts_generate(server, client, request, pngts_generate_id)
    end
    local pngts_list_id = path:match("^/api/v1/streams/([%w%-%_]+)/pngts/list$")
    if pngts_list_id and method == "GET" then
        return api.pngts_list(server, client, request, pngts_list_id)
    end
    local pngts_job_id = path:match("^/api/v1/pngts/jobs/([%w%-%_]+)$")
    if pngts_job_id and method == "GET" then
        return api.pngts_job_status(server, client, pngts_job_id)
    end

    local radio_start_id = path:match("^/api/v1/streams/([%w%-%_]+)/radio/start$")
    if radio_start_id and method == "POST" then
        return api.radio_start(server, client, request, radio_start_id)
    end
    local radio_stop_id = path:match("^/api/v1/streams/([%w%-%_]+)/radio/stop$")
    if radio_stop_id and method == "POST" then
        return api.radio_stop(server, client, request, radio_stop_id)
    end
    local radio_restart_id = path:match("^/api/v1/streams/([%w%-%_]+)/radio/restart$")
    if radio_restart_id and method == "POST" then
        return api.radio_restart(server, client, request, radio_restart_id)
    end
    local radio_status_id = path:match("^/api/v1/streams/([%w%-%_]+)/radio/status$")
    if radio_status_id and method == "GET" then
        return api.radio_status(server, client, request, radio_status_id)
    end

    if path == "/api/v1/adapters" and method == "GET" then
        return list_adapters(server, client)
    end
    if path == "/api/v1/adapters" and method == "POST" then
        local body = parse_json_body(request)
        if not body or not body.id then
            return error_response(server, client, 400, "adapter id required")
        end
        return upsert_adapter(server, client, body.id, request)
    end

    local adapter_id = path:match("^/api/v1/adapters/([%w%-%_]+)$")
    if adapter_id and method == "GET" then
        return get_adapter(server, client, adapter_id)
    end
    if adapter_id and method == "PUT" then
        return upsert_adapter(server, client, adapter_id, request)
    end
    if adapter_id and method == "DELETE" then
        return delete_adapter(server, client, adapter_id, request)
    end

    if path == "/api/v1/splitters" and method == "GET" then
        return list_splitters(server, client)
    end
    if path == "/api/v1/splitters" and method == "POST" then
        local body = parse_json_body(request)
        if not body then
            return error_response(server, client, 400, "invalid json")
        end
        local id = body.id or generate_id("splitter")
        return upsert_splitter(server, client, id, request)
    end

    local splitter_id = path:match("^/api/v1/splitters/([%w%-%_]+)$")
    if splitter_id and method == "GET" then
        return get_splitter(server, client, splitter_id)
    end
    if splitter_id and method == "PUT" then
        return upsert_splitter(server, client, splitter_id, request)
    end
    if splitter_id and method == "DELETE" then
        return delete_splitter(server, client, splitter_id, request)
    end

    local splitter_links = path:match("^/api/v1/splitters/([%w%-%_]+)/links$")
    if splitter_links and method == "GET" then
        return list_splitter_links(server, client, splitter_links)
    end
    if splitter_links and method == "POST" then
        local body = parse_json_body(request)
        if not body then
            return error_response(server, client, 400, "invalid json")
        end
        local link_id = body.id or generate_id("link")
        return upsert_splitter_link(server, client, splitter_links, link_id, request)
    end

    local splitter_link_split, splitter_link_id = path:match("^/api/v1/splitters/([%w%-%_]+)/links/([%w%-%_]+)$")
    if splitter_link_split and splitter_link_id and method == "PUT" then
        return upsert_splitter_link(server, client, splitter_link_split, splitter_link_id, request)
    end
    if splitter_link_split and splitter_link_id and method == "DELETE" then
        return delete_splitter_link(server, client, splitter_link_split, splitter_link_id, request)
    end

    local splitter_allow = path:match("^/api/v1/splitters/([%w%-%_]+)/allow$")
    if splitter_allow and method == "GET" then
        return list_splitter_allow(server, client, splitter_allow)
    end
    if splitter_allow and method == "POST" then
        return add_splitter_allow(server, client, splitter_allow, request)
    end

    local splitter_allow_split, splitter_allow_rule = path:match("^/api/v1/splitters/([%w%-%_]+)/allow/([%w%-%_]+)$")
    if splitter_allow_split and splitter_allow_rule and method == "DELETE" then
        return delete_splitter_allow(server, client, splitter_allow_split, splitter_allow_rule, request)
    end

    local splitter_start = path:match("^/api/v1/splitters/([%w%-%_]+)/start$")
    if splitter_start and method == "POST" then
        return start_splitter(server, client, splitter_start)
    end
    local splitter_stop = path:match("^/api/v1/splitters/([%w%-%_]+)/stop$")
    if splitter_stop and method == "POST" then
        return stop_splitter(server, client, splitter_stop)
    end
    local splitter_restart = path:match("^/api/v1/splitters/([%w%-%_]+)/restart$")
    if splitter_restart and method == "POST" then
        return restart_splitter(server, client, splitter_restart)
    end
    local splitter_apply = path:match("^/api/v1/splitters/([%w%-%_]+)/apply%-config$")
    if splitter_apply and method == "POST" then
        return apply_splitter_config(server, client, splitter_apply)
    end

    local splitter_config = path:match("^/api/v1/splitters/([%w%-%_]+)/config$")
    if splitter_config and method == "GET" then
        return get_splitter_config(server, client, splitter_config)
    end

    if path == "/api/v1/splitter-status" and method == "GET" then
        return list_splitter_status(server, client)
    end
    local splitter_status_id = path:match("^/api/v1/splitter%-status/([%w%-%_]+)$")
    if splitter_status_id and method == "GET" then
        return get_splitter_status(server, client, splitter_status_id)
    end

    if path == "/api/v1/buffers/resources" and method == "GET" then
        return list_buffer_resources(server, client)
    end
    if path == "/api/v1/buffers/resources" and method == "POST" then
        local body = parse_json_body(request)
        if not body then
            return error_response(server, client, 400, "invalid json")
        end
        local id = tostring(body.id or "")
        if id == "" then
            return error_response(server, client, 400, "buffer id required")
        end
        return upsert_buffer_resource(server, client, id, body, request)
    end

    local buffer_resource_id = path:match("^/api/v1/buffers/resources/([%w%-%_]+)$")
    if buffer_resource_id and method == "GET" then
        return get_buffer_resource(server, client, buffer_resource_id)
    end
    if buffer_resource_id and method == "PUT" then
        local body = parse_json_body(request)
        if not body then
            return error_response(server, client, 400, "invalid json")
        end
        local body_id = tostring(body.id or "")
        if body_id == "" then
            return error_response(server, client, 400, "buffer id required")
        end
        if body_id ~= buffer_resource_id then
            return error_response(server, client, 400, "buffer id mismatch")
        end
        return upsert_buffer_resource(server, client, buffer_resource_id, body, request)
    end
    if buffer_resource_id and method == "DELETE" then
        return delete_buffer_resource(server, client, buffer_resource_id, request)
    end

    local buffer_inputs = path:match("^/api/v1/buffers/resources/([%w%-%_]+)/inputs$")
    if buffer_inputs and method == "GET" then
        return list_buffer_inputs(server, client, buffer_inputs)
    end
    if buffer_inputs and method == "POST" then
        local body = parse_json_body(request)
        if not body then
            return error_response(server, client, 400, "invalid json")
        end
        local input_id = body.id or generate_id("input")
        return upsert_buffer_input(server, client, buffer_inputs, input_id, body, request)
    end

    local buffer_input_resource, buffer_input_id =
        path:match("^/api/v1/buffers/resources/([%w%-%_]+)/inputs/([%w%-%_]+)$")
    if buffer_input_resource and buffer_input_id and method == "PUT" then
        local body = parse_json_body(request)
        if not body then
            return error_response(server, client, 400, "invalid json")
        end
        local body_id = body.id
        if body_id ~= nil and tostring(body_id) ~= buffer_input_id then
            return error_response(server, client, 400, "buffer input id mismatch")
        end
        return upsert_buffer_input(server, client, buffer_input_resource, buffer_input_id, body, request)
    end
    if buffer_input_resource and buffer_input_id and method == "DELETE" then
        return delete_buffer_input(server, client, buffer_input_resource, buffer_input_id, request)
    end

    if path == "/api/v1/buffers/allow" and method == "GET" then
        return list_buffer_allow(server, client)
    end
    if path == "/api/v1/buffers/allow" and method == "POST" then
        local body = parse_json_body(request)
        if not body then
            return error_response(server, client, 400, "invalid json")
        end
        return add_buffer_allow(server, client, body, request)
    end

    local buffer_allow_id = path:match("^/api/v1/buffers/allow/([%w%-%_]+)$")
    if buffer_allow_id and method == "DELETE" then
        return delete_buffer_allow(server, client, buffer_allow_id, request)
    end

    if path == "/api/v1/buffers/reload" and method == "POST" then
        return reload_buffers(server, client)
    end

    local buffer_restart = path:match("^/api/v1/buffers/([%w%-%_]+)/restart%-reader$")
    if buffer_restart and method == "POST" then
        return restart_buffer_reader(server, client, buffer_restart)
    end

    if path == "/api/v1/buffer-status" and method == "GET" then
        return list_buffer_status(server, client)
    end
    local buffer_status_id = path:match("^/api/v1/buffer%-status/([%w%-%_]+)$")
    if buffer_status_id and method == "GET" then
        return get_buffer_status(server, client, buffer_status_id)
    end

    if path == "/api/v1/adapter-status" and method == "GET" then
        return list_adapter_status(server, client)
    end
    if path == "/api/v1/dvb-adapters" and method == "GET" then
        return list_dvb_adapters(server, client)
    end
    if path == "/api/v1/dvb-scan" and method == "POST" then
        local admin = require_admin(request)
        if not admin then
            return error_response(server, client, 403, "forbidden")
        end
        return start_dvb_scan(server, client, request)
    end

    if path == "/api/v1/dvb-auto-search/status" and method == "GET" then
        return get_dvb_autosearch_status(server, client, request)
    end
    if path == "/api/v1/dvb-auto-search/trigger" and method == "POST" then
        return trigger_dvb_autosearch(server, client, request)
    end
    if path == "/api/v1/dvb-auto-search/queue/clear" and method == "POST" then
        return clear_dvb_autosearch_queue(server, client, request)
    end
    if path == "/api/v1/dvb-auto-search/unfreeze" and method == "POST" then
        return unfreeze_dvb_autosearch(server, client, request)
    end

    if path == "/api/v1/dvb-scan-presets" and method == "GET" then
        return get_dvb_scan_presets(server, client, request)
    end
    if path == "/api/v1/dvb-scan-presets/refresh" and method == "POST" then
        return dvb_scan_presets_refresh(server, client, request)
    end
    if path == "/api/v1/dvb-scan-presets/manual" and method == "POST" then
        return set_dvb_scan_presets_manual(server, client, request)
    end
    if path == "/api/v1/dvb-full-scan" and method == "POST" then
        return start_dvb_full_scan(server, client, request)
    end

    local dvb_scan_id = path:match("^/api/v1/dvb%-scan/([%w%-%_]+)$")
    if dvb_scan_id and method == "GET" then
        local admin = require_admin(request)
        if not admin then
            return error_response(server, client, 403, "forbidden")
        end
        return get_dvb_scan(server, client, request, dvb_scan_id)
    end

    local dvb_full_scan_id = path:match("^/api/v1/dvb%-full%-scan/([%w%-%_]+)$")
    if dvb_full_scan_id and method == "GET" then
        return get_dvb_full_scan(server, client, request, dvb_full_scan_id)
    end
    local dvb_full_scan_cancel_id = path:match("^/api/v1/dvb%-full%-scan/([%w%-%_]+)/cancel$")
    if dvb_full_scan_cancel_id and method == "POST" then
        return cancel_dvb_full_scan(server, client, request, dvb_full_scan_cancel_id)
    end
    local dvb_full_scan_export_id = path:match("^/api/v1/dvb%-full%-scan/([%w%-%_]+)/export$")
    if dvb_full_scan_export_id and method == "GET" then
        return export_dvb_full_scan(server, client, request, dvb_full_scan_export_id)
    end
    local dvb_full_scan_create_id = path:match("^/api/v1/dvb%-full%-scan/([%w%-%_]+)/create%-streams$")
    if dvb_full_scan_create_id and method == "POST" then
        return create_streams_from_dvb_full_scan(server, client, request, dvb_full_scan_create_id)
    end

    local adapter_status_id = path:match("^/api/v1/adapter%-status/([%w%-%_]+)$")
    if adapter_status_id and method == "GET" then
        return get_adapter_status(server, client, adapter_status_id)
    end

    if path == "/api/v1/stream-status" and method == "GET" then
        return list_stream_status(server, client, request)
    end

    local status_id = path:match("^/api/v1/stream%-status/([%w%-%_]+)$")
    if status_id and method == "GET" then
        return get_stream_status(server, client, request, status_id)
    end

    if path == "/api/v1/users" and method == "GET" then
        return list_users(server, client, request)
    end
    if path == "/api/v1/users" and method == "POST" then
        return create_user(server, client, request)
    end
    local user_name = path:match("^/api/v1/users/([%w%-%_%.]+)$")
    if user_name and method == "PUT" then
        return update_user(server, client, request, user_name)
    end
    local reset_name = path:match("^/api/v1/users/([%w%-%_%.]+)/reset$")
    if reset_name and method == "POST" then
        return reset_user_password(server, client, request, reset_name)
    end

    if path == "/api/v1/sessions" and method == "GET" then
        return list_sessions(server, client, request)
    end

    if path == "/api/v1/auth-debug/session" and method == "GET" then
        return auth_debug_session(server, client, request)
    end

    local session_id = path:match("^/api/v1/sessions/([%w%-]+)$")
    if session_id and method == "DELETE" then
        return delete_session(server, client, session_id)
    end

    if path == "/api/v1/logs" and method == "GET" then
        return list_logs(server, client, request)
    end
    if path == "/api/v1/access-log" and method == "GET" then
        return list_access_log(server, client, request)
    end
    if path == "/api/v1/health/process" and method == "GET" then
        return health_process(server, client)
    end
    if path == "/api/v1/health/inputs" and method == "GET" then
        return health_inputs(server, client)
    end
    if path == "/api/v1/health/outputs" and method == "GET" then
        return health_outputs(server, client)
    end
    if path == "/api/v1/metrics" and method == "GET" then
        return list_metrics(server, client, request)
    end
    if path == "/api/v1/metrics/http" and method == "GET" then
        return list_http_api_metrics(server, client, request)
    end
    if path == "/api/v1/audit" and method == "GET" then
        return list_audit_events(server, client, request)
    end
    if path == "/api/v1/tools" and method == "GET" then
        return list_tools(server, client)
    end
    if path == "/api/v1/license" and method == "GET" then
        return license_info(server, client)
    end
    if path == "/api/v1/alerts" and method == "GET" then
        return list_alerts(server, client, request)
    end

    if path == "/api/v1/transcode-status" and method == "GET" then
        return list_transcode_status(server, client, request)
    end

    local transcode_id = path:match("^/api/v1/transcode%-status/([%w%-%_]+)$")
    if transcode_id and method == "GET" then
        return get_transcode_status(server, client, request, transcode_id)
    end

    local restart_id = path:match("^/api/v1/transcode/([%w%-%_]+)/restart$")
    if restart_id and method == "POST" then
        return restart_transcode(server, client, request, restart_id)
    end

    if path == "/api/v1/reload" and method == "POST" then
        return reload_service(server, client, request)
    end

    if path == "/api/v1/restart" and method == "POST" then
        return restart_service(server, client, request)
    end

    if path == "/api/v1/sharding/apply" and method == "POST" then
        return apply_sharding(server, client, request)
    end

    if path == "/api/v1/config/validate" and method == "POST" then
        return api._validate_config(server, client, request)
    end

    if path == "/api/v1/config/revisions" and method == "GET" then
        return api._list_config_revisions(server, client, request)
    end
    if path == "/api/v1/config/revisions" and method == "DELETE" then
        return api._delete_all_config_revisions(server, client, request)
    end
    local config_rev_id = path:match("^/api/v1/config/revisions/(%d+)/restore$")
    if config_rev_id and method == "POST" then
        return api._restore_config_revision(server, client, request, config_rev_id)
    end
    local config_rev_delete = path:match("^/api/v1/config/revisions/(%d+)$")
    if config_rev_delete and method == "DELETE" then
        return api._delete_config_revision(server, client, request, config_rev_delete)
    end

    if path == "/api/v1/settings" and method == "GET" then
        return get_settings(server, client)
    end
    if path == "/api/v1/settings" and method == "PUT" then
        return set_settings(server, client, request)
    end
    if path == "/api/v1/notifications/telegram/test" and method == "POST" then
        return telegram_test(server, client)
    end
    if path == "/api/v1/notifications/telegram/backup" and method == "POST" then
        return telegram_backup(server, client)
    end
    if path == "/api/v1/notifications/telegram/summary" and method == "POST" then
        return telegram_summary(server, client)
    end
    if path == "/api/v1/notifications/telegram/status" and method == "GET" then
        return telegram_status(server, client)
    end
    if path == "/api/v1/notifications/telegram/triggers" and method == "POST" then
        return telegram_triggers(server, client)
    end
    if path == "/api/v1/ai/logs" and method == "GET" then
        return ai_logs(server, client, request)
    end
    if path == "/api/v1/ai/metrics" and method == "GET" then
        return ai_metrics(server, client, request)
    end
    if path == "/api/v1/observability/system/snapshot" and method == "GET" then
        return system_metrics_snapshot(server, client, request)
    end
    if path == "/api/v1/observability/system/timeseries" and method == "GET" then
        return system_metrics_timeseries(server, client, request)
    end
    if path == "/api/v1/observability/stream-series" and method == "GET" then
        return observability_stream_series(server, client, request)
    end
    if path == "/api/v1/observability/stream-events" and method == "GET" then
        return observability_stream_events(server, client, request)
    end
    if path == "/api/v1/observability/collector/status" and method == "GET" then
        return observability_collector_debug(server, client, request)
    end
    if path == "/api/v1/ai/summary" and method == "GET" then
        return ai_summary(server, client, request)
    end
    if path == "/api/v1/ai/jobs" and method == "GET" then
        return ai_jobs(server, client)
    end
    if path == "/api/v1/ai/plan" and method == "POST" then
        return ai_plan(server, client, request)
    end
    if path == "/api/v1/ai/apply" and method == "POST" then
        return ai_apply(server, client, request)
    end
    if path == "/api/v1/ai/telegram" and method == "POST" then
        return ai_telegram(server, client, request)
    end
    if path == "/api/v1/softcam/test" and method == "POST" then
        return softcam_test(server, client, request)
    end
    if path == "/api/v1/servers/status" and method == "GET" then
        return server_status_list(server, client, request)
    end
    if path == "/api/v1/servers/streams/list" and method == "POST" then
        return api._servers_list_streams(server, client, request)
    end
    if path == "/api/v1/servers/streams/get" and method == "POST" then
        return api._servers_get_stream(server, client, request)
    end
    if path == "/api/v1/servers/streams/upsert" and method == "POST" then
        return api._servers_upsert_stream(server, client, request)
    end
    if path == "/api/v1/servers/streams/delete" and method == "POST" then
        return api._servers_delete_stream(server, client, request)
    end
    if path == "/api/v1/servers/streams/action" and method == "POST" then
        return api._servers_action_stream(server, client, request)
    end
    if path == "/api/v1/servers/streams" and method == "POST" then
        -- Backward-compatible alias.
        return api._servers_list_streams(server, client, request)
    end
    if path == "/api/v1/servers/dvr/import-streams" and method == "POST" then
        return api._servers_dvr_import_streams(server, client, request)
    end
    if path == "/api/v1/servers/dvr/storage/candidates" and method == "POST" then
        return api._servers_dvr_storage_candidates(server, client, request)
    end
    if path == "/api/v1/servers/dvr/sync-state" and method == "POST" then
        return api._servers_dvr_sync_state(server, client, request)
    end
    if path == "/api/v1/servers/dvr/record/bulk" and method == "POST" then
        return api._servers_dvr_record_bulk(server, client, request)
    end
    if path == "/api/v1/servers/dvr/backup/cursor/reset" and method == "POST" then
        return api._servers_dvr_backup_cursor_reset(server, client, request)
    end
    if path == "/api/v1/servers/dvr/backup/cycle/rebuild" and method == "POST" then
        return api._servers_dvr_backup_cycle_rebuild(server, client, request)
    end
    if path == "/api/v1/servers/pull-streams" and method == "POST" then
        return api._servers_pull_streams(server, client, request)
    end
    if path == "/api/v1/servers/import" and method == "POST" then
        return import_server_config(server, client, request)
    end
    if path == "/api/v1/servers/test" and method == "POST" then
        return server_test(server, client, request)
    end
    if path == "/api/v1/dvr/health" and method == "GET" then
        return api._dvr_health(server, client, request)
    end
    if path == "/api/v1/dvr/storage/candidates" and method == "GET" then
        return api._dvr_storage_candidates_get(server, client, request)
    end
    if path == "/api/v1/dvr/streams/list" and method == "POST" then
        return api._dvr_streams_list(server, client, request)
    end
    if path == "/api/v1/dvr/streams/get" and (method == "GET" or method == "POST") then
        return api._dvr_streams_get(server, client, request)
    end
    if path == "/api/v1/dvr/streams/upsert" and method == "POST" then
        return api._dvr_streams_upsert(server, client, request)
    end
    if path == "/api/v1/dvr/streams/delete" and method == "POST" then
        return api._dvr_streams_delete(server, client, request)
    end
    if path == "/api/v1/dvr/streams/bulk-record" and method == "POST" then
        return api._dvr_streams_bulk_record(server, client, request)
    end
    if path == "/api/v1/dvr/ingest-state" and method == "POST" then
        return api._dvr_ingest_state(server, client, request)
    end
    if path == "/api/v1/dvr/backup/state" and method == "GET" then
        return api._dvr_backup_state_get(server, client, request)
    end
    if path == "/api/v1/dvr/archive" and method == "GET" then
        return api._dvr_archive_get(server, client, request)
    end
    if path == "/api/v1/dvr/backup/cursor/reset" and method == "POST" then
        return api._dvr_backup_cursor_reset(server, client, request)
    end
    if path == "/api/v1/dvr/backup/cursor/reset-bulk" and method == "POST" then
        return api._dvr_backup_cursor_reset_bulk(server, client, request)
    end
    if path == "/api/v1/dvr/backup/cycle/rebuild" and method == "POST" then
        return api._dvr_backup_cycle_rebuild(server, client, request)
    end
    if path == "/api/v1/dvr/backup/cycle/rebuild-bulk" and method == "POST" then
        return api._dvr_backup_cycle_rebuild_bulk(server, client, request)
    end
    if path == "/api/v1/dvr/backup/next-segment" and (method == "GET" or method == "POST") then
        return api._dvr_backup_next_segment(server, client, request)
    end
    if path == "/api/v1/dvr/backup/progress" and method == "POST" then
        return api._dvr_backup_progress(server, client, request)
    end
    if path == "/api/v1/import" and method == "POST" then
        return import_config(server, client, request)
    end
    if path == "/api/v1/export" and method == "GET" then
        return export_config(server, client, request)
    end

    return error_response(server, client, 404, "not found")
end

function api.start(opts)
    opts = opts or {}
    local addr = opts.addr or "0.0.0.0"
    local port = opts.port or 8000
    local http_request_line_max = setting_number("http_request_line_max", 4096)
    local http_headers_max = setting_number("http_headers_max", 12288)
    local http_header_max = setting_number("http_header_max", 4096)
    local http_content_length_max = setting_number("http_content_length_max", 8 * 1024 * 1024)
    local http_max_clients = math.max(0, math.floor(setting_number("http_max_clients", 0) or 0))
    local http_max_clients_per_ip = math.max(0, math.floor(setting_number("http_max_clients_per_ip", 0) or 0))
    local http_accept_backoff_ms = math.max(10, math.min(5000, math.floor(setting_number("http_accept_backoff_ms", 100) or 100)))

    http_server({
        addr = addr,
        port = port,
        server_name = "Stream API",
        route = {
            { "/api/*", api.handle_request },
        },
        request_line_max = http_request_line_max,
        headers_max = http_headers_max,
        header_max = http_header_max,
        content_length_max = http_content_length_max,
        max_clients = http_max_clients,
        max_clients_per_ip = http_max_clients_per_ip,
        accept_backoff_ms = http_accept_backoff_ms,
    })

    if dvb_autosearch.timer then
        pcall(function()
            dvb_autosearch.timer:close()
        end)
        dvb_autosearch.timer = nil
    end
    dvb_autosearch.timer = timer({
        interval = 10,
        callback = function()
            local ok, err = pcall(dvb_autosearch_tick)
            if not ok then
                log.warning("[dvb-autosearch] tick failed: " .. tostring(err))
            end
            -- Periodic retention cleanup for scan history.
            local days = clamp_number(setting_number("dvb_scan_jobs_retention_days", 14), 1, 365) or 14
            local cutoff = os.time() - (days * 86400)
            db_exec_safe("DELETE FROM dvb_scan_jobs WHERE finished_ts > 0 AND finished_ts < " .. tostring(cutoff) .. ";")
            db_exec_safe("DELETE FROM dvb_scan_grid WHERE job_id NOT IN (SELECT id FROM dvb_scan_jobs);")
            db_exec_safe("DELETE FROM dvb_scan_channels WHERE job_id NOT IN (SELECT id FROM dvb_scan_jobs);")
        end,
    })

    if api._dvr_outbox_timer then
        pcall(function()
            api._dvr_outbox_timer:close()
        end)
        api._dvr_outbox_timer = nil
    end
    api._dvr_outbox_timer = timer({
        interval = 2,
        callback = function()
            local ok, err = pcall(function()
                api._dvr_outbox_flush(20)
            end)
            if not ok then
                log.warning("[dvr] outbox flush failed: " .. tostring(err))
            end
        end,
    })

    if api._dvr_sync_timer then
        pcall(function()
            api._dvr_sync_timer:close()
        end)
        api._dvr_sync_timer = nil
    end
    api._dvr_sync_timer = timer({
        interval = 5,
        callback = function()
            local ok, err = pcall(function()
                api._dvr_auto_sync_tick()
            end)
            if not ok then
                log.warning("[dvr] auto sync tick failed: " .. tostring(err))
            end
        end,
    })

    log.info("[api] listening on " .. addr .. ":" .. port)
end
