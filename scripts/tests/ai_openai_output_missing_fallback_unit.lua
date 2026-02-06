-- AstralAI OpenAI client: fallback when response has no output_text (200 OK but empty output)

dofile("scripts/base.lua")
dofile("scripts/ai_openai_client.lua")

local function assert_true(cond, msg)
    if not cond then
        error(msg or "assert failed")
    end
end

-- Force no-proxy path in the client to keep the test deterministic.
local orig_getenv = os.getenv
os.getenv = function(key)
    if key == "LLM_PROXY_PRIMARY"
        or key == "LLM_PROXY_SECONDARY"
        or key == "ASTRAL_LLM_PROXY_PRIMARY"
        or key == "ASTRAL_LLM_PROXY_SECONDARY"
    then
        return ""
    end
    return orig_getenv(key)
end

local models_used = {}
local calls = 0

http_request = function(opts)
    calls = calls + 1
    local payload = json.decode(opts.content or "{}") or {}
    table.insert(models_used, payload.model or "")

    if calls == 1 then
        -- Simulate a 200 OK Responses object with no output. Some models/proxies do this.
        opts.callback(nil, {
            code = 200,
            headers = {},
            content = json.encode({
                id = "resp_test",
                object = "response",
                status = "incomplete",
                output = {},
            }),
        })
        return
    end

    local ok_body = json.encode({
        output = {
            {
                type = "message",
                content = {
                    { type = "output_text", text = "{}" },
                },
            },
        },
    })

    opts.callback(nil, { code = 200, headers = {}, content = ok_body })
end

local ok_result = nil
local err_result = nil
local meta_result = nil

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
    model_fallbacks = { "gpt-5-mini" },
    max_attempts = 2,
}, function(ok, result, meta)
    ok_result = ok
    err_result = ok and nil or result
    meta_result = meta
end)

assert_true(started == true, start_err or "request should start")
assert_true(ok_result == true, "request should succeed: " .. tostring(err_result))
assert_true(#models_used == 2, "expected two requests (primary + fallback)")
assert_true(models_used[1] == "gpt-5-nano", "first request should use primary model")
assert_true(models_used[2] == "gpt-5-mini", "second request should use fallback model")
assert_true(meta_result and meta_result.model == "gpt-5-mini", "meta.model should match fallback model")

print("ai_openai_output_missing_fallback_unit: ok")
astra.exit()

