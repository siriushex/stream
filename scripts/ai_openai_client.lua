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

local function normalize_proxy(value)
    if type(value) ~= "string" then
        return nil
    end
    value = value:gsub("%s+", "")
    if value == "" then
        return nil
    end
    return value
end

local function normalize_api_base(value)
    if type(value) ~= "string" then
        return value
    end
    local out = value:gsub("^%s+", ""):gsub("%s+$", "")
    if out:sub(-1) == "/" then
        out = out:sub(1, -2)
    end
    if out:match("/v1$") then
        out = out:sub(1, -4)
    end
    return out
end

local function extract_error_message(body)
    if type(body) ~= "string" or body == "" then
        return nil
    end
    local ok, decoded = pcall(json.decode, body)
    if not ok or type(decoded) ~= "table" then
        return nil
    end
    local err = decoded.error
    if type(err) ~= "table" then
        return nil
    end
    if err.message and err.message ~= "" then
        return tostring(err.message)
    end
    if err.code and err.code ~= "" then
        return tostring(err.code)
    end
    if err.type and err.type ~= "" then
        return tostring(err.type)
    end
    return nil
end

local function detect_image_error(body)
    local msg = ""
    if type(body) == "string" then
        msg = body:lower()
    end
    return (msg:find("image") or msg:find("input_image") or msg:find("vision") or msg:find("data url") or msg:find("data_url")) ~= nil
end

local function resolve_proxy_list()
    local proxies = {}
    local primary = normalize_proxy(os.getenv("LLM_PROXY_PRIMARY")) or normalize_proxy(os.getenv("ASTRAL_LLM_PROXY_PRIMARY"))
    local secondary = normalize_proxy(os.getenv("LLM_PROXY_SECONDARY")) or normalize_proxy(os.getenv("ASTRAL_LLM_PROXY_SECONDARY"))
    if primary then
        table.insert(proxies, primary)
    end
    if secondary then
        table.insert(proxies, secondary)
    end
    return proxies
end

local function ensure_curl_available()
    if ai_openai_client.curl_available ~= nil then
        return ai_openai_client.curl_available
    end
    if not process or type(process.spawn) ~= "function" then
        ai_openai_client.curl_available = false
        return false
    end
    local ok, proc = pcall(process.spawn, { "curl", "--version" }, { stdout = "pipe", stderr = "pipe" })
    if not ok or not proc then
        ai_openai_client.curl_available = false
        return false
    end
    local status = proc:poll()
    if status and status.exit_code and status.exit_code ~= 0 then
        ai_openai_client.curl_available = false
    else
        ai_openai_client.curl_available = true
    end
    proc:close()
    return ai_openai_client.curl_available
end

local function split_curl_output(raw)
    if type(raw) ~= "string" or raw == "" then
        return "", nil
    end
    local status = raw:match("HTTP_STATUS:(%d%d%d)")
    if status then
        local body = raw:gsub("\nHTTP_STATUS:%d%d%d\n?$", "")
        return body, tonumber(status)
    end
    return raw, nil
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

local function detect_model_not_found(code, body)
    if code ~= 400 and code ~= 404 then
        return false
    end
    if type(body) ~= "string" or body == "" then
        return false
    end
    local ok, decoded = pcall(json.decode, body)
    if not ok or type(decoded) ~= "table" then
        return false
    end
    local err = decoded.error
    if type(err) ~= "table" then
        return false
    end
    local err_code = tostring(err.code or err.type or ""):lower()
    if err_code == "model_not_found" then
        return true
    end
    local msg = tostring(err.message or ""):lower()
    if msg:find("model") and (msg:find("not found") or msg:find("does not exist") or msg:find("no longer available")) then
        return true
    end
    return false
end

