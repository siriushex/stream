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

local ok, err = ai_runtime.validate_summary_output({
    summary = "ok",
    top_issues = {},
    suggestions = {},
})
assert_true(ok == true, err or "summary validation failed")

local ok2 = ai_runtime.validate_summary_output({
    summary = 123,
    top_issues = {},
    suggestions = {},
})
assert_true(ok2 == nil, "expected invalid summary to fail")

print("ai_summary_unit: ok")
astra.exit()
