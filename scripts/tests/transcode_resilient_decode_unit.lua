log.set({ debug = true })

dofile("scripts/base.lua")
dofile("scripts/config.lua")
dofile("scripts/transcode.lua")

config.init({
  data_dir = "/tmp/transcode_resilient_decode_unit_data",
  db_path = "/tmp/transcode_resilient_decode_unit_data/transcode_resilient_decode_unit.db",
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

local function has_flag(argv, flag)
  if type(argv) ~= "table" then
    return false
  end
  for i = 1, #argv do
    if argv[i] == flag then
      return true
    end
  end
  return false
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

local function find_last_value(argv, flag)
  if type(argv) ~= "table" then
    return nil
  end
  local idx = nil
  for i = 1, #argv - 1 do
    if argv[i] == flag then
      idx = i
    end
  end
  if idx then
    return argv[idx + 1]
  end
  return nil
end

local function build_job(id, opts)
  opts = opts or {}
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
  local cfg = {
    id = id,
    name = "unit " .. id,
    input = { opts.input_url or "udp://239.0.0.1:1234" },
    transcode = {
      enabled = true,
      engine = "cpu",
      profiles = { profile },
      watchdog = {},
      ffmpeg_global_args = opts.ffmpeg_global_args,
      resilient_decode = opts.resilient_decode,
    },
  }
  local row = { enabled = 0, config = cfg, config_json = "{}" }
  local job = transcode.upsert(id, row, true)
  assert_true(job ~= nil, "expected job")
  assert_true(job.ladder_enabled == true, "expected ladder enabled")
  return job
end

-- auto mode: UDP inputs enable resilient decode by default.
do
  local job = build_job("tc_res_auto", {
    input_url = "udp://239.0.0.1:1234",
    ffmpeg_global_args = { "-fflags", "+genpts" },
  })
  local argv, err = transcode._build_ladder_encoder_ffmpeg_args(job)
  assert_true(argv ~= nil, err or "expected argv")
  assert_true(has_pair(argv, "-thread_queue_size", "1024"), "expected -thread_queue_size 1024")
  assert_true(has_pair(argv, "-err_detect", "ignore_err"), "expected -err_detect ignore_err")
  local fflags = tostring(find_last_value(argv, "-fflags") or "")
  assert_true(fflags:find("discardcorrupt", 1, true) ~= nil, "expected discardcorrupt in -fflags")
end

-- auto mode: HTTP inputs also enable resilient decode by default.
do
  local job = build_job("tc_res_http", {
    input_url = "http://127.0.0.1:8000/live.ts",
    ffmpeg_global_args = { "-fflags", "+genpts" },
  })
  local argv, err = transcode._build_ladder_encoder_ffmpeg_args(job)
  assert_true(argv ~= nil, err or "expected argv")
  assert_true(has_pair(argv, "-thread_queue_size", "1024"), "expected -thread_queue_size 1024")
  assert_true(has_pair(argv, "-err_detect", "ignore_err"), "expected -err_detect ignore_err")
  local fflags = tostring(find_last_value(argv, "-fflags") or "")
  assert_true(fflags:find("discardcorrupt", 1, true) ~= nil, "expected discardcorrupt in -fflags")
end

-- off mode: do not inject resilient decode args.
do
  local job = build_job("tc_res_off", {
    input_url = "udp://239.0.0.1:1234",
    ffmpeg_global_args = { "-fflags", "+genpts" },
    resilient_decode = false,
  })
  local argv, err = transcode._build_ladder_encoder_ffmpeg_args(job)
  assert_true(argv ~= nil, err or "expected argv")
  assert_true(not has_flag(argv, "-thread_queue_size"), "did not expect -thread_queue_size")
  assert_true(not has_flag(argv, "-err_detect"), "did not expect -err_detect")
  local fflags = tostring(find_last_value(argv, "-fflags") or "")
  assert_true(fflags == "+genpts", "expected -fflags unchanged")
end

log.info("[unit] transcode_resilient_decode_unit ok")
astra.exit()
