log.set({ debug = true })

local source = transmit({})
local instance = playout({
    upstream = source:stream(),
    playout_mode = "auto",
    playout_min_fill_ms = 500,
})

local stats = instance:stats()
assert(type(stats.media_kbps) == "number", "media clock bitrate stats missing")
assert(type(stats.arrival_kbps) == "number", "arrival bitrate stats missing")
assert(stats.prebuffering == true, "playout must begin in prebuffering state")

print("playout_media_clock_stats_unit: ok")
astra.exit()
