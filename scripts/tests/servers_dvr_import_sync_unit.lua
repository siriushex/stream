log.set({ debug = true })

dofile("scripts/base.lua")
dofile("scripts/config.lua")
dofile("scripts/dvr.lua")

local function assert_true(value, message)
    if not value then
        error(message or "assert failed")
    end
end

local tmp = "/tmp/servers_dvr_import_sync_unit"
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

config.list_streams = function()
    return {
        { id = "s1", config = { id = "s1", name = "Stream One", dvr = { path = "/var/dvr/s1" } } },
        { id = "s2", config = { id = "s2", name = "Stream Two" } },
        { id = "legacy_row_id", config = { id = "cfg_stream_id", name = "Config-ID Stream" } },
    }
end

local captured = {
    upsert_items = nil,
    ingest_payload = nil,
    ingest_payloads = {},
    cursor_reset_payload = nil,
    cycle_rebuild_payload = nil,
    storage_candidates_calls = 0,
    storage_fail_next = false,
}

_G.__stream_remote_servers = {
    probe = function(_entry, callback)
        callback(true, {
            status = "ok",
            api_type_effective = "dvr_v1",
            capabilities = {},
        })
    end,
    dvr_upsert_streams = function(_entry, items, callback)
        captured.upsert_items = items
        callback(true, {
            status = "ok",
            total = #items,
            imported = #items,
            failed = {},
        })
    end,
    dvr_bulk_record = function(_entry, payload, callback)
        callback(true, {
            ok = true,
            affected = #(payload and payload.stream_ids or {}),
            errors = {},
        })
    end,
    dvr_ingest_state = function(_entry, payload, callback)
        captured.ingest_payload = payload
        captured.ingest_payloads[#captured.ingest_payloads + 1] = payload
        callback(true, {
            ok = true,
            current_mode = payload and payload.mode,
        })
    end,
    dvr_backup_cursor_reset = function(_entry, payload, callback)
        captured.cursor_reset_payload = payload
        callback(true, {
            ok = true,
            total = #(payload and payload.stream_ids or {}),
            affected = #(payload and payload.stream_ids or {}),
            failed = {},
        })
    end,
    dvr_backup_cycle_rebuild = function(_entry, payload, callback)
        captured.cycle_rebuild_payload = payload
        callback(true, {
            ok = true,
            total = #(payload and payload.stream_ids or {}),
            affected = #(payload and payload.stream_ids or {}),
            failed = {},
        })
    end,
    dvr_storage_candidates = function(_entry, _payload, callback)
        captured.storage_candidates_calls = captured.storage_candidates_calls + 1
        if captured.storage_fail_next then
            captured.storage_fail_next = false
            return callback(false, nil, "remote storage detection failed", 500)
        end
        callback(true, {
            ok = true,
            recommended_path = "/media/dvr-auto",
            candidates = {
                { path = "/media/dvr-auto", mount_point = "/media/disk1", avail_bytes = 10737418240, fs_type = "xfs" },
                { path = "/var/lib/stream/dvr", mount_point = "/", avail_bytes = 5368709120, fs_type = "ext4", is_system = true },
            },
        })
    end,
    classify_error_status = function(_message, code)
        return tonumber(code) or 400
    end,
}
_G.__stream_dvr = dvr

dofile("scripts/api.lua")

local sent = nil
local server = {
    send = function(_, _, payload)
        sent = payload
    end,
}
local client = {}

local function make_post(path, body, extra_headers)
    local headers = { ["content-type"] = "application/json" }
    if type(extra_headers) == "table" then
        for key, value in pairs(extra_headers) do
            headers[key] = value
        end
    end
    return {
        method = "POST",
        path = path,
        addr = "127.0.0.1",
        headers = headers,
        query = {},
        content = json.encode(body or {}),
    }
end

local function decode_sent()
    local ok, payload = pcall(json.decode, sent and sent.content or "")
    assert_true(ok and type(payload) == "table", "expected JSON response")
    return payload
end

sent = nil
api.handle_request(server, client, make_post("/api/v1/servers/dvr/import-streams", {
    id = "dvr1",
    origin_url = "http://127.0.0.1:9000",
    import_all = true,
}))
assert_true(sent and tonumber(sent.code) == 200, "expected 200 for dvr import-streams")
local import_payload = decode_sent()
assert_true(import_payload.ok == true, "expected ok=true on import")
assert_true(tonumber(import_payload.total) == 3, "expected total=3")
assert_true(tonumber(import_payload.imported) == 3, "expected imported=3")
assert_true(import_payload.archive_default_path == "/media/dvr-auto", "expected auto archive path")
assert_true(import_payload.archive_path_source == "remote_auto", "expected remote_auto archive source")
assert_true(import_payload.origin_auth_source == "server", "expected server auth source on default import")
assert_true(type(captured.upsert_items) == "table" and #captured.upsert_items == 3, "expected 3 upsert items")
assert_true(captured.upsert_items[1].source_url == "http://admin:admin@127.0.0.1:9000/play/s1", "unexpected source_url for s1")
assert_true(captured.upsert_items[2].source_url == "http://admin:admin@127.0.0.1:9000/play/s2", "unexpected source_url for s2")
assert_true(captured.upsert_items[3].source_url == "http://admin:admin@127.0.0.1:9000/play/legacy_row_id",
    "unexpected source_url for legacy_row_id")
assert_true(captured.upsert_items[1].archive_path == "/var/dvr/s1", "expected local stream archive path to be preserved")
assert_true(captured.upsert_items[2].archive_path == "/media/dvr-auto", "expected remote default archive path for stream without local path")
assert_true(type(captured.upsert_items[1].config) == "table", "expected full config payload for s1")
assert_true(captured.upsert_items[1].config.id == "s1", "expected config.id=s1")
assert_true(type(captured.upsert_items[1].config.input) == "table", "expected config.input array")
assert_true(#captured.upsert_items[1].config.input == 1, "expected single source input in remote config")
assert_true(captured.upsert_items[1].config.input[1] == "http://admin:admin@127.0.0.1:9000/play/s1",
    "expected source_url in config.input[1] for s1")
assert_true(captured.upsert_items[1].config.backup_type == "disabled", "expected backup_type=disabled for remote config")
assert_true(type(captured.upsert_items[1].config.dvr) == "table", "expected config.dvr table for s1")
assert_true(captured.upsert_items[1].config.dvr.mode == "local", "expected local dvr mode on remote config")
assert_true(captured.upsert_items[1].config.dvr.backup_enabled == false,
    "expected backup disabled on remote config")
assert_true(captured.upsert_items[1].config.dvr.source_url == "http://admin:admin@127.0.0.1:9000/play/s1",
    "expected config.dvr.source_url for s1")
assert_true(type(captured.upsert_items[3].config) == "table", "expected full config payload for cfg id stream")
assert_true(captured.upsert_items[3].config.id == "legacy_row_id", "expected config.id rewritten to effective stream_id")

local link_s1 = dvr.get_remote_link("s1", "dvr1")
local link_s2 = dvr.get_remote_link("s2", "dvr1")
assert_true(type(link_s1) == "table", "missing remote link for s1")
assert_true(type(link_s2) == "table", "missing remote link for s2")

sent = nil
captured.upsert_items = nil
api.handle_request(server, client, make_post("/api/v1/servers/dvr/import-streams", {
    server_id = "dvr1",
    stream_ids = { "s1" },
    origin_url = "http://127.0.0.1:9060",
}))
assert_true(sent and tonumber(sent.code) == 200, "expected 200 for dvr import-streams with server_id alias")
local import_server_id_payload = decode_sent()
assert_true(import_server_id_payload.ok == true, "expected ok=true on server_id alias import")
assert_true(type(captured.upsert_items) == "table" and #captured.upsert_items == 1, "expected one import item for server_id alias")
assert_true(captured.upsert_items[1].stream_id == "s1", "expected stream_id=s1 for server_id alias import")

sent = nil
captured.upsert_items = nil
api.handle_request(server, client, make_post("/api/v1/servers/dvr/import-streams", {
    id = "dvr1",
    stream_ids = { "s1" },
    origin_url = "http://127.0.0.1:17000",
}))
assert_true(sent and tonumber(sent.code) == 400, "expected 400 for self-origin import")
local import_self_origin_payload = decode_sent()
assert_true(tostring(import_self_origin_payload.error or ""):find("origin_url points to selected DVR server", 1, true) ~= nil,
    "expected explicit self-origin guard error")
assert_true(captured.upsert_items == nil, "self-origin import must not call upsert")

sent = nil
captured.upsert_items = nil
api.handle_request(server, client, make_post("/api/v1/servers/dvr/import-streams", {
    id = "dvr1",
    stream_ids = { "s1" },
}, {
    ["host"] = "panel.local:9060",
    ["x-forwarded-proto"] = "https",
}))
assert_true(sent and tonumber(sent.code) == 200, "expected 200 for dvr import-streams host/proto fallback")
local import_fallback_payload = decode_sent()
assert_true(import_fallback_payload.ok == true, "expected ok=true on fallback import")
assert_true(import_fallback_payload.origin_url == "https://panel.local:9060", "unexpected fallback origin_url")
assert_true(import_fallback_payload.origin_auth_source == "server", "expected server auth source on fallback import")
assert_true(type(captured.upsert_items) == "table" and #captured.upsert_items == 1, "expected one fallback import item")
assert_true(captured.upsert_items[1].source_url == "https://admin:admin@panel.local:9060/play/s1", "unexpected fallback source_url")
assert_true(captured.upsert_items[1].archive_path == "/var/dvr/s1", "expected stream-level archive path in fallback import")

local storage_calls_before_explicit = captured.storage_candidates_calls
sent = nil
captured.upsert_items = nil
api.handle_request(server, client, make_post("/api/v1/servers/dvr/import-streams", {
    id = "dvr1",
    stream_ids = { "s1" },
    origin_url = "http://127.0.0.1:9060",
    archive_path = "/media/custom-dvr",
}))
assert_true(sent and tonumber(sent.code) == 200, "expected 200 for explicit archive path import")
local import_explicit_payload = decode_sent()
assert_true(import_explicit_payload.ok == true, "expected ok=true for explicit archive path import")
assert_true(import_explicit_payload.archive_path_source == "request", "expected request archive source")
assert_true(type(captured.upsert_items) == "table" and #captured.upsert_items == 1, "expected one explicit import item")
assert_true(captured.upsert_items[1].archive_path == "/media/custom-dvr", "expected explicit archive path in import payload")
assert_true(captured.storage_candidates_calls == storage_calls_before_explicit, "storage candidates should not be called for explicit archive path")

sent = nil
captured.upsert_items = nil
api.handle_request(server, client, make_post("/api/v1/servers/dvr/import-streams", {
    id = "dvr1",
    stream_ids = { "s1" },
    origin_url = "http://127.0.0.1:9060",
    origin_play_token = "tok-123",
}))
assert_true(sent and tonumber(sent.code) == 200, "expected 200 for import with origin_play_token")
local import_token_payload = decode_sent()
assert_true(import_token_payload.ok == true, "expected ok=true for tokenized import")
assert_true(import_token_payload.origin_play_token_source == "request", "expected request token source")
assert_true(import_token_payload.origin_auth_source == "token", "expected token auth source for tokenized import")
assert_true(type(captured.upsert_items) == "table" and #captured.upsert_items == 1, "expected one tokenized import item")
assert_true(captured.upsert_items[1].source_url == "http://127.0.0.1:9060/play/s1?token=tok-123",
    "expected source_url token query param for tokenized import")

sent = nil
captured.upsert_items = nil
api.handle_request(server, client, make_post("/api/v1/servers/dvr/import-streams", {
    id = "dvr1",
    stream_ids = { "cfg_stream_id" },
    origin_url = "http://127.0.0.1:9060",
}))
assert_true(sent and tonumber(sent.code) == 200, "expected 200 for import by config.id")
local import_cfgid_payload = decode_sent()
assert_true(import_cfgid_payload.ok == true, "expected ok=true for config.id import")
assert_true(type(captured.upsert_items) == "table" and #captured.upsert_items == 1, "expected one config.id import item")
assert_true(captured.upsert_items[1].stream_id == "cfg_stream_id", "expected stream_id from config.id in import payload")
assert_true(captured.upsert_items[1].source_url == "http://admin:admin@127.0.0.1:9060/play/cfg_stream_id",
    "expected source_url based on config.id when selected by config.id")

captured.storage_fail_next = true
sent = nil
captured.upsert_items = nil
api.handle_request(server, client, make_post("/api/v1/servers/dvr/import-streams", {
    id = "dvr1",
    stream_ids = { "s2" },
    origin_url = "http://127.0.0.1:9060",
}))
assert_true(sent and tonumber(sent.code) == 200, "expected 200 when remote storage detection fails")
local import_storage_fail_payload = decode_sent()
assert_true(import_storage_fail_payload.ok == true, "expected ok=true when storage detection fails")
assert_true(import_storage_fail_payload.archive_path_source == "fallback", "expected fallback archive source")
assert_true(type(import_storage_fail_payload.storage_warning) == "string" and import_storage_fail_payload.storage_warning ~= "",
    "expected storage warning when detection fails")
assert_true(type(captured.upsert_items) == "table" and #captured.upsert_items == 1, "expected one import item on storage failure")
assert_true(captured.upsert_items[1].archive_path == nil, "archive path must be omitted when detection fails and no local path exists")

sent = nil
api.handle_request(server, client, make_post("/api/v1/servers/dvr/storage/candidates", {
    id = "dvr1",
    refresh = true,
}))
assert_true(sent and tonumber(sent.code) == 200, "expected 200 for remote dvr storage candidates")
local remote_storage_payload = decode_sent()
assert_true(remote_storage_payload.ok == true, "expected ok=true for remote storage candidates")
assert_true(remote_storage_payload.recommended_path == "/media/dvr-auto", "unexpected remote recommended_path")
assert_true(type(remote_storage_payload.candidates) == "table" and #remote_storage_payload.candidates >= 1,
    "expected remote storage candidates")

sent = nil
api.handle_request(server, client, {
    method = "GET",
    path = "/api/v1/dvr/storage/candidates",
    addr = "127.0.0.1",
    headers = {},
    query = { refresh = "1" },
})
assert_true(sent and tonumber(sent.code) == 200, "expected 200 for local dvr storage candidates")
local local_storage_payload = decode_sent()
assert_true(local_storage_payload.ok == true, "expected ok=true for local storage candidates")
assert_true(type(local_storage_payload.candidates) == "table", "expected local storage candidates list")

sent = nil
api.handle_request(server, client, make_post("/api/v1/servers/dvr/sync-state", {
    id = "dvr1",
    stream_id = "s1",
    mode = "DVR_ACTIVE",
    reason = "no_data",
    state_seq = 7,
}))
assert_true(sent and tonumber(sent.code) == 200, "expected 200 for dvr sync-state")
local sync_payload = decode_sent()
assert_true(sync_payload.ok == true, "expected ok=true for sync-state")
assert_true(sync_payload.queued == true, "expected queued=true")
assert_true(sync_payload.sent == true, "expected sent=true")
assert_true(type(captured.ingest_payload) == "table", "expected remote ingest payload")
assert_true(captured.ingest_payload.stream_id == "s1", "unexpected stream_id in ingest payload")
assert_true(captured.ingest_payload.mode == "DVR_ACTIVE", "unexpected mode in ingest payload")
assert_true(tonumber(captured.ingest_payload.state_seq) == 7, "unexpected state_seq in ingest payload")

local sync_state = dvr.get_remote_sync_state("s1", "dvr1")
assert_true(type(sync_state) == "table", "missing sync state row")
assert_true(tonumber(sync_state.last_state_seq) == 7, "sync state seq mismatch")
assert_true(tostring(sync_state.last_mode or "") == "DVR_ACTIVE", "sync state mode mismatch")

local ingest_count_before_adhoc = #captured.ingest_payloads
sent = nil
api.handle_request(server, client, make_post("/api/v1/servers/dvr/sync-state", {
    type = "dvr_v1",
    host = "127.0.0.1",
    port = 17000,
    login = "admin",
    password = "admin",
    stream_id = "s2",
    mode = "LIVE",
    reason = "adhoc",
}))
assert_true(sent and tonumber(sent.code) == 200, "expected 200 for adhoc dvr sync-state")
local sync_adhoc_payload = decode_sent()
assert_true(sync_adhoc_payload.ok == true, "expected ok=true for adhoc sync-state")
assert_true(sync_adhoc_payload.queued == false, "expected queued=false for adhoc sync-state")
assert_true(sync_adhoc_payload.sent == true, "expected sent=true for adhoc sync-state")
assert_true(#captured.ingest_payloads == (ingest_count_before_adhoc + 1), "expected direct remote ingest call for adhoc sync-state")
local adhoc_ingest = captured.ingest_payloads[#captured.ingest_payloads]
assert_true(type(adhoc_ingest) == "table", "expected adhoc ingest payload")
assert_true(adhoc_ingest.stream_id == "s2", "unexpected adhoc stream_id in ingest payload")
assert_true(adhoc_ingest.mode == "LIVE", "unexpected adhoc mode in ingest payload")

sent = nil
api.handle_request(server, client, make_post("/api/v1/servers/dvr/backup/cursor/reset", {
    id = "dvr1",
    stream_ids = { "s1", "s2" },
}))
assert_true(sent and tonumber(sent.code) == 200, "expected 200 for dvr backup cursor reset")
local reset_payload = decode_sent()
assert_true(reset_payload.ok == true, "expected ok=true for backup cursor reset")
assert_true(tonumber(reset_payload.affected) == 2, "expected affected=2 for backup cursor reset")
assert_true(type(captured.cursor_reset_payload) == "table", "expected cursor reset payload capture")
assert_true(type(captured.cursor_reset_payload.stream_ids) == "table", "expected stream_ids in cursor reset payload")
assert_true(captured.cursor_reset_payload.stream_ids[1] == "s1", "unexpected first stream_id in cursor reset payload")

sent = nil
api.handle_request(server, client, make_post("/api/v1/servers/dvr/backup/cycle/rebuild", {
    id = "dvr1",
    stream_ids = { "s2" },
    include_partial = false,
    min_partial_sec = 120,
}))
assert_true(sent and tonumber(sent.code) == 200, "expected 200 for dvr backup cycle rebuild")
local rebuild_payload = decode_sent()
assert_true(rebuild_payload.ok == true, "expected ok=true for backup cycle rebuild")
assert_true(tonumber(rebuild_payload.affected) == 1, "expected affected=1 for backup cycle rebuild")
assert_true(type(captured.cycle_rebuild_payload) == "table", "expected cycle rebuild payload capture")
assert_true(captured.cycle_rebuild_payload.include_partial == false, "expected include_partial=false for cycle rebuild payload")
assert_true(tonumber(captured.cycle_rebuild_payload.min_partial_sec) == 120, "expected min_partial_sec=120 for cycle rebuild payload")

-- Auto-sync prefers fresh local DVR mode over coarse on_air status mapping.
runtime = {
    list_status_lite_ids = function(_ids)
        return {
            s1 = { on_air = true, last_error = "" },
            s2 = { on_air = false, last_error = "no_data" },
        }
    end,
}
dvr.upsert_stream({
    stream_id = "s2",
    name = "Stream Two",
    source_url = "http://127.0.0.1:9000/play/s2",
    record_enabled = true,
    retention_days = 3,
    segment_sec = 3600,
    recording_paused = true,
    last_mode = "RECOVERING_TO_LIVE",
    last_reason = "recovering_to_live",
    updated_ts = os.time(),
})
dvr.upsert_remote_sync_state({
    stream_id = "s2",
    dvr_server_id = "dvr1",
    last_state_seq = 0,
    last_mode = "LIVE",
    updated_ts = os.time(),
})
local ingest_count_before = #captured.ingest_payloads
api._dvr_auto_sync_tick()
api._dvr_outbox_flush(20)
local ingest_count_after = #captured.ingest_payloads
assert_true(ingest_count_after > ingest_count_before, "expected auto sync to send ingest_state")
local found_recovering = false
for i = ingest_count_before + 1, ingest_count_after do
    local payload = captured.ingest_payloads[i]
    if payload and payload.stream_id == "s2" then
        assert_true(payload.mode == "RECOVERING_TO_LIVE", "expected RECOVERING_TO_LIVE from local DVR mode")
        found_recovering = true
    end
end
assert_true(found_recovering, "expected ingest payload for s2")

_G.__stream_remote_servers = nil
_G.__stream_dvr = nil
runtime = nil

log.info("[unit] servers_dvr_import_sync_unit ok")
astra.exit()
