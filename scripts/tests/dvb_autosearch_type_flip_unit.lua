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
assert_true(cfg_default.allow_type_flip == true, "type flip should be enabled by default")
assert_equal(cfg_default.type_flip_wait_sec, 30, "type flip wait default should be 30 sec")

local cfg_override = dvb_autosearch_adapter_cfg({
    id = "a1",
    config = {
        auto_signal_search_enabled = true,
        auto_signal_type_flip_enabled = false,
        auto_signal_type_flip_wait_sec = 45,
    },
})
assert_true(cfg_override ~= nil, "adapter cfg override should be built")
assert_true(cfg_override.allow_type_flip == false, "type flip flag override should work")
assert_equal(cfg_override.type_flip_wait_sec, 45, "type flip wait override should work")

local saved_apply = dvb_autosearch_apply_adapter_config
dvb_autosearch_apply_adapter_config = function(_, cfg)
    return { id = "a1", config = cfg }
end

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
        type_flip_wait_sec = 30,
    },
    state = "running",
    candidates = {},
    candidate_index = 1,
}

local done = dvb_autosearch_step_task(task)
assert_true(done == false, "type-flip scheduling should not finish task")
assert_equal(task.phase, "type-flip-return", "task should switch to type-flip-return phase")
assert_true(task.type_flip_tried == true, "type flip should be marked as tried")
assert_true(task.prev_cfg and task.prev_cfg.type == "S2", "previous config must be saved")

task.wait_until = 0
done = dvb_autosearch_step_task(task)
assert_true(done == false, "type-flip return should move to confirm phase")
assert_equal(task.phase, "confirm", "task should move to confirm phase")
assert_true(task.applied_candidate and task.applied_candidate.name == "type-flip S2->S->S2",
    "candidate marker should be set")

dvb_autosearch_apply_adapter_config = saved_apply

log.info("[unit] dvb_autosearch_type_flip_unit ok")
astra.exit()
