log.set({ debug = true })

dofile("scripts/base.lua")

local function assert_true(v, msg)
    if not v then
        error(msg or "assert")
    end
end

local old_process = process
local old_timer = timer
local old_io = io
local old_os_execute = os.execute
local old_os_time = os.time
local old_export_async = stream_export_async

local timer_queue = {}
local writes = 0
local encode_calls = 0
local fake_now = 100

local function restore()
    process = old_process
    timer = old_timer
    io = old_io
    os.execute = old_os_execute
    os.time = old_os_time
    stream_export_async = old_export_async
end

timer = function(opts)
    local handle = {
        closed = false,
        close = function(self)
            self.closed = true
        end,
    }
    timer_queue[#timer_queue + 1] = { opts = opts, handle = handle }
    return handle
end

os.time = function()
    return fake_now
end

-- No worker should be spawned in this test (we force worker_disabled=true).
process = {
    spawn = function()
        return nil
    end,
}

io = {}
os.execute = function()
    return 1
end

local function run_next_timer()
    local item = table.remove(timer_queue, 1)
    assert_true(item ~= nil, "timer queue is empty")
    if item.handle and not item.handle.closed then
        local cb = item.opts and item.opts.callback
        if type(cb) == "function" then
            cb(item.handle)
        end
    end
end

local cfg = {
    is_primary_writer = true,
    data_dir = "/tmp",
    db_path = "/tmp/export_async_fallback_cooldown_unit.db",
    get_setting = function(key)
        if key == "export_async_fallback_interval_sec" then
            return 5
        end
        return nil
    end,
    export_astra_encoded = function()
        encode_calls = encode_calls + 1
        return { ok = true }, "{\"ok\":true}"
    end,
    export_astra_file = function()
        writes = writes + 1
        return true
    end,
}

stream_export_async = nil
local mod = dofile("scripts/export_async.lua")
assert_true(type(mod) == "table", "module load failed")
mod._state.worker_disabled = true

local ok1 = mod.request({ primary_path = "/tmp/export_async_cooldown_1.json" }, cfg)
assert_true(ok1 == true, "first request should succeed")
assert_true(#timer_queue == 1, "request timer must be scheduled")
run_next_timer()
assert_true(#timer_queue == 1, "fallback timer must be scheduled")
local first_delay = tonumber(timer_queue[1].opts and timer_queue[1].opts.interval) or 0
assert_true(first_delay >= 0.19 and first_delay <= 0.5, "first fallback should be near-immediate")
run_next_timer()
assert_true(writes == 1, "first fallback should write once")
assert_true(encode_calls == 1, "first fallback should encode once")

fake_now = 102
local ok2 = mod.request({ primary_path = "/tmp/export_async_cooldown_2.json" }, cfg)
assert_true(ok2 == true, "second request should succeed")
assert_true(#timer_queue == 1, "second request timer must be scheduled")
run_next_timer()
assert_true(#timer_queue == 1, "second fallback timer must be scheduled")
local second_delay = tonumber(timer_queue[1].opts and timer_queue[1].opts.interval) or 0
assert_true(second_delay >= 2.9, "fallback cooldown must delay next in-process export")
run_next_timer()
assert_true(writes == 2, "second fallback should write once")
assert_true(encode_calls == 2, "second fallback should encode once")

restore()
log.info("[unit] export_async_fallback_cooldown_unit ok")
astra.exit()
