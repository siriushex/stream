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

local detect = ai_openai_client._test and ai_openai_client._test.detect_model_not_found
assert_true(type(detect) == "function", "detect_model_not_found missing")

local body_ok = json.encode({ error = { code = "model_not_found", message = "The model `nope` does not exist" } })
assert_true(detect(404, body_ok) == true, "expected model_not_found for 404")
assert_true(detect(400, body_ok) == true, "expected model_not_found for 400")

local body_other = json.encode({ error = { code = "rate_limit_exceeded", message = "Too many requests" } })
assert_true(detect(429, body_other) == false, "should not match on 429")
assert_true(detect(400, body_other) == false, "should not match non-model error")

print("ai_openai_model_fallback_unit: ok")
astra.exit()

