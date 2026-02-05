-- AstralAI runtime scaffold (plan/apply orchestration)

ai_runtime = ai_runtime or {}

ai_runtime.config = ai_runtime.config or {}
ai_runtime.jobs = ai_runtime.jobs or {}
ai_runtime.next_job_id = ai_runtime.next_job_id or 1
ai_runtime.request_seq = ai_runtime.request_seq or 0

local function setting_bool(key, fallback)
    if config and config.get_setting then
        local value = config.get_setting(key)
        if value == nil then
            return fallback
        end
        if value == true or value == 1 or value == "1" or value == "true" then
            return true
        end
        if value == false or value == 0 or value == "0" or value == "false" then
            return false
        end
    end
    return fallback
end

local function setting_number(key, fallback)
    if config and config.get_setting then
        local value = config.get_setting(key)
        if value == nil or value == "" then
            return fallback
        end
        local num = tonumber(value)
        if num ~= nil then
            return num
        end
    end
    return fallback
end

local function setting_string(key, fallback)
    if config and config.get_setting then
        local value = config.get_setting(key)
        if value ~= nil and value ~= "" then
            return tostring(value)
        end
    end
    return fallback
end

local function setting_list(key)
    if not config or not config.get_setting then
        return {}
    end
    local value = config.get_setting(key)
    if type(value) == "table" then
        return value
    end
    if value == nil or value == "" then
        return {}
    end
    local out = {}
    for item in tostring(value):gmatch("[^,%s]+") do
        table.insert(out, item)
    end
    return out
end

local function resolve_api_key()
    local key = os.getenv("ASTRAL_OPENAI_API_KEY")
    if key == nil or key == "" then
        key = os.getenv("OPENAI_API_KEY")
    end
    if key == nil or key == "" then
        return nil
    end
    return key
end

local function resolve_api_base()
    local base = os.getenv("ASTRAL_OPENAI_API_BASE")
    if base == nil or base == "" then
        base = "https://api.openai.com"
    end
    return base
end

local function build_json_schema()
    return {
        name = "astral_ai_plan",
        strict = true,
        schema = {
            type = "object",
            additionalProperties = false,
            required = { "summary", "ops", "warnings" },
            properties = {
                summary = { type = "string" },
                warnings = {
                    type = "array",
                    items = { type = "string" },
                },
                ops = {
                    type = "array",
                    items = {
                        type = "object",
                        additionalProperties = false,
                        required = { "op", "target" },
                        properties = {
                            op = { type = "string" },
                            target = { type = "string" },
                            field = { type = { "string", "null" } },
                            value = { type = { "string", "number", "boolean", "null" } },
                            note = { type = { "string", "null" } },
                        },
                    },
                },
            },
        },
    }
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

local function reload_runtime(force)
    local errors = {}
    if runtime and runtime.refresh_adapters then
        runtime.refresh_adapters(force)
    end
    if runtime and runtime.refresh then
        local ok, stream_errors = runtime.refresh(force)
        if ok == false then
            local detail = format_refresh_errors(stream_errors) or "stream refresh failed"
            table.insert(errors, detail)
        end
    end
    if splitter and splitter.refresh then
        splitter.refresh(force)
    end
    if buffer and buffer.refresh then
        buffer.refresh()
    end
    if #errors > 0 then
        return nil, table.concat(errors, "; ")
    end
    return true
end

local function build_prompt_text(prompt, context)
    local parts = {}
    table.insert(parts, "You are AstralAI. Return JSON only, strictly following the schema.")
    table.insert(parts, "Do not include markdown or extra text.")
    if context then
        table.insert(parts, "Context:")
        table.insert(parts, json.encode(context))
    end
    if prompt and prompt ~= "" then
        table.insert(parts, "Request:")
        table.insert(parts, prompt)
    end
    return table.concat(parts, "\n")
end

