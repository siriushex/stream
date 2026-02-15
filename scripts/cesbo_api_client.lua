-- Cesbo Stream HTTP API client (compat layer)
--
-- Поддерживает:
-- - baseUrl вида http(s)://host:port (без завершающего "/")
-- - Basic Auth (login/password администратора)
-- - GET /api/* (JSON)
-- - POST /control/ (JSON {"cmd": "...", ...})
-- - таймауты, обработку HTTP ошибок, минимальные retry при сетевых сбоях
--
-- Важно:
-- - не логируем пароль и заголовок Authorization
-- - не делаем агрессивные ретраи (по умолчанию 3 попытки)

CesboApiClient = {}
CesboApiClient.__index = CesboApiClient

local function safe_tostring(v)
    if v == nil then return "" end
    return tostring(v)
end

local function starts_with(s, prefix)
    s = safe_tostring(s)
    prefix = safe_tostring(prefix)
    return s:sub(1, #prefix) == prefix
end

local function trim_slashes_end(s)
    return safe_tostring(s):gsub("/+$", "")
end

local function url_encode(value)
    local s = safe_tostring(value)
    s = s:gsub("\n", "\r\n")
    s = s:gsub("([^%w%-_%.%~ ])", function(c)
        return string.format("%%%02X", string.byte(c))
    end)
    s = s:gsub(" ", "+")
    return s
end

local function build_query(params)
    if type(params) ~= "table" then
        return ""
    end
    local parts = {}
    for k, v in pairs(params) do
        if v ~= nil then
            parts[#parts + 1] = url_encode(k) .. "=" .. url_encode(v)
        end
    end
    table.sort(parts)
    return table.concat(parts, "&")
end

local function join_path(base_path, suffix)
    base_path = safe_tostring(base_path)
    suffix = safe_tostring(suffix)
    if base_path == "" then base_path = "/" end
    if base_path:sub(1, 1) ~= "/" then base_path = "/" .. base_path end
    if suffix == "" then
        return base_path
    end
    if suffix:sub(1, 1) ~= "/" then suffix = "/" .. suffix end
    if base_path == "/" then
        return suffix
    end
    return base_path:gsub("/+$", "") .. suffix
end

local function snip(text, limit)
    local s = safe_tostring(text)
    limit = tonumber(limit) or 200
    if #s <= limit then
        return s
    end
    return s:sub(1, limit) .. "…"
end

local function normalize_http_response(response)
    if type(response) ~= "table" then
        return { code = 0, message = "no response", headers = {}, content = "" }
    end
    local out = {
        code = tonumber(response.code) or 0,
        message = response.message,
        headers = type(response.headers) == "table" and response.headers or {},
        content = response.content,
    }
    return out
end

local function is_network_error(resp)
    -- В этом проекте code=0 обычно означает timeout/connection error.
    return not resp or not resp.code or tonumber(resp.code) == 0
end

local function should_retry(resp)
    if not resp then return true end
    local code = tonumber(resp.code) or 0
    if code == 0 then return true end
    -- Минимально: ретраим только "временные" 5xx.
    if code == 502 or code == 503 or code == 504 then
        return true
    end
    return false
end

local function mk_timer(delay_sec, fn)
    if type(timer) ~= "function" then
        -- В unit-тестах timer может быть переопределён. Если его нет — вызываем сразу.
        return fn()
    end
    return timer({
        interval = delay_sec,
        callback = function(self)
            self:close()
            fn()
        end,
    })
end

local function deep_copy_table(t)
    if type(t) ~= "table" then return t end
    local out = {}
    for k, v in pairs(t) do
        out[k] = deep_copy_table(v)
    end
    return out
end

function CesboApiClient.new(opts)
    opts = type(opts) == "table" and opts or {}
    local base_url = trim_slashes_end(opts.baseUrl or opts.base_url or "")
    if base_url == "" then
        return nil, "baseUrl required"
    end

    local parsed = parse_url(base_url)
    if not parsed then
        return nil, "invalid baseUrl"
    end
    if parsed.format ~= "http" and parsed.format ~= "https" then
        return nil, "unsupported scheme"
    end
    if parsed.format == "https" and not (astra and astra.features and astra.features.ssl) then
        return nil, "https not supported (OpenSSL not available)"
    end

    local self = setmetatable({}, CesboApiClient)
    self.baseUrl = base_url
    self.host = parsed.host
    self.port = parsed.port
    self.tls = (parsed.format == "https")
    self.basePath = parsed.path or "/"

    -- Basic Auth. Можно передать в opts или указать в baseUrl как login:pass@host.
    self.login = safe_tostring(opts.login or parsed.login or "")
    self.password = safe_tostring(opts.password or parsed.password or "")

    -- Таймауты (ms)
    self.connect_timeout_ms = tonumber(opts.connect_timeout_ms) or 800
    self.read_timeout_ms = tonumber(opts.read_timeout_ms) or 2000
    self.timeout_ms = tonumber(opts.timeout_ms) or 3000

    -- Retry
    self.max_attempts = tonumber(opts.max_attempts) or 3
    if self.max_attempts < 1 then self.max_attempts = 1 end
    if self.max_attempts > 3 then self.max_attempts = 3 end
    self.retry_backoff_ms = tonumber(opts.retry_backoff_ms) or 250
    self.retry_jitter_pct = tonumber(opts.retry_jitter_pct) or 20

    self.debug = opts.debug == true
    return self, nil
end

function CesboApiClient:_debug(msg)
    if not self.debug then return end
    if log and log.debug then
        log.debug("[cesbo_api] " .. safe_tostring(msg))
    end
end

function CesboApiClient:_build_headers(extra, body_len)
    local headers = {
        "Host: " .. safe_tostring(self.host) .. ":" .. safe_tostring(self.port),
        "Connection: close",
        "Accept: application/json",
    }

    if self.login ~= "" or self.password ~= "" then
        local auth = base64.encode(self.login .. ":" .. self.password)
        headers[#headers + 1] = "Authorization: Basic " .. auth
    end

    if body_len and body_len > 0 then
        headers[#headers + 1] = "Content-Type: application/json"
        headers[#headers + 1] = "Content-Length: " .. tostring(body_len)
    end

    if type(extra) == "table" then
        for _, line in ipairs(extra) do
            if line and line ~= "" then
                headers[#headers + 1] = tostring(line)
            end
        end
    end
    return headers
end

function CesboApiClient:_request(method, path, query, body_obj, callback)
    if type(http_request) ~= "function" then
        callback(false, "http_request unavailable")
        return
    end
    method = safe_tostring(method):upper()
    if method ~= "GET" and method ~= "POST" then
        callback(false, "unsupported method")
        return
    end

    local full_path = join_path(self.basePath, path)
    local qs = build_query(query)
    if qs ~= "" then
        local sep = full_path:find("%?", 1, true) and "&" or "?"
        full_path = full_path .. sep .. qs
    end

    local body = nil
    if body_obj ~= nil then
        local ok, encoded = pcall(json.encode, body_obj)
        if not ok or not encoded then
            callback(false, "json encode failed")
            return
        end
        body = encoded
    end

    local attempt = 1
    local function do_attempt()
        local headers = self:_build_headers(nil, body and #body or 0)
        self:_debug(method .. " " .. full_path .. " attempt=" .. tostring(attempt))

        http_request({
            host = self.host,
            port = self.port,
            path = full_path,
            method = method,
            ssl = self.tls == true,
            tls = self.tls == true,
            timeout = self.timeout_ms,
            connect_timeout_ms = self.connect_timeout_ms,
            read_timeout_ms = self.read_timeout_ms,
            headers = headers,
            content = body,
            callback = function(_, response)
                local resp = normalize_http_response(response)
                self:_debug(method .. " " .. full_path .. " -> " .. tostring(resp.code))

                if should_retry(resp) and attempt < self.max_attempts then
                    attempt = attempt + 1
                    local delay_ms = self.retry_backoff_ms * (2 ^ (attempt - 2))
                    -- jitter
                    local jitter = (delay_ms * (self.retry_jitter_pct / 100.0))
                    if jitter > 0 then
                        delay_ms = delay_ms + (math.random() * jitter * 2 - jitter)
                    end
                    if delay_ms < 50 then delay_ms = 50 end
                    local delay_sec = delay_ms / 1000.0
                    if is_network_error(resp) then
                        self:_debug("retry after network error: " .. tostring(delay_ms) .. "ms")
                    else
                        self:_debug("retry after http " .. tostring(resp.code) .. ": " .. tostring(delay_ms) .. "ms")
                    end
                    mk_timer(delay_sec, do_attempt)
                    return
                end

                if not resp or not resp.code then
                    callback(false, "no response")
                    return
                end
                if resp.code < 200 or resp.code >= 300 then
                    local detail = snip(resp.content, 200)
                    local msg = "http " .. tostring(resp.code)
                    if detail ~= "" then
                        msg = msg .. ": " .. detail
                    end
                    callback(false, msg, resp)
                    return
                end

                if resp.content == nil or resp.content == "" then
                    callback(true, nil, resp)
                    return
                end
                local ok, decoded = pcall(json.decode, resp.content)
                if not ok then
                    callback(false, "json decode failed", resp)
                    return
                end
                callback(true, decoded, resp)
            end,
        })
    end

    do_attempt()
end

-- ===== Low-level wrappers =====

function CesboApiClient:GetApi(path, query, callback)
    return self:_request("GET", join_path("/api", path), query, nil, callback)
end

function CesboApiClient:PostControl(payload, callback)
    return self:_request("POST", "/control/", nil, payload, callback)
end

local function control_cmd(cmd, extra)
    local payload = { cmd = cmd }
    if type(extra) == "table" then
        for k, v in pairs(extra) do
            payload[k] = v
        end
    end
    return payload
end

-- ===== Process Status API =====

function CesboApiClient:GetSystemStatus(time, callback)
    local t = tonumber(time) or 1
    return self:GetApi("/system-status", { t = tostring(t) }, callback)
end

function CesboApiClient:RestartServer(callback)
    return self:PostControl(control_cmd("restart"), callback)
end

-- ===== DVB Adapters API =====

function CesboApiClient:GetAdapterInfo(id, callback)
    return self:GetApi("/adapter-info/" .. url_encode(id), nil, callback)
end

function CesboApiClient:SetAdapter(id, adapterConfig, callback)
    return self:PostControl(control_cmd("set-adapter", {
        id = safe_tostring(id),
        adapter = adapterConfig or {},
    }), callback)
end

function CesboApiClient:RestartAdapter(id, callback)
    return self:PostControl(control_cmd("restart-adapter", { id = safe_tostring(id) }), callback)
end

function CesboApiClient:RemoveAdapter(id, callback)
    return self:SetAdapter(id, { remove = true }, callback)
end

function CesboApiClient:GetAdapterStatus(id, time, callback)
    local t = tonumber(time) or 1
    return self:GetApi("/adapter-status/" .. url_encode(id), { t = tostring(t) }, callback)
end

-- ===== Streams API =====

function CesboApiClient:GetStreamInfo(id, callback)
    return self:GetApi("/stream-info/" .. url_encode(id), nil, callback)
end

function CesboApiClient:SetStream(id, streamConfig, callback)
    return self:PostControl(control_cmd("set-stream", {
        id = safe_tostring(id),
        stream = streamConfig or {},
    }), callback)
end

function CesboApiClient:ToggleStream(id, callback)
    return self:PostControl(control_cmd("toggle-stream", { id = safe_tostring(id) }), callback)
end

function CesboApiClient:RestartStream(id, callback)
    return self:PostControl(control_cmd("restart-stream", { id = safe_tostring(id) }), callback)
end

function CesboApiClient:SetStreamInput(id, input, callback)
    local payload = control_cmd("set-stream-input", { id = safe_tostring(id) })
    if input ~= nil then
        payload.input = tonumber(input) or input
    end
    return self:PostControl(payload, callback)
end

function CesboApiClient:RemoveStream(id, callback)
    return self:SetStream(id, { remove = true }, callback)
end

function CesboApiClient:GetStreamStatus(id, time, callback)
    local t = tonumber(time) or 1
    return self:GetApi("/stream-status/" .. url_encode(id), { t = tostring(t) }, callback)
end

-- ===== Other API Methods =====

function CesboApiClient:GetVersion(callback)
    return self:PostControl(control_cmd("version"), callback)
end

function CesboApiClient:LoadConfiguration(callback)
    return self:PostControl(control_cmd("load"), callback)
end

function CesboApiClient:UploadConfiguration(cfg, callback)
    return self:PostControl(control_cmd("upload", { config = cfg or {} }), callback)
end

function CesboApiClient:SetLicense(serial, callback)
    return self:PostControl(control_cmd("set-license", { license = safe_tostring(serial) }), callback)
end

function CesboApiClient:SetStreamImage(streamId, url, callback)
    return self:PostControl(control_cmd("set-stream-image", {
        id = safe_tostring(streamId),
        url = safe_tostring(url),
    }), callback)
end

-- ===== Scan API =====

function CesboApiClient:ScanInit(scanAddress, callback)
    return self:PostControl(control_cmd("scan-init", { scan = safe_tostring(scanAddress) }), function(ok, data, resp)
        if not ok then
            callback(false, data, resp)
            return
        end
        if type(data) ~= "table" or data.id == nil then
            callback(false, "scan-init: missing id in response", resp)
            return
        end
        callback(true, data.id, resp)
    end)
end

function CesboApiClient:ScanKill(analyzerId, callback)
    return self:PostControl(control_cmd("scan-kill", { id = safe_tostring(analyzerId) }), callback)
end

function CesboApiClient:ScanCheck(analyzerId, callback)
    return self:PostControl(control_cmd("scan-check", { id = safe_tostring(analyzerId) }), callback)
end

-- ===== Sessions API =====

function CesboApiClient:GetSessions(callback)
    return self:PostControl(control_cmd("sessions"), callback)
end

function CesboApiClient:CloseSession(sessionId, callback)
    return self:PostControl(control_cmd("close-session", { id = safe_tostring(sessionId) }), callback)
end

-- ===== Users API =====

function CesboApiClient:GetUser(login, callback)
    return self:PostControl(control_cmd("get-user", { id = safe_tostring(login) }), callback)
end

function CesboApiClient:SetUser(login, userConfig, passwordPlaintext, callback)
    local user = deep_copy_table(userConfig or {})
    if passwordPlaintext ~= nil then
        user.password = safe_tostring(passwordPlaintext)
    end
    return self:PostControl(control_cmd("set-user", { id = safe_tostring(login), user = user }), callback)
end

function CesboApiClient:RemoveUser(login, callback)
    return self:SetUser(login, { remove = true }, nil, callback)
end

function CesboApiClient:ToggleUser(login, callback)
    return self:PostControl(control_cmd("toggle-user", { id = safe_tostring(login) }), callback)
end
