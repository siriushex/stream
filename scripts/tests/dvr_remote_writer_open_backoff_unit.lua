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

local tmp = "/tmp/dvr_remote_writer_open_backoff_unit"
os.execute("rm -rf " .. tmp .. " >/dev/null 2>&1 || true")
os.execute("mkdir -p " .. tmp)

config.init({
    data_dir = tmp,
    db_path = tmp .. "/stream.db",
})
config.set_setting("http_auth_enabled", false)

local init_calls = 0
_G.init_input = function(_cfg)
    init_calls = init_calls + 1
    return nil
end

dofile("scripts/dvr.lua")

local stream_id = "remote_backoff_smoke"
local ok, err = dvr.upsert_stream({
    stream_id = stream_id,
    name = "Remote Backoff Smoke",
    source_url = "http://127.0.0.1:12345/play/" .. stream_id,
    record_enabled = true,
    retention_days = 3,
    recording_paused = false,
})
assert_true(ok ~= nil, err or "upsert failed")

dvr.local_tick()
assert_eq(init_calls, 1, "expected first open attempt")

os.execute("sleep 1")
dvr.local_tick()
os.execute("sleep 1")
dvr.local_tick()
assert_eq(init_calls, 1, "open attempts must be throttled during backoff window")

os.execute("sleep 5")
dvr.local_tick()
assert_true(init_calls >= 2, "expected retry after backoff interval")

log.info("[unit] dvr_remote_writer_open_backoff_unit ok")
astra.exit()
