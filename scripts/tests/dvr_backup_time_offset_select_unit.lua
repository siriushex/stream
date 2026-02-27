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

local tmp = "/tmp/dvr_backup_time_offset_select_unit"
os.execute("rm -rf " .. tmp .. " >/dev/null 2>&1 || true")
os.execute("mkdir -p " .. tmp)

config.init({
    data_dir = tmp,
    db_path = tmp .. "/stream.db",
})

local cfg = dvr.settings_for_stream({
    dvr = {
        backup_enabled = true,
        backup_start_mode = "time_offset",
    },
})
assert_eq(cfg.backup_start_mode, "time_offset", "backup_start_mode must keep explicit mode")
assert_eq(tonumber(cfg.backup_start_offset_hours), -24, "time_offset mode must default to -24h offset")

local stream_id = "dvr_time_offset"
local base = 1700030000
for i = 0, 5 do
    local seg_start = base + (i * 3600)
    local paths = dvr.segment_paths(stream_id, seg_start)
    local fh = assert(io.open(paths.final_path, "wb"))
    fh:write("seg" .. tostring(i))
    fh:close()
    local ok, err = dvr.upsert_segment({
        stream_id = stream_id,
        seg_start_ts = seg_start,
        seg_end_ts = seg_start + 3600,
        path = paths.final_path,
        size_bytes = 4,
        is_complete = true,
    })
    assert_true(ok ~= nil, err or "upsert segment failed")
end

local now_ts = base + (5 * 3600) + 1800
local first, first_err = dvr.backup_select_segment(stream_id, {
    allow_cycle_restart = true,
    start_mode = "time_offset",
    start_offset_hours = -2,
    now_ts = now_ts,
})
assert_true(type(first) == "table", first_err or "time-offset select failed")
assert_eq(tonumber(first.segment and first.segment.seg_start_ts), base + (3 * 3600),
    "time-offset select must start from nearest <= target segment")

local first_state = dvr.get_backup_state_for_api(stream_id)
assert_eq(tonumber(first_state.skipped_count), 3, "segments before offset target must be skipped in cycle")

local step1, step1_err = dvr.backup_commit_progress(stream_id, {
    played_sec = 3599,
    allow_cycle_restart = true,
    start_mode = "time_offset",
    start_offset_hours = -2,
    now_ts = now_ts,
})
assert_true(type(step1) == "table", step1_err or "step1 progress failed")
assert_true(step1.advanced == true, "step1 must advance")
assert_eq(tonumber(step1.state and step1.state.cursor_seg_start_ts), base + (4 * 3600),
    "step1 must move to next sequential segment")

local step2, step2_err = dvr.backup_commit_progress(stream_id, {
    played_sec = 3599,
    allow_cycle_restart = true,
    start_mode = "time_offset",
    start_offset_hours = -2,
    now_ts = now_ts,
})
assert_true(type(step2) == "table", step2_err or "step2 progress failed")
assert_true(step2.advanced == true, "step2 must advance")
assert_eq(tonumber(step2.state and step2.state.cursor_seg_start_ts), base + (5 * 3600),
    "step2 must move to next sequential segment")

local step3, step3_err = dvr.backup_commit_progress(stream_id, {
    played_sec = 3599,
    allow_cycle_restart = true,
    start_mode = "time_offset",
    start_offset_hours = -2,
    now_ts = now_ts,
})
assert_true(type(step3) == "table", step3_err or "step3 progress failed")
assert_true(step3.advanced == true, "step3 must advance via cycle restart")
assert_true(step3.cycle_restarted == true, "step3 must restart cycle when exhausted")
assert_eq(tonumber(step3.state and step3.state.cursor_seg_start_ts), base,
    "restarted cycle must begin from oldest segment")

log.info("[unit] dvr_backup_time_offset_select_unit ok")
astra.exit()
