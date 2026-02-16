log.set({ debug = true })

dofile("scripts/base.lua")

local function assert_true(value, message)
  if not value then
    error(message or "assert_true failed")
  end
end

local streams = {
  { index = 0, codec_type = "video", tags = { id = "v540", variant_bitrate = "1200000" }, height = 540 },
  { index = 1, codec_type = "video", tags = { id = "v1080", variant_bitrate = "4200000" }, height = 1080 },
  { index = 2, codec_type = "audio", tags = { id = "a128", variant_bitrate = "128000" } },
  { index = 3, codec_type = "audio", tags = { id = "a64", variant_bitrate = "64000" } },
}

do
  local selected, err = dash_select_streams(streams, { dash_strategy = "auto_max" })
  assert_true(selected and not err, "auto_max must select streams")
  assert_true(selected.selected_video_id == "v1080", "auto_max must choose max video bitrate")
  assert_true(selected.selected_audio_id == "a128", "auto_max must choose max audio bitrate")
end

do
  local selected, err = dash_select_streams(streams, { dash_strategy = "auto_min" })
  assert_true(selected and not err, "auto_min must select streams")
  assert_true(selected.selected_video_id == "v540", "auto_min must choose min video bitrate")
  assert_true(selected.selected_audio_id == "a64", "auto_min must choose min audio bitrate")
end

do
  local selected, err = dash_select_streams(streams, {
    dash_strategy = "fixed_id",
    dash_representation_id = "v540",
    dash_audio_id = "a64",
  })
  assert_true(selected and not err, "fixed_id must select streams")
  assert_true(selected.selected_video_id == "v540", "fixed_id must keep requested video id")
  assert_true(selected.selected_audio_id == "a64", "fixed_id must keep requested audio id")
end

do
  local selected, err = dash_select_streams(streams, {
    dash_strategy = "res_limit",
    dash_max_height = 720,
  })
  assert_true(selected and not err, "res_limit must select streams")
  assert_true(selected.selected_video_id == "v540", "res_limit must choose best stream within max height")
end

do
  local selected, err = dash_select_streams(streams, {
    dash_strategy = "fixed_id",
    dash_representation_id = "",
  })
  assert_true(selected == nil and tostring(err):find("requires dash_representation_id", 1, true) ~= nil,
    "fixed_id without representation id must fail")
end

print("dash_probe_select_unit: ok")
astra.exit()
