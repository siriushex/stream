log.set({ debug = true })

dofile("scripts/base.lua")

local function assert_true(cond, msg)
    if not cond then error(msg or "assert failed") end
end

local file = assert(io.open("scripts/stream.lua", "rb"))
local source = file:read("*a")
file:close()

assert_true(source:find("input_data.epg_collector = eit_collect", 1, true) ~= nil,
    "EPG collector is not attached to stream inputs")
assert_true(source:find("channel_data.active_input_id == input_id", 1, true) ~= nil,
    "EPG callback is not restricted to the active input")
assert_true(source:find("epg.resolve_stream_config", 1, true) ~= nil,
    "legacy/modern EPG resolver is not used by runtime")
assert_true(source:find("channel_data.clients = 1", 1, true) ~= nil,
    "EPG streams are not kept active without HTTP viewers")
assert_true(source:find("input_data.epg_collector = nil", 1, true) ~= nil,
    "EPG collector is not released during input teardown")

print("epg_runtime_attach_unit: ok")
astra.exit()
