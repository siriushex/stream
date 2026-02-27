log.set({ debug = true })

dofile("scripts/base.lua")
dofile("scripts/config.lua")
dofile("scripts/dvr.lua")

local function assert_true(value, message)
    if not value then
        error(message or "assert failed")
    end
end

local tmp = "/tmp/servers_status_dvr_health_unit"
os.execute("rm -rf " .. tmp .. " >/dev/null 2>&1 || true")
os.execute("mkdir -p " .. tmp)

config.init({
    data_dir = tmp,
    db_path = tmp .. "/stream.db",
})
config.set_setting("http_auth_enabled", false)
config.set_setting("servers", {
    {
        id = "dvr1",
        name = "DVR #1",
        host = "127.0.0.1",
        port = 17000,
        api_type = "dvr_v1",
        enabled = true,
        login = "admin",
        password = "admin",
    },
})

_G.__stream_remote_servers = {
    probe = function(_entry, callback)
        callback(true, {
            status = "ok",
            api_type_effective = "dvr_v1",
            capabilities = {},
        })
    end,
    classify_error_status = function(_message, code)
        return tonumber(code) or 400
    end,
}
_G.__stream_dvr = dvr

dofile("scripts/api.lua")

local ok, err = dvr.upsert_remote_link({
    stream_id = "s1",
    dvr_server_id = "dvr1",
    dvr_stream_id = "s1",
    source_play_url = "http://127.0.0.1:9000/play/s1",
})
assert_true(ok == true, "upsert_remote_link failed: " .. tostring(err))

ok, err = dvr.upsert_remote_sync_state({
    stream_id = "s1",
    dvr_server_id = "dvr1",
    last_state_seq = 9,
    last_mode = "LIVE",
})
assert_true(ok == true, "upsert_remote_sync_state failed: " .. tostring(err))

local row_ready, row_retry = nil, nil
row_ready, err = dvr.enqueue_remote_outbox({
    stream_id = "s1",
    dvr_server_id = "dvr1",
    event_type = "ingest_state",
    payload = {
        stream_id = "s1",
        mode = "DVR_ACTIVE",
        reason = "no_data",
        ts = os.time(),
        state_seq = 10,
    },
})
assert_true(type(row_ready) == "table", "enqueue ready row failed: " .. tostring(err))

row_retry, err = dvr.enqueue_remote_outbox({
    stream_id = "s2",
    dvr_server_id = "dvr1",
    event_type = "ingest_state",
    payload = {
        stream_id = "s2",
        mode = "LIVE",
        reason = "recover",
        ts = os.time(),
        state_seq = 3,
    },
})
assert_true(type(row_retry) == "table", "enqueue retry row failed: " .. tostring(err))

ok, err = dvr.outbox_mark_retry(row_retry.id, "dvr offline", 60)
assert_true(ok == true, "outbox_mark_retry failed: " .. tostring(err))

local sent = nil
local server = {
    send = function(_, _, payload)
        sent = payload
    end,
}
local client = {}

api.handle_request(server, client, {
    method = "GET",
    path = "/api/v1/servers/status",
    addr = "127.0.0.1",
    headers = {},
    query = {},
    content = "",
})

assert_true(sent and tonumber(sent.code) == 200, "expected 200 for /api/v1/servers/status")
local ok_json, payload = pcall(json.decode, sent and sent.content or "")
assert_true(ok_json and type(payload) == "table", "expected JSON payload")
local items = payload.items or {}
assert_true(type(items) == "table" and #items == 1, "expected exactly one server status row")

local row = items[1]
assert_true(row.id == "dvr1", "unexpected server id")
assert_true(row.ok == true, "probe should be ok")
assert_true(type(row.dvr_sync) == "table", "expected dvr_sync metadata")
assert_true(tonumber(row.dvr_sync.links_count) == 1, "links_count mismatch")
assert_true(tonumber(row.dvr_sync.sync_rows) == 1, "sync_rows mismatch")
assert_true(tonumber(row.dvr_sync.outbox_total) == 2, "outbox_total mismatch")
assert_true(tonumber(row.dvr_sync.ready_count) == 1, "ready_count mismatch")
assert_true(tonumber(row.dvr_sync.retrying_count) == 1, "retrying_count mismatch")
assert_true(type(row.dvr_sync.last_error) == "string" and row.dvr_sync.last_error ~= "", "last_error missing")

_G.__stream_remote_servers = nil
_G.__stream_dvr = nil

log.info("[unit] servers_status_dvr_health_unit ok")
astra.exit()
