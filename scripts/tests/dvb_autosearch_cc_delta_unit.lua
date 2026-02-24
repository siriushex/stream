log.set({ debug = true })

dofile("scripts/base.lua")
dofile("scripts/config.lua")
dofile("scripts/api.lua")

local function assert_true(value, message)
    if not value then
        error(message or "assert_true failed")
    end
end

local adapter_id = "a-cc"
dvb_autosearch_push_history({
    [adapter_id] = { streams = 4, streams_on_air = 4, bitrate_kbps = 8000, cc_total = 8, pes_total = 0 },
})
dvb_autosearch_push_history({
    [adapter_id] = { streams = 4, streams_on_air = 4, bitrate_kbps = 7900, cc_total = 14, pes_total = 0 },
})
-- Counter reset (e.g. adapter/input restart), then grows again.
dvb_autosearch_push_history({
    [adapter_id] = { streams = 4, streams_on_air = 4, bitrate_kbps = 7800, cc_total = 3, pes_total = 0 },
})
dvb_autosearch_push_history({
    [adapter_id] = { streams = 4, streams_on_air = 4, bitrate_kbps = 7700, cc_total = 20, pes_total = 0 },
})

local degraded, reason, details = dvb_autosearch_degradation(adapter_id, {
    id = adapter_id,
    config = {
        auto_signal_search_enabled = true,
        auto_signal_window_sec = 60,
        auto_signal_min_streams = 1,
        auto_signal_bitrate_mode = "absolute",
        auto_signal_bitrate_min_kbps = 1,
        auto_signal_cc_delta_threshold = 20,
    },
})

assert_true(degraded == true, "degradation should be detected with reset-tolerant CC delta")
assert_true(reason == "cc", "degradation reason should be cc")
assert_true(type(details) == "table" and (tonumber(details.cc_delta) or 0) >= 20,
    "effective cc_delta should include post-reset increments")

log.info("[unit] dvb_autosearch_cc_delta_unit ok")
astra.exit()
