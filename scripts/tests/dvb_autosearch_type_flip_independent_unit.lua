log.set({ debug = true })

dofile("scripts/base.lua")
dofile("scripts/config.lua")
dofile("scripts/api.lua")

local function assert_true(value, message)
    if not value then
        error(message or "assert_true failed")
    end
end

local saved_enabled = dvb_autosearch_enabled
local saved_lock_ok = dvb_autosearch_lock_ok
local saved_collect_runtime = dvb_autosearch_collect_runtime
local saved_push_history = dvb_autosearch_push_history
local saved_degradation = dvb_autosearch_degradation
local saved_enqueue = dvb_autosearch_enqueue
local saved_dequeue = dvb_autosearch_dequeue
local saved_get_adapter = config.get_adapter
local saved_list_adapters = config.list_adapters
local saved_started_at = runtime and runtime.started_at or nil

dvb_autosearch_enabled = function()
    return true
end

dvb_autosearch_lock_ok = function()
    return true
end

dvb_autosearch_collect_runtime = function()
    return {}
end

dvb_autosearch_push_history = function(_)
end

local enqueue_called = false
local enqueue_opts = nil
local enqueue_reason = nil
local degradation_opts = nil

dvb_autosearch_degradation = function(_, _row, opts)
    degradation_opts = opts or {}
    return true, "cc", {
        streams = 2,
        streams_on_air = 2,
        avg_bitrate_kbps = 1200,
        cc_delta = 140,
    }
end

dvb_autosearch_enqueue = function(_adapter_id, reason, _details, opts)
    enqueue_called = true
    enqueue_opts = opts or {}
    enqueue_reason = reason
    return true
end

dvb_autosearch_dequeue = function()
    return nil
end

config.list_adapters = function()
    return {
        {
            id = "a1",
            enabled = 1,
            config = {
                adapter = 0,
                device = 0,
                type = "S2",
                auto_signal_search_enabled = false,
                auto_signal_type_flip_enabled = true,
                auto_signal_cc_delta_threshold = 50,
                auto_signal_min_streams = 1,
            },
        },
    }
end

config.get_adapter = function(id)
    if id == "a1" then
        return {
            id = "a1",
            enabled = 1,
            config = {
                adapter = 0,
                device = 0,
                type = "S2",
                auto_signal_search_enabled = false,
                auto_signal_type_flip_enabled = true,
            },
        }
    end
    return nil
end

runtime = runtime or {}
runtime.started_at = os.time() - 1000

dvb_autosearch_tick()

assert_true(enqueue_called == true, "tick should enqueue task for standalone type-flip mode")
assert_true(enqueue_reason == "cc", "standalone type-flip mode should trigger on cc reason")
assert_true(enqueue_opts and enqueue_opts.type_flip_only == true,
    "standalone type-flip enqueue should set type_flip_only")
assert_true(degradation_opts and degradation_opts.cc_only == true,
    "standalone type-flip degradation should be cc-only")
assert_true(tonumber(degradation_opts and degradation_opts.window_sec) == 60,
    "standalone type-flip degradation should use 60 sec window")
assert_true(tonumber(degradation_opts and degradation_opts.cc_threshold) == 120,
    "standalone type-flip degradation should use CC threshold 120")

dvb_autosearch_enabled = saved_enabled
dvb_autosearch_lock_ok = saved_lock_ok
dvb_autosearch_collect_runtime = saved_collect_runtime
dvb_autosearch_push_history = saved_push_history
dvb_autosearch_degradation = saved_degradation
dvb_autosearch_enqueue = saved_enqueue
dvb_autosearch_dequeue = saved_dequeue
config.get_adapter = saved_get_adapter
config.list_adapters = saved_list_adapters
runtime.started_at = saved_started_at

log.info("[unit] dvb_autosearch_type_flip_independent_unit ok")
astra.exit()
