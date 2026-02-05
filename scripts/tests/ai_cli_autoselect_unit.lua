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

local job = ai_runtime.plan({ prompt = "scan dvb adapter 0 and check signal lock", stream_id = "s1" }, { user = "admin" })
assert_true(job and job.status == "done", "plan should be done")

local cli = captured.include_cli or {}
local set = {}
for _, name in ipairs(cli) do set[name] = true end
assert_true(set.stream == true, "stream cli missing")
assert_true(set.dvbls == true, "dvbls cli missing")
assert_true(set.femon == true, "femon cli missing")

job = ai_runtime.plan({ prompt = "analyze mpeg-ts pids for input", input_url = "udp://239.0.0.1:1234" }, { user = "admin" })
assert_true(job and job.status == "done", "plan should be done")
cli = captured.include_cli or {}
set = {}
for _, name in ipairs(cli) do set[name] = true end
assert_true(set.analyze == true, "analyze cli missing")

print("ai_cli_autoselect_unit: ok")
astra.exit()