local function validate_plan_output(plan)
    if type(plan) ~= "table" then
        return nil, "plan must be object"
    end
    if type(plan.summary) ~= "string" then
        return nil, "plan.summary must be string"
    end
    if type(plan.ops) ~= "table" then
        return nil, "plan.ops must be array"
    end
    if type(plan.warnings) ~= "table" then
        return nil, "plan.warnings must be array"
    end
    for idx, item in ipairs(plan.ops) do
        if type(item) ~= "table" then
            return nil, "plan.ops[" .. idx .. "] must be object"
        end
        if type(item.op) ~= "string" or item.op == "" then
            return nil, "plan.ops[" .. idx .. "].op required"
        end
        if type(item.target) ~= "string" or item.target == "" then
            return nil, "plan.ops[" .. idx .. "].target required"
        end
        if item.field ~= nil and type(item.field) ~= "string" then
            return nil, "plan.ops[" .. idx .. "].field must be string or null"
        end
        if item.note ~= nil and type(item.note) ~= "string" then
            return nil, "plan.ops[" .. idx .. "].note must be string or null"
        end
        if item.value ~= nil then
            local t = type(item.value)
            if t ~= "string" and t ~= "number" and t ~= "boolean" then
                return nil, "plan.ops[" .. idx .. "].value must be primitive"
            end
        end
    end
    for idx, warning in ipairs(plan.warnings) do
        if type(warning) ~= "string" then
            return nil, "plan.warnings[" .. idx .. "] must be string"
        end
    end
    return true
end

local function validate_plan_payload(payload)
    if type(payload) ~= "table" then
        return nil, "invalid payload"
    end
    local prompt = payload.prompt
    local proposed = payload.proposed_config
    if prompt ~= nil and type(prompt) ~= "string" then
        return nil, "prompt must be string"
    end
    if proposed ~= nil and type(proposed) ~= "table" then
        return nil, "proposed_config must be object"
    end
    if prompt ~= nil and prompt:match("^%s*$") then
        prompt = nil
    end
    if prompt and proposed then
        return nil, "provide prompt or proposed_config"
    end
    if prompt then
        return { mode = "prompt", prompt = prompt }
    end
    if proposed then
        return { mode = "diff", proposed_config = proposed }
    end
    return nil, "prompt or proposed_config required"
end

local function extract_output_json(response)
    if type(response) ~= "table" then
        return nil, "invalid response"
    end
    if type(response.output) ~= "table" then
        return nil, "missing output"
    end
    for _, item in ipairs(response.output) do
        if item.type == "message" and type(item.content) == "table" then
            for _, chunk in ipairs(item.content) do
                if chunk.type == "output_text" and chunk.text and chunk.text ~= "" then
                    return chunk.text
                end
            end
        end
    end
    return nil, "output text missing"
end

local function normalize_headers(headers)
    if type(headers) ~= "table" then
        return {}
    end
    local out = {}
    for k, v in pairs(headers) do
        if type(k) == "string" then
            out[string.lower(k)] = v
        end
    end
    return out
end

local function parse_rate_limits(headers)
    if type(headers) ~= "table" then
        return {}
    end
    local out = {}
    local keys = {
        "x-ratelimit-limit-requests",
        "x-ratelimit-remaining-requests",
        "x-ratelimit-reset-requests",
        "x-ratelimit-limit-tokens",
        "x-ratelimit-remaining-tokens",
        "x-ratelimit-reset-tokens",
    }
    for _, key in ipairs(keys) do
        if headers[key] then
            out[key] = headers[key]
        end
    end
    return out
end

local function should_retry(code)
    if not code then
        return false
    end
    if code == 429 or code == 408 or code == 409 then
        return true
    end
    if code >= 500 and code < 600 then
        return true
    end
    return false
end

local function schedule_retry(job, prompt, delay_sec)
    job.next_try_ts = os.time() + delay_sec
    timer({
        interval = delay_sec,
        callback = function(self)
            self:close()
            schedule_openai_plan(job, prompt)
        end,
    })
end

