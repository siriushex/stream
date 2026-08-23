log.set({ debug = true })

dofile("scripts/base.lua")
dofile("scripts/config.lua")

local function assert_true(value, message)
    if not value then
        error(message or "assert_true failed")
    end
end

local tmp = "/tmp/buffer_dashboard_link_unit"
os.execute("rm -rf " .. tmp .. " >/dev/null 2>&1 || true")
os.execute("mkdir -p " .. tmp)
config.init({ data_dir = tmp, db_path = tmp .. "/stream.db" })
config.set_setting("buffer_listen_port", 8089)

config.upsert_buffer_resource("managed", {
    name = "Managed",
    path = "/managed",
    publish_to_dashboard = true,
})
local managed_ok, managed = config.sync_buffer_dashboard_stream("managed")
assert_true(managed_ok and managed.state == "managed", "managed stream was not created")
local managed_stream = config.get_stream("managed")
assert_true(managed_stream.config.buffer_managed_resource_id == "managed",
    "managed ownership marker missing")
assert_true(managed_stream.config.input[1] == "http://127.0.0.1:8089/managed",
    "managed stream URL mismatch")

config.upsert_stream("manual-target", true, {
    id = "manual-target",
    name = "Manual",
    input = { "http://127.0.0.1:8089/manual" },
})
config.upsert_buffer_resource("manual", {
    name = "Manual Link",
    path = "/manual",
    publish_to_dashboard = true,
    dashboard_stream_id = "manual-target",
})
local manual_ok, manual = config.sync_buffer_dashboard_stream("manual")
assert_true(manual_ok and manual.state == "linked" and manual.managed == false,
    "compatible manual stream was not linked")
assert_true(config.get_stream("manual-target").config.buffer_managed_resource_id == nil,
    "manual stream must not be rewritten")

config.upsert_stream("occupied", true, {
    id = "occupied",
    input = { "http://127.0.0.1:9999/unrelated" },
})
config.upsert_buffer_resource("conflict", {
    name = "Conflict",
    path = "/conflict",
    publish_to_dashboard = true,
    dashboard_stream_id = "occupied",
})
local conflict_ok, conflict_err = config.sync_buffer_dashboard_stream("conflict")
assert_true(not conflict_ok and tostring(conflict_err):find("conflict", 1, true),
    "occupied stream ID must be rejected")

config.delete_buffer_resource("managed")
assert_true(config.get_stream("managed") == nil, "owned managed stream was not deleted")
config.delete_buffer_resource("manual")
assert_true(config.get_stream("manual-target") ~= nil, "manual linked stream was deleted")

print("buffer_dashboard_link_unit: ok")
astra.exit()
