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

local normalize = radio and radio._test and radio._test.normalize_settings
assert_true(type(normalize) == "function", "normalize_settings missing")

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

  assert_eq(s.audio_format, "mp3", "audio_format fallback")
  assert_true(type(s.restart_delay_sec) == "number" and s.restart_delay_sec > 0, "restart_delay_sec must be > 0")
  assert_eq(s.max_restarts_per_10min, 1, "max_restarts_per_10min clamp")
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

print("radio_stream_settings_unit: ok")
astra.exit()

