log.set({ debug = true })

dofile("scripts/base.lua")
dofile("scripts/config.lua")
dofile("scripts/api.lua")

local function assert_true(value, message)
    if not value then
        error(message or "assert_true failed")
    end
end

local function assert_equal(actual, expected, message)
    if actual ~= expected then
        error((message or "assert_equal failed") .. ": expected=" .. tostring(expected) .. " actual=" .. tostring(actual))
    end
end

local cfg_default = dvb_autosearch_adapter_cfg({
    id = "a0",
    config = {
        auto_signal_search_enabled = true,
    },
})
assert_true(cfg_default ~= nil, "adapter cfg should be built")
assert_true(cfg_default.allow_type_flip == false, "type flip should be disabled by default")
assert_equal(cfg_default.type_flip_s2_hold_sec, 10, "type flip pre-hold default should be 10 sec")
assert_equal(cfg_default.type_flip_wait_sec, 20, "type flip wait default should be 20 sec")
assert_equal(cfg_default.type_flip_confirm_sec, 180, "type flip confirm default should be 180 sec")
assert_equal(cfg_default.type_flip_cc_window_sec, 60, "type flip cc window default should be 60 sec")
assert_equal(cfg_default.type_flip_cc_threshold, 120, "type flip cc threshold default should be 120")
assert_equal(cfg_default.type_flip_fault_window_sec, 60, "type flip fault window default should be 60 sec")
assert_equal(cfg_default.type_flip_no_data_threshold, 40, "type flip no_data threshold default should be 40")
assert_equal(cfg_default.type_flip_pes_threshold, 50, "type flip pes threshold default should be 50")

local cfg_override = dvb_autosearch_adapter_cfg({
    id = "a1",
    config = {
        auto_signal_search_enabled = true,
        auto_signal_type_flip_enabled = true,
        auto_signal_type_flip_wait_sec = 45,
    },
})
assert_true(cfg_override ~= nil, "adapter cfg override should be built")
assert_true(cfg_override.allow_type_flip == true, "type flip flag override should work")
assert_equal(cfg_override.type_flip_wait_sec, 45, "type flip wait override should work")

local saved_apply = dvb_autosearch_apply_adapter_config
dvb_autosearch_apply_adapter_config = function(_, cfg)
    return { id = "a1", config = cfg }
end

local saved_get_adapter = config.get_adapter
local saved_build_candidates = dvb_autosearch_build_candidates

local task = {
    adapter_id = "a1",
    row = {
        id = "a1",
        config = {
            adapter = 0,
            device = 0,
            type = "S2",
            tp = "12322:H:27500",
        },
    },
    cfg = {
        allow_type_flip = true,
        type_flip_s2_hold_sec = 10,
        type_flip_wait_sec = 20,
        type_flip_confirm_sec = 180,
        type_flip_cc_window_sec = 60,
        type_flip_cc_threshold = 50,
        type_flip_fault_window_sec = 60,
        type_flip_no_data_threshold = 40,
        type_flip_pes_threshold = 50,
    },
    state = "running",
    candidates = {},
    candidate_index = 1,
}

local done = dvb_autosearch_step_task(task)
assert_true(done == false, "type-flip scheduling should not finish task")
assert_equal(task.phase, "type-flip-pre-wait", "task should switch to type-flip-pre-wait phase")
assert_true(task.type_flip_tried == true, "type flip should be marked as tried")
assert_true(task.prev_cfg and task.prev_cfg.type == "S2", "previous config must be saved")

task.wait_until = 0
done = dvb_autosearch_step_task(task)
assert_true(done == false, "type-flip return should move to confirm phase")
assert_equal(task.phase, "type-flip-return", "task should switch to type-flip-return phase")

task.wait_until = 0
done = dvb_autosearch_step_task(task)
assert_true(done == false, "type-flip return should move to confirm phase")
assert_equal(task.phase, "confirm", "task should move to confirm phase")
assert_true(task.applied_candidate and task.applied_candidate.name == "type-flip S2->S->S2",
    "candidate marker should be set")
assert_true((tonumber(task.wait_until) or 0) >= (os.time() + 170), "confirm hold should be close to 180 sec")

config.get_adapter = function(id)
    return {
        id = id,
        enabled = 1,
        config = {
            adapter = 0,
            device = 0,
            type = "S2",
            tp = "12322:H:27500",
        },
    }
end

dvb_autosearch_build_candidates = function(_)
    return {}, {
        enabled = false,
        allow_type_flip = true,
        type_flip_s2_hold_sec = 10,
        type_flip_wait_sec = 20,
        type_flip_confirm_sec = 180,
        type_flip_cc_window_sec = 60,
        type_flip_cc_threshold = 50,
        type_flip_fault_window_sec = 60,
        type_flip_no_data_threshold = 40,
        type_flip_pes_threshold = 50,
        probe_sec = 30,
        confirm_sec = 60,
        bitrate_min_kbps = 500,
    }
end

local start_task_with_flip = {
    adapter_id = "a2",
    type_flip_only = true,
}
dvb_autosearch_start_task(start_task_with_flip)
assert_equal(start_task_with_flip.state, "running", "start_task should continue with type-flip when candidates are missing")
assert_true(start_task_with_flip.no_candidate_profiles == true, "missing candidates should be marked")

dvb_autosearch_build_candidates = function(_)
    return {}, {
        allow_type_flip = false,
    }
end

local start_task_without_flip = {
    adapter_id = "a3",
}
dvb_autosearch_start_task(start_task_without_flip)
assert_equal(start_task_without_flip.state, "failed", "start_task must fail if candidates are missing and type-flip is disabled")

dvb_autosearch_apply_adapter_config = saved_apply
dvb_autosearch_build_candidates = saved_build_candidates
config.get_adapter = saved_get_adapter

log.info("[unit] dvb_autosearch_type_flip_unit ok")
astra.exit()
