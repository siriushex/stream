-- Extra API handlers (PNG -> TS, Create radio)
-- Loaded after api.lua to avoid Lua local limit in the main chunk.

function api.pngts_job_payload(job)
    if not job then
        return nil
    end
    return {
        id = job.id,
        kind = job.kind,
        stream_id = job.stream_id,
        status = job.status,
        error = job.error,
        exit_code = job.exit_code,
        signal = job.signal,
        result = job.result,
        logs = job.logs,
        created_at = job.created_at,
        updated_at = job.updated_at,
    }
end

function api.pngts_ffprobe(server, client, request, stream_id)
    if not pngts or type(pngts.start_ffprobe) ~= "function" then
        return error_response(server, client, 501, "pngts module unavailable")
    end
    local body = parse_json_body(request) or {}
    local input_url = safe_tostring(body.input_url)
    if input_url == "" then
        local row = config.get_stream(stream_id)
        local cfg = row and row.config or nil
        if cfg and type(cfg.input) == "table" and cfg.input[1] then
            input_url = tostring(cfg.input[1])
        end
    end
    if input_url == "" then
        return error_response(server, client, 400, "input_url required")
    end
    local job = pngts.start_ffprobe(stream_id, input_url)
    return json_response(server, client, 200, { job = api.pngts_job_payload(job) })
end

function api.pngts_generate(server, client, request, stream_id)
    if not pngts or type(pngts.start_generate) ~= "function" then
        return error_response(server, client, 501, "pngts module unavailable")
    end
    local body = parse_json_body(request) or {}
    local assets, err = pngts.prepare_assets_from_payload(stream_id, body)
    if not assets then
        return error_response(server, client, 400, err or "invalid assets")
    end

    local image_path = safe_tostring(body.image_path)
    if image_path == "" then
        image_path = safe_tostring(assets.image_path)
    end
    if image_path == "" then
        return error_response(server, client, 400, "image is required")
    end

    local audio_mode = safe_tostring(body.audio_mode)
    if audio_mode == "" then audio_mode = "silence" end
    local audio_preset = safe_tostring(body.beep_preset)
    local mp3_path = safe_tostring(body.mp3_path)
    if mp3_path == "" then
        mp3_path = safe_tostring(assets.mp3_path)
    end
    if audio_mode == "mp3" and mp3_path == "" then
        return error_response(server, client, 400, "mp3 file required")
    end

    local codec = safe_tostring(body.codec)
    local width = tonumber(body.width)
    local height = tonumber(body.height)
    local fps = pngts.parse_fps(body.fps)
    local pix_fmt = safe_tostring(body.pix_fmt)
    local profile = safe_tostring(body.profile)
    local level = safe_tostring(body.level)
    local duration = tonumber(body.duration)
    local video_bitrate = safe_tostring(body.video_bitrate)

    local output_path = safe_tostring(body.output_path)
    if output_path == "" then
        output_path = pngts.build_output_path(stream_id, codec, width, height, fps)
    end

    local opts = {
        image_path = image_path,
        output_path = output_path,
        codec = codec,
        width = width,
        height = height,
        fps = fps,
        pix_fmt = pix_fmt,
        profile = profile,
        level = level,
        duration = duration,
        video_bitrate = video_bitrate,
        audio = {
            mode = audio_mode,
            preset = audio_preset,
            path = mp3_path,
        },
    }

    local job = pngts.start_generate(stream_id, opts)
    return json_response(server, client, 200, { job = api.pngts_job_payload(job) })
end

function api.pngts_job_status(server, client, job_id)
    if not pngts or type(pngts.get_job) ~= "function" then
        return error_response(server, client, 501, "pngts module unavailable")
    end
    local job = pngts.get_job(job_id)
    if not job then
        return error_response(server, client, 404, "job not found")
    end
    return json_response(server, client, 200, { job = api.pngts_job_payload(job) })
end

function api.pngts_list(server, client, request, stream_id)
    if not pngts or type(pngts.list_outputs) ~= "function" then
        return error_response(server, client, 501, "pngts module unavailable")
    end
    local files = pngts.list_outputs(stream_id) or {}
    return json_response(server, client, 200, { files = files })
