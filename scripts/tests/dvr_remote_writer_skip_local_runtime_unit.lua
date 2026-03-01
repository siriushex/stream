log.set({ debug = true })

dofile("scripts/base.lua")
dofile("scripts/config.lua")
dofile("scripts/dvr.lua")

local function assert_true(value, message)
    if not value then
        error(message or "assert failed")
    end
end

local tmp = "/tmp/dvr_remote_writer_skip_local_runtime_unit"
os.execute("rm -rf " .. tmp .. " >/dev/null 2>&1 || true")
os.execute("mkdir -p " .. tmp)

config.init({
    data_dir = tmp,
    db_path = tmp .. "/stream.db",
})

local src_path = tmp .. "/source.ts"
local source_fh = io.open(src_path, "wb")
assert_true(source_fh ~= nil, "failed to create source.ts")
source_fh:write(string.rep("\x47", 188 * 32))
source_fh:close()

local stream_id = "11125"
local upsert_ok, upsert_err = dvr.upsert_stream({
    stream_id = stream_id,
    name = "Remote DVR Skip Local",
    source_url = "file://" .. src_path .. "#loop",
    record_enabled = true,
    retention_days = 3,
    recording_paused = false,
})
assert_true(upsert_ok ~= nil, upsert_err or "upsert stream failed")

runtime = {
    streams = {
        [tonumber(stream_id)] = {
            channel = {
                config = {
                    id = stream_id,
                    name = "Local Stream Shadow",
                    input = { "udp://127.0.0.1:12345" },
                    dvr = {
                        mode = "remote",
                        enabled = true,
                        backup_enabled = false,
                    },
                },
            },
        },
    },
}

for _ = 1, 3 do
    dvr.local_tick()
    os.execute("sleep 1")
end

local segments = dvr.list_segments(stream_id, nil, nil, true, 16) or {}
assert_true(#segments == 0, "remote writer must skip stream when local runtime stream exists")

local runtime_status = dvr.get_runtime_status(stream_id)
assert_true(runtime_status == nil, "remote runtime status should remain empty for skipped stream")

log.info("[unit] dvr_remote_writer_skip_local_runtime_unit ok")
astra.exit()
