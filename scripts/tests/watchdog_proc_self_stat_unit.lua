log.set({ debug = true })

dofile("scripts/base.lua")
dofile("scripts/watchdog.lua")

local function assert_eq(a, b, msg)
  if a ~= b then
    error((msg or "assert_eq failed") .. ": got=" .. tostring(a) .. " want=" .. tostring(b))
  end
end

-- Ensure /proc/self/stat parsing uses utime+stime (not stime+cutime).
do
  local line = "12345 (stream) R 1 2 3 4 5 6 7 8 9 10 111 222 333 444 17 18 19 20 21 22"
  local ticks = watchdog._parse_proc_self_time_line(line)
  assert_eq(ticks, 333, "expected utime+stime ticks")
end

log.info("[unit] watchdog_proc_self_stat_unit ok")
astra.exit()
