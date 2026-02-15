-- Create radio: audio stream + PNG -> UDP MPEG-TS (ffmpeg)

radio = {}
radio.jobs = {}

local function now_ts()
    return os.time()
end

local function clamp_int(value, min_value, max_value, fallback)
    local n = tonumber(value)
    if not n then
        return fallback
    end
    n = math.floor(n + 0.0)
    if min_value ~= nil and n < min_value then
        n = min_value
    end
    if max_value ~= nil and n > max_value then
        n = max_value
    end
    return n
end

local function clamp_number(value, min_value, max_value, fallback)
    local n = tonumber(value)
    if not n then
        return fallback
    end
    if min_value ~= nil and n < min_value then
        n = min_value
    end
    if max_value ~= nil and n > max_value then
        n = max_value
    end
    return n
end

local function ensure_dir(path)
    local stat = utils and utils.stat and utils.stat(path) or nil
    if not stat or stat.type ~= "directory" then
        os.execute("mkdir -p " .. path)
    end
end

local function file_exists(path)
    if not path or path == "" then return false end
    local stat = utils and utils.stat and utils.stat(path) or nil
    return stat and stat.type == "file"
end

local function shell_escape(value)
    local text = tostring(value or "")
    return "'" .. text:gsub("'", "'\\''") .. "'"
end

local function sanitize_id(value)
    local raw = tostring(value or "")
    local clean = raw:gsub("[^%w%-%_]", "_")
    if clean == "" then
        clean = "stream"
    end
    return clean
end

local function decode_data_url(data_url, allowed_prefix)
    if not data_url or data_url == "" then
        return nil, nil, "empty data url"
    end
    local header, b64 = data_url:match("^data:([^,]+),(.+)$")
    if not header or not b64 then
        return nil, nil, "invalid data url"
    end
    if allowed_prefix and not header:find(allowed_prefix, 1, true) then
        return nil, nil, "unexpected mime type"
    end
    local ok, decoded = pcall(base64.decode, b64)
    if not ok or not decoded then
        return nil, nil, "base64 decode failed"
    end
    return decoded, header
end

local function write_binary(path, bytes)
    local file, err = io.open(path, "wb")
    if not file then
        return nil, err
    end
    file:write(bytes)
    file:close()
    return true
end

local function read_setting_string(key, fallback)
    if config and config.get_setting then
        local v = config.get_setting(key)
        if v ~= nil and tostring(v) ~= "" then
            return tostring(v)
        end
    end
    return fallback
end

local function normalize_bool(value, fallback)
    if value == nil then return fallback end
    if value == true or value == 1 or value == "1" or value == "true" then
        return true
    end
    return false
end

local function resolve_stream_radio_dir(stream_id)
    local base = config and config.data_dir or "./data"
    local safe_id = sanitize_id(stream_id)
    local dir = base .. "/streams/" .. safe_id .. "/radio"
    ensure_dir(dir)
    return dir
end

local function build_uploaded_png_path(stream_id)
    local dir = resolve_stream_radio_dir(stream_id)
    local stamp = os.date("%Y%m%d-%H%M%S")
    return dir .. "/cover_" .. stamp .. ".png"
end

local function resolve_stream_log_dir(stream_id)
    local base = config and config.data_dir or "./data"
    local safe_id = sanitize_id(stream_id)
    local dir = base .. "/streams/" .. safe_id .. "/logs"
    ensure_dir(dir)
    return dir
end

local function build_log_path(stream_id)
    local dir = resolve_stream_log_dir(stream_id)
    return dir .. "/radio.log"
end

local function build_fifo_path(stream_id)
    local dir = resolve_stream_radio_dir(stream_id)
    return dir .. "/audio.pipe"
end

local function ensure_fifo(path)
    os.execute("rm -f " .. shell_escape(path))
    local ok = os.execute("mkfifo " .. shell_escape(path))
    return ok == true or ok == 0
end

