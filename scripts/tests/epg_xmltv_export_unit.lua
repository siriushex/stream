log.set({ debug = true })

dofile("scripts/base.lua")
dofile("scripts/epg.lua")

local function assert_true(cond, msg)
    if not cond then error(msg or "assert failed") end
end

local function from_hex(value)
    return (value:gsub("..", function(pair)
        return string.char(tonumber(pair, 16))
    end))
end

local function read_file(path)
    local file = assert(io.open(path, "rb"))
    local value = file:read("*a")
    file:close()
    return value
end

local tmp = "/tmp/epg_xmltv_export_unit"
os.execute("rm -rf " .. tmp .. " >/dev/null 2>&1 || true")
os.execute("mkdir -p " .. tmp)
local destination = tmp .. "/guide.xml"

config = {
    data_dir = tmp,
    list_streams = function()
        return {
            {
                id = "a5_60103",
                enabled = 1,
                config = {
                    id = "a5_60103",
                    name = "LNK & HD",
                    epg_export = "file://" .. destination,
                },
            },
        }
    end,
}

local section = from_hex(
    "50f072eac7c302040005000704502345ef5b1234560130008057" ..
    "4d1e6c69740815c5bd696e696f7311154469656e6f73206e61756a69656e6f73" ..
    "4e0e116c69740008152064616c69732e" ..
    "4e21016c6974001b1549c5a173616d75732061707261c5a1796d61732c207069726d61" ..
    "540210008d51dcd0"
)

local ok, changed = epg.ingest_section("a5_60103", section, {
    now = 1787488400,
    defer_export = true,
})
assert_true(ok == true and changed == true, "section was not ingested")
for _, event in pairs(epg.registry["a5_60103"] or {}) do
    -- Some broadcasters mark DVB text as UTF-8 (0x15) but still put a
    -- Windows/ISO-8859 byte in it. The XMLTV writer must repair that byte.
    event.title = "Atl" .. string.char(0xE9) .. "tico"
end
assert_true(epg.export_all("unit") == true, "export did not succeed")

local xml = read_file(destination)
assert_true(xml:find('<channel id="a5_60103">', 1, true) ~= nil, "channel missing")
assert_true(xml:find('LNK &amp; HD', 1, true) ~= nil, "channel XML escaping missing")
assert_true(xml:find('<programme ', 1, true) ~= nil, "programme missing")
assert_true(xml:find('channel="a5_60103"', 1, true) ~= nil, "programme channel missing")
assert_true(xml:find('<title lang="lit">Atlético</title>', 1, true) ~= nil, "invalid UTF-8 was not repaired")
assert_true(xml:find(string.char(0xE9), 1, true) == nil, "raw ISO-8859 byte leaked into UTF-8 XML")
assert_true(xml:find('<sub-title lang="lit">Dienos naujienos</sub-title>', 1, true) ~= nil,
    "subtitle missing")
assert_true(xml:find('<desc lang="lit">Išsamus aprašymas, pirma dalis.</desc>', 1, true) ~= nil,
    "description missing")
assert_true(xml:find('<category>1.0</category>', 1, true) ~= nil, "category missing")

local sentinel = "previous-valid-guide"
local file = assert(io.open(destination, "wb"))
file:write(sentinel)
file:close()
epg.reset_registry()
assert_true(epg.export_all("empty") == false, "empty export should be skipped")
assert_true(read_file(destination) == sentinel, "empty export overwrote the previous valid file")

print("epg_xmltv_export_unit: ok")
astra.exit()
