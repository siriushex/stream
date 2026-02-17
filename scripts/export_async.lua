-- Stream async config export queue.
--
-- Goal: keep primary config JSON + LKG + revision snapshots updated without
-- blocking the main event loop (Lua chunk) on big configs.
--
-- This module intentionally sets a global (`stream_export_async`) to avoid
-- adding more locals to scripts/api.lua (Lua has a hard limit of 200 locals
-- per function/chunk).

stream_export_async = stream_export_async or {}

local M = stream_export_async

M._state = M._state or {
    pending = nil,
    timer = nil,
    poll_timer = nil,
    fallback_timer = nil,
    fallback_last_ts = 0,
    proc = nil,
    proc_started_ts = nil,
    stdout_tail = "",
    stderr_tail = "",
    worker_unavailable_logged = false,
    worker_disabled = false,
}

local function detect_script_dir()
    local dbg = _G and _G.debug or nil
    if type(dbg) ~= "table" or type(dbg.getinfo) ~= "function" then
        return nil
    end
    local info = dbg.getinfo(1, "S")
    if not info or not info.source then
        return nil
    end
    local src = tostring(info.source or "")
    if src:sub(1, 1) == "@" then
        src = src:sub(2)
    end
    local dir = src:match("^(.*[/\\])")
    if not dir or dir == "" then
        return nil
    end
    if dir:sub(-1) == "/" or dir:sub(-1) == "\\" then
        dir = dir:sub(1, -2)
    end
    return (dir ~= "" and dir) or nil
end

local EXPORT_ASYNC_DIR = detect_script_dir()

local function path_join(base, leaf)
    local b = tostring(base or "")
    local l = tostring(leaf or "")
    if b == "" then
        return l
    end
    if l == "" then
        return b
    end
    local tail = b:sub(-1)
    if tail == "/" or tail == "\\" then
        return b .. l
    end
    return b .. "/" .. l
end

local function resolve_self_bin()
    local function trim(value)
        local text = tostring(value or "")
        text = text:gsub("^%s+", ""):gsub("%s+$", "")
        if text == "" then
            return nil
        end
        return text
    end

    local function shell_escape(value)
        return "'" .. tostring(value or ""):gsub("'", "'\\''") .. "'"
    end

    local function is_exec_ok(result)
        return result == true or result == 0
    end

    local function is_executable(path)
        path = trim(path)
        if not path then
            return false
        end
        local ok, res = pcall(os.execute, "test -x " .. shell_escape(path) .. " >/dev/null 2>&1")
        if not ok then
            return false
        end
        return is_exec_ok(res)
    end

    local function command_output(cmd)
        if not io or type(io.popen) ~= "function" then
            return nil
        end
        local ok, handle = pcall(io.popen, cmd)
        if not ok then
            return nil
        end
        if not handle then
            return nil
        end
        local out = handle:read("*a")
        handle:close()
        return trim(out)
    end

    local candidate = nil
    if _G.argv and _G.argv[0] then
        candidate = trim(_G.argv[0])
    elseif arg and arg[0] then
        candidate = trim(arg[0])
    end

    -- Absolute invocation path is the most reliable option for child workers.
    if candidate and candidate:sub(1, 1) == "/" and is_executable(candidate) then
        return candidate
    end

    -- Some deployments launch stream via PATH ("stream"), while helper workers
    -- may run with a minimal PATH. Prefer common install paths explicitly.
    local known_bins = {
        "/usr/local/bin/stream",
        "/usr/bin/stream",
    }
    for _, known in ipairs(known_bins) do
        if is_executable(known) then
            return known
        end
    end

    -- Linux fast path: current executable.
    local proc_exe = command_output("readlink -f /proc/self/exe 2>/dev/null")
    if proc_exe and is_executable(proc_exe) then
        return proc_exe
    end

    -- Resolve argv basename via PATH if available.
    if candidate then
        local resolved = command_output("command -v " .. shell_escape(candidate) .. " 2>/dev/null")
        if resolved and is_executable(resolved) then
            return resolved
        end
    end

    local fallback = command_output("command -v stream 2>/dev/null")
    if fallback and is_executable(fallback) then
        return fallback
    end

    return nil
end

local nice_cache = nil
local ionice_cache = nil

local function can_nice()
    if nice_cache ~= nil then
        return nice_cache
    end
    if package and package.config and package.config:sub(1, 1) == "\\" then
        nice_cache = false
        return false
    end
    local ok = os.execute("command -v nice >/dev/null 2>&1")
    nice_cache = (ok == true or ok == 0)
    return nice_cache
end

