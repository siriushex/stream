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
        "retry-after",
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

local function parse_duration_seconds(value)
    if value == nil then
        return nil
    end
    local text = tostring(value):lower():gsub("^%s+", ""):gsub("%s+$", "")
    if text == "" then
        return nil
    end
    local number, unit = text:match("^(%d+%.?%d*)([a-z]+)$")
    if not number then
        number = text:match("^(%d+%.?%d*)$")
        if not number then
            return nil
        end
        unit = "s"
    end
    local n = tonumber(number)
    if not n then
        return nil
    end
    if unit == "ms" then
        return n / 1000
    end
    if unit == "s" or unit == "sec" or unit == "secs" then
        return n
    end
    if unit == "second" or unit == "seconds" then
        return n
    end
    if unit == "m" or unit == "min" or unit == "mins" then
        return n * 60
    end
    if unit == "minute" or unit == "minutes" then
        return n * 60
    end
    if unit == "h" or unit == "hr" or unit == "hrs" then
        return n * 3600
    end
    if unit == "hour" or unit == "hours" then
        return n * 3600
    end
    return nil
end

local function extract_retry_after_seconds(text)
    if type(text) ~= "string" or text == "" then
        return nil
    end
    local lower = text:lower()
    -- OpenAI (and some proxies) embed retry hints in error messages:
    -- "Please try again in 20s" / "try again in 2 seconds" / "retry after 100ms".
    local raw = lower:match("try again in%s+([%d%.]+%s*[a-z]+)")
        or lower:match("retry after%s+([%d%.]+%s*[a-z]+)")
        or lower:match("please retry in%s+([%d%.]+%s*[a-z]+)")
    if not raw then
        return nil
    end
    raw = raw:gsub("%s+", "")
    return parse_duration_seconds(raw)
end

function ai_openai_client.compute_retry_delay(meta, fallback_delay)
    local delay = tonumber(fallback_delay) or 15
    local rl = type(meta) == "table" and meta.rate_limits or nil
    local has_rl = false
    if type(rl) == "table" then
        for _ in pairs(rl) do
            has_rl = true
            break
        end
        local function apply_candidate(candidate)
            local parsed = parse_duration_seconds(candidate)
            if parsed and parsed > delay then
                delay = parsed
            end
        end
        apply_candidate(rl["retry-after"])
        apply_candidate(rl["x-ratelimit-reset-requests"])
        apply_candidate(rl["x-ratelimit-reset-tokens"])
    end
    if type(meta) == "table" then
        local from_msg = extract_retry_after_seconds(meta.error_detail)
        if from_msg and from_msg > delay then
            delay = from_msg
        end
        -- If we got HTTP 429 without rate-limit headers, fall back to safer defaults.
        -- This avoids rapid-fire retries against proxies that strip headers.
        if meta.code == 429 and not has_rl then
            local attempt = tonumber(meta.attempts) or 1
            local min_delay = 10
            if attempt >= 3 then
                min_delay = 60
            elseif attempt >= 2 then
                min_delay = 30
            end
            if delay < min_delay then
                delay = min_delay
            end
        end
    end
    delay = math.ceil(delay)
    if delay < 1 then
        delay = 1
    end
    if delay > 300 then
        delay = 300
    end
    return delay
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

local function make_temp_path(prefix, ext)
    local path = os.tmpname()
    if type(path) ~= "string" or path == "" then
        local suffix = ext or ""
        path = "/tmp/" .. tostring(prefix or "astral-ai")
            .. "-" .. tostring(os.time())
            .. "-" .. tostring(math.random(100000, 999999))
            .. suffix
    end
    return path
end

local function read_text_file(path)
    if type(path) ~= "string" or path == "" then
        return ""
    end
    local ok, fh = pcall(io.open, path, "rb")
    if not ok or not fh then
        return ""
    end
    local text = fh:read("*a") or ""
    fh:close()
    return text
end

