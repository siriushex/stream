log.set({ debug = true })

dofile("scripts/base.lua")
dofile("scripts/config.lua")

config.init({
  data_dir = "/tmp/dash_bridge_args_unit_data",
  db_path = "/tmp/dash_bridge_args_unit_data/dash_bridge_args_unit.db",
})

local function assert_true(value, message)
  if not value then
    error(message or "assert_true failed")
  end
end

local function argv_contains(argv, needle)
  for _, item in ipairs(argv or {}) do
    if tostring(item) == tostring(needle) then
      return true
    end
  end
  return false
end

local function argv_value_after(argv, key)
  for i = 1, #argv - 1 do
    if tostring(argv[i]) == tostring(key) then
      return argv[i + 1]
    end
  end
  return nil
end

do
  local conf = {
    name = "dash bridge unit",
    format = "https",
    host = "example.com",
    port = 443,
    path = "/live/manifest.mpd",
    bridge_addr = "127.0.0.1",
    bridge_port = 33790,
    dash_rw_timeout_ms = 15000,
    dash_reconnect_delay_max = 2,
    dash_user_agent = "UnitAgent/1.0",
    dash_referer = "https://ref.example.com",
    dash_cookies = "a=b",
    dash_headers = "X-Test: 1\\r\\nX-Mode: on",
  }
  local selection = {
    selected_video_index = 1,
    selected_audio_index = 2,
  }
  local argv, err = build_dash_bridge_args(conf, selection)
  assert_true(argv and not err, "build_dash_bridge_args should succeed")
  assert_true(argv_contains(argv, "-f"), "argv must contain format flag")
  assert_true(argv_value_after(argv, "-f") == "dash", "input demuxer must be dash")
  assert_true(argv_value_after(argv, "-i") == "https://example.com:443/live/manifest.mpd", "dash input url mismatch")
  assert_true(argv_contains(argv, "-map"), "argv must contain map")
  assert_true(argv_contains(argv, "0:1"), "argv must map selected video index")
  assert_true(argv_contains(argv, "0:2"), "argv must map selected audio index")
  assert_true(argv_contains(argv, "-c") and argv_contains(argv, "copy"), "dash bridge must run in copy mode")
  local output_url = argv[#argv]
  assert_true(tostring(output_url):find("udp://127.0.0.1:33790", 1, true) == 1, "bridge output URL mismatch")
end

do
  local conf = {
    name = "dash scheme normalize",
    format = "dash",
    host = "example.com",
    port = 80,
    path = "/manifest.mpd",
    dash_scheme = "http",
    bridge_port = 33791,
  }
  local argv, err = build_dash_bridge_args(conf, nil)
  assert_true(argv and not err, "build_dash_bridge_args should support dash:// transport input")
  assert_true(argv_value_after(argv, "-i") == "http://example.com:80/manifest.mpd",
    "dash:// source must normalize to http://")
  assert_true(argv_contains(argv, "0:v:0?"), "fallback video map must exist")
  assert_true(argv_contains(argv, "0:a:0?"), "fallback audio map must exist")
end

do
  local conf = {
    name = "dash hls normalize",
    format = "hls",
    host = "example.com",
    port = 80,
    path = "/manifest.mpd",
    bridge_port = 33792,
  }
  local argv, err = build_dash_bridge_args(conf, nil)
  assert_true(argv and not err, "build_dash_bridge_args should normalize hls:// source")
  assert_true(argv_value_after(argv, "-i") == "http://example.com:80/manifest.mpd",
    "hls:// source must normalize to http://")
end

print("dash_bridge_args_unit: ok")
astra.exit()
