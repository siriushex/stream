log.set({ debug = true })

dofile("scripts/base.lua")
dofile("scripts/config.lua")
dofile("scripts/api.lua")

local function assert_true(value, message)
    if not value then
        error(message or "assert_true failed")
    end
end

local adapter_ok = "tf_cc_ok"
for _, point in ipairs({
    { cc = 0, pes = 0 },
    { cc = 40, pes = 10 },
    { cc = 80, pes = 20 },
    { cc = 130, pes = 25 },
}) do
    dvb_autosearch_push_history({
        [adapter_ok] = {
            streams = 20,
            streams_on_air = 20,
            bitrate_kbps = 20000,
            cc_total = point.cc,
            pes_total = point.pes,
            no_data_fault_events = 0,
        },
    })
end

local degraded_ok, reason_ok, details_ok = dvb_autosearch_degradation(adapter_ok, {
    id = adapter_ok,
    config = {
        auto_signal_search_enabled = false,
        auto_signal_type_flip_enabled = true,
    },
}, {
    cc_only = true,
    window_sec = 60,
    cc_threshold = 120,
})

assert_true(degraded_ok == true, "type-flip cc-only degradation must trigger")
assert_true(reason_ok == "cc", "reason must be cc")
assert_true(type(details_ok) == "table" and (tonumber(details_ok.cc_delta) or 0) > 120,
    "cc delta must exceed threshold")

local adapter_low_cc = "tf_cc_low"
for _, point in ipairs({
    { cc = 0, pes = 0 },
    { cc = 30, pes = 200 },
    { cc = 70, pes = 450 },
}) do
    dvb_autosearch_push_history({
        [adapter_low_cc] = {
            streams = 20,
            streams_on_air = 20,
            bitrate_kbps = 20000,
            cc_total = point.cc,
            pes_total = point.pes,
            no_data_fault_events = 0,
        },
    })
end

local degraded_low_cc = dvb_autosearch_degradation(adapter_low_cc, {
    id = adapter_low_cc,
    config = {
        auto_signal_search_enabled = false,
        auto_signal_type_flip_enabled = true,
    },
}, {
    cc_only = true,
    window_sec = 60,
    cc_threshold = 120,
})
assert_true(degraded_low_cc == false, "degradation must not trigger when CC is below threshold")

local saved_confirm = dvb_autosearch_confirm_degradation
dvb_autosearch_confirm_degradation = function()
    return false, "ok", {}
end

local task = {
    adapter_id = adapter_ok,
    row = {
        id = adapter_ok,
        config = {
            adapter = 0,
            device = 0,
            type = "S2",
        },
    },
    cfg = {
        type_flip_cc_threshold = 120,
    },
    state = "running",
    phase = "confirm",
    wait_until = 0,
    switch_applied_ts = os.time() - 1,
    type_flip_only = true,
    type_flip_tried = true,
    applied_candidate = { name = "type-flip S2->S->S2" },
}
local done = dvb_autosearch_step_task(task)
assert_true(done == true and task.state == "done", "type-flip confirm should finish task")

local degraded_after_reset, reason_after_reset = dvb_autosearch_degradation(adapter_ok, {
    id = adapter_ok,
    config = {
        auto_signal_search_enabled = false,
        auto_signal_type_flip_enabled = true,
    },
}, {
    cc_only = true,
    window_sec = 60,
    cc_threshold = 120,
})
assert_true(degraded_after_reset == false, "after type-flip cycle counters must be reset")
assert_true(reason_after_reset == "insufficient-history" or reason_after_reset == "insufficient-window",
    "after reset reason should indicate missing history window")

dvb_autosearch_confirm_degradation = saved_confirm

log.info("[unit] dvb_autosearch_type_flip_nodata_pes_unit ok")
astra.exit()
