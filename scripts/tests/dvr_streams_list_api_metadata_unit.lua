log.set({ debug = true })

dofile("scripts/base.lua")
dofile("scripts/config.lua")
dofile("scripts/dvr.lua")

local function assert_true(value, message)
    if not value then
        error(message or "assert failed")
    end
end

local tmp = "/tmp/dvr_streams_list_api_metadata_unit"
os.execute("rm -rf " .. tmp .. " >/dev/null 2>&1 || true")
os.execute("mkdir -p " .. tmp)

config.init({
    data_dir = tmp,
    db_path = tmp .. "/stream.db",
})
config.set_setting("http_auth_enabled", false)

config.upsert_stream("s_local", true, {
    id = "s_local",
    name = "Local stream",
    input = { "udp://239.1.1.1:1234" },
})

local upsert_res, err = dvr.upsert_stream({
    stream_id = "s_local",
    name = "Local stream",
    source_url = "http://127.0.0.1:8000/play/s_local",
    record_enabled = true,
    retention_days = 5,
    recording_paused = false,
    last_mode = "LIVE",
    last_state_seq = 12,
})
assert_true(type(upsert_res) == "table", "failed to upsert dvr stream: " .. tostring(err))

local remote_res, remote_err = dvr.upsert_stream({
    stream_id = "s_remote_only",
    name = "Remote-only DVR stream",
    source_url = "http://127.0.0.1:8000/play/s_remote_only",
    record_enabled = true,
    retention_days = 3,
    recording_paused = false,
    last_mode = "LIVE",
    last_state_seq = 3,
})
assert_true(type(remote_res) == "table", "failed to upsert remote-only dvr stream: " .. tostring(remote_err))

local state_ok, state_err = dvr.apply_ingest_state({
    stream_id = "s_local",
    mode = "DVR_ACTIVE",
    reason = "no_data",
    state_seq = 13,
    ts = os.time(),
})
assert_true(type(state_ok) == "table", "failed to apply ingest state: " .. tostring(state_err))

_G.__stream_dvr = dvr

dofile("scripts/api.lua")

local sent = nil
local server = {
    send = function(_, _, payload)
        sent = payload
    end,
}
local client = {}

local function make_get(path, query)
    return {
        method = "GET",
        path = path,
        addr = "127.0.0.1",
        headers = {},
        query = query or {},
        content = "",
    }
end

local function decode_sent()
    local ok_decode, payload = pcall(json.decode, sent and sent.content or "")
    assert_true(ok_decode and type(payload) == "table", "expected JSON response")
    return payload
end

sent = nil
api.handle_request(server, client, make_get("/api/v1/streams"))
assert_true(sent and tonumber(sent.code) == 200, "expected 200 for streams list")
local list_payload = decode_sent()
assert_true(type(list_payload) == "table", "streams list payload must be table")
local local_row = nil
for _, row in ipairs(list_payload) do
    if tostring(row and row.id or "") == "s_local" then
        local_row = row
        break
    end
end
assert_true(type(local_row) == "table", "missing s_local in list payload")
assert_true(type(local_row.dvr) == "table", "expected dvr metadata in list payload")
assert_true(local_row.dvr.record_enabled == true, "record_enabled mismatch")
assert_true(local_row.dvr.recording_paused == true, "recording_paused mismatch")
assert_true(tonumber(local_row.dvr.retention_days) == 5, "retention_days mismatch")
assert_true(tostring(local_row.dvr.last_mode or "") == "DVR_ACTIVE", "last_mode mismatch")

sent = nil
api.handle_request(server, client, make_get("/api/v1/streams/s_local"))
assert_true(sent and tonumber(sent.code) == 200, "expected 200 for stream get")
local get_payload = decode_sent()
assert_true(type(get_payload.dvr) == "table", "expected dvr metadata in stream get")
assert_true(get_payload.dvr.recording_paused == true, "stream get recording_paused mismatch")
assert_true(tostring(get_payload.dvr.last_mode or "") == "DVR_ACTIVE", "stream get last_mode mismatch")

sent = nil
api.handle_request(server, client, make_get("/api/v1/streams/s_remote_only"))
assert_true(sent and tonumber(sent.code) == 200, "expected 200 for remote-only stream get")
local remote_get_payload = decode_sent()
assert_true(remote_get_payload.dvr_only == true, "expected dvr_only=true for remote-only stream")
assert_true(type(remote_get_payload.config) == "table", "expected config for remote-only stream")
assert_true(type(remote_get_payload.config.input) == "table", "expected input list for remote-only stream")
assert_true(remote_get_payload.config.input[1] == "http://127.0.0.1:8000/play/s_remote_only",
    "unexpected source input for remote-only stream")
assert_true(type(remote_get_payload.dvr) == "table", "expected dvr metadata for remote-only stream")
assert_true(remote_get_payload.dvr.record_enabled == true, "expected remote-only record_enabled=true")

local remote_list_row = nil
for _, row in ipairs(list_payload) do
    if tostring(row and row.id or "") == "s_remote_only" then
        remote_list_row = row
        break
    end
end
assert_true(type(remote_list_row) == "table", "missing s_remote_only in list payload")
assert_true(remote_list_row.dvr_only == true, "expected dvr_only=true in list payload")
assert_true(type(remote_list_row.dvr) == "table", "expected dvr metadata in list for remote-only stream")
assert_true(remote_list_row.dvr.record_enabled == true, "expected list record_enabled=true for remote-only stream")

_G.__stream_dvr = nil

log.info("[unit] dvr_streams_list_api_metadata_unit ok")
astra.exit()
