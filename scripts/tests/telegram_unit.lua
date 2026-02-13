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
