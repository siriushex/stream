local function script_path(name)
    return "scripts/" .. name
end

log.set({ debug = true })

dofile(script_path("base.lua"))
dofile(script_path("config.lua"))
dofile(script_path("ai_tools.lua"))
dofile(script_path("ai_runtime.lua"))

config.init({ data_dir = "/tmp/ai_apply_data", db_path = "/tmp/ai_apply_data/ai_apply.db" })

local function assert_true(cond, msg)
    if not cond then
        error(msg or "assert failed")
    end
end

config.set_setting("ai_enabled", true)
config.set_setting("ai_allow_apply", true)
ai_runtime.configure()

local payload = {
    settings = {
        http_play_stream = true,
    },
}

local job, err = ai_runtime.apply({ proposed_config = payload }, { user = "test" })
assert_true(job and job.status == "done", err or "apply failed")
assert_true(job.result and job.result.summary, "apply summary missing")

local value = config.get_setting("http_play_stream")
assert_true(value ~= nil, "setting not applied")

print("ai apply smoke ok")
astra.exit()
