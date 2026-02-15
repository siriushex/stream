log.set({ debug = true })

dofile("scripts/base.lua")
dofile("scripts/config.lua")
dofile("scripts/transcode.lua")

config.init({
  data_dir = "/tmp/transcode_qsv_args_unit_data",
  db_path = "/tmp/transcode_qsv_args_unit_data/transcode_qsv_args_unit.db",
})

-- Stub udp_switch so ladder outputs are built in unit env (no real sockets).
udp_switch = function(_opts)
  return {
    port = function()
      return 12345
    end,
    stream = function()
      return nil
    end,
  }
end

local function assert_true(v, msg)
  if not v then
    error(msg or "assert")
  end
end

local function has_pair(argv, flag, value)
  if type(argv) ~= "table" then
    return false
  end
  for i = 1, #argv - 1 do
    if argv[i] == flag and argv[i + 1] == value then
      return true
    end
  end
  return false
end

local function build_job(id, video_codec)
  local profile = {
    id = "HD",
    name = "720p",
    width = 1280,
    height = 720,
    fps = 25,
    bitrate_kbps = 2500,
    maxrate_kbps = 3200,
    bufsize_kbps = 5000,
    audio_mode = "aac",
    audio_bitrate_kbps = 128,
    audio_sr = 48000,
    audio_channels = 2,
    deinterlace = "auto",
  }
  if video_codec then
    profile.video_codec = video_codec
  end
  local cfg = {
    id = id,
    name = "unit " .. id,
    input = { "udp://239.0.0.1:1234" },
    transcode = {
      enabled = true,
      engine = "qsv",
      profiles = { profile },
      watchdog = {},
    },
  }
  local row = { enabled = 0, config = cfg, config_json = "{}" }
  local job = transcode.upsert(id, row, true)
  assert_true(job ~= nil, "expected job")
  assert_true(job.ladder_enabled == true, "expected ladder enabled")
  return job
end

-- h264_qsv defaults (preset/lookahead/profile).
do
  local job = build_job("tc_qsv_h264")
  local argv, err = transcode._build_ladder_encoder_ffmpeg_args(job)
  assert_true(argv ~= nil, err or "expected argv")
  assert_true(has_pair(argv, "-c:v", "h264_qsv"), "expected -c:v h264_qsv")
  assert_true(has_pair(argv, "-b:v", "2500k"), "expected -b:v 2500k")
  assert_true(has_pair(argv, "-maxrate", "3200k"), "expected -maxrate 3200k")
  assert_true(has_pair(argv, "-bufsize", "5000k"), "expected -bufsize 5000k")
  assert_true(has_pair(argv, "-preset", "fast"), "expected qsv -preset fast")
  assert_true(has_pair(argv, "-look_ahead_depth", "50"), "expected qsv look_ahead_depth 50")
  assert_true(has_pair(argv, "-profile:v", "high"), "expected qsv h264 profile high")
end

-- hevc_qsv defaults (profile should switch to main).
do
  local job = build_job("tc_qsv_hevc", "hevc_qsv")
  local argv, err = transcode._build_ladder_encoder_ffmpeg_args(job)
  assert_true(argv ~= nil, err or "expected argv")
  assert_true(has_pair(argv, "-c:v", "hevc_qsv"), "expected -c:v hevc_qsv")
  assert_true(has_pair(argv, "-preset", "fast"), "expected qsv -preset fast")
  assert_true(has_pair(argv, "-look_ahead_depth", "50"), "expected qsv look_ahead_depth 50")
  assert_true(has_pair(argv, "-profile:v", "main"), "expected qsv hevc profile main")
end

log.info("[unit] transcode_qsv_args_unit ok")
astra.exit()

