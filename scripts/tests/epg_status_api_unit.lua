log.set({ debug = true })

dofile("scripts/base.lua")
dofile("scripts/epg.lua")

local function assert_true(cond, msg)
    if not cond then error(msg or "assert failed") end
end

config = {
    list_streams = function()
        return {
            {
                id = "a5_60103",
                enabled = 1,
                config = { epg_export = "file:///opt/epg/lnk.xml" },
            },
            {
                id = "no_epg",
                enabled = 1,
                config = {},
            },
        }
    end,
}
epg.stream_status.a5_60103 = {
    collector = "active",
    last_eit_ts = 123,
    event_count = 42,
    last_write_ts = 120,
}

local payload = epg.get_status()
assert_true(payload.configured == 1, "configured count mismatch")
assert_true(payload.event_count == 42, "event count mismatch")
assert_true(#payload.streams == 1, "unexpected status rows")
assert_true(payload.streams[1].id == "a5_60103", "stream id missing")
assert_true(payload.streams[1].destination == "/opt/epg/lnk.xml", "destination missing")
assert_true(payload.streams[1].legacy == true, "legacy marker missing")
assert_true(payload.streams[1].collector == "active", "collector state missing")

local api_file = assert(io.open("scripts/api.lua", "rb"))
local api_source = api_file:read("*a")
api_file:close()
assert_true(api_source:find('/api/v1/epg/status', 1, true) ~= nil, "EPG API route missing")

print("epg_status_api_unit: ok")
astra.exit()
