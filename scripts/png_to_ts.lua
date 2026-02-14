-- PNG -> MPEG-TS generator (ffmpeg)
-- Used by UI "PNG to Stream" to build a reserve TS from a still image.

pngts = {}

pngts.jobs = {}
pngts.last_id = 0
pngts.cleanup_timer = nil

local function now_ts()
    return os.time()
end

local function ensure_dir(path)
    local stat = utils and utils.stat and utils.stat(path) or nil
    if not stat or stat.type ~= "directory" then
        os.execute("mkdir -p " .. path)
    end
end

local function sanitize_id(value)
    local raw = tostring(value or "")
    local clean = raw:gsub("[^%w%-%_]", "_")
    if clean == "" then
        clean = "stream"
    end
    return clean
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

local function file_exists(path)
    if not path or path == "" then
        return false
    end
    local stat = utils and utils.stat and utils.stat(path) or nil
    return stat and stat.type == "file"
end

local function resolve_stream_backup_dir(stream_id)
    local base = config and config.data_dir or "./data"
    local safe_id = sanitize_id(stream_id)
    local dir = base .. "/streams/" .. safe_id .. "/backup"
    ensure_dir(dir)
    return dir
end

function pngts.list_outputs(stream_id)
    local dir = resolve_stream_backup_dir(stream_id)
    local files = {}
    if not utils or type(utils.readdir) ~= "function" then
        return files
    end
    local ok, iter = pcall(utils.readdir, dir)
    if not ok or not iter then
        return files
    end
    for name in iter do
        if name:match("%.ts$") then
            local path = dir .. "/" .. name
            local stat = utils and utils.stat and utils.stat(path) or nil
            table.insert(files, {
                name = name,
                path = path,
                size = stat and stat.size or 0,
                mtime = stat and stat.mtime or 0,
            })
        end
    end
    table.sort(files, function(a, b)
        return (a.mtime or 0) > (b.mtime or 0)
    end)
    return files
end

local function build_output_path(stream_id, codec, width, height, fps)
    local dir = resolve_stream_backup_dir(stream_id)
    local safe_codec = tostring(codec or "h264"):gsub("[^%w]", "")
    local w = tonumber(width) or 1280
    local h = tonumber(height) or 720
    local f = tostring(fps or "25"):gsub("[^%w%-%_%.]", "")
    local base = string.format("backup-from-png_%s_%dx%d_%s.ts", safe_codec, w, h, f)
    local path = dir .. "/" .. base
    if utils and utils.stat and utils.stat(path) and utils.stat(path).type == "file" then
        local suffix = os.date("%Y%m%d-%H%M%S")
        path = dir .. "/" .. base:gsub("%.ts$", "_" .. suffix .. ".ts")
    end
    return path
end

local function normalize_codec(value)
    local v = tostring(value or ""):lower()
    if v == "h264" or v == "libx264" then
        return "h264"
    end
    if v == "hevc" or v == "h265" or v == "libx265" then
        return "hevc"
    end
    if v == "mpeg2" or v == "mpeg2video" then
        return "mpeg2"
    end
    return "h264"
end

local function parse_fps(value)
    local v = tostring(value or "")
    if v == "" then
        return nil
    end
    local a, b = v:match("^(%d+)%s*/%s*(%d+)$")
    if a and b then
        local num = tonumber(a)
        local den = tonumber(b)
        if den and den > 0 then
            local fps = num / den
            return string.format("%.3f", fps):gsub("%.?0+$", "")
        end
    end
    local n = tonumber(v)
    if n and n > 0 then
        return tostring(n)
    end
    return nil
end

local function build_audio_args(audio)
    local mode = tostring(audio and audio.mode or "silence")
    if mode == "mp3" then
        local path = tostring(audio.path or "")
        return { "-stream_loop", "-1", "-i", path }
    end
    if mode == "beep" then
        local preset = tostring(audio.preset or "sine_440")
        local filter = "sine=f=440:r=48000"
        if preset == "sine_1000" then
            filter = "sine=f=1000:r=48000"
        elseif preset == "beep_1s" then
            -- Periodic beep (1Hz) using apulsator.
            filter = "sine=f=220:r=48000,apulsator=mode=sine:hz=1"
        elseif preset == "pink_noise" then
            filter = "anoisesrc=c=pink:r=48000:a=0.2"
        end
        return { "-f", "lavfi", "-i", filter }
    end
    return { "-f", "lavfi", "-i", "anullsrc=r=48000:cl=stereo" }
