log.set({ debug = true })

dofile("scripts/base.lua")
dofile("scripts/config.lua")
dofile("scripts/api.lua")

local function assert_true(value, message)
    if not value then
        error(message or "assert_true failed")
    end
end

config = config or {}
config.get_setting = function(key)
    if key == "dvb_autosearch_queue_max" then
        return 32
    end
    if key == "dvb_autosearch_reenqueue_sec" then
        return 60
    end
    return nil
end

local ok1 = dvb_autosearch_enqueue("a1", "low_bitrate", {
    on_air_count = 5,
    cc_delta = 12,
    bitrate = 120,
})
local ok2 = dvb_autosearch_enqueue("a1", "cc_spike", {
    on_air_count = 8,
    cc_delta = 77,
    bitrate = 90,
})

assert_true(ok1 == true, "first enqueue must succeed")
assert_true(ok2 == false, "second enqueue for same adapter must dedup")

local payload = dvb_autosearch_status_payload()
local queue = payload and payload.queue or {}
assert_true(type(queue) == "table" and #queue == 1, "queue must contain single task for adapter")
assert_true(queue[1].reason == "cc_spike", "dedup should refresh reason/details")

local task = dvb_autosearch_dequeue()
assert_true(task ~= nil, "dequeue should return task")
local cooldown_block = dvb_autosearch_enqueue("a1", "retry_too_soon", {
    on_air_count = 3,
    cc_delta = 1,
    bitrate = 250,
})
assert_true(cooldown_block == false, "reenqueue cooldown must block immediate same-adapter task")

local forced = dvb_autosearch_enqueue("a1", "manual_force", {
    on_air_count = 3,
    cc_delta = 1,
    bitrate = 250,
}, { force = true })
assert_true(forced == true, "manual force enqueue must bypass cooldown")
assert_true(dvb_autosearch_dequeue() ~= nil, "forced item should be dequeued")

local q1 = dvb_autosearch_enqueue("a1", "repeat_adapter", {
    streams_on_air = 100,
    cc_delta = 50,
    avg_bitrate_kbps = 100,
    expected_bitrate_kbps = 500,
}, { force = true })
local q2 = dvb_autosearch_enqueue("a2", "other_adapter", {
    streams_on_air = 1,
    cc_delta = 1,
    avg_bitrate_kbps = 300,
    expected_bitrate_kbps = 350,
}, { force = true })
assert_true(q1 == true and q2 == true, "enqueue for fairness check failed")

local fairness_pick = dvb_autosearch_dequeue()
assert_true(fairness_pick ~= nil, "fairness dequeue failed")
assert_true(fairness_pick.adapter_id == "a2", "fairness must avoid consecutive same adapter when alternatives exist")

log.info("[unit] dvb_autosearch_queue_unit ok")
astra.exit()
