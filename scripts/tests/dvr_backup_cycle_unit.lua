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

local tmp = "/tmp/dvr_backup_cycle_unit"
os.execute("rm -rf " .. tmp .. " >/dev/null 2>&1 || true")
os.execute("mkdir -p " .. tmp)

config.init({
    data_dir = tmp,
    db_path = tmp .. "/stream.db",
})

local stream_id = "dvr_ch1"
local ok, err = dvr.upsert_stream({
    stream_id = stream_id,
    name = "DVR Channel",
    source_url = "http://127.0.0.1/play/" .. stream_id,
    record_enabled = true,
    retention_days = 3,
})
assert_true(ok ~= nil, err or "upsert stream failed")

local base = 1700000000
local function add_seg(start_ts)
    local paths = dvr.segment_paths(stream_id, start_ts)
    local fh = io.open(paths.final_path, "wb")
    if fh then
        fh:write("test")
        fh:close()
    end
    local seg_ok, seg_err = dvr.upsert_segment({
        stream_id = stream_id,
        seg_start_ts = start_ts,
        seg_end_ts = start_ts + 3600,
        path = paths.final_path,
        size_bytes = 4,
        is_complete = true,
    })
    assert_true(seg_ok ~= nil, seg_err or "upsert segment failed")
end

add_seg(base)
add_seg(base + 3600)
add_seg(base + 7200)

local selected1, selected1_err = dvr.backup_select_segment(stream_id, {
    allow_cycle_restart = true,
})
assert_true(type(selected1) == "table", selected1_err or "select #1 failed")
assert_eq(tonumber(selected1.segment.seg_start_ts), base, "must pick oldest segment first")

local keep_progress, keep_progress_err = dvr.backup_commit_progress(stream_id, {
    played_sec = 120,
})
assert_true(type(keep_progress) == "table", keep_progress_err or "progress commit failed")
assert_true(keep_progress.advanced == false, "progress update must not advance")
assert_eq(tonumber(keep_progress.state.cursor_seg_start_ts), base, "cursor must stay on first segment")
assert_eq(tonumber(keep_progress.state.cursor_offset_sec), 120, "cursor offset must be persisted")

local selected_after_resume, selected_after_resume_err = dvr.backup_select_segment(stream_id, {
    allow_cycle_restart = true,
})
assert_true(type(selected_after_resume) == "table", selected_after_resume_err or "resume select failed")
assert_eq(tonumber(selected_after_resume.segment.seg_start_ts), base, "resume must keep same segment")
assert_true(tonumber(selected_after_resume.state.cursor_offset_sec) >= 120, "resume must keep offset")

local done_first, done_first_err = dvr.backup_commit_progress(stream_id, {
    played_sec = 3598,
})
assert_true(type(done_first) == "table", done_first_err or "done first failed")
assert_true(done_first.advanced == true, "done first must advance to next")
assert_eq(tonumber(done_first.state.cursor_seg_start_ts), base + 3600, "must advance to second segment")

local done_second, done_second_err = dvr.backup_commit_progress(stream_id, {
    played_sec = 3599,
})
assert_true(type(done_second) == "table", done_second_err or "done second failed")
assert_true(done_second.advanced == true, "done second must advance")
assert_eq(tonumber(done_second.state.cursor_seg_start_ts), base + 7200, "must advance to third segment")

local exhausted, exhausted_err = dvr.backup_commit_progress(stream_id, {
    played_sec = 3599,
    allow_cycle_restart = false,
})
assert_true(type(exhausted) == "table", exhausted_err or "exhausted commit failed")
assert_true(exhausted.cycle_exhausted == true, "cycle must be exhausted when restart is disabled")
assert_eq(tonumber(exhausted.state.cursor_seg_start_ts), 0, "cursor must reset on exhausted cycle")

local restarted, restarted_err = dvr.backup_select_segment(stream_id, {
    allow_cycle_restart = true,
})
assert_true(type(restarted) == "table", restarted_err or "restart select failed")
assert_true(restarted.cycle_restarted == true, "must start a new cycle after exhaustion")
assert_eq(tonumber(restarted.segment.seg_start_ts), base, "new cycle must start from oldest segment")

log.info("[unit] dvr_backup_cycle_unit ok")
astra.exit()
