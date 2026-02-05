local function script_path(name)
    return "scripts/" .. name
end

log.set({ debug = true })

dofile(script_path("base.lua"))
dofile(script_path("ai_context.lua"))
dofile(script_path("ai_runtime.lua"))
dofile(script_path("api.lua"))

local function assert_true(cond, msg)
    if not cond then
        error(msg or "assert failed")
    end
end

-- Stub config/runtime and auth
config = config or {}
config.get_setting = function(key)
    if key == "ai_enabled" then return true end
    if key == "ai_model" then return "test-model" end
    if key == "ai_max_tokens" then return 128 end
    if key == "ai_temperature" then return 0 end
    if key == "ai_store" then return false end
    if key == "ai_logs_retention_days" then return 1 end
    if key == "ai_cli_timeout_sec" then return 0 end
    if key == "ai_cli_allow_no_timeout" then return true end
    if key == "ai_cli_bin_path" then return "/bin/echo" end
    return nil
end
config.list_ai_log_events = function()
    return {
        { ts = os.time(), level = "ERROR", stream_id = "s1", message = "test error" },
    }
end
config.list_ai_metrics = function()
    return {}
end
config.get_session = function()
    return { token = "t", user_id = 1 }
end
config.get_user = function()
    return { id = 1, username = "admin", type = 1 }
end

runtime = runtime or {}
runtime.list_status = function()
    return {
        s1 = { on_air = true, bitrate = 123, transcode_state = "RUNNING" },
    }
end

ai_openai_client = {
    has_api_key = function() return true end,
    request_json_schema = function(opts, cb)
        cb(true, { summary = "ok", top_issues = {}, suggestions = {} }, {})
    end,
}

ai_runtime.configure()

local function make_request(path, query)
    return {
        method = "GET",
        path = path,
        addr = "127.0.0.1",
        headers = { authorization = "Bearer token" },
        query = query or {},
    }
end

local function decode_json(payload)
    if not payload or not payload.content then
        return nil
    end
    local ok, data = pcall(json.decode, payload.content)
    if not ok then
        return nil
    end
    return data
end

local sent = nil
local server = {
    send = function(_, _, payload)
        sent = payload
    end
}
local client = {}

api.handle_request(server, client, make_request("/api/v1/ai/summary", {
    range = "24h",
    ai = "1",
    include_logs = "1",
    include_cli = "stream,analyze,femon",
    stream_id = "s1",
    input_url = "udp://239.0.0.1:1234",
    femon_url = "dvb://#adapter=0&type=S2&tp=1234",
}))

assert_true(sent ~= nil, "ai summary response missing")
assert_true(type(sent.content) == "string", "expected JSON content")
local decoded = decode_json(sent)
assert_true(decoded ~= nil, "failed to decode JSON")

print("ai_context_api_unit: ok")
astra.exit()
