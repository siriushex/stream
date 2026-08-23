log.set({ debug = true })

dofile("scripts/base.lua")
dofile("scripts/config.lua")

local function assert_true(value, message)
    if not value then
        error(message or "assert_true failed")
    end
end

local tmp = "/tmp/buffer_av_failover_config_unit"
os.execute("rm -rf " .. tmp .. " >/dev/null 2>&1 || true")
os.execute("mkdir -p " .. tmp)

local opts = {
    data_dir = tmp,
    db_path = tmp .. "/stream.db",
}
config.init(opts)
config.upsert_buffer_resource("health", {
    name = "Health",
    path = "/health",
    enable = false,
    health_require_video = true,
    health_require_audio = true,
    health_min_bitrate_kbps = 256,
    health_failover_sec = 7,
    health_fail_checks = 3,
})

local row = config.get_buffer_resource("health")
assert_true(row ~= nil, "buffer resource missing")
assert_true(row.health_require_video == 1, "video requirement was not persisted")
assert_true(row.health_require_audio == 1, "audio requirement was not persisted")
assert_true(row.health_min_bitrate_kbps == 256, "minimum bitrate was not persisted")
assert_true(row.health_failover_sec == 7, "failover time was not persisted")
assert_true(row.health_fail_checks == 3, "failure checks were not persisted")

config.migrate()
local reopened = config.get_buffer_resource("health")
assert_true(reopened.health_fail_checks == 3, "idempotent migration changed resource")

print("buffer_av_failover_config_unit: ok")
astra.exit()
