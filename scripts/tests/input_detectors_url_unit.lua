log.set({ debug = true })

dofile("scripts/base.lua")
dofile("scripts/stream.lua")

local function assert_true(v, msg)
  if not v then
    error(msg or "assert")
  end
end

-- Basic parse with numeric params.
do
  -- '&' separator inside fragment should be accepted.
  do
    local p = parse_url("udp://239.0.0.1:1234#no_audio_on=5&stop_video=freeze")
    assert_true(p and p.format == "udp", "expected udp format")
    assert_true(tostring(p.no_audio_on) == "5", "no_audio_on should be 5 (amp)")
    assert_true(tostring(p.stop_video) == "freeze", "stop_video should be freeze (amp)")
  end

  local url = "udp://239.0.0.1:1234"
    .. "#no_audio_on=5"
    .. "#stop_video=freeze"
    .. "#stop_video_timeout_sec=7"
    .. "#stop_video_freeze_sec=12"
    .. "#detect_av=on"
    .. "#detect_av_threshold_ms=900"
    .. "#detect_av_hold_sec=3"
    .. "#detect_av_stable_sec=10"
    .. "#detect_av_resend_interval_sec=60"
    .. "#silencedetect=1"
    .. "#silencedetect_duration=20"
    .. "#silencedetect_interval=10"
    .. "#silencedetect_noise=-30"
  local p = parse_url(url)
  assert_true(p and p.format == "udp", "expected udp format")
  assert_true(tostring(p.no_audio_on) == "5", "no_audio_on should be 5")
  assert_true(tostring(p.stop_video) == "freeze", "stop_video should be freeze")
  assert_true(tostring(p.stop_video_timeout_sec) == "7", "stop_video_timeout_sec should be 7")
  assert_true(tostring(p.stop_video_freeze_sec) == "12", "stop_video_freeze_sec should be 12")
  assert_true(tostring(p.detect_av) == "on", "detect_av should be on")
  assert_true(tostring(p.detect_av_threshold_ms) == "900", "detect_av_threshold_ms should be 900")
  assert_true(tostring(p.detect_av_hold_sec) == "3", "detect_av_hold_sec should be 3")
  assert_true(tostring(p.detect_av_stable_sec) == "10", "detect_av_stable_sec should be 10")
  assert_true(tostring(p.detect_av_resend_interval_sec) == "60", "detect_av_resend_interval_sec should be 60")
  assert_true(p.silencedetect == "1" or p.silencedetect == true, "silencedetect should be enabled")
  assert_true(tostring(p.silencedetect_duration) == "20", "silencedetect_duration should be 20")
  assert_true(tostring(p.silencedetect_interval) == "10", "silencedetect_interval should be 10")
  assert_true(tostring(p.silencedetect_noise) == "-30", "silencedetect_noise should be -30")
end

-- Detector normalization should accept UI/URL keys.
do
  local function get_av_threshold(url)
    local cfg = parse_url(url)
    cfg.name = "unit #1"

    local input_data = { config = cfg }
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
        video_pts_ms = 1800,
      },
    })

    local det = input_data.detectors_config and input_data.detectors_config.av_desync or nil
    return det and det.threshold_ms or nil
  end

  assert_true(get_av_threshold("udp://239.0.0.1:1234#detect_av=on#detect_av_threshold_ms=900") == 900,
    "detect_av_threshold_ms should be used")
  assert_true(get_av_threshold("udp://239.0.0.1:1234#detect_av=on#av_threshold_ms=1234") == 1234,
    "legacy av_threshold_ms should be used")
end

-- Boolean flag without value.
do
  local p = parse_url("udp://239.0.0.1:1234#no_audio_on")
  assert_true(p.no_audio_on == true, "no_audio_on should parse as true")
end

print("input_detectors_url_unit: ok")
astra.exit()
