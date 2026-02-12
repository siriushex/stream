log.set({ debug = true })

dofile("scripts/base.lua")
dofile("scripts/config.lua")
dofile("scripts/transcode.lua")

config.init({
  data_dir = "/tmp/transcode_recovery_unit_data",
  db_path = "/tmp/transcode_recovery_unit_data/transcode_recovery_unit.db",
})

local function assert_true(v, msg)
  if not v then
    error(msg or "assert")
  end
end

-- Helper: build a stopped transcode job (no ffmpeg processes spawned).
local function build_job(id, watchdog)
  local cfg = {
    id = id,
    name = "unit " .. id,
    input = { "udp://239.0.0.1:1234" },
    transcode = {
      enabled = true,
      process_per_output = true,
      outputs = {
        { url = "udp://127.0.0.1:12345" },
      },
      watchdog = watchdog or {},
    },
  }
  local row = { enabled = 0, config = cfg, config_json = "{}" }
  local job = transcode.upsert(id, row, true)
  assert_true(job ~= nil, "expected job")
  assert_true(job.process_per_output == true, "expected process_per_output")
  assert_true(type(job.workers) == "table" and job.workers[1], "expected worker")
  return job
end

-- Forced restart after suppression should bypass cooldown.
do
  local job = build_job("tc_force", {
    restart_cooldown_critical_sec = 1000,
    restart_force_after_sec = 45,
    max_restarts_per_10min = 10,
  })
  local worker = job.workers[1]
  worker.state = "RUNNING"

  local now = os.time()
  worker.last_restart_ts = now
  worker.restart_suppressed_since_ts = now - 46
  worker.restart_suppressed_count = 3

  local ok = transcode.restart(job, "manual")
  assert_true(ok == true, "expected forced restart")
  assert_true(worker.state == "RESTARTING", "worker should be RESTARTING")
  assert_true(worker.last_forced_restart_ts ~= nil, "expected last_forced_restart_ts")
end

-- Restart limit should mark ERROR and set rearm timestamp (if configured).
do
  local job = build_job("tc_limit", {
    max_restarts_per_10min = 1,
    error_rearm_sec = 10,
    restart_cooldown_critical_sec = 0,
  })
  local worker = job.workers[1]
  worker.state = "RUNNING"

  local now = os.time()
  worker.restart_history = { now }

  local ok = transcode.restart(job, "manual")
  assert_true(ok == false, "expected restart blocked by limit")
  assert_true(worker.state == "ERROR", "expected worker ERROR")
  assert_true(worker.error_rearm_ts ~= nil, "expected error_rearm_ts")
end

log.info("[unit] transcode_recovery_unit ok")
astra.exit()