end

-- Create radio: audio + PNG -> UDP TS
function api.radio_payload(status)
    if not status then
        return nil
    end
    return {
        status = status.status,
        stream_id = status.stream_id,
        start_ts = status.start_ts,
        last_error = status.last_error,
        last_exit = status.last_exit,
        settings = status.settings,
        logs = status.logs,
    }
end

local function radio_is_sharding_master()
    return sharding
        and type(sharding.is_active) == "function"
        and type(sharding.is_master) == "function"
        and sharding.is_active()
        and sharding.is_master()
end

local function radio_get_local_http_port()
    if not config or type(config.get_setting) ~= "function" then
        return 0
    end
    return tonumber(config.get_setting("http_port") or 0) or 0
end

local function radio_get_stream_shard_port(stream_id)
    if not sharding or type(sharding.get_stream_shard_port) ~= "function" then
        return nil
    end
    return sharding.get_stream_shard_port(stream_id)
end

local function radio_get_header(headers, key)
    if type(headers) ~= "table" then
        return nil
    end
    local want = tostring(key or ""):lower()
    for k, v in pairs(headers) do
        if tostring(k or ""):lower() == want then
            return v
        end
    end
    return nil
end

local function radio_get_desired_autostart(stream_id)
    if not config or type(config.get_stream) ~= "function" then
        return false
    end
    local row = config.get_stream(stream_id)
    local cfg = row and row.config or nil
    local rcfg = cfg and cfg.radio or nil
    return (type(rcfg) == "table" and rcfg.autostart == true) and true or false
end

local function radio_persist_config(stream_id, patch, autostart)
    if not config or type(config.get_stream) ~= "function" or type(config.upsert_stream) ~= "function" then
        return nil, "config store unavailable"
    end
    local row = config.get_stream(stream_id)
    if not row then
        return nil, "stream not found"
    end
    local enabled = (tonumber(row.enabled) or 0) ~= 0
    local cfg = row.config or {}
    cfg.id = tostring(cfg.id or stream_id)
    if not cfg.name or tostring(cfg.name) == "" then
        cfg.name = "Stream " .. tostring(stream_id)
    end

    local rcfg = cfg.radio
    if type(rcfg) ~= "table" then
        rcfg = {}
    end

    -- Обновляем только известные поля. Никогда не сохраняем png_data_url (слишком большой payload).
    if type(patch) == "table" then
        local function set(key, value)
            if value ~= nil then
                rcfg[key] = value
            end
        end

        set("audio_url", patch.audio_url)
        set("png_path", patch.png_path)
        set("use_curl", patch.use_curl)
        set("user_agent", patch.user_agent)
        set("extra_headers", patch.extra_headers)
        set("audio_format", patch.audio_format)

        set("fps", patch.fps)
        set("width", patch.width)
        set("height", patch.height)
        set("keep_aspect", patch.keep_aspect)
        set("vcodec", patch.vcodec)
        set("preset", patch.preset)
        set("video_bitrate", patch.video_bitrate)
        set("gop", patch.gop)
        set("pix_fmt", patch.pix_fmt)
        set("tune_stillimage", patch.tune_stillimage)

        set("acodec", patch.acodec)
        set("audio_bitrate", patch.audio_bitrate)
        set("channels", patch.channels)
        set("sample_rate", patch.sample_rate)

        set("output_url", patch.output_url)
        set("log_path", patch.log_path)
        set("pkt_size", patch.pkt_size)
        set("pcr_period", patch.pcr_period)
        set("max_interleave_delta", patch.max_interleave_delta)
        set("muxdelay", patch.muxdelay)

        -- Supervisor настройки (само-восстановление).
        set("auto_restart", patch.auto_restart)
        set("restart_delay_sec", patch.restart_delay_sec or patch.restart_delay)
        set("no_progress_timeout_sec", patch.no_progress_timeout_sec or patch.no_progress_timeout)
        set("max_restarts_per_10min", patch.max_restarts_per_10min)
    end

    rcfg.autostart = autostart and true or false
    cfg.radio = rcfg

    config.upsert_stream(stream_id, enabled, cfg)

    -- Важно: сохранить на диск JSON конфиг, иначе при следующем старте import перезатрёт изменения.
    if config.is_primary_writer and config.export_primary_config
        and config.primary_config_is_json and config.primary_config_is_json()
    then
        local payload, err = config.export_primary_config()
        if not payload then
            return nil, "config export failed: " .. tostring(err)
        end
    end

    return true