local function schedule_openai_plan(job, prompt)
    if not http_request then
        job.status = "error"
        job.error = "http_request unavailable"
        return
    end
    local api_key = resolve_api_key()
    if not api_key then
        job.status = "error"
        job.error = "api key missing"
        return
    end
    local base = resolve_api_base()
    local parsed = parse_url(base)
    if not parsed or not parsed.host then
        job.status = "error"
        job.error = "invalid api base"
        return
    end
    local path = parsed.path or "/"
    if path:sub(-1) == "/" then
        path = path:sub(1, -2)
    end
    path = path .. "/v1/responses"
    local context = ai_prompt and ai_prompt.build_context and ai_prompt.build_context({}) or {}
    local payload = {
        model = ai_runtime.config.model,
        input = build_prompt_text(prompt, context),
        max_output_tokens = ai_runtime.config.max_tokens or 512,
        temperature = ai_runtime.config.temperature or 0,
        store = ai_runtime.config.store == true,
        parallel_tool_calls = false,
        text = {
            format = {
                type = "json_schema",
                json_schema = build_json_schema(),
            },
        },
    }

    local body = json.encode(payload)
    ai_runtime.request_seq = ai_runtime.request_seq + 1
    local req_id = ai_runtime.request_seq
    job.status = "running"
    job.request_id = req_id
    job.attempts = (job.attempts or 0) + 1
    job.max_attempts = job.max_attempts or 3
    http_request({
        host = parsed.host,
        port = parsed.port or 443,
        path = path,
        method = "POST",
        timeout = 30,
        tls = (parsed.format == "https"),
        headers = {
            "Content-Type: application/json",
            "Authorization: Bearer " .. api_key,
            "Connection: close",
        },
        content = body,
        callback = function(_, response)
            if not response or not response.code then
                job.status = "error"
                job.error = "no response"
                log_audit(job, false, job.error, { mode = "prompt" })
                return
            end
            local headers = normalize_headers(response.headers)
            job.rate_limits = parse_rate_limits(headers)
            if response.code < 200 or response.code >= 300 then
                if should_retry(response.code) and job.attempts < job.max_attempts then
                    job.status = "retry"
                    job.error = "http " .. tostring(response.code)
                    schedule_retry(job, prompt, (job.attempts == 1) and 1 or (job.attempts == 2) and 5 or 15)
                    return
                end
                job.status = "error"
                job.error = "http " .. tostring(response.code)
                log_audit(job, false, job.error, { mode = "prompt", code = response.code })
                return
            end
            if not response.content then
                job.status = "error"
                job.error = "empty response"
                log_audit(job, false, job.error, { mode = "prompt" })
                return
            end
            local decoded = json.decode(response.content)
            if type(decoded) ~= "table" then
                job.status = "error"
                job.error = "invalid json"
                log_audit(job, false, job.error, { mode = "prompt" })
                return
            end
            local text, err = extract_output_json(decoded)
            if not text then
                job.status = "error"
                job.error = err or "missing output"
                log_audit(job, false, job.error, { mode = "prompt" })
                return
            end
            local plan = json.decode(text)
            if type(plan) ~= "table" then
                job.status = "error"
                job.error = "invalid plan json"
                log_audit(job, false, job.error, { mode = "prompt" })
                return
            end
            local ok, plan_err = validate_plan_output(plan)
            if not ok then
                job.status = "error"
                job.error = plan_err or "plan validation failed"
                log_audit(job, false, job.error, { mode = "prompt" })
                return
            end
            job.status = "done"
            job.result = {
                plan = plan,
                summary = plan.summary or "",
            }
            log_audit(job, true, "plan ready", { mode = "prompt" })
        end,
    })
end

function ai_runtime.configure()
    local cfg = ai_runtime.config
    cfg.enabled = setting_bool("ai_enabled", false)
    cfg.model = setting_string("ai_model", "")
    cfg.max_tokens = setting_number("ai_max_tokens", 512)
    cfg.temperature = setting_number("ai_temperature", 0.2)
    cfg.store = setting_bool("ai_store", false)
    cfg.allow_apply = setting_bool("ai_allow_apply", false)
    cfg.allowed_chat_ids = setting_list("ai_telegram_allowed_chat_ids")

    local has_key = resolve_api_key() ~= nil
    cfg.has_api_key = has_key

    if cfg.enabled then
        log.info(string.format(
            "[ai] enabled model=%s store=%s allow_apply=%s api_key=%s",
            cfg.model ~= "" and cfg.model or "unset",
            cfg.store and "true" or "false",
            cfg.allow_apply and "true" or "false",
            has_key and "set" or "missing"
        ))
    else
        log.info("[ai] disabled")
    end
end

function ai_runtime.is_enabled()
    return ai_runtime.config.enabled == true
end

function ai_runtime.is_ready()
    if not ai_runtime.is_enabled() then
        return false
    end
    if not ai_runtime.config.model or ai_runtime.config.model == "" then
        return false
    end
    if not ai_runtime.config.has_api_key then
        return false
    end
    return true
