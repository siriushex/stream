log.set({ debug = true })

dofile("scripts/base.lua")
dofile("scripts/config.lua")
dofile("scripts/dvr.lua")

local function assert_true(value, message)
    if not value then
        error(message or "assert failed")
    end
end

local tmp = "/tmp/dvr_local_no_data_input_fallback_unit"
os.execute("rm -rf " .. tmp .. " >/dev/null 2>&1 || true")
os.execute("mkdir -p " .. tmp)

config.init({
    data_dir = tmp,
    db_path = tmp .. "/stream.db",
})
config.set_setting("http_auth_enabled", false)

local stream_id = "dvr_no_data_input_fallback"
local stream_cfg = {
    id = stream_id,
    name = "DVR no-data fallback",
    input = {
        "http://origin.example/live",
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
    last_error = "",
    active_input_id = 1,
    active_input_index = 0,
    inputs_status = {
        {
            id = 1,
            index = 0,
            active = true,
            state = "DOWN",
            health_state = "offline",
            health_reason = "http_404",
            last_error = "no_data",
        },
    },
}

runtime.list_status_lite_ids = function(_ids)
    return {
        [stream_id] = {
            on_air = status.on_air == true,
            last_error = status.last_error,
            active_input_id = status.active_input_id,
            active_input_index = status.active_input_index,
            inputs_status = status.inputs_status,
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

dvr.local_tick()
assert_true(state_mode() == "LIVE", "initial mode must stay LIVE before trigger")

now = 101
dvr.local_tick()
assert_true(state_mode() == "LIVE", "must stay LIVE before backup trigger window")

now = 103
dvr.local_tick()
assert_true(state_mode() == "FAIL_CONFIRMED", "must enter FAIL_CONFIRMED from active input no_data")

os.time = orig_os_time

log.info("[unit] dvr_local_no_data_input_fallback_unit ok")
astra.exit()
