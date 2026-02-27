log.set({ debug = true })

dofile("scripts/base.lua")
dofile("scripts/config.lua")
dofile("scripts/dvr.lua")

local function assert_true(value, message)
    if not value then
        error(message or "assert_true failed")
    end
end

assert_true(dvr.should_use_segment_lock(nil, "/tmp/a.lock") == false, "nil segment must not use lock")
assert_true(dvr.should_use_segment_lock({}, "") == false, "empty lock path must disable lock usage")
assert_true(dvr.should_use_segment_lock({ is_complete = true }, "/tmp/a.lock") == false, "complete segment must not use lock")
assert_true(dvr.should_use_segment_lock({ is_complete = 1 }, "/tmp/a.lock") == false, "numeric complete segment must not use lock")
assert_true(dvr.should_use_segment_lock({ is_complete = false }, "/tmp/a.lock") == true, "incomplete segment must use lock")
assert_true(dvr.should_use_segment_lock({ is_complete = 0 }, "/tmp/a.lock") == true, "numeric incomplete segment must use lock")
assert_true(dvr.should_force_skip_stalled_segment(nil, 30, 0) == false, "nil segment must not force skip")
assert_true(dvr.should_force_skip_stalled_segment({ is_complete = false }, 30, 0) == false,
    "incomplete segment must not force skip")
assert_true(dvr.should_force_skip_stalled_segment({ is_complete = true }, 10, 0) == false,
    "short elapsed must not force skip")
assert_true(dvr.should_force_skip_stalled_segment({ is_complete = true }, 30, 2) == false,
    "non-zero played progress must not force skip")
assert_true(dvr.should_force_skip_stalled_segment({ is_complete = true }, 30, 1) == true,
    "stalled complete segment must force skip")

log.info("[unit] dvr_segment_lock_usage_unit ok")
astra.exit()
