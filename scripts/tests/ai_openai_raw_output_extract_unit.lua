-- AstralAI OpenAI client raw output_text extraction unit test
--
-- If the outer OpenAI response JSON cannot be decoded (proxy truncation / trailing junk),
-- the client should still be able to extract the `output_text` JSON string and decode it.

dofile("scripts/base.lua")
dofile("scripts/ai_openai_client.lua")

local function assert_true(cond, msg)
    if not cond then
        error(msg or "assert failed")
    end
end

-- Force proxy path.
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

-- Synchronous timers for unit tests.
timer = function(opts)
    local self = { close = function() end }
    opts.callback(self)
    return self
end

local request_count = 0
process = process or {}

-- Outer body is intentionally invalid JSON (trailing comma), but contains a valid output_text JSON string.
local inner = json.encode({ summary = "hi", ops = {}, warnings = {} })
local function json_quote(text)
    -- Minimal JSON string quoting for this unit test (enough for the generated inner JSON).
    return "\"" .. tostring(text):gsub("\\", "\\\\"):gsub("\"", "\\\"") .. "\""
end
local outer = "{"
    .. "\"output_text\":" .. json_quote(inner)
    .. ",}" -- invalid JSON

do
    local candidates = ai_openai_client._test and ai_openai_client._test.extract_output_text_candidates
        and ai_openai_client._test.extract_output_text_candidates(outer)
        or {}
    assert_true(#candidates >= 1, "extract_output_text_candidates must find output_text value")
    assert_true(candidates[1]:find("\"summary\"", 1, true) ~= nil, "candidate must look like json output")
end

process.spawn = function(args, _opts)
    local cmd = args and args[1] or ""
    if cmd ~= "curl" then
        return nil
    end

    -- curl --version check
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
    for i = 1, #args do
        if args[i] == "-o" then
            response_path = args[i + 1]
        elseif args[i] == "-D" then
            headers_path = args[i + 1]
        end
    end
    assert_true(type(response_path) == "string" and response_path ~= "", "missing -o response file")
    assert_true(type(headers_path) == "string" and headers_path ~= "", "missing -D headers file")

    local hh = io.open(headers_path, "wb")
    assert_true(hh ~= nil, "failed to open headers file")
    hh:write("x-ratelimit-limit-requests: 5000\n")
    hh:close()

    local fh = io.open(response_path, "wb")
    assert_true(fh ~= nil, "failed to open response file")
    fh:write(outer)
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
    max_attempts = 1,
}, function(ok, result)
    ok_result = ok
    result_or_err = result
end)

assert_true(started == true, start_err or "request should start")
assert_true(ok_result == true, "raw output_text extract should succeed")
assert_true(type(result_or_err) == "table" and result_or_err.summary == "hi", "decoded output json must be returned")
assert_true(request_count == 1, "should not require model fallback when raw extract works")

print("ai_openai_raw_output_extract_unit: ok")
astra.exit()