local function can_ionice()
    if ionice_cache ~= nil then
        return ionice_cache
    end
    if package and package.config and package.config:sub(1, 1) == "\\" then
        ionice_cache = false
        return false
    end
    local ok = os.execute("command -v ionice >/dev/null 2>&1")
    ionice_cache = (ok == true or ok == 0)
    return ionice_cache
end

local function with_nice(argv)
    if not argv or type(argv) ~= "table" then
        return argv
    end
    if not can_nice() then
        return argv
    end
    local out = { "nice", "-n", "10" }
    for i = 1, #argv do
        out[#out + 1] = argv[i]
    end
    return out
end

local function with_ionice(argv)
    if not argv or type(argv) ~= "table" then
        return argv
    end
    if not can_ionice() then
        return argv
    end
    -- Best-effort IO deprioritization (does not require root on most distros).
    local out = { "ionice", "-c2", "-n", "7" }
    for i = 1, #argv do
        out[#out + 1] = argv[i]
    end
    return out
end

local function with_low_priority(argv)
    argv = with_nice(argv)
    argv = with_ionice(argv)
    return argv
end

local EXPORT_FALLBACK_INTERVAL_DEFAULT_SEC = 30
local EXPORT_FALLBACK_INTERVAL_MAX_SEC = 300

local function fallback_interval_sec(cfg)
    local raw = nil
    if cfg and type(cfg.get_setting) == "function" then
        raw = cfg.get_setting("export_async_fallback_interval_sec")
    end
    local interval = tonumber(raw)
    if interval == nil then
        interval = EXPORT_FALLBACK_INTERVAL_DEFAULT_SEC
    end
    if interval < 0 then
        interval = 0
    end
    if interval > EXPORT_FALLBACK_INTERVAL_MAX_SEC then
        interval = EXPORT_FALLBACK_INTERVAL_MAX_SEC
    end
    return interval
end

local function append_tail(prev, chunk, limit)
    if not chunk or chunk == "" then
        return prev or ""
    end
    local out = (prev or "") .. chunk
    limit = tonumber(limit) or 8192
    if #out > limit then
        out = out:sub(#out - limit + 1)
    end
    return out
end

local function merge_export_paths(dst, src)
    if not src then
        return dst
    end
    dst = dst or {}
    if src.primary_path and src.primary_path ~= "" then
        dst.primary_path = src.primary_path
    end
    if src.lkg_path and src.lkg_path ~= "" then
        dst.lkg_path = src.lkg_path
    end
    if src.snapshot_path and src.snapshot_path ~= "" then
        dst.snapshot_path = src.snapshot_path
    end
    return dst
end

local function is_readable_file(path)
    local p = tostring(path or "")
    if p == "" then
        return false
    end
    if not io or type(io.open) ~= "function" then
        return nil
    end
    local ok, handle = pcall(io.open, p, "rb")
    if not ok then
        return false
    end
    if not handle then
        return false
    end
    handle:close()
    return true
end

local function read_text_file(path)
    local p = tostring(path or "")
    if p == "" then
        return nil
    end
    if not io or type(io.open) ~= "function" then
        return nil
    end
    local ok, handle = pcall(io.open, p, "rb")
    if not ok or not handle then
        return nil
    end
    local body = handle:read("*a")
    handle:close()
    if type(body) ~= "string" or body == "" then
        return nil
    end
    return body
end

local function worker_script_candidates(script_name)
    local out = {
        "/usr/local/share/stream/scripts/" .. script_name,
        "/usr/share/stream/scripts/" .. script_name,
    }
    if EXPORT_ASYNC_DIR and EXPORT_ASYNC_DIR ~= "" then
        table.insert(out, 1, path_join(EXPORT_ASYNC_DIR, script_name))
    end
    local self_bin = resolve_self_bin()
    local bin_dir = tostring(self_bin or ""):match("^(.*)/[^/]+$")
    if bin_dir and bin_dir ~= "" then
        out[#out + 1] = bin_dir .. "/../share/stream/scripts/" .. script_name
    end
    return out
end

local function resolve_worker_script_path(script_name)
    local candidates = worker_script_candidates(script_name)
    for _, path in ipairs(candidates) do
        local readable = is_readable_file(path)
        if readable == true then
            return path
        end
        if readable == nil then
            return path
        end
    end
    return nil
end

local function built_in_export_worker_source()
    local base_script = resolve_worker_script_path("base.lua") or "scripts/base.lua"
    local config_script = resolve_worker_script_path("config.lua") or "scripts/config.lua"
    return string.format([=[
-- Stream export helper generated by export_async.lua.
dofile(%q)
dofile(%q)

local opt = {
    data_dir = "./data",
    db_path = nil,
    primary = nil,
    lkg = nil,
    snapshot = nil,
}

options_usage = [[
    --data-dir PATH     data directory (default: ./data)
    --db PATH           sqlite db path (default: data-dir/stream.db)
    --primary PATH      write primary config json (optional)
    --lkg PATH          write LKG snapshot json (optional)
    --snapshot PATH     write revision snapshot json (optional)
]]

options = {
    ["--data-dir"] = function(idx)
        opt.data_dir = argv[idx + 1]
        return 1
    end,
    ["--db"] = function(idx)
        opt.db_path = argv[idx + 1]
        return 1
    end,
    ["--primary"] = function(idx)
        opt.primary = argv[idx + 1]
        return 1
    end,
    ["--lkg"] = function(idx)
        opt.lkg = argv[idx + 1]
        return 1
    end,
    ["--snapshot"] = function(idx)
        opt.snapshot = argv[idx + 1]
        return 1
    end,
}

local function want_outputs()
    return (opt.primary and opt.primary ~= "")
        or (opt.lkg and opt.lkg ~= "")
        or (opt.snapshot and opt.snapshot ~= "")
end

local function write_one(path, payload, encoded, label)
    if not path or path == "" then
        return true
    end
    local ok, err = config.export_astra_file(path, { payload = payload, encoded = encoded })
    if not ok then
        log.error("[export] write failed (" .. tostring(label) .. "): " .. tostring(err))
        return nil, err
    end
    return true
end

function main()
    if not want_outputs() then
        log.error("[export] no outputs specified")
        os.exit(2)
    end

    config.init({
        data_dir = opt.data_dir,
        db_path = opt.db_path,
    })
    if opt.primary and opt.primary ~= "" and config.set_primary_config_path then
        config.set_primary_config_path(opt.primary)
    end

    local payload, encoded = config.export_astra_encoded()

    local ok, err = write_one(opt.primary, payload, encoded, "primary")
    if not ok then
        log.error("[export] failed: " .. tostring(err))
        os.exit(1)
    end

    ok, err = write_one(opt.snapshot, payload, encoded, "snapshot")
    if not ok then
        log.error("[export] failed: " .. tostring(err))
        os.exit(1)
    end

    ok, err = write_one(opt.lkg, payload, encoded, "lkg")
    if not ok then
        log.error("[export] failed: " .. tostring(err))
        os.exit(1)
    end

    astra.exit()
end
]=], base_script, config_script)
end

local function materialize_worker_source(cfg, source)
    if type(source) ~= "string" or source == "" then
        return nil
    end
    if not io or type(io.open) ~= "function" then
        return nil
    end
    local targets = {}
    if cfg and cfg.data_dir and cfg.data_dir ~= "" then
        targets[#targets + 1] = path_join(cfg.data_dir, ".stream-export-write.lua")
    end
    targets[#targets + 1] = "/tmp/.stream-export-write.lua"
    for _, target in ipairs(targets) do
        local ok, handle = pcall(io.open, target, "wb")
        if ok and handle then
            local write_ok = pcall(function()
                handle:write(source)
                handle:close()
            end)
            if write_ok and is_readable_file(target) ~= false then
                return target
            end
        end
    end
    return nil
end

local function materialize_embedded_export_worker(cfg)
    local embedded = nil
    if utils and type(utils.embedded_read) == "function" then
        embedded = utils.embedded_read("scripts/export_write.lua")
    end
    if type(embedded) ~= "string" or embedded == "" then
        local src = resolve_worker_script_path("export_write.lua")
        if src then
            embedded = read_text_file(src)
        end
    end
    if type(embedded) ~= "string" or embedded == "" then
        embedded = built_in_export_worker_source()
    end
    return materialize_worker_source(cfg, embedded)
end

local function resolve_export_worker_script(cfg)
    local embedded_fallback = "scripts/export_write.lua"
    local resolved = resolve_worker_script_path("export_write.lua")
    if resolved then
        return resolved
    end
    local extracted = materialize_embedded_export_worker(cfg)
    if extracted and extracted ~= "" then
        return extracted
    end
    -- Embedded assets mode: helper script may be available inside the binary
    -- without a real file on disk. Keep this fallback so worker mode still works.
    return embedded_fallback
end

local run_pending_job = nil
local schedule_inprocess_fallback = nil

local function worker_cwd(helper_script, cfg)
    local script = tostring(helper_script or "")
    local root = script:match("^(.*)/scripts/[^/]+$")
    if root and root ~= "" then
        return root
    end
    local data_dir = cfg and tostring(cfg.data_dir or "") or ""
    if data_dir ~= "" then
        return data_dir
    end
    return nil
end

local function spawn_job(paths, cfg)
    if not paths or type(paths) ~= "table" then
        return nil
    end
    if not cfg or not cfg.data_dir or not cfg.db_path then
        return nil
    end
    if not process or type(process.spawn) ~= "function" then
        log.warning("[export_async] skipped: process module unavailable")
        return nil
    end

    local helper_script = resolve_export_worker_script(cfg)
    if not helper_script or helper_script == "" then
        return nil, "export helper script is unavailable"
    end

    local self_bin = resolve_self_bin()
    if not self_bin or self_bin == "" then
        return nil, "stream binary is unavailable"
    end

    local argv = {
        self_bin,
        helper_script,
        "--data-dir", tostring(cfg.data_dir),
        "--db", tostring(cfg.db_path),
    }
    if paths.primary_path and paths.primary_path ~= "" then
        argv[#argv + 1] = "--primary"
        argv[#argv + 1] = tostring(paths.primary_path)
    end
    if paths.lkg_path and paths.lkg_path ~= "" then
        argv[#argv + 1] = "--lkg"
        argv[#argv + 1] = tostring(paths.lkg_path)
    end
    if paths.snapshot_path and paths.snapshot_path ~= "" then
        argv[#argv + 1] = "--snapshot"
        argv[#argv + 1] = tostring(paths.snapshot_path)
    end
    if #argv <= 6 then
        return nil
    end

    argv = with_low_priority(argv)
    local spawn_opts = {
        stdout = "pipe",
        stderr = "pipe",
    }
    local cwd = worker_cwd(helper_script, cfg)
    if cwd and cwd ~= "" then
        spawn_opts.cwd = cwd
    end
    local ok, proc_or_err = pcall(process.spawn, argv, spawn_opts)
    if not ok or not proc_or_err then
        local detail = ok and "process.spawn returned nil" or tostring(proc_or_err)
        return nil, "spawn failed: " .. tostring(detail)
    end
    local proc = proc_or_err

    local s = M._state
    s.proc = proc
    s.proc_started_ts = os.time()
    s.stdout_tail = ""
    s.stderr_tail = ""

    if s.poll_timer then
        s.poll_timer:close()
        s.poll_timer = nil
    end

    if timer then
        s.poll_timer = timer({
            interval = 0.2,
            callback = function(self)
                local state = M._state
                local p = state.proc
                if not p then
                    self:close()
                    state.poll_timer = nil
                    return
                end

                state.stdout_tail = append_tail(state.stdout_tail, p:read_stdout(), 8192)
                state.stderr_tail = append_tail(state.stderr_tail, p:read_stderr(), 8192)

                local st = p:poll()
                if not st then
                    local started = tonumber(state.proc_started_ts) or os.time()
                    if (os.time() - started) > 60 then
                        log.error("[export_async] timeout; killing worker")
                        pcall(function() p:kill() end)
                    end
                    return
                end

                local exit_code = tonumber(st.exit_code) or 0
                local signal = tonumber(st.signal) or 0
                pcall(function() p:close() end)
                state.proc = nil
                state.proc_started_ts = nil

                local stderr_tail = tostring(state.stderr_tail or "")
                local stderr_lower = stderr_tail:lower()
                local missing_file = stderr_lower:find("no such file", 1, true) ~= nil
                    or stderr_lower:find("not found", 1, true) ~= nil
                local missing_helper = missing_file
                    and stderr_lower:find("export_write.lua", 1, true) ~= nil
                local missing_worker_bin = (exit_code == 126 or exit_code == 127) and missing_file
                if missing_helper or missing_worker_bin then
                    state.worker_disabled = true
                    if not state.worker_unavailable_logged then
                        log.warning("[export_async] worker disabled after worker exit=" .. tostring(exit_code) ..
                            "; using in-process fallback")
                        state.worker_unavailable_logged = true
                    end
                end

                if exit_code ~= 0 or signal ~= 0 then
                    log.error(string.format("[export_async] failed: exit=%d signal=%d stderr_tail=%s",
                        exit_code, signal, stderr_tail))
                end

                self:close()
                state.poll_timer = nil

                local next_paths = state.pending
                state.pending = nil
                if next_paths then
                    run_pending_job(next_paths, cfg)
                end
            end,
        })
    end

    return true
end

local function run_export_inprocess(paths, cfg)
    if not paths or type(paths) ~= "table" then
        return true
    end
    if not cfg then
        return nil, "config is unavailable"
    end
    if type(cfg.export_astra_file) ~= "function" then
        return nil, "config export writer is unavailable"
    end

    local payload = nil
    local encoded = nil
    if type(cfg.export_astra_encoded) == "function" then
        local ok, p, e = pcall(cfg.export_astra_encoded)
        if not ok then
            return nil, tostring(p)
        end
        payload = p
        encoded = e
    elseif type(cfg.export_astra) == "function" then
        local ok, p = pcall(cfg.export_astra)
        if not ok then
            return nil, tostring(p)
        end
        payload = p
        if json and type(json.encode_pretty) == "function" then
            encoded = json.encode_pretty(payload)
        else
            encoded = json.encode(payload)
        end
    else
        return nil, "config export encoder is unavailable"
    end

    local function write_target(path)
        if not path or path == "" then
            return true
        end
        local ok, err = cfg.export_astra_file(path, {
            payload = payload,
            encoded = encoded,
        })
        if not ok then
            return nil, err or ("write failed: " .. tostring(path))
        end
        return true
    end

    local ok, err = write_target(paths.primary_path)
    if not ok then return nil, err end
    ok, err = write_target(paths.snapshot_path)
    if not ok then return nil, err end
    ok, err = write_target(paths.lkg_path)
    if not ok then return nil, err end

    return true
end

schedule_inprocess_fallback = function(paths, cfg)
    local state = M._state
    if paths and type(paths) == "table" then
        state.pending = merge_export_paths(state.pending, paths)
    end

    if not timer then
        local next_paths = state.pending
        state.pending = nil
        if not next_paths then
            return true
        end
        local done, fallback_err = run_export_inprocess(next_paths, cfg)
        state.fallback_last_ts = os.time()
        if not done then
            log.error("[export_async] in-process fallback failed: " .. tostring(fallback_err))
        end
        if state.pending then
            return schedule_inprocess_fallback(nil, cfg)
        end
        return true
    end

    if state.fallback_timer then
        return true
    end

    local delay = 0.2
    local min_interval = fallback_interval_sec(cfg)
    if min_interval > 0 then
        local now = os.time()
        local last = tonumber(state.fallback_last_ts) or 0
        if last > 0 then
            local elapsed = now - last
            if elapsed < min_interval then
                delay = math.max(delay, min_interval - elapsed)
            end
        end
    end

    state.fallback_timer = timer({
        interval = delay,
        callback = function(self)
            self:close()
            local st = M._state
            st.fallback_timer = nil
            local next_paths = st.pending
            st.pending = nil
            if not next_paths then
                return
            end
            local done, fallback_err = run_export_inprocess(next_paths, cfg)
            st.fallback_last_ts = os.time()
            if not done then
                log.error("[export_async] in-process fallback failed: " .. tostring(fallback_err))
            end
            if st.pending then
                schedule_inprocess_fallback(nil, cfg)
            end
        end,
    })
    return true
end

run_pending_job = function(paths, cfg)
    if not paths then
        return true
    end

    local state = M._state
    if not state.worker_disabled then
        local ok, err = spawn_job(paths, cfg)
        if ok then
            return true
        end
        local text = tostring(err or "spawn failed")
        if text:find("unavailable", 1, true) ~= nil
            or text:find("No such file", 1, true) ~= nil
            or text:find("not found", 1, true) ~= nil
        then
            state.worker_disabled = true
        end
        if not state.worker_unavailable_logged then
            log.warning("[export_async] worker unavailable; using in-process fallback: " .. text)
            state.worker_unavailable_logged = true
        end
    else
        -- Worker path was already deemed unavailable for this process lifecycle.
        -- Keep config apply fast by using in-process export directly.
        if not state.worker_unavailable_logged then
            log.warning("[export_async] worker disabled; using in-process fallback")
            state.worker_unavailable_logged = true
        end
    end

    return schedule_inprocess_fallback(paths, cfg)
end

function M.request(paths, cfg)
    cfg = cfg or config
    if not cfg or cfg.is_primary_writer ~= true then
        return nil
    end

    local s = M._state
    s.pending = merge_export_paths(s.pending, paths)

    if s.proc then
        return true
    end
    if s.timer then
        return true
    end

    if not timer then
        local next_paths = s.pending
        s.pending = nil
        return run_pending_job(next_paths, cfg)
    end

    s.timer = timer({
        interval = 0.5,
        callback = function(self)
            self:close()
            local state = M._state
            state.timer = nil
            if state.proc then
                return
            end
            local next_paths = state.pending
            state.pending = nil
            if next_paths then
                run_pending_job(next_paths, cfg)
            end
        end,
    })
    return true
end

return M
