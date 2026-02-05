local function script_path(name)
    return "scripts/" .. name
end

log.set({ debug = true })

dofile(script_path("base.lua"))
dofile(script_path("config.lua"))
dofile(script_path("ai_tools.lua"))
dofile(script_path("ai_prompt.lua"))
dofile(script_path("ai_runtime.lua"))

local function assert_true(cond, msg)
    if not cond then
        error(msg or "assert failed")
    end
end

config.init({ data_dir = "/tmp/ai_chat_preview", db_path = "/tmp/ai_chat_preview/ai_chat.db" })
config.set_setting("ai_enabled", true)
config.set_setting("ai_model", "test")
ai_runtime.configure()

ai_openai_client = {
    has_api_key = function() return true end,
    request_json_schema = function(_, cb)
        cb(true, {
            summary = "ok",
            warnings = {},
            ops = {
                { op = "set_setting", target = "http_play_stream", value = true },
            },
        }, {})
    end,
}

local job = ai_runtime.plan({ prompt = "enable http play", preview_diff = true }, { user = "test" })
assert_true(job and job.status == "done", "plan job should be done")
assert_true(job.result and job.result.diff, "diff preview missing")
assert_true(job.result.diff.sections and job.result.diff.sections.settings, "settings diff missing")

print("ai_chat_preview_diff_unit: ok")
astra.exit()
