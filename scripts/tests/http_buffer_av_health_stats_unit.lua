log.set({ debug = true })

local instance = http_buffer({})
instance:apply_config({
    settings = {
        enabled = false,
        listen_host = "127.0.0.1",
        listen_port = 18089,
        max_clients_total = 2,
        client_read_timeout_sec = 2,
    },
    allow = {},
    resources = {
        {
            id = "health-unit",
            name = "Health Unit",
            path = "/health-unit",
            enable = false,
            backup_type = "active",
            no_data_timeout_sec = 2,
            backup_start_delay_sec = 1,
            backup_return_delay_sec = 8,
            backup_probe_interval_sec = 1,
            health_require_video = true,
            health_require_audio = true,
            health_min_bitrate_kbps = 256,
            health_failover_sec = 7,
            health_fail_checks = 3,
            buffering_sec = 2,
            bandwidth_kbps = 1000,
            inputs = {},
        },
    },
})

local rows = instance:list_status()
assert(type(rows) == "table" and type(rows[1]) == "table", "resource status missing")
assert(type(rows[1].health) == "table", "resource health status missing")
assert(rows[1].health.require_video == true, "require_video status mismatch")
assert(rows[1].health.require_audio == true, "require_audio status mismatch")
assert(rows[1].health.min_bitrate_kbps == 256, "min bitrate status mismatch")
assert(rows[1].health.failover_sec == 7, "failover status mismatch")
assert(rows[1].health.fail_checks == 3, "failure checks status mismatch")
assert(rows[1].health.reason == "warming", "initial health reason mismatch")

print("http_buffer_av_health_stats_unit: ok")
astra.exit()
