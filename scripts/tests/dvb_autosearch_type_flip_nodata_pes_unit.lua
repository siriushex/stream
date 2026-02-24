log.set({ debug = true })

dofile("scripts/base.lua")
dofile("scripts/config.lua")
dofile("scripts/api.lua")

local function assert_true(value, message)
    if not value then
        error(message or "assert_true failed")
    end
end

local adapter_ok = "tf_np_ok"
for _ = 1, 5 do
    dvb_autosearch_push_history({
        [adapter_ok] = {
            streams = 20,
            streams_on_air = 20,
            bitrate_kbps = 20000,
            cc_total = 0,
            pes_total = 80,
            no_data_fault_events = 11,
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
    no_data_pes_only = true,
    window_sec = 60,
    no_data_threshold = 40,
    pes_threshold = 40,
})

assert_true(degraded_ok == true, "type-flip no_data+pes degradation must trigger")
assert_true(reason_ok == "no_data_pes", "reason must be no_data_pes")
assert_true(type(details_ok) == "table" and (tonumber(details_ok.no_data_fault_delta) or 0) > 40,
    "no_data delta must exceed threshold")
assert_true((tonumber(details_ok.pes_peak_sum) or 0) > 40, "pes peak sum must exceed threshold")

local adapter_no_pes = "tf_np_low_pes"
for _ = 1, 5 do
    dvb_autosearch_push_history({
        [adapter_no_pes] = {
            streams = 20,
            streams_on_air = 20,
            bitrate_kbps = 20000,
            cc_total = 0,
            pes_total = 20,
            no_data_fault_events = 12,
        },
    })
end

local degraded_no_pes = dvb_autosearch_degradation(adapter_no_pes, {
    id = adapter_no_pes,
    config = {
        auto_signal_search_enabled = false,
        auto_signal_type_flip_enabled = true,
    },
}, {
    no_data_pes_only = true,
    window_sec = 60,
    no_data_threshold = 40,
    pes_threshold = 40,
})
assert_true(degraded_no_pes == false, "degradation must not trigger when PES is below threshold")

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
        type_flip_fault_window_sec = 60,
        type_flip_no_data_threshold = 40,
        type_flip_pes_threshold = 40,
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
    no_data_pes_only = true,
    window_sec = 60,
    no_data_threshold = 40,
    pes_threshold = 40,
})
assert_true(degraded_after_reset == false, "after type-flip cycle counters must be reset")
assert_true(reason_after_reset == "insufficient-history" or reason_after_reset == "insufficient-window",
    "after reset reason should indicate missing history window")

dvb_autosearch_confirm_degradation = saved_confirm

log.info("[unit] dvb_autosearch_type_flip_nodata_pes_unit ok")
astra.exit()

