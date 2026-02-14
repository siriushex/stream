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

function api.radio_start(server, client, request, stream_id)
    if not radio or type(radio.start) ~= "function" then
        return error_response(server, client, 501, "radio module unavailable")
    end
    local body = parse_json_body(request) or {}
    local ok, err = radio.start(stream_id, body)
    if not ok then
        return error_response(server, client, 400, err or "start failed")
    end
    local status = radio.get_status(stream_id)
    return json_response(server, client, 200, { status = api.radio_payload(status) })
end

function api.radio_stop(server, client, request, stream_id)
    if not radio or type(radio.stop) ~= "function" then
        return error_response(server, client, 501, "radio module unavailable")
    end
    radio.stop(stream_id)
    local status = radio.get_status(stream_id)
    return json_response(server, client, 200, { status = api.radio_payload(status) })
end

function api.radio_restart(server, client, request, stream_id)
    if not radio or type(radio.restart) ~= "function" then
        return error_response(server, client, 501, "radio module unavailable")
    end
    local body = parse_json_body(request) or {}
    local ok, err = radio.restart(stream_id, body)
    if not ok then
        return error_response(server, client, 400, err or "restart failed")
    end
    local status = radio.get_status(stream_id)
    return json_response(server, client, 200, { status = api.radio_payload(status) })
end

function api.radio_status(server, client, request, stream_id)
    if not radio or type(radio.get_status) ~= "function" then
        return error_response(server, client, 501, "radio module unavailable")
    end
    local status = radio.get_status(stream_id)
    return json_response(server, client, 200, { status = api.radio_payload(status) })
end