end

function ai_runtime.status()
    local cfg = ai_runtime.config
    return {
        enabled = cfg.enabled == true,
        ready = ai_runtime.is_ready(),
        model = cfg.model or "",
        store = cfg.store == true,
        allow_apply = cfg.allow_apply == true,
        api_key_set = cfg.has_api_key == true,
    }
end

function ai_runtime.list_jobs()
    local out = {}
    for _, job in pairs(ai_runtime.jobs) do
        table.insert(out, job)
    end
    table.sort(out, function(a, b)
        return (a.created_ts or 0) > (b.created_ts or 0)
    end)
    return out
end

local function create_job(kind, payload)
    local id = tostring(ai_runtime.next_job_id)
    ai_runtime.next_job_id = ai_runtime.next_job_id + 1
    local job = {
        id = id,
        kind = kind,
        status = "queued",
        created_ts = os.time(),
        payload = payload,
    }
    ai_runtime.jobs[id] = job
    return job
end

local function log_audit(job, ok, message, meta)
    if not config or not config.add_audit_event then
        return
    end
    config.add_audit_event("ai_" .. tostring(job.kind or "job"), {
        actor_user_id = job.actor_user_id or 0,
        actor_username = job.actor_username or "",
        ip = job.actor_ip or "",
        ok = ok ~= false,
        message = message or "",
        meta = meta,
    })
end

