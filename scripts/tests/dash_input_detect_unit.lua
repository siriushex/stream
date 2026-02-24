log.set({ debug = true })

dofile("scripts/base.lua")
dofile("scripts/config.lua")

config.init({
  data_dir = "/tmp/dash_input_detect_unit_data",
  db_path = "/tmp/dash_input_detect_unit_data/dash_input_detect_unit.db",
})

local function assert_true(value, message)
  if not value then
    error(message or "assert_true failed")
  end
end

do
  local cfg = parse_url("https://example.com/live/manifest.mpd")
  assert_true(cfg and cfg.format == "https", "expected https format")
  assert_true(resolve_effective_input_format(cfg) == "dash", "mpd path should resolve to dash")
end

do
  local cfg = parse_url("https://example.com/live/index.m3u8#input_type=dash")
  assert_true(cfg and cfg.format == "https", "expected https format")
  assert_true(resolve_effective_input_format(cfg) == "dash", "explicit input_type=dash should resolve to dash")
end

do
  local cfg = parse_url("https://example.com/live/manifest.mpd#input_type=http_ts")
  assert_true(cfg and cfg.format == "https", "expected https format")
  assert_true(resolve_effective_input_format(cfg) == "http", "explicit input_type=http_ts must override mpd autodetect")
end

do
  local cfg = parse_url("hls://example.com/live/index.m3u8")
  assert_true(cfg and cfg.format == "hls", "expected hls format")
  assert_true(resolve_effective_input_format(cfg) == "hls", "non-mpd hls should remain hls")
end

do
  local cfg = parse_url("udp://239.10.10.10:1234#input_type=dash")
  assert_true(cfg and cfg.format == "udp", "expected udp format")
  assert_true(resolve_effective_input_format(cfg) == "dash", "input_type override should apply regardless of URL scheme")
end

do
  local cfg = parse_url("http://example.com/live/channel")
  cfg.dash_strategy = "auto_max"
  assert_true(resolve_effective_input_format(cfg) == "dash",
    "dash_* options should force effective dash for extensionless urls")
end

do
  local cfg = parse_url("http://example.com/live/channel")
  cfg.hls_segment_retries = 3
  assert_true(resolve_effective_input_format(cfg) == "hls",
    "hls_* options should force effective hls for extensionless urls")
end

do
  local cfg = parse_url("http://example.com/live/list.m3u")
  assert_true(cfg and cfg.format == "http", "expected http format")
  assert_true(resolve_effective_input_format(cfg) == "hls", "m3u playlist should resolve to hls")
end

print("dash_input_detect_unit: ok")
astra.exit()
