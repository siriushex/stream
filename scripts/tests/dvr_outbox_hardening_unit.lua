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

local tmp = "/tmp/dvr_outbox_hardening_unit"
os.execute("rm -rf " .. tmp .. " >/dev/null 2>&1 || true")
os.execute("mkdir -p " .. tmp)

config.init({
    data_dir = tmp,
    db_path = tmp .. "/stream.db",
})
config.set_setting("dvr_remote_outbox_max", 3)

local function enqueue(stream_id, seq, mode, reason)
    local row, err = dvr.enqueue_remote_outbox({
        stream_id = stream_id,
        dvr_server_id = "dvr1",
        event_type = "ingest_state",
        payload = {
            stream_id = stream_id,
            mode = mode,
            reason = reason,
            ts = os.time(),
            state_seq = seq,
        },
    })
    assert_true(type(row) == "table", err or "enqueue failed")
    return row
end

local first = enqueue("s1", 1, "DVR_ACTIVE", "no_data")
assert_true(tonumber(first.id) and first.id > 0, "first row id expected")
assert_eq(dvr.outbox_count(), 1, "outbox must contain first row")

local duplicate = enqueue("s1", 1, "DVR_ACTIVE", "no_data")
assert_true(duplicate.duplicate == true, "same seq/mode should be deduplicated")
assert_eq(duplicate.id, first.id, "duplicate should return same outbox id")
assert_eq(dvr.outbox_count(), 1, "duplicate must not grow queue")

local second = enqueue("s1", 2, "LIVE", "on_air")
assert_true(tonumber(second.id) and second.id > first.id, "new seq must enqueue new row")
assert_eq(dvr.outbox_count(), 1, "newer seq should replace obsolete queued state")

local ready = dvr.list_outbox_ready(10)
assert_eq(#ready, 1, "expected one ready row after replace")
assert_eq(tonumber(ready[1].payload and ready[1].payload.state_seq), 2, "queued seq must be latest")
assert_eq(tostring(ready[1].payload and ready[1].payload.mode), "LIVE", "queued mode must be latest")

enqueue("s2", 1, "DVR_ACTIVE", "no_data")
enqueue("s3", 1, "DVR_ACTIVE", "no_data")
enqueue("s4", 1, "DVR_ACTIVE", "no_data")
assert_eq(dvr.outbox_count(), 3, "queue must be capped by dvr_remote_outbox_max")

ready = dvr.list_outbox_ready(10)
assert_eq(#ready, 3, "ready rows must respect cap")
local ids = {}
for _, row in ipairs(ready) do
    ids[tostring(row.stream_id)] = true
end
assert_true(ids.s2 == true and ids.s3 == true and ids.s4 == true, "oldest row must be pruned first")
assert_true(ids.s1 ~= true, "oldest stream row s1 expected pruned by cap")

log.info("[unit] dvr_outbox_hardening_unit ok")
astra.exit()