function ai_runtime.plan(payload, ctx)
    local job = create_job("plan", {
        requested_by = ctx and ctx.user or "",
        source = ctx and ctx.source or "api",
    })
    job.actor_user_id = ctx and ctx.user_id or 0
    job.actor_username = ctx and ctx.user or ""
    job.actor_ip = ctx and ctx.ip or ""
    local validated, payload_err = validate_plan_payload(payload)
    if not validated then
        job.status = "error"
        job.error = payload_err or "invalid payload"
        log_audit(job, false, job.error)
        return job
    end
    if not ai_runtime.is_enabled() then
        job.status = "error"
        job.error = "ai disabled"
        log_audit(job, false, job.error)
        return job
    end
    if validated.mode == "diff" then
        log_audit(job, true, "plan requested", { mode = "diff" })
        local ok, err = ai_tools.config_validate(validated.proposed_config)
        if not ok then
            job.status = "error"
            job.error = err or "validation failed"
            log_audit(job, false, job.error, { mode = "diff" })
            return job
        end
        local current, snap_err = ai_tools.config_snapshot()
        if not current then
            job.status = "error"
            job.error = snap_err or "snapshot failed"
            log_audit(job, false, job.error, { mode = "diff" })
            return job
        end
        local diff, diff_err = ai_tools.config_diff(current, validated.proposed_config)
        if not diff then
            job.status = "error"
            job.error = diff_err or "diff failed"
            log_audit(job, false, job.error, { mode = "diff" })
            return job
        end
        job.status = "done"
        job.result = {
            validated = true,
            diff = diff,
            summary = diff.summary or {},
        }
        log_audit(job, true, "plan ready", { mode = "diff", summary = diff.summary })
        return job
    end
    if validated.mode == "prompt" then
        log_audit(job, true, "plan requested", { mode = "prompt", prompt_len = #(tostring(validated.prompt)) })
        if not ai_runtime.is_ready() then
            job.status = "error"
            job.error = "ai not configured"
            log_audit(job, false, job.error, { mode = "prompt" })
            return job
        end
        schedule_openai_plan(job, tostring(validated.prompt))
        return job
    end
    job.status = "error"
    job.error = "prompt or proposed_config required"
    log_audit(job, false, job.error)
    return job
end

function ai_runtime.validate_plan_output(plan)
    return validate_plan_output(plan)
end

function ai_runtime.apply(payload, ctx)
    local job = create_job("apply", {
        requested_by = ctx and ctx.user or "",
        source = ctx and ctx.source or "api",
    })
    job.actor_user_id = ctx and ctx.user_id or 0
    job.actor_username = ctx and ctx.user or ""
    job.actor_ip = ctx and ctx.ip or ""

    if not ai_runtime.is_enabled() then
        job.status = "error"
        job.error = "ai disabled"
        log_audit(job, false, job.error)
        return nil, job.error
    end
    if not (ai_runtime.config and ai_runtime.config.allow_apply) then
        job.status = "error"
        job.error = "ai apply disabled"
        log_audit(job, false, job.error)
        return nil, job.error
    end
    if type(payload) ~= "table" then
        job.status = "error"
        job.error = "invalid payload"
        log_audit(job, false, job.error)
        return nil, job.error
    end
    local proposed = payload.proposed_config or payload.config
    if type(proposed) ~= "table" then
        job.status = "error"
        job.error = "proposed_config required"
        log_audit(job, false, job.error)
        return nil, job.error
    end
    local mode = tostring(payload.mode or "merge")
    if mode ~= "merge" and mode ~= "replace" then
        job.status = "error"
        job.error = "invalid apply mode"
        log_audit(job, false, job.error)
        return nil, job.error
    end

    local ok, err = ai_tools.config_validate(proposed)
    if not ok then
        job.status = "error"
        job.error = err or "validation failed"
        log_audit(job, false, job.error)
        return nil, job.error
    end
    local lint_warnings = {}
    if config and config.lint_payload then
        local lint_errors
        lint_errors, lint_warnings = config.lint_payload(proposed)
        if lint_errors and #lint_errors > 0 then
            job.status = "error"
            job.error = lint_errors[1] or "lint failed"
            log_audit(job, false, job.error)
            return nil, job.error
        end
    end

    local current, snap_err = ai_tools.config_snapshot()
    if not current then
        job.status = "error"
        job.error = snap_err or "snapshot failed"
        log_audit(job, false, job.error)
        return nil, job.error
    end
    local diff, diff_err = ai_tools.config_diff(current, proposed)
    if not diff then
        job.status = "error"
        job.error = diff_err or "diff failed"
        log_audit(job, false, job.error)
        return nil, job.error
    end

    local revision_id = 0
    if config and config.create_revision then
        revision_id = config.create_revision({
            created_by = job.actor_username or "",
            comment = tostring(payload.comment or "ai apply"),
            status = "PENDING",
        })
    end

    local lkg_path = nil
    if config and config.ensure_lkg_snapshot then
        local ok_lkg, err_lkg = config.ensure_lkg_snapshot()
        if ok_lkg then
            lkg_path = ok_lkg
        else
            if revision_id > 0 then
                config.update_revision(revision_id, {
                    status = "BAD",
                    error_text = "backup failed: " .. tostring(err_lkg),
                })
            end
            job.status = "error"
            job.error = "backup failed: " .. tostring(err_lkg)
            log_audit(job, false, job.error)
            return nil, job.error
        end
    end

    local summary, apply_err = ai_tools.config_apply(proposed, {
        mode = mode,
        transaction = true,
    })
    if not summary then
        if revision_id > 0 then
            config.update_revision(revision_id, {
                status = "BAD",
                error_text = tostring(apply_err or "apply failed"),
            })
        end
        job.status = "error"
        job.error = apply_err or "apply failed"
        log_audit(job, false, job.error)
        return nil, job.error
    end

    local snapshot_path = nil
    if revision_id > 0 and config and config.build_snapshot_path then
        snapshot_path = config.build_snapshot_path(revision_id)
        local ok_snap, snap_err = config.export_astra_file(snapshot_path)
        if not ok_snap then
            config.update_revision(revision_id, {
                status = "BAD",
                error_text = "snapshot failed: " .. tostring(snap_err),
                snapshot_path = snapshot_path,
            })
            if lkg_path then
                config.restore_snapshot(lkg_path)
                reload_runtime(true)
            end
            job.status = "error"
            job.error = "snapshot failed: " .. tostring(snap_err)
            log_audit(job, false, job.error)
            return nil, job.error
        end
    end

    local reload_ok, reload_err = reload_runtime(true)
    if not reload_ok then
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
            reload_runtime(true)
        end
        job.status = "error"
        job.error = reload_err or "reload failed"
        log_audit(job, false, job.error)
        return nil, job.error
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

    job.status = "done"
    job.result = {
        revision_id = revision_id,
        diff = diff,
        summary = summary,
        warnings = lint_warnings or {},
    }
    log_audit(job, true, "apply ok", {
        revision_id = revision_id,
        diff_summary = diff.summary,
    })
    return job
end

function ai_runtime.handle_telegram(payload)
    return nil, "ai telegram not implemented"
end
