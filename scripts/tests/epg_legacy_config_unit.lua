log.set({ debug = true })

dofile("scripts/base.lua")
dofile("scripts/epg.lua")

local function assert_equal(actual, expected, msg)
    if actual ~= expected then
        error((msg or "value mismatch") .. ": expected=" .. tostring(expected) ..
            " actual=" .. tostring(actual))
    end
end

local legacy = epg.resolve_stream_config({
    id = "a5_60103",
    config = {
        name = "LNK",
        epg_export = "file:///opt/epg/lnk.xml",
        codepage = "iso-8859-4",
    },
})
assert_equal(legacy.xmltv_id, "a5_60103", "legacy id")
assert_equal(legacy.destination, "/opt/epg/lnk.xml", "legacy file URI")
assert_equal(legacy.format, "xmltv", "legacy format")
assert_equal(legacy.codepage, "iso-8859-4", "legacy codepage")
assert_equal(legacy.legacy, true, "legacy marker")

local absolute = epg.resolve_stream_config({
    id = "absolute",
    config = { epg_export = "/opt/epg/absolute.xml" },
})
assert_equal(absolute.destination, "/opt/epg/absolute.xml", "absolute legacy path")

local modern = epg.resolve_stream_config({
    id = "modern-id",
    config = {
        epg_export = "file:///opt/epg/legacy.xml",
        epg = {
            xmltv_id = "modern.xmltv",
            destination = "/var/lib/stream/modern.xml",
            format = "json",
            codepage = "utf-8",
        },
    },
})
assert_equal(modern.xmltv_id, "modern.xmltv", "modern id precedence")
assert_equal(modern.destination, "/var/lib/stream/modern.xml", "modern destination precedence")
assert_equal(modern.format, "json", "modern format precedence")
assert_equal(modern.legacy, false, "modern marker")

assert_equal(epg.resolve_stream_config({ id = "bad", config = { epg_export = "http://bad/epg.xml" } }),
    nil, "unsupported legacy URI")
assert_equal(epg.resolve_stream_config({ id = "empty", config = {} }), nil, "missing config")
assert_equal(epg.resolve_stream_config({ id = "disabled", config = { epg_export = false } }),
    nil, "disabled legacy config")

config = {
    get_setting = function() return nil end,
    list_streams = function()
        return {
            { id = "legacy", enabled = 1, config = { epg_export = "file:///opt/epg/legacy.xml" } },
        }
    end,
}
assert_equal(epg.resolve_export_interval(), 60, "safe legacy default interval")
config.list_streams = function() return {} end
assert_equal(epg.resolve_export_interval(), 0, "no EPG interval without configured streams")

print("epg_legacy_config_unit: ok")
astra.exit()
