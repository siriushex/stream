log.set({ debug = true })

dofile("scripts/base.lua")
dofile("scripts/config.lua")
dofile("scripts/dvr.lua")

local function assert_true(value, message)
    if not value then
        error(message or "assert failed")
    end
end

local tmp = "/tmp/dvr_local_recovering_mode_unit"
os.execute("rm -rf " .. tmp .. " >/dev/null 2>&1 || true")
os.execute("mkdir -p " .. tmp)

config.init({
    data_dir = tmp,
    db_path = tmp .. "/stream.db",
})
config.set_setting("http_auth_enabled", false)

local stream_id = "dvr_local_recover"
local stream_cfg = {
    id = stream_id,
    name = "DVR local recover stream",
    input = {
        "udp://239.1.1.1:1234",
        "http://127.0.0.1:8000/dvr/play/" .. stream_id,
    },
    dvr = {
        enabled = false,
        backup_enabled = true,
        backup_trigger_no_data_sec = 2,
        backup_recover_stable_sec = 5,
    },
}

runtime = {
    streams = {
        [stream_id] = {
            channel = {
                config = stream_cfg,
            },
        },
    },
}

local status = {
    on_air = false,
    last_error = "No data on active input",
    active_input_id = 1,
}

runtime.list_status_lite_ids = function(_ids)
    return {
        [stream_id] = {
            on_air = status.on_air == true,
            last_error = status.last_error,
            active_input_id = status.active_input_id,
        },
    }
end

local now = 100
local orig_os_time = os.time
os.time = function()
    return now
end

local function state_mode()
    local row = dvr.get_backup_state_for_api(stream_id)
    return tostring(row and row.mode or "")
end

local function stream_paused()
    local row = dvr.get_stream(stream_id)
    return row and row.recording_paused == true
end

dvr.local_tick()
assert_true(state_mode() == "LIVE", "initial mode must be LIVE")
assert_true(stream_paused() == false, "LIVE must not pause recording")

now = 101
dvr.local_tick()
assert_true(state_mode() == "LIVE", "must stay LIVE before trigger window")

now = 103
dvr.local_tick()
assert_true(state_mode() == "FAIL_CONFIRMED", "must enter FAIL_CONFIRMED after trigger window")
assert_true(stream_paused() == false, "FAIL_CONFIRMED must keep recording until DVR_ACTIVE")

status.on_air = true
status.last_error = ""
status.active_input_id = 2
now = 104
dvr.local_tick()
assert_true(state_mode() == "DVR_ACTIVE", "must enter DVR_ACTIVE when local backup input is active")
assert_true(stream_paused() == true, "DVR_ACTIVE must pause recording")

status.active_input_id = 1
now = 105
dvr.local_tick()
assert_true(state_mode() == "RECOVERING_TO_LIVE", "must enter RECOVERING_TO_LIVE when main input returns")
assert_true(stream_paused() == true, "RECOVERING_TO_LIVE must keep recording paused")

now = 108
dvr.local_tick()
assert_true(state_mode() == "RECOVERING_TO_LIVE", "must stay RECOVERING_TO_LIVE until recover_stable_sec")

now = 111
dvr.local_tick()
assert_true(state_mode() == "LIVE", "must return to LIVE after recover_stable_sec")
assert_true(stream_paused() == false, "LIVE after recovery must resume recording")

os.time = orig_os_time

log.info("[unit] dvr_local_recovering_mode_unit ok")
astra.exit()
