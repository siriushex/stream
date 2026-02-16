log.set({ debug = true })

dofile("scripts/base.lua")
dofile("scripts/transcode.lua")

local function assert_eq(actual, expected, label)
  if actual ~= expected then
    error(string.format("%s: expected %s, got %s", tostring(label or "assert"), tostring(expected), tostring(actual)))
  end
end

local function assert_true(v, msg)
  if not v then
    error(msg or "assert")
  end
end

-- Explicit probe interval must always win.
do
  local interval = transcode._resolve_failover_probe_interval({
    mode = "active_stop_if_all_inactive",
    global_state = "INACTIVE",
    probe_interval = 7,
    no_data_timeout = 3,
  })
  assert_eq(interval, 7, "explicit probe_interval")
end

-- Inactive safety net: with probe_interval=0 we still probe to auto-recover.
do
  local interval = transcode._resolve_failover_probe_interval({
    mode = "active_stop_if_all_inactive",
    global_state = "INACTIVE",
    probe_interval = 0,
    no_data_timeout = 3,
  })
  assert_eq(interval, 3, "inactive rescue probe")
end

-- Clamp rescue interval lower bound.
do
  local interval = transcode._resolve_failover_probe_interval({
    mode = "active_stop_if_all_inactive",
    global_state = "INACTIVE",
    probe_interval = 0,
    no_data_timeout = 0,
  })
  assert_eq(interval, 1, "inactive rescue lower clamp")
end

-- Clamp rescue interval upper bound.
do
  local interval = transcode._resolve_failover_probe_interval({
    mode = "active_stop_if_all_inactive",
    global_state = "INACTIVE",
    probe_interval = 0,
    no_data_timeout = 99,
  })
  assert_eq(interval, 10, "inactive rescue upper clamp")
end

-- Outside INACTIVE state and probe_interval=0 -> no probes.
do
  local interval = transcode._resolve_failover_probe_interval({
    mode = "active_stop_if_all_inactive",
    global_state = "RUNNING",
    probe_interval = 0,
    no_data_timeout = 3,
  })
  assert_eq(interval, 0, "running no probe when interval disabled")
end

-- Non-table guard.
do
  local interval = transcode._resolve_failover_probe_interval(nil)
  assert_true(interval == 0, "nil input should return 0")
end

log.info("[unit] transcode_failover_probe_interval_unit ok")
astra.exit()
