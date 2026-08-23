log.set({ debug = true })

dofile("scripts/base.lua")

local hls_port = tonumber(os.getenv("HLS_SOURCE_PORT")) or 19201
local udp_port = tonumber(os.getenv("HLS_OUTPUT_PORT")) or 19202
local status_path = os.getenv("HLS_STATUS_PATH") or "/tmp/native-hls-playout-status.json"

local conf = parse_url("http://127.0.0.1:" .. tostring(hls_port) .. "/live.m3u8")
conf.name = "native-hls-playout-canary"
conf.format = "hls"
conf.playout = true
conf.playout_mode = "auto"
conf.playout_min_fill_ms = 500
conf.playout_target_fill_ms = 1000
conf.playout_max_buffer_mb = 16
conf.playout_null_stuffing = true

local input = init_input(conf)
assert(input and input.tail and input.playout, "native HLS playout input failed")
local output = udp_output({
    upstream = input.tail:stream(),
    addr = "127.0.0.1",
    port = udp_port,
})
assert(output ~= nil, "UDP output failed")
native_hls_canary_output = output

timer({
    interval = 1,
    callback = function()
        local stats = input.playout:stats() or {}
        local file = io.open(status_path .. ".tmp", "wb")
        if file then
            file:write(json.encode(stats))
            file:close()
            os.rename(status_path .. ".tmp", status_path)
        end
    end,
})
