log.set({ debug = true })

dofile("scripts/base.lua")

local function assert_true(v, msg)
  if not v then
    error(msg or "assert")
  end
end

if not process or type(process.spawn) ~= "function" then
  log.warning("[unit] process_spawn_env_unit skipped (process module missing)")
  astra.exit()
end

local env_bin = "env"
if utils and type(utils.stat) == "function" then
  local st = utils.stat("/usr/bin/env")
  if st and st.type == "file" then
    env_bin = "/usr/bin/env"
  else
    local st2 = utils.stat("/bin/env")
    if st2 and st2.type == "file" then
      env_bin = "/bin/env"
    end
  end
end

-- Ensure env passed to the child does not leak into parent.
assert_true(os.getenv("ASTRA_TEST_ENV") == nil, "expected ASTRA_TEST_ENV unset in parent")

local ok, proc = pcall(process.spawn, { env_bin }, {
  stdout = "pipe",
  stderr = "pipe",
  env = {
    ASTRA_TEST_ENV = "hello",
  },
})
assert_true(ok and proc, "spawn failed")

local stdout = ""
local stderr = ""
local exit_status = nil
for _ = 1, 200 do
  local chunk = proc:read_stdout()
  if chunk then
    stdout = stdout .. chunk
  end
  local err_chunk = proc:read_stderr()
  if err_chunk then
    stderr = stderr .. err_chunk
  end
  local status = proc:poll()
  if status then
    exit_status = status
    -- Drain remaining stdout after exit.
    for _ = 1, 2000 do
      local rest = proc:read_stdout()
      if not rest then
        break
      end
      stdout = stdout .. rest
    end
    -- Drain remaining stderr after exit.
    for _ = 1, 2000 do
      local rest = proc:read_stderr()
      if not rest then
        break
      end
      stderr = stderr .. rest
    end
    break
  end
  -- Yield so the child process has time to run.
  os.execute("sleep 0.01")
end

if stdout:find("ASTRA_TEST_ENV=hello", 1, true) == nil then
  log.error("[unit] env debug: bin=" .. tostring(env_bin) ..
    " exit=" .. tostring(exit_status and exit_status.exit_code) ..
    " signal=" .. tostring(exit_status and exit_status.signal) ..
    " stdout_len=" .. tostring(#stdout) ..
    " stderr_len=" .. tostring(#stderr))
  if stderr and stderr ~= "" then
    log.error("[unit] env stderr (first 200): " .. stderr:sub(1, 200))
  end
  if stdout and stdout ~= "" then
    log.error("[unit] env stdout (first 200): " .. stdout:sub(1, 200))
  end
  error("env var not found in child output")
end
assert_true(os.getenv("ASTRA_TEST_ENV") == nil, "env leaked into parent")

log.info("[unit] process_spawn_env_unit ok")
astra.exit()
