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

local tmp = "/tmp/dvr_archive_timeshift_query_unit"
os.execute("rm -rf " .. tmp .. " >/dev/null 2>&1 || true")
os.execute("mkdir -p " .. tmp)

config.init({
    data_dir = tmp,
    db_path = tmp .. "/stream.db",
})

local stream_id = "dvr_timeshift_q"
local base = 1700100000
for i = 0, 3 do
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

local now_ts = base + (3 * 3600) + 900 -- +15m

local resolved_2h = dvr.resolve_archive_from_query({ timeshift = "2" }, now_ts)
assert_eq(resolved_2h, now_ts - (2 * 3600), "timeshift=2 must resolve to now-2h")

local selected_2h, err_2h = dvr.select_archive_segment(stream_id, {
    include_partial = true,
    from_ts = resolved_2h,
    fallback_oldest = true,
})
assert_true(type(selected_2h) == "table", err_2h or "select 2h failed")
assert_eq(tonumber(selected_2h.segment and selected_2h.segment.seg_start_ts), base + 3600,
    "timeshift=2h must select segment at base+1h")
assert_eq(tonumber(selected_2h.cursor_offset_sec), 900, "offset inside selected segment must match 15m")

local resolved_neg = dvr.resolve_archive_from_query({ timeshift = "-2" }, now_ts)
assert_eq(resolved_neg, now_ts - (2 * 3600), "negative timeshift must be interpreted as hours back")

local resolved_with_from = dvr.resolve_archive_from_query({ from_ts = tostring(base + 7200), timeshift = "24" }, now_ts)
assert_eq(resolved_with_from, base + 7200, "from_ts must have priority over timeshift")

local invalid = dvr.resolve_archive_from_query({ timeshift = "abc" }, now_ts)
assert_eq(invalid, nil, "invalid timeshift must be ignored")

log.info("[unit] dvr_archive_timeshift_query_unit ok")
astra.exit()
