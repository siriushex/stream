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

config = config or {}
config.get_setting = function(key)
    if key == "ai_enabled" then return true end
    if key == "ai_model" then return "gpt-5.2" end
    if key == "ai_max_tokens" then return 64 end
    if key == "ai_temperature" then return 0 end
    if key == "ai_store" then return false end
    return nil
end

local captured = {}
ai_context = {
    build_context = function(opts)
        captured = opts or {}
        return {}
    end
}

ai_openai_client = {
    has_api_key = function() return true end,
    request_json_schema = function(_, cb)
        cb(true, { summary = "ok", warnings = {}, ops = {} }, {})
    end,
}

ai_runtime.configure()

local job = ai_runtime.plan({ prompt = "rename stream test to prod" }, { user = "admin" })
assert_true(job and job.status == "done", "plan should be done")
assert_true(captured.include_metrics == false, "include_metrics should be false for non-metrics prompt")

job = ai_runtime.plan({ prompt = "show chart of bitrate for stream s1" }, { user = "admin" })
assert_true(job and job.status == "done", "plan should be done")
assert_true(captured.include_metrics == true, "include_metrics should be true for chart prompt")

print("ai_metrics_autoselect_unit: ok")
astra.exit()
