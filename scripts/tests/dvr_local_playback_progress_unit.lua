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

local tmp = "/tmp/dvr_local_playback_progress_unit"
os.execute("rm -rf " .. tmp .. " >/dev/null 2>&1 || true")
os.execute("mkdir -p " .. tmp)

config.init({
    data_dir = tmp,
    db_path = tmp .. "/stream.db",
})

local stream_id = "local_dvr_1"
local ok, err = dvr.upsert_stream({
    stream_id = stream_id,
    name = "Local DVR",
    source_url = "http://127.0.0.1/play/" .. stream_id,
    record_enabled = true,
    retention_days = 3,
})
assert_true(ok ~= nil, err or "upsert stream failed")

local base = 1700010000
local function add_seg(start_ts)
    local paths = dvr.segment_paths(stream_id, start_ts)
    local fh = io.open(paths.final_path, "wb")
    if fh then
        fh:write(string.rep("a", 100))
        fh:close()
    end
    local seg_ok, seg_err = dvr.upsert_segment({
        stream_id = stream_id,
        seg_start_ts = start_ts,
        seg_end_ts = start_ts + 3600,
        path = paths.final_path,
        size_bytes = 100,
        is_complete = true,
    })
    assert_true(seg_ok ~= nil, seg_err or "upsert segment failed")
    return paths
end

local seg1_paths = add_seg(base)
add_seg(base + 3600)

local selected, selected_err = dvr.backup_select_segment(stream_id, {
    allow_cycle_restart = true,
})
assert_true(type(selected) == "table", selected_err or "backup select failed")
assert_eq(tonumber(selected.segment.seg_start_ts), base, "must select first segment")

local lock_fp = io.open(seg1_paths.lock_path, "wb")
assert_true(lock_fp ~= nil, "failed to open lock file")
lock_fp:write("50")
lock_fp:close()

local lock_bytes = dvr.read_lock_bytes(seg1_paths.lock_path)
assert_eq(lock_bytes, 50, "lock bytes must be parsed")

local played_mid = dvr.estimate_segment_played_sec(selected.segment, lock_bytes, 0)
assert_eq(played_mid, 1800, "mid progress must be estimated from lock ratio")

local progress_mid, progress_mid_err = dvr.backup_commit_progress(stream_id, {
    seg_start_ts = base,
    played_sec = played_mid,
    allow_cycle_restart = true,
})
assert_true(type(progress_mid) == "table", progress_mid_err or "mid progress commit failed")
assert_true(progress_mid.advanced == false, "mid progress must keep current segment")
assert_eq(tonumber(progress_mid.state.cursor_seg_start_ts), base, "cursor must stay on first segment")

local played_done = dvr.estimate_segment_played_sec(selected.segment, 100, 0)
assert_eq(played_done, 3600, "done progress must map to full segment duration")

local progress_done, progress_done_err = dvr.backup_commit_progress(stream_id, {
    seg_start_ts = base,
    played_sec = played_done,
    segment_guard_sec = 3,
    allow_cycle_restart = true,
})
assert_true(type(progress_done) == "table", progress_done_err or "done progress commit failed")
assert_true(progress_done.advanced == true, "done progress must advance")
assert_eq(tonumber(progress_done.state.cursor_seg_start_ts), base + 3600, "cursor must move to next segment")

log.info("[unit] dvr_local_playback_progress_unit ok")
astra.exit()
