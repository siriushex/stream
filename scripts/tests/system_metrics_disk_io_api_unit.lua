log.set({ debug = true })

dofile("scripts/base.lua")
dofile("scripts/config.lua")
dofile("scripts/api.lua")

local function assert_true(v, msg)
    if not v then
        error(msg or "assert")
    end
end

config = config or {}
config.get_setting = function(key)
    if key == "http_auth_enabled" then
        return false
    end
    if key == "observability_enabled" then
        return true
    end
    return nil
end
config.get_user_by_username = function(username)
    if username == "admin" then
        return { id = 1, username = "admin", is_admin = 1 }
    end
    return nil
end
config.get_user_by_id = function(id)
    if tonumber(id) == 1 then
        return { id = 1, username = "admin", is_admin = 1 }
    end
    return nil
end

system_metrics = {
    state = {
        rollup_enabled = true,
        rollup_interval_sec = 60,
        retention_sec = 3600,
        retention_source = "setting",
    },
    get_timeseries = function(_range)
        return {
            rollup = true,
            items = {
                {
                    t_ms = 1700000000000,
                    cpu_usage = 0.42,
                    mem_used_percent = 58.5,
                    disk_used_percent = 77.1,
                    net = {
                        eth0 = { rx_bps = 12345, tx_bps = 23456 },
                    },
                    disk_io = {
                        sda = { read_bps = 34567, write_bps = 45678 },
                    },
                },
            },
        }
    end,
}

local sent = nil
local server = {
    send = function(_, _, payload)
        sent = payload
    end,
}
local client = {}

api.handle_request(server, client, {
    method = "GET",
    path = "/api/v1/observability/system/timeseries",
    addr = "127.0.0.1",
    headers = {},
    query = { range = "1h" },
})

assert_true(sent ~= nil, "expected response")
assert_true(tonumber(sent.code) == 200, "expected 200")
local ok, payload = pcall(json.decode, sent.content or "{}")
assert_true(ok and type(payload) == "table", "expected json payload")
assert_true(type(payload.timeseries) == "table", "expected timeseries")

local read_series = payload.timeseries.disk_read_bps
local write_series = payload.timeseries.disk_write_bps
assert_true(type(read_series) == "table", "expected disk_read_bps map")
assert_true(type(write_series) == "table", "expected disk_write_bps map")
assert_true(type(read_series.sda) == "table" and #read_series.sda == 1, "expected one read point for sda")
assert_true(type(write_series.sda) == "table" and #write_series.sda == 1, "expected one write point for sda")
assert_true(tonumber(read_series.sda[1][2]) == 34567, "unexpected read_bps value")
assert_true(tonumber(write_series.sda[1][2]) == 45678, "unexpected write_bps value")

print("system_metrics_disk_io_api_unit: ok")
astra.exit()
