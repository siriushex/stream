local function script_path(name)
    return "scripts/" .. name
end

log.set({ debug = true })

dofile(script_path("base.lua"))
dofile(script_path("config.lua"))
dofile(script_path("ai_tools.lua"))
dofile(script_path("ai_prompt.lua"))
dofile(script_path("ai_runtime.lua"))

config.init({ data_dir = "/tmp/ai_smoke_data", db_path = "/tmp/ai_smoke_data/ai_smoke.db" })

local function read_file(path)
    local file = io.open(path, "rb")
    if not file then
        return nil
    end
    local content = file:read("*a")
    file:close()
    return content
end

local function load_json(path)
    local content = read_file(path)
    if not content then
        return nil, "missing file"
    end
    local ok, value = pcall(json.decode, content)
    if not ok then
        return nil, "invalid json"
    end
    return value
end

local function assert_true(cond, msg)
    if not cond then
        error(msg or "assert failed")
    end
end

local base = "fixtures/ai_plan_min.json"
local payload = load_json(base)
assert_true(type(payload) == "table", "payload missing")
local diff, err = ai_tools.config_diff(payload, payload)
assert_true(diff ~= nil, err or "diff failed")
assert_true(diff.summary.added == 0, "expected no added")
assert_true(diff.summary.removed == 0, "expected no removed")
assert_true(diff.summary.updated == 0, "expected no updated")

config.set_setting("ai_enabled", true)
ai_runtime.configure()

local job = ai_runtime.plan({ proposed_config = payload }, { user = "test" })
assert_true(job and job.status == "done", "plan job should be done")
assert_true(job.result and job.result.summary, "plan summary missing")

local ok, err = ai_runtime.validate_plan_output({
    summary = "ok",
    warnings = {},
    ops = {
        { op = "noop", target = "config" },
    },
})
assert_true(ok, err or "plan validation failed")
local ok2 = ai_runtime.validate_plan_output({ summary = true, warnings = {}, ops = {} })
assert_true(ok2 == nil, "expected invalid plan to fail")

print("ai plan smoke ok")
astra.exit()
