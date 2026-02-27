log.set({ debug = true })

dofile("scripts/base.lua")
dofile("scripts/config.lua")
dofile("scripts/transcode.lua")

local function assert_true(v, msg)
  if not v then
    error(msg or "assert")
  end
end

local root = "/tmp/transcode_status_lite_output_errors_unit"
os.execute("rm -rf " .. root .. " >/dev/null 2>&1 || true")
os.execute("mkdir -p " .. root)

config.init({
  data_dir = root,
  db_path = root .. "/stream.db",
})

local row = {
  enabled = 0,
  config_json = "{}",
  config = {
    id = "tc_lite_errors",
    name = "tc_lite_errors",
    input = { "udp://239.0.0.1:1234" },
    transcode = {
      enabled = true,
      process_per_output = true,
      outputs = {
        { url = "udp://127.0.0.1:10001", watchdog = {} },
        { url = "udp://127.0.0.1:10002", watchdog = {} },
      },
      watchdog = {},
    },
  },
}

local job = transcode.upsert("tc_lite_errors", row, true)
assert_true(type(job) == "table", "job expected")
assert_true(type(job.output_monitors) == "table" and #job.output_monitors >= 2, "output monitors expected")

local now = os.time()
job.output_monitors[1].cc_errors = 7
job.output_monitors[1].pes_errors = 3
job.output_monitors[1].cc_errors_ts = now - 2
job.output_monitors[1].pes_errors_ts = now - 2
job.output_monitors[1].scrambled_active = false

job.output_monitors[2].cc_errors = 2
job.output_monitors[2].pes_errors = 1
job.output_monitors[2].cc_errors_ts = now
job.output_monitors[2].pes_errors_ts = now
job.output_monitors[2].scrambled_active = true

local lite = transcode.get_status_lite("tc_lite_errors")
assert_true(type(lite) == "table", "lite status expected")
assert_true(tonumber(lite.output_cc_errors) == 9, "output_cc_errors sum mismatch")
assert_true(tonumber(lite.output_pes_errors) == 4, "output_pes_errors sum mismatch")
assert_true(lite.output_scrambled == true, "output_scrambled should be true")
assert_true(tonumber(lite.updated_at) and tonumber(lite.updated_at) >= now, "updated_at should include monitor timestamps")

log.info("[unit] transcode_status_lite_output_errors_unit ok")
astra.exit()

