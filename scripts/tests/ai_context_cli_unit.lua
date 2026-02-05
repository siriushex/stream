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

-- Stub config/runtime and dvbls
config = config or {}
config.get_setting = function(key)
    if key == "ai_cli_timeout_sec" then return 0 end
    if key == "ai_cli_max_concurrency" then return 1 end
    if key == "ai_cli_cache_sec" then return 30 end
    if key == "ai_cli_output_limit" then return 1024 end
    if key == "ai_cli_allow_no_timeout" then return true end
    if key == "ai_cli_bin_path" then return "/bin/echo" end
    if key == "ai_logs_retention_days" then return 0 end
    return nil
end

dvbls = function()
    return {
        { adapter = 0, device = 0, busy = false, type = "S2", frontend = "test", mac = "00:11" },
    }
end

local ctx = ai_context.build_context({
    include_logs = false,
    include_cli = { "dvbls", "analyze", "femon" },
    input_url = "udp://239.0.0.1:1234",
    femon_url = "dvb://#adapter=0&type=S2&tp=1234",
})

assert_true(ctx ~= nil, "context missing")
assert_true(ctx.cli and ctx.cli.dvbls and #ctx.cli.dvbls == 1, "dvbls missing")
assert_true(type(ctx.cli.analyze) == "string", "analyze output missing")
assert_true(type(ctx.cli.femon) == "string", "femon output missing")

print("ai_context_cli_unit: ok")
astra.exit()
