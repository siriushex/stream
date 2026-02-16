log.set({ debug = true })

dofile("scripts/base.lua")
dofile("scripts/config.lua")
dofile("scripts/transcode.lua")

config.init({
  data_dir = "/tmp/transcode_watchdog_defaults_unit_data",
  db_path = "/tmp/transcode_watchdog_defaults_unit_data/transcode_watchdog_defaults_unit.db",
})

local function assert_true(v, msg)
  if not v then
    error(msg or "assert")
  end
end

local function build_job(id, tc_watchdog, out_watchdog)
  local cfg = {
    id = id,
    name = "unit " .. id,
    input = { "udp://239.0.0.1:1234" },
    transcode = {
      enabled = true,
      process_per_output = true,
      outputs = {
        {
          url = "udp://127.0.0.1:12345",
          watchdog = out_watchdog,
        },
      },
      watchdog = tc_watchdog or {},
    },
  }
  local row = { enabled = 0, config = cfg, config_json = "{}" }
  local job = transcode.upsert(id, row, true)
  assert_true(job ~= nil, "expected job")
  assert_true(type(job.workers) == "table" and job.workers[1], "expected worker")
  return job
end

-- Default behavior: critical cooldown stays low (30s) and auto-rearm is enabled (120s).
do
  local job = build_job("tc_wd_default")
  local worker = job.workers[1]
  assert_true(job.watchdog.restart_cooldown_critical_sec == 30, "job critical cooldown default must be 30")
  assert_true(worker.watchdog.restart_cooldown_critical_sec == 30, "worker critical cooldown default must be 30")
  assert_true(job.watchdog.error_rearm_sec == 120, "job error_rearm default must be 120")
  assert_true(worker.watchdog.error_rearm_sec == 120, "worker error_rearm default must be 120")
end

-- If restart_cooldown_sec explicitly set (legacy contract), critical cooldown inherits it.
do
  local job = build_job("tc_wd_legacy_base", {
    restart_cooldown_sec = 180,
  })
  local worker = job.workers[1]
  assert_true(job.watchdog.restart_cooldown_critical_sec == 180, "job critical should inherit explicit cooldown")
  assert_true(worker.watchdog.restart_cooldown_critical_sec == 180, "worker critical should inherit explicit cooldown")
end

-- Output-level restart_cooldown_sec affects quality lane, while critical lane
-- keeps the global default unless explicitly overridden.
do
  local job = build_job("tc_wd_output_override", nil, {
    restart_cooldown_sec = 90,
  })
  local worker = job.workers[1]
  assert_true(worker.watchdog.restart_cooldown_sec == 90, "worker base cooldown override expected")
  assert_true(worker.watchdog.restart_cooldown_critical_sec == 30, "worker critical should use global critical lane default")
end

log.info("[unit] transcode_watchdog_defaults_unit ok")
astra.exit()
