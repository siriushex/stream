log.set({ debug = true })

dofile("scripts/base.lua")
dofile("scripts/config.lua")

local function assert_true(cond, msg)
    if not cond then
        error(msg or "assert failed")
    end
end

local tmp = "/tmp/config_primary_fingerprint_unit"
os.execute("rm -rf " .. tmp .. " >/dev/null 2>&1 || true")
os.execute("mkdir -p " .. tmp)

local db_path = tmp .. "/stream.db"
local cfg_path = tmp .. "/config.json"

config.init({
    data_dir = tmp,
    db_path = db_path,
})
config.set_primary_config_path(cfg_path)

local ok, err = config.ensure_config_file(cfg_path)
assert_true(ok ~= nil, err or "ensure_config_file failed")

local payload, export_err = config.export_primary_config()
assert_true(payload ~= nil, export_err or "export_primary_config failed")

local fp, fp_err = config.primary_config_fingerprint(cfg_path)
assert_true(fp ~= nil, fp_err or "primary_config_fingerprint failed")

local stored = config.get_primary_config_fingerprint()
assert_true(stored == fp, "stored fingerprint mismatch")

local exported = config.export_astra({}) or {}
local settings = exported.settings or {}
for k, _ in pairs(settings) do
    assert_true(type(k) ~= "string" or k:sub(1, 1) ~= "_", "internal key leaked to export: " .. tostring(k))
end

print("config_primary_fingerprint_unit: ok")
astra.exit()

