local function script_path(name)
    return "scripts/" .. name
end

log.set({ debug = true })

dofile(script_path("base.lua"))
dofile(script_path("ai_runtime.lua"))

local function assert_true(cond, msg)
    if not cond then
        error(msg or "assert failed")
    end
end

assert_true(ai_runtime and ai_runtime._test and type(ai_runtime._test.sanitize_value) == "function", "sanitize helper missing")

local nan = 0 / 0
local inf = 1 / 0

local sanitized = ai_runtime._test.sanitize_value({
    metric_nan = nan,
    metric_inf = inf,
})

assert_true(sanitized.metric_nan == sanitized.metric_nan, "metric_nan still NaN after sanitize")
assert_true(sanitized.metric_inf ~= math.huge and sanitized.metric_inf ~= -math.huge, "metric_inf still inf after sanitize")

local encoded = json.encode(sanitized)
local lower = tostring(encoded):lower()
assert_true(not lower:find(":nan", 1, true) and not lower:find(",nan", 1, true), "json contains nan value")
assert_true(not lower:find(":inf", 1, true) and not lower:find(",inf", 1, true), "json contains inf value")

print("ai_prompt_sanitize_nan_unit: ok")
astra.exit()
