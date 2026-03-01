log.set({ debug = true })

dofile("scripts/base.lua")
dofile("scripts/radio_stream.lua")

local function assert_true(v, msg)
  if not v then
    error(msg or "assert")
  end
end

local function assert_eq(a, b, msg)
  if a ~= b then
    error((msg or "assert") .. ": expected " .. tostring(b) .. ", got " .. tostring(a))
  end
end

local function has_pair(argv, flag, value)
  if type(argv) ~= "table" then return false end
  for i = 1, #argv - 1 do
    if argv[i] == flag and argv[i + 1] == value then
      return true
    end
  end
  return false
end

local function has_token(argv, token)
  if type(argv) ~= "table" then return false end
  for i = 1, #argv do
    if argv[i] == token then
      return true
    end
  end
  return false
end

local normalize = radio and radio._test and radio._test.normalize_settings
assert_true(type(normalize) == "function", "normalize_settings missing")
local direct_reason = radio and radio._test and radio._test.force_direct_input_reason
assert_true(type(direct_reason) == "function", "force_direct_input_reason missing")
local build_ffmpeg_args = radio and radio._test and radio._test.build_ffmpeg_args
assert_true(type(build_ffmpeg_args) == "function", "build_ffmpeg_args missing")
local mark_ffmpeg_progress = radio and radio._test and radio._test.mark_ffmpeg_progress
assert_true(type(mark_ffmpeg_progress) == "function", "mark_ffmpeg_progress missing")

do
  local s = normalize({
    audio_url = "http://example.com/radio.mp3",
    png_path = "/tmp/test.png",
    output_url = "udp://239.0.0.1:1234",
    pkt_size = 1316,
    audio_format = "ogg",
    restart_delay_sec = 0,
    max_restarts_per_10min = 0,
    use_curl = true,
  })

  assert_eq(s.audio_format, "auto", "audio_format fallback")
  assert_true(type(s.restart_delay_sec) == "number" and s.restart_delay_sec > 0, "restart_delay_sec must be > 0")
  assert_eq(s.max_restarts_per_10min, 1, "max_restarts_per_10min clamp")
  assert_eq(s.fps, 1, "default fps")
  assert_eq(s.preset, "ultrafast", "default preset")
  assert_eq(s.video_bitrate, "400k", "default video bitrate")
  assert_eq(s.scale_flags, "fast_bilinear", "default scale flags")
  assert_true(s.pre_scale_png == true, "pre_scale_png default")
  assert_true(tostring(s.output_url):find("pkt_size=1316", 1, true) ~= nil, "pkt_size appended")
end

do
  local s = normalize({
    audio_url = "http://example.com/radio.mp3",
    png_path = "/tmp/test.png",
    output_url = "udp://239.0.0.1:1234?ttl=32",
    pkt_size = 1316,
  })
  assert_true(tostring(s.output_url):find("ttl=32", 1, true) ~= nil, "preserve existing query")
  assert_true(tostring(s.output_url):find("pkt_size=1316", 1, true) ~= nil, "append pkt_size with &")
end

do
  local hls = normalize({
    audio_url = "http://example.com/live/index.m3u8?token=1",
    png_path = "/tmp/test.png",
    output_url = "udp://239.0.0.1:1234",
    use_curl = true,
    audio_format = "mp3",
  })
  assert_eq(direct_reason(hls), "hls_url", "HLS URL should force direct input")
end

do
  local ts = normalize({
    audio_url = "example.com:8080/live/stream.ts",
    png_path = "/tmp/test.png",
    output_url = "udp://239.0.0.1:1234",
    use_curl = true,
    audio_format = "mp3",
  })
  assert_true(tostring(ts.audio_url):find("^http://") ~= nil, "host:port URL should be normalized to http://")
  assert_eq(direct_reason(ts), "mpegts_url", "MPEG-TS URL should force direct input")
end

do
  local hls = normalize({
    audio_url = "r5.sky1000.ru:8080/Radio_Reka/index.m3u8?token=abc",
    png_path = "/tmp/test.png",
    output_url = "udp://239.0.0.1:1234",
    use_curl = true,
    audio_format = "auto",
  })
  assert_eq(hls.audio_url, "http://r5.sky1000.ru:8080/Radio_Reka/index.m3u8?token=abc", "missing scheme should be normalized")
  assert_eq(direct_reason(hls), "hls_url", "normalized HLS URL should force direct input")
end

do
  local s = normalize({
    audio_url = "http://example.com/live/stream.ts",
    png_path = "/tmp/test.png",
    output_url = "udp://239.0.0.1:1234",
    use_curl = false,
    audio_format = "mpegts",
  })
  local argv = build_ffmpeg_args(s, nil)
  assert_true(has_pair(argv, "-f", "mpegts"), "direct mpegts input should set -f mpegts")
  assert_true(has_pair(argv, "-framerate", tostring(s.fps)), "png input should use input framerate")
  assert_true(has_pair(argv, "-thread_queue_size", tostring(s.audio_thread_queue_size)), "audio input queue size should be configured")
end

do
  local s = normalize({
    audio_url = "http://example.com/live/stream.ts",
    png_path = "/tmp/test.png",
    output_url = "udp://239.0.0.1:1234",
    use_curl = false,
    audio_format = "mpegts",
  })
  s.runtime_png_path = "/tmp/test-scaled.png"
  s.runtime_png_prescaled = true
  local argv = build_ffmpeg_args(s, nil)
  assert_true(has_pair(argv, "-i", "/tmp/test-scaled.png"), "prescaled PNG input path")
  assert_true(not has_token(argv, "-vf"), "prescaled PNG should skip realtime -vf")
end

do
  local job = {
    last_progress_ts = 100,
    last_ffmpeg_time_sec = 10.00,
    last_ffmpeg_frame = 100,
  }
  mark_ffmpeg_progress(job, "frame=  100 fps=8.0 time=00:00:10.00 bitrate=550.1kbits/s")
  assert_eq(job.last_progress_ts, 100, "same frame/time must not be treated as progress")

  mark_ffmpeg_progress(job, "frame=  101 fps=8.0 time=00:00:10.12 bitrate=550.1kbits/s")
  assert_true(job.last_progress_ts >= 100, "advanced frame/time must update progress timestamp")
  assert_true((job.last_ffmpeg_time_sec or 0) > 10.0, "time cursor should advance")
  assert_eq(job.last_ffmpeg_frame, 101, "frame cursor should advance")
end

print("radio_stream_settings_unit: ok")
astra.exit()
