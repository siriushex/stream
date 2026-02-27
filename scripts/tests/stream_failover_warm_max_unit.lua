log.set({ debug = true })

dofile("scripts/base.lua")
dofile("scripts/stream.lua")

local function assert_true(value, message)
    if not value then
        error(message or "assert_true failed")
    end
end

local function assert_list_eq(actual, expected, label)
    assert_true(type(actual) == "table", (label or "list") .. ": actual is not table")
    assert_true(type(expected) == "table", (label or "list") .. ": expected is not table")
    assert_true(#actual == #expected,
        string.format("%s: expected size %d, got %d", tostring(label or "list"), #expected, #actual))
    for i = 1, #expected do
        assert_true(actual[i] == expected[i],
            string.format("%s: item #%d expected %s, got %s",
                tostring(label or "list"), i, tostring(expected[i]), tostring(actual[i])))
    end
end

do
    local actual = stream_resolve_warm_standby_inputs(5, 1, "active", 2, "RUNNING")
    assert_list_eq(actual, { 2, 3 }, "active warms next backups")
end

do
    local actual = stream_resolve_warm_standby_inputs(4, 3, "active", 2, "RUNNING")
    assert_list_eq(actual, { 1, 2 }, "active on backup warms higher priority first")
end

do
    local actual = stream_resolve_warm_standby_inputs(4, 2, "active_stop_if_all_inactive", 3, "RUNNING")
    assert_list_eq(actual, { 1, 3, 4 }, "active_stop warms like active while running")
end

do
    local actual = stream_resolve_warm_standby_inputs(4, 2, "active", 3, "INACTIVE")
    assert_list_eq(actual, {}, "inactive state disables warm standby")
end

do
    local actual = stream_resolve_warm_standby_inputs(4, 1, "passive", 3, "RUNNING")
    assert_list_eq(actual, {}, "passive mode has no warm standby")
end

do
    local actual = stream_resolve_warm_standby_inputs(4, 1, "active", 0, "RUNNING")
    assert_list_eq(actual, {}, "warm_max=0 disables warm standby")
end

do
    local actual = stream_resolve_warm_standby_inputs(4, 0, "active", 2, "RUNNING")
    assert_list_eq(actual, { 1, 2 }, "no active input warms from first by priority")
end

print("stream_failover_warm_max_unit: ok")
astra.exit()
