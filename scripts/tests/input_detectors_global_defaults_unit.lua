-- Global detector defaults (Telegram Alerts) unit tests

log.set({ debug = true })

dofile("scripts/base.lua")
dofile("scripts/config.lua")
dofile("scripts/stream.lua")

config.init({
  data_dir = "/tmp/input_detectors_global_defaults_unit_data",
  db_path = "/tmp/input_detectors_global_defaults_unit_data/input_detectors_global_defaults_unit.db",
})

local function assert_true(v, msg)
  if not v then
    error(msg or "assert")
  end
end

local function run_with_settings(settings, input_url)
  for k, v in pairs(settings or {}) do
    config.set_setting(k, v)
  end
  if type(stream_reset_global_detector_defaults_cache) == "function" then
    stream_reset_global_detector_defaults_cache()
  end

  local cfg = parse_url(input_url)
  cfg.name = "unit #1"

  local input_data = { config = cfg, source_url = input_url }
  local channel_data = {
    input = { input_data },
    output = {},
    active_input_id = 1,
    config = { id = "unit", name = "unit" },
  }

  on_analyze_spts(channel_data, 1, {
    analyze = true,
    on_air = true,
    total = {
      bitrate = 1000,
      cc_errors = 0,
      pes_errors = 0,
      scrambled = false,
      audio_present = true,
      video_present = true,
      audio_pts_ms = 1000,
      video_pts_ms = 1100,
    },
  })

  return input_data.detectors_config
end

-- Defaults should be disabled when telegram alerts are disabled.
do
  local det = run_with_settings({
    telegram_enabled = false,
    telegram_detectors_preset = "custom",
    telegram_detectors_no_audio_enabled = true,
    telegram_detectors_no_audio_timeout_sec = 5,
  }, "udp://239.0.0.1:1234")
  assert_true(det == nil, "expected no detectors when telegram_enabled=false")
end

-- Defaults should apply when telegram alerts enabled and preset is custom.
do
  local det = run_with_settings({
    telegram_enabled = true,
    telegram_detectors_preset = "custom",
    telegram_detectors_no_audio_enabled = true,
    telegram_detectors_no_audio_timeout_sec = 5,
    telegram_detectors_stop_video_enabled = true,
    telegram_detectors_stop_video_timeout_sec = 5,
    telegram_detectors_av_desync_enabled = true,
    telegram_detectors_av_desync_threshold_ms = 800,
    telegram_detectors_av_desync_hold_sec = 3,
    telegram_detectors_av_desync_stable_sec = 10,
    telegram_detectors_av_desync_resend_interval_sec = 60,
  }, "udp://239.0.0.1:1234")

  assert_true(det ~= nil, "expected detectors config")
  assert_true(det.no_audio and det.no_audio.enabled == true, "expected no_audio enabled from defaults")
  assert_true(det.stop_video and det.stop_video.enabled == true, "expected stop_video enabled from defaults")
  assert_true(det.av_desync and det.av_desync.enabled == true, "expected av_desync enabled from defaults")
end

-- Per-input explicit disable should override defaults.
do
  local det = run_with_settings({
    telegram_enabled = true,
    telegram_detectors_preset = "custom",
    telegram_detectors_no_audio_enabled = true,
    telegram_detectors_no_audio_timeout_sec = 5,
  }, "udp://239.0.0.1:1234#no_audio_on=0")

  assert_true(det == nil or det.no_audio == nil, "expected per-input no_audio_on=0 to disable no_audio detector")
end

print("input_detectors_global_defaults_unit: ok")
astra.exit()
