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
    proc = nil,
    proc_started_ts = nil,
    stdout_tail = "",
    stderr_tail = "",
}

local function resolve_self_bin()
    if _G.argv and _G.argv[0] then
        return _G.argv[0]
    end
    if arg and arg[0] then
        return arg[0]
    end
    return "stream"
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

    local argv = {
        resolve_self_bin(),
        "scripts/export_write.lua",
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

    local ok, proc = pcall(process.spawn, argv, {
        stdout = "pipe",
        stderr = "pipe",
        cwd = tostring(cfg.data_dir),
    })
    if not ok or not proc then
        log.error("[export_async] spawn failed")
        return nil
    end

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

                if exit_code ~= 0 or signal ~= 0 then
                    log.error(string.format("[export_async] failed: exit=%d signal=%d stderr_tail=%s",
                        exit_code, signal, tostring(state.stderr_tail or "")))
                end

                self:close()
                state.poll_timer = nil

                local next_paths = state.pending
                state.pending = nil
                if next_paths then
                    spawn_job(next_paths, cfg)
                end
            end,
        })
    end

    return true
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
        return spawn_job(next_paths, cfg)
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
                spawn_job(next_paths, cfg)
            end
        end,
    })
    return true
end

return M

