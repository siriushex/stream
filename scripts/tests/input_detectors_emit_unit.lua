-- Unit test: detector events should emit alerts without crashing (emit_stream_alert linkage)

log.set({ debug = true })

dofile("scripts/base.lua")
dofile("scripts/config.lua")
dofile("scripts/stream.lua")

config.init({
  data_dir = "/tmp/input_detectors_emit_unit_data",
  db_path = "/tmp/input_detectors_emit_unit_data/input_detectors_emit_unit.db",
})

local function assert_true(v, msg)
  if not v then
    error(msg or "assert")
  end
end

do
  local now = os.time()
  local input_cfg = parse_url("udp://239.0.0.1:1234#no_audio_on=2")
  input_cfg.name = "detector #1"

  local input_data = { config = input_cfg }
  -- Simulate that audio activity stopped long enough ago.
  input_data.last_audio_pts_change_ts = now - 10

  local channel_data = {
    input = { input_data },
    output = {},
    active_input_id = 1,
    config = { id = "unit-det", name = "unit-det" },
  }

  on_analyze_spts(channel_data, 1, {
    analyze = true,
    on_air = true,
    total = {
      bitrate = 1000,
      cc_errors = 0,
      pes_errors = 0,
      scrambled = false,
      audio_present = false,
      video_present = true,
      video_pts_ms = 1000,
    },
  })

  local alerts = config.list_alerts({ since = now - 60, limit = 50 })
  local found = false
  for _, row in ipairs(alerts or {}) do
    if row.code == "NO_AUDIO_DETECTED" and row.stream_id == "unit-det" then
      found = true
      break
    end
  end
  assert_true(found, "expected NO_AUDIO_DETECTED alert")
end

print("input_detectors_emit_unit: ok")
astra.exit()

