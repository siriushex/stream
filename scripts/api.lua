-- REST API layer

api = {}

local function json_response(server, client, code, payload)
    server:send(client, {
        code = code,
        headers = {
            "Content-Type: application/json",
            "Cache-Control: no-cache",
            "Connection: close",
        },
        content = json.encode(payload or {}),
    })
end

local function error_response(server, client, code, message)
    json_response(server, client, code, { error = message })
end

local function rate_limit_response(server, client, retry_after, message)
    local headers = {
        "Content-Type: application/json",
        "Cache-Control: no-cache",
        "Connection: close",
    }
    if retry_after and retry_after > 0 then
        table.insert(headers, "Retry-After: " .. tostring(retry_after))
    end
    server:send(client, {
        code = 429,
        headers = headers,
        content = json.encode({ error = message or "rate limited" }),
    })
end

local function parse_json_body(request)
    if not request or not request.content then
        return nil
    end
    return json.decode(request.content)
end

local function shell_escape(value)
    local text = tostring(value or "")
    return "'" .. text:gsub("'", "'\\''") .. "'"
end

local function has_timeout()
    local ok = os.execute("command -v timeout >/dev/null 2>&1")
    return ok == true or ok == 0
end

local function run_command(cmd, timeout_sec)
    local timeout_cmd = ""
    if timeout_sec and timeout_sec > 0 then
        if has_timeout() then
            timeout_cmd = "timeout " .. tostring(math.floor(timeout_sec)) .. " "
        else
            return nil, "timeout tool missing"
        end
    end
    local ok, handle = pcall(io.popen, timeout_cmd .. cmd .. " 2>&1")
    if not ok or not handle then
        return nil, "exec failed"
    end
    local output = handle:read("*a") or ""
    handle:close()
    return output
end

local function get_header(headers, key)
    if not headers then
        return nil
    end
    return headers[key] or headers[string.lower(key)]
end

local function setting_number(key, fallback)
    if not config or not config.get_setting then
        return fallback
    end
    local value = config.get_setting(key)
    local number = tonumber(value)
    if number == nil then
        return fallback
    end
    return number
end

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

local function is_state_change(method)
    return method == "POST" or method == "PUT" or method == "DELETE" or method == "PATCH"
end

local function has_bearer_auth(request)
    local auth = request and request.headers and get_header(request.headers, "authorization") or nil
    return auth and auth:find("Bearer ") == 1
end

local function parse_cookie(headers)
    local cookie = get_header(headers, "cookie")
    if not cookie then
        return nil
    end
    local out = {}
    for part in string.gmatch(cookie, "[^;]+") do
        local key, value = part:match("^%s*(.-)%s*=%s*(.*)$")
        if key and value then
            out[key] = value
        end
    end
    return out
end

local function get_token(request)
    local auth = get_header(request.headers, "authorization")
    if auth and auth:find("Bearer ") == 1 then
        return auth:sub(8)
    end

    local cookies = parse_cookie(request.headers)
    if cookies and cookies.astra_session then
        return cookies.astra_session
    end

    return nil
end

local function csrf_required(request)
    if not request or not is_state_change(request.method or "GET") then
        return false
    end
    if has_bearer_auth(request) then
        return false
    end
    return setting_bool("http_csrf_enabled", true)
end

local function check_csrf(request, session)
    if not csrf_required(request) then
        return true
    end
    local header = get_header(request.headers, "x-csrf-token")
    if not header or header == "" then
        return false
    end
    return session and session.token and header == session.token
end

local rate_limits = {
    login = {},
    counter = 0,
}

local auth_session_ttl_cache = {
    ts = 0,
    value = nil,
}

local function get_auth_session_ttl()
    local now = os.time()
    local cached = auth_session_ttl_cache.value
    if cached ~= nil and (now - auth_session_ttl_cache.ts) < 10 then
        return cached
    end
    local ttl = setting_number("auth_session_ttl_sec", 3600)
    if ttl < 300 then
        ttl = 300
    end
    auth_session_ttl_cache.ts = now
    auth_session_ttl_cache.value = ttl
    return ttl
end

local dvb_scan = {
    seq = 0,
    jobs = {},
}

local stream_analyze = {
    seq = 0,
    jobs = {},
    active = 0,
}

local function mpts_scan(server, client, request)
    local body = parse_json_body(request)
    if not body or not body.input then
        return error_response(server, client, 400, "input required")
    end
    local input = tostring(body.input or "")
    if input == "" then
        return error_response(server, client, 400, "input required")
    end
    if #input > 512 then
        return error_response(server, client, 400, "input too long")
    end

    local cfg = parse_url(input)
    if not cfg or not cfg.format then
        return error_response(server, client, 400, "invalid input")
    end
    local format = tostring(cfg.format or ""):lower()
    if format ~= "udp" and format ~= "rtp" then
        return error_response(server, client, 400, "only udp/rtp inputs supported")
    end
    local addr = tostring(cfg.addr or "")
    local port = tonumber(cfg.port)
    if addr == "" or not port then
        return error_response(server, client, 400, "invalid input addr/port")
    end

    local duration = tonumber(body.duration) or 3
    if duration < 1 then duration = 1 end
    if duration > 10 then duration = 10 end

    local script_path = "tools/mpts_pat_scan.py"
    local handle = io.open(script_path, "r")
    if not handle then
        return error_response(server, client, 500, "mpts_pat_scan.py not found")
    end
    handle:close()

    local cmd = table.concat({
        "python3",
        shell_escape(script_path),
        "--addr",
        shell_escape(addr),
        "--port",
        shell_escape(port),
        "--duration",
        shell_escape(duration),
        "--input",
        shell_escape(input),
        "--pretty",
    }, " ")
    local output, err = run_command(cmd, duration + 2)
    if not output or output == "" then
        return error_response(server, client, 500, err or "empty output")
    end
    local ok, parsed = pcall(json.decode, output)
    if not ok or type(parsed) ~= "table" then
        return error_response(server, client, 500, "scan failed: invalid output")
    end
    local services = parsed.services or {}
    return json_response(server, client, 200, { services = services })
end

local function dvb_scan_cleanup()
    local now = os.time()
    for id, job in pairs(dvb_scan.jobs) do
        if job and job.status ~= "running" and job.finished_at and (now - job.finished_at) > 300 then
            dvb_scan.jobs[id] = nil
        end
    end
end

local function stream_analyze_cleanup()
    local now = os.time()
    for id, job in pairs(stream_analyze.jobs) do
        if job and job.status ~= "running" and job.finished_at and (now - job.finished_at) > 300 then
            stream_analyze.jobs[id] = nil
        end
    end
end

local function rate_limit_check(bucket, key, limit, window_sec)
    if limit <= 0 then
        return true, nil
    end
    local now = os.time()
    local entry = bucket[key]
    if not entry or (now - entry.window_start) >= window_sec then
        entry = { window_start = now, count = 0 }
        bucket[key] = entry
    end
    entry.count = entry.count + 1
    if entry.count > limit then
        return false, entry
    end
    return true, entry
end

local function prune_rate_limits(bucket, window_sec)
    local now = os.time()
    for key, entry in pairs(bucket) do
        if not entry or (now - entry.window_start) >= (window_sec * 2) then
            bucket[key] = nil
        end
    end
end

local function require_auth(request)
    local token = get_token(request)
    if not token then
        return nil
    end
    local session = config.get_session(token)
    if not session then
        return nil
    end

    -- Sliding expiration: extend session on activity to reduce repeated logins.
    -- Update is throttled (only when remaining TTL is below 50%).
    if config.extend_session then
        local ttl = get_auth_session_ttl()
        local exp = tonumber(session.expires_at) or 0
        local now = os.time()
        local remaining = exp - now
        if remaining < math.floor(ttl * 0.5) then
            local new_exp = now + ttl
            config.extend_session(token, new_exp)
            session.expires_at = new_exp
        end
    end

    return session
end

local function require_admin(request)
    local session = require_auth(request)
    if not session then
        return nil
    end
    local user = config.get_user_by_id and config.get_user_by_id(session.user_id)
    if not user then
        return nil
    end
    if tonumber(user.is_admin) ~= 1 then
        return nil
    end
    return user
end

local function audit_event(action, request, opts)
    if not config.add_audit_event then
        return
    end
    opts = opts or {}
    opts.ip = opts.ip or (request and request.addr) or ""
    config.add_audit_event(action, opts)
end

local function get_request_user(request)
    local session = require_auth(request)
    if not session then
        return nil
    end
    return config.get_user_by_id and config.get_user_by_id(session.user_id)
end

local function format_refresh_errors(errors)
    if type(errors) ~= "table" or #errors == 0 then
        return nil
    end
    local parts = {}
    for _, entry in ipairs(errors) do
        if type(entry) == "table" then
            table.insert(parts, tostring(entry.id or "?") .. ": " .. tostring(entry.error or "error"))
        else
            table.insert(parts, tostring(entry))
        end
    end
    return table.concat(parts, "; ")
end

local function read_text_file(path)
    local file, err = io.open(path, "rb")
    if not file then
        return nil, err
    end
    local content = file:read("*a")
    file:close()
    return content
end

local function detect_license(text)
    if not text or text == "" then
        return "Unknown", nil
    end
    if text:find("GNU GENERAL PUBLIC LICENSE") then
        local version = text:match("Version%s+([0-9%.]+)")
        local spdx = "GPL"
        if version then
            spdx = "GPL-" .. version
            if not version:find("%.") then
                spdx = spdx .. ".0"
            end
            return "GNU General Public License v" .. version, spdx
        end
        return "GNU General Public License", spdx
    end
    if text:find("GNU LESSER GENERAL PUBLIC LICENSE") then
        local version = text:match("Version%s+([0-9%.]+)")
        local spdx = "LGPL"
        if version then
            spdx = "LGPL-" .. version
            if not version:find("%.") then
                spdx = spdx .. ".0"
            end
            return "GNU Lesser General Public License v" .. version, spdx
        end
        return "GNU Lesser General Public License", spdx
    end
    return "Custom License", nil
end

local function license_info(server, client)
    local path = "COPYING"
    local text, err = read_text_file(path)
    if not text then
        return error_response(server, client, 500, "license file not found")
    end
    local name, spdx = detect_license(text)
    json_response(server, client, 200, {
        name = name,
        spdx = spdx,
        path = path,
        text = text,
    })
end

local function reload_runtime(force)
    local errors = {}
    if runtime and runtime.refresh_adapters then
        runtime.refresh_adapters(force)
    end
    local ok, stream_errors = runtime.refresh(force)
    if ok == false then
        local detail = format_refresh_errors(stream_errors) or "stream refresh failed"
        table.insert(errors, detail)
    end
    if splitter and splitter.refresh then
        splitter.refresh(force)
    end
    if buffer and buffer.refresh then
        buffer.refresh()
    end
    if #errors > 0 then
        return nil, table.concat(errors, "; "), stream_errors
    end
    return true
end

local function validate_config_payload(payload)
    local errors = {}
    local warnings = {}
    local ok, err = config.validate_payload(payload)
    if not ok then
        table.insert(errors, { path = "config", message = err or "invalid config" })
        return errors, warnings
    end

    local lint_errors, lint_warnings = config.lint_payload(payload)
    for _, item in ipairs(lint_errors or {}) do
        table.insert(errors, { path = "config", message = item })
    end
    for _, item in ipairs(lint_warnings or {}) do
        table.insert(warnings, { path = "config", message = item })
    end

    local function check_stream_list(list, label)
        if type(list) ~= "table" then
            return
        end
        local seen = {}
        for idx, entry in ipairs(list) do
            if type(entry) == "table" then
                local id = tostring(entry.id or "")
                if id ~= "" then
                    if seen[id] then
                        table.insert(errors, { path = label .. "[" .. idx .. "]", message = "duplicate id: " .. id })
                    else
                        seen[id] = true
                    end
                end
                if type(validate_stream_config) == "function" then
                    local ok, err = validate_stream_config(entry)
                    if not ok then
                        table.insert(errors, { path = label .. "[" .. idx .. "]", message = err or "invalid stream config" })
                    end
                end
            end
        end
    end

    check_stream_list(payload.make_stream, "make_stream")
    check_stream_list(payload.streams, "streams")

    return errors, warnings
end

local function apply_config_change(server, client, request, opts)
    opts = opts or {}
    local actor = opts.actor
    if not actor then
        local user = get_request_user(request)
        actor = user and user.username or ""
    end

    if type(opts.validate) == "function" then
        local ok, err, details = opts.validate()
        if ok == false then
            return json_response(server, client, 400, {
                error = err or "validation failed",
                errors = details,
            })
        end
    end

    local revision_id = 0
    if config and config.create_revision then
        revision_id = config.create_revision({
            created_by = actor,
            comment = opts.comment or "",
            status = "PENDING",
        })
    end

    local lkg_path = nil
    if config and config.ensure_lkg_snapshot then
        local ok, err = config.ensure_lkg_snapshot()
        if ok then
            lkg_path = ok
        else
            if revision_id > 0 then
                config.update_revision(revision_id, {
                    status = "BAD",
                    error_text = "backup failed: " .. tostring(err),
                })
            end
            return error_response(server, client, 500, "backup failed: " .. tostring(err))
        end
    end

    local primary_exported = false
    local function rollback_primary_config()
        if not primary_exported then
            return
        end
        if config and config.restore_primary_config_from_snapshot and lkg_path then
            local ok, err = config.restore_primary_config_from_snapshot(lkg_path)
            if not ok then
                log.error("[api] primary config rollback failed: " .. tostring(err))
            end
        end
    end

    local apply_result = nil
    if type(opts.apply) == "function" then
        local ok, res = pcall(opts.apply)
        if not ok then
            if revision_id > 0 then
                config.update_revision(revision_id, { status = "BAD", error_text = tostring(res) })
            end
            return error_response(server, client, 500, "apply failed: " .. tostring(res))
        end
        if res == false then
            if revision_id > 0 then
                config.update_revision(revision_id, { status = "BAD", error_text = tostring(opts.apply_error or "apply failed") })
            end
            return error_response(server, client, 500, tostring(opts.apply_error or "apply failed"))
        end
        apply_result = res
    end

    if config and config.primary_config_is_json and config.primary_config_is_json()
        and config.export_primary_config then
        local ok, err = config.export_primary_config()
        if not ok then
            if revision_id > 0 then
                config.update_revision(revision_id, {
                    status = "BAD",
                    error_text = "config export failed: " .. tostring(err),
                })
            end
            if lkg_path then
                config.restore_snapshot(lkg_path)
                rollback_primary_config()
                reload_runtime(true)
            end
            return error_response(server, client, 500, "config export failed: " .. tostring(err))
        end
        primary_exported = true
    end

    local snapshot_path = nil
    if revision_id > 0 and config and config.build_snapshot_path then
        snapshot_path = config.build_snapshot_path(revision_id)
        local payload, snap_err = config.export_astra_file(snapshot_path)
        if not payload then
            config.update_revision(revision_id, {
                status = "BAD",
                error_text = "snapshot failed: " .. tostring(snap_err),
                snapshot_path = snapshot_path,
            })
            if lkg_path then
                config.restore_snapshot(lkg_path)
                rollback_primary_config()
                reload_runtime(true)
            end
            return error_response(server, client, 500, "snapshot failed: " .. tostring(snap_err))
        end
    end

    local ok = true
    local reload_err = nil
    if type(opts.runtime_apply) == "function" then
        local apply_ok, apply_err
        local safe, res_ok, res_err = pcall(opts.runtime_apply)
        if not safe then
            apply_ok = false
            apply_err = res_ok
        else
            apply_ok = (res_ok ~= false)
            apply_err = res_err
        end
        ok = apply_ok
        reload_err = apply_err
    else
        ok, reload_err = reload_runtime(true)
    end
    if not ok then
        if revision_id > 0 then
            config.update_revision(revision_id, {
                status = "BAD",
                error_text = tostring(reload_err or "reload failed"),
                snapshot_path = snapshot_path,
            })
        end
        if config and config.add_alert then
            config.add_alert("CRITICAL", "", "CONFIG_RELOAD_FAILED",
                tostring(reload_err or "reload failed"),
                { revision_id = revision_id })
        end
        if lkg_path then
            config.restore_snapshot(lkg_path)
            rollback_primary_config()
            reload_runtime(true)
        end
        return json_response(server, client, 409, {
            error = "Config rejected, rolled back",
            detail = reload_err,
            revision_id = revision_id,
        })
    end

    if revision_id > 0 then
        config.update_revision(revision_id, {
            status = "ACTIVE",
            applied_ts = os.time(),
            snapshot_path = snapshot_path,
        })
        config.set_setting("config_active_revision_id", revision_id)
        config.set_setting("config_lkg_revision_id", revision_id)
        if config.update_lkg_snapshot then
            config.update_lkg_snapshot()
        end
        local max_keep = config.get_setting("config_max_revisions")
        config.prune_revisions(max_keep)
        if config.mark_boot_ok then
            config.mark_boot_ok(revision_id)
        end
    end
    if config and config.add_alert then
        config.add_alert("INFO", "", "CONFIG_RELOAD_OK", "config applied", {
            revision_id = revision_id,
        })
    end

    -- In sharded setups other processes must reload runtime to pick up DB changes.
    -- This is best-effort and should not block config apply.
    if sharding and type(sharding.broadcast_reload) == "function" then
        pcall(sharding.broadcast_reload)
    end

    local body = nil
    if type(opts.success_builder) == "function" then
        body = opts.success_builder(apply_result, revision_id)
    else
        body = { status = "ok", revision_id = revision_id }
    end
    if type(opts.after) == "function" then
        local ok, err = pcall(opts.after, apply_result, revision_id)
        if not ok then
            log.error("[api] after hook failed: " .. tostring(err))
        end
    end
    json_response(server, client, 200, body)
end

local function list_streams(server, client)
    local rows = config.list_streams()
    local result = {}
    for _, row in ipairs(rows) do
        table.insert(result, {
            id = row.id,
            enabled = (tonumber(row.enabled) or 0) ~= 0,
            config = row.config,
        })
    end
    json_response(server, client, 200, result)
end

local function get_stream(server, client, id)
    local row = config.get_stream(id)
    if not row then
        return error_response(server, client, 404, "stream not found")
    end
    json_response(server, client, 200, {
        id = row.id,
        enabled = (tonumber(row.enabled) or 0) ~= 0,
        config = row.config,
    })
end

local function start_stream_preview(server, client, request, stream_id)
    if not preview or not preview.start then
        return error_response(server, client, 501, "preview unavailable")
    end
    local opts = {}
    local q = request and request.query or {}
    local vo = q.video_only or q.videoonly or q.vo or nil
    if vo ~= nil then
        local v = tostring(vo):lower()
        opts.video_only = (v == "1" or v == "true" or v == "yes" or v == "on")
    end
    local aa = q.audio_aac or q.audioaac or q.aac or nil
    if aa ~= nil then
        local v = tostring(aa):lower()
        opts.audio_aac = (v == "1" or v == "true" or v == "yes" or v == "on")
    end
    local audio = q.audio or q.a or nil
    if audio ~= nil then
        local v = tostring(audio):lower()
        if v == "aac" then
            opts.audio_aac = true
        end
    end
    local h264 = q.h264 or q.video_h264 or q.vh264 or nil
    if h264 ~= nil then
        local v = tostring(h264):lower()
        opts.video_h264 = (v == "1" or v == "true" or v == "yes" or v == "on")
    end
    if opts.video_only then
        -- video_only уже подразумевает "без аудио", поэтому игнорируем audio_aac.
        opts.audio_aac = false
    end
    local result, err, code = preview.start(stream_id, opts)
    if not result then
        return error_response(server, client, code or 500, err or "preview failed")
    end
    if result.mode == "hls" then
        return json_response(server, client, 200, {
            url = result.url,
            mode = "hls",
        })
    end
    return json_response(server, client, 200, {
        url = result.url,
        token = result.token,
        expires_in_sec = result.expires_in_sec,
        mode = "preview",
        reused = result.reused == true,
    })
end

local function stop_stream_preview(server, client, request, stream_id)
    if not preview or not preview.stop then
        return error_response(server, client, 501, "preview unavailable")
    end
    preview.stop(stream_id)
    return json_response(server, client, 200, { status = "ok" })
end

local function upsert_stream(server, client, id, request)
    local body = parse_json_body(request)
    if not body then
        return error_response(server, client, 400, "invalid json")
    end

    local function config_is_empty(tbl)
        if type(tbl) ~= "table" then
            return true
        end
        return next(tbl) == nil
    end

    local function is_enabled_only_patch(payload)
        if type(payload) ~= "table" then
            return false
        end
        for k, _ in pairs(payload) do
            if k ~= "enabled" and k ~= "id" and k ~= "config" then
                return false
            end
        end
        return true
    end

    local existing = nil
    if config and config.get_stream then
        existing = config.get_stream(id)
    end

    -- For updates, treat missing `enabled` as "keep current" (avoids accidental re-enable).
    -- For new streams, keep the historical default: enabled unless explicitly `false`.
    local enabled = nil
    if body.enabled == nil and existing then
        enabled = (tonumber(existing.enabled) or 0) ~= 0
    else
        enabled = (body.enabled ~= false)
    end

    local cfg = nil
    if not config_is_empty(body.config) then
        cfg = body.config
    elseif existing and is_enabled_only_patch(body) then
        -- Allow enabled-only patches without requiring clients to re-send the full stream config.
        cfg = existing.config or {}
    else
        -- Legacy behavior: accept stream config fields on the top-level object.
        cfg = body
        cfg.enabled = nil
        cfg.config = nil
    end
    cfg.id = id

    if not cfg.name then
        cfg.name = "Stream " .. id
    end
    if type(sanitize_stream_config) == "function" then
        sanitize_stream_config(cfg)
    end
    apply_config_change(server, client, request, {
        comment = "stream " .. id,
        validate = function()
            if enabled and type(validate_stream_config) == "function" then
                local ok, err = validate_stream_config(cfg)
                if not ok then
                    return false, err or "invalid stream config", {
                        { path = "stream", message = err or "invalid stream config" },
                    }
                end
            end
            return true
        end,
        apply = function()
            config.upsert_stream(id, enabled, cfg)
        end,
        runtime_apply = function()
            if not runtime or not runtime.apply_stream_row then
                return false, "runtime apply not available"
            end
            local row = config.get_stream(id)
            if not row then
                return false, "stream not found after update"
            end
            return runtime.apply_stream_row(row, true)
        end,
        after = function()
            if epg and epg.export_all then
                epg.export_all("stream change")
            end
        end,
    })
end

local function delete_stream(server, client, id, request)
    apply_config_change(server, client, request, {
        comment = "stream " .. id .. " delete",
        apply = function()
            config.delete_stream(id)
        end,
        runtime_apply = function()
            if not runtime or not runtime.apply_stream_row then
                return false, "runtime apply not available"
            end
            return runtime.apply_stream_row({ id = id, enabled = 0, config = {} }, true)
        end,
        after = function()
            if epg and epg.export_all then
                epg.export_all("stream delete")
            end
        end,
    })
end