end

local function build_video_args(opts)
    local codec = normalize_codec(opts.codec)
    local args = {}
    if codec == "hevc" then
        table.insert(args, "-c:v"); table.insert(args, "libx265")
    elseif codec == "mpeg2" then
        table.insert(args, "-c:v"); table.insert(args, "mpeg2video")
    else
        table.insert(args, "-c:v"); table.insert(args, "libx264")
    end

    if opts.profile and opts.profile ~= "" then
        table.insert(args, "-profile:v")
        table.insert(args, tostring(opts.profile))
    end
    if opts.level and tostring(opts.level) ~= "" then
        table.insert(args, "-level:v")
        table.insert(args, tostring(opts.level))
    end
    if opts.pix_fmt and opts.pix_fmt ~= "" then
        table.insert(args, "-pix_fmt")
        table.insert(args, tostring(opts.pix_fmt))
    end
    if opts.fps and tostring(opts.fps) ~= "" then
        table.insert(args, "-r")
        table.insert(args, tostring(opts.fps))
    end
    if opts.width and opts.height then
        table.insert(args, "-s")
        table.insert(args, tostring(opts.width) .. "x" .. tostring(opts.height))
    end
    if opts.video_bitrate and tostring(opts.video_bitrate) ~= "" then
        table.insert(args, "-b:v")
        table.insert(args, tostring(opts.video_bitrate))
    end
    return args
end

function pngts.build_ffmpeg_args(opts)
    local ffmpeg = read_setting_string("ffmpeg_path", "ffmpeg")
    local image_path = tostring(opts.image_path or "")
    local output_path = tostring(opts.output_path or "")
    local duration = tonumber(opts.duration) or 10
    if duration < 1 then duration = 1 end

    local args = {
        ffmpeg,
        "-hide_banner",
        "-nostdin",
        "-loglevel",
        "error",
        "-y",
        "-loop",
        "1",
        "-i",
        image_path,
    }

    local audio_args = build_audio_args(opts.audio or {})
    for _, v in ipairs(audio_args) do table.insert(args, v) end

    table.insert(args, "-map"); table.insert(args, "0:v:0")
    table.insert(args, "-map"); table.insert(args, "1:a:0")

    local video_args = build_video_args(opts)
    for _, v in ipairs(video_args) do table.insert(args, v) end

    table.insert(args, "-c:a"); table.insert(args, "aac")
    table.insert(args, "-b:a"); table.insert(args, "128k")
    table.insert(args, "-ar"); table.insert(args, "48000")
    table.insert(args, "-ac"); table.insert(args, "2")

    table.insert(args, "-t"); table.insert(args, tostring(duration))
    table.insert(args, "-f"); table.insert(args, "mpegts")
    table.insert(args, output_path)

    return args
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

local function new_job(kind, stream_id)
    pngts.last_id = pngts.last_id + 1
    local id = tostring(pngts.last_id)
    local job = {
        id = id,
        kind = kind,
        stream_id = stream_id,
        status = "running",
        created_at = now_ts(),
        updated_at = now_ts(),
        logs = "",
        error = nil,
        result = nil,
        proc = nil,
        timeout_sec = 60,
    }
    pngts.jobs[id] = job
    return job
end

local function finalize_job(job, status, result, err, logs)
    job.status = status
    job.updated_at = now_ts()
    job.result = result
    job.error = err
    if logs and logs ~= "" then
        job.logs = logs
    end
    if job.proc then
        if job.proc.close then job.proc:close() end
        job.proc = nil
    end
end

local function ensure_cleanup_timer()
    if pngts.cleanup_timer then
        return
    end
    pngts.cleanup_timer = timer({
        interval = 10,
        callback = function()
            local now = now_ts()
            local removed = false
            for id, job in pairs(pngts.jobs) do
                if job and job.updated_at and (now - job.updated_at) > 3600 then
                    pngts.jobs[id] = nil
                    removed = true
                end
            end
            if not removed then
                -- keep timer running for future jobs
            end
        end,
    })
end

