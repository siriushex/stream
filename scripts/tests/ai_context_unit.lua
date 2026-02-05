local function script_path(name)
    return "scripts/" .. name
end

log.set({ debug = true })

dofile(script_path("base.lua"))
dofile(script_path("ai_context.lua"))

local function assert_true(cond, msg)
    if not cond then
        error(msg or "assert failed")
    end
end

-- Stub config and runtime
config = config or {}
config.get_setting = function(key)
    if key == "ai_cli_timeout_sec" then return 1 end
    if key == "ai_cli_max_concurrency" then return 1 end
    if key == "ai_cli_cache_sec" then return 30 end
    if key == "ai_cli_output_limit" then return 1024 end
    if key == "ai_cli_allow_no_timeout" then return false end
    if key == "ai_logs_retention_days" then return 1 end
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
        s1 = { on_air = true, bitrate = 1234, transcode_state = "RUNNING", active_input = 1 },
    }
end

local ctx = ai_context.build_context({
    include_logs = true,
    include_cli = { "stream" },
    stream_id = "s1",
})

assert_true(ctx ~= nil, "context missing")
assert_true(ctx.logs and #ctx.logs == 1, "logs missing")
assert_true(ctx.cli and ctx.cli.stream and ctx.cli.stream.stream_id == "s1", "stream snapshot missing")

print("ai_context_unit: ok")
astra.exit()
