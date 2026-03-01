log.set({ debug = true })

dofile("scripts/base.lua")
dofile("scripts/config.lua")

local function assert_true(cond, msg)
    if not cond then
        error(msg or "assert failed")
    end
end

local tmp = "/tmp/config_adapter_buffer_default_unit"
os.execute("rm -rf " .. tmp .. " >/dev/null 2>&1 || true")
os.execute("mkdir -p " .. tmp)

config.init({
    data_dir = tmp,
    db_path = tmp .. "/stream.db",
})

-- Missing buffer_size must be filled with default 4.
config.upsert_adapter("a1", true, {
    adapter = 0,
    device = 0,
    type = "S2",
})
local a1 = config.get_adapter("a1")
assert_true(a1 and a1.config, "adapter a1 is missing")
assert_true(a1.config.buffer_size == 4, "default buffer_size must be 4")

-- Legacy nested config.buffer_size should be promoted.
config.upsert_adapter("a2", true, {
    adapter = 1,
    device = 0,
    type = "S2",
    config = {
        buffer_size = 8,
    },
})
local a2 = config.get_adapter("a2")
assert_true(a2 and a2.config, "adapter a2 is missing")
assert_true(a2.config.buffer_size == 8, "nested buffer_size must be promoted")
local nested = a2.config.config
assert_true(nested == nil or nested.buffer_size == nil, "nested buffer_size must be removed")

-- Explicit value must not be overridden.
config.upsert_adapter("a3", true, {
    adapter = 2,
    device = 0,
    type = "S2",
    buffer_size = 16,
})
local a3 = config.get_adapter("a3")
assert_true(a3 and a3.config, "adapter a3 is missing")
assert_true(a3.config.buffer_size == 16, "explicit buffer_size must be preserved")

print("config_adapter_buffer_default_unit: ok")
astra.exit()