function pngts.start_ffprobe(stream_id, input_url)
    local job = new_job("ffprobe", stream_id)
    ensure_cleanup_timer()

    local ffprobe = read_setting_string("ffprobe_path", "ffprobe")
    local args = {
        ffprobe,
        "-hide_banner",
        "-v",
        "error",
        "-show_streams",
        "-show_format",
        "-of",
        "json",
        input_url,
    }
    local proc, err = spawn_process(args)
    if not proc then
        finalize_job(job, "error", nil, err)
        return job
    end
    job.proc = proc
    job.timeout_sec = 20

    local started = now_ts()
    job.poller = timer({
        interval = 0.2,
        callback = function(self)
            local status = proc:poll()
            if not status then
                if now_ts() - started > job.timeout_sec then
                    proc:terminate()
                    proc:kill()
                    local stderr = proc:read_stderr() or ""
                    finalize_job(job, "error", nil, "ffprobe timeout", stderr)
                    self:close()
                end
                return
            end
            local stdout = proc:read_stdout() or ""
            local stderr = proc:read_stderr() or ""
            local ok, parsed = pcall(json.decode, stdout)
            if not ok then
                finalize_job(job, "error", nil, "ffprobe parse error", stderr)
            else
                finalize_job(job, "done", parsed, nil, stderr)
            end
            self:close()
        end,
    })
    return job
end

function pngts.start_generate(stream_id, opts)
    local job = new_job("generate", stream_id)
    ensure_cleanup_timer()

    local image_path = tostring(opts.image_path or "")
    if image_path == "" then
        finalize_job(job, "error", nil, "image path missing")
        return job
    end
    local output_path = tostring(opts.output_path or "")
    if output_path == "" then
        finalize_job(job, "error", nil, "output path missing")
        return job
    end

    local args = pngts.build_ffmpeg_args(opts)
    local proc, err = spawn_process(args)
    if not proc then
        finalize_job(job, "error", nil, err)
        return job
    end
    job.proc = proc
    job.timeout_sec = 60
    local started = now_ts()

    job.poller = timer({
        interval = 0.2,
        callback = function(self)
            local status = proc:poll()
            if not status then
                if now_ts() - started > job.timeout_sec then
                    proc:terminate()
                    proc:kill()
                    local stderr = proc:read_stderr() or ""
                    finalize_job(job, "error", nil, "ffmpeg timeout", stderr)
                    self:close()
                end
                return
            end
            local stdout = proc:read_stdout() or ""
            local stderr = proc:read_stderr() or ""
            if status ~= 0 then
                finalize_job(job, "error", nil, "ffmpeg failed", stderr)
            else
                finalize_job(job, "done", { output_path = output_path }, nil, stderr)
            end
            self:close()
        end,
    })
    return job
end

function pngts.get_job(job_id)
    return pngts.jobs[tostring(job_id)]
end

function pngts.prepare_assets_from_payload(stream_id, payload)
    local assets = {}
    local backup_dir = resolve_stream_backup_dir(stream_id)

    if payload.image_data_url then
        local bytes, _, err = decode_data_url(payload.image_data_url, "image/png")
        if not bytes then
            return nil, "invalid PNG data: " .. tostring(err)
        end
        local path = backup_dir .. "/image.png"
        local ok, werr = write_binary(path, bytes)
        if not ok then
            return nil, "failed to write PNG: " .. tostring(werr)
        end
        assets.image_path = path
    elseif payload.image_path then
        local p = tostring(payload.image_path)
        if not file_exists(p) then
            return nil, "PNG file not found: " .. tostring(p)
        end
        assets.image_path = p
    end

    if payload.audio_mode == "mp3" then
        if payload.mp3_data_url then
            local bytes, _, err = decode_data_url(payload.mp3_data_url, "audio/")
            if not bytes then
                return nil, "invalid MP3 data: " .. tostring(err)
            end
            local path = backup_dir .. "/audio.mp3"
            local ok, werr = write_binary(path, bytes)
            if not ok then
                return nil, "failed to write MP3: " .. tostring(werr)
            end
            assets.mp3_path = path
        elseif payload.mp3_path then
            local p = tostring(payload.mp3_path)
            if not file_exists(p) then
                return nil, "MP3 file not found: " .. tostring(p)
            end
            assets.mp3_path = p
        end
    end

    return assets
end

function pngts.build_output_path(stream_id, codec, width, height, fps)
    return build_output_path(stream_id, codec, width, height, fps)
end

function pngts.parse_fps(value)
    return parse_fps(value)
end
