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

local decoded = iso8859.decode(from_hex("15c5bd696e696f73"))
assert_equal(decoded, "Žinios", "DVB UTF-8 decoding")

local parsed, err = epg.parse_eit_section(section)
assert_true(parsed ~= nil, err)
assert_equal(parsed.table_id, 0x50, "table id")
assert_equal(parsed.service_id, 60103, "service id")
assert_equal(parsed.version, 1, "version")
assert_equal(parsed.section_number, 2, "section number")
assert_equal(parsed.last_section_number, 4, "last section number")
assert_equal(parsed.transport_stream_id, 5, "transport stream id")
assert_equal(parsed.original_network_id, 7, "original network id")
assert_equal(#parsed.events, 1, "event count")

local event = parsed.events[1]
assert_equal(event.event_id, 0x2345, "event id")
assert_equal(event.start, 1787488496, "UTC start")
assert_equal(event.duration, 5400, "duration")
assert_equal(event.stop, 1787493896, "stop")
assert_equal(event.running_status, 4, "running status")
assert_equal(event.lang, "lit", "language")
assert_equal(event.title, "Žinios", "title")
assert_equal(event.subtitle, "Dienos naujienos", "short text")
assert_equal(event.description, "Išsamus aprašymas, pirma dalis.", "ordered extended text")
assert_equal(event.categories[1].level1, 1, "content level 1")
assert_equal(event.categories[1].level2, 0, "content level 2")

local malformed, malformed_err = epg.parse_eit_section(section:sub(1, 40))
assert_equal(malformed, nil, "truncated section")
assert_true(type(malformed_err) == "string" and malformed_err ~= "", "truncated error")

print("epg_eit_parser_unit: ok")
astra.exit()
