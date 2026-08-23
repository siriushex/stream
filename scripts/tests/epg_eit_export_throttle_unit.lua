log.set({ debug = true })

dofile("scripts/base.lua")
dofile("scripts/epg.lua")

local function assert_equal(actual, expected, msg)
    if actual ~= expected then
        error((msg or "value mismatch") .. ": expected=" .. tostring(expected) ..
            " actual=" .. tostring(actual))
    end
end

local function assert_true(cond, msg)
    if not cond then error(msg or "assert failed") end
end

local function from_hex(value)
    return (value:gsub("..", function(pair)
        return string.char(tonumber(pair, 16))
    end))
end

local section = from_hex(
    "50f072eac7c302040005000704502345ef5b1234560130008057" ..
    "4d1e6c69740815c5bd696e696f7311154469656e6f73206e61756a69656e6f73" ..
    "4e0e116c69740008152064616c69732e" ..
    "4e21016c6974001b1549c5a173616d75732061707261c5a1796d61732c207069726d61" ..
    "540210008d51dcd0"
)

local export_requests = 0
epg.request_export = function()
    export_requests = export_requests + 1
end

local ok, changed = epg.ingest_section("a5_60103", section, { now = 1787488400 })
assert_true(ok, "valid EIT section must be accepted")
assert_true(changed, "new EIT event must mark the registry dirty")
assert_equal(export_requests, 0, "EIT ingest must not export on every section")
assert_true(epg.registry_dirty == true, "changed EIT must mark registry dirty")

print("epg_eit_export_throttle_unit: ok")
astra.exit()
