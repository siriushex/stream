log.set({ debug = true })

dofile("scripts/base.lua")

local function assert_true(value, message)
    if not value then
        error(message or "assert_true failed")
    end
end

local original_http_request = http_request
local original_timer = timer
local original_transmit = transmit
local requests = {}

timer = function(opts)
    return {
        opts = opts,
        close = function() end,
    }
end

transmit = function(options)
    return {
        __options = options or {},
        set_upstream = function(self, stream)
            self.__upstream = stream
        end,
    }
end

http_request = function(opts)
    local req = {
        opts = opts,
        close = function() end,
        stream = function()
            return "unit-stream"
        end,
    }
    requests[#requests + 1] = req
    return req
end

local conf = parse_url("http://origin.example/live.m3u8")
conf.name = "hls-active-segment-dedup-unit"
conf.hls_segment_retries = 1

local module = init_input_module.hls(conf)
local instance_id = conf.host .. ":" .. conf.port .. conf.path
local instance = hls_input_instance_list[instance_id]
assert_true(module ~= nil and instance ~= nil, "HLS input must start")
assert_true(#requests == 1, "initial playlist request missing")

local playlist = table.concat({
    "#EXTM3U",
    "#EXT-X-TARGETDURATION:2",
    "#EXT-X-MEDIA-SEQUENCE:100",
    "#EXTINF:2.0,",
    "segment100.ts",
    "",
}, "\n")

requests[1].opts.callback(requests[1], { code = 200, content = playlist })
assert_true(#requests == 2, "segment request missing")
requests[2].opts.callback(requests[2], {
    code = 200,
    headers = { ["content-length"] = "1000000" },
})

assert_true(instance.active_seq == 100, "segment 100 must be active")
assert_true(instance.queued[100] == true, "active segment must remain reserved")
assert_true(#instance.queue == 0, "active segment must not remain queued")

instance.request_playlist()
assert_true(#requests == 3, "playlist refresh request missing")
requests[3].opts.callback(requests[3], { code = 200, content = playlist })
assert_true(instance.active_seq == 100, "refresh must not replace active segment")
assert_true(instance.queued[100] == true, "refresh must preserve active reservation")
assert_true(#instance.queue == 0, "refresh must not enqueue active segment")

requests[2].opts.callback(requests[2], nil)
assert_true(instance.last_seq == 100, "completed segment must advance sequence")
assert_true(instance.active_seq == nil, "completed segment must release active state")
assert_true(instance.queued[100] == nil, "completed segment must release reservation")

kill_input_module.hls(module, conf)
http_request = original_http_request
timer = original_timer
transmit = original_transmit

print("hls_active_segment_dedup_unit: ok")
astra.exit()
