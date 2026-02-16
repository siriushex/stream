log.set({ debug = true })

dofile("scripts/base.lua")
dofile("scripts/config.lua")
dofile("scripts/stream.lua")

config.init({
  data_dir = "/tmp/dash_input_validate_unit_data",
  db_path = "/tmp/dash_input_validate_unit_data/dash_input_validate_unit.db",
})

local function assert_true(value, message)
  if not value then
    error(message or "assert_true failed")
  end
end

local function make_cfg(input_url)
  return {
    id = "dash-validate",
    name = "dash-validate",
    enable = true,
    input = { input_url },
    output = { "udp://239.200.1.1:1234" },
  }
end

do
  local ok, err = validate_stream_config(
    make_cfg("https://example.com/live/manifest.mpd#input_type=dash#dash_strategy=auto_max")
  )
  assert_true(ok == true and err == nil, "valid dash config should pass")
end

do
  local ok, err = validate_stream_config(
    make_cfg("https://example.com/live/manifest.mpd#input_type=dash#dash_strategy=broken")
  )
  assert_true(ok == nil and tostring(err):find("dash_strategy", 1, true) ~= nil,
    "invalid dash_strategy must fail validation")
end

do
  local ok, err = validate_stream_config(
    make_cfg("https://example.com/live/manifest.mpd#input_type=dash#dash_strategy=fixed_id")
  )
  assert_true(ok == nil and tostring(err):find("dash fixed_id requires dash_representation_id", 1, true) ~= nil,
    "fixed_id without representation id must fail validation")
end

do
  local ok, err = validate_stream_config(
    make_cfg("https://example.com/live/manifest.mpd#input_type=dash#dash_enable_cenc=1#dash_cenc_key=1234")
  )
  assert_true(ok == nil and tostring(err):find("dash_cenc_key must be 32 hex chars", 1, true) ~= nil,
    "invalid cenc key must fail validation")
end

do
  local ok, err = validate_stream_config(
    make_cfg("https://example.com/live/manifest.mpd#input_type=dash#dash_startup_grace_sec=2")
  )
  assert_true(ok == nil and tostring(err):find("dash_startup_grace_sec", 1, true) ~= nil,
    "too low startup grace must fail validation")
end

do
  local ok, err = validate_stream_config(
    make_cfg("https://example.com/live/manifest.mpd#input_type=dash#dash_max_no_data_sec=5")
  )
  assert_true(ok == nil and tostring(err):find("dash_max_no_data_sec", 1, true) ~= nil,
    "too low max no-data must fail validation")
end

do
  local ok, err = validate_stream_config(
    make_cfg("https://example.com/live/manifest.mpd#input_type=dash#dash_startup_grace_sec=60#dash_max_no_data_sec=90")
  )
  assert_true(ok == true and err == nil, "valid stall self-heal options should pass")
end

do
  local ok, err = validate_stream_config(
    make_cfg("udp://239.1.1.1:1234#input_type=dash")
  )
  assert_true(ok == nil and tostring(err):find("dash input requires http/https/hls mpd url", 1, true) ~= nil,
    "non-http transport for dash must fail")
end

print("dash_input_validate_unit: ok")
astra.exit()
