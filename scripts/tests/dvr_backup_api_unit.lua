log.set({ debug = true })

dofile("scripts/base.lua")
dofile("scripts/config.lua")
dofile("scripts/dvr.lua")

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

local tmp = "/tmp/dvr_backup_api_unit"
os.execute("rm -rf " .. tmp .. " >/dev/null 2>&1 || true")
os.execute("mkdir -p " .. tmp)

config.init({
    data_dir = tmp,
    db_path = tmp .. "/stream.db",
})
config.set_setting("http_auth_enabled", false)

local stream_id = "api_dvr_1"
local upsert_ok, upsert_err = dvr.upsert_stream({
    stream_id = stream_id,
    name = "API DVR 1",
    source_url = "http://127.0.0.1/play/" .. stream_id,
    record_enabled = true,
    retention_days = 3,
})
assert_true(upsert_ok ~= nil, upsert_err or "upsert stream failed")

local function add_seg(start_ts)
    local paths = dvr.segment_paths(stream_id, start_ts)
    local fh = io.open(paths.final_path, "wb")
    if fh then
        fh:write("seg")
        fh:close()
    end
    local ok, err = dvr.upsert_segment({
        stream_id = stream_id,
        seg_start_ts = start_ts,
        seg_end_ts = start_ts + 3600,
        path = paths.final_path,
        size_bytes = 3,
        is_complete = true,
    })
    assert_true(ok ~= nil, err or "upsert segment failed")
end

local base = 1700000000
add_seg(base)
add_seg(base + 3600)

_G.__stream_dvr = dvr
dofile("scripts/api.lua")

local sent = nil
local server = {
    send = function(_, _, payload)
        sent = payload
    end,
}
local client = {}

local function decode_sent_json()
    local ok, payload = pcall(json.decode, sent and sent.content or "")
    assert_true(ok and type(payload) == "table", "expected JSON response")
    return payload
end

sent = nil
api.handle_request(server, client, {
    method = "GET",
    path = "/api/v1/dvr/backup/next-segment",
    addr = "127.0.0.1",
    headers = {},
    query = { stream_id = stream_id },
})
assert_true(sent and tonumber(sent.code) == 200, "next-segment must return 200")
local next_payload = decode_sent_json()
assert_true(next_payload.ok == true, "next-segment payload must be ok")
assert_eq(tonumber(next_payload.segment and next_payload.segment.seg_start_ts), base, "must start from oldest segment")

sent = nil
api.handle_request(server, client, {
    method = "POST",
    path = "/api/v1/dvr/backup/progress",
    addr = "127.0.0.1",
    headers = { ["content-type"] = "application/json" },
    query = {},
    content = json.encode({
        stream_id = stream_id,
        played_sec = 3599,
    }),
})
assert_true(sent and tonumber(sent.code) == 200, "progress must return 200")
local progress_payload = decode_sent_json()
assert_true(progress_payload.ok == true, "progress payload must be ok")
assert_true(progress_payload.advanced == true, "progress must advance to next segment")
assert_eq(tonumber(progress_payload.state and progress_payload.state.cursor_seg_start_ts), base + 3600,
    "cursor must move to second segment")

sent = nil
api.handle_request(server, client, {
    method = "POST",
    path = "/api/v1/dvr/backup/cursor/reset-bulk",
    addr = "127.0.0.1",
    headers = { ["content-type"] = "application/json" },
    query = {},
    content = json.encode({
        stream_ids = { stream_id },
    }),
})
assert_true(sent and tonumber(sent.code) == 200, "cursor reset bulk must return 200")
local reset_bulk_payload = decode_sent_json()
assert_true(reset_bulk_payload.ok == true, "cursor reset bulk payload must be ok")
assert_eq(tonumber(reset_bulk_payload.total), 1, "cursor reset bulk total mismatch")
assert_eq(tonumber(reset_bulk_payload.affected), 1, "cursor reset bulk affected mismatch")
assert_true(type(reset_bulk_payload.failed) == "table" and #reset_bulk_payload.failed == 0,
    "cursor reset bulk failed list must be empty")

sent = nil
api.handle_request(server, client, {
    method = "POST",
    path = "/api/v1/dvr/backup/cycle/rebuild-bulk",
    addr = "127.0.0.1",
    headers = { ["content-type"] = "application/json" },
    query = {},
    content = json.encode({
        stream_ids = { stream_id },
        include_partial = true,
    }),
})
assert_true(sent and tonumber(sent.code) == 200, "cycle rebuild bulk must return 200")
local rebuild_bulk_payload = decode_sent_json()
assert_true(rebuild_bulk_payload.ok == true, "cycle rebuild bulk payload must be ok")
assert_eq(tonumber(rebuild_bulk_payload.total), 1, "cycle rebuild bulk total mismatch")
assert_eq(tonumber(rebuild_bulk_payload.affected), 1, "cycle rebuild bulk affected mismatch")
assert_true(type(rebuild_bulk_payload.failed) == "table" and #rebuild_bulk_payload.failed == 0,
    "cycle rebuild bulk failed list must be empty")
assert_true(type(rebuild_bulk_payload.items) == "table" and #rebuild_bulk_payload.items == 1,
    "cycle rebuild bulk items must contain one row")

sent = nil
api.handle_request(server, client, {
    method = "POST",
    path = "/api/v1/dvr/backup/cursor/reset-bulk",
    addr = "127.0.0.1",
    headers = { ["content-type"] = "application/json" },
    query = {},
    content = json.encode({
        stream_ids = {},
    }),
})
assert_true(sent and tonumber(sent.code) == 400, "cursor reset bulk with empty ids must return 400")

sent = nil
api.handle_request(server, client, {
    method = "POST",
    path = "/api/v1/dvr/backup/cycle/rebuild-bulk",
    addr = "127.0.0.1",
    headers = { ["content-type"] = "application/json" },
    query = {},
    content = json.encode({
        stream_ids = {},
    }),
})
assert_true(sent and tonumber(sent.code) == 400, "cycle rebuild bulk with empty ids must return 400")

_G.__stream_dvr = nil

log.info("[unit] dvr_backup_api_unit ok")
astra.exit()
