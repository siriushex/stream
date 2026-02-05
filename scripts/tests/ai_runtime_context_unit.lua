local function script_path(name)
    return "scripts/" .. name
end

log.set({ debug = true })

dofile(script_path("base.lua"))
dofile(script_path("ai_context.lua"))
dofile(script_path("ai_runtime.lua"))

local function assert_true(cond, msg)
    if not cond then
        error(msg or "assert failed")
    end
end

config = config or {}
config.get_setting = function(key)
    if key == "ai_enabled" then return true end
    if key == "ai_model" then return "test-model" end
    if key == "ai_max_tokens" then return 256 end
    if key == "ai_temperature" then return 0 end
    if key == "ai_store" then return false end
    if key == "ai_logs_retention_days" then return 1 end
    if key == "ai_cli_timeout_sec" then return 0 end
    if key == "ai_cli_allow_no_timeout" then return true end
    return nil
end
config.list_ai_log_events = function()
    return {
        { ts = os.time(), level = "ERROR", stream_id = "s1", message = "test error" },
    }
end

runtime = runtime or {}
runtime.list_status = function()
    return {
        s1 = { on_air = true, bitrate = 123, transcode_state = "RUNNING", active_input = 1 },
    }
end

dvbls = function()
    return { { adapter = 0, device = 0, busy = false, type = "S2" } }
end

local captured = nil
ai_openai_client = {
    has_api_key = function() return true end,
    request_json_schema = function(opts, cb)
        captured = opts.input
        cb(true, { summary = "ok", top_issues = {}, suggestions = {} }, {})
    end,
}

ai_runtime.configure()

local ok, err = ai_runtime.request_summary({
    include_logs = true,
    include_cli = { "stream", "dvbls" },
    stream_id = "s1",
    range_sec = 3600,
}, function() end)

assert_true(ok == true, err or "request_summary failed")
assert_true(type(captured) == "string" and captured:find("\"context\""), "context missing in prompt")
assert_true(captured:find("dvbls"), "dvbls missing in prompt")

print("ai_runtime_context_unit: ok")
astra.exit()
