-- AstralAI OpenAI client (Responses API + Structured Outputs)

ai_openai_client = ai_openai_client or {}

ai_openai_client.config = ai_openai_client.config or {
    timeout_sec = 30,
    max_attempts = 3,
    retry_schedule = { 1, 5, 15 },
}

local function setting_string(key, fallback)
    if config and config.get_setting then
        local value = config.get_setting(key)
        if value ~= nil and value ~= "" then
            return tostring(value)
        end
    end
    return fallback
end

local function normalize_headers(headers)
    if type(headers) ~= "table" then
        return {}
    end
    local out = {}
    for k, v in pairs(headers) do
        if type(k) == "string" then
            out[string.lower(k)] = v
        end
    end
    return out
end

local function parse_rate_limits(headers)
    if type(headers) ~= "table" then
        return {}
    end
    local out = {}
    local keys = {
        "x-ratelimit-limit-requests",
        "x-ratelimit-remaining-requests",
        "x-ratelimit-reset-requests",
        "x-ratelimit-limit-tokens",
        "x-ratelimit-remaining-tokens",
        "x-ratelimit-reset-tokens",
    }
    for _, key in ipairs(keys) do
        if headers[key] then
            out[key] = headers[key]
        end
    end
    return out
end

local function should_retry(code)
    if not code then
        return false
    end
    if code == 429 or code == 408 or code == 409 then
        return true
    end
    if code >= 500 and code < 600 then
        return true
    end
    return false
end

local function extract_output_json(response)
    if type(response) ~= "table" then
        return nil, "invalid response"
    end
    if type(response.output) ~= "table" then
        return nil, "missing output"
    end
    for _, item in ipairs(response.output) do
        if item.type == "message" and type(item.content) == "table" then
            for _, chunk in ipairs(item.content) do
                if chunk.type == "output_text" and chunk.text and chunk.text ~= "" then
                    return chunk.text
                end
            end
        end
    end
    return nil, "output text missing"
end

function ai_openai_client.resolve_api_key()
    local key = setting_string("ai_api_key", "")
    if key ~= "" then
        return key
    end
    key = os.getenv("ASTRAL_OPENAI_API_KEY")
    if key == nil or key == "" then
        key = os.getenv("OPENAI_API_KEY")
    end
    if key == nil or key == "" then
        return nil
    end
    return key
end

function ai_openai_client.resolve_api_base()
    local base = setting_string("ai_api_base", "")
    if base ~= "" then
        return base
    end
    base = os.getenv("ASTRAL_OPENAI_API_BASE")
    if base == nil or base == "" then
        base = "https://api.openai.com"
    end
    return base
end

function ai_openai_client.has_api_key()
    return ai_openai_client.resolve_api_key() ~= nil
end

local function build_url(base)
    local parsed = parse_url(base)
    if not parsed or not parsed.host then
        return nil, "invalid api base"
    end
    local path = parsed.path or "/"
    if path:sub(-1) == "/" then
        path = path:sub(1, -2)
    end
    return {
        host = parsed.host,
        port = parsed.port or 443,
        tls = (parsed.format == "https"),
        path = path .. "/v1/responses",
    }
end

function ai_openai_client.request_json_schema(opts, callback)
    if type(callback) ~= "function" then
        return nil, "callback required"
    end
    if not http_request then
        return nil, "http_request unavailable"
    end
    if type(opts) ~= "table" then
        return nil, "invalid options"
    end
    local input = opts.input
    if type(input) ~= "string" and type(input) ~= "table" then
        return nil, "input required"
    end
    if type(input) == "string" and input == "" then
        return nil, "input required"
    end
    if type(input) == "table" and next(input) == nil then
        return nil, "input required"
    end
    local schema = opts.json_schema
    if type(schema) ~= "table" then
        return nil, "json_schema required"
    end
    local api_key = opts.api_key or ai_openai_client.resolve_api_key()
    if not api_key then
        return nil, "api key missing"
    end
    local api_base = opts.api_base or ai_openai_client.resolve_api_base()
    local url, url_err = build_url(api_base)
    if not url then
        return nil, url_err
    end

    local max_attempts = tonumber(opts.max_attempts) or ai_openai_client.config.max_attempts or 3
    local retry_schedule = opts.retry_schedule or ai_openai_client.config.retry_schedule or { 1, 5, 15 }
    local timeout = tonumber(opts.timeout_sec) or ai_openai_client.config.timeout_sec or 30
    local attempts = 0

    local function perform_request()
        attempts = attempts + 1
        local payload = {
            model = opts.model,
            input = input,
            max_output_tokens = opts.max_output_tokens or 512,
            temperature = opts.temperature or 0,
            store = opts.store == true,
            parallel_tool_calls = false,
            text = {
                format = {
                    type = "json_schema",
                    json_schema = schema,
                },
            },
        }
        local body = json.encode(payload)
        http_request({
            host = url.host,
            port = url.port,
            path = url.path,
            method = "POST",
            timeout = timeout,
            tls = url.tls,
            headers = {
                "Content-Type: application/json",
                "Authorization: Bearer " .. api_key,
                "Connection: close",
            },
            content = body,
            callback = function(_, response)
                local meta = {
                    attempts = attempts,
                    code = response and response.code or nil,
                    rate_limits = parse_rate_limits(normalize_headers(response and response.headers or {})),
                }
                if not response or not response.code then
                    return callback(false, "no response", meta)
                end
                if response.code < 200 or response.code >= 300 then
                    if should_retry(response.code) and attempts < max_attempts then
                        local delay = retry_schedule[attempts] or retry_schedule[#retry_schedule] or 15
                        if type(opts.on_retry) == "function" then
                            pcall(opts.on_retry, attempts, delay, meta)
                        end
                        schedule_retry(delay)
                        return
                    end
                    return callback(false, "http " .. tostring(response.code), meta)
                end
                if not response.content then
                    return callback(false, "empty response", meta)
                end
                local decoded = json.decode(response.content)
                if type(decoded) ~= "table" then
                    return callback(false, "invalid json", meta)
                end
                local text, err = extract_output_json(decoded)
                if not text then
                    return callback(false, err or "missing output", meta)
                end
                local parsed_out = json.decode(text)
                if type(parsed_out) ~= "table" then
                    return callback(false, "invalid output json", meta)
                end
                return callback(true, parsed_out, meta)
            end,
        })
    end

    local function schedule_retry(delay)
        timer({
            interval = delay,
            callback = function(self)
                self:close()
                perform_request()
            end,
        })
    end

    perform_request()
    return true
end

ai_openai_client._test = {
    normalize_headers = normalize_headers,
    parse_rate_limits = parse_rate_limits,
    should_retry = should_retry,
}
