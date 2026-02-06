-- AstralAI OpenAI model alias normalization unit test

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

local function run_case(input_model, expected_model)
    local models_used = {}

    http_request = function(opts)
        local payload = json.decode(opts.content or "{}") or {}
        table.insert(models_used, payload.model or "")

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

    local started, start_err = ai_openai_client.request_json_schema({
        input = "test",
        api_key = "sk-test",
        api_base = "https://api.openai.com",
        json_schema = {
            name = "unit_test",
            strict = true,
            schema = { type = "object", additionalProperties = true },
        },
        model = input_model,
        max_attempts = 1,
    }, function(ok, err)
        ok_result = ok
        err_result = ok and nil or err
    end)

    assert_true(started == true, start_err or "request should start")
    assert_true(ok_result == true, "request should succeed: " .. tostring(err_result))
    assert_true(#models_used == 1, "expected exactly one request")
    assert_true(models_used[1] == expected_model, string.format(
        "expected model %s, got %s (input %s)",
        tostring(expected_model),
        tostring(models_used[1]),
        tostring(input_model)
    ))
end

run_case("gpt-5.2-mini", "gpt-5-mini")
run_case("gpt-5.2-nano", "gpt-5-nano")
run_case(" gpt-5.1-mini ", "gpt-5-mini")
run_case(" gpt-5.1-nano ", "gpt-5-nano")

print("ai_openai_model_alias_unit: ok")
astra.exit()

