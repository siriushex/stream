log.set({ debug = true })

dofile("scripts/base.lua")
dofile("scripts/config.lua")
dofile("scripts/stream.lua")

config.init({
  data_dir = "/tmp/dash_on_air_hold_unit_data",
  db_path = "/tmp/dash_on_air_hold_unit_data/dash_on_air_hold_unit.db",
})

local function assert_true(value, message)
  if not value then
    error(message or "assert_true failed")
  end
end

local function make_total()
  return {
    bitrate = 0,
    cc_errors = 0,
    pes_errors = 0,
    scrambled = false,
  }
end

do
  local channel_data = {
    config = { id = "dash-hold", name = "dash-hold" },
    failover = { no_data_timeout = 5 },
    input = {
      {
        config = { name = "dash input", format = "dash" },
        on_air = true,
        fail_count = 0,
      },
    },
    active_input_id = 1,
  }

  for i = 1, 9 do
    on_analyze_spts(channel_data, 1, { analyze = true, on_air = false, total = make_total() })
    assert_true(channel_data.input[1].on_air == true, "dash hold should keep on_air=true for short gaps")
  end

  on_analyze_spts(channel_data, 1, { analyze = true, on_air = false, total = make_total() })
  assert_true(channel_data.input[1].on_air == false, "dash hold should expire after minimum 10 samples")
end

do
  local channel_data = {
    config = { id = "udp-no-hold", name = "udp-no-hold" },
    input = {
      {
        config = { name = "udp input", format = "udp", no_data_timeout_sec = 5 },
        on_air = true,
        fail_count = 0,
      },
    },
    active_input_id = 1,
  }

  for i = 1, 4 do
    on_analyze_spts(channel_data, 1, { analyze = true, on_air = false, total = make_total() })
    assert_true(channel_data.input[1].on_air == true, "non-dash should respect no_data_timeout_sec debounce")
  end
  on_analyze_spts(channel_data, 1, { analyze = true, on_air = false, total = make_total() })
  assert_true(channel_data.input[1].on_air == false, "non-dash debounce should expire at no_data_timeout_sec")
end

print("dash_on_air_hold_unit: ok")
astra.exit()
