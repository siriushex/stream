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
local old_argv = _G.argv
local old_export_async = stream_export_async

local spawn_calls = 0
local encode_calls = 0
local writes = 0

local function restore()
  process = old_process
  timer = old_timer
  io = old_io
  os.execute = old_os_execute
  _G.argv = old_argv
  stream_export_async = old_export_async
end

_G.argv = { "stream" }
timer = nil
io = {}
os.execute = function()
  return 1
end
process = {
  spawn = function()
    spawn_calls = spawn_calls + 1
    return nil
  end,
}

local cfg = {
  is_primary_writer = true,
  data_dir = "/tmp",
  db_path = "/tmp/export_async_missing_bin.db",
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

local ok1 = mod.request({ primary_path = "/tmp/export_async_missing_bin_1.json" }, cfg)
assert_true(ok1 == true, "first request should succeed")
assert_true(mod._state and mod._state.worker_disabled == true, "worker must be disabled after missing bin")

local ok2 = mod.request({ primary_path = "/tmp/export_async_missing_bin_2.json" }, cfg)
assert_true(ok2 == true, "second request should succeed")

assert_true(spawn_calls == 0, "spawn should not be called when stream binary is unresolved")
assert_true(encode_calls == 2, "fallback export must run for each request")
assert_true(writes == 2, "expected fallback writes")

restore()
log.info("[unit] export_async_missing_bin_fallback_unit ok")
astra.exit()
