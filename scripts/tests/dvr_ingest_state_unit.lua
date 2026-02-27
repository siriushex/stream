log.set({ debug = true })

dofile("scripts/base.lua")
dofile("scripts/config.lua")
dofile("scripts/dvr.lua")

local function assert_true(value, message)
    if not value then
        error(message or "assert failed")
    end
end

local tmp = "/tmp/dvr_ingest_state_unit"
os.execute("rm -rf " .. tmp .. " >/dev/null 2>&1 || true")
os.execute("mkdir -p " .. tmp)

config.init({
    data_dir = tmp,
    db_path = tmp .. "/stream.db",
})

local upsert_ok, upsert_err = dvr.upsert_stream({
    stream_id = "ch1",
    name = "Channel 1",
    source_url = "http://127.0.0.1/play/ch1",
    record_enabled = true,
    retention_days = 3,
})
assert_true(upsert_ok ~= nil, upsert_err or "upsert_stream failed")

local state1, state1_err = dvr.apply_ingest_state({
    stream_id = "ch1",
    mode = "DVR_ACTIVE",
    state_seq = 1,
    reason = "no_data",
    ts = 1700000001,
})
assert_true(type(state1) == "table", state1_err or "apply_ingest_state seq1 failed")
assert_true(state1.applied == true, "seq1 must be applied")
assert_true(state1.ignored_duplicate == false, "seq1 must not be duplicate")
assert_true(state1.recording_paused == true, "recording_paused must be true in DVR_ACTIVE")
assert_true(tonumber(state1.last_state_seq) == 1, "last_state_seq must be 1")

local state_dup, dup_err = dvr.apply_ingest_state({
    stream_id = "ch1",
    mode = "DVR_ACTIVE",
    state_seq = 1,
    reason = "duplicate",
    ts = 1700000002,
})
assert_true(type(state_dup) == "table", dup_err or "apply_ingest_state duplicate failed")
assert_true(state_dup.applied == false, "duplicate must be ignored")
assert_true(state_dup.ignored_duplicate == true, "duplicate flag must be true")
assert_true(state_dup.recording_paused == true, "duplicate must keep previous paused flag")
assert_true(tonumber(state_dup.last_state_seq) == 1, "duplicate must keep seq=1")

local state2, state2_err = dvr.apply_ingest_state({
    stream_id = "ch1",
    mode = "LIVE",
    state_seq = 2,
    reason = "on_air",
    ts = 1700000003,
})
assert_true(type(state2) == "table", state2_err or "apply_ingest_state seq2 failed")
assert_true(state2.applied == true, "seq2 must be applied")
assert_true(state2.recording_paused == false, "recording_paused must be false in LIVE")
assert_true(tonumber(state2.last_state_seq) == 2, "last_state_seq must be 2")

local stream1 = dvr.get_stream("ch1")
assert_true(type(stream1) == "table", "stream ch1 missing after updates")
assert_true(stream1.recording_paused == false, "stream row must be resumed in LIVE")
assert_true(tonumber(stream1.last_state_seq) == 2, "stream row seq must be 2")
assert_true(tostring(stream1.last_mode or "") == "LIVE", "stream row mode must be LIVE")

local bootstrap, bootstrap_err = dvr.apply_ingest_state({
    stream_id = "new stream id",
    mode = "DVR_ACTIVE",
    state_seq = 1,
    reason = "bootstrap",
    ts = 1700000010,
})
assert_true(type(bootstrap) == "table", bootstrap_err or "bootstrap apply_ingest_state failed")
assert_true(bootstrap.applied == true, "bootstrap state must be applied")
assert_true(bootstrap.recording_paused == true, "bootstrap must pause recording")

local bootstrap_stream = dvr.get_stream("new stream id")
assert_true(type(bootstrap_stream) == "table", "bootstrap stream row missing")
assert_true(bootstrap_stream.source_url == "http://127.0.0.1/play/new_stream_id",
    "bootstrap source_url must be sanitized fallback /play URL")

log.info("[unit] dvr_ingest_state_unit ok")
astra.exit()
