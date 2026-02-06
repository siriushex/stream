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
    return "http://127.0.0.1:" .. tostring(play_port) .. "/play/" .. tostring(stream_id)
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

    local stream = runtime and runtime.streams and runtime.streams[stream_id] or nil
    if not stream then
        return nil, "stream not found", 404
    end
    if stream.kind ~= "stream" or not stream.channel then
        return nil, "preview not supported", 409
    end

    -- Дешёвый путь: если у потока уже есть HLS output, возвращаем его без preview-сессии.
    -- Но если UI запросил video_only (фолбэк для браузерной совместимости), HLS нельзя использовать,
    -- потому что там может быть неподдерживаемое аудио (например MP2).
    if not video_only then
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
        if (video_only and not s.video_only) or ((not video_only) and s.video_only) then
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