local function build_udp_url(base_url, pkt_size)
    local url = tostring(base_url or "")
    if url == "" then return "" end
    if not pkt_size or pkt_size == "" then
        return url
    end
    local separator = url:find("?", 1, true) and "&" or "?"
    if url:find("pkt_size=", 1, true) then
        return url
    end
    return url .. separator .. "pkt_size=" .. tostring(pkt_size)
end

local function parse_headers(raw)
    if not raw or raw == "" then
        return {}
    end
    local headers = {}
    for line in tostring(raw):gmatch("[^\r\n]+") do
        local trimmed = line:gsub("^%s+", ""):gsub("%s+$", "")
        if trimmed ~= "" then
            table.insert(headers, trimmed)
        end
    end
    return headers
end

local function spawn_process(args)
    if not process or type(process.spawn) ~= "function" then
        return nil, "process module is not available"
    end
    local ok, proc = pcall(process.spawn, args, { stdout = "pipe", stderr = "pipe" })
    if not ok or not proc then
        return nil, "failed to spawn process"
    end
    return proc
end

local function new_job(stream_id, settings)
    local job = {
        stream_id = stream_id,
        status = "stopped",
        start_ts = nil,
        last_progress_ts = nil,
        startup_grace_sec = 15,
        no_progress_timeout_sec = 30,
        max_restarts_per_10min = 10,
        last_stall_log_ts = 0,
        stop_requested = false,
        settings = settings or {},
        ffmpeg = nil,
        curl = nil,
        poller = nil,
        restart_timer = nil,
        logs = {},
        log_limit = 200,
        last_error = nil,
        last_exit = nil,
        restart_count = 0,
        restart_window = {},
        auto_restart = true,
        restart_delay_sec = 4,
        fifo_path = nil,
    }
    radio.jobs[stream_id] = job
    return job
end

local function append_log(job, prefix, text)
    if not text or text == "" then return end
    local lines = {}
    for line in tostring(text):gmatch("[^\r\n]+") do
        table.insert(lines, line)
    end
    if #lines == 0 then return end
    for _, line in ipairs(lines) do
        local entry = prefix .. " " .. line
        table.insert(job.logs, entry)
        if #job.logs > job.log_limit then
            table.remove(job.logs, 1)
        end
        if job.log_path and job.log_path ~= "" then
            local file = io.open(job.log_path, "a")
            if file then
                file:write(entry .. "\n")
                file:close()
            end
        end
    end
end

local function logs_to_text(job)
    if not job or not job.logs then return "" end
    return table.concat(job.logs, "\n")
end

local function stop_process(proc, kill_delay)
    if not proc then return end
    if proc.terminate then proc:terminate() end
    if kill_delay and kill_delay > 0 then
        timer({
            interval = kill_delay,
            callback = function(self)
                self:close()
                if proc.kill then proc:kill() end
                if proc.close then proc:close() end
            end,
        })
    else
        if proc.kill then proc:kill() end
        if proc.close then proc:close() end
    end
end

local function should_restart(job)
    if not job.auto_restart or job.stop_requested then
        return false
    end
    local window = job.restart_window
    local now = now_ts()
    local filtered = {}
    for _, ts in ipairs(window) do
        if now - ts < 600 then
            table.insert(filtered, ts)
        end
    end
    job.restart_window = filtered
    local limit = tonumber(job.max_restarts_per_10min) or 10
    if limit < 1 then
        limit = 1
    end
    if #filtered >= limit then
        return false
    end
    return true
end

