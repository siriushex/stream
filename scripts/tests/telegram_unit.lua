-- Telegram alerts unit tests

dofile("scripts/base.lua")
dofile("scripts/telegram.lua")

local t = telegram._test

local function assert_eq(a, b, label)
    if a ~= b then
        error((label or "assert") .. ": expected " .. tostring(b) .. ", got " .. tostring(a))
    end
end

-- Level gating
assert_eq(t.level_allowed("WARNING", "ERROR"), true, "level gate warning->error")
assert_eq(t.level_allowed("WARNING", "INFO"), false, "level gate warning->info")
assert_eq(t.level_allowed("OFF", "CRITICAL"), false, "level gate off->critical")

-- Message formatting
local msg_down = t.build_message({
    code = "STREAM_DOWN",
    stream_id = "test1",
    meta = { stream_name = "Test Stream", no_data_timeout_sec = 10, active_input_url = "http://example.com/live" },
})
assert(msg_down and msg_down:find("DOWN"), "stream down message")

local msg_up = t.build_message({
    code = "STREAM_UP",
    stream_id = "test1",
    meta = { stream_name = "Test Stream", bitrate_kbps = 1200 },
})
assert(msg_up and msg_up:find("UP"), "stream up message")

local msg_no_audio = t.build_message({
    code = "NO_AUDIO_DETECTED",
    stream_id = "test1",
    meta = { stream_name = "Test Stream", input_index = 0, timeout_sec = 5, input_url = "udp://239.0.0.1:1234" },
})
assert(msg_no_audio and msg_no_audio:find("NO AUDIO"), "no audio message")

local msg_stop = t.build_message({
    code = "VIDEO_STOP_DETECTED",
    stream_id = "test1",
    meta = { stream_name = "Test Stream", input_index = 1, timeout_sec = 5, input_url = "udp://239.0.0.1:1234" },
})
assert(msg_stop and msg_stop:find("VIDEO STOP"), "video stop message")

local msg_desync = t.build_message({
    code = "AV_DESYNC_DETECTED",
    stream_id = "test1",
    meta = { stream_name = "Test Stream", current_ms = 1200, threshold_ms = 800 },
})
assert(msg_desync and msg_desync:find("AV DESYNC"), "av desync message")

local msg_silence = t.build_message({
    code = "AUDIO_SILENCE_DETECTED",
    stream_id = "test1",
    meta = { stream_name = "Test Stream", noise_db = -30 },
})
assert(msg_silence and msg_silence:find("SILENCE"), "silence message")

local msg_switch = t.build_message({
    code = "INPUT_SWITCH",
    stream_id = "test1",
    meta = { stream_name = "Test Stream", from_index = 0, to_index = 1 },
})
assert(msg_switch and msg_switch:find("SWITCH"), "input switch message")

local msg_input_down = t.build_message({
    code = "INPUT_DOWN",
    stream_id = "test1",
    meta = { stream_name = "Test Stream", input_index = 0, reason = "timeout" },
})
assert(msg_input_down and msg_input_down:find("INPUT DOWN"), "input down message")

local msg_out = t.build_message({
    code = "OUTPUT_ERROR",
    stream_id = "test1",
    message = "no progress detected",
    meta = { stream_name = "Test Stream", output_index = 0 },
})
assert(msg_out and msg_out:find("output"), "output error message")

local msg_reload = t.build_message({
    code = "CONFIG_RELOAD_FAILED",
    message = "invalid config",
})
assert(msg_reload and msg_reload:find("RELOAD FAILED"), "reload failed message")

local msg_trans = t.build_message({
    code = "TRANSCODE_STALL",
    stream_id = "test1",
    message = "stall",
    meta = { stream_name = "Test Stream" },
})
assert(msg_trans and msg_trans:find("ERROR"), "transcode stall message")

-- Dedupe & throttle
telegram.config.available = true
telegram.curl_available = true
telegram.config.dedupe_window_sec = 60
telegram.config.throttle_limit = 1
telegram.config.throttle_window_sec = 60
telegram.queue = {}
telegram.dedupe = {}
telegram.throttle = {}

local ok1 = t.enqueue_text("hello")
local ok2 = t.enqueue_text("hello")
assert_eq(ok1, true, "dedupe first ok")
assert_eq(ok2, false, "dedupe blocks second")

local ok3 = t.enqueue_text("world")
assert_eq(ok3, false, "throttle blocks second distinct message")

print("telegram_unit: ok")
astra.exit()
