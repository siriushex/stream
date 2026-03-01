log.set({ debug = true })

dofile("scripts/base.lua")
dofile("scripts/stream.lua")

local function assert_eq(actual, expected, message)
    if actual ~= expected then
        error((message or "assert_eq failed") .. ": expected=" .. tostring(expected) .. " got=" .. tostring(actual))
    end
end

do
    local input = {
        fail_since = 100,
        ok_since = 95,
        last_seen_ts = 90,
        last_ok_ts = 91,
        last_error = "no_data",
        __no_data_streak = 7,
        is_ok = true,
        on_air = true,
    }

    stream_mark_input_activated(input, 1234)

    assert_eq(input.fail_since, 1234, "fail_since reset")
    assert_eq(input.ok_since, nil, "ok_since cleared")
    assert_eq(input.last_seen_ts, 1234, "last_seen_ts reset")
    assert_eq(input.last_ok_ts, 1234, "last_ok_ts reset")
    assert_eq(input.last_error, nil, "last_error cleared")
    assert_eq(input.__no_data_streak, 0, "__no_data_streak reset")
    assert_eq(input.is_ok, false, "is_ok reset")
    assert_eq(input.on_air, false, "on_air reset")
end

print("stream_failover_activation_state_unit: ok")
astra.exit()