local function strip_input_images(input)
    if type(input) ~= "table" then
        return nil
    end
    local changed = false
    local out = {}
    for _, msg in ipairs(input) do
        if type(msg) == "table" and type(msg.content) == "table" then
            local content = {}
            for _, chunk in ipairs(msg.content) do
                if type(chunk) == "table" and chunk.type == "input_image" then
                    changed = true
                else
                    table.insert(content, chunk)
                end
            end
            local new_msg = {}
            for k, v in pairs(msg) do
                new_msg[k] = v
            end
            new_msg.content = content
            table.insert(out, new_msg)
        else
            table.insert(out, msg)
        end
    end
    if not changed then
        return nil
    end
    return out
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
        return normalize_api_base(base)
    end
    base = os.getenv("ASTRAL_OPENAI_API_BASE")
    if base == nil or base == "" then
        base = "https://api.openai.com"
    end
    return normalize_api_base(base)
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
    if path:match("/v1$") then
        path = path:sub(1, -4)
    end
    if path == "" then
        path = ""
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
    api_base = normalize_api_base(api_base)
    local url, url_err = build_url(api_base)
    if not url then
        return nil, url_err
    end

    local max_attempts = tonumber(opts.max_attempts) or ai_openai_client.config.max_attempts or 3
    local retry_schedule = opts.retry_schedule or ai_openai_client.config.retry_schedule or { 1, 5, 15 }
    local timeout = tonumber(opts.timeout_sec) or ai_openai_client.config.timeout_sec or 30
    local attempts = 0
    local proxies = resolve_proxy_list()
    local models = {}
    local primary_model = opts.model
    if type(primary_model) ~= "string" or primary_model == "" then
        primary_model = "gpt-5.2"
    end
    table.insert(models, primary_model)
    local fallbacks = opts.model_fallbacks or opts.fallback_models
    if type(fallbacks) ~= "table" then
        fallbacks = { "gpt-5-mini", "gpt-4.1" }
    end
    for _, name in ipairs(fallbacks) do
        if type(name) == "string" and name ~= "" and name ~= primary_model then
            table.insert(models, name)
        end
    end
    local model_index = 1
    local input_no_images = strip_input_images(input)
    local stripped_images = false

    local function perform_request()
        attempts = attempts + 1
        local payload_input = input
        if stripped_images and input_no_images then
            payload_input = input_no_images
        end
        local payload = {
            model = models[model_index],
            input = payload_input,
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
        if #proxies > 0 then
            if not ensure_curl_available() then
                return callback(false, "curl unavailable for proxy", { attempts = attempts })
            end

            local function handle_result(ok, response_body, response_code, err_text)
                local meta = {
                    attempts = attempts,
                    code = response_code,
                    rate_limits = {},
                }
                local err_detail = extract_error_message(response_body or "")
                if detect_model_not_found(response_code, response_body) and model_index < #models then
                    model_index = model_index + 1
                    return perform_request()
                end
                if response_code == 400 and not stripped_images and input_no_images and detect_image_error(err_detail or response_body or "") then
                    stripped_images = true
                    return perform_request()
                end
                if not ok then
                    if should_retry(response_code) and attempts < max_attempts then
                        local delay = retry_schedule[attempts] or retry_schedule[#retry_schedule] or 15
                        if type(opts.on_retry) == "function" then
                            pcall(opts.on_retry, attempts, delay, meta)
                        end
                        schedule_retry(delay)
                        return
                    end
                    local msg = err_text or "request failed"
                    if err_detail and err_detail ~= "" then
                        msg = msg .. ": " .. err_detail
                    end
                    return callback(false, msg, meta)
                end
                local decoded = json.decode(response_body or "")
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
            end

            local function spawn_curl(proxy_url)
                local args = {
                    "curl",
                    "-sS",
                    "-m",
                    tostring(timeout),
                    "--connect-timeout",
                    tostring(math.min(5, timeout)),
                    "-H",
                    "Content-Type: application/json",
                    "-H",
                    "Authorization: Bearer " .. api_key,
                    "-X",
                    "POST",
                    (api_base:gsub("/+$", "") .. "/v1/responses"),
                    "--data-binary",
                    body,
                    "-w",
                    "\nHTTP_STATUS:%{http_code}\n",
                }
                if proxy_url then
                    table.insert(args, "--proxy")
                    table.insert(args, proxy_url)
                end
                local ok, proc = pcall(process.spawn, args, { stdout = "pipe", stderr = "pipe" })
                if not ok or not proc then
                    return nil, "spawn failed"
                end
                return proc, nil
            end

            local function attempt_proxy(index)
                local proxy_url = proxies[index]
                if not proxy_url then
                    return handle_result(false, nil, 0, "proxy failed")
                end
                local proc, err = spawn_curl(proxy_url)
                if not proc then
                    if index < #proxies then
                        return attempt_proxy(index + 1)
                    end
                    return handle_result(false, nil, 0, err or "spawn failed")
                end
                timer({
                    interval = 0.2,
                    callback = function(self)
                        local status = proc:poll()
                        if not status then
                            return
                        end
                        self:close()
                        local stdout = proc:read_stdout()
                        local stderr = proc:read_stderr()
                        proc:close()
                        if status.exit_code and status.exit_code ~= 0 then
                            if index < #proxies then
                                return attempt_proxy(index + 1)
                            end
                            return handle_result(false, nil, 0, stderr or "curl failed")
                        end
                        local body_out, status_code = split_curl_output(stdout or "")
                        if not status_code or status_code == 0 then
                            if index < #proxies then
                                return attempt_proxy(index + 1)
                            end
                            return handle_result(false, nil, 0, "no status")
                        end
                        if status_code < 200 or status_code >= 300 then
                            if index < #proxies then
                                return attempt_proxy(index + 1)
                            end
                            return handle_result(false, body_out or "", status_code, "http " .. tostring(status_code))
                        end
                        return handle_result(true, body_out or "", status_code, nil)
                    end,
                })
            end

            attempt_proxy(1)
            return
        end

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
                local err_detail = extract_error_message(response and response.content or "")
                if not response or not response.code then
                    return callback(false, "no response", meta)
                end
                if response.code < 200 or response.code >= 300 then
                    if detect_model_not_found(response.code, response.content or "") and model_index < #models then
                        model_index = model_index + 1
                        perform_request()
                        return
                    end
                    if response.code == 400 and not stripped_images and input_no_images and detect_image_error(err_detail or response.content or "") then
                        stripped_images = true
                        perform_request()
                        return
                    end
                    if should_retry(response.code) and attempts < max_attempts then
                        local delay = retry_schedule[attempts] or retry_schedule[#retry_schedule] or 15
                        if type(opts.on_retry) == "function" then
                            pcall(opts.on_retry, attempts, delay, meta)
                        end
                        schedule_retry(delay)
                        return
                    end
                    local msg = "http " .. tostring(response.code)
                    if err_detail and err_detail ~= "" then
                        msg = msg .. ": " .. err_detail
                    end
                    return callback(false, msg, meta)
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
    detect_model_not_found = detect_model_not_found,
    build_url = build_url,
}