local function build_ffmpeg_args(settings, fifo_path)
    local ffmpeg = read_setting_string("ffmpeg_path", "ffmpeg")
    local args = { ffmpeg, "-hide_banner", "-nostdin", "-loglevel", "info", "-thread_queue_size", "1024" }

    table.insert(args, "-loop")
    table.insert(args, "1")
    table.insert(args, "-i")
    table.insert(args, tostring(settings.png_path or ""))

    if settings.use_curl then
        table.insert(args, "-f")
        table.insert(args, tostring(settings.audio_format or "mp3"))
        table.insert(args, "-i")
        table.insert(args, fifo_path)
    else
        table.insert(args, "-i")
        table.insert(args, tostring(settings.audio_url or ""))
    end

    local vf = string.format("fps=%s,scale=%s:%s:flags=lanczos", settings.fps, settings.width, settings.height)
    if settings.keep_aspect then
        vf = string.format("scale=%s:%s:force_original_aspect_ratio=decrease:flags=lanczos,pad=%s:%s:(ow-iw)/2:(oh-ih)/2, fps=%s",
            settings.width, settings.height, settings.width, settings.height, settings.fps)
    end
    table.insert(args, "-vf")
    table.insert(args, vf)

    table.insert(args, "-r")
    table.insert(args, tostring(settings.fps))
    table.insert(args, "-g")
    table.insert(args, tostring(settings.gop))
    table.insert(args, "-pix_fmt")
    table.insert(args, tostring(settings.pix_fmt))

    table.insert(args, "-c:v")
    table.insert(args, tostring(settings.vcodec))
    table.insert(args, "-preset")
    table.insert(args, tostring(settings.preset))
    table.insert(args, "-b:v")
    table.insert(args, tostring(settings.video_bitrate))
    if settings.tune_stillimage then
        table.insert(args, "-tune")
        table.insert(args, "stillimage")
    end

    table.insert(args, "-c:a")
    table.insert(args, tostring(settings.acodec))
    table.insert(args, "-b:a")
    table.insert(args, tostring(settings.audio_bitrate))
    table.insert(args, "-ac")
    table.insert(args, tostring(settings.channels))
    table.insert(args, "-ar")
    table.insert(args, tostring(settings.sample_rate))

    table.insert(args, "-pcr_period")
    table.insert(args, tostring(settings.pcr_period))
    table.insert(args, "-max_interleave_delta")
    table.insert(args, tostring(settings.max_interleave_delta))
    table.insert(args, "-muxdelay")
    table.insert(args, tostring(settings.muxdelay))

    table.insert(args, "-f")
    table.insert(args, "mpegts")
    table.insert(args, tostring(settings.output_url))
    return args
end

local function build_curl_args(settings, fifo_path)
    local args = { "curl", "-sS", "--fail", "--location" }
    -- Быстрый fail при обрывах/зависаниях, чтобы автоперезапуск был предсказуемым.
    table.insert(args, "--connect-timeout")
    table.insert(args, "5")
    table.insert(args, "--speed-limit")
    table.insert(args, "1024")
    table.insert(args, "--speed-time")
    table.insert(args, "15")
    if settings.user_agent and settings.user_agent ~= "" then
        table.insert(args, "-A")
        table.insert(args, settings.user_agent)
    end
    local headers = parse_headers(settings.extra_headers)
    for _, header in ipairs(headers) do
        table.insert(args, "-H")
        table.insert(args, header)
    end
    table.insert(args, "-o")
    table.insert(args, fifo_path)
    table.insert(args, tostring(settings.audio_url))
    return args
end

