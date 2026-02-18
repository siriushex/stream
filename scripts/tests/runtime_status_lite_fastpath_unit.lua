log.set({ debug = true })

dofile("scripts/base.lua")
dofile("scripts/runtime.lua")

config = config or {}
config.get_setting = function(_key)
    return nil
end

local function assert_true(v, msg)
    if not v then
        error(msg or "assert")
    end
end

local jitter_calls = 0
local playout_calls = 0

runtime.streams = {
    s1 = {
        kind = "stream",
        channel = {
            active_input_id = 1,
            input = {
                {
                    source_url = "udp://239.0.0.1:1234",
                    on_air = true,
                    stats = {
                        bitrate = 1234,
                        cc_errors = 0,
                        pes_errors = 0,
                        on_air = true,
                    },
                    input = {
                        jitter = {
                            stats = function()
                                jitter_calls = jitter_calls + 1
                                return { p95_ms = 5 }
                            end,
                        },
                        playout = {
                            stats = function()
                                playout_calls = playout_calls + 1
                                return { buffer_ms = 300 }
                            end,
                        },
                    },
                },
            },
        },
    },
}

local lite = runtime.list_status_lite()
assert_true(type(lite) == "table" and type(lite.s1) == "table", "lite status missing stream")
assert_true(jitter_calls == 0, "lite status must skip jitter stats collection")
assert_true(playout_calls == 0, "lite status must skip playout stats collection")
assert_true(type(lite.s1.inputs) == "table" and type(lite.s1.inputs[1]) == "table", "lite status missing input")
assert_true(lite.s1.inputs[1].jitter == nil, "lite input must not include jitter payload")
assert_true(lite.s1.inputs[1].playout == nil, "lite input must not include playout payload")

local full = runtime.list_status()
assert_true(type(full) == "table" and type(full.s1) == "table", "full status missing stream")
assert_true(jitter_calls > 0, "full status must collect jitter stats")
assert_true(playout_calls > 0, "full status must collect playout stats")
assert_true(type(full.s1.inputs) == "table" and type(full.s1.inputs[1]) == "table", "full status missing input")
assert_true(type(full.s1.inputs[1].jitter) == "table", "full input must include jitter payload")
assert_true(type(full.s1.inputs[1].playout) == "table", "full input must include playout payload")

print("runtime_status_lite_fastpath_unit: ok")
astra.exit()
