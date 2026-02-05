local function script_path(name)
    return "scripts/" .. name
end

log.set({ debug = true })

dofile(script_path("base.lua"))
dofile(script_path("config.lua"))
dofile(script_path("ai_tools.lua"))
dofile(script_path("ai_runtime.lua"))

local function assert_true(cond, msg)
    if not cond then
        error(msg or "assert failed")
    end
end

config.init({ data_dir = "/tmp/ai_guardrail_data", db_path = "/tmp/ai_guardrail_data/ai_guardrail.db" })
config.set_setting("ai_enabled", true)
config.set_setting("ai_allow_apply", true)
config.set_setting("ai_max_ops", 2)
ai_runtime.configure()

local plan = {
    summary = "bulk changes",
    warnings = {},
    ops = {
        { op = "set_setting", target = "http_play_stream", value = true },
        { op = "set_setting", target = "http_play_hls", value = true },
        { op = "enable_stream", target = "s1" },
    },
}

local ok, err = ai_runtime.apply({ plan = plan }, { user = "test" })
assert_true(ok == nil, "expected guardrail to block apply")
assert_true(err and err:find("too many ops"), "expected guardrail error")

local ok2, err2 = ai_runtime.apply({ plan = plan, allow_destructive = true }, { user = "test" })
assert_true(ok2 ~= nil, err2 or "expected apply to pass with allow_destructive")

local disable_plan = {
    summary = "disable stream",
    warnings = {},
    ops = {
        { op = "disable_stream", target = "s1" },
    },
}

local ok3, err3 = ai_runtime.apply({ plan = disable_plan }, { user = "test" })
assert_true(ok3 == nil, "expected disable guardrail to block apply")
assert_true(err3 and err3:find("disable ops require"), "expected disable guardrail error")

local ok4, err4 = ai_runtime.apply({ plan = disable_plan, allow_destructive = true }, { user = "test" })
assert_true(ok4 ~= nil, err4 or "expected disable apply to pass with allow_destructive")

print("ai_apply_guardrail_unit: ok")
astra.exit()