local function write_temp_body(body)
    if type(body) ~= "string" or body == "" then
        return nil
    end
    local path = make_temp_path("astral-ai-body", ".json")
    local ok, fh = pcall(io.open, path, "wb")
    if not ok or not fh then
        return nil
    end
    fh:write(body)
    fh:close()
    return path
end

local function extract_error_message(body)
    if type(body) ~= "string" or body == "" then
        return nil
    end
    local ok, decoded = pcall(json.decode, body)
    if not ok or type(decoded) ~= "table" then
        return nil
    end
    if decoded.message and decoded.message ~= "" then
        return tostring(decoded.message)
    end
    local err = decoded.error
    if type(err) == "string" and err ~= "" then
        return tostring(err)
    end
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

local function snip_error_body(body, limit)
    if type(body) ~= "string" then
        return nil
    end
    local text = body:gsub("%s+", " "):gsub("^%s+", ""):gsub("%s+$", "")
    if text == "" then
        return nil
    end
    local max_len = tonumber(limit) or 200
    if #text > max_len then
        text = text:sub(1, max_len) .. "…"
    end
    return text
end

local function sanitize_utf8(text)
    if type(text) ~= "string" or text == "" then
        return text
    end
    local out = {}
    local i = 1
    local len = #text
    while i <= len do
        local c = text:byte(i)
        if c < 0x20 or c == 0x7F then
            -- Never send ASCII control bytes to OpenAI: some JSON parsers reject them.
            table.insert(out, " ")
            i = i + 1
        elseif c < 0x80 then
            table.insert(out, string.char(c))
            i = i + 1
        elseif c >= 0xC2 and c <= 0xDF then
            local c2 = text:byte(i + 1)
            if c2 and c2 >= 0x80 and c2 <= 0xBF then
                table.insert(out, text:sub(i, i + 1))
                i = i + 2
            else
                table.insert(out, "?")
                i = i + 1
            end
        elseif c >= 0xE0 and c <= 0xEF then
            local c2, c3 = text:byte(i + 1), text:byte(i + 2)
            if c2 and c3 and c2 >= 0x80 and c2 <= 0xBF and c3 >= 0x80 and c3 <= 0xBF then
                table.insert(out, text:sub(i, i + 2))
                i = i + 3
            else
                table.insert(out, "?")
                i = i + 1
            end
        elseif c >= 0xF0 and c <= 0xF4 then
            local c2, c3, c4 = text:byte(i + 1), text:byte(i + 2), text:byte(i + 3)
            if c2 and c3 and c4
                and c2 >= 0x80 and c2 <= 0xBF
                and c3 >= 0x80 and c3 <= 0xBF
                and c4 >= 0x80 and c4 <= 0xBF then
                table.insert(out, text:sub(i, i + 3))
                i = i + 4
            else
                table.insert(out, "?")
                i = i + 1
            end
        else
            table.insert(out, "?")
            i = i + 1
        end
    end
    return table.concat(out)
end

local function scrub_json_body(body)
    if type(body) ~= "string" or body == "" then
        return body, 0
    end
    -- Replace all control bytes (including newline/tab) with spaces, then ensure UTF-8.
    local out, n = body:gsub("[%z\1-\31\127]", " ")
    out = sanitize_utf8(out)
    return out, n
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

local function parse_curl_headers(raw)
    if type(raw) ~= "string" or raw == "" then
        return {}
    end
    local out = {}
    for line in raw:gmatch("[^\r\n]+") do
        local key, value = line:match("^([^:]+):%s*(.*)$")
        if key and value then
            out[tostring(key):lower()] = value
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

local function detect_quota_exceeded_429(body)
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
    if err_code == "insufficient_quota" or err_code == "billing_hard_limit_reached" then
        return true
    end
    local msg = tostring(err.message or ""):lower()
    if msg:find("exceeded your current quota", 1, true) then
        return true
    end
    if msg:find("insufficient quota", 1, true) then
        return true
    end
    if msg:find("billing") and msg:find("hard limit") then
        return true
    end
    return false