local function normalize_settings(raw)
    local out = {}
    out.audio_url = tostring(raw.audio_url or "")
    out.png_path = tostring(raw.png_path or "")
    out.autostart = normalize_bool(raw.autostart, false)
    out.use_curl = normalize_bool(raw.use_curl, true)
    out.extra_headers = tostring(raw.extra_headers or "")
    out.user_agent = tostring(raw.user_agent or "")
    local fmt = tostring(raw.audio_format or "mp3"):lower()
    if fmt ~= "mp3" and fmt ~= "aac" then
        fmt = "mp3"
    end
    out.audio_format = fmt
    out.fps = clamp_number(raw.fps, 1, 120, 25)
    out.width = clamp_int(raw.width, 16, 8192, 270)
    out.height = clamp_int(raw.height, 16, 8192, 270)
    out.keep_aspect = normalize_bool(raw.keep_aspect, false)
    out.vcodec = tostring(raw.vcodec or "libx264")
    out.preset = tostring(raw.preset or "veryfast")
    out.video_bitrate = tostring(raw.video_bitrate or "1400k")
    out.pix_fmt = tostring(raw.pix_fmt or "yuv420p")
    out.gop = clamp_int(raw.gop, 1, 100000, math.floor(out.fps * 2))
    out.tune_stillimage = normalize_bool(raw.tune_stillimage, true)
    out.acodec = tostring(raw.acodec or "aac")
    out.audio_bitrate = tostring(raw.audio_bitrate or "256k")
    out.channels = clamp_int(raw.channels, 1, 8, 2)
    out.sample_rate = clamp_int(raw.sample_rate, 8000, 192000, 48000)
    out.pcr_period = clamp_int(raw.pcr_period, 0, 10000, 30)
    out.max_interleave_delta = clamp_int(raw.max_interleave_delta, 0, 100000, 0)
    out.muxdelay = clamp_number(raw.muxdelay, 0, 100, 0.7)
    out.pkt_size = clamp_int(raw.pkt_size, 188, 65507, 1316)
    local base_out = tostring(raw.output_url or "")
    out.output_url = build_udp_url(base_out, out.pkt_size)
    out.log_path = tostring(raw.log_path or "")
    out.auto_restart = normalize_bool(raw.auto_restart, true)
    -- Внутренний timer требует interval > 0 (0 приведёт к abort), поэтому минимальный delay > 0.
    out.restart_delay_sec = clamp_number(raw.restart_delay_sec or raw.restart_delay, 0.1, 60, 4)
    out.no_progress_timeout_sec = clamp_number(raw.no_progress_timeout_sec or raw.no_progress_timeout, 0, 600, 30)
    out.max_restarts_per_10min = clamp_int(raw.max_restarts_per_10min, 1, 1000, 10)
    return out
end

local function cleanup_job(job)
    if job.poller then
        job.poller:close()
        job.poller = nil
    end
    if job.restart_timer then
        job.restart_timer:close()
        job.restart_timer = nil
    end
    if job.ffmpeg then
        stop_process(job.ffmpeg, 0)
        job.ffmpeg = nil
    end
    if job.curl then
        stop_process(job.curl, 0)
        job.curl = nil
    end
    if job.fifo_path then
        os.execute("rm -f " .. shell_escape(job.fifo_path))
        job.fifo_path = nil
    end
end

local function schedule_restart(job)
    if job.restart_timer then
        -- Уже запланирован перезапуск. Не дублируем, иначе быстро упираемся в лимит
        -- max_restarts_per_10min и получаем ложный "error".
        return
    end
    if not should_restart(job) then
        job.status = "error"
        if not job.last_error or job.last_error == "" then
            job.last_error = "restart limit reached"
        end
        return
    end
    job.restart_count = job.restart_count + 1
    table.insert(job.restart_window, now_ts())
    local delay = tonumber(job.restart_delay_sec) or 4
    if delay <= 0 then
        delay = 0.5
    end
    job.status = "restarting"
    job.restart_timer = timer({
        interval = delay,
        callback = function(self)
            self:close()
            job.restart_timer = nil
            local ok, started, err = pcall(radio.start, job.stream_id, job.settings)
            if not ok then
                job.status = "error"
                job.last_error = tostring(started or "restart failed")
                return
            end
            if not started then
                job.status = "error"
                job.last_error = tostring(err or "restart failed")
            end
        end,
    })
end

local function mark_ffmpeg_progress(job, text)
    if not job or not text or text == "" then
        return
    end
    local s = tostring(text)
    -- В логе ffmpeg обычно есть строки: "frame=... time=...". Это дешёвый и достаточно надёжный признак,
    -- что генератор действительно продолжает выдавать TS.
    if s:find("time=", 1, true) or s:find("frame=", 1, true) then
        job.last_progress_ts = now_ts()
    end
