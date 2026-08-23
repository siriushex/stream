log.set({ debug = true })

local primary_port = tonumber(os.getenv("BUFFER_PRIMARY_PORT")) or 19101
local backup_port = tonumber(os.getenv("BUFFER_BACKUP_PORT")) or 19102
local output_port = tonumber(os.getenv("BUFFER_OUTPUT_PORT")) or 19109
local status_path = os.getenv("BUFFER_STATUS_PATH") or "/tmp/buffer-av-health-status.json"

local instance = http_buffer({})
instance:apply_config({
    settings = {
        enabled = true,
        listen_host = "127.0.0.1",
        listen_port = output_port,
        max_clients_total = 4,
        client_read_timeout_sec = 5,
    },
    allow = {
        { id = "local", kind = "allow", value = "127.0.0.1" },
    },
    resources = {
        {
            id = "av-health-canary",
            name = "A/V Health Canary",
            path = "/canary",
            enable = true,
            backup_type = "active",
            no_data_timeout_sec = 3,
            backup_start_delay_sec = 0,
            backup_return_delay_sec = 5,
            backup_probe_interval_sec = 1,
            health_require_video = true,
            health_require_audio = true,
            health_min_bitrate_kbps = 128,
            health_failover_sec = 3,
            health_fail_checks = 2,
            buffering_sec = 4,
            bandwidth_kbps = 1200,
            client_start_offset_sec = 0,
            max_client_lag_ms = 3000,
            smart_start_enabled = false,
            ts_resync_enabled = true,
            ts_drop_corrupt_enabled = true,
            ts_rewrite_cc_enabled = false,
            pacing_mode = "none",
            inputs = {
                {
                    id = "primary",
                    url = "http://127.0.0.1:" .. tostring(primary_port) .. "/primary.ts",
                    enable = true,
                    priority = 0,
                },
                {
                    id = "backup",
                    url = "http://127.0.0.1:" .. tostring(backup_port) .. "/backup.ts",
                    enable = true,
                    priority = 1,
                },
            },
        },
    },
})

timer({
    interval = 1,
    callback = function()
        local status = instance:get_status("av-health-canary") or {}
        local file = io.open(status_path .. ".tmp", "wb")
        if file then
            file:write(json.encode(status))
            file:close()
            os.rename(status_path .. ".tmp", status_path)
        end
    end,
})
