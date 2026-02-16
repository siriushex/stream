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
local old_utils = utils
local old_argv = _G.argv
local old_export_async = stream_export_async

local captured = nil
local files = {}

local function restore()
  process = old_process
  timer = old_timer
  io = old_io
  os.execute = old_os_execute
  utils = old_utils
  _G.argv = old_argv
  stream_export_async = old_export_async
end

_G.argv = { "stream" }
timer = nil

io = {
  open = function(path, mode)
    local p = tostring(path or "")
    local m = tostring(mode or "")
    if m == "wb" then
      files[p] = ""
      return {
        write = function(_, chunk)
          files[p] = files[p] .. tostring(chunk or "")
        end,
        close = function() end,
      }
    end
    if m == "rb" then
      if files[p] ~= nil then
        return {
          read = function() return files[p] end,
          close = function() end,
        }
      end
      return nil
    end
    return nil
  end,
}

os.execute = function(cmd)
  cmd = tostring(cmd or "")
  if cmd:find("test -x '/usr/local/bin/stream'", 1, true) then
    return 0
  end
  if cmd:find("command -v nice", 1, true) then
    return 1
  end
  if cmd:find("command -v ionice", 1, true) then
    return 1
  end
  return 1
end

utils = {
  embedded_read = function(path)
    if tostring(path or "") == "scripts/export_write.lua" then
      return "-- embedded export helper\nprint('ok')\n"
    end
    return nil
  end,
}

process = {
  spawn = function(argv, opts)
    captured = { argv = argv, opts = opts }
    return {
      read_stdout = function() return nil end,
      read_stderr = function() return nil end,
      poll = function() return { exit_code = 0, signal = 0 } end,
      close = function() end,
      kill = function() end,
    }
  end,
}

stream_export_async = nil
local mod = dofile("scripts/export_async.lua")
assert_true(type(mod) == "table", "module load failed")

local cfg = {
  is_primary_writer = true,
  data_dir = "/tmp/export_async_embedded_helper_unit",
  db_path = "/tmp/export_async_embedded_helper_unit.db",
}
local ok = mod.request({
  primary_path = "/tmp/export_async_embedded_helper_unit.json",
}, cfg)
assert_true(ok == true, "request failed")
assert_true(captured and type(captured.argv) == "table", "spawn not called")
assert_true(captured.argv[1] == "/usr/local/bin/stream",
  "expected absolute stream path, got: " .. tostring(captured.argv[1]))

local helper_path = "/tmp/export_async_embedded_helper_unit/.stream-export-write.lua"
assert_true(captured.argv[2] == helper_path,
  "expected materialized helper path, got: " .. tostring(captured.argv[2]))
assert_true(type(files[helper_path]) == "string" and files[helper_path] ~= "",
  "embedded helper content should be written")

restore()
log.info("[unit] export_async_embedded_helper_unit ok")
astra.exit()