end

local function model_supports_temperature(model)
    if type(model) ~= "string" or model == "" then
        return true
    end
    -- OpenAI API rejects temperature/top_p for older GPT-5 models (gpt-5, gpt-5-mini, gpt-5-nano).
    -- Keep requests compatible by omitting these params for those models.
    if model == "gpt-5" or model == "gpt-5-mini" or model == "gpt-5-nano" then
        return false
    end
    return true
end

local function should_retry_response(code, body)
    if not should_retry(code) then
        return false
    end
    if code == 429 and detect_quota_exceeded_429(body) then
        return false
    end
    return true
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

local function detect_response_format_error(code, body)
    if code ~= 400 then
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
    if err_code:find("response_format") or err_code:find("json_schema") then
        return true
    end
    local msg = tostring(err.message or ""):lower()
    if msg:find("response_format") or msg:find("json schema") or msg:find("structured output") then
        return true
    end
    if msg:find("does not support") and (msg:find("response") or msg:find("json")) then
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

    -- OpenAI Responses API expects json schema fields at `text.format.*`:
    -- { type="json_schema", name="...", schema={...}, strict=true }.
    -- Internally we use the common `{ name, strict, schema }` object, so map it.
    local text_format = {
        type = "json_schema",
        name = schema.name,
        schema = schema.schema,
        strict = schema.strict,
    }
    if type(text_format.name) ~= "string" or text_format.name == "" then
        text_format.name = "astral_schema"
    end
    if type(text_format.schema) ~= "table" then
        return nil, "json_schema.schema required"
    end
    if text_format.strict == nil then
        text_format.strict = true
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
        primary_model = "gpt-5-mini"
    end
    table.insert(models, primary_model)
    local fallbacks = opts.model_fallbacks or opts.fallback_models
    if type(fallbacks) ~= "table" then
        if primary_model == "gpt-5.2" or primary_model == "gpt-5.1" then
            fallbacks = { "gpt-5-mini", "gpt-4.1" }
        else
            fallbacks = { "gpt-5.2", "gpt-4.1" }
        end
    end
    for _, name in ipairs(fallbacks) do
        if type(name) == "string" and name ~= "" and name ~= primary_model then
            table.insert(models, name)
        end
    end
    local model_index = 1
    local input_no_images = strip_input_images(input)
    local stripped_images = false

    -- Forward declare: perform_request uses schedule_retry for backoff retries.
    local schedule_retry

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
            store = opts.store == true,
            parallel_tool_calls = false,
            text = {
                format = {
                    type = text_format.type,
                    name = text_format.name,
                    schema = text_format.schema,
                    strict = text_format.strict,
                },
            },
        }
        if opts.temperature ~= nil and model_supports_temperature(models[model_index]) then
            payload.temperature = opts.temperature
        end
        local body = json.encode(payload)
        local scrubbed = 0
        body, scrubbed = scrub_json_body(body)
        local ok_local = pcall(json.decode, body)
        if not ok_local then
            return callback(false, "invalid json body (local encode)", {
                attempts = attempts,
                code = 0,
                model = models[model_index],
                scrubbed_control_bytes = scrubbed > 0 and scrubbed or nil,
                error_detail = "local json.encode produced invalid json",
            })
        end
        local body_path = nil
        local headers_path = nil
        local response_path = nil
        if #proxies > 0 then
            body_path = write_temp_body(body)
            headers_path = make_temp_path("astral-ai-headers", ".txt")
            response_path = make_temp_path("astral-ai-response", ".json")
        end
        local function cleanup_temp()
            if body_path then
                pcall(os.remove, body_path)
                body_path = nil
            end
            if headers_path then
                pcall(os.remove, headers_path)
                headers_path = nil
            end
            if response_path then
                pcall(os.remove, response_path)
                response_path = nil
            end
        end
        local function read_rate_headers()
            if not headers_path then
                return {}
            end
            return parse_curl_headers(read_text_file(headers_path))
        end
        if #proxies > 0 then
            if not ensure_curl_available() then
                cleanup_temp()
                return callback(false, "curl unavailable for proxy", { attempts = attempts })
            end

            local function handle_result(ok, response_body, response_code, err_text)
                local rate_headers = read_rate_headers()
                cleanup_temp()
                local meta = {
                    attempts = attempts,
                    code = response_code,
                    rate_limits = parse_rate_limits(rate_headers),
                    model = models[model_index],
                }
                if scrubbed > 0 then
                    meta.scrubbed_control_bytes = scrubbed
                end
                local err_detail = extract_error_message(response_body or "") or snip_error_body(response_body, 200)
                meta.error_detail = err_detail
                if detect_model_not_found(response_code, response_body) and model_index < #models then
                    model_index = model_index + 1
                    return perform_request()
                end
                if detect_response_format_error(response_code, response_body) and model_index < #models then
                    model_index = model_index + 1
                    return perform_request()
                end
                if response_code == 400 and not stripped_images and input_no_images and detect_image_error(err_detail or response_body or "") then
                    stripped_images = true
                    return perform_request()
                end
                if not ok then
                    if should_retry_response(response_code, response_body) and attempts < max_attempts then
                        local delay = retry_schedule[attempts] or retry_schedule[#retry_schedule] or 15
                        delay = ai_openai_client.compute_retry_delay(meta, delay)
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
                local data_value = body_path and ("@" .. body_path) or body
                local args = {
                    "curl",
                    "-sS",
                    "-m",
                    tostring(timeout),
                    "--connect-timeout",
                    tostring(math.min(5, timeout)),
                    "-D",
                    headers_path or "/dev/null",
                    "-o",
                    response_path or "/dev/null",
                    "-H",
                    "Content-Type: application/json",
                    "-H",
                    "Authorization: Bearer " .. api_key,
                    "-X",
                    "POST",
                    (api_base:gsub("/+$", "") .. "/v1/responses"),
                    "--data-binary",
                    data_value,
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
                local poll_interval = 1
                timer({
                    interval = poll_interval,
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
                        local _, status_code = split_curl_output(stdout or "")
                        local body_out = response_path and read_text_file(response_path) or ""
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
                "Host: " .. url.host,
                "User-Agent: astral-ai",
                "Content-Type: application/json",
                "Content-Length: " .. tostring(#body),
                "Authorization: Bearer " .. api_key,
                "Connection: close",
            },
            content = body,
            callback = function(_, response)
                local meta = {
                    attempts = attempts,
                    code = response and response.code or nil,
                    rate_limits = parse_rate_limits(normalize_headers(response and response.headers or {})),
                    model = models[model_index],
                }
                if scrubbed > 0 then
                    meta.scrubbed_control_bytes = scrubbed
                end
                local err_detail = extract_error_message(response and response.content or "")
                    or snip_error_body(response and response.content or "", 200)
                meta.error_detail = err_detail
                if not response or not response.code then
                    return callback(false, "no response", meta)
                end
                if response.code < 200 or response.code >= 300 then
                    if detect_model_not_found(response.code, response.content or "") and model_index < #models then
                        model_index = model_index + 1
                        perform_request()
                        return
                    end
                    if detect_response_format_error(response.code, response.content or "") and model_index < #models then
                        model_index = model_index + 1
                        perform_request()
                        return
                    end
                    if response.code == 400 and not stripped_images and input_no_images and detect_image_error(err_detail or response.content or "") then
                        stripped_images = true
                        perform_request()
                        return
                    end
                    if should_retry_response(response.code, response.content or "") and attempts < max_attempts then
                        local delay = retry_schedule[attempts] or retry_schedule[#retry_schedule] or 15
                        delay = ai_openai_client.compute_retry_delay(meta, delay)
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

    schedule_retry = function(delay)
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
    scrub_json_body = scrub_json_body,
}
