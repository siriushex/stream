local function script_path(name)
    return "scripts/" .. name
end

log.set({ debug = true })

dofile(script_path("base.lua"))
dofile(script_path("ai_openai_client.lua"))

local function assert_true(cond, msg)
    if not cond then
        error(msg or "assert failed")
    end
end

config = config or {}
config.get_setting = function(key)
    if key == "ai_api_key" then return "test-key" end
    if key == "ai_api_base" then return "https://api.openai.com" end
    return nil
end

local calls = 0
http_request = function(req)
    calls = calls + 1
    local payload = json.decode(req.content or "{}") or {}
    local input = payload.input
    local has_image = false
    if type(input) == "table" then
        for _, msg in ipairs(input) do
            if type(msg.content) == "table" then
                for _, chunk in ipairs(msg.content) do
                    if chunk.type == "input_image" then
                        has_image = true
                    end
                end
            end
        end
    end
    if calls == 1 then
        assert_true(has_image, "first call should include image")
        local err = json.encode({ error = { message = "input_image not supported" } })
        req.callback(nil, { code = 400, content = err, headers = {} })
        return
    end
    assert_true(not has_image, "second call should strip images")
    local ok_body = json.encode({
        output = {
            {
                type = "message",
                content = {
                    { type = "output_text", text = json.encode({ ok = true }) },
                },
            },
        },
    })
    req.callback(nil, { code = 200, content = ok_body, headers = {} })
end

local schema = {
    name = "test_schema",
    strict = true,
    schema = {
        type = "object",
        additionalProperties = false,
        required = { "ok" },
        properties = {
            ok = { type = "boolean" },
        },
    },
}

local input = {
    {
        role = "user",
        content = {
            { type = "input_text", text = "test" },
            { type = "input_image", image_url = "data:image/png;base64,AAA" },
        },
    },
}

local ok, err = ai_openai_client.request_json_schema({
    input = input,
    json_schema = schema,
    model = "gpt-5.2",
}, function(success, result)
    assert_true(success, "expected success after fallback")
    assert_true(result and result.ok == true, "expected ok=true result")
end)

assert_true(ok == true, err or "request failed")
assert_true(calls == 2, "expected two attempts")

print("ai_openai_image_fallback_unit: ok")
astra.exit()