end

local function radio_proxy_request(server, client, request, target_port, on_response)
    if not http_request then
        return error_response(server, client, 500, "http_request unavailable")
    end
    local method = request and request.method or "GET"
    local path = request and request.path or "/"
    local body = request and request.content or ""
    if method == "GET" or method == "HEAD" then
        body = ""
    elseif method == "POST" and body == "" then
        body = "{}"
    end
    local content_type = radio_get_header(request and request.headers or nil, "content-type") or "application/json"

    local extra = {}
    if body ~= "" then
        extra[#extra + 1] = "Content-Type: " .. tostring(content_type)
        extra[#extra + 1] = "Content-Length: " .. tostring(#body)
    end

    local headers = sharding and sharding.forward_auth_headers and sharding.forward_auth_headers(request, target_port, extra)
        or {
            "Host: 127.0.0.1:" .. tostring(target_port),
            "Connection: close",
            extra[1],
            extra[2],
        }

    local req_opts = {
        host = "127.0.0.1",
        port = target_port,
        path = path,
        method = method,
        headers = headers,
        connect_timeout_ms = 200,
        read_timeout_ms = 1200,
        callback = function(self, response)
            if type(on_response) == "function" then
                pcall(on_response, response)
            end
            if not response then
                return error_response(server, client, 503, "shard unavailable")
            end
            local code = tonumber(response.code) or 0
            if code <= 0 then
                return error_response(server, client, 503, tostring(response.message or "shard error"))
            end
            local resp_headers = response.headers or {}
            local resp_type = resp_headers["content-type"] or resp_headers["Content-Type"] or "application/json"
            server:send(client, {
                code = code,
                headers = {
                    "Content-Type: " .. tostring(resp_type),
                    "Cache-Control: no-cache",
                    "Connection: close",
                },
                content = response.content or "",
            })
        end,
    }
    if body ~= "" then
        req_opts.content = body
    end

    local ok, err = pcall(http_request, req_opts)
    if not ok then
        return error_response(server, client, 503, "shard request failed: " .. tostring(err))
    end
    return nil
end

function api.radio_start(server, client, request, stream_id)
    if not radio or type(radio.start) ~= "function" then
        return error_response(server, client, 501, "radio module unavailable")
    end

    -- В sharding master режиме запускаем генератор на owning shard, но persistence делаем здесь (writer).
    if radio_is_sharding_master() then
        local target_port = radio_get_stream_shard_port(stream_id)
        local local_port = radio_get_local_http_port()
        if target_port and local_port > 0 and target_port ~= local_port then
            return radio_proxy_request(server, client, request, target_port, function(response)
                if not response or tonumber(response.code) ~= 200 then
                    return
                end
                local ok2, payload = pcall(json.decode, response.content or "")
                if not ok2 or type(payload) ~= "table" then
                    return
                end
                local st = payload.status
                local patch = (type(st) == "table") and st.settings or nil
                local ok3, perr = radio_persist_config(stream_id, patch, true)
                if not ok3 then
                    log.error("[radio] persist failed: " .. tostring(perr))
                end
            end)
        end
    end

    local body = parse_json_body(request) or {}
    local ok, err = radio.start(stream_id, body)
    if not ok then
        return error_response(server, client, 400, err or "start failed")
    end
    local status = radio.get_status(stream_id)
    local patch = status and status.settings or nil
    local pok, perr = radio_persist_config(stream_id, patch, true)
    if not pok then
        return error_response(server, client, 500, perr or "persist failed")
    end
    local payload = api.radio_payload(status)
    if type(payload) == "table" then
        payload.desired_autostart = true
    end
    return json_response(server, client, 200, { status = payload })
end

function api.radio_stop(server, client, request, stream_id)
    if not radio or type(radio.stop) ~= "function" then
        return error_response(server, client, 501, "radio module unavailable")
    end

    if radio_is_sharding_master() then
        local target_port = radio_get_stream_shard_port(stream_id)
        local local_port = radio_get_local_http_port()
        if target_port and local_port > 0 and target_port ~= local_port then
            local ok3, perr = radio_persist_config(stream_id, nil, false)
            if not ok3 then
                log.error("[radio] persist failed: " .. tostring(perr))
            end
            return radio_proxy_request(server, client, request, target_port, nil)
        end
    end

    radio.stop(stream_id)
    local status = radio.get_status(stream_id)
    local pok, perr = radio_persist_config(stream_id, nil, false)
    if not pok then
        return error_response(server, client, 500, perr or "persist failed")
    end
    local payload = api.radio_payload(status)
    if type(payload) == "table" then
        payload.desired_autostart = false
    end
    return json_response(server, client, 200, { status = payload })
end

function api.radio_restart(server, client, request, stream_id)
    if not radio or type(radio.restart) ~= "function" then
        return error_response(server, client, 501, "radio module unavailable")
    end

    if radio_is_sharding_master() then
        local target_port = radio_get_stream_shard_port(stream_id)
        local local_port = radio_get_local_http_port()
        if target_port and local_port > 0 and target_port ~= local_port then
            return radio_proxy_request(server, client, request, target_port, function(response)
                if not response or tonumber(response.code) ~= 200 then
                    return
                end
                local ok2, payload = pcall(json.decode, response.content or "")
                if not ok2 or type(payload) ~= "table" then
                    return
                end
                local st = payload.status
                local patch = (type(st) == "table") and st.settings or nil
                local ok3, perr = radio_persist_config(stream_id, patch, true)
                if not ok3 then
                    log.error("[radio] persist failed: " .. tostring(perr))
                end
            end)
        end
    end

    local body = parse_json_body(request) or {}
    local ok, err = radio.restart(stream_id, body)
    if not ok then
        return error_response(server, client, 400, err or "restart failed")
    end
    local status = radio.get_status(stream_id)
    local patch = status and status.settings or nil
    local pok, perr = radio_persist_config(stream_id, patch, true)
    if not pok then
        return error_response(server, client, 500, perr or "persist failed")
    end
    local payload = api.radio_payload(status)
    if type(payload) == "table" then
        payload.desired_autostart = true
    end
    return json_response(server, client, 200, { status = payload })
end

function api.radio_status(server, client, request, stream_id)
    if not radio or type(radio.get_status) ~= "function" then
        return error_response(server, client, 501, "radio module unavailable")
    end

    if radio_is_sharding_master() then
        local target_port = radio_get_stream_shard_port(stream_id)
        local local_port = radio_get_local_http_port()
        if target_port and local_port > 0 and target_port ~= local_port then
            local desired = radio_get_desired_autostart(stream_id)
            return radio_proxy_request(server, client, request, target_port, function(response)
                if not response or tonumber(response.code) ~= 200 then
                    return
                end
                -- Пытаемся подмешать desired_autostart в payload перед отдачей клиенту.
                local ok2, payload = pcall(json.decode, response.content or "")
                if not ok2 or type(payload) ~= "table" or type(payload.status) ~= "table" then
                    return
                end
                payload.status.desired_autostart = desired
                local ok3, encoded = pcall(json.encode, payload)
                if ok3 and encoded then
                    response.content = encoded
                end
            end)
        end
    end

    local status = radio.get_status(stream_id)
    local payload = api.radio_payload(status)
    if type(payload) == "table" then
        payload.desired_autostart = radio_get_desired_autostart(stream_id)
    end
    return json_response(server, client, 200, { status = payload })
end