end

local function ensure_poller(job)
    if job.poller then return end
    job.poller = timer({
        interval = 0.5,
        callback = function(self)
            if job.stop_requested then
                cleanup_job(job)
                job.status = "stopped"
                self:close()
                return
            end
            if job.curl then
                local chunk = job.curl:read_stderr()
                append_log(job, "[curl]", chunk)
                local status = job.curl:poll()
                if status then
                    job.last_exit = status
                    job.last_error = "curl exited"
                    append_log(job, "[curl]", "exit=" .. tostring(status))
                    stop_process(job.curl, 0)
                    job.curl = nil
                    if job.ffmpeg then
                        stop_process(job.ffmpeg, 1)
                    end
                    schedule_restart(job)
                    return
                end
            end
            if job.ffmpeg then
                local chunk = job.ffmpeg:read_stderr()
                mark_ffmpeg_progress(job, chunk)
                append_log(job, "[ffmpeg]", chunk)
                local status = job.ffmpeg:poll()
                if status then
                    job.last_exit = status
                    job.last_error = "ffmpeg exited"
                    append_log(job, "[ffmpeg]", "exit=" .. tostring(status))
                    stop_process(job.ffmpeg, 0)
                    job.ffmpeg = nil
                    if job.curl then
                        stop_process(job.curl, 0)
                        job.curl = nil
                    end
                    schedule_restart(job)
                    return
                end
            end

            -- Watchdog: если ffmpeg жив, но перестал писать прогресс (завис/замолчал), перезапускаем.
            if job.status == "running" and job.ffmpeg and not job.stop_requested then
                local now = now_ts()
                local grace = tonumber(job.startup_grace_sec) or 15
                local timeout = tonumber(job.no_progress_timeout_sec) or 0
                if timeout > 0 and job.last_progress_ts and job.start_ts and (now - job.start_ts) >= grace then
                    if (now - job.last_progress_ts) >= timeout then
                        if not job.last_stall_log_ts or (now - job.last_stall_log_ts) >= 5 then
                            append_log(job, "[watchdog]", "no ffmpeg progress for " ..
                                tostring(now - job.last_progress_ts) .. "s, restarting")
                            job.last_stall_log_ts = now
                        end
                        job.last_error = "ffmpeg stalled"
                        if job.ffmpeg then
                            stop_process(job.ffmpeg, 0)
                            job.ffmpeg = nil
                        end
                        if job.curl then
                            stop_process(job.curl, 0)
                            job.curl = nil
                        end
                        schedule_restart(job)
                        return
                    end
                end
            end
        end,
    })
end

function radio.start(stream_id, raw_settings)
    local settings = normalize_settings(raw_settings or {})
    if settings.audio_url == "" then
        return false, "audio url required"
    end
    local png_data_url = raw_settings and raw_settings.png_data_url or nil
    if png_data_url and png_data_url ~= "" then
        local bytes, _, err = decode_data_url(png_data_url, "image/png")
        if not bytes then
            return false, err or "invalid png data"
        end
        local path = build_uploaded_png_path(stream_id)
        local ok, werr = write_binary(path, bytes)
        if not ok then
            return false, werr or "failed to save png"
        end
        settings.png_path = path
    end
    if settings.png_path == "" then
        return false, "png path required"
    end
    if not file_exists(settings.png_path) then
        return false, "png file not found"
    end
    if settings.output_url == "" then
        return false, "output url required"
    end

    if not settings.log_path or settings.log_path == "" then
        settings.log_path = build_log_path(stream_id)
    end

    local job = radio.jobs[stream_id] or new_job(stream_id, settings)
    if job.status == "running" then
        return false, "already running"
    end

    cleanup_job(job)
    job.settings = settings
    job.log_path = settings.log_path
    job.stop_requested = false
    job.auto_restart = settings.auto_restart
    job.restart_delay_sec = settings.restart_delay_sec
    job.no_progress_timeout_sec = settings.no_progress_timeout_sec
    job.max_restarts_per_10min = settings.max_restarts_per_10min
    job.status = "starting"
    job.last_error = nil
    job.start_ts = now_ts()
    job.last_progress_ts = job.start_ts
    job.last_stall_log_ts = 0

    local fifo_path = nil
    if settings.use_curl then
        fifo_path = build_fifo_path(stream_id)
        if not ensure_fifo(fifo_path) then
            job.status = "error"
            job.last_error = "failed to create fifo"
            return false, "fifo create failed"
        end
        job.fifo_path = fifo_path
    end

    local ffmpeg_args = build_ffmpeg_args(settings, fifo_path)
    local ffmpeg_proc, err = spawn_process(ffmpeg_args)
    if not ffmpeg_proc then
        job.status = "error"
        job.last_error = err
        return false, err
    end
    job.ffmpeg = ffmpeg_proc

    if settings.use_curl then
        local curl_args = build_curl_args(settings, fifo_path)
        local curl_proc, cerr = spawn_process(curl_args)
        if not curl_proc then
            stop_process(job.ffmpeg, 0)
            job.ffmpeg = nil
            job.status = "error"
            job.last_error = cerr
            return false, cerr
        end
        job.curl = curl_proc
    end

    job.status = "running"
    ensure_poller(job)
    return true
