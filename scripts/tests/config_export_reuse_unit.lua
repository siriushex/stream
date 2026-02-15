log.set({ debug = true })

dofile("scripts/base.lua")
dofile("scripts/config.lua")

local function assert_true(cond, msg)
    if not cond then
        error(msg or "assert failed")
    end
end

local called = 0
local original_export = config.export_astra
config.export_astra = function(opts)
    called = called + 1
    return original_export(opts)
end

local payload = {
    settings = { demo = true },
    users = {},
    make_stream = {},
    dvb_tune = {},
    splitters = {},
    softcam = {},
}
local encoded = json.encode(payload)

local path = "/tmp/config_export_reuse_unit.json"
local ok, err = config.export_astra_file(path, { payload = payload, encoded = encoded })
assert_true(ok ~= nil, err or "export_astra_file failed")
assert_true(called == 0, "export_astra was called unexpectedly")

local file, ferr = io.open(path, "rb")
assert_true(file ~= nil, ferr or "open failed")
local content = file:read("*a") or ""
file:close()

assert_true(content == encoded, "file content mismatch")

print("config_export_reuse_unit: ok")
astra.exit()

