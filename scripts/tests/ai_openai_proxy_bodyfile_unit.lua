-- AstralAI OpenAI client proxy path bodyfile unit test
--
-- When proxies are enabled, we call out to curl. The response body must be read
-- from a temp file (curl -o) to avoid stdout pipe truncation causing "invalid json".

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
local spawned = {}
process = process or {}
process.spawn = function(args, _opts)
    table.insert(spawned, args)

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

    -- Real request: require -o <response_path> and -D <headers_path>.
    local response_path = nil
    local headers_path = nil
    for i = 1, #args do
        if args[i] == "-o" then
            response_path = args[i + 1]
        elseif args[i] == "-D" then
            headers_path = args[i + 1]
        end
    end
    assert_true(type(response_path) == "string" and response_path ~= "", "curl must use -o <file> for response body")
    assert_true(type(headers_path) == "string" and headers_path ~= "", "curl must use -D <file> for headers")

    -- Write response body to file (what the client should read).
    local body = json.encode({
        output = {
            {
                type = "message",
                content = {
                    { type = "output_text", text = "{}" },
                },
            },
        },
    })
    local fh = io.open(response_path, "wb")
    assert_true(fh ~= nil, "failed to open response temp file")
    fh:write(body)
    fh:close()

    -- Write minimal headers (rate-limits) to ensure header parsing doesn't crash.
    local hh = io.open(headers_path, "wb")
    assert_true(hh ~= nil, "failed to open headers temp file")
    hh:write("x-ratelimit-limit-requests: 5000\n")
    hh:write("x-ratelimit-remaining-requests: 4999\n")
    hh:close()

    -- Stdout only contains the status marker (curl -w).
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

local ok_result, err_result = nil, nil

local started, start_err = ai_openai_client.request_json_schema({
    input = "test",
    api_key = "sk-test",
    api_base = "https://api.openai.com",
    json_schema = {
        name = "unit_test",
        strict = true,
        schema = { type = "object", additionalProperties = true },
    },
    model = "gpt-5.2",
    max_attempts = 1,
}, function(ok, result)
    ok_result = ok
    if ok then
        err_result = nil
    else
        err_result = result
    end
end)

assert_true(started == true, start_err or "request should start")
assert_true(ok_result == true, "proxy request should succeed (response read from file)")
assert_true(err_result == nil, "no error expected")

print("ai_openai_proxy_bodyfile_unit: ok")
astra.exit()
