-- Preview manager (HLS on-demand, без транскодинга).
--
-- Требования:
-- - старт предпросмотра только по запросу UI
-- - максимум 1 активная preview-сессия на поток
-- - максимум N активных preview по серверу (preview_max_sessions)
-- - авто-остановка по idle timeout (preview_idle_timeout_sec) и TTL токена (preview_token_ttl_sec)
-- - доступ к /preview/* только по крипто-случайному токену в path
--
-- Реализация:
-- - сегментация TS в HLS через встроенный hls_output (storage=memfd)
-- - токен хранится в памяти и используется как stream_id для memfd-слоя

preview = preview or {}

local sessions = {}   -- token -> session
local by_stream = {}  -- stream_id -> token
local sweep_timer = nil

local function setting_bool(key, fallback)
    if not config or not config.get_setting then
        return fallback
    end
    local value = config.get_setting(key)
    if value == nil then
        return fallback
    end
    if value == true or value == 1 or value == "1" then
        return true
    end
    return false
end

local function setting_number(key, fallback)
    if not config or not config.get_setting then
        return fallback
    end
    local value = tonumber(config.get_setting(key))
    if value == nil then
        return fallback
    end
    return value
end

local function setting_string(key, fallback)
    if not config or not config.get_setting then
        return fallback
    end
    local value = config.get_setting(key)
    if value == nil or value == "" then
        return fallback
    end
    return tostring(value)
end

local function join_path(base, suffix)
    if not base or base == "" then
        return suffix or ""
    end
    if not suffix or suffix == "" then
        return base
    end
    local clean_base = base:sub(-1) == "/" and base:sub(1, -2) or base
    local clean_suffix = suffix:sub(1, 1) == "/" and suffix:sub(2) or suffix
    return clean_base .. "/" .. clean_suffix
end

local function clamp_number(value, min_value, max_value)
    local n = tonumber(value)
    if n == nil then
        return nil
    end
    if min_value ~= nil and n < min_value then
        n = min_value
    end
    if max_value ~= nil and n > max_value then
        n = max_value
    end
    return n
end

local function preview_limits()
    local max_sessions = clamp_number(setting_number("preview_max_sessions", 2), 1, 16) or 2
    local idle = clamp_number(setting_number("preview_idle_timeout_sec", 45), 5, 600) or 45
    local ttl = clamp_number(setting_number("preview_token_ttl_sec", 180), 60, 900) or 180
    return max_sessions, idle, ttl
end

local function validate_token(token)
    if type(token) ~= "string" then
        return false
    end
    if #token < 16 or #token > 128 then
        return false
    end
    if not token:match("^[0-9a-fA-F]+$") then
        return false
    end
    return true
end

local function bytes_to_hex(bytes)
    return (bytes:gsub(".", function(ch)
        return string.format("%02x", string.byte(ch))
    end))
end

local function random_hex(nbytes)
    local fp = io.open("/dev/urandom", "rb")
    if fp then
        local b = fp:read(nbytes)
        fp:close()
        if b and #b == nbytes then
            return bytes_to_hex(b)
        end
    end
    local t = {}
    for i = 1, (nbytes * 2) do
        t[i] = string.format("%x", math.random(0, 15))
    end
    return table.concat(t)
end

local function new_token()
    -- 16 bytes = 32 hex chars
    for _ = 1, 8 do
        local token = random_hex(16)
        token = tostring(token or ""):lower()
        if token ~= "" and not sessions[token] then
            return token
        end
    end
    return nil
end

local function find_hls_output(cfg)
    if type(cfg) ~= "table" then
        return nil
    end
    local outputs = cfg.output
    if type(outputs) ~= "table" then
        return nil
    end
    for _, out in ipairs(outputs) do
        if type(out) == "table" and out.format == "hls" then
            return out
        end
    end
    return nil
end

local function build_direct_hls_url(stream_id, out)
    if type(out) ~= "table" then
        return nil
    end
    local playlist = tostring(out.playlist or "index.m3u8")
    local base_url = out.publish_url or out.base_url
    if type(base_url) == "string" and base_url ~= "" then
        return join_path(base_url, playlist)
    end
    -- Фолбэк: глобальная база HLS + /<stream_id>/<playlist>
    local hls_base = setting_string("hls_base_url", "/hls")
    if hls_base == "" then
        hls_base = "/hls"
    end
    return join_path(join_path(hls_base, stream_id), playlist)
end

local function resolve_transcode_output_upstream(job)
    if not job then
        return nil
    end
    if job.ladder_enabled == true then
        local first = job.profiles and job.profiles[1] or nil
        local pid = first and first.id or nil
        local bus = pid and job.profile_buses and job.profile_buses[pid] or nil
        if bus and bus.switch then
            return bus.switch:stream()
        end
    end
    if job.process_per_output == true then
        local worker = job.workers and job.workers[1] or nil
        if worker and worker.proxy_enabled == true and worker.proxy_switch then
            return worker.proxy_switch:stream()
        end
    end
    return nil
end

local function channel_on_air(channel)
    if not channel or type(channel) ~= "table" then
        return false
    end
    local inputs = channel.input
    if type(inputs) ~= "table" then
        return false
    end

    local now = os.time()
    local function input_ok(input_data)
        if not input_data or type(input_data) ~= "table" then
            return false
        end
        if input_data.on_air == true then
            return true
        end
        local stats = input_data.stats
        if type(stats) == "table" then
            if stats.on_air == true then
                return true
            end
            local br = tonumber(stats.bitrate)
            if br and br > 0 then
                return true
            end
        end
        local last_ok = tonumber(input_data.last_ok_ts)
        if last_ok and last_ok > 0 and (now - last_ok) <= 5 then
            return true
        end
        return false
    end

    local active_id = tonumber(channel.active_input_id or 0) or 0
    if active_id > 0 and input_ok(inputs[active_id]) then
        return true
    end

    for _, input_data in ipairs(inputs) do
        if input_ok(input_data) then
            return true
        end
    end

    return false
end

local function channel_has_running_input(channel)
    if not channel or type(channel) ~= "table" then
        return false
    end
    local inputs = channel.input
    if type(inputs) ~= "table" then
        return false
    end
    for _, input_data in ipairs(inputs) do
        if input_data and input_data.input ~= nil then
            return true
        end
    end
    return false
end

local function channel_has_failures(channel)
    if not channel or type(channel) ~= "table" then
        return false
    end
    local inputs = channel.input
    if type(inputs) ~= "table" then
        return false
    end
    for _, input_data in ipairs(inputs) do
        if type(input_data) == "table" then
            local fail = tonumber(input_data.fail_count) or 0
            local err = tostring(input_data.last_error or "")
            if fail > 0 or err ~= "" then
                return true
            end
        end
    end
    return false
end

local function ensure_dir(path)
    if not path or path == "" then
        return false
    end
    local stat = utils and utils.stat and utils.stat(path) or {}
    if stat.type == "directory" then
        return true
    end
    os.execute("mkdir -p " .. path)
    return true
end

local function rm_rf(path)
    if not path or path == "" then
        return
    end
    -- path строится из безопасных частей (корень + token), без пробелов.
    os.execute("rm -rf " .. path)
end

local function resolve_ffmpeg_bin()
    local env = os.getenv("ASTRA_FFMPEG_PATH") or os.getenv("FFMPEG_PATH")
    if env and env ~= "" then
        return env
    end
    local cfg = setting_string("ffmpeg_path", "")
    if cfg and cfg ~= "" then
        return cfg
    end
    return "ffmpeg"
end

local function pick_preview_tmp_root()
    local configured = setting_string("preview_tmp_root", "")
    if configured and configured ~= "" then
        return configured
    end
    local shm = "/dev/shm"
    local st = utils and utils.stat and utils.stat(shm) or {}
    if st.type == "directory" then
        return shm .. "/astra-preview"
    end
    local base = (config and config.data_dir) and config.data_dir or "./data"
    return base .. "/preview"
end

local function build_local_play_url(stream_id)
    local http_port = tonumber(config and config.get_setting and config.get_setting("http_port") or nil) or 8000
    local play_port = tonumber(config and config.get_setting and config.get_setting("http_play_port") or nil) or http_port
    if not play_port or play_port == 0 then
        play_port = http_port
    end
    -- internal=1: localhost ffmpeg может читать /play даже при включённом http_auth (см. http_auth_check()).
    return "http://127.0.0.1:" .. tostring(play_port) .. "/play/" .. tostring(stream_id) .. "?internal=1"
end

local function start_ffmpeg_hls_video_only(token, stream_id)
    if not process or type(process.spawn) ~= "function" then
        return nil, "process module is not available", 501
    end

    local root = pick_preview_tmp_root()
    ensure_dir(root)

    local base_path = root .. "/" .. token
    ensure_dir(base_path)

    -- Чтобы клиент не ловил 404 на первом запросе плейлиста, кладём заглушку.
    do
        local fp = io.open(base_path .. "/index.m3u8", "wb")
        if fp then
            fp:write("#EXTM3U\n#EXT-X-VERSION:3\n#EXT-X-TARGETDURATION:2\n#EXT-X-MEDIA-SEQUENCE:0\n")
            fp:close()
        end
    end

    local input_url = build_local_play_url(stream_id)
    local ffmpeg = resolve_ffmpeg_bin()

    local args = {
        ffmpeg,
        "-hide_banner",
        "-nostdin",
        "-loglevel",
        "error",
        "-fflags",
        "+genpts",
        "-i",
        input_url,
        -- Без транскодинга: только video, audio/subs/data выключаем.
        "-an",
        "-sn",
        "-dn",
        "-c",
        "copy",
        "-f",
        "hls",
        "-hls_time",
        "2",
        "-hls_list_size",
        "4",
        "-hls_flags",
        "delete_segments+independent_segments",
        "-hls_allow_cache",
        "0",
        "-hls_segment_filename",
        "seg_%08d.ts",
        "index.m3u8",
    }

    local ok, proc = pcall(process.spawn, args, { cwd = base_path })
    if not ok or not proc then
        rm_rf(base_path)
        return nil, "failed to start preview process", 500
    end

    return {
        proc = proc,
        base_path = base_path,
    }
end

local function start_ffmpeg_hls_audio_aac(token, stream_id)
    if not process or type(process.spawn) ~= "function" then
        return nil, "process module is not available", 501
    end

    local root = pick_preview_tmp_root()
    ensure_dir(root)

    local base_path = root .. "/" .. token
    ensure_dir(base_path)

    -- Чтобы клиент не ловил 404 на первом запросе плейлиста, кладём заглушку.
    do
        local fp = io.open(base_path .. "/index.m3u8", "wb")
        if fp then
            fp:write("#EXTM3U\n#EXT-X-VERSION:3\n#EXT-X-TARGETDURATION:2\n#EXT-X-MEDIA-SEQUENCE:0\n")
            fp:close()
        end
    end

    local input_url = build_local_play_url(stream_id)
    local ffmpeg = resolve_ffmpeg_bin()

    local args = {
        ffmpeg,
        "-hide_banner",
        "-nostdin",
        "-loglevel",
        "error",
        "-fflags",
        "+genpts",
        "-i",
        input_url,
        -- Без транскодинга видео, но аудио переводим в AAC для браузерной совместимости (MP2 часто не играет).
        "-map",
        "0:v:0?",
        "-map",
        "0:a:0?",
        "-sn",
        "-dn",
        "-c:v",
        "copy",
        "-c:a",
        "aac",
        "-b:a",
        "128k",
        "-ac",
        "2",
        "-ar",
        "48000",
        "-af",
        "aresample=async=1",
        "-f",
        "hls",
        "-hls_time",
        "2",
        "-hls_list_size",
        "4",
        "-hls_flags",
        "delete_segments+independent_segments",
        "-hls_allow_cache",
        "0",
        "-hls_segment_filename",
        "seg_%08d.ts",
        "index.m3u8",
    }

    local ok, proc = pcall(process.spawn, args, { cwd = base_path })
    if not ok or not proc then
        rm_rf(base_path)
        return nil, "failed to start preview process", 500
    end

    return {
        proc = proc,
        base_path = base_path,
    }
end

local function start_ffmpeg_hls_h264_aac(token, stream_id)
    if not process or type(process.spawn) ~= "function" then
        return nil, "process module is not available", 501
    end

    local root = pick_preview_tmp_root()
    ensure_dir(root)

    local base_path = root .. "/" .. token
    ensure_dir(base_path)

    -- Чтобы клиент не ловил 404 на первом запросе плейлиста, кладём заглушку.
    do
        local fp = io.open(base_path .. "/index.m3u8", "wb")
        if fp then
            fp:write("#EXTM3U\n#EXT-X-VERSION:3\n#EXT-X-TARGETDURATION:2\n#EXT-X-MEDIA-SEQUENCE:0\n")
            fp:close()
        end
    end

    local input_url = build_local_play_url(stream_id)
    local ffmpeg = resolve_ffmpeg_bin()

    -- Полный "browser compatible" профиль: H.264 + AAC (наиболее предсказуемо для HTML5 video).
    -- Для быстрого старта (особенно в Safari) делаем "лёгкий" предпросмотр:
    -- - ultrafast preset
    -- - ограничение разрешения (не апскейлим)
    -- bitrate держим минимальным (~1 Mbit), чтобы предпросмотр был дешёвым по сети/CPU.
    local args = {
        ffmpeg,
        "-hide_banner",
        "-nostdin",
        "-loglevel",
        "error",
        "-fflags",
        "+genpts",
        "-i",
        input_url,
        "-map",
        "0:v:0?",
        "-map",
        "0:a:0?",
        "-sn",
        "-dn",
        "-vf",
        "scale='min(854,iw)':-2",
        "-c:v",
        "libx264",
        "-preset",
        "ultrafast",
        "-tune",
        "zerolatency",
        "-pix_fmt",
        "yuv420p",
        "-profile:v",
        "baseline",
        "-level",
        "3.1",
        "-b:v",
        "1000k",
        "-maxrate",
        "1000k",
        "-bufsize",
        "2000k",
        -- Под HLS сегментацию (2s) удобнее иметь регулярные keyframe.
        "-sc_threshold",
        "0",
        "-force_key_frames",
        "expr:gte(t,n_forced*2)",
        "-c:a",
        "aac",
        "-b:a",
        "128k",
        "-ac",
        "2",
        "-ar",
        "48000",
        "-af",
        "aresample=async=1",
        "-f",
        "hls",
        "-hls_time",
        "2",
        "-hls_list_size",
        "4",
        "-hls_flags",
        "delete_segments+independent_segments",
        "-hls_allow_cache",
        "0",
        "-hls_segment_filename",
        "seg_%08d.ts",
        "index.m3u8",
    }

    local ok, proc = pcall(process.spawn, args, { cwd = base_path })
    if not ok or not proc then
        rm_rf(base_path)
        return nil, "failed to start preview process", 500
    end

    return {
        proc = proc,
        base_path = base_path,
    }
end

local function stop_session(token, reason)
    token = tostring(token or ""):lower()
    local s = sessions[token]
    if not s then
        return false
    end

    sessions[token] = nil
    if s.stream_id and by_stream[s.stream_id] == token then
        by_stream[s.stream_id] = nil
    end

    if s.proc then
        pcall(function() s.proc:terminate() end)
        pcall(function() s.proc:kill() end)
        pcall(function() s.proc:close() end)
    end
    s.proc = nil

    if s.output and s.output.close then
        pcall(function() s.output:close() end)
    end
    s.output = nil

    if s.input then
        pcall(function() kill_input(s.input) end)
        s.input = nil
    end

    if s.channel_data and _G.channel_release then
        pcall(function() _G.channel_release(s.channel_data, reason or "preview_stop") end)
    end
    s.channel_data = nil

    local msg = "[preview] stop token=" .. token
    if s.stream_id then
        msg = msg .. " stream=" .. tostring(s.stream_id)
    end
    if reason then
        msg = msg .. " reason=" .. tostring(reason)
    end
    log.info(msg)

    if s.base_path then
        rm_rf(s.base_path)
    end
    s.base_path = nil

    collectgarbage()
    return true
end

local function ensure_sweep_timer()
    if sweep_timer then
        return
    end
    sweep_timer = timer({
        interval = 2,
        callback = function(self)
            local _, idle, _ = preview_limits()
            local now = os.time()
            local to_stop = {}
            for token, s in pairs(sessions) do
                local last = tonumber(s.last_access_at or s.created_at or 0) or 0
                local exp = tonumber(s.expires_at or 0) or 0
                if exp > 0 and now > exp then
                    table.insert(to_stop, { token = token, reason = "ttl" })
                elseif last > 0 and (now - last) > idle then
                    table.insert(to_stop, { token = token, reason = "idle" })
                elseif s.proc and s.proc.poll then
                    local status = s.proc:poll()
                    if status then
                        table.insert(to_stop, { token = token, reason = "proc_exit" })
                    end
                end
            end
            for _, item in ipairs(to_stop) do
                stop_session(item.token, item.reason)
            end
            if next(sessions) == nil then
                self:close()
                sweep_timer = nil
            end
        end,
    })
end

function preview.extract_token(path)
    if type(path) ~= "string" then
        return nil
    end
    local token = path:match("^/preview/([0-9a-fA-F]+)/")
    if not token or not validate_token(token) then
        return nil
    end
    return tostring(token):lower()
end

function preview.touch(token)
    if not validate_token(token) then
        return false
    end
    token = tostring(token):lower()
    local s = sessions[token]
    if not s then
        return false
    end
    local _, _, ttl = preview_limits()
    local now = os.time()
    s.last_access_at = now
    s.expires_at = now + ttl
    return true
end

function preview.stop(stream_id)
    stream_id = tostring(stream_id or "")
    if stream_id == "" then
        return false
    end
    local token = by_stream[stream_id]
    if not token then
        return false
    end
    return stop_session(token, "api")
end

function preview.get_session(token)
    if not validate_token(token) then
        return nil
    end
    token = tostring(token):lower()
    return sessions[token]
end

function preview.start(stream_id, opts)
    stream_id = tostring(stream_id or "")
    if stream_id == "" then
        return nil, "stream id required", 400
    end

    opts = (type(opts) == "table") and opts or {}
    local video_only = (opts.video_only == true)
    local video_h264 = (not video_only) and (opts.video_h264 == true)
    local audio_aac = (not video_only) and (not video_h264) and (opts.audio_aac == true)

    local stream = runtime and runtime.streams and runtime.streams[stream_id] or nil
    local cfg = nil
    if not stream and config and config.get_stream then
        local row = config.get_stream(stream_id)
        if row then
            cfg = row.config or nil
        end
    end
    if not stream and not cfg then
        return nil, "stream not found", 404
    end

    -- If transcoding is enabled for this stream (or stream type is transcode),
    -- preview must NOT spawn another ffmpeg transcoder. Use the post-ffmpeg output "as is".
    local is_transcode_cfg = false
    if type(cfg) == "table" then
        local stype = tostring(cfg.type or ""):lower()
        if stype == "transcode" or stype == "ffmpeg" then
            is_transcode_cfg = true
        elseif type(cfg.transcode) == "table" and cfg.transcode.enabled == true then
            is_transcode_cfg = true
        end
    end
    if is_transcode_cfg then
        video_only = false
        audio_aac = false
        video_h264 = false
    end

    -- If this stream is not instantiated in this shard runtime (stream sharding),
    -- build preview from loopback /play (which can proxy to the owning shard).
    if not stream then
        local existing = by_stream[stream_id]
        if existing and sessions[existing] then
            local s = sessions[existing]
            if (video_only ~= (s.video_only == true))
                or (audio_aac ~= (s.audio_aac == true))
                or (video_h264 ~= (s.video_h264 == true)) then
                stop_session(existing, "profile_change")
            else
                preview.touch(existing)
                return {
                    mode = "preview",
                    url = s.url,
                    token = s.token,
                    expires_in_sec = tonumber(s.expires_in_sec) or nil,
                    reused = true,
                }
            end
        end

        local max_sessions, _, ttl = preview_limits()
        local active = 0
        for _ in pairs(sessions) do
            active = active + 1
        end
        if active >= max_sessions then
            return nil, "preview limit reached", 429
        end

        local token = new_token()
        if not token then
            return nil, "failed to generate token", 500
        end

        local output = nil
        local proc = nil
        local base_path = nil
        local input = nil
        if video_only then
            local started, start_err, start_code = start_ffmpeg_hls_video_only(token, stream_id)
            if not started then
                return nil, start_err or "preview failed", start_code or 500
            end
            proc = started.proc
            base_path = started.base_path
        elseif audio_aac then
            local started, start_err, start_code = start_ffmpeg_hls_audio_aac(token, stream_id)
            if not started then
                return nil, start_err or "preview failed", start_code or 500
            end
            proc = started.proc
            base_path = started.base_path
        elseif video_h264 then
            local started, start_err, start_code = start_ffmpeg_hls_h264_aac(token, stream_id)
            if not started then
                return nil, start_err or "preview failed", start_code or 500
            end
            proc = started.proc
            base_path = started.base_path
        else
            local url = build_local_play_url(stream_id)
            local conf = parse_url(url)
            if not conf then
                return nil, "invalid input url", 400
            end
            conf.name = "preview-" .. tostring(stream_id)
            input = init_input(conf)
            if not input then
                return nil, "failed to init preview input", 500
            end

            local ts_ext = setting_string("hls_ts_extension", "ts")
            if ts_ext == "" then
                ts_ext = "ts"
            end
            output = hls_output({
                upstream = input.tail:stream(),
                playlist = "index.m3u8",
                prefix = "seg",
                ts_extension = ts_ext,
                pass_data = true,
                use_wall = true,
                naming = "sequence",
                round_duration = false,
                storage = "memfd",
                stream_id = token,
                on_demand = true,
                idle_timeout_sec = setting_number("preview_idle_timeout_sec", 45),
                target_duration = 2,
                window = 4,
                cleanup = 8,
                max_bytes = 32 * 1024 * 1024,
                max_segments = 32,
            })
        end

        local now = os.time()
        sessions[token] = {
            token = token,
            stream_id = stream_id,
            created_at = now,
            last_access_at = now,
            expires_at = now + ttl,
            expires_in_sec = ttl,
            url = "/preview/" .. token .. "/index.m3u8",
            video_only = video_only,
            audio_aac = audio_aac,
            video_h264 = video_h264,
            output = output,
            proc = proc,
            base_path = base_path,
            input = input,
            channel_data = nil,
        }
        by_stream[stream_id] = token

        log.info("[preview] start token=" .. token .. " stream=" .. stream_id .. " (loopback)")
        ensure_sweep_timer()

        return {
            mode = "preview",
            url = sessions[token].url,
            token = token,
            expires_in_sec = ttl,
            reused = false,
        }
    end

    -- Streams with an active transcode job already have an encoded output. For preview we must not launch
    -- another ffmpeg transcoder. Use published HLS when available, otherwise create a lightweight
    -- (remux-only) HLS preview from the transcode output bus.
    local job = stream.job
    if not job and transcode and transcode.jobs then
        job = transcode.jobs[stream_id]
    end
    if job then

        -- Never spawn preview ffmpeg for transcode streams, even if UI requested a fallback profile.
        video_only = false
        audio_aac = false
        video_h264 = false

        -- Prefer the existing transcode publish (HLS master) when present.
        if job.ladder_enabled == true
            and type(job.publish_hls_outputs) == "table"
            and next(job.publish_hls_outputs) ~= nil then
            local url = build_direct_hls_url(stream_id, { playlist = "index.m3u8" })
            if url and url ~= "" then
                return { mode = "hls", url = url }
            end
        end

        local existing = by_stream[stream_id]
        if existing and sessions[existing] then
            local s = sessions[existing]
            preview.touch(existing)
            return {
                mode = "preview",
                url = s.url,
                token = s.token,
                expires_in_sec = tonumber(s.expires_in_sec) or nil,
                reused = true,
            }
        end

        local upstream = resolve_transcode_output_upstream(job)
        if not upstream then
            return nil, "preview not supported", 409
        end

        local max_sessions, _, ttl = preview_limits()
        local active = 0
        for _ in pairs(sessions) do
            active = active + 1
        end
        if active >= max_sessions then
            return nil, "preview limit reached", 429
        end

        local token = new_token()
        if not token then
            return nil, "failed to generate token", 500
        end

        local ts_ext = setting_string("hls_ts_extension", "ts")
        if ts_ext == "" then
            ts_ext = "ts"
        end

        local output = hls_output({
            upstream = upstream,
            playlist = "index.m3u8",
            prefix = "seg",
            ts_extension = ts_ext,
            pass_data = true,
            use_wall = true,
            naming = "sequence",
            round_duration = false,
            storage = "memfd",
            stream_id = token,
            on_demand = true,
            idle_timeout_sec = setting_number("preview_idle_timeout_sec", 45),
            target_duration = 2,
            window = 4,
            cleanup = 8,
            max_bytes = 32 * 1024 * 1024,
            max_segments = 32,
        })

        local now = os.time()
        sessions[token] = {
            token = token,
            stream_id = stream_id,
            created_at = now,
            last_access_at = now,
            expires_at = now + ttl,
            expires_in_sec = ttl,
            url = "/preview/" .. token .. "/index.m3u8",
            output = output,
            proc = nil,
            base_path = nil,
            channel_data = nil,
        }
        by_stream[stream_id] = token

        log.info("[preview] start token=" .. token .. " stream=" .. stream_id .. " (transcode)")
        ensure_sweep_timer()

        return {
            mode = "preview",
            url = sessions[token].url,
            token = token,
            expires_in_sec = ttl,
            reused = false,
        }
    end

    if stream.kind ~= "stream" or not stream.channel then
        return nil, "preview not supported", 409
    end

    -- Быстрый оффлайн-чек: если input уже запущен, но сигнала нет, не даём UI "висеть" на буферизации.
    -- Если input ещё не стартовал (0 клиентов), даём шанс предпросмотру запустить его.
    if channel_has_running_input(stream.channel)
        and not channel_on_air(stream.channel)
        and channel_has_failures(stream.channel) then
        return nil, "stream offline", 409
    end

    -- Дешёвый путь: если у потока уже есть HLS output, возвращаем его без preview-сессии.
    -- Но если UI запросил video_only (фолбэк для браузерной совместимости), HLS нельзя использовать,
    -- потому что там может быть неподдерживаемое аудио (например MP2).
    if not video_only and not audio_aac and not video_h264 then
        -- Если включен global http_play_hls, то /hls/<id>/index.m3u8 доступен даже без per-stream output.
        -- Это самый дешёвый вариант: не запускаем preview-сессию вообще.
        if setting_bool("http_play_hls", false) then
            local out = find_hls_output(stream.channel.config or {}) or { playlist = "index.m3u8" }
            local url = build_direct_hls_url(stream_id, out)
            if url and url ~= "" then
                return { mode = "hls", url = url }
            end
        else
            local out = find_hls_output(stream.channel.config or {})
            if out then
                local url = build_direct_hls_url(stream_id, out)
                if url and url ~= "" then
                    return { mode = "hls", url = url }
                end
            end
        end
    end

    local existing = by_stream[stream_id]
    if existing and sessions[existing] then
        local s = sessions[existing]
        -- Если текущая сессия не совпадает по профилю, перезапускаем.
        if (video_only ~= (s.video_only == true))
            or (audio_aac ~= (s.audio_aac == true))
            or (video_h264 ~= (s.video_h264 == true)) then
            stop_session(existing, "profile_change")
        else
            preview.touch(existing)
            return {
                mode = "preview",
                url = s.url,
                token = s.token,
                expires_in_sec = tonumber(s.expires_in_sec) or nil,
                reused = true,
            }
        end
    end

    local max_sessions, _, ttl = preview_limits()
    local active = 0
    for _ in pairs(sessions) do
        active = active + 1
    end
    if active >= max_sessions then
        return nil, "preview limit reached", 429
    end

    local token = new_token()
    if not token then
        return nil, "failed to generate token", 500
    end

    local output = nil
    local proc = nil
    local base_path = nil
    if video_only then
        local started, start_err, start_code = start_ffmpeg_hls_video_only(token, stream_id)
        if not started then
            return nil, start_err or "preview failed", start_code or 500
        end
        proc = started.proc
        base_path = started.base_path
    elseif audio_aac then
        local started, start_err, start_code = start_ffmpeg_hls_audio_aac(token, stream_id)
        if not started then
            return nil, start_err or "preview failed", start_code or 500
        end
        proc = started.proc
        base_path = started.base_path
    elseif video_h264 then
        local started, start_err, start_code = start_ffmpeg_hls_h264_aac(token, stream_id)
        if not started then
            return nil, start_err or "preview failed", start_code or 500
        end
        proc = started.proc
        base_path = started.base_path
    else
        -- Настройки HLS для предпросмотра.
        local ts_ext = setting_string("hls_ts_extension", "ts")
        if ts_ext == "" then
            ts_ext = "ts"
        end

        output = hls_output({
            upstream = stream.channel.tail:stream(),
            playlist = "index.m3u8",
            prefix = "seg",
            ts_extension = ts_ext,
            pass_data = true,
            use_wall = true,
            naming = "sequence",
            round_duration = false,
            storage = "memfd",
            stream_id = token,
            on_demand = true,
            idle_timeout_sec = setting_number("preview_idle_timeout_sec", 45),
            target_duration = 2,
            window = 4,
            cleanup = 8,
            -- Жёсткий лимит памяти на сессию (для memfd/heap хранения сегментов).
            max_bytes = 32 * 1024 * 1024,
            max_segments = 32,
        })
    end

    local now = os.time()
    sessions[token] = {
        token = token,
        stream_id = stream_id,
        created_at = now,
        last_access_at = now,
        expires_at = now + ttl,
        expires_in_sec = ttl,
        url = "/preview/" .. token .. "/index.m3u8",
        video_only = video_only,
        audio_aac = audio_aac,
        video_h264 = video_h264,
        output = output,
        proc = proc,
        base_path = base_path,
        channel_data = stream.channel,
    }
    by_stream[stream_id] = token

    -- Чтобы поток не остановился от idle, удерживаем его на время preview.
    if _G.channel_retain then
        pcall(function() _G.channel_retain(stream.channel, "preview") end)
    else
        -- Фолбэк: запускаем первый input как в /play.
        if stream.channel.input and stream.channel.input[1] and not stream.channel.input[1].input then
            pcall(function() channel_init_input(stream.channel, 1) end)
        end
    end

    log.info("[preview] start token=" .. token .. " stream=" .. stream_id)
    ensure_sweep_timer()

    return {
        mode = "preview",
        url = sessions[token].url,
        token = token,
        expires_in_sec = ttl,
        reused = false,
    }
end
