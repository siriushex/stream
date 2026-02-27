log.set({ debug = true })

dofile("scripts/base.lua")
dofile("scripts/config.lua")
dofile("scripts/dvr.lua")

local function assert_true(value, message)
    if not value then
        error(message or "assert failed")
    end
end

local tmp = "/tmp/dvr_remote_writer_internal_loopback_unit"
os.execute("rm -rf " .. tmp .. " >/dev/null 2>&1 || true")
os.execute("mkdir -p " .. tmp)

config.init({
    data_dir = tmp,
    db_path = tmp .. "/stream.db",
})

local stream_id = "loopback_internal_flag"
local upsert_ok, upsert_err = dvr.upsert_stream({
    stream_id = stream_id,
    name = "Loopback Internal Flag",
    source_url = "http://127.0.0.1:1/play/" .. stream_id,
    record_enabled = true,
    retention_days = 3,
})
assert_true(upsert_ok ~= nil, upsert_err or "upsert stream failed")

runtime = {
    streams = {},
}

dvr.local_tick()

local runtime_row = dvr.get_runtime_status(stream_id)
assert_true(type(runtime_row) == "table", "runtime status missing")
assert_true(type(runtime_row.active_input_url) == "string" and runtime_row.active_input_url ~= "",
    "active_input_url must be set")
assert_true(runtime_row.active_input_url:find("/play/" .. stream_id, 1, true) ~= nil,
    "active_input_url must contain /play/{id}")
assert_true(runtime_row.active_input_url:find("internal=1", 1, true) ~= nil,
    "loopback source_url must include internal=1")

log.info("[unit] dvr_remote_writer_internal_loopback_unit ok")
astra.exit()
