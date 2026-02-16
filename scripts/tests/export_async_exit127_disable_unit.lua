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
local stderr_once = false
local timer_queue = {}

local function restore()
  process = old_process
  timer = old_timer
  io = old_io
  os.execute = old_os_execute
  _G.argv = old_argv
  stream_export_async = old_export_async
end

_G.argv = { "stream" }
io = {}
os.execute = function(cmd)
  cmd = tostring(cmd or "")
  if cmd:find("test -x '/usr/local/bin/stream'", 1, true) then
    return 0
  end
  if cmd:find("command -v nice", 1, true) then
    return 0
  end
  if cmd:find("command -v ionice", 1, true) then
    return 1
  end
  return 1
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

local function flush_timers()
  local guard = 0
  while #timer_queue > 0 do
    guard = guard + 1
    assert_true(guard < 128, "timer queue overflow")
    local item = table.remove(timer_queue, 1)
    if item and item.handle and not item.handle.closed then
      local cb = item.opts and item.opts.callback
      if type(cb) == "function" then
        cb(item.handle)
      end
    end
  end
end

process = {
  spawn = function()
    spawn_calls = spawn_calls + 1
    return {
      read_stdout = function() return nil end,
      read_stderr = function()
        if not stderr_once then
          stderr_once = true
          return "nice: stream: No such file or directory\n"
        end
        return nil
      end,
      poll = function()
        return { exit_code = 127, signal = 0 }
      end,
      close = function() end,
      kill = function() end,
    }
  end,
}

local cfg = {
  is_primary_writer = true,
  data_dir = "/tmp",
  db_path = "/tmp/export_async_exit127_disable_unit.db",
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

local ok1 = mod.request({ primary_path = "/tmp/export_async_exit127_disable_1.json" }, cfg)
assert_true(ok1 == true, "first request should succeed")
flush_timers()
assert_true(mod._state and mod._state.worker_disabled == true,
  "worker must be disabled after exit=127 not found")

local ok2 = mod.request({ primary_path = "/tmp/export_async_exit127_disable_2.json" }, cfg)
assert_true(ok2 == true, "second request should succeed")
flush_timers()

assert_true(spawn_calls == 1, "spawn should be called once before worker disable")
assert_true(encode_calls == 1, "fallback export should run on second request")
assert_true(writes == 1, "expected fallback write for second request")

restore()
log.info("[unit] export_async_exit127_disable_unit ok")
astra.exit()