end

function radio.stop(stream_id)
    local job = radio.jobs[stream_id]
    if not job then
        return true
    end
    job.stop_requested = true
    job.auto_restart = false
    if job.restart_timer then
        job.restart_timer:close()
        job.restart_timer = nil
    end
    if job.ffmpeg then
        stop_process(job.ffmpeg, 1)
    end
    if job.curl then
        stop_process(job.curl, 1)
    end
    return true
end

function radio.restart(stream_id, settings)
    local job = radio.jobs[stream_id]
    if job then
        job.stop_requested = true
        job.auto_restart = false
        cleanup_job(job)
    end
    return radio.start(stream_id, settings)
end

function radio.get_status(stream_id)
    local job = radio.jobs[stream_id]
    if not job then
        return {
            status = "stopped",
            stream_id = stream_id,
        }
    end
    return {
        status = job.status,
        stream_id = job.stream_id,
        start_ts = job.start_ts,
        last_error = job.last_error,
        last_exit = job.last_exit,
        settings = job.settings,
        logs = logs_to_text(job),
    }
end

function radio.get_logs(stream_id)
    local job = radio.jobs[stream_id]
    if not job then return "" end
    return logs_to_text(job)
end

-- Синхронизация радио-генератора с конфигом стрима (autostart).
-- Вызывается из runtime.apply_stream(), поэтому должна быть максимально безопасной:
-- ошибки не должны валить стрим-пайплайн.
function radio.sync_from_stream_config(stream_id, stream_cfg, enabled)
    local cfg = (type(stream_cfg) == "table") and stream_cfg.radio or nil
    local want = enabled and type(cfg) == "table" and cfg.autostart == true

    local job = radio.jobs[stream_id]
    if not want then
        if job and job.status ~= "stopped" then
            pcall(function() radio.stop(stream_id) end)
        end
        return true
    end

    if job and (job.status == "running" or job.status == "starting") then
        return true
    end

    local ok, started, start_err = pcall(radio.start, stream_id, cfg)
    if not ok then
        log.warning("[radio] autostart failed for stream " .. tostring(stream_id) .. ": " .. tostring(started))
        return false, started
    end
    if not started then
        log.warning("[radio] autostart failed for stream " .. tostring(stream_id) .. ": " .. tostring(start_err))
        return false, start_err or "start failed"
    end
    return true
end

-- Внутренние хелперы для unit-тестов (не использовать в runtime напрямую).
radio._test = {
    normalize_settings = normalize_settings,
    build_udp_url = build_udp_url,
    build_curl_args = build_curl_args,
    build_ffmpeg_args = build_ffmpeg_args,
}