local function purge_disabled_streams(server, client, request)
    local admin = require_admin(request)
    if not admin then
        return error_response(server, client, 403, "forbidden")
    end

    local rows = config.list_streams()
    local ids = {}
    for _, row in ipairs(rows) do
        if (tonumber(row.enabled) or 0) == 0 then
            table.insert(ids, row.id)
        end
    end
    if #ids == 0 then
        return json_response(server, client, 200, { status = "ok", deleted = 0 })
    end
    table.sort(ids)

    apply_config_change(server, client, request, {
        actor = admin.username,
        comment = "purge disabled streams",
        apply = function()
            for _, id in ipairs(ids) do
                config.delete_stream(id)
            end
            return { deleted = #ids }
        end,
        runtime_apply = function()
            if not runtime or not runtime.apply_stream_row then
                return false, "runtime apply not available"
            end
            for _, id in ipairs(ids) do
                local ok, err = runtime.apply_stream_row({ id = id, enabled = 0, config = {} }, true)
                if ok == false then
                    return false, err or ("runtime delete failed: " .. id)
                end
            end
            return true
        end,
        after = function()
            if epg and epg.export_all then
                epg.export_all("stream purge disabled")
            end
        end,
        success_builder = function(res, revision_id)
            return {
                status = "ok",
                deleted = res and (tonumber(res.deleted) or 0) or 0,
                revision_id = revision_id,
            }
        end,
    })
end

local function detect_nvidia_available()
    local ok, handle = pcall(io.popen, "nvidia-smi -L 2>/dev/null")
    if not ok or not handle then
        return false
    end
    local out = handle:read("*a") or ""
    handle:close()
    return out:match("GPU%s+%d+") ~= nil
end

local function build_default_transcode_ladder(base_id, base_name)
    local engine = detect_nvidia_available() and "nvidia" or "cpu"
    local tc = {
        engine = engine,
        ffmpeg_global_args = { "-fflags", "+genpts" },
        profiles = {
            {
                id = "SD",
                name = "540p",
                width = 960,
                height = 540,
                fps = 25,
                bitrate_kbps = 1200,
                maxrate_kbps = 1500,
            },
        },
        publish = {
            {
                type = "hls",
                enabled = true,
                variants = { "SD" },
                storage = "memfd",
            },
        },
        watchdog = {
            restart_delay_sec = 1,
            restart_jitter_sec = 1,
            restart_backoff_base_sec = 1,
            restart_backoff_max_sec = 10,
            no_progress_timeout_sec = 30,
            max_error_lines_per_min = 200,
            probe_interval_sec = 0,
            max_restarts_per_10min = 10,
            restart_cooldown_sec = 0,
        },
    }
    if engine == "nvidia" then
        -- Auto-distribute across GPUs by picking the least busy device at runtime.
        tc.gpu_device = "auto"
    end
    return {
        id = base_id,
        name = (base_name and ("Transcode " .. tostring(base_name))) or ("Transcode " .. tostring(base_id)),
        type = "transcode",
        input = { "stream://" .. tostring(base_id) },
        transcode = tc,
    }
end

local function transcode_all_streams(server, client, request)
    local admin = require_admin(request)
    if not admin then
        return error_response(server, client, 403, "forbidden")
    end

    local body = parse_json_body(request) or {}
    local enable_requested = body and (body.enable == true or body.enable == 1 or body.enable == "1")
    -- Safety first: avoid CPU/RAM spikes. We only create streams disabled by default.
    if enable_requested then
        enable_requested = false
    end

    local rows = config.list_streams()
    local by_id = {}
    for _, row in ipairs(rows) do
        by_id[row.id] = row
    end

    local targets = {}
    local skipped = 0
    for _, row in ipairs(rows) do
        local enabled = (tonumber(row.enabled) or 0) ~= 0
        if enabled then
            local cfg = row.config or {}
            local stype = tostring(cfg.type or ""):lower()
            if stype ~= "transcode" and stype ~= "ffmpeg" then
                local base_id = row.id
                local tc_id = "tc_" .. tostring(base_id)
                if by_id[tc_id] then
                    skipped = skipped + 1
                else
                    table.insert(targets, { base_id = base_id, tc_id = tc_id, base_name = cfg.name })
                end
            end
        end
    end

    if #targets == 0 then
        return json_response(server, client, 200, { status = "ok", created = 0, skipped = skipped })
    end

    table.sort(targets, function(a, b) return tostring(a.tc_id) < tostring(b.tc_id) end)

    apply_config_change(server, client, request, {
        actor = admin.username,
        comment = "transcode all streams",
        validate = function()
            for _, item in ipairs(targets) do
                local cfg = build_default_transcode_ladder(item.base_id, item.base_name)
                cfg.id = item.tc_id
                if type(validate_stream_config) == "function" then
                    local ok, err = validate_stream_config(cfg)
                    if not ok then
                        return false, err or ("invalid transcode config: " .. tostring(item.tc_id)), {
                            { path = "stream", message = err or "invalid transcode config" },
                        }
                    end
                end
            end
            return true
        end,
        apply = function()
            for _, item in ipairs(targets) do
                local cfg = build_default_transcode_ladder(item.base_id, item.base_name)
                cfg.id = item.tc_id
                config.upsert_stream(item.tc_id, false, cfg)
            end
            return { created = #targets, skipped = skipped }
        end,
        runtime_apply = function()
            if not runtime or not runtime.apply_stream_row then
                return false, "runtime apply not available"
            end
            for _, item in ipairs(targets) do
                local row = config.get_stream(item.tc_id)
                if row then
                    local ok, err = runtime.apply_stream_row(row, true)
                    if ok == false then
                        return false, err or ("runtime apply failed: " .. tostring(item.tc_id))
                    end
                end
            end
            return true
        end,
        success_builder = function(res, revision_id)
            return {
                status = "ok",
                created = res and (tonumber(res.created) or 0) or 0,
                skipped = res and (tonumber(res.skipped) or 0) or 0,
                revision_id = revision_id,
            }
        end,
    })
end

local function list_adapters(server, client)
    local rows = config.list_adapters()
    local result = {}
    for _, row in ipairs(rows) do
        table.insert(result, {
            id = row.id,
            enabled = (tonumber(row.enabled) or 0) ~= 0,
            config = row.config,
        })
    end
    json_response(server, client, 200, result)
end

local function get_adapter(server, client, id)
    local row = config.get_adapter(id)
    if not row then
        return error_response(server, client, 404, "adapter not found")
    end
    json_response(server, client, 200, {
        id = row.id,
        enabled = (tonumber(row.enabled) or 0) ~= 0,
        config = row.config,
    })
end

local function upsert_adapter(server, client, id, request)
    local body = parse_json_body(request)
    if not body then
        return error_response(server, client, 400, "invalid json")
    end

    local function config_is_empty(tbl)
        if type(tbl) ~= "table" then
            return true
        end
        return next(tbl) == nil
    end

    local function is_enabled_only_patch(payload)
        if type(payload) ~= "table" then
            return false
        end
        for k, _ in pairs(payload) do
            if k ~= "enabled" and k ~= "id" and k ~= "config" then
                return false
            end
        end
        return true
    end

    local existing = nil
    if config and config.get_adapter then
        existing = config.get_adapter(id)
    end

    -- For updates, treat missing `enabled` as "keep current" (avoids accidental re-enable).
    -- For new adapters, keep the historical default: enabled unless explicitly `false`.
    local enabled = nil
    if body.enabled == nil and existing then
        enabled = (tonumber(existing.enabled) or 0) ~= 0
    else
        enabled = (body.enabled ~= false)
    end

    local cfg = nil
    if not config_is_empty(body.config) then
        cfg = body.config
    elseif existing and is_enabled_only_patch(body) then
        -- Allow enabled-only patches without requiring clients to re-send the full adapter config.
        cfg = existing.config or {}
    else
        -- Legacy behavior: accept adapter config fields on the top-level object.
        cfg = body
        cfg.enabled = nil
        cfg.config = nil
    end
    cfg.id = id

    apply_config_change(server, client, request, {
        comment = "adapter " .. id,
        apply = function()
            config.upsert_adapter(id, enabled, cfg)
        end,
    })
end

local function delete_adapter(server, client, id, request)
    apply_config_change(server, client, request, {
        comment = "adapter " .. id .. " delete",
        apply = function()
            config.delete_adapter(id)
        end,
    })
end

local function generate_id(prefix)
    local stamp = os.time()
    local rand = math.random(1000, 9999)
    return tostring(prefix or "id") .. "_" .. tostring(stamp) .. "_" .. tostring(rand)
end

local function splitter_row_payload(row, links_count)
    return {
        id = row.id,
        name = row.name,
        enable = (tonumber(row.enable) or 0) ~= 0,
        port = tonumber(row.port) or 0,
        in_interface = row.in_interface,
        out_interface = row.out_interface,
        logtype = row.logtype,
        logpath = row.logpath,
        config_path = row.config_path,
        links_count = links_count or 0,
        created = row.created,
        updated = row.updated,
    }
end

local function list_splitters(server, client)
    local rows = config.list_splitters()
    local result = {}
    for _, row in ipairs(rows) do
        local links = config.list_splitter_links(row.id)
        table.insert(result, splitter_row_payload(row, #links))
    end
    json_response(server, client, 200, result)
end

local function get_splitter(server, client, id)
    local row = config.get_splitter(id)
    if not row then
        return error_response(server, client, 404, "splitter not found")
    end
    local links = config.list_splitter_links(id)
    json_response(server, client, 200, splitter_row_payload(row, #links))
end

local function upsert_splitter(server, client, id, request)
    local body = parse_json_body(request)
    if not body then
        return error_response(server, client, 400, "invalid json")
    end

    local port = tonumber(body.port)
    if not port or port < 1 or port > 65535 then
        return error_response(server, client, 400, "invalid port")
    end

    apply_config_change(server, client, request, {
        comment = "splitter " .. id,
        apply = function()
            config.upsert_splitter(id, body)
        end,
        success_builder = function(_, revision_id)
            return { status = "ok", id = id, revision_id = revision_id }
        end,
    })
end

local function delete_splitter(server, client, id, request)
    apply_config_change(server, client, request, {
        comment = "splitter " .. id .. " delete",
        apply = function()
            config.delete_splitter(id)
        end,
    })
end

local function list_splitter_links(server, client, splitter_id)
    if not config.get_splitter(splitter_id) then
        return error_response(server, client, 404, "splitter not found")
    end
    local rows = config.list_splitter_links(splitter_id)
    local result = {}
    for _, row in ipairs(rows) do
        table.insert(result, {
            id = row.id,
            splitter_id = row.splitter_id,
            enable = (tonumber(row.enable) or 0) ~= 0,
            url = row.url,
            bandwidth = row.bandwidth,
            buffering = row.buffering,
            created = row.created,
            updated = row.updated,
        })
    end
    json_response(server, client, 200, result)
end

local function upsert_splitter_link(server, client, splitter_id, link_id, request)
    if not config.get_splitter(splitter_id) then
        return error_response(server, client, 404, "splitter not found")
    end
    local body = parse_json_body(request)
    if not body then
        return error_response(server, client, 400, "invalid json")
    end
    local url = tostring(body.url or "")
    local parsed = parse_url(url)
    if not parsed or parsed.format ~= "http" then
        return error_response(server, client, 400, "hlssplitter supports http urls only")
    end
    apply_config_change(server, client, request, {
        comment = "splitter " .. splitter_id .. " link " .. link_id,
        apply = function()
            config.upsert_splitter_link(splitter_id, link_id, body)
        end,
        success_builder = function(_, revision_id)
            return { status = "ok", id = link_id, revision_id = revision_id }
        end,
    })
end

local function delete_splitter_link(server, client, splitter_id, link_id, request)
    if not config.get_splitter(splitter_id) then
        return error_response(server, client, 404, "splitter not found")
    end
    apply_config_change(server, client, request, {
        comment = "splitter " .. splitter_id .. " link " .. link_id .. " delete",
        apply = function()
            config.delete_splitter_link(splitter_id, link_id)
        end,
    })
end

local function list_splitter_allow(server, client, splitter_id)
    if not config.get_splitter(splitter_id) then
        return error_response(server, client, 404, "splitter not found")
    end
    local rows = config.list_splitter_allow(splitter_id)
    local result = {}
    for _, row in ipairs(rows) do
        table.insert(result, {
            id = row.id,
            splitter_id = row.splitter_id,
            kind = row.kind,
            value = row.value,
            created = row.created,
        })
    end
    json_response(server, client, 200, result)
end

local function parse_ipv4(value)
    if not value then
        return nil
    end
    local a, b, c, d = tostring(value):match("^%s*(%d+)%.(%d+)%.(%d+)%.(%d+)%s*$")
    if not a then
        return nil
    end
    a = tonumber(a)
    b = tonumber(b)
    c = tonumber(c)
    d = tonumber(d)
    if not a or not b or not c or not d then
        return nil
    end
    if a > 255 or b > 255 or c > 255 or d > 255 then
        return nil
    end
    return true
end

local function parse_cidr(value)
    local base, prefix = tostring(value or ""):match("^%s*(.-)%s*/%s*(%d+)%s*$")
    if not base then
        return false
    end
    local num = tonumber(prefix)
    if not num or num < 0 or num > 32 then
        return false
    end
    return parse_ipv4(base) ~= nil
end

local function parse_allow_range(value)
    local text = tostring(value or "")
    local from_ip, to_ip = text:match("^%s*([^%s,%-]+)%s*[,%-]%s*([^%s,%-]+)%s*$")
    if not from_ip then
        from_ip, to_ip = text:match("^%s*([^%s]+)%s*%.%.%s*([^%s]+)%s*$")
    end
    if not from_ip or not to_ip then
        return false
    end
    if not parse_ipv4(from_ip) or not parse_ipv4(to_ip) then
        return false
    end
    return true
end

local function add_splitter_allow(server, client, splitter_id, request)
    if not config.get_splitter(splitter_id) then
        return error_response(server, client, 404, "splitter not found")
    end
    local body = parse_json_body(request)
    if not body then
        return error_response(server, client, 400, "invalid json")
    end
    local kind = tostring(body.kind or "")
    if kind ~= "allow" and kind ~= "allowRange" then
        return error_response(server, client, 400, "invalid allow kind")
    end
    local value = tostring(body.value or "")
    if value == "" then
        return error_response(server, client, 400, "allow value required")
    end
    if kind == "allowRange" then
        if not parse_cidr(value) and not parse_allow_range(value) then
            return error_response(server, client, 400, "invalid allowRange value")
        end
    end
    local id = body.id or generate_id("allow")
    apply_config_change(server, client, request, {
        comment = "splitter " .. splitter_id .. " allow " .. id,
        apply = function()
            config.add_splitter_allow(splitter_id, id, kind, value)
        end,
        success_builder = function(_, revision_id)
            return { status = "ok", id = id, revision_id = revision_id }
        end,
    })
end

local function delete_splitter_allow(server, client, splitter_id, rule_id, request)
    if not config.get_splitter(splitter_id) then
        return error_response(server, client, 404, "splitter not found")
    end
    apply_config_change(server, client, request, {
        comment = "splitter " .. splitter_id .. " allow " .. rule_id .. " delete",
        apply = function()
            config.delete_splitter_allow(splitter_id, rule_id)
        end,
    })
end

local function start_splitter(server, client, id)
    local ok = splitter and splitter.start and splitter.start(id)
    if not ok then
        return error_response(server, client, 404, "splitter not found")
    end
    json_response(server, client, 200, { status = "ok" })
end

local function stop_splitter(server, client, id)
    local ok = splitter and splitter.stop and splitter.stop(id)
    if not ok then
        return error_response(server, client, 404, "splitter not found")
    end
    json_response(server, client, 200, { status = "ok" })
end

local function restart_splitter(server, client, id)
    local ok = splitter and splitter.restart and splitter.restart(id)
    if not ok then
        return error_response(server, client, 404, "splitter not found")
    end
    json_response(server, client, 200, { status = "ok" })
end

local function apply_splitter_config(server, client, id)
    local ok = splitter and splitter.apply_config and splitter.apply_config(id)
    if not ok then
        return error_response(server, client, 404, "splitter not found")
    end
    json_response(server, client, 200, { status = "ok" })
end

local function get_splitter_config(server, client, id)
    if not config.get_splitter(id) then
        return error_response(server, client, 404, "splitter not found")
    end
    if not splitter or not splitter.render_config then
        return error_response(server, client, 500, "splitter config unavailable")
    end
    local xml, err = splitter.render_config(id)
    if not xml then
        return error_response(server, client, 404, err or "splitter not found")
    end
    server:send(client, {
        code = 200,
        headers = {
            "Content-Type: application/xml; charset=utf-8",
            "Cache-Control: no-cache",
            "Connection: close",
        },
        content = xml,
    })
end

local function list_splitter_status(server, client)
    local status = splitter and splitter.list_status and splitter.list_status() or {}
    json_response(server, client, 200, status)
end

local function get_splitter_status(server, client, id)
    local status = splitter and splitter.get_status and splitter.get_status(id)
    if not status then
        return error_response(server, client, 404, "splitter not found")
    end
    json_response(server, client, 200, status)
end

local function normalize_buffer_path(value)
    local path = tostring(value or "")
    if path == "" then
        return ""
    end
    if path:sub(1, 1) ~= "/" then
        path = "/" .. path
    end
    return path
end

local function buffer_output_url(path)
    local host = setting_string("buffer_listen_host", "0.0.0.0")
    local port = setting_number("buffer_listen_port", 8089)
    local display_host = host
    if display_host == "" or display_host == "0.0.0.0" then
        display_host = "<server_ip>"
    end
    local normalized = normalize_buffer_path(path or "")
    return "http://" .. display_host .. ":" .. tostring(port) .. normalized
end

local function buffer_resource_payload(row)
    return {
        id = row.id,
        name = row.name,
        path = row.path,
        enable = (tonumber(row.enable) or 0) ~= 0,
        backup_type = row.backup_type,
        no_data_timeout_sec = row.no_data_timeout_sec,
        backup_start_delay_sec = row.backup_start_delay_sec,
        backup_return_delay_sec = row.backup_return_delay_sec,
        backup_probe_interval_sec = row.backup_probe_interval_sec,
        active_input_index = row.active_input_index,
        buffering_sec = row.buffering_sec,
        bandwidth_kbps = row.bandwidth_kbps,
        client_start_offset_sec = row.client_start_offset_sec,
        max_client_lag_ms = row.max_client_lag_ms,
        smart_start_enabled = row.smart_start_enabled ~= 0,
        smart_target_delay_ms = row.smart_target_delay_ms,
        smart_lookback_ms = row.smart_lookback_ms,
        smart_require_pat_pmt = row.smart_require_pat_pmt ~= 0,
        smart_require_keyframe = row.smart_require_keyframe ~= 0,
        smart_require_pcr = row.smart_require_pcr ~= 0,
        smart_wait_ready_ms = row.smart_wait_ready_ms,
        smart_max_lead_ms = row.smart_max_lead_ms,
        keyframe_detect_mode = row.keyframe_detect_mode,
        av_pts_align_enabled = row.av_pts_align_enabled ~= 0,
        av_pts_max_desync_ms = row.av_pts_max_desync_ms,
        paramset_required = row.paramset_required ~= 0,
        start_debug_enabled = row.start_debug_enabled ~= 0,
        ts_resync_enabled = row.ts_resync_enabled ~= 0,
        ts_drop_corrupt_enabled = row.ts_drop_corrupt_enabled ~= 0,
        ts_rewrite_cc_enabled = row.ts_rewrite_cc_enabled ~= 0,
        pacing_mode = row.pacing_mode,
        created = row.created,
        updated = row.updated,
    }
end

local function buffer_input_payload(row)
    return {
        id = row.id,
        resource_id = row.resource_id,
        enable = (tonumber(row.enable) or 0) ~= 0,
        url = row.url,
        priority = row.priority,
        created = row.created,
        updated = row.updated,
    }
end

local function buffer_allow_payload(row)
    return {
        id = row.id,
        kind = row.kind,
        value = row.value,
        created = row.created,
    }
end

local function list_buffer_resources(server, client)
    local rows = config.list_buffer_resources()
    local result = {}
    for _, row in ipairs(rows) do
        table.insert(result, buffer_resource_payload(row))
    end
    json_response(server, client, 200, result)
end

local function get_buffer_resource(server, client, id)
    local row = config.get_buffer_resource(id)
    if not row then
        return error_response(server, client, 404, "buffer resource not found")
    end
    json_response(server, client, 200, buffer_resource_payload(row))
end

local function upsert_buffer_resource(server, client, id, body, request)
    if not body then
        return error_response(server, client, 400, "invalid json")
    end
    local body_id = tostring(body.id or "")
    if body_id == "" then
        return error_response(server, client, 400, "buffer id required")
    end
    if body_id ~= id then
        return error_response(server, client, 400, "buffer id mismatch")
    end
    log.debug("[buffers] save resource id=" .. id .. " payload=" .. json.encode(body))
    local path = normalize_buffer_path(body.path or "")
    if path == "" then
        return error_response(server, client, 400, "path required")
    end
    local by_path = config.get_buffer_resource_by_path(path)
    if by_path and by_path.id ~= id then
        return error_response(server, client, 400, "path already in use")
    end
    body.path = path
    apply_config_change(server, client, request, {
        comment = "buffer resource " .. id,
        validate = function()
            if path == "" then
                return false, "path required", { { path = "path", message = "path required" } }
            end
            return true
        end,
        apply = function()
            config.upsert_buffer_resource(id, body)
        end,
        success_builder = function(_, revision_id)
            local row = config.get_buffer_resource(id)
            if not row then
                return { status = "ok", revision_id = revision_id }
            end
            local payload = buffer_resource_payload(row)
            payload.revision_id = revision_id
            return payload
        end,
    })
end

local function delete_buffer_resource(server, client, id, request)
    apply_config_change(server, client, request, {
        comment = "buffer resource " .. id .. " delete",
        apply = function()
            config.delete_buffer_resource(id)
        end,
    })
end

local function list_buffer_inputs(server, client, resource_id)
    if not config.get_buffer_resource(resource_id) then
        return error_response(server, client, 404, "buffer resource not found")
    end
    local rows = config.list_buffer_inputs(resource_id)
    local result = {}
    for _, row in ipairs(rows) do
        table.insert(result, buffer_input_payload(row))
    end
    json_response(server, client, 200, result)
end

local function upsert_buffer_input(server, client, resource_id, input_id, body, request)
    if not config.get_buffer_resource(resource_id) then
        return error_response(server, client, 404, "buffer resource not found")
    end
    if not body then
        return error_response(server, client, 400, "invalid json")
    end
    log.debug("[buffers] save input resource=" .. resource_id .. " id=" .. input_id ..
        " payload=" .. json.encode(body))
    local url = tostring(body.url or "")
    local parsed = parse_url(url)
    if not parsed or parsed.format ~= "http" then
        return error_response(server, client, 400, "buffer supports http urls only")
    end
    apply_config_change(server, client, request, {
        comment = "buffer input " .. resource_id .. "/" .. input_id,
        apply = function()
            config.upsert_buffer_input(resource_id, input_id, body)
        end,
        success_builder = function(_, revision_id)
            local row = nil
            local rows = config.list_buffer_inputs(resource_id)
            for _, item in ipairs(rows) do
                if item.id == input_id then
                    row = item
                    break
                end
            end
            if not row then
                return { status = "ok", revision_id = revision_id }
            end
            local payload = buffer_input_payload(row)
            payload.revision_id = revision_id
            return payload
        end,
    })
end

local function delete_buffer_input(server, client, resource_id, input_id, request)
    if not config.get_buffer_resource(resource_id) then
        return error_response(server, client, 404, "buffer resource not found")
    end
    apply_config_change(server, client, request, {
        comment = "buffer input " .. resource_id .. "/" .. input_id .. " delete",
        apply = function()
            config.delete_buffer_input(resource_id, input_id)
        end,
    })
end

local function list_buffer_allow(server, client)
    local rows = config.list_buffer_allow()
    local result = {}
    for _, row in ipairs(rows) do
        table.insert(result, buffer_allow_payload(row))
    end
    json_response(server, client, 200, result)
end

local function add_buffer_allow(server, client, body, request)
    if not body then
        return error_response(server, client, 400, "invalid json")
    end
    local kind = tostring(body.kind or "")
    if kind ~= "allow" and kind ~= "allowRange" then
        return error_response(server, client, 400, "invalid allow kind")
    end
    local value = tostring(body.value or "")
    if value == "" then
        return error_response(server, client, 400, "allow value required")
    end
    local id = body.id or generate_id("allow")
    log.debug("[buffers] save allow id=" .. id .. " payload=" .. json.encode(body))
    apply_config_change(server, client, request, {
        comment = "buffer allow " .. id,
        apply = function()
            config.add_buffer_allow(id, kind, value)
        end,
        success_builder = function(_, revision_id)
            local row = nil
            local rows = config.list_buffer_allow()
            for _, item in ipairs(rows) do
                if item.id == id then
                    row = item
                    break
                end
            end
            if row then
                local payload = buffer_allow_payload(row)
                payload.revision_id = revision_id
                return payload
            end
            return { id = id, kind = kind, value = value, revision_id = revision_id }
        end,
    })
end

local function delete_buffer_allow(server, client, rule_id, request)
    apply_config_change(server, client, request, {
        comment = "buffer allow " .. rule_id .. " delete",
        apply = function()
            config.delete_buffer_allow(rule_id)
        end,
    })
end

local function reload_buffers(server, client)
    if buffer and buffer.refresh then
        buffer.refresh()
    end
    json_response(server, client, 200, { status = "ok" })
end

local function restart_buffer_reader(server, client, id)
    local ok = buffer and buffer.restart_reader and buffer.restart_reader(id)
    if not ok then
        return error_response(server, client, 404, "buffer resource not found")
    end
    json_response(server, client, 200, { status = "ok" })
end

local function list_buffer_status(server, client)
    local status = buffer and buffer.list_status and buffer.list_status() or {}
    for _, row in ipairs(status) do
        row.output_url = buffer_output_url(row.path)
    end
    json_response(server, client, 200, status)
end

local function get_buffer_status(server, client, id)
    local status = buffer and buffer.get_status and buffer.get_status(id)
    if not status then
        return error_response(server, client, 404, "buffer resource not found")
    end
    status.output_url = buffer_output_url(status.path)
    json_response(server, client, 200, status)
end

local function list_adapter_status(server, client)
    local status = runtime and runtime.list_adapter_status and runtime.list_adapter_status() or {}
    json_response(server, client, 200, status)
end

local function list_dvb_adapters(server, client)
    if not dvbls then
        return error_response(server, client, 501, "dvbls module is not found")
    end
    local ok, result = pcall(dvbls)
    if not ok then
        return error_response(server, client, 500, "failed to list dvb adapters")
    end
    json_response(server, client, 200, result or {})
end

local function dvb_scan_collect_cas(descriptors)
    local cas = {}
    if type(descriptors) ~= "table" then
        return cas
    end
    for _, desc in ipairs(descriptors) do
        if type(desc) == "table" and desc.type_name == "cas" then
            local entry = {
                caid = tonumber(desc.caid),
                pid = tonumber(desc.pid),
                data = desc.data,
            }
            table.insert(cas, entry)
        end
    end
    return cas
end

local function dvb_scan_merge_cas(target, items)
    target = target or {}
    local seen = {}
    for _, entry in ipairs(target) do
        if entry.caid then
            local key = tostring(entry.caid) .. ":" .. tostring(entry.pid or "")
            seen[key] = true
        end
    end
    for _, entry in ipairs(items or {}) do
        if entry.caid then
            local key = tostring(entry.caid) .. ":" .. tostring(entry.pid or "")
            if not seen[key] then
                table.insert(target, entry)
                seen[key] = true
            end
        end
    end
    return target
end

local function dvb_scan_find_lang(descriptors)
    if type(descriptors) ~= "table" then
        return nil
    end
    for _, desc in ipairs(descriptors) do
        if type(desc) == "table" and desc.type_name == "lang" and desc.lang ~= nil then
            return tostring(desc.lang)
        end
    end
    return nil
end

local function dvb_scan_find_descriptor(descriptors, type_ids)
    if type(descriptors) ~= "table" then
        return nil
    end
    local wanted = {}
    if type(type_ids) == "table" then
        for _, value in ipairs(type_ids) do
            local id = tonumber(value)
            if id then
                wanted[id] = true
            end
        end
    else
        local id = tonumber(type_ids)
        if id then
            wanted[id] = true
        end
    end
    if next(wanted) == nil then
        return nil
    end
    for _, desc in ipairs(descriptors) do
        if type(desc) == "table" then
            local id = tonumber(desc.type_id)
            if id and wanted[id] and desc.data ~= nil then
                return tostring(desc.data)
            end
        end
    end
    return nil
end

local function dvb_scan_add_pat(job, data)
    if type(data.programs) ~= "table" then
        return
    end
    if data.tsid ~= nil then
        job.pat_tsid = tonumber(data.tsid)
    end
    if data.crc32 ~= nil then
        job.pat_crc32 = tonumber(data.crc32)
    end
    job.programs = job.programs or {}
    for _, program in ipairs(data.programs) do
        local pnr = tonumber(program.pnr)
        local pid = tonumber(program.pid)
        if pnr and pnr ~= 0 then
            local entry = job.programs[pnr] or { pnr = pnr }
            entry.pmt_pid = pid or entry.pmt_pid
            job.programs[pnr] = entry
        end
    end
end

local function dvb_scan_add_pmt(job, data)
    local pnr = tonumber(data.pnr)
    if not pnr then
        return
    end
    job.programs = job.programs or {}
    local entry = job.programs[pnr] or { pnr = pnr }
    entry.pmt_pid = entry.pmt_pid or tonumber(data.pid)
    entry.pcr = tonumber(data.pcr)
    entry.crc32 = tonumber(data.crc32) or entry.crc32
    entry.streams = {}
    entry.cas = dvb_scan_merge_cas(entry.cas, dvb_scan_collect_cas(data.descriptors))

    if type(data.streams) == "table" then
        for _, stream in ipairs(data.streams) do
            local item = {
                pid = tonumber(stream.pid),
                type_id = tonumber(stream.type_id),
                type_name = stream.type_name,
                lang = dvb_scan_find_lang(stream.descriptors),
                cas = dvb_scan_collect_cas(stream.descriptors),
            }
            local desc = dvb_scan_find_descriptor(stream.descriptors, { 0x59, 0x56 })
            if desc ~= nil then
                item.descriptor = desc
            end
            entry.streams[#entry.streams + 1] = item
            entry.cas = dvb_scan_merge_cas(entry.cas, item.cas)
        end
    end
    job.programs[pnr] = entry
end

local function dvb_scan_add_sdt(job, data)
    if type(data.services) ~= "table" then
        return
    end
    if data.tsid ~= nil then
        job.sdt_tsid = tonumber(data.tsid)
    end
    if data.crc32 ~= nil then
        job.sdt_crc32 = tonumber(data.crc32)
    end
    job.services = job.services or {}
    for _, service in ipairs(data.services) do
        local sid = tonumber(service.sid)
        if sid then
            local name, provider = nil, nil
            if type(service.descriptors) == "table" then
                for _, desc in ipairs(service.descriptors) do
                    if type(desc) == "table" and desc.type_name == "service" then
                        name = desc.service_name or name
                        provider = desc.service_provider or provider
                    end
                end
            end
            job.services[sid] = { name = name, provider = provider }
        end
    end
end

local function dvb_scan_build_channels(job)
    local channels = {}
    for pnr, entry in pairs(job.programs or {}) do
        if pnr and tonumber(pnr) ~= 0 then
            local service = (job.services and job.services[pnr]) or {}
            local channel = {
                pnr = tonumber(pnr),
                name = service.name,
                provider = service.provider,
                pmt_pid = entry.pmt_pid,
                cas = entry.cas or {},
                video = {},
                audio = {},
            }
            for _, stream in ipairs(entry.streams or {}) do
                local type_name = tostring(stream.type_name or "")
                local lower = type_name:lower()
                if lower:find("video", 1, true) then
                    table.insert(channel.video, {
                        pid = stream.pid,
                        type = type_name,
                        type_id = stream.type_id,
                    })
                elseif lower:find("audio", 1, true) then
                    table.insert(channel.audio, {
                        pid = stream.pid,
                        lang = stream.lang,
                        type = type_name,
                        type_id = stream.type_id,
                    })
                end
            end
            table.insert(channels, channel)
        end
    end
    table.sort(channels, function(a, b)
        return (a.pnr or 0) < (b.pnr or 0)
    end)
    job.channels = channels
end

local function dvb_scan_finish(job, status, err)
    if job.timer then
        job.timer:close()
        job.timer = nil
    end
    if job.analyze then
        job.analyze = nil
    end
    if job.input then
        kill_input(job.input)
        job.input = nil
    end
    job.finished_at = os.time()
    job.status = status
    if err then
        job.error = err
    end
    job.signal = runtime and runtime.get_adapter_status and runtime.get_adapter_status(job.adapter_id) or nil
    dvb_scan_build_channels(job)
    dvb_scan_cleanup()
end

local function stream_analyze_finish(job, status, err)
    if job.timer then
        job.timer:close()
        job.timer = nil
    end
    if job.analyze then
        job.analyze = nil
    end
    if job.input then
        kill_input(job.input)
        job.input = nil
    end
    if job.retained and job.channel_data and _G.channel_release then
        -- Analyze can temporarily retain a live stream pipeline so it stays active without viewers.
        -- Release the retain when the job finishes, even on errors.
        pcall(_G.channel_release, job.channel_data, "analyze")
        job.retained = nil
    end
    -- Даже если retain не делали, не держим ссылки на канал в finished job.
    job.channel_data = nil
    job.finished_at = os.time()
    job.status = status
    if err then
        job.error = err
    end
    dvb_scan_build_channels(job)
    do
        local list = {}
        for _, channel in ipairs(job.channels or {}) do
            if type(channel) == "table" then
                table.insert(list, {
                    pnr = channel.pnr,
                    pmt_pid = channel.pmt_pid,
                    pcr = channel.pcr,
                    name = channel.name,
                    provider = channel.provider,
                })
            end
        end
        table.sort(list, function(a, b)
            return (tonumber(a.pnr) or 0) < (tonumber(b.pnr) or 0)
        end)
        job.program_list = list
    end
    local program_count = 0
    for _ in pairs(job.programs or {}) do
        program_count = program_count + 1
    end
    job.summary = {
        programs = program_count,
        channels = job.channels and #job.channels or 0,
        bitrate = job.totals and job.totals.bitrate or nil,
        cc_errors = job.totals and job.totals.cc_errors or nil,
        pes_errors = job.totals and job.totals.pes_errors or nil,
        scrambled = job.totals and job.totals.scrambled or nil,
    }
    stream_analyze_cleanup()
    stream_analyze.active = math.max(0, stream_analyze.active - 1)
end

local function get_analyze_limit()
    local limit = setting_number("monitor_analyze_max_concurrency", 2)
    if not limit or limit < 1 then
        limit = 1
    end
    return limit
end

local function resolve_stream_input_url(stream_id)
    local status = runtime and runtime.get_stream_status and runtime.get_stream_status(stream_id) or nil
    if status and status.transcode_state then
        return nil, "transcode stream is not supported"
    end
    if status and status.active_input_url then
        return status.active_input_url
    end
    local row = config.get_stream(stream_id)
    if not row then
        return nil, "stream not found"
    end
    local cfg = row.config or {}
    local inputs = cfg.input
    if type(inputs) == "table" and #inputs > 0 then
        return inputs[1]
    end
    if type(inputs) == "string" and inputs ~= "" then
        return inputs
    end
    return nil, "no input url"
end

local function stream_analyze_payload(job)
    if not job then
        return nil
    end
    local include_scan_details = (job.status ~= "running")

    local function copy_cas_rows(rows)
        local out = {}
        for _, row in ipairs(rows or {}) do
            if type(row) == "table" then
                table.insert(out, {
                    caid = tonumber(row.caid),
                    pid = tonumber(row.pid),
                })
            end
        end
        return out
    end

    local function copy_stream_rows(rows)
        local out = {}
        for _, row in ipairs(rows or {}) do
            if type(row) == "table" then
                table.insert(out, {
                    pid = tonumber(row.pid),
                    type_name = row.type,
                    type_id = tonumber(row.type_id),
                    lang = row.lang,
                    cas = copy_cas_rows(row.cas),
                })
            end
        end
        return out
    end

    local channels = nil
    local programs = nil
    local program_list = nil
    if include_scan_details then
        channels = {}
        programs = {}
        program_list = {}
        for _, channel in ipairs(job.channels or {}) do
            if type(channel) == "table" then
                local video = copy_stream_rows(channel.video)
                local audio = copy_stream_rows(channel.audio)
                local channel_copy = {
                    pnr = tonumber(channel.pnr),
                    name = channel.name,
                    provider = channel.provider,
                    pmt_pid = tonumber(channel.pmt_pid),
                    pcr = tonumber(channel.pcr),
                    cas = copy_cas_rows(channel.cas),
                    video = video,
                    audio = audio,
                }
                table.insert(channels, channel_copy)
                table.insert(program_list, {
                    pnr = channel_copy.pnr,
                    pmt_pid = channel_copy.pmt_pid,
                    pcr = channel_copy.pcr,
                    name = channel_copy.name,
                    provider = channel_copy.provider,
                })

                local streams = {}
                for _, row in ipairs(video) do
                    table.insert(streams, {
                        pid = row.pid,
                        type_name = row.type_name,
                        type_id = row.type_id,
                    })
                end
                for _, row in ipairs(audio) do
                    table.insert(streams, {
                        pid = row.pid,
                        type_name = row.type_name,
                        type_id = row.type_id,
                        lang = row.lang,
                    })
                end
                table.insert(programs, {
                    pnr = channel_copy.pnr,
                    pmt_pid = channel_copy.pmt_pid,
                    pcr = channel_copy.pcr,
                    name = channel_copy.name,
                    provider = channel_copy.provider,
                    cas = copy_cas_rows(channel.cas),
                    streams = streams,
                })
            end
        end
        table.sort(channels, function(a, b)
            return (a.pnr or 0) < (b.pnr or 0)
        end)
        table.sort(programs, function(a, b)
            return (a.pnr or 0) < (b.pnr or 0)
        end)
        table.sort(program_list, function(a, b)
            return (a.pnr or 0) < (b.pnr or 0)
        end)
    end

    local pids = {}
    for _, row in ipairs(job.pids or {}) do
        if type(row) == "table" then
            table.insert(pids, {
                pid = tonumber(row.pid),
                bitrate = tonumber(row.bitrate),
                cc_error = tonumber(row.cc_error) or 0,
                pes_error = tonumber(row.pes_error) or 0,
                sc_error = tonumber(row.sc_error) or 0,
            })
        end
    end

    local totals = nil
    if type(job.totals) == "table" then
        totals = {
            bitrate = tonumber(job.totals.bitrate) or 0,
            cc_errors = tonumber(job.totals.cc_errors) or 0,
            pes_errors = tonumber(job.totals.pes_errors) or 0,
            scrambled = job.totals.scrambled == true,
        }
    end

    local summary = nil
    if type(job.summary) == "table" then
        summary = {
            programs = tonumber(job.summary.programs) or 0,
            channels = tonumber(job.summary.channels) or 0,
            bitrate = tonumber(job.summary.bitrate) or 0,
            cc_errors = tonumber(job.summary.cc_errors) or 0,
            pes_errors = tonumber(job.summary.pes_errors) or 0,
            scrambled = job.summary.scrambled == true,
        }
    end

    return {
        id = job.id,
        status = job.status,
        stream_id = job.stream_id,
        stream_name = job.stream_name,
        input_url = job.input_url,
        duration_sec = job.duration_sec,
        started_at = job.started_at,
        finished_at = job.finished_at,
        error = job.error,
        totals = totals,
        summary = summary,
        pids = pids,
        programs = programs,
        program_list = program_list,
        channels = channels,
        pat_tsid = job.pat_tsid,
        pat_crc32 = job.pat_crc32,
        sdt_tsid = job.sdt_tsid,
        sdt_crc32 = job.sdt_crc32,
        last_update = job.last_update,
    }
end

local function build_local_play_url(stream_id)
    local http_port = tonumber(config and config.get_setting and config.get_setting("http_port") or nil) or 8000
    local play_port = tonumber(config and config.get_setting and config.get_setting("http_play_port") or nil) or http_port
    if not play_port or play_port == 0 then
        play_port = http_port
    end
    -- internal=1: loopback-анализ должен работать даже если /play скрыт для внешних клиентов
    -- или включён http_auth (см. server.lua: is_internal_play_request()).
    return "http://127.0.0.1:" .. tostring(play_port) .. "/play/" .. tostring(stream_id) .. "?internal=1#sync"
end

local function start_stream_analyze(server, client, request, stream_id_override)
    if not require_auth(request) then
        return error_response(server, client, 401, "unauthorized")
    end
    if not analyze then
        return error_response(server, client, 501, "analyze module is not found")
    end
    local body = parse_json_body(request) or {}
    local stream_id = stream_id_override or body.stream_id or body.id
    if not stream_id or stream_id == "" then
        return error_response(server, client, 400, "stream_id is required")
    end
    local limit = get_analyze_limit()
    if stream_analyze.active >= limit then
        return error_response(server, client, 429, "analyze busy")
    end
    local duration = tonumber(body.duration_sec) or 3
    if duration < 2 then duration = 2 end
    if duration > 10 then duration = 10 end

    for _, job in pairs(stream_analyze.jobs) do
        if job and job.status == "running" and job.stream_id == tostring(stream_id) then
            return json_response(server, client, 200, { id = job.id, status = job.status, stream_id = job.stream_id })
        end
    end

    local input_url, input_err = resolve_stream_input_url(stream_id)

    -- Prefer analyzing the live stream pipeline (post-remap, same as /play) when available.
    -- This avoids SSRF/allowlist problems for remote inputs and works for stream:// sources.
    local entry = runtime and runtime.streams and runtime.streams[tostring(stream_id)] or nil
    local channel_data = entry and entry.channel or nil
    local active_id = channel_data and tonumber(channel_data.active_input_id or 0) or 0
    -- stream.lua экспортирует удержание канала как _G.channel_retain/_G.channel_release
    -- (локальные channel_retain/channel_release не видны отсюда).
    -- Если retain недоступен, но канал уже активен (active_input_id!=0) - можем анализировать без удержания.
    local can_retain = (channel_data and _G.channel_retain and _G.channel_release) and true or false
    local can_tail = channel_data and channel_data.tail or nil
    local can_attach_live = can_tail and (can_retain or active_id ~= 0)

    if not can_attach_live and not input_url then
        return error_response(server, client, 400, input_err or "input url not found")
    end

    local stream_name = tostring(stream_id)
    local row = config and config.get_stream and config.get_stream(stream_id)
    if row and row.config and row.config.name and row.config.name ~= "" then
        stream_name = row.config.name
    end

    stream_analyze.seq = stream_analyze.seq + 1
    local id = tostring(stream_analyze.seq)
    local job = {
        id = id,
        stream_id = tostring(stream_id),
        stream_name = stream_name,
        input_url = input_url and tostring(input_url) or nil,
        status = "running",
        started_at = os.time(),
        duration_sec = duration,
        programs = {},
        services = {},
        channels = {},
        totals = {},
        pids = {},
    }

    local analyze_name = "stream-analyze-" .. tostring(stream_id)
    local upstream = nil

    -- If the stream exists in runtime but is idle, channel_data.tail can be nil until we activate inputs.
    -- Try to retain first (when available) to bring the pipeline up, then re-check tail.
    if channel_data and can_retain and not can_tail then
        job.channel_data = channel_data
        local ok, retained = pcall(_G.channel_retain, channel_data, "analyze")
        if ok and retained then
            job.retained = true
        end
        can_tail = channel_data.tail
        if can_tail then
            can_attach_live = true
        end
    end

    if can_attach_live then
        job.channel_data = channel_data
        if can_retain and not job.retained then
            local ok, retained = pcall(_G.channel_retain, channel_data, "analyze")
            if ok and retained then
                job.retained = true
            end
        end
        upstream = channel_data.tail:stream()
    else
        -- Fallback: analyze through loopback /play. This avoids SSRF allowlist issues for remote inputs
        -- and ensures the analyzed TS matches what external clients see.
        -- Даже если канал ещё не активен (нет viewers / on-demand), loopback /play
        -- безопаснее, чем прямой http_request к input_url: не упираемся в allowlist
        -- и получаем ровно тот TS, который видит внешний клиент.
        local url = build_local_play_url(stream_id)
        local conf = parse_url(url)
        if not conf then
            return error_response(server, client, 400, "invalid input url")
        end
        conf.name = analyze_name

        local input = init_input(conf)
        if not input and input_url then
            -- Loopback can fail if /play is disabled or stream is missing in runtime; try the raw input URL.
            conf = parse_url(input_url)
            if not conf then
                return error_response(server, client, 400, "invalid input url")
            end
            conf.name = analyze_name
            input = init_input(conf)
        end
        if not input then
            return error_response(server, client, 500, "failed to init input")
        end
        job.input = input
        upstream = input.tail:stream()
    end

    stream_analyze.active = stream_analyze.active + 1
    job.analyze = analyze({
        upstream = upstream,
        name = analyze_name,
        join_pid = true,
        callback = function(data)
            if type(data) ~= "table" then
                return
            end
            if data.error then
                job.error = data.error
                return
            end
            if data.psi == "pat" then
                dvb_scan_add_pat(job, data)
            elseif data.psi == "pmt" then
                dvb_scan_add_pmt(job, data)
            elseif data.psi == "sdt" then
                dvb_scan_add_sdt(job, data)
            elseif data.analyze and data.total then
                local total = data.total or {}
                -- Keep a plain snapshot table to avoid json.encode races on mutable analyzer internals.
                job.totals = {
                    bitrate = tonumber(total.bitrate) or 0,
                    cc_errors = tonumber(total.cc_errors) or 0,
                    pes_errors = tonumber(total.pes_errors) or 0,
                    scrambled = total.scrambled == true,
                }
                job.last_update = os.time()
                if type(data.analyze) == "table" then
                    local list = {}
                    for _, item in ipairs(data.analyze) do
                        if type(item) == "table" then
                            local pid = tonumber(item.pid)
                            if pid then
                                table.insert(list, {
                                    pid = pid,
                                    bitrate = tonumber(item.bitrate),
                                    cc_error = tonumber(item.cc_error) or 0,
                                    pes_error = tonumber(item.pes_error) or 0,
                                    sc_error = tonumber(item.sc_error) or 0,
                                })
                            end
                        end
                    end
                    table.sort(list, function(a, b)
                        return (a.pid or 0) < (b.pid or 0)
                    end)
                    job.pids = list
                end
            end
        end,
    })

    job.timer = timer({
        interval = duration,
        callback = function(self)
            self:close()
            stream_analyze_finish(job, "done")
        end,
    })

    stream_analyze.jobs[id] = job
    json_response(server, client, 200, { id = job.id, status = job.status, stream_id = job.stream_id })
end

local function get_stream_analyze(server, client, request, id)
    if not require_auth(request) then
        return error_response(server, client, 401, "unauthorized")
    end
    local job = stream_analyze.jobs[id]
    if not job then
        return error_response(server, client, 404, "analyze job not found")
    end
    json_response(server, client, 200, stream_analyze_payload(job))
end

local function dvb_scan_config_from_adapter(adapter_id)
    local row = config.get_adapter(adapter_id)
    if not row then
        return nil, "adapter not found"
    end
    local cfg = row.config or {}
    if cfg.adapter == nil then
        return nil, "adapter index is required"
    end
    local conf = {
        name = "dvb-scan-" .. tostring(adapter_id),
        format = "dvb",
        adapter = cfg.adapter,
        device = cfg.device or 0,
        type = cfg.type,
        tp = cfg.tp,
        lnb = cfg.lnb,
        lof1 = cfg.lof1,
        lof2 = cfg.lof2,
        slof = cfg.slof,
        diseqc = cfg.diseqc,
        tone = cfg.tone,
        rolloff = cfg.rolloff,
        uni_scr = cfg.uni_scr,
        uni_frequency = cfg.uni_frequency,
        frequency = cfg.frequency,
        polarization = cfg.polarization,
        symbolrate = cfg.symbolrate,
        bandwidth = cfg.bandwidth,
        guardinterval = cfg.guardinterval,
        transmitmode = cfg.transmitmode,
        hierarchy = cfg.hierarchy,
        modulation = cfg.modulation,
        budget = cfg.budget,
    }
    if (not conf.tp or conf.tp == "") and conf.frequency and conf.polarization and conf.symbolrate then
        conf.tp = tostring(conf.frequency) .. ":" .. tostring(conf.polarization) .. ":" .. tostring(conf.symbolrate)
    end
    return conf, nil
end

local function start_dvb_scan(server, client, request)
    local user = require_admin(request)
    if not user then
        return error_response(server, client, 401, "unauthorized")
    end
    if not analyze then
        return error_response(server, client, 501, "analyze module is not found")
    end
    local body = parse_json_body(request) or {}
    local adapter_id = body.adapter_id or body.id
    if not adapter_id or adapter_id == "" then
        return error_response(server, client, 400, "adapter_id is required")
    end
    local duration = tonumber(body.duration_sec) or 8
    if duration < 2 then duration = 2 end
    if duration > 30 then duration = 30 end

    for _, job in pairs(dvb_scan.jobs) do
        if job and job.status == "running" and job.adapter_id == adapter_id then
            return json_response(server, client, 200, { id = job.id, status = job.status, adapter_id = adapter_id })
        end
    end

    local conf, err = dvb_scan_config_from_adapter(adapter_id)
    if not conf then
        return error_response(server, client, 400, err or "invalid adapter config")
    end

    dvb_scan.seq = dvb_scan.seq + 1
    local id = tostring(dvb_scan.seq)
    local job = {
        id = id,
        adapter_id = adapter_id,
        status = "running",
        started_at = os.time(),
        programs = {},
        services = {},
        channels = {},
    }

    local input = init_input(conf)
    if not input then
        return error_response(server, client, 500, "failed to init dvb input")
    end
    job.input = input
    job.analyze = analyze({
        upstream = input.tail:stream(),
        name = conf.name,
        join_pid = true,
        callback = function(data)
            if type(data) ~= "table" then
                return
            end
            if data.error then
                job.error = data.error
                return
            end
            if data.psi == "pat" then
                dvb_scan_add_pat(job, data)
            elseif data.psi == "pmt" then
                dvb_scan_add_pmt(job, data)
            elseif data.psi == "sdt" then
                dvb_scan_add_sdt(job, data)
            end
        end,
    })

    job.timer = timer({
        interval = duration,
        callback = function(self)
            self:close()
            dvb_scan_finish(job, "done")
        end,
    })

    dvb_scan.jobs[id] = job
    json_response(server, client, 200, { id = id, status = job.status, adapter_id = adapter_id })
end

local function get_dvb_scan(server, client, request, id)
    local job = dvb_scan.jobs[id]
    if not job then
        return error_response(server, client, 404, "scan not found")
    end
    local payload = {
        id = job.id,
        status = job.status,
        adapter_id = job.adapter_id,
        started_at = job.started_at,
        finished_at = job.finished_at,
        error = job.error,
        signal = job.signal,
        channels = job.channels,
    }
    if job.status == "running" and (runtime and runtime.get_adapter_status) then
        payload.signal = runtime.get_adapter_status(job.adapter_id) or payload.signal
    end
    json_response(server, client, 200, payload)
end

local function get_adapter_status(server, client, id)
    local status = runtime and runtime.get_adapter_status and runtime.get_adapter_status(id)
    if not status then
        return error_response(server, client, 404, "adapter status not found")
    end
    json_response(server, client, 200, status)
end

local stream_status_cache = {
    full = { ts = 0, payload = nil },
    lite = { ts = 0, payload = nil },
}

local function query_truthy(value)
    if value == true then
        return true
    end
    if value == nil then
        return false
    end
    local s = tostring(value):lower()
    return s == "1" or s == "true" or s == "yes" or s == "on"
end

local function list_stream_status(server, client, request)
    local now = os.time()
    local query = request and request.query or {}
    local lite = query_truthy(query and query.lite)
    local cache_key = lite and "lite" or "full"
    local cache = stream_status_cache[cache_key] or { ts = 0, payload = nil }

    if cache.payload and (now - (cache.ts or 0)) <= 1 then
        return json_response(server, client, 200, cache.payload)
    end

    local status = {}
    if lite and runtime.list_status_lite then
        status = runtime.list_status_lite() or {}
    elseif runtime.list_status then
        status = runtime.list_status() or {}
    end
    stream_status_cache[cache_key] = { ts = now, payload = status }
    json_response(server, client, 200, status)
end

local function get_stream_status(server, client, request, id)
    local query = request and request.query or {}
    local lite = query_truthy(query and query.lite)
    local status = nil
    if lite and runtime.get_stream_status_lite then
        status = runtime.get_stream_status_lite(id)
    elseif runtime.get_stream_status then
        status = runtime.get_stream_status(id)
    end
    if not status then
        return error_response(server, client, 404, "stream not found")
    end
    json_response(server, client, 200, status)
end

local function get_stream_cam_stats(server, client, id)
    local entry = runtime and runtime.streams and runtime.streams[tostring(id)] or nil
    if not entry or entry.kind ~= "stream" or not entry.channel then
        return error_response(server, client, 404, "stream not found")
    end

    local channel = entry.channel
    local active_id = tonumber(channel.active_input_id or 0) or 0

    local inputs = {}
    for input_id, input_data in ipairs(channel.input or {}) do
        local item = {
            input_id = input_id,
            active = (active_id == input_id),
            name = input_data.config and input_data.config.name or nil,
            format = input_data.config and input_data.config.format or nil,
        }

        local input = input_data.input
        -- Best-effort: expose which softcam id is attached to this input (if any).
        local softcam_id = nil
        if input and input.__softcam_id then
            softcam_id = tostring(input.__softcam_id)
        else
            local cam_cfg = input_data.config and input_data.config.cam or nil
            if type(cam_cfg) == "string" or type(cam_cfg) == "number" then
                softcam_id = tostring(cam_cfg)
            elseif type(cam_cfg) == "table" then
                local opts = cam_cfg.__options or {}
                if opts.id then
                    softcam_id = tostring(opts.id)
                end
            end
        end
        if softcam_id and softcam_id ~= "" then
            item.softcam_id = softcam_id
        end

        -- Best-effort: backup softcam id (dual-CAM redundancy).
        local softcam_backup_id = nil
        if input and input.__softcam_backup_id then
            softcam_backup_id = tostring(input.__softcam_backup_id)
        else
            local cam_cfg = input_data.config and input_data.config.cam_backup or nil
            if type(cam_cfg) == "string" or type(cam_cfg) == "number" then
                softcam_backup_id = tostring(cam_cfg)
            elseif type(cam_cfg) == "table" then
                local opts = cam_cfg.__options or {}
                if opts.id then
                    softcam_backup_id = tostring(opts.id)
                end
            end
        end
        if softcam_backup_id and softcam_backup_id ~= "" then
            item.softcam_backup_id = softcam_backup_id
        end

        local decrypt = input and input.decrypt or nil
        if decrypt and decrypt.stats then
            local ok, data = pcall(function()
                return decrypt:stats()
            end)
            if ok then
                item.decrypt = data
            else
                item.decrypt_error = tostring(data)
            end
        end

        -- CAM connection stats (if the softcam module supports it, e.g. newcamd:stats()).
        local cam = nil
        if input and type(input.__softcam_clone) == "table" and input.__softcam_clone.stats then
            cam = input.__softcam_clone
        elseif input and type(input.__softcam_instance) == "table" and input.__softcam_instance.stats then
            cam = input.__softcam_instance
        elseif softcam_id then
            local shared = _G[tostring(softcam_id)]
            if type(shared) == "table" and shared.stats then
                cam = shared
            elseif type(softcam_list) == "table" then
                for _, entry in ipairs(softcam_list) do
                    if type(entry) == "table" and entry.stats and entry.__options and tostring(entry.__options.id) == tostring(softcam_id) then
                        cam = entry
                        break
                    end
                end
            end
        end
        if cam and cam.stats then
            local ok, data = pcall(function()
                return cam:stats()
            end)
            if ok then
                if type(cam) == "table" and type(cam.__options) == "table" then
                    local opts = cam.__options
                    if opts.pool_index ~= nil then
                        data.pool_index = tonumber(opts.pool_index) or opts.pool_index
                    end
                    if opts.pool_size ~= nil then
                        data.pool_size = tonumber(opts.pool_size) or opts.pool_size
                    end
                end
                item.cam = data
            else
                item.cam_error = tostring(data)
            end
        end

        -- Backup CAM connection stats (dual-CAM redundancy).
        local cam_backup = nil
        if input and type(input.__softcam_backup_clone) == "table" and input.__softcam_backup_clone.stats then
            cam_backup = input.__softcam_backup_clone
        elseif input and type(input.__softcam_backup_instance) == "table" and input.__softcam_backup_instance.stats then
            cam_backup = input.__softcam_backup_instance
        elseif softcam_backup_id then
            local shared = _G[tostring(softcam_backup_id)]
            if type(shared) == "table" and shared.stats then
                cam_backup = shared
            elseif type(softcam_list) == "table" then
                for _, entry in ipairs(softcam_list) do
                    if type(entry) == "table" and entry.stats and entry.__options and tostring(entry.__options.id) == tostring(softcam_backup_id) then
                        cam_backup = entry
                        break
                    end
                end
            end
        end
        if cam_backup and cam_backup.stats then
            local ok, data = pcall(function()
                return cam_backup:stats()
            end)
            if ok then
                if type(cam_backup) == "table" and type(cam_backup.__options) == "table" then
                    local opts = cam_backup.__options
                    if opts.pool_index ~= nil then
                        data.pool_index = tonumber(opts.pool_index) or opts.pool_index
                    end
                    if opts.pool_size ~= nil then
                        data.pool_size = tonumber(opts.pool_size) or opts.pool_size
                    end
                end
                item.cam_backup = data
            else
                item.cam_backup_error = tostring(data)
            end
        end

        inputs[#inputs + 1] = item
    end

    json_response(server, client, 200, {
        stream_id = tostring(id),
        active_input_id = active_id,
        inputs = inputs,
    })
end

local function list_sessions(server, client, request)
    local query = request and request.query or {}
    local mode = query.type or query.kind
    if mode and tostring(mode) == "auth" then
        local sessions = auth and auth.list_sessions and auth.list_sessions(query) or {}
        return json_response(server, client, 200, sessions)
    end
    local stream_filter = tostring(query.stream_id or query.stream or ""):lower()
    local login_filter = tostring(query.login or ""):lower()
    local ip_filter = tostring(query.ip or ""):lower()
    local text_filter = tostring(query.text or ""):lower()
    local raw_limit = query.limit and tonumber(query.limit) or nil
    local raw_offset = query.offset and tonumber(query.offset) or nil
    local use_paging = raw_limit ~= nil or raw_offset ~= nil
    local limit = raw_limit and math.max(1, math.min(raw_limit, 1000)) or 200
    local offset = raw_offset and math.max(0, raw_offset) or 0
    local sessions = runtime.list_sessions and runtime.list_sessions() or {}
    local filtered = {}

    local function matches_text(value, needle)
        if not needle or needle == "" then
            return true
        end
        if not value then
            return false
        end
        return tostring(value):lower():find(needle, 1, true) ~= nil
    end

    for _, session in ipairs(sessions) do
        if stream_filter ~= "" then
            local stream_ok = matches_text(session.stream_id, stream_filter)
            if not stream_ok then
                stream_ok = matches_text(session.stream_name, stream_filter)
            end
            if not stream_ok then
                goto continue
            end
        end
        if login_filter ~= "" and not matches_text(session.login, login_filter) then
            goto continue
        end
        if ip_filter ~= "" and not matches_text(session.ip, ip_filter) then
            goto continue
        end
        if text_filter ~= "" then
            local hay = table.concat({
                session.server or "",
                session.stream_name or "",
                session.stream_id or "",
                session.ip or "",
                session.login or "",
                session.user_agent or "",
            }, " ")
            if not matches_text(hay, text_filter) then
                goto continue
            end
        end
        table.insert(filtered, session)
        ::continue::
    end

    if use_paging then
        local slice = {}
        local last = math.min(#filtered, offset + limit)
        for idx = offset + 1, last do
            table.insert(slice, filtered[idx])
        end
        filtered = slice
    end

    json_response(server, client, 200, filtered)
end

local function auth_debug_session(server, client, request)
    if not require_admin(request) then
        return error_response(server, client, 403, "forbidden")
    end
    if not auth or not auth.debug_session then
        return error_response(server, client, 404, "auth module not available")
    end
    local query = request and request.query or {}
    local stream_id = query.stream_id or query.stream
    if not stream_id or stream_id == "" then
        return error_response(server, client, 400, "stream_id required")
    end
    local stream = config.get_stream and config.get_stream(stream_id)
    if not stream then
        return error_response(server, client, 404, "stream not found")
    end
    local result, err = auth.debug_session({
        stream_id = stream_id,
        stream_cfg = stream.config or {},
        ip = query.ip or (request and request.addr) or "",
        proto = query.proto or "hls",
        token = query.token or "",
    })
    if not result then
        return error_response(server, client, 400, err or "invalid request")
    end
    json_response(server, client, 200, result)
end

local function delete_session(server, client, id)
    if not (runtime.close_session and runtime.close_session(id)) then
        return error_response(server, client, 404, "session not found")
    end
    json_response(server, client, 200, { status = "ok" })
end

local function list_logs(server, client, request)
    local query = request and request.query or {}
    local since = tonumber(query.since) or 0
    local limit = tonumber(query.limit) or 200
    local level = query.level
    local text = query.text
    local stream_id = query.stream_id or query.stream
    local entries = log_store and log_store.list and log_store.list(since, limit, level, text, stream_id) or {}
    local next_id = (log_store and log_store.next_id) or 1
    json_response(server, client, 200, { entries = entries, next_id = next_id })
end

local function list_access_log(server, client, request)
    local query = request and request.query or {}
    local since = tonumber(query.since) or 0
    local limit = tonumber(query.limit) or 200
    local event = query.event
    local stream_id = query.stream_id or query.stream
    local ip = query.ip
    local login = query.login
    local text = query.text
    local entries = access_log and access_log.list and access_log.list(
        since,
        limit,
        event,
        stream_id,
        ip,
        login,
        text
    ) or {}
    local next_id = (access_log and access_log.next_id) or 1
    json_response(server, client, 200, { entries = entries, next_id = next_id })
end

local function list_alerts(server, client, request)
    local query = request and request.query or {}
    local code_prefix = nil
    if query.type and tostring(query.type) == "auth" then
        code_prefix = "AUTH_"
    end
    local rows = config.list_alerts and config.list_alerts({
        since = query.since,
        limit = query.limit,
        stream_id = query.stream_id,
        code = query.code,
        code_prefix = code_prefix,
    }) or {}
    json_response(server, client, 200, rows)
end

local function list_tools(server, client)
    if transcode and transcode.get_tool_info then
        return json_response(server, client, 200, transcode.get_tool_info(true))
    end
    return json_response(server, client, 200, {})
end

local function list_metrics(server, client, request)
    local now = os.time()
    local started_at = (runtime and runtime.started_at) or now
    local uptime = math.max(0, now - started_at)

    local stream_counts = { total = 0, enabled = 0, disabled = 0 }
    if config and config.count_streams then
        stream_counts = config.count_streams()
    elseif config and config.list_streams then
        local rows = config.list_streams()
        stream_counts.total = #rows
        for _, row in ipairs(rows) do
            if (tonumber(row.enabled) or 0) ~= 0 then
                stream_counts.enabled = stream_counts.enabled + 1
            end
        end
        stream_counts.disabled = math.max(0, stream_counts.total - stream_counts.enabled)
    end

    local adapter_counts = { total = 0, enabled = 0, disabled = 0 }
    if config and config.count_adapters then
        adapter_counts = config.count_adapters()
    elseif config and config.list_adapters then
        local rows = config.list_adapters()
        adapter_counts.total = #rows
        for _, row in ipairs(rows) do
            if (tonumber(row.enabled) or 0) ~= 0 then
                adapter_counts.enabled = adapter_counts.enabled + 1
            end
        end
        adapter_counts.disabled = math.max(0, adapter_counts.total - adapter_counts.enabled)
    end

    local status = runtime and runtime.list_status and runtime.list_status() or {}
    local on_air = 0
    for _, entry in pairs(status) do
        if entry and entry.on_air == true then
            on_air = on_air + 1
        end
    end

    local transcode_enabled = 0
    if runtime and runtime.streams then
        for _, entry in pairs(runtime.streams) do
            if entry and entry.kind == "transcode" then
                transcode_enabled = transcode_enabled + 1
            end
        end
    end

    local adapter_with_status = 0
    if runtime and runtime.list_adapter_status then
        local adapter_status = runtime.list_adapter_status()
        for _, entry in pairs(adapter_status) do
            if entry and entry.updated_at then
                adapter_with_status = adapter_with_status + 1
            end
        end
    end

    local sessions_active = 0
    if runtime and runtime.list_sessions then
        local sessions = runtime.list_sessions()
        sessions_active = #sessions
    end
    local auth_sessions = (config and config.count_sessions) and config.count_sessions() or 0
    local lua_mem_kb = nil
    if collectgarbage then
        lua_mem_kb = math.floor(collectgarbage("count") + 0.5)
    end
    local perf = (runtime and runtime.perf) or {}

    local mpts_metrics = nil
    for id, entry in pairs(status) do
        if entry and entry.mpts_stats then
            if not mpts_metrics then
                mpts_metrics = {}
            end
            mpts_metrics[id] = entry.mpts_stats
        end
    end

    local payload = {
        ts = now,
        version = astra and astra.version or "",
        uptime_sec = uptime,
        streams = {
            total = stream_counts.total,
            enabled = stream_counts.enabled,
            disabled = stream_counts.disabled,
            on_air = on_air,
            transcode_enabled = transcode_enabled,
        },
        adapters = {
            total = adapter_counts.total,
            enabled = adapter_counts.enabled,
            disabled = adapter_counts.disabled,
            with_status = adapter_with_status,
        },
        sessions = {
            auth = auth_sessions,
            clients = sessions_active,
        },
        lua_mem_kb = lua_mem_kb,
        perf = {
            refresh_ms = perf.last_refresh_ms,
            refresh_ts = perf.last_refresh_ts,
            status_ms = perf.last_status_ms,
            status_ts = perf.last_status_ts,
            status_one_ms = perf.last_status_one_ms,
            status_one_ts = perf.last_status_one_ts,
            adapter_refresh_ms = perf.last_adapter_refresh_ms,
            adapter_refresh_ts = perf.last_adapter_refresh_ts,
        },
    }
    if mpts_metrics then
        payload.mpts = mpts_metrics
    end

    local format = ""
    if request and request.query and request.query.format then
        format = tostring(request.query.format):lower()
    end
    if format == "prometheus" or format == "prom" then
        local lines = {
            "astra_uptime_seconds " .. tostring(payload.uptime_sec or 0),
            "astra_streams_total " .. tostring(payload.streams.total or 0),
            "astra_streams_enabled " .. tostring(payload.streams.enabled or 0),
            "astra_streams_disabled " .. tostring(payload.streams.disabled or 0),
            "astra_streams_on_air " .. tostring(payload.streams.on_air or 0),
            "astra_streams_transcode_enabled " .. tostring(payload.streams.transcode_enabled or 0),
            "astra_adapters_total " .. tostring(payload.adapters.total or 0),
            "astra_adapters_enabled " .. tostring(payload.adapters.enabled or 0),
            "astra_adapters_disabled " .. tostring(payload.adapters.disabled or 0),
            "astra_adapters_with_status " .. tostring(payload.adapters.with_status or 0),
            "astra_sessions_auth " .. tostring(payload.sessions.auth or 0),
            "astra_sessions_clients " .. tostring(payload.sessions.clients or 0),
        }
        if lua_mem_kb then
            table.insert(lines, "astra_lua_mem_kb " .. tostring(lua_mem_kb))
        end
        if perf.last_refresh_ms then
            table.insert(lines, "astra_perf_refresh_ms " .. tostring(perf.last_refresh_ms))
        end
        if perf.last_status_ms then
            table.insert(lines, "astra_perf_status_ms " .. tostring(perf.last_status_ms))
        end
        if perf.last_status_one_ms then
            table.insert(lines, "astra_perf_status_one_ms " .. tostring(perf.last_status_one_ms))
        end
        if perf.last_adapter_refresh_ms then
            table.insert(lines, "astra_perf_adapter_refresh_ms " .. tostring(perf.last_adapter_refresh_ms))
        end
        if mpts_metrics then
            for stream_id, stats in pairs(mpts_metrics) do
                local label = string.format("{stream_id=\"%s\"}", tostring(stream_id):gsub("\"", "\\\""))
                if stats.bitrate_bps then
                    table.insert(lines, "astra_mpts_bitrate_bps" .. label .. " " .. tostring(stats.bitrate_bps))
                end
                if stats.null_percent then
                    table.insert(lines, "astra_mpts_null_percent" .. label .. " " .. tostring(stats.null_percent))
                end
                if stats.psi_interval_ms then
                    table.insert(lines, "astra_mpts_psi_interval_ms" .. label .. " " .. tostring(stats.psi_interval_ms))
                end
            end
        end
        server:send(client, {
            code = 200,
            headers = {
                "Content-Type: text/plain; version=0.0.4",
                "Cache-Control: no-cache",
                "Connection: close",
            },
            content = table.concat(lines, "\n") .. "\n",
        })
        return
    end

    json_response(server, client, 200, payload)
end

local function health_summary(server, client)
    local counts = nil
    if config and config.count_streams then
        counts = config.count_streams()
    end
    local uptime = runtime and runtime.started_at and (os.time() - runtime.started_at) or 0
    local refresh_ok = runtime and runtime.last_refresh_ok ~= false
    json_response(server, client, 200, {
        ok = refresh_ok and config and config.db ~= nil,
        db_ok = config and config.db ~= nil,
        http_ok = true,
        streams_loaded = counts and counts.enabled or 0,
        streams_total = counts and counts.total or 0,
        uptime_sec = uptime,
        last_refresh_ok = refresh_ok,
        last_refresh_errors = runtime and runtime.last_refresh_errors or {},
    })
end

local function health_process(server, client)
    local now = os.time()
    local started_at = (runtime and runtime.started_at) or now
    local uptime = math.max(0, now - started_at)
    json_response(server, client, 200, {
        status = "ok",
        ts = now,
        version = astra and astra.version or "",
        started_at = started_at,
        uptime_sec = uptime,
    })
end

local function health_inputs(server, client)
    local now = os.time()
    local status = runtime and runtime.list_status and runtime.list_status() or {}
    local summary = {
        streams_total = 0,
        streams_with_inputs = 0,
        streams_without_inputs = 0,
        streams_all_down = 0,
    }
    local inputs = {
        total = 0,
        active = 0,
        standby = 0,
        down = 0,
        probing = 0,
        unknown = 0,
    }
    local unhealthy = {}

    for id, entry in pairs(status) do
        if entry.inputs then
            summary.streams_total = summary.streams_total + 1
            local list = entry.inputs or {}
            local total = #list
            if total == 0 then
                summary.streams_without_inputs = summary.streams_without_inputs + 1
                table.insert(unhealthy, {
                    id = id,
                    name = (runtime.streams[id]
                        and runtime.streams[id].channel
                        and runtime.streams[id].channel.config
                        and runtime.streams[id].channel.config.name)
                        or id,
                    active_input_index = entry.active_input_index,
                    reason = "no_inputs",
                })
            else
                summary.streams_with_inputs = summary.streams_with_inputs + 1
                local ok_inputs = 0
                local down_inputs = 0
                for _, input in ipairs(list) do
                    local state = input.state
                    if not state then
                        if input.on_air == true then
                            if input.active == true then
                                state = "ACTIVE"
                            else
                                state = "STANDBY"
                            end
                        else
                            state = "DOWN"
                        end
                    end
                    inputs.total = inputs.total + 1
                    if state == "ACTIVE" then
                        inputs.active = inputs.active + 1
                        ok_inputs = ok_inputs + 1
                    elseif state == "STANDBY" then
                        inputs.standby = inputs.standby + 1
                        ok_inputs = ok_inputs + 1
                    elseif state == "PROBING" then
                        inputs.probing = inputs.probing + 1
                    elseif state == "DOWN" then
                        inputs.down = inputs.down + 1
                        down_inputs = down_inputs + 1
                    else
                        inputs.unknown = inputs.unknown + 1
                    end
                end
                if ok_inputs == 0 then
                    summary.streams_all_down = summary.streams_all_down + 1
                    table.insert(unhealthy, {
                        id = id,
                        name = (runtime.streams[id]
                            and runtime.streams[id].channel
                            and runtime.streams[id].channel.config
                            and runtime.streams[id].channel.config.name)
                            or id,
                        active_input_index = entry.active_input_index,
                        inputs_total = total,
                        inputs_down = down_inputs,
                        reason = "all_down",
                    })
                end
            end
        end
    end

    json_response(server, client, 200, {
        ts = now,
        streams = summary,
        inputs = inputs,
        unhealthy_streams = unhealthy,
    })
end

local function health_outputs(server, client)
    local now = os.time()
    local status = runtime and runtime.list_status and runtime.list_status() or {}
    local total = 0
    local on_air = 0
    local down = 0
    local unhealthy = {}

    for id, entry in pairs(status) do
        total = total + 1
        local ok = entry.on_air == true
        if entry.transcode_state then
            ok = entry.transcode_state == "RUNNING"
        end
        if ok then
            on_air = on_air + 1
        else
            down = down + 1
            table.insert(unhealthy, {
                id = id,
                name = (runtime.streams[id]
                    and runtime.streams[id].channel
                    and runtime.streams[id].channel.config
                    and runtime.streams[id].channel.config.name)
                    or id,
                state = entry.transcode_state or (entry.on_air == true and "RUNNING" or "DOWN"),
            })
        end
    end

    json_response(server, client, 200, {
        ts = now,
        streams = {
            total = total,
            on_air = on_air,
            down = down,
        },
        unhealthy_streams = unhealthy,
    })
end

local function list_audit_events(server, client, request)
    if not require_admin(request) then
        return error_response(server, client, 403, "forbidden")
    end
    local query = request and request.query or {}
    local rows = config.list_audit_events and config.list_audit_events({
        since = query.since,
        limit = query.limit,
        action = query.action,
        actor = query.actor,
        target = query.target,
        ip = query.ip,
        ok = query.ok,
    }) or {}
    json_response(server, client, 200, rows)
end

local function list_transcode_status(server, client)
    local status = runtime.list_transcode_status and runtime.list_transcode_status() or {}
    json_response(server, client, 200, status)
end

local function get_transcode_status(server, client, id)
    local status = runtime.get_transcode_status and runtime.get_transcode_status(id)
    if not status then
        return error_response(server, client, 404, "transcode not found")
    end
    json_response(server, client, 200, status)
end

local function restart_transcode(server, client, id)
    local ok = runtime.restart_transcode and runtime.restart_transcode(id)
    if not ok then
        return error_response(server, client, 404, "transcode not found")
    end
    json_response(server, client, 200, { status = "restarting" })
end

local function kill_ffmpeg_processes()
    if package and package.config and package.config:sub(1, 1) == "\\" then
        return
    end
    local ok, err = pcall(os.execute, "pkill -f ffmpeg >/dev/null 2>&1 || true")
    if not ok then
        log.warning("[restart] failed to kill ffmpeg processes: " .. tostring(err))
        return
    end
    log.info("[restart] ffmpeg cleanup requested")
end

local function reload_service(server, client)
    local ok, err = reload_runtime(true)
    if not ok then
        return json_response(server, client, 500, { error = "reload failed", detail = err })
    end
    json_response(server, client, 200, { status = "ok" })
end

local function restart_service(server, client, request)
    local mode = request and request.query and request.query.mode or "soft"
    if mode ~= "hard" then
        return reload_service(server, client)
    end
    local supervisor_enabled = setting_bool("supervisor_enabled", false)
        or (os.getenv("ASTRA_SUPERVISOR") == "1")
        or (os.getenv("INVOCATION_ID") ~= nil)
    if not supervisor_enabled then
        return error_response(server, client, 400, "hard restart disabled (no supervisor)")
    end
    json_response(server, client, 200, { status = "restarting" })
    kill_ffmpeg_processes()
    timer({
        interval = 0.2,
        callback = function(self)
            self:close()
            astra.exit()
        end,
    })
end

local function apply_sharding(server, client, request)
    if not require_admin(request) then
        return error_response(server, client, 403, "forbidden")
    end
    if not sharding or type(sharding.apply_systemd) ~= "function" then
        return error_response(server, client, 400, "sharding module unavailable")
    end
    json_response(server, client, 200, { status = "applying" })
    timer({
        interval = 0.2,
        callback = function(self)
            self:close()
            local ok, err = sharding.apply_systemd()
            if not ok then
                log.error("[sharding] apply failed: " .. tostring(err))
                if config and config.add_alert then
                    config.add_alert("ERROR", "", "SHARDING_APPLY_FAILED",
                        tostring(err),
                        {})
                end
                return
            end
            log.warning("[sharding] apply ok (services restarted)")
        end,
    })
end

local function get_settings(server, client)
    local rows = config.list_settings and config.list_settings() or {}
    local token = rows.telegram_bot_token
    if token ~= nil and tostring(token) ~= "" then
        local masked = token
        local prefix = tostring(token):match("^([^:]+):") or tostring(token):sub(1, 6)
        if #prefix > 6 then
            prefix = prefix:sub(1, 6)
        end
        masked = prefix .. ":***"
        rows.telegram_bot_token_masked = masked
        rows.telegram_bot_token_set = true
    else
        rows.telegram_bot_token_masked = ""
        rows.telegram_bot_token_set = false
    end
    rows.telegram_bot_token = nil

    local ai_key = rows.ai_api_key
    if ai_key ~= nil and tostring(ai_key) ~= "" then
        local prefix = tostring(ai_key):sub(1, 6)
        if #prefix < 3 then
            prefix = tostring(ai_key)
        end
        rows.ai_api_key_masked = prefix .. "***"
        rows.ai_api_key_set = true
    else
        rows.ai_api_key_masked = ""
        rows.ai_api_key_set = false
    end
    rows.ai_api_key = nil
    json_response(server, client, 200, rows)
end

local function apply_log_settings_patch(body)
    if type(body) ~= "table" then
        return
    end
    if log_store and type(log_store.configure) == "function" then
        if body.log_max_entries ~= nil or body.log_retention_sec ~= nil then
            log_store.configure({
                max_entries = body.log_max_entries,
                retention_sec = body.log_retention_sec,
            })
        end
    end
    if access_log and type(access_log.configure) == "function" then
        if body.access_log_max_entries ~= nil or body.access_log_retention_sec ~= nil then
            access_log.configure({
                max_entries = body.access_log_max_entries,
                retention_sec = body.access_log_retention_sec,
            })
        end
    end

    -- Apply runtime log options (stdout/file/syslog) on-the-fly.
    if body.runtime_log_dest ~= nil
        or body.runtime_log_level ~= nil
        or body.runtime_log_file ~= nil
        or body.runtime_log_syslog ~= nil
        or body.runtime_log_color ~= nil
        or body.runtime_log_rotate_mb ~= nil
        or body.runtime_log_rotate_keep ~= nil
    then
        if _G.runtime_log_baseline == nil and log and type(log.get) == "function" then
            local ok, snap = pcall(log.get)
            if ok and type(snap) == "table" then
                _G.runtime_log_baseline = snap
            end
        end
        local baseline = _G.runtime_log_baseline
        local dest_raw = config.get_setting("runtime_log_dest")
        local level_raw = config.get_setting("runtime_log_level")
        local file_raw = config.get_setting("runtime_log_file")
        local syslog_raw = config.get_setting("runtime_log_syslog")
        local color_raw = config.get_setting("runtime_log_color")
        local rotate_mb_raw = config.get_setting("runtime_log_rotate_mb")
        local rotate_keep_raw = config.get_setting("runtime_log_rotate_keep")

        local dest_mode = nil
        if dest_raw ~= nil then
            dest_mode = tostring(dest_raw or ""):lower()
        end
        local opts = {}
        if dest_mode == "inherit" then
            if type(baseline) == "table" then
                opts.stdout = baseline.stdout == true
                opts.filename = tostring(baseline.filename or "")
                opts.syslog = tostring(baseline.syslog or "")
                opts.color = baseline.color == true
                opts.level = tostring(baseline.level or "")
                opts.rotate_max_bytes = tonumber(baseline.rotate_max_bytes) or 0
                opts.rotate_keep = tonumber(baseline.rotate_keep) or 0
            else
                opts.stdout = true
                opts.filename = ""
                opts.syslog = ""
                opts.color = false
                opts.level = "info"
                opts.rotate_max_bytes = 0
                opts.rotate_keep = 0
            end
        elseif dest_mode ~= nil and dest_mode ~= "inherit" then
            local want_stdout = true
            local want_file = false
            local want_syslog = false
            if dest_mode == "none" then
                want_stdout = false
            elseif dest_mode == "file" then
                want_stdout = false
                want_file = true
            elseif dest_mode == "stdout_file" then
                want_file = true
            elseif dest_mode == "syslog" then
                want_stdout = false
                want_syslog = true
            elseif dest_mode == "stdout_syslog" then
                want_syslog = true
            elseif dest_mode == "file_syslog" then
                want_stdout = false
                want_file = true
                want_syslog = true
            elseif dest_mode == "all" then
                want_file = true
                want_syslog = true
            else
                want_stdout = true
            end

            opts.stdout = want_stdout == true
            opts.filename = want_file and tostring(file_raw or "") or ""
            opts.syslog = want_syslog and tostring(syslog_raw or "") or ""
        elseif dest_mode == nil then
            if file_raw ~= nil then
                opts.filename = tostring(file_raw or "")
            end
            if syslog_raw ~= nil then
                opts.syslog = tostring(syslog_raw or "")
            end
        end

        if level_raw ~= nil then
            local level = tostring(level_raw or ""):lower()
            if level ~= "" and level ~= "inherit" then
                opts.level = level
            end
        end
        if color_raw ~= nil and dest_mode ~= "inherit" then
            local enabled = (color_raw == true or color_raw == 1 or color_raw == "1" or color_raw == "true")
            opts.color = enabled == true
        end
        if rotate_mb_raw ~= nil and dest_mode ~= "inherit" then
            local mb = tonumber(rotate_mb_raw) or 0
            if mb < 0 then mb = 0 end
            opts.rotate_max_bytes = math.floor(mb) * 1024 * 1024
        end
        if rotate_keep_raw ~= nil and dest_mode ~= "inherit" then
            local keep = tonumber(rotate_keep_raw) or 0
            if keep < 0 then keep = 0 end
            opts.rotate_keep = math.floor(keep)
        end

        if next(opts) ~= nil then
            log.set(opts)
        end
    end
end

local function set_settings(server, client, request)
    local body = parse_json_body(request)
    if not body then
        return error_response(server, client, 400, "invalid json")
    end
    local query = request and request.query or {}
    local softcam_apply = true
    if query.softcam_apply ~= nil then
        local v = tostring(query.softcam_apply or ""):lower()
        if v == "0" or v == "false" or v == "no" or v == "off" then
            softcam_apply = false
        end
    end
    if body.telegram_bot_token ~= nil then
        local token = tostring(body.telegram_bot_token or "")
        if token == "" then
            body.telegram_bot_token = nil
        end
    end
    if body.ai_api_key ~= nil then
        local key = tostring(body.ai_api_key or "")
        if key == "" then
            body.ai_api_key = nil
        end
    end
    body.telegram_bot_token_masked = nil
    body.telegram_bot_token_set = nil
    body.ai_api_key_masked = nil
    body.ai_api_key_set = nil
    apply_config_change(server, client, request, {
        comment = "settings update",
        apply = function()
            for k, v in pairs(body) do
                config.set_setting(k, v)
            end
            if softcam_apply and type(apply_softcam_settings) == "function" and body.softcam ~= nil then
                apply_softcam_settings()
            end
            apply_log_settings_patch(body)
            if runtime and runtime.configure_influx
                and (body.influx_enabled ~= nil or body.influx_url ~= nil or body.influx_org ~= nil
                    or body.influx_bucket ~= nil or body.influx_token ~= nil
                    or body.influx_interval_sec ~= nil or body.influx_instance ~= nil
                    or body.influx_measurement ~= nil)
            then
                runtime.configure_influx()
            end
            if runtime and runtime.configure_gc
                and (body.lua_gc_full_collect_interval_ms ~= nil
                    or body.lua_gc_step_interval_ms ~= nil
                    or body.lua_gc_step_units ~= nil)
            then
                runtime.configure_gc()
            end
            if body.performance_aggregate_stream_timers ~= nil
                and type(stream_reconfigure_timer_mode) == "function"
            then
                stream_reconfigure_timer_mode()
            end
            if body.performance_aggregate_transcode_timers ~= nil
                and transcode and transcode.reconfigure_timer_mode
            then
                transcode.reconfigure_timer_mode()
            end
            if telegram and telegram.configure
                and (body.telegram_enabled ~= nil or body.telegram_level ~= nil
                    or body.telegram_bot_token ~= nil or body.telegram_chat_id ~= nil
                    or body.telegram_backup_enabled ~= nil or body.telegram_backup_schedule ~= nil
                    or body.telegram_backup_time ~= nil or body.telegram_backup_weekday ~= nil
                    or body.telegram_backup_monthday ~= nil or body.telegram_backup_include_secrets ~= nil
                    or body.telegram_summary_enabled ~= nil or body.telegram_summary_schedule ~= nil
                    or body.telegram_summary_time ~= nil or body.telegram_summary_weekday ~= nil
                    or body.telegram_summary_monthday ~= nil or body.telegram_summary_include_charts ~= nil)
            then
                telegram.configure()
            end
            if ai_runtime and ai_runtime.configure
                and (body.ai_enabled ~= nil or body.ai_model ~= nil or body.ai_max_tokens ~= nil
                    or body.ai_temperature ~= nil or body.ai_store ~= nil
                    or body.ai_allow_apply ~= nil or body.ai_telegram_allowed_chat_ids ~= nil)
            then
                ai_runtime.configure()
            end
            if ai_observability and ai_observability.configure
                and (body.ai_logs_retention_days ~= nil or body.ai_metrics_retention_days ~= nil
                    or body.ai_rollup_interval_sec ~= nil)
            then
                ai_observability.configure()
            end
            if system_metrics and system_metrics.configure
                and (body.ai_logs_retention_days ~= nil or body.ai_metrics_retention_days ~= nil
                    or body.ai_rollup_interval_sec ~= nil
                    or body.observability_system_rollup_enabled ~= nil
                    or body.observability_system_rollup_interval_sec ~= nil
                    or body.observability_system_retention_sec ~= nil
                    or body.observability_system_include_virtual_ifaces ~= nil)
            then
                system_metrics.configure()
            end
            if watchdog and watchdog.configure
                and (body.resource_watchdog_enabled ~= nil or body.resource_watchdog_interval_sec ~= nil
                    or body.resource_watchdog_cpu_pct ~= nil or body.resource_watchdog_rss_mb ~= nil
                    or body.resource_watchdog_rss_pct ~= nil or body.resource_watchdog_max_strikes ~= nil
                    or body.resource_watchdog_min_uptime_sec ~= nil or body.resource_watchdog_action ~= nil)
            then
                watchdog.configure()
            end
        end,
        after = function()
            if epg and epg.configure_timer then
                epg.configure_timer()
            end
        end,
    })
end

local function telegram_test(server, client)
    if not telegram or not telegram.send_test then
        return error_response(server, client, 400, "telegram notifier unavailable")
    end
    local ok, err = telegram.send_test()
    if not ok then
        return error_response(server, client, 400, err or "telegram disabled")
    end
    json_response(server, client, 200, { status = "queued" })
end

local function telegram_backup(server, client)
    if not telegram or not telegram.send_backup_now then
        return error_response(server, client, 400, "telegram notifier unavailable")
    end
    local ok, err = telegram.send_backup_now()
    if not ok then
        return error_response(server, client, 400, err or "telegram disabled")
    end
    json_response(server, client, 200, { status = "queued" })
end

local function telegram_summary(server, client)
    if not telegram or not telegram.send_summary_now then
        return error_response(server, client, 400, "telegram notifier unavailable")
    end
    local ok, err = telegram.send_summary_now()
    if not ok then
        return error_response(server, client, 400, err or "telegram disabled")
    end
    json_response(server, client, 200, { status = "queued" })
end

local function ai_status(server, client)
    if not ai_runtime or not ai_runtime.status then
        return json_response(server, client, 200, { enabled = false, ready = false })
    end
    json_response(server, client, 200, ai_runtime.status())
end

local function ai_jobs(server, client)
    if not ai_runtime or not ai_runtime.list_jobs then
        return json_response(server, client, 200, { status = ai_runtime and ai_runtime.status and ai_runtime.status() or {}, jobs = {} })
    end
    json_response(server, client, 200, { status = ai_runtime.status(), jobs = ai_runtime.list_jobs() })
end

local function parse_range_seconds(value, fallback)
    if value == nil or value == "" then
        return fallback
    end
    local text = tostring(value)
    local num, unit = text:match("^(%d+)%s*([smhdwSMHDW]?)$")
    if not num then
        return fallback
    end
    local n = tonumber(num)
    if not n or n <= 0 then
        return fallback
    end
    unit = (unit or ""):lower()
    if unit == "m" then
        return n * 60
    elseif unit == "h" or unit == "" then
        return n * 3600
    elseif unit == "d" then
        return n * 86400
    elseif unit == "w" then
        return n * 604800
    end
    return fallback
end

local function ai_logs(server, client, request)
    if not require_admin(request) then
        return error_response(server, client, 403, "forbidden")
    end
    if not config or not config.list_ai_log_events then
        return error_response(server, client, 400, "observability unavailable")
    end
    local query = request and request.query or {}
    local range = parse_range_seconds(query.range, 24 * 3600)
    local since_ts = os.time() - range
    local until_ts = nil
    local level = query.level
    local stream_id = query.stream_id or query.stream
    local limit = tonumber(query.limit) or 500
    local rows = config.list_ai_log_events({
        since = since_ts,
        ["until"] = until_ts,
        level = level,
        stream_id = stream_id,
        limit = limit,
    })
    json_response(server, client, 200, {
        since = since_ts,
        range = range,
        items = rows,
    })
end

local function ai_metrics(server, client, request)
    if not require_admin(request) then
        return error_response(server, client, 403, "forbidden")
    end
    if not config or not config.list_ai_metrics then
        return error_response(server, client, 400, "observability unavailable")
    end
    local query = request and request.query or {}
    local range = parse_range_seconds(query.range, 24 * 3600)
    local since_ts = os.time() - range
    local scope = query.scope or "global"
    local scope_id = query.id or query.stream_id or ""
    local metric_key = query.metric or ""
    local limit = tonumber(query.limit) or 2000
    local on_demand = setting_bool("ai_metrics_on_demand", true)
    if ai_observability and ai_observability.state and ai_observability.state.metrics_on_demand then
        on_demand = true
    end
    if on_demand and ai_observability and ai_observability.build_metrics_from_logs then
        local base_interval = setting_number("ai_rollup_interval_sec", 60)
        local target_points = 240
        local adaptive = math.floor(range / target_points)
        local interval = math.max(base_interval, adaptive > 0 and adaptive or base_interval)
        local result = ai_observability.get_on_demand_metrics
            and ai_observability.get_on_demand_metrics(range, interval, scope, scope_id)
            or { items = ai_observability.build_metrics_from_logs(range, interval, scope, scope_id), mode = "on_demand" }
        local items = result.items or {}
        if metric_key and metric_key ~= "" then
            local filtered = {}
            for _, item in ipairs(items) do
                if item.metric_key == metric_key then
                    table.insert(filtered, item)
                end
            end
            items = filtered
        end
        table.sort(items, function(a, b)
            if a.ts_bucket == b.ts_bucket then
                return tostring(a.metric_key) < tostring(b.metric_key)
            end
            return (a.ts_bucket or 0) < (b.ts_bucket or 0)
        end)
        json_response(server, client, 200, {
            since = since_ts,
            range = range,
            items = items,
            mode = result.mode or "on_demand",
        })
        return
    end

    local rows = config.list_ai_metrics({
        since = since_ts,
        scope = scope,
        scope_id = scope_id,
        metric_key = metric_key,
        limit = limit,
    })
    json_response(server, client, 200, {
        since = since_ts,
        range = range,
        items = rows,
        mode = "rollup",
    })
end

local function observability_enabled()
    -- Keep in sync with web/app.js isViewEnabled('observability')
    local on_demand = setting_bool("ai_metrics_on_demand", true)
    local logs_days = setting_number("ai_logs_retention_days", 0)
    local metrics_days = setting_number("ai_metrics_retention_days", 0)
    if on_demand then
        metrics_days = 0
    end
    return (logs_days or 0) > 0 or (metrics_days or 0) > 0
end

local function system_metrics_snapshot(server, client, request)
    if not require_admin(request) then
        return error_response(server, client, 403, "forbidden")
    end
    if not observability_enabled() then
        return error_response(server, client, 403, "observability disabled")
    end
    if not system_metrics or not system_metrics.snapshot then
        return error_response(server, client, 400, "system metrics unavailable")
    end

    local snap = system_metrics.snapshot() or {}
    local now_ms = (snap.ts or os.time()) * 1000
    snap.ts_ms = now_ms

    json_response(server, client, 200, {
        now = now_ms,
        snapshot = snap,
        flags = {
            enabled = true,
            rollup = (system_metrics.state and system_metrics.state.rollup_enabled) == true,
        },
    })
end

local function system_metrics_timeseries(server, client, request)
    if not require_admin(request) then
        return error_response(server, client, 403, "forbidden")
    end
    if not observability_enabled() then
        return error_response(server, client, 403, "observability disabled")
    end
    if not system_metrics or not system_metrics.get_timeseries then
        return error_response(server, client, 400, "system metrics unavailable")
    end

    local query = request and request.query or {}
    local range = parse_range_seconds(query.range, 24 * 3600)
    local result = system_metrics.get_timeseries(range) or {}
    local items = result.items or {}

    local series = {
        cpu_usage = {},
        mem_used_percent = {},
        disk_used_percent = {},
        net_rx_bps = {},
        net_tx_bps = {},
    }

    for _, pt in ipairs(items) do
        local t = pt.t_ms
        if t then
            if pt.cpu_usage ~= nil then
                table.insert(series.cpu_usage, { t, pt.cpu_usage })
            end
            if pt.mem_used_percent ~= nil then
                table.insert(series.mem_used_percent, { t, pt.mem_used_percent })
            end
            if pt.disk_used_percent ~= nil then
                table.insert(series.disk_used_percent, { t, pt.disk_used_percent })
            end
            if pt.net then
                for iface, v in pairs(pt.net) do
                    if v and v.rx_bps ~= nil then
                        series.net_rx_bps[iface] = series.net_rx_bps[iface] or {}
                        table.insert(series.net_rx_bps[iface], { t, v.rx_bps })
                    end
                    if v and v.tx_bps ~= nil then
                        series.net_tx_bps[iface] = series.net_tx_bps[iface] or {}
                        table.insert(series.net_tx_bps[iface], { t, v.tx_bps })
                    end
                end
            end
        end
    end

    local now_ms = os.time() * 1000
    json_response(server, client, 200, {
        now = now_ms,
        timeseries = series,
        flags = {
            enabled = true,
            rollup = result.rollup == true,
            rollup_enabled = (system_metrics.state and system_metrics.state.rollup_enabled) == true,
        },
    })
end

local function ai_summary(server, client, request)
    if not require_admin(request) then
        return error_response(server, client, 403, "forbidden")
    end
    if not config or not config.list_ai_metrics then
        return error_response(server, client, 400, "observability unavailable")
    end
    local query = request and request.query or {}
    local include_logs = false
    if query.include_logs ~= nil then
        local value = tostring(query.include_logs)
        if value == "1" or value == "true" then
            include_logs = true
        end
    end
    local include_cli = query.include_cli or query.cli
    local cli_stream_id = query.stream_id or query.id
    local cli_input_url = query.input_url or query.url
    local cli_femon_url = query.femon_url
    local cli_log_limit = tonumber(query.log_limit) or nil
    local range = parse_range_seconds(query.range, 24 * 3600)
    local since_ts = os.time() - range
    local on_demand = setting_bool("ai_metrics_on_demand", true)
    if ai_observability and ai_observability.state and ai_observability.state.metrics_on_demand then
        on_demand = true
    end
    local summary = {
        total_bitrate_kbps = 0,
        streams_on_air = 0,
        streams_down = 0,
        streams_total = 0,
        input_switch = 0,
        alerts_error = 0,
    }
    local last_bucket = 0
    local metrics = {}
    if on_demand and ai_observability and ai_observability.build_metrics_from_logs then
        local base_interval = setting_number("ai_rollup_interval_sec", 60)
        local target_points = 240
        local adaptive = math.floor(range / target_points)
        local interval = math.max(base_interval, adaptive > 0 and adaptive or base_interval)
        local result = ai_observability.get_on_demand_metrics
            and ai_observability.get_on_demand_metrics(range, interval, "global", "")
            or nil
        if result then
            metrics = result.items or {}
            summary = result.summary or summary
            last_bucket = result.bucket or 0
        end
    else
        metrics = config.list_ai_metrics({
            since = since_ts,
            scope = "global",
            limit = 10000,
        })
        for _, row in ipairs(metrics) do
            if row.ts_bucket and row.ts_bucket > last_bucket then
                last_bucket = row.ts_bucket
            end
        end
        if last_bucket > 0 then
            for _, row in ipairs(metrics) do
                if row.ts_bucket == last_bucket then
                    if summary[row.metric_key] ~= nil then
                        summary[row.metric_key] = row.value
                    end
                end
            end
        end
    end

    local want_ai = query.ai == "1" or query.ai == "true" or query.mode == "ai"
    if not want_ai then
        return json_response(server, client, 200, {
            range = range,
            latest_bucket = last_bucket,
            summary = summary,
            note = "AI summary not enabled; returning latest rollup snapshot",
        })
    end
    if not ai_runtime or not ai_runtime.is_ready or not ai_runtime.is_ready() then
        return json_response(server, client, 200, {
            range = range,
            latest_bucket = last_bucket,
            summary = summary,
            ai = nil,
            note = "AI not configured",
        })
    end
    if include_logs and (not config or not config.list_ai_log_events) then
        return json_response(server, client, 200, {
            range = range,
            latest_bucket = last_bucket,
            summary = summary,
            ai = nil,
            note = "AI log events unavailable",
        })
    end
    local errors = {}
    if include_logs and config and config.list_ai_log_events then
        errors = config.list_ai_log_events({
            since = since_ts,
            level = "ERROR",
            limit = 20,
        })
    end
    local responded = false
    ai_runtime.request_summary({
        summary = summary,
        errors = errors,
        range_sec = range,
        include_logs = include_logs,
        include_cli = include_cli,
        stream_id = cli_stream_id,
        input_url = cli_input_url,
        femon_url = cli_femon_url,
        log_limit = cli_log_limit,
    }, function(ok, result)
        if responded then return end
        responded = true
        if not ok then
            return json_response(server, client, 200, {
                range = range,
                latest_bucket = last_bucket,
                summary = summary,
                ai = nil,
                note = "AI summary failed",
            })
        end
        json_response(server, client, 200, {
            range = range,
            latest_bucket = last_bucket,
            summary = summary,
            ai = result,
            note = "AI summary",
        })
    end)
end

local function ai_plan(server, client, request)
    if not require_admin(request) then
        return error_response(server, client, 403, "forbidden")
    end
    if not ai_runtime or not ai_runtime.plan then
        return error_response(server, client, 400, "ai runtime unavailable")
    end
    local body = parse_json_body(request)
    if not body then
        return error_response(server, client, 400, "invalid json")
    end
    local user = get_request_user(request)
    local job = ai_runtime.plan(body, {
        user = user and user.username or (request and request.user or ""),
        user_id = user and user.id or 0,
        ip = request and request.addr or "",
    })
    if not job then
        return error_response(server, client, 500, "ai plan failed")
    end
    json_response(server, client, 200, job)
end

local function ai_apply(server, client, request)
    if not require_admin(request) then
        return error_response(server, client, 403, "forbidden")
    end
    if not ai_runtime or not ai_runtime.apply then
        return error_response(server, client, 400, "ai runtime unavailable")
    end
    if not ai_runtime.is_enabled or not ai_runtime.is_enabled() then
        return error_response(server, client, 400, "ai disabled")
    end
    if not (ai_runtime.config and ai_runtime.config.allow_apply) then
        return error_response(server, client, 403, "ai apply disabled")
    end
    local body = parse_json_body(request)
    if not body then
        return error_response(server, client, 400, "invalid json")
    end
    local ok, err = ai_runtime.apply(body, { user = request and request.user or "" })
    if not ok then
        return error_response(server, client, 501, err or "ai apply not implemented")
    end
    json_response(server, client, 200, ok)
end

local function ai_telegram(server, client, request)
    if not require_admin(request) then
        return error_response(server, client, 403, "forbidden")
    end
    if not ai_runtime or not ai_runtime.handle_telegram then
        return error_response(server, client, 400, "ai runtime unavailable")
    end
    local body = parse_json_body(request)
    if not body then
        return error_response(server, client, 400, "invalid json")
    end
    local ok, err = ai_runtime.handle_telegram(body)
    if not ok then
        return error_response(server, client, 501, err or "ai telegram not implemented")
    end
    json_response(server, client, 200, ok)
end

local function resolve_server_entry(body)
    if type(body) ~= "table" then
        return nil, "invalid json"
    end
    if body.id and config and config.get_setting then
        local list = config.get_setting("servers")
        if type(list) == "table" then
            for _, item in ipairs(list) do
                if type(item) == "table" and tostring(item.id or "") == tostring(body.id or "") then
                    return item
                end
            end
        end
        return nil, "server not found"
    end
    return body
end

local function normalize_server_host(entry)
    if type(entry) ~= "table" then
        return nil, "invalid server"
    end
    local host = entry.host or entry.address or ""
    if host == "" then
        return nil, "server host required"
    end
    local parsed = nil
    if host:find("://", 1, true) then
        parsed = parse_url(host)
        if not parsed then
            return nil, "invalid server url"
        end
    end
    local host_only = host
    local port_hint = nil
    if not parsed then
        local maybe_host, maybe_port = host:match("^(.-):(%d+)$")
        if maybe_host and maybe_port then
            host_only = maybe_host
            port_hint = tonumber(maybe_port)
        end
    end
    local scheme = parsed and parsed.format or "http"
    if scheme ~= "http" and scheme ~= "https" then
        return nil, "unsupported scheme"
    end
    local port = tonumber(entry.port) or port_hint or (parsed and parsed.port) or (scheme == "https" and 443 or 8000)
    local hostname = parsed and parsed.host or host_only
    local base_path = parsed and parsed.path or ""
    if base_path == "/" then
        base_path = ""
    end
    return {
        host = hostname,
        port = port,
        login = entry.login or entry.user or "",
        password = entry.password or entry.pass or "",
        scheme = scheme,
        base_path = base_path,
    }
end

local function slugify_server_id(value)
    local text = tostring(value or ""):lower()
    text = text:gsub("[^%w_-]+", "_")
    text = text:gsub("_+", "_")
    text = text:gsub("^_+", ""):gsub("_+$", "")
    return text
end

local function get_server_id(entry)
    if type(entry) ~= "table" then
        return nil
    end
    local id = tostring(entry.id or "")
    if id ~= "" then
        return id
    end
    local seed = entry.name or entry.host or entry.address or ""
    local slug = slugify_server_id(seed)
    if slug == "" then
        return nil
    end
    return slug
end

local function build_server_path(cfg, path)
    local base = cfg.base_path or ""
    if base == "" then
        return path
    end
    return base .. path
end

local function decode_json_safe(text)
    if not text or text == "" then
        return nil
    end
    local ok, data = pcall(json.decode, text)
    if not ok then
        return nil
    end
    return data
end

local function parse_cookie_from_headers(headers)
    if not headers then
        return nil
    end
    local raw = headers["set-cookie"] or headers["Set-Cookie"]
    if not raw then
        return nil
    end
    local token = tostring(raw):match("astra_session=([^;]+)")
    if token and token ~= "" then
        return "astra_session=" .. token
    end
    return nil
end

local function ensure_curl_available()
    if not process or type(process.spawn) ~= "function" then
        return false
    end
    local ok, proc = pcall(process.spawn, { "curl", "--version" }, { stdout = "pipe", stderr = "pipe" })
    if not ok or not proc then
        return false
    end
    if proc and proc.close then
        proc:close()
    end
    return true
end

local function run_curl(args, callback)
    if not ensure_curl_available() then
        callback(nil, nil, "curl unavailable")
        return
    end
    local ok, proc = pcall(process.spawn, args, { stdout = "pipe", stderr = "pipe" })
    if not ok or not proc then
        callback(nil, nil, "curl spawn failed")
        return
    end
    local start_ts = os.time()
    local poller = nil
    poller = timer({
        interval = 0.2,
        callback = function()
            local status = proc:poll()
            if not status then
                if os.time() - start_ts > 15 then
                    proc:terminate()
                    proc:kill()
                    proc:close()
                    if poller then poller:close() end
                    callback(nil, nil, "curl timeout")
                end
                return
            end
            if poller then poller:close() end
            local stdout = proc:read_stdout()
            local stderr = proc:read_stderr()
            proc:close()
            callback(status, stdout, stderr)
        end,
    })
end

local function parse_curl_body_code(output)
    if not output then
        return nil, nil
    end
    local code = output:match("ASTRA_HTTP_CODE:(%d+)%s*$")
    local body = output:gsub("\nASTRA_HTTP_CODE:%d+%s*$", "")
    if code then
        return tonumber(code), body
    end
    return nil, output
end

local function split_headers_body(text)
    if not text then
        return "", ""
    end
    local marker = "\r\n\r\n"
    local idx = text:find(marker, 1, true)
    if not idx then
        return text, ""
    end
    local head = text:sub(1, idx - 1)
    local body = text:sub(idx + #marker)
    return head, body
end

local function parse_status_from_headers(text)
    if not text then
        return nil
    end
    local code = text:match("HTTP/%d%.%d%s+(%d%d%d)")
    if code then
        return tonumber(code)
    end
    return nil
end

local function parse_cookie_from_header_text(text)
    if not text then
        return nil
    end
    local cookie = text:match("[Ss]et%-[Cc]ookie:%s*([^\r\n]+)")
    if not cookie then
        return nil
    end
    local token = cookie:match("astra_session=([^;]+)")
    if token and token ~= "" then
        return "astra_session=" .. token
    end
    return nil
end

local function remote_http_login(cfg, callback)
    if not cfg.login or cfg.login == "" or not cfg.password or cfg.password == "" then
        callback(true, nil)
        return
    end
    local payload = json.encode({ username = cfg.login, password = cfg.password })
    local headers = {
        "Content-Type: application/json",
        "Content-Length: " .. tostring(#payload),
        "Host: " .. tostring(cfg.host) .. ":" .. tostring(cfg.port),
        "Connection: close",
    }
    local paths = {
        "/api/v1/auth/login",
        "/api/auth/login",
    }
    local idx = 1
    local function attempt()
        local path = build_server_path(cfg, paths[idx])
        http_request({
            host = cfg.host,
            port = cfg.port,
            path = path,
            method = "POST",
            headers = headers,
            content = payload,
            callback = function(self, response)
                if not response then
                    return callback(false, nil, "login failed (no response)")
                end
                local code = response.code or 0
                if code == 404 and idx < #paths then
                    idx = idx + 1
                    return attempt()
                end
                if not code or code >= 400 then
                    return callback(false, nil, "login failed (" .. tostring(code or "unknown") .. ")")
                end
                local cookie = parse_cookie_from_headers(response.headers)
                if not cookie then
                    return callback(false, nil, "login failed (no session cookie)")
                end
                callback(true, cookie)
            end,
        })
    end
    attempt()
end

local function remote_http_fetch_json(cfg, path, cookie, method, body, callback)
    local headers = {
        "Host: " .. tostring(cfg.host) .. ":" .. tostring(cfg.port),
        "Connection: close",
    }
    if cookie and cookie ~= "" then
        table.insert(headers, "Cookie: " .. cookie)
    end
    local payload = body or nil
    if payload then
        table.insert(headers, "Content-Type: application/json")
        table.insert(headers, "Content-Length: " .. tostring(#payload))
    end
    http_request({
        host = cfg.host,
        port = cfg.port,
        path = build_server_path(cfg, path),
        method = method or "GET",
        headers = headers,
        content = payload,
        callback = function(self, response)
            if not response then
                return callback(false, nil, "no response")
            end
            local code = response.code or 0
            if code >= 400 then
                return callback(false, nil, "http " .. tostring(code))
            end
            local data = decode_json_safe(response.content or "")
            if not data then
                return callback(false, nil, "invalid json", code)
            end
            callback(true, data, nil, code)
        end,
    })
end

local function remote_https_login(cfg, callback)
    if not cfg.login or cfg.login == "" or not cfg.password or cfg.password == "" then
        callback(true, nil)
        return
    end
    local payload = json.encode({ username = cfg.login, password = cfg.password })
    local paths = {
        "/api/v1/auth/login",
        "/api/auth/login",
    }
    local idx = 1
    local function attempt()
        local url = string.format("https://%s:%d%s", cfg.host, cfg.port, build_server_path(cfg, paths[idx]))
        local args = {
            "curl",
            "-sS",
            "-D",
            "-",
            "-o",
            "-",
            "-H",
            "Content-Type: application/json",
            "-X",
            "POST",
            url,
            "-d",
            payload,
        }
        run_curl(args, function(status, stdout, stderr)
            if not status then
                return callback(false, nil, stderr or "login failed")
            end
            local head, _ = split_headers_body(stdout or "")
            local code = parse_status_from_headers(head) or 0
            if code == 404 and idx < #paths then
                idx = idx + 1
                return attempt()
            end
            if not code or code >= 400 then
                return callback(false, nil, "login failed (" .. tostring(code or "unknown") .. ")")
            end
            local cookie = parse_cookie_from_header_text(head)
            if not cookie then
                return callback(false, nil, "login failed (no session cookie)")
            end
            callback(true, cookie)
        end)
    end
    attempt()
end

local function remote_https_fetch_json(cfg, path, cookie, method, body, callback)
    local url = string.format("https://%s:%d%s", cfg.host, cfg.port, build_server_path(cfg, path))
    local args = { "curl", "-sS", "-w", "\nASTRA_HTTP_CODE:%{http_code}\n" }
    if cookie and cookie ~= "" then
        table.insert(args, "-H")
        table.insert(args, "Cookie: " .. cookie)
    end
    if body then
        table.insert(args, "-H")
        table.insert(args, "Content-Type: application/json")
        table.insert(args, "-X")
        table.insert(args, method or "POST")
        table.insert(args, "-d")
        table.insert(args, body)
    else
        if method and method ~= "GET" then
            table.insert(args, "-X")
            table.insert(args, method)
        end
    end
    table.insert(args, url)
    run_curl(args, function(status, stdout, stderr)
        if not status then
            return callback(false, nil, stderr or "curl failed")
        end
        local code, bodyText = parse_curl_body_code(stdout or "")
        if not code then
            return callback(false, nil, "no http code")
        end
        if code >= 400 then
            return callback(false, nil, "http " .. tostring(code), code)
        end
        local data = decode_json_safe(bodyText or "")
        if not data then
            return callback(false, nil, "invalid json", code)
        end
        callback(true, data, nil, code)
    end)
end

local function remote_login(cfg, callback)
    if cfg.scheme == "https" then
        return remote_https_login(cfg, callback)
    end
    return remote_http_login(cfg, callback)
end

local function remote_fetch_json(cfg, path, cookie, method, body, callback)
    if cfg.scheme == "https" then
        return remote_https_fetch_json(cfg, path, cookie, method, body, callback)
    end
    return remote_http_fetch_json(cfg, path, cookie, method, body, callback)
end

local function remote_health_check(cfg, callback)
    local function do_health(cookie, path)
        remote_fetch_json(cfg, path, cookie, "GET", nil, function(ok, data, err, code)
            if ok then
                return callback(true, "health ok")
            end
            if err == "invalid json" and code and code >= 200 and code < 300 then
                return callback(true, "health ok")
            end
            if code == 404 and path == "/api/v1/health/process" then
                return do_health(cookie, "/api/v1/health")
            end
            return callback(false, err or "health check failed")
        end)
    end
    remote_login(cfg, function(ok, cookie, err)
        if not ok then
            return callback(false, err or "login failed")
        end
        do_health(cookie, "/api/v1/health/process")
    end)
end

local function server_test(server, client, request)
    local body = parse_json_body(request)
    if not body then
        return error_response(server, client, 400, "invalid json")
    end
    local entry, err = resolve_server_entry(body)
    if not entry then
        return error_response(server, client, 404, err or "server not found")
    end
    local cfg, cfg_err = normalize_server_host(entry)
    if not cfg then
        return error_response(server, client, 400, cfg_err or "invalid server")
    end

    local responded = false
    local function respond_ok(message)
        if responded then return end
        responded = true
        json_response(server, client, 200, { status = "ok", message = message or "ok" })
    end
    local function respond_err(code, message)
        if responded then return end
        responded = true
        error_response(server, client, code or 400, message or "failed")
    end

    local base_path = cfg.base_path or ""
    local function build_path(path)
        if base_path == "" then
            return path
        end
        return base_path .. path
    end

    local function do_health(cookie)
        local headers = {
            "Host: " .. tostring(cfg.host) .. ":" .. tostring(cfg.port),
            "Connection: close",
        }
        if cookie and cookie ~= "" then
            table.insert(headers, "Cookie: " .. cookie)
        end
        http_request({
            host = cfg.host,
            port = cfg.port,
            path = build_path("/api/v1/health/process"),
            method = "GET",
            headers = headers,
            callback = function(self, response)
                if not response then
                    return respond_err(502, "no response from server")
                end
                if response.code and response.code >= 200 and response.code < 300 then
                    return respond_ok("health ok")
                end
                if response.code == 404 then
                    http_request({
                        host = cfg.host,
                        port = cfg.port,
                        path = build_path("/api/v1/health"),
                        method = "GET",
                        headers = headers,
                        callback = function(self2, response2)
                            if not response2 then
                                return respond_err(502, "no response from server")
                            end
                            if response2.code and response2.code >= 200 and response2.code < 300 then
                                return respond_ok("health ok")
                            end
                            return respond_err(400, "health check failed (" .. tostring(response2.code or "unknown") .. ")")
                        end,
                    })
                    return
                end
                return respond_err(400, "health check failed (" .. tostring(response.code or "unknown") .. ")")
            end,
        })
    end

    local function ensure_curl_available()
        if not process or type(process.spawn) ~= "function" then
            return false
        end
        local ok, proc = pcall(process.spawn, { "curl", "--version" }, { stdout = "pipe", stderr = "pipe" })
        if not ok or not proc then
            return false
        end
        if proc and proc.close then
            proc:close()
        end
        return true
    end

    local function run_curl(args, callback)
        if not ensure_curl_available() then
            callback(nil, nil, "curl unavailable")
            return
        end
        local ok, proc = pcall(process.spawn, args, { stdout = "pipe", stderr = "pipe" })
        if not ok or not proc then
            callback(nil, nil, "curl spawn failed")
            return
        end
        local start_ts = os.time()
        local poller = nil
        poller = timer({
            interval = 0.2,
            callback = function()
                local status = proc:poll()
                if not status then
                    if os.time() - start_ts > 10 then
                        proc:terminate()
                        proc:kill()
                        proc:close()
                        if poller then poller:close() end
                        callback(nil, nil, "curl timeout")
                    end
                    return
                end
                if poller then poller:close() end
                local stdout = proc:read_stdout()
                local stderr = proc:read_stderr()
                proc:close()
                callback(status, stdout, stderr)
            end,
        })
    end

    local function parse_http_code(text)
        if not text then
            return nil
        end
        local code = text:match("(%d%d%d)%s*$")
        if code then
            return tonumber(code)
        end
        return nil
    end

    local function parse_cookie(text)
        if not text then
            return ""
        end
        local line = text:match("[Ss]et%-[Cc]ookie:%s*([^\r\n]+)")
        if not line then
            return ""
        end
        local token = line:match("astra_session=([^;]+)")
        return token or ""
    end

    local function do_health_https(cookie)
        local url = string.format("https://%s:%d%s", cfg.host, cfg.port, build_path("/api/v1/health/process"))
        local args = { "curl", "-sS", "-o", "/dev/null", "-w", "%{http_code}" }
        if cookie and cookie ~= "" then
            table.insert(args, "-H")
            table.insert(args, "Cookie: " .. cookie)
        end
        table.insert(args, url)
        run_curl(args, function(status, stdout, stderr)
            if not status then
                return respond_err(502, stderr or "curl failed")
            end
            local code = parse_http_code(stdout)
            if code and code >= 200 and code < 300 then
                return respond_ok("health ok")
            end
            if code == 404 then
                local url2 = string.format("https://%s:%d%s", cfg.host, cfg.port, build_path("/api/v1/health"))
                run_curl({ "curl", "-sS", "-o", "/dev/null", "-w", "%{http_code}", url2 }, function(status2, stdout2, stderr2)
                    if not status2 then
                        return respond_err(502, stderr2 or "curl failed")
                    end
                    local code2 = parse_http_code(stdout2)
                    if code2 and code2 >= 200 and code2 < 300 then
                        return respond_ok("health ok")
                    end
                    return respond_err(400, "health check failed (" .. tostring(code2 or "unknown") .. ")")
                end)
                return
            end
            return respond_err(400, "health check failed (" .. tostring(code or "unknown") .. ")")
        end)
    end

    if cfg.scheme == "https" then
        if cfg.login ~= "" and cfg.password ~= "" then
            local payload = json.encode({ username = cfg.login, password = cfg.password })
            local url = string.format("https://%s:%d%s", cfg.host, cfg.port, build_path("/api/v1/auth/login"))
            local args = {
                "curl",
                "-sS",
                "-D",
                "-",
                "-o",
                "/dev/null",
                "-H",
                "Content-Type: application/json",
                "-X",
                "POST",
                "-w",
                "\n%{http_code}\n",
                url,
                "-d",
                payload,
            }
            run_curl(args, function(status, stdout, stderr)
                if not status then
                    return respond_err(502, stderr or "login failed")
                end
                local code = parse_http_code(stdout)
                if not code or code >= 400 then
                    return respond_err(400, "login failed (" .. tostring(code or "unknown") .. ")")
                end
                local token = parse_cookie(stdout)
                if token == "" then
                    return respond_err(400, "login failed (no session cookie)")
                end
                do_health_https("astra_session=" .. token)
            end)
            return
        end
        do_health_https(nil)
        return
    end

    if cfg.login ~= "" and cfg.password ~= "" then
        local payload = json.encode({ username = cfg.login, password = cfg.password })
        local headers = {
            "Content-Type: application/json",
            "Content-Length: " .. tostring(#payload),
            "Host: " .. tostring(cfg.host) .. ":" .. tostring(cfg.port),
            "Connection: close",
        }
        http_request({
            host = cfg.host,
            port = cfg.port,
            path = build_path("/api/v1/auth/login"),
            method = "POST",
            headers = headers,
            content = payload,
            callback = function(self, response)
                if not response then
                    return respond_err(502, "login failed (no response)")
                end
                if not response.code or response.code >= 400 then
                    return respond_err(400, "login failed (" .. tostring(response.code or "unknown") .. ")")
                end
                local cookie = nil
                if response.headers and response.headers["set-cookie"] then
                    cookie = tostring(response.headers["set-cookie"])
                end
                local token = cookie and cookie:match("astra_session=([^;]+)") or ""
                if token == "" then
                    return respond_err(400, "login failed (no session cookie)")
                end
                do_health("astra_session=" .. token)
            end,
        })
        return
    end

    do_health(nil)
end

local function softcam_test(server, client, request)
    local admin = require_admin(request)
    if not admin then
        return error_response(server, client, 403, "forbidden")
    end
    local body = parse_json_body(request)
    if not body then
        return error_response(server, client, 400, "invalid json")
    end

    local host = tostring(body.host or ""):gsub("^%s+", ""):gsub("%s+$", "")
    local port = tonumber(body.port or 0) or 0
    local user = tostring(body.user or ""):gsub("^%s+", ""):gsub("%s+$", "")
    local pass = tostring(body.pass or "")
    local key = tostring(body.key or ""):gsub("%s+", "")
    local caid = tostring(body.caid or ""):gsub("%s+", "")

    if host == "" then
        return error_response(server, client, 400, "host is required")
    end
    if port <= 0 then
        return error_response(server, client, 400, "port is required")
    end
    if user == "" then
        return error_response(server, client, 400, "user is required")
    end
    if pass == "" then
        return error_response(server, client, 400, "pass is required")
    end

    if key ~= "" then
        if key:sub(1, 2):lower() == "0x" then
            key = key:sub(3)
        end
        if not key:match("^[0-9a-fA-F]+$") or #key ~= 28 then
            return error_response(server, client, 400, "key must be 28 hex chars")
        end
        key = key:lower()
    end

    if caid ~= "" then
        if caid:sub(1, 2):lower() == "0x" then
            caid = caid:sub(3)
        end
        if not caid:match("^[0-9a-fA-F]+$") or #caid ~= 4 then
            return error_response(server, client, 400, "caid must be 4 hex chars")
        end
        caid = caid:upper()
    end

    local timeout = tonumber(body.timeout or 0) or 0
    if timeout <= 0 then
        local timeout_ms = tonumber(body.timeout_ms or 0) or 0
        if timeout_ms > 0 then
            timeout = math.floor(timeout_ms / 1000)
        end
    end
    if timeout <= 0 then
        timeout = 8
    end

    local ctor = _G["newcamd"]
    if type(ctor) ~= "function" and type(ctor) ~= "table" then
        return error_response(server, client, 500, "newcamd module unavailable")
    end

    local cfg = {
        name = "Softcam test",
        type = "newcamd",
        host = host,
        port = port,
        user = user,
        pass = pass,
        timeout = timeout,
        disable_emm = true,
    }
    if key ~= "" then
        cfg.key = key
    end
    if caid ~= "" then
        cfg.caid = caid
    end

    local ok, cam = pcall(ctor, cfg)
    if not ok or not cam then
        return error_response(server, client, 400, "softcam init failed")
    end
    if type(cam) ~= "table" or type(cam.stats) ~= "function" then
        pcall(function()
            if cam and cam.close then cam:close() end
        end)
        return error_response(server, client, 500, "softcam stats unavailable")
    end

    local responded = false
    local poller = nil
    local tries = 0
    local last_stats = nil

    local function finish_ok(message, stats)
        if responded then return end
        responded = true
        if poller then poller:close() end
        pcall(function()
            if cam and cam.close then cam:close() end
        end)
        json_response(server, client, 200, {
            status = "ok",
            message = message or "ok",
            cam = stats,
        })
    end

    local function finish_err(code, message, stats)
        if responded then return end
        responded = true
        if poller then poller:close() end
        pcall(function()
            if cam and cam.close then cam:close() end
        end)
        json_response(server, client, code or 400, {
            error = message or "softcam test failed",
            cam = stats,
        })
    end

    local max_wait_sec = tonumber(body.max_wait_sec or 3) or 3
    if max_wait_sec < 0.5 then max_wait_sec = 0.5 end
    if max_wait_sec > 10 then max_wait_sec = 10 end
    local max_tries = math.max(3, math.floor((max_wait_sec / 0.1) + 0.5))

    poller = timer({
        interval = 0.1,
        callback = function()
            tries = tries + 1
            local ok2, stats = pcall(function()
                return cam:stats()
            end)
            if ok2 and type(stats) == "table" then
                last_stats = stats
                if stats.ready == true then
                    return finish_ok("ready", stats)
                end
            end
            if tries >= max_tries then
                local err = "timeout"
                if last_stats and last_stats.last_error then
                    err = tostring(last_stats.last_error)
                end
                return finish_err(400, "softcam not ready: " .. err, last_stats)
            end
        end,
    })
end

local function list_server_entries(filter_id)
    local list = (config and config.get_setting) and config.get_setting("servers") or nil
    if type(list) ~= "table" then
        return {}
    end
    if not filter_id then
        return list
    end
    local out = {}
    for _, entry in ipairs(list) do
        local entry_id = get_server_id(entry)
        if entry_id and tostring(entry_id) == tostring(filter_id) then
            table.insert(out, entry)
            break
        end
    end
    return out
end

local function server_status_list(server, client, request)
    local admin = require_admin(request)
    if not admin then
        return error_response(server, client, 403, "forbidden")
    end
    local filter_id = request and request.query and request.query.id or nil
    local list = list_server_entries(filter_id)
    if #list == 0 then
        return json_response(server, client, 200, { items = {} })
    end
    local results = {}
    local pending = #list
    local responded = false
    local function finish()
        if responded then return end
        responded = true
        json_response(server, client, 200, { items = results })
    end
    local function done(entry, ok, message)
        local id = get_server_id(entry)
        if id then
            table.insert(results, {
                id = id,
                ok = ok and true or false,
                message = message or "",
                ts = os.time(),
            })
        end
        pending = pending - 1
        if pending <= 0 then
            finish()
        end
    end
    for _, entry in ipairs(list) do
        if entry.enable == false or entry.enabled == false then
            done(entry, false, "disabled")
        else
            local cfg, cfg_err = normalize_server_host(entry)
            if not cfg then
                done(entry, false, cfg_err or "invalid server")
            else
                remote_health_check(cfg, function(ok, msg)
                    done(entry, ok, msg or (ok and "ok" or "error"))
                end)
            end
        end
    end
end

local function pull_server_streams(server, client, request)
    local admin = require_admin(request)
    if not admin then
        return error_response(server, client, 403, "forbidden")
    end
    local body = parse_json_body(request)
    if not body then
        return error_response(server, client, 400, "invalid json")
    end
    local entry, err = resolve_server_entry(body)
    if not entry then
        return error_response(server, client, 404, err or "server not found")
    end
    local cfg, cfg_err = normalize_server_host(entry)
    if not cfg then
        return error_response(server, client, 400, cfg_err or "invalid server")
    end
    local mode = tostring(body.mode or "merge")
    if mode ~= "merge" then
        return error_response(server, client, 400, "unsupported mode")
    end
    if not config or not config.import_astra then
        return error_response(server, client, 500, "config import unavailable")
    end

    remote_login(cfg, function(ok, cookie, login_err)
        if not ok then
            return error_response(server, client, 400, login_err or "login failed")
        end
        local paths = { "/api/v1/streams", "/api/streams" }
        local idx = 1
        local function fetch_next()
            local path = paths[idx]
            remote_fetch_json(cfg, path, cookie, "GET", nil, function(ok2, data, fetch_err, code)
                if not ok2 then
                    if code == 404 and idx < #paths then
                        idx = idx + 1
                        return fetch_next()
                    end
                    return error_response(server, client, 400, fetch_err or "fetch failed")
                end
                local payload = { make_stream = {} }
                if type(data) == "table" and data.make_stream then
                    payload.make_stream = data.make_stream
                elseif type(data) == "table" then
                    for _, row in ipairs(data) do
                        if type(row) == "table" and type(row.config) == "table" then
                            local cfgRow = row.config
                            cfgRow.enable = row.enabled
                            table.insert(payload.make_stream, cfgRow)
                        end
                    end
                end
                if #payload.make_stream == 0 then
                    return error_response(server, client, 400, "no streams received")
                end
                apply_config_change(server, client, request, {
                    comment = "pull streams",
                    apply = function()
                        return config.import_astra(payload, { mode = "merge", transaction = true })
                    end,
                    success_builder = function(summary, revision_id)
                        return { status = "ok", revision_id = revision_id, summary = summary }
                    end,
                })
            end)
        end
        fetch_next()
    end)
end

local function import_server_config(server, client, request)
    local admin = require_admin(request)
    if not admin then
        return error_response(server, client, 403, "forbidden")
    end
    local body = parse_json_body(request)
    if not body then
        return error_response(server, client, 400, "invalid json")
    end
    local entry, err = resolve_server_entry(body)
    if not entry then
        return error_response(server, client, 404, err or "server not found")
    end
    local cfg, cfg_err = normalize_server_host(entry)
    if not cfg then
        return error_response(server, client, 400, cfg_err or "invalid server")
    end
    local mode = tostring(body.mode or "merge")
    if mode ~= "merge" and mode ~= "replace" then
        return error_response(server, client, 400, "invalid mode")
    end
    if not config or not config.import_astra then
        return error_response(server, client, 500, "config import unavailable")
    end
    local include_users = body.include_users == true
    local include_settings = body.include_settings == true
    local include_streams = body.include_streams ~= false
    local include_adapters = body.include_adapters ~= false
    local include_softcam = body.include_softcam ~= false
    local include_splitters = body.include_splitters ~= false

    local query = string.format(
        "/api/v1/export?include_users=%s&include_settings=%s&include_streams=%s&include_adapters=%s&include_softcam=%s&include_splitters=%s",
        include_users and "1" or "0",
        include_settings and "1" or "0",
        include_streams and "1" or "0",
        include_adapters and "1" or "0",
        include_softcam and "1" or "0",
        include_splitters and "1" or "0"
    )
    local legacy_query = string.format(
        "/api/export?users=%s&settings=%s&streams=%s&adapters=%s&softcam=%s&splitters=%s",
        include_users and "1" or "0",
        include_settings and "1" or "0",
        include_streams and "1" or "0",
        include_adapters and "1" or "0",
        include_softcam and "1" or "0",
        include_splitters and "1" or "0"
    )

    remote_login(cfg, function(ok, cookie, login_err)
        if not ok then
            return error_response(server, client, 400, login_err or "login failed")
        end
        local paths = { query, legacy_query }
        local idx = 1
        local function fetch_next()
            local path = paths[idx]
            remote_fetch_json(cfg, path, cookie, "GET", nil, function(ok2, data, fetch_err, code)
                if not ok2 then
                    if code == 404 and idx < #paths then
                        idx = idx + 1
                        return fetch_next()
                    end
                    return error_response(server, client, 400, fetch_err or "fetch failed")
                end
                if type(data) ~= "table" or next(data) == nil then
                    return error_response(server, client, 400, "empty config")
                end
                apply_config_change(server, client, request, {
                    comment = "import remote config",
                    apply = function()
                        return config.import_astra(data, { mode = mode, transaction = true })
                    end,
                    success_builder = function(summary, revision_id)
                        return { status = "ok", revision_id = revision_id, summary = summary }
                    end,
                })
            end)
        end
        fetch_next()
    end)
end

local function login(server, client, request)
    local body = parse_json_body(request)
    if not body or not body.username or not body.password then
        return error_response(server, client, 400, "invalid json")
    end
    local ip = (request and request.addr) or "unknown"
    local limit = setting_number("rate_limit_login_per_min", 30)
    local window = setting_number("rate_limit_login_window_sec", 60)
    local ok, entry = rate_limit_check(rate_limits.login, ip, limit, window)
    rate_limits.counter = (rate_limits.counter or 0) + 1
    if (rate_limits.counter % 200) == 0 then
        prune_rate_limits(rate_limits.login, window)
    end
    if not ok then
        local retry_after = (entry and entry.window_start)
            and math.max(1, (entry.window_start + window) - os.time())
            or window
        return rate_limit_response(server, client, retry_after, "rate limited")
    end

    local user = config.verify_user(body.username, body.password)
    if not user then
        audit_event("login", request, {
            actor_username = tostring(body.username or ""),
            ok = false,
            message = "invalid credentials",
        })
        return error_response(server, client, 401, "invalid credentials")
    end

    local ttl = setting_number("auth_session_ttl_sec", 3600)
    if ttl < 300 then
        ttl = 300
    end
    local token = config.create_session(user.id, ttl)
    if config.touch_user_login then
        config.touch_user_login(user.id, request and request.addr)
    end
    audit_event("login", request, {
        actor_user_id = user.id,
        actor_username = user.username,
        ok = true,
    })
    local cookie = "astra_session=" .. token .. "; Path=/; HttpOnly; SameSite=Lax; Max-Age=" .. ttl
    server:send(client, {
        code = 200,
        headers = {
            "Content-Type: application/json",
            "Set-Cookie: " .. cookie,
            "Connection: close",
        },
        content = json.encode({
            token = token,
            user = { id = user.id, username = user.username, is_admin = user.is_admin },
        }),
    })
end

local function list_users(server, client, request)
    if not require_admin(request) then
        return error_response(server, client, 403, "forbidden")
    end
    local rows = config.list_users and config.list_users() or {}
    local out = {}
    for _, row in ipairs(rows) do
        table.insert(out, {
            id = row.id,
            username = row.username,
            is_admin = (tonumber(row.is_admin) or 0) == 1,
            enabled = row.enabled == nil or (tonumber(row.enabled) or 0) ~= 0,
            comment = row.comment or "",
            created_at = tonumber(row.created_at) or 0,
            last_login_at = tonumber(row.last_login_at) or 0,
            last_login_ip = row.last_login_ip or "",
        })
    end
    json_response(server, client, 200, out)
end

local function create_user(server, client, request)
    local admin = require_admin(request)
    if not admin then
        return error_response(server, client, 403, "forbidden")
    end
    local body = parse_json_body(request)
    if not body or not body.username or not body.password then
        return error_response(server, client, 400, "invalid json")
    end
    local username = tostring(body.username)
    local password = tostring(body.password)
    local is_admin = body.is_admin == true
    local enabled = body.enabled ~= false
    local comment = body.comment
    local ok, err = config.create_user and config.create_user(username, password, is_admin, enabled, comment)
    if not ok then
        local message = err or "user create failed"
        if not err and config.check_password_policy then
            local policy_ok, policy_err = config.check_password_policy(password, username)
            if not policy_ok and policy_err then
                message = policy_err
            end
        end
        audit_event("user_create", request, {
            actor_user_id = admin.id,
            actor_username = admin.username,
            target_username = username,
            ok = false,
            message = message,
        })
        return error_response(server, client, 400, message)
    end
    audit_event("user_create", request, {
        actor_user_id = admin.id,
        actor_username = admin.username,
        target_username = username,
        ok = true,
        meta = {
            is_admin = is_admin,
            enabled = enabled,
        },
    })
    json_response(server, client, 200, { status = "ok" })
end

local function update_user(server, client, request, username)
    local admin = require_admin(request)
    if not admin then
        return error_response(server, client, 403, "forbidden")
    end
    local body = parse_json_body(request)
    if not body then
        return error_response(server, client, 400, "invalid json")
    end
    local target = config.get_user_by_username and config.get_user_by_username(username)
    if not target then
        return error_response(server, client, 404, "user not found")
    end

    local new_admin = body.is_admin
    local new_enabled = body.enabled
    if (new_admin == false or new_enabled == false)
        and tonumber(target.is_admin) == 1 then
        local admins = config.count_admins and config.count_admins() or 1
        if admins <= 1 then
            audit_event("user_update", request, {
                actor_user_id = admin.id,
                actor_username = admin.username,
                target_username = username,
                ok = false,
                message = "cannot disable last admin",
            })
            return error_response(server, client, 400, "cannot disable last admin")
        end
    end

    if not (config.update_user and config.update_user(username, {
        is_admin = body.is_admin,
        enabled = body.enabled,
        comment = body.comment,
    })) then
        audit_event("user_update", request, {
            actor_user_id = admin.id,
            actor_username = admin.username,
            target_username = username,
            ok = false,
            message = "user update failed",
        })
        return error_response(server, client, 400, "user update failed")
    end

    if new_enabled == false and config.delete_sessions_for_user then
        config.delete_sessions_for_user(target.id)
    end
    audit_event("user_update", request, {
        actor_user_id = admin.id,
        actor_username = admin.username,
        target_username = username,
        ok = true,
        meta = {
            is_admin = body.is_admin,
            enabled = body.enabled,
            comment = body.comment,
        },
    })

    json_response(server, client, 200, { status = "ok" })
end

local function reset_user_password(server, client, request, username)
    local admin = require_admin(request)
    if not admin then
        return error_response(server, client, 403, "forbidden")
    end
    local body = parse_json_body(request)
    if not body or not body.password then
        return error_response(server, client, 400, "invalid json")
    end
    local ok, err = config.set_user_password and config.set_user_password(username, tostring(body.password))
    if not ok then
        local message = err or "user not found"
        local status = (message == "user not found") and 404 or 400
        audit_event("password_reset", request, {
            actor_user_id = admin.id,
            actor_username = admin.username,
            target_username = username,
            ok = false,
            message = message,
        })
        return error_response(server, client, status, message)
    end
    local target = config.get_user_by_username and config.get_user_by_username(username)
    if target and config.delete_sessions_for_user then
        config.delete_sessions_for_user(target.id)
    end
    audit_event("password_reset", request, {
        actor_user_id = admin.id,
        actor_username = admin.username,
        target_username = username,
        ok = true,
    })
    json_response(server, client, 200, { status = "ok" })
end

local function logout(server, client, request)
    local token = get_token(request)
    if token then
        local session = config.get_session(token)
        if session and not check_csrf(request, session) then
            return error_response(server, client, 403, "csrf required")
        end
        config.delete_session(token)
    end
    server:send(client, {
        code = 200,
        headers = {
            "Content-Type: application/json",
            "Set-Cookie: astra_session=; Path=/; HttpOnly; SameSite=Lax; Max-Age=0",
            "Connection: close",
        },
        content = json.encode({ status = "ok" }),
    })
end

local function import_config(server, client, request)
    local body = parse_json_body(request)
    if not body then
        return error_response(server, client, 400, "invalid json")
    end
    local mode = body.mode or "merge"
    local payload = body.config or body
    apply_config_change(server, client, request, {
        comment = "import config",
        validate = function()
            local errors, warnings = validate_config_payload(payload)
            if #errors > 0 then
                return false, "validation failed", errors, warnings
            end
            return true
        end,
        apply = function()
            local summary, err = config.import_astra(payload, { mode = mode, transaction = true })
            if not summary then
                error(err or "import failed")
            end
            if type(apply_softcam_settings) == "function" then
                apply_softcam_settings()
            end
            return summary
        end,
        success_builder = function(summary, revision_id)
            return { status = "ok", revision_id = revision_id, summary = summary }
        end,
    })
end

local function export_config(server, client, request)
    local admin = require_admin(request)
    if not admin then
        return error_response(server, client, 403, "forbidden")
    end

    local function query_bool(value, fallback)
        if value == nil then
            return fallback
        end
        if value == true or value == 1 or value == "1" or value == "true" then
            return true
        end
        if value == false or value == 0 or value == "0" or value == "false" then
            return false
        end
        return fallback
    end

    local query = request and request.query or {}
    local include_users = query_bool(query.include_users, true)
    local include_settings = query_bool(query.include_settings, true)
    local include_streams = query_bool(query.include_streams, true)
    local include_adapters = query_bool(query.include_adapters, true)
    local include_softcam = query_bool(query.include_softcam, true)
    local include_splitters = query_bool(query.include_splitters, true)
    local download = query_bool(query.download, false)

    local payload = config.export_astra and config.export_astra({
        include_users = include_users,
        include_settings = include_settings,
        include_streams = include_streams,
        include_adapters = include_adapters,
        include_softcam = include_softcam,
        include_splitters = include_splitters,
    }) or {}

    local headers = {
        "Content-Type: application/json",
        "Cache-Control: no-cache",
        "Connection: close",
    }
    if download then
        table.insert(headers, "Content-Disposition: attachment; filename=astra-export.json")
    end
    server:send(client, {
        code = 200,
        headers = headers,
        content = json.encode(payload),
    })
end

local function validate_config(server, client, request)
    local body = parse_json_body(request)
    local payload = nil
    if body then
        payload = body.config or body
    end
    if not payload or next(payload) == nil then
        payload = config.export_astra and config.export_astra({}) or {}
    end
    local errors, warnings = validate_config_payload(payload)
    local ok = (#errors == 0)
    json_response(server, client, 200, {
        ok = ok,
        errors = errors,
        warnings = warnings,
    })
end

local function list_config_revisions(server, client, request)
    local admin = require_admin(request)
    if not admin then
        return error_response(server, client, 403, "forbidden")
    end
    local query = request and request.query or {}
    local limit = tonumber(query.limit) or 50
    local rows = config.list_revisions(limit)
    json_response(server, client, 200, {
        active_revision_id = config.get_setting("config_active_revision_id"),
        lkg_revision_id = config.get_setting("config_lkg_revision_id"),
        revisions = rows,
    })
end

local function restore_config_revision(server, client, request, rev_id)
    local admin = require_admin(request)
    if not admin then
        return error_response(server, client, 403, "forbidden")
    end
    local row = config.get_revision(rev_id)
    if not row then
        return error_response(server, client, 404, "revision not found")
    end
    if not row.snapshot_path or row.snapshot_path == "" then
        return error_response(server, client, 400, "snapshot not available")
    end
    apply_config_change(server, client, request, {
        comment = "restore revision " .. tostring(row.id),
        apply = function()
            local summary, err = config.restore_snapshot(row.snapshot_path)
            if not summary then
                error(err or "restore failed")
            end
            return summary
        end,
        success_builder = function(summary, revision_id)
            return {
                status = "ok",
                revision_id = revision_id,
                restored_from = row.id,
                summary = summary,
            }
        end,
    })
end

local function delete_config_revision(server, client, request, rev_id)
    local admin = require_admin(request)
    if not admin then
        return error_response(server, client, 403, "forbidden")
    end
    if not config or not config.delete_revision then
        return error_response(server, client, 501, "config revisions are unavailable")
    end
    local row = config.delete_revision(rev_id)
    if not row then
        return error_response(server, client, 404, "revision not found")
    end
    local active_id = config.get_setting("config_active_revision_id")
    local lkg_id = config.get_setting("config_lkg_revision_id")
    if active_id and tonumber(active_id) == tonumber(rev_id) then
        config.set_setting("config_active_revision_id", 0)
    end
    if lkg_id and tonumber(lkg_id) == tonumber(rev_id) then
        config.set_setting("config_lkg_revision_id", 0)
    end
    json_response(server, client, 200, { status = "ok", deleted = tonumber(rev_id) })
end

local function delete_all_config_revisions(server, client, request)
    local admin = require_admin(request)
    if not admin then
        return error_response(server, client, 403, "forbidden")
    end
    if not config or not config.delete_all_revisions then
        return error_response(server, client, 501, "config revisions are unavailable")
    end
    local count = config.delete_all_revisions()
    config.set_setting("config_active_revision_id", 0)
    config.set_setting("config_lkg_revision_id", 0)
    json_response(server, client, 200, { status = "ok", deleted = tonumber(count) or 0 })
end

function api.handle_request(server, client, request)
    if not request then
        return nil
    end

    local method = request.method or "GET"
    local path = request.path or "/"

    if method == "OPTIONS" then
        return json_response(server, client, 200, { status = "ok" })
    end

    if path == "/api/v1/auth/login" and method == "POST" then
        return login(server, client, request)
    end

    if path == "/api/v1/auth/logout" and method == "POST" then
        return logout(server, client, request)
    end

    if (path == "/health" or path == "/api/v1/health") and method == "GET" then
        return health_summary(server, client)
    end

    local session = require_auth(request)
    if not session then
        return error_response(server, client, 401, "unauthorized")
    end
    if not check_csrf(request, session) then
        return error_response(server, client, 403, "csrf required")
    end

    if path == "/api/v1/streams" and method == "GET" then
        return list_streams(server, client)
    end
    if path == "/api/v1/streams" and method == "POST" then
        local body = parse_json_body(request)
        if not body or not body.id then
            return error_response(server, client, 400, "stream id required")
        end
        return upsert_stream(server, client, body.id, request)
    end
    if path == "/api/v1/streams/purge-disabled" and method == "POST" then
        return purge_disabled_streams(server, client, request)
    end
    if path == "/api/v1/streams/transcode-all" and method == "POST" then
        return transcode_all_streams(server, client, request)
    end

    local stream_id = path:match("^/api/v1/streams/([%w%-%_]+)$")
    if stream_id and method == "GET" then
        return get_stream(server, client, stream_id)
    end
    if stream_id and method == "PUT" then
        return upsert_stream(server, client, stream_id, request)
    end
    if stream_id and method == "DELETE" then
        return delete_stream(server, client, stream_id, request)
    end

    local stream_cam_stats = path:match("^/api/v1/streams/([%w%-%_]+)/cam%-stats$")
    if stream_cam_stats and method == "GET" then
        return get_stream_cam_stats(server, client, stream_cam_stats)
    end

    local stream_analyze_id = path:match("^/api/v1/streams/analyze/([%w%-%_]+)$")
    if stream_analyze_id and method == "GET" then
        return get_stream_analyze(server, client, request, stream_analyze_id)
    end
    if path == "/api/v1/streams/analyze" and method == "POST" then
        return start_stream_analyze(server, client, request)
    end
    local stream_analyze_stream = path:match("^/api/v1/streams/([%w%-%_]+)/analyze$")
    if stream_analyze_stream and method == "POST" then
        return start_stream_analyze(server, client, request, stream_analyze_stream)
    end
    if path == "/api/v1/mpts/scan" and method == "POST" then
        return mpts_scan(server, client, request)
    end

    local stream_preview_start = path:match("^/api/v1/streams/([%w%-%_]+)/preview/start$")
    if stream_preview_start and method == "POST" then
        return start_stream_preview(server, client, request, stream_preview_start)
    end
    local stream_preview_stop = path:match("^/api/v1/streams/([%w%-%_]+)/preview/stop$")
    if stream_preview_stop and method == "POST" then
        return stop_stream_preview(server, client, request, stream_preview_stop)
    end

    if path == "/api/v1/adapters" and method == "GET" then
        return list_adapters(server, client)
    end
    if path == "/api/v1/adapters" and method == "POST" then
        local body = parse_json_body(request)
        if not body or not body.id then
            return error_response(server, client, 400, "adapter id required")
        end
        return upsert_adapter(server, client, body.id, request)
    end

    local adapter_id = path:match("^/api/v1/adapters/([%w%-%_]+)$")
    if adapter_id and method == "GET" then
        return get_adapter(server, client, adapter_id)
    end
    if adapter_id and method == "PUT" then
        return upsert_adapter(server, client, adapter_id, request)
    end
    if adapter_id and method == "DELETE" then
        return delete_adapter(server, client, adapter_id, request)
    end

    if path == "/api/v1/splitters" and method == "GET" then
        return list_splitters(server, client)
    end
    if path == "/api/v1/splitters" and method == "POST" then
        local body = parse_json_body(request)
        if not body then
            return error_response(server, client, 400, "invalid json")
        end
        local id = body.id or generate_id("splitter")
        return upsert_splitter(server, client, id, request)
    end

    local splitter_id = path:match("^/api/v1/splitters/([%w%-%_]+)$")
    if splitter_id and method == "GET" then
        return get_splitter(server, client, splitter_id)
    end
    if splitter_id and method == "PUT" then
        return upsert_splitter(server, client, splitter_id, request)
    end
    if splitter_id and method == "DELETE" then
        return delete_splitter(server, client, splitter_id, request)
    end

    local splitter_links = path:match("^/api/v1/splitters/([%w%-%_]+)/links$")
    if splitter_links and method == "GET" then
        return list_splitter_links(server, client, splitter_links)
    end
    if splitter_links and method == "POST" then
        local body = parse_json_body(request)
        if not body then
            return error_response(server, client, 400, "invalid json")
        end
        local link_id = body.id or generate_id("link")
        return upsert_splitter_link(server, client, splitter_links, link_id, request)
    end

    local splitter_link_split, splitter_link_id = path:match("^/api/v1/splitters/([%w%-%_]+)/links/([%w%-%_]+)$")
    if splitter_link_split and splitter_link_id and method == "PUT" then
        return upsert_splitter_link(server, client, splitter_link_split, splitter_link_id, request)
    end
    if splitter_link_split and splitter_link_id and method == "DELETE" then
        return delete_splitter_link(server, client, splitter_link_split, splitter_link_id, request)
    end

    local splitter_allow = path:match("^/api/v1/splitters/([%w%-%_]+)/allow$")
    if splitter_allow and method == "GET" then
        return list_splitter_allow(server, client, splitter_allow)
    end
    if splitter_allow and method == "POST" then
        return add_splitter_allow(server, client, splitter_allow, request)
    end

    local splitter_allow_split, splitter_allow_rule = path:match("^/api/v1/splitters/([%w%-%_]+)/allow/([%w%-%_]+)$")
    if splitter_allow_split and splitter_allow_rule and method == "DELETE" then
        return delete_splitter_allow(server, client, splitter_allow_split, splitter_allow_rule, request)
    end

    local splitter_start = path:match("^/api/v1/splitters/([%w%-%_]+)/start$")
    if splitter_start and method == "POST" then
        return start_splitter(server, client, splitter_start)
    end
    local splitter_stop = path:match("^/api/v1/splitters/([%w%-%_]+)/stop$")
    if splitter_stop and method == "POST" then
        return stop_splitter(server, client, splitter_stop)
    end
    local splitter_restart = path:match("^/api/v1/splitters/([%w%-%_]+)/restart$")
    if splitter_restart and method == "POST" then
        return restart_splitter(server, client, splitter_restart)
    end
    local splitter_apply = path:match("^/api/v1/splitters/([%w%-%_]+)/apply%-config$")
    if splitter_apply and method == "POST" then
        return apply_splitter_config(server, client, splitter_apply)
    end

    local splitter_config = path:match("^/api/v1/splitters/([%w%-%_]+)/config$")
    if splitter_config and method == "GET" then
        return get_splitter_config(server, client, splitter_config)
    end

    if path == "/api/v1/splitter-status" and method == "GET" then
        return list_splitter_status(server, client)
    end
    local splitter_status_id = path:match("^/api/v1/splitter%-status/([%w%-%_]+)$")
    if splitter_status_id and method == "GET" then
        return get_splitter_status(server, client, splitter_status_id)
    end

    if path == "/api/v1/buffers/resources" and method == "GET" then
        return list_buffer_resources(server, client)
    end
    if path == "/api/v1/buffers/resources" and method == "POST" then
        local body = parse_json_body(request)
        if not body then
            return error_response(server, client, 400, "invalid json")
        end
        local id = tostring(body.id or "")
        if id == "" then
            return error_response(server, client, 400, "buffer id required")
        end
        return upsert_buffer_resource(server, client, id, body, request)
    end

    local buffer_resource_id = path:match("^/api/v1/buffers/resources/([%w%-%_]+)$")
    if buffer_resource_id and method == "GET" then
        return get_buffer_resource(server, client, buffer_resource_id)
    end
    if buffer_resource_id and method == "PUT" then
        local body = parse_json_body(request)
        if not body then
            return error_response(server, client, 400, "invalid json")
        end
        local body_id = tostring(body.id or "")
        if body_id == "" then
            return error_response(server, client, 400, "buffer id required")
        end
        if body_id ~= buffer_resource_id then
            return error_response(server, client, 400, "buffer id mismatch")
        end
        return upsert_buffer_resource(server, client, buffer_resource_id, body, request)
    end
    if buffer_resource_id and method == "DELETE" then
        return delete_buffer_resource(server, client, buffer_resource_id, request)
    end

    local buffer_inputs = path:match("^/api/v1/buffers/resources/([%w%-%_]+)/inputs$")
    if buffer_inputs and method == "GET" then
        return list_buffer_inputs(server, client, buffer_inputs)
    end
    if buffer_inputs and method == "POST" then
        local body = parse_json_body(request)
        if not body then
            return error_response(server, client, 400, "invalid json")
        end
        local input_id = body.id or generate_id("input")
        return upsert_buffer_input(server, client, buffer_inputs, input_id, body, request)
    end

    local buffer_input_resource, buffer_input_id =
        path:match("^/api/v1/buffers/resources/([%w%-%_]+)/inputs/([%w%-%_]+)$")
    if buffer_input_resource and buffer_input_id and method == "PUT" then
        local body = parse_json_body(request)
        if not body then
            return error_response(server, client, 400, "invalid json")
        end
        local body_id = body.id
        if body_id ~= nil and tostring(body_id) ~= buffer_input_id then
            return error_response(server, client, 400, "buffer input id mismatch")
        end
        return upsert_buffer_input(server, client, buffer_input_resource, buffer_input_id, body, request)
    end
    if buffer_input_resource and buffer_input_id and method == "DELETE" then
        return delete_buffer_input(server, client, buffer_input_resource, buffer_input_id, request)
    end

    if path == "/api/v1/buffers/allow" and method == "GET" then
        return list_buffer_allow(server, client)
    end
    if path == "/api/v1/buffers/allow" and method == "POST" then
        local body = parse_json_body(request)
        if not body then
            return error_response(server, client, 400, "invalid json")
        end
        return add_buffer_allow(server, client, body, request)
    end

    local buffer_allow_id = path:match("^/api/v1/buffers/allow/([%w%-%_]+)$")
    if buffer_allow_id and method == "DELETE" then
        return delete_buffer_allow(server, client, buffer_allow_id, request)
    end

    if path == "/api/v1/buffers/reload" and method == "POST" then
        return reload_buffers(server, client)
    end

    local buffer_restart = path:match("^/api/v1/buffers/([%w%-%_]+)/restart%-reader$")
    if buffer_restart and method == "POST" then
        return restart_buffer_reader(server, client, buffer_restart)
    end

    if path == "/api/v1/buffer-status" and method == "GET" then
        return list_buffer_status(server, client)
    end
    local buffer_status_id = path:match("^/api/v1/buffer%-status/([%w%-%_]+)$")
    if buffer_status_id and method == "GET" then
        return get_buffer_status(server, client, buffer_status_id)
    end

    if path == "/api/v1/adapter-status" and method == "GET" then
        return list_adapter_status(server, client)
    end
    if path == "/api/v1/dvb-adapters" and method == "GET" then
        return list_dvb_adapters(server, client)
    end
    if path == "/api/v1/dvb-scan" and method == "POST" then
        local admin = require_admin(request)
        if not admin then
            return error_response(server, client, 403, "forbidden")
        end
        return start_dvb_scan(server, client, request)
    end

    local dvb_scan_id = path:match("^/api/v1/dvb%-scan/([%w%-%_]+)$")
    if dvb_scan_id and method == "GET" then
        local admin = require_admin(request)
        if not admin then
            return error_response(server, client, 403, "forbidden")
        end
        return get_dvb_scan(server, client, request, dvb_scan_id)
    end

    local adapter_status_id = path:match("^/api/v1/adapter%-status/([%w%-%_]+)$")
    if adapter_status_id and method == "GET" then
        return get_adapter_status(server, client, adapter_status_id)
    end

    if path == "/api/v1/stream-status" and method == "GET" then
        return list_stream_status(server, client, request)
    end

    local status_id = path:match("^/api/v1/stream%-status/([%w%-%_]+)$")
    if status_id and method == "GET" then
        return get_stream_status(server, client, request, status_id)
    end

    if path == "/api/v1/users" and method == "GET" then
        return list_users(server, client, request)
    end
    if path == "/api/v1/users" and method == "POST" then
        return create_user(server, client, request)
    end
    local user_name = path:match("^/api/v1/users/([%w%-%_%.]+)$")
    if user_name and method == "PUT" then
        return update_user(server, client, request, user_name)
    end
    local reset_name = path:match("^/api/v1/users/([%w%-%_%.]+)/reset$")
    if reset_name and method == "POST" then
        return reset_user_password(server, client, request, reset_name)
    end

    if path == "/api/v1/sessions" and method == "GET" then
        return list_sessions(server, client, request)
    end

    if path == "/api/v1/auth-debug/session" and method == "GET" then
        return auth_debug_session(server, client, request)
    end

    local session_id = path:match("^/api/v1/sessions/([%w%-]+)$")
    if session_id and method == "DELETE" then
        return delete_session(server, client, session_id)
    end

    if path == "/api/v1/logs" and method == "GET" then
        return list_logs(server, client, request)
    end
    if path == "/api/v1/access-log" and method == "GET" then
        return list_access_log(server, client, request)
    end
    if path == "/api/v1/health/process" and method == "GET" then
        return health_process(server, client)
    end
    if path == "/api/v1/health/inputs" and method == "GET" then
        return health_inputs(server, client)
    end
    if path == "/api/v1/health/outputs" and method == "GET" then
        return health_outputs(server, client)
    end
    if path == "/api/v1/metrics" and method == "GET" then
        return list_metrics(server, client, request)
    end
    if path == "/api/v1/audit" and method == "GET" then
        return list_audit_events(server, client, request)
    end
    if path == "/api/v1/tools" and method == "GET" then
        return list_tools(server, client)
    end
    if path == "/api/v1/license" and method == "GET" then
        return license_info(server, client)
    end
    if path == "/api/v1/alerts" and method == "GET" then
        return list_alerts(server, client, request)
    end

    if path == "/api/v1/transcode-status" and method == "GET" then
        return list_transcode_status(server, client)
    end

    local transcode_id = path:match("^/api/v1/transcode%-status/([%w%-%_]+)$")
    if transcode_id and method == "GET" then
        return get_transcode_status(server, client, transcode_id)
    end

    local restart_id = path:match("^/api/v1/transcode/([%w%-%_]+)/restart$")
    if restart_id and method == "POST" then
        return restart_transcode(server, client, restart_id)
    end

    if path == "/api/v1/reload" and method == "POST" then
        return reload_service(server, client)
    end

    if path == "/api/v1/restart" and method == "POST" then
        return restart_service(server, client, request)
    end

    if path == "/api/v1/sharding/apply" and method == "POST" then
        return apply_sharding(server, client, request)
    end

    if path == "/api/v1/config/validate" and method == "POST" then
        return validate_config(server, client, request)
    end

    if path == "/api/v1/config/revisions" and method == "GET" then
        return list_config_revisions(server, client, request)
    end
    if path == "/api/v1/config/revisions" and method == "DELETE" then
        return delete_all_config_revisions(server, client, request)
    end
    local config_rev_id = path:match("^/api/v1/config/revisions/(%d+)/restore$")
    if config_rev_id and method == "POST" then
        return restore_config_revision(server, client, request, config_rev_id)
    end
    local config_rev_delete = path:match("^/api/v1/config/revisions/(%d+)$")
    if config_rev_delete and method == "DELETE" then
        return delete_config_revision(server, client, request, config_rev_delete)
    end

    if path == "/api/v1/settings" and method == "GET" then
        return get_settings(server, client)
    end
    if path == "/api/v1/settings" and method == "PUT" then
        return set_settings(server, client, request)
    end
    if path == "/api/v1/notifications/telegram/test" and method == "POST" then
        return telegram_test(server, client)
    end
    if path == "/api/v1/notifications/telegram/backup" and method == "POST" then
        return telegram_backup(server, client)
    end
    if path == "/api/v1/notifications/telegram/summary" and method == "POST" then
        return telegram_summary(server, client)
    end
    if path == "/api/v1/ai/logs" and method == "GET" then
        return ai_logs(server, client, request)
    end
    if path == "/api/v1/ai/metrics" and method == "GET" then
        return ai_metrics(server, client, request)
    end
    if path == "/api/v1/observability/system/snapshot" and method == "GET" then
        return system_metrics_snapshot(server, client, request)
    end
    if path == "/api/v1/observability/system/timeseries" and method == "GET" then
        return system_metrics_timeseries(server, client, request)
    end
    if path == "/api/v1/ai/summary" and method == "GET" then
        return ai_summary(server, client, request)
    end
    if path == "/api/v1/ai/jobs" and method == "GET" then
        return ai_jobs(server, client)
    end
    if path == "/api/v1/ai/plan" and method == "POST" then
        return ai_plan(server, client, request)
    end
    if path == "/api/v1/ai/apply" and method == "POST" then
        return ai_apply(server, client, request)
    end
    if path == "/api/v1/ai/telegram" and method == "POST" then
        return ai_telegram(server, client, request)
    end
    if path == "/api/v1/softcam/test" and method == "POST" then
        return softcam_test(server, client, request)
    end
    if path == "/api/v1/servers/status" and method == "GET" then
        return server_status_list(server, client, request)
    end
    if path == "/api/v1/servers/pull-streams" and method == "POST" then
        return pull_server_streams(server, client, request)
    end
    if path == "/api/v1/servers/import" and method == "POST" then
        return import_server_config(server, client, request)
    end
    if path == "/api/v1/servers/test" and method == "POST" then
        return server_test(server, client, request)
    end
    if path == "/api/v1/import" and method == "POST" then
        return import_config(server, client, request)
    end
    if path == "/api/v1/export" and method == "GET" then
        return export_config(server, client, request)
    end

    return error_response(server, client, 404, "not found")
end

function api.start(opts)
    opts = opts or {}
    local addr = opts.addr or "0.0.0.0"
    local port = opts.port or 8000
    local http_request_line_max = setting_number("http_request_line_max", 4096)
    local http_headers_max = setting_number("http_headers_max", 12288)
    local http_header_max = setting_number("http_header_max", 4096)
    local http_content_length_max = setting_number("http_content_length_max", 8 * 1024 * 1024)
    local http_max_clients = math.max(0, math.floor(setting_number("http_max_clients", 0) or 0))
    local http_max_clients_per_ip = math.max(0, math.floor(setting_number("http_max_clients_per_ip", 0) or 0))
    local http_accept_backoff_ms = math.max(10, math.min(5000, math.floor(setting_number("http_accept_backoff_ms", 100) or 100)))

    http_server({
        addr = addr,
        port = port,
        server_name = "Astra API",
        route = {
            { "/api/*", api.handle_request },
        },
        request_line_max = http_request_line_max,
        headers_max = http_headers_max,
        header_max = http_header_max,
        content_length_max = http_content_length_max,
        max_clients = http_max_clients,
        max_clients_per_ip = http_max_clients_per_ip,
        accept_backoff_ms = http_accept_backoff_ms,
    })

    log.info("[api] listening on " .. addr .. ":" .. port)
end
