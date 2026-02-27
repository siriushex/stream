log.set({ debug = true })

dofile("scripts/base.lua")
dofile("scripts/config.lua")
dofile("scripts/dvr.lua")

local function assert_true(value, message)
    if not value then
        error(message or "assert failed")
    end
end

local tmp = "/tmp/dvr_backup_select_skip_empty_segment_unit"
os.execute("rm -rf " .. tmp .. " >/dev/null 2>&1 || true")
os.execute("mkdir -p " .. tmp)

config.init({
    data_dir = tmp,
    db_path = tmp .. "/stream.db",
})

local stream_id = "dvr_select_skip_empty"
local seg1 = tmp .. "/seg1.part.ts"
local seg2 = tmp .. "/seg2.ts"

local fp1 = assert(io.open(seg1, "wb"))
fp1:close()
local fp2 = assert(io.open(seg2, "wb"))
fp2:write(string.rep("A", 4096))
fp2:close()

local ok1, err1 = dvr.upsert_segment({
    stream_id = stream_id,
    seg_start_ts = 1700000000,
    seg_end_ts = 1700003600,
    path = seg1,
    size_bytes = 0,
    is_complete = true,
    created_ts = 1700000000,
    updated_ts = 1700003600,
})
assert_true(ok1 ~= nil, err1 or "upsert seg1 failed")

local ok2, err2 = dvr.upsert_segment({
    stream_id = stream_id,
    seg_start_ts = 1700003600,
    seg_end_ts = 1700007200,
    path = seg2,
    size_bytes = 4096,
    is_complete = true,
    created_ts = 1700003600,
    updated_ts = 1700007200,
})
assert_true(ok2 ~= nil, err2 or "upsert seg2 failed")

local selected, sel_err = dvr.backup_select_segment(stream_id, {
    allow_cycle_restart = true,
    include_partial = true,
})
assert_true(type(selected) == "table", sel_err or "backup_select_segment failed")
assert_true(type(selected.segment) == "table", "segment missing")
assert_true(tonumber(selected.segment.seg_start_ts) == 1700003600, "must skip empty segment and select next")
assert_true(tonumber(selected.segment.size_bytes) == 4096, "selected segment size mismatch")

local state = dvr.get_backup_state_for_api(stream_id)
assert_true(type(state) == "table", "backup state missing")
assert_true(tonumber(state.skipped_count) >= 1, "empty segment must be marked skipped")
assert_true(tonumber(state.playing_count) >= 1, "next segment must be marked playing")

log.info("[unit] dvr_backup_select_skip_empty_segment_unit ok")
astra.exit()
