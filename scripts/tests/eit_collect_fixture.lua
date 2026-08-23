log.set({ debug = true })

dofile("scripts/base.lua")

local function assert_true(cond, msg)
    if not cond then error(msg or "assert failed") end
end

local function from_hex(value)
    return (value:gsub("..", function(pair)
        return string.char(tonumber(pair, 16))
    end))
end

local function packetize(section, cc)
    assert_true(#section <= 183, "single-packet fixture overflow")
    return string.char(0x47, 0x40, 0x12, 0x10 + (cc % 16), 0x00)
        .. section .. string.rep(string.char(0xFF), 183 - #section)
end

local function pcr_packet(value, cc)
    local base = math.floor(value / 300)
    local ext = value % 300
    local b6 = math.floor(base / 2 ^ 25) % 256
    local b7 = math.floor(base / 2 ^ 17) % 256
    local b8 = math.floor(base / 2 ^ 9) % 256
    local b9 = math.floor(base / 2) % 256
    local b10 = (base % 2) * 128 + 0x7E + math.floor(ext / 256)
    local b11 = ext % 256
    return string.char(0x47, 0x00, 0x64, 0x20 + (cc % 16), 0x07, 0x10,
        b6, b7, b8, b9, b10, b11) .. string.rep(string.char(0xFF), 176)
end

local null_packet = string.char(0x47, 0x1F, 0xFF, 0x10) .. string.rep(string.char(0xFF), 184)

local actual = from_hex("4ef01beac7c1000000010001004e1234ede41234560100008000a769cd46")
local other_ts = from_hex("4ff01beac7c1000000010001004f1234ede41234560100008000afde3809")
local other_service = from_hex("4ef01beac8c1000000010001004e1234ede41234560100008000f6341e63")

local tmp = "/tmp/eit_collect_fixture.ts"
local file = assert(io.open(tmp, "wb"))
file:write(null_packet)
file:write(pcr_packet(0, 0))
file:write(packetize(actual, 0))
file:write(packetize(actual, 1)) -- duplicate section
file:write(packetize(other_ts, 2)) -- other-TS present/following
file:write(packetize(other_service, 3)) -- other service
file:write(pcr_packet(2700000, 1))
file:write(null_packet)
file:write(pcr_packet(5400000, 2))
file:close()

local callbacks = 0
local source
local collector
source = file_input({
    filename = tmp,
    callback = function()
        assert_true(callbacks == 1, "expected one deduplicated actual-service section, got " .. callbacks)
        print("eit_collect_fixture: ok")
        astra.exit()
    end,
})
collector = eit_collect({
    upstream = source:stream(),
    service_id = 60103,
    callback = function(section)
        assert_true(type(section) == "string" and #section >= 18, "invalid section callback")
        callbacks = callbacks + 1
    end,
})
