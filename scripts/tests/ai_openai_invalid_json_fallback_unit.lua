-- AstralAI OpenAI client invalid-json fallback unit test
--
-- Some proxies can return a truncated or otherwise invalid JSON body. The client should
-- fall back to the next model (and/or retry) instead of failing immediately.

dofile("scripts/base.lua")
dofile("scripts/ai_openai_client.lua")

local function assert_true(cond, msg)
    if not cond then
        error(msg or "assert failed")
    end
end

-- Force proxy path in the client.
local orig_getenv = os.getenv
os.getenv = function(key)
    if key == "LLM_PROXY_PRIMARY" then
        return "http://proxy.local:3128"
    end
    if key == "LLM_PROXY_SECONDARY"
        or key == "ASTRAL_LLM_PROXY_PRIMARY"
        or key == "ASTRAL_LLM_PROXY_SECONDARY"
    then
        return ""
    end
    return orig_getenv(key)
end

-- Make timers run synchronously in this test.
timer = function(opts)
    local self = { close = function() end }
    opts.callback(self)
    return self
end

-- Stub process.spawn for curl.
local request_count = 0
local models_seen = {}

process = process or {}
process.spawn = function(args, _opts)
    local cmd = args and args[1] or ""
    if cmd ~= "curl" then
        return nil
    end

    -- curl --version check (ensure_curl_available)
    if args[2] == "--version" then
        return {
            poll = function()
                return { exit_code = 0 }
            end,
            read_stdout = function()
                return "curl 8.0.0\n"
            end,
            read_stderr = function()
                return ""
            end,
            close = function() end,
        }
    end

    request_count = request_count + 1

    local response_path = nil
    local headers_path = nil
    local data_value = nil
    for i = 1, #args do
        if args[i] == "-o" then
            response_path = args[i + 1]
        elseif args[i] == "-D" then
            headers_path = args[i + 1]
        elseif args[i] == "--data-binary" then
            data_value = args[i + 1]
        end
    end

    assert_true(type(response_path) == "string" and response_path ~= "", "curl must use -o <file> for response body")
    assert_true(type(headers_path) == "string" and headers_path ~= "", "curl must use -D <file> for headers")

    if type(data_value) == "string" and data_value:sub(1, 1) == "@" then
        local path = data_value:sub(2)
        local fh = io.open(path, "rb")
        assert_true(fh ~= nil, "failed to open request body file")
        local req_body = fh:read("*a") or ""
        fh:close()
        local ok, decoded = pcall(json.decode, req_body)
        assert_true(ok and type(decoded) == "table", "request body must be json")
        table.insert(models_seen, tostring(decoded.model or ""))
    end

    -- Minimal headers (rate-limits) to exercise parsing.
    local hh = io.open(headers_path, "wb")
    assert_true(hh ~= nil, "failed to open headers temp file")
    hh:write("x-ratelimit-limit-requests: 5000\n")
    hh:write("x-ratelimit-remaining-requests: 4999\n")
    hh:close()

    -- Response: first request returns truncated JSON; second request returns a valid response.
    local fh = io.open(response_path, "wb")
    assert_true(fh ~= nil, "failed to open response temp file")
    if request_count == 1 then
        fh:write("{ \"id\": \"resp_bad\", \"object\": \"response\"") -- missing closing braces
    else
        local output_text = json.encode({ summary = "hi", ops = {}, warnings = {} })
        local body = json.encode({
            output = {
                {
                    type = "message",
                    content = {
                        { type = "output_text", text = output_text },
                    },
                },
            },
        })
        fh:write(body)
    end
    fh:close()

    return {
        poll = function()
            return { exit_code = 0 }
        end,
        read_stdout = function()
            return "\nHTTP_STATUS:200\n"
        end,
        read_stderr = function()
            return ""
        end,
        close = function() end,
    }
end

local ok_result, result_or_err = nil, nil

local started, start_err = ai_openai_client.request_json_schema({
    input = "test",
    api_key = "sk-test",
    api_base = "https://api.openai.com",
    json_schema = {
        name = "unit_test",
        strict = true,
        schema = { type = "object", additionalProperties = true },
    },
    model = "gpt-5-nano",
    max_attempts = 3,
}, function(ok, result)
    ok_result = ok
    result_or_err = result
end)

assert_true(started == true, start_err or "request should start")
assert_true(ok_result == true, "request should succeed after fallback")
assert_true(type(result_or_err) == "table", "result must be object")
assert_true(result_or_err.summary == "hi", "decoded output json must be returned")
assert_true(#models_seen >= 2, "client should fall back to another model on invalid json")
assert_true(models_seen[1] ~= models_seen[2], "fallback model must differ from primary")

print("ai_openai_invalid_json_fallback_unit: ok")
astra.exit()

