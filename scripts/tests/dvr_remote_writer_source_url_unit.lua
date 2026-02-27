log.set({ debug = true })

dofile("scripts/base.lua")
dofile("scripts/config.lua")
dofile("scripts/dvr.lua")

local function assert_true(value, message)
    if not value then
        error(message or "assert failed")
    end
end

local tmp = "/tmp/dvr_remote_writer_source_url_unit"
os.execute("rm -rf " .. tmp .. " >/dev/null 2>&1 || true")
os.execute("mkdir -p " .. tmp)

config.init({
    data_dir = tmp,
    db_path = tmp .. "/stream.db",
})

local src_path = tmp .. "/source.ts"
local source_fh = io.open(src_path, "wb")
assert_true(source_fh ~= nil, "failed to create source.ts")

local function make_ts_packet_with_pcr(pid, cc, pcr_base)
    pid = tonumber(pid) or 256
    cc = tonumber(cc) or 0
    pcr_base = tonumber(pcr_base) or 0

    local b = {}
    b[1] = 0x47
    b[2] = math.floor(pid / 256) % 0x20
    b[3] = pid % 0x100
    b[4] = 0x20 + (cc % 16) -- adaptation only

    b[5] = 7 -- flags + PCR(6)
    b[6] = 0x10 -- PCR flag

    local p = pcr_base
    local ext = 0
    b[7] = math.floor(p / 0x2000000) % 0x100
    b[8] = math.floor(p / 0x20000) % 0x100
    b[9] = math.floor(p / 0x200) % 0x100
    b[10] = math.floor(p / 2) % 0x100
    b[11] = ((p % 2) * 0x80) + 0x7E + math.floor(ext / 0x100)
    b[12] = ext % 0x100

    for i = 13, 188 do
        b[i] = 0xFF
    end
    return string.char(table.unpack(b))
end

for i = 0, 255 do
    -- ~40ms PCR step at 90kHz clock
    source_fh:write(make_ts_packet_with_pcr(256, i % 16, i * 3600))
end
source_fh:close()

local stream_id = "remote_dvr_1"
local upsert_ok, upsert_err = dvr.upsert_stream({
    stream_id = stream_id,
    name = "Remote DVR 1",
    source_url = "file://" .. src_path .. "#loop",
    record_enabled = true,
    retention_days = 3,
    recording_paused = false,
})
assert_true(upsert_ok ~= nil, upsert_err or "upsert stream failed")

runtime = {
    streams = {},
}

local function tick_and_wait(iterations)
    local total = tonumber(iterations) or 1
    if total < 1 then total = 1 end
    for _ = 1, total do
        dvr.local_tick()
        os.execute("sleep 1")
    end
end

tick_and_wait(4)

local segments_open = dvr.list_segments(stream_id, nil, nil, true, 16)
assert_true(type(segments_open) == "table", "remote writer segments list must be table")

local runtime_open = dvr.get_runtime_status(stream_id)
assert_true(type(runtime_open) == "table", "remote writer runtime status missing")
assert_true(tostring(runtime_open.active_input_url or ""):find("file://", 1, true) == 1,
    "runtime active_input_url should keep file source_url")

local bulk_res = dvr.bulk_record({
    stream_ids = { stream_id },
    record_enabled = false,
})
assert_true(type(bulk_res) == "table" and tonumber(bulk_res.affected) == 1, "bulk disable failed")

tick_and_wait(3)

local segments_after = dvr.list_segments(stream_id, nil, nil, true, 16)
assert_true(type(segments_after) == "table", "segments_after should be table")
-- Empty list is allowed here: empty/invalid upstream can produce zero-byte segment,
-- and writer finalization removes such segments by design.

local runtime_after = dvr.get_runtime_status(stream_id)
if runtime_after ~= nil then
    assert_true(type(runtime_after) == "table", "runtime_after must be table when present")
    assert_true(runtime_after.on_air == false, "runtime on_air should be false after disable")
end

log.info("[unit] dvr_remote_writer_source_url_unit ok")
astra.exit()
