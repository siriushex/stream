log.set({ debug = true })

local source = transmit({})
local instance = decrypt({
    upstream = source:stream(),
    name = "softcam key sequence stats",
    biss = "1122330044556600",
    key_guard = true,
    shift = 1,
})

local stats = instance:stats()
assert(type(stats.shift) == "table", "shift stats missing")
assert(stats.shift.ingress_seq == 0, "initial ingress sequence must be zero")
assert(stats.shift.egress_seq == 0, "initial egress sequence must be zero")
assert(type(stats.ca_streams) == "table" and type(stats.ca_streams[1]) == "table",
    "BISS CA stream stats missing")
assert(type(stats.ca_streams[1].accepted_key) == "table", "accepted key stats missing")
assert(stats.ca_streams[1].accepted_key.pending == false, "accepted key must not be pending")
assert(stats.ca_streams[1].accepted_key.apply_seq == 0, "initial apply sequence must be zero")

print("softcam_key_guard_sequence_stats_unit: ok")
astra.exit()
