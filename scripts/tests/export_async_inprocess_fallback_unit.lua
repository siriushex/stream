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
local old_export_async = stream_export_async

local spawn_called = false
local writes = {}
local encode_called = false

local function restore()
  process = old_process
  timer = old_timer
  io = old_io
  os.execute = old_os_execute
  stream_export_async = old_export_async
end

timer = nil
process = {
  spawn = function()
    spawn_called = true
    return nil
  end,
}

-- Force "helper script not found" even when running from repo root.
io = {
  open = function(path, mode)
    if tostring(path or ""):find("export_write.lua", 1, true) then
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

local cfg = {
  is_primary_writer = true,
  data_dir = "/tmp",
  db_path = "/tmp/export_async_inprocess_fallback_unit.db",
  export_astra_encoded = function()
    encode_called = true
    return { ok = true }, "{\"ok\":true}"
  end,
  export_astra_file = function(path, opts)
    writes[#writes + 1] = {
      path = path,
      has_payload = type(opts and opts.payload) == "table",
      has_encoded = type(opts and opts.encoded) == "string",
    }
    return true
  end,
}

stream_export_async = nil
local mod = dofile("scripts/export_async.lua")
assert_true(type(mod) == "table", "module load failed")

local ok = mod.request({
  primary_path = "/tmp/export_async_fallback_primary.json",
  lkg_path = "/tmp/export_async_fallback_lkg.json",
  snapshot_path = "/tmp/export_async_fallback_snapshot.json",
}, cfg)

assert_true(ok == true, "request should succeed")
assert_true(spawn_called == true, "spawn should be attempted before in-process fallback")
assert_true(encode_called == true, "fallback must encode payload")
assert_true(#writes == 3, "expected 3 export targets to be written")
assert_true(writes[1].has_payload and writes[1].has_encoded, "writer should receive payload+encoded")

restore()
log.info("[unit] export_async_inprocess_fallback_unit ok")
astra.exit()
