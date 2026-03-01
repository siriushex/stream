log.set({ debug = true })

dofile("scripts/base.lua")
dofile("scripts/config.lua")

local function assert_true(value, message)
    if not value then
        error(message or "assert failed")
    end
end

local function assert_eq(actual, expected, message)
    if actual ~= expected then
        error((message or "assert eq failed") .. ": actual=" .. tostring(actual) .. " expected=" .. tostring(expected))
    end
end

local tmp = "/tmp/radio_api_config_fallback_unit"
os.execute("rm -rf " .. tmp .. " >/dev/null 2>&1 || true")
os.execute("mkdir -p " .. tmp)

local png_path = tmp .. "/cover.png"
do
    local fh = io.open(png_path, "wb")
    assert_true(fh ~= nil, "png create failed")
    fh:write("png")
    fh:close()
end

config.init({
    data_dir = tmp,
    db_path = tmp .. "/stream.db",
})
config.set_setting("http_auth_enabled", false)
config.set_setting("http_allow_public_noauth", true)

local stream_id = "radio"
config.upsert_stream(stream_id, true, {
    id = stream_id,
    name = "Radio Unit",
    input = { "udp://127.0.0.1:22003" },
    radio = {
        audio_url = "http://127.0.0.1:9060/play/reka?internal=1",
        png_path = png_path,
        output_url = "udp://127.0.0.1:22003#pkt_size=1316",
        autostart = false,
        use_curl = false,
    },
})

local calls = {
    start = nil,
    restart = nil,
}

radio = {
    jobs = {},
    start = function(id, settings)
        calls.start = {
            id = id,
            settings = settings,
        }
        return true
    end,
    restart = function(id, settings)
        calls.restart = {
            id = id,
            settings = settings,
        }
        return true
    end,
    stop = function()
        return true
    end,
    get_status = function(id)
        return {
            status = "running",
            stream_id = id,
            settings = (calls.restart and calls.restart.settings) or (calls.start and calls.start.settings) or {},
            logs = "",
        }
    end,
}

dofile("scripts/api.lua")
dofile("scripts/api_media.lua")

local sent = nil
local server = {
    send = function(_, _, payload)
        sent = payload
    end,
}
local client = {}

local function request_json(path, body)
    sent = nil
    api.handle_request(server, client, {
        method = "POST",
        path = path,
        addr = "127.0.0.1",
        headers = {
            ["content-type"] = "application/json",
        },
        query = {},
        content = body and json.encode(body) or "{}",
    })
    assert_true(sent ~= nil, "no response")
    local ok, payload = pcall(json.decode, sent.content or "")
    assert_true(ok and type(payload) == "table", "json response expected")
    return sent, payload
end

do
    local response, payload = request_json("/api/v1/streams/" .. stream_id .. "/radio/start", {})
    assert_eq(tonumber(response.code), 200, "radio start")
    assert_true(type(payload.status) == "table", "status payload required")
    assert_true(calls.start ~= nil, "radio.start was not called")
    assert_eq(calls.start.id, stream_id, "start stream id")
    assert_eq(calls.start.settings.audio_url, "http://127.0.0.1:9060/play/reka?internal=1", "audio_url fallback")
    assert_eq(calls.start.settings.output_url, "udp://127.0.0.1:22003#pkt_size=1316", "output_url fallback")
end

do
    local response, _ = request_json("/api/v1/streams/" .. stream_id .. "/radio/restart", {
        user_agent = "UnitTest/1.0",
    })
    assert_eq(tonumber(response.code), 200, "radio restart")
    assert_true(calls.restart ~= nil, "radio.restart was not called")
    assert_eq(calls.restart.id, stream_id, "restart stream id")
    assert_eq(calls.restart.settings.audio_url, "http://127.0.0.1:9060/play/reka?internal=1",
        "restart audio_url fallback")
    assert_eq(calls.restart.settings.user_agent, "UnitTest/1.0", "restart body override")
end

log.info("[unit] radio_api_config_fallback_unit ok")
astra.exit()
