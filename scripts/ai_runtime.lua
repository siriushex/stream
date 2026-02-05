-- AstralAI runtime scaffold (plan/apply orchestration)

ai_runtime = ai_runtime or {}

ai_runtime.config = ai_runtime.config or {}
ai_runtime.jobs = ai_runtime.jobs or {}
ai_runtime.next_job_id = ai_runtime.next_job_id or 1
ai_runtime.request_seq = ai_runtime.request_seq or 0
ai_runtime.last_summary = ai_runtime.last_summary or nil

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


local function build_json_schema()
    return {
        name = "astral_ai_plan",
        strict = true,
        schema = {
            type = "object",
            additionalProperties = false,
            -- Structured Outputs strict schemas require `required` to include every key in `properties`.
            required = { "summary", "ops", "warnings", "charts" },
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
                        required = { "op", "target", "field", "value", "note" },
                        properties = {
                            op = { type = "string" },
                            target = { type = "string" },
                            field = { type = { "string", "null" } },
                            value = { type = { "string", "number", "boolean", "null" } },
                            note = { type = { "string", "null" } },
                        },
                    },
                },
                charts = {
                    type = "array",
                    items = {
                        type = "object",
                        additionalProperties = false,
                        required = { "title", "type", "series" },
                        properties = {
                            title = { type = { "string", "null" } },
                            type = { type = { "string", "null" } },
                            series = {
                                type = "array",
                                items = {
                                    type = "object",
                                    additionalProperties = false,
                                    required = { "name", "values" },
                                    properties = {
                                        name = { type = { "string", "null" } },
                                        values = {
                                            type = "array",
                                            items = { type = "number" },
                                        },
                                    },
                                },
                            },
                        },
                    },
                },
            },
        },
    }
end

local function build_summary_schema()
    return {
        name = "astral_ai_summary",
        strict = true,
        schema = {
            type = "object",
            additionalProperties = false,
            -- Structured Outputs strict schemas require `required` to include every key in `properties`.
            required = { "summary", "top_issues", "suggestions", "charts" },
            properties = {
                summary = { type = "string" },
                top_issues = {
                    type = "array",
                    items = { type = "string" },
                },
                suggestions = {
                    type = "array",
                    items = { type = "string" },
                },
                charts = {
                    type = "array",
                    items = {
                        type = "object",
                        additionalProperties = false,
                        required = { "title", "type", "series" },
                        properties = {
                            title = { type = { "string", "null" } },
                            type = { type = { "string", "null" } },
                            series = {
                                type = "array",
                                items = {
                                    type = "object",
                                    additionalProperties = false,
                                    required = { "name", "values" },
                                    properties = {
                                        name = { type = { "string", "null" } },
                                        values = {
                                            type = "array",
                                            items = { type = "number" },
                                        },
                                    },
                                },
                            },
                        },
                    },
                },
            },
        },
    }
end

local function build_summary_prompt(payload)
    local parts = {}
    table.insert(parts, "You are AstralAI observability analyst.")
    table.insert(parts, "Return JSON only, strictly following the schema.")
    table.insert(parts, "Keep it short: summary + up to 3 issues + up to 3 suggestions.")
    if payload then
        table.insert(parts, "Observability snapshot:")
        table.insert(parts, json.encode(payload))
    end
    return table.concat(parts, "\n")
end

local build_prompt_text

local function derive_include_logs_from_prompt(prompt)
    local text = tostring(prompt or ""):lower()
    if text:find("log") or text:find("error") or text:find("warn") or text:find("alert") then
        return true
    end
    if text:find("down") or text:find("fail") or text:find("issue") or text:find("problem") then
        return true
    end
    return false
end

local function derive_cli_from_prompt(prompt, payload)
    local list = { "stream" }
    local set = { stream = true }
    local text = tostring(prompt or ""):lower()
    if text:find("dvb") or text:find("adapter") or text:find("scan") or text:find("tuner") or text:find("sat") then
        set.dvbls = true
    end
    if text:find("analy") or text:find("pid") or text:find("pmt") or text:find("pcr") or text:find("mpeg") or text:find("ts") then
        set.analyze = true
    end
    if text:find("signal") or text:find("lock") or text:find("femon") or text:find("snr") or text:find("ber") then
        set.femon = true
    end
    payload = payload or {}
    if payload.input_url then
        set.analyze = true
    end
    if payload.femon_url then
        set.femon = true
    end
    if set.dvbls then table.insert(list, "dvbls") end
    if set.analyze then table.insert(list, "analyze") end
    if set.femon then table.insert(list, "femon") end
    return list
end

local function derive_include_metrics_from_prompt(prompt)
    local text = tostring(prompt or ""):lower()
    if text:find("graph") or text:find("chart") or text:find("diagram") or text:find("plot") then
        return true
    end
    if text:find("metrics") or text:find("trend") or text:find("stats") or text:find("summary") then
        return true
    end
    return false
end

local function build_context_options(payload, prompt)
    payload = payload or {}
    local include_logs = payload.include_logs
    if include_logs == nil then
        if prompt then
            include_logs = derive_include_logs_from_prompt(prompt)
        else
            include_logs = false
        end
    else
        include_logs = include_logs == true
    end
    local include_cli = payload.include_cli
    if include_cli == nil then
        if prompt then
            include_cli = derive_cli_from_prompt(prompt, payload)
        else
            include_cli = { "stream" }
        end
    end
    local include_metrics = payload.include_metrics
    if include_metrics == nil and prompt then
        include_metrics = derive_include_metrics_from_prompt(prompt)
    end
    return {
        include_logs = include_logs,
        include_cli = include_cli,
        include_metrics = include_metrics == true,
        range = payload.range,
        range_sec = payload.range_sec,
        stream_id = payload.stream_id,
        input_url = payload.input_url,
        femon_url = payload.femon_url,
        log_limit = payload.log_limit,
        log_level = payload.log_level,
        attachments = payload.attachments,
    }
end

local function normalize_attachments(items)
    if type(items) ~= "table" then
        return nil
    end
    local max_items = setting_number("ai_attachments_max", 2)
    local max_bytes = setting_number("ai_attachments_max_bytes", 1500000)
    if max_items < 1 then max_items = 1 end
    if max_bytes < 128000 then max_bytes = 128000 end
    local out = {}
    for _, item in ipairs(items) do
        if #out >= max_items then
            break
        end
        if type(item) == "table" then
            local data_url = item.data_url or item.url
            local mime = item.mime
            local data = item.data
            if not data_url and mime and data then
                data_url = "data:" .. tostring(mime) .. ";base64," .. tostring(data)
            end
            if data_url and type(data_url) == "string" then
                if #data_url <= max_bytes then
                    table.insert(out, { data_url = data_url })
                else
                    return nil, "attachment too large"
                end
            end
        end
    end
    if #out == 0 then
        return nil
    end
    return out
end

local function build_openai_input(prompt, context, attachments)
    local text = build_prompt_text(prompt, context)
    if type(attachments) ~= "table" or #attachments == 0 then
        return text
    end
    local content = {
        { type = "input_text", text = text },
    }
    for _, item in ipairs(attachments) do
        if item and item.data_url then
            table.insert(content, {
                type = "input_image",
                image_url = item.data_url,
            })
        end
    end
    return {
        {
            role = "user",
            content = content,
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

local function get_op_limit()
    local limit = setting_number("ai_max_ops", 20)
    if not limit or limit < 1 then
        limit = 20
    end
    return math.floor(limit)
end

local function op_count(plan)
    if not plan or type(plan.ops) ~= "table" then
        return 0
    end
    return #plan.ops
end

local function count_ops(plan, names)
    if not plan or type(plan.ops) ~= "table" then
        return 0
    end
    local total = 0
    for _, item in ipairs(plan.ops) do
        local op = tostring(item.op or "")
        if names[op] then
            total = total + 1
        end
    end
    return total
end

local function sanitize_utf8(text)
    if type(text) ~= "string" then
        return text
    end
    local out = {}
    local i = 1
    local len = #text
    while i <= len do
        local c = text:byte(i)
        if c < 0x80 then
            table.insert(out, string.char(c))
            i = i + 1
        elseif c >= 0xC2 and c <= 0xDF then
            local c2 = text:byte(i + 1)
            if c2 and c2 >= 0x80 and c2 <= 0xBF then
                table.insert(out, text:sub(i, i + 1))
                i = i + 2
            else
                table.insert(out, "?")
                i = i + 1
            end
        elseif c >= 0xE0 and c <= 0xEF then
            local c2, c3 = text:byte(i + 1), text:byte(i + 2)
            if c2 and c3 and c2 >= 0x80 and c2 <= 0xBF and c3 >= 0x80 and c3 <= 0xBF then
                table.insert(out, text:sub(i, i + 2))
                i = i + 3
            else
                table.insert(out, "?")
                i = i + 1
            end
        elseif c >= 0xF0 and c <= 0xF4 then
            local c2, c3, c4 = text:byte(i + 1), text:byte(i + 2), text:byte(i + 3)
            if c2 and c3 and c4
                and c2 >= 0x80 and c2 <= 0xBF
                and c3 >= 0x80 and c3 <= 0xBF
                and c4 >= 0x80 and c4 <= 0xBF then
                table.insert(out, text:sub(i, i + 3))
                i = i + 4
            else
                table.insert(out, "?")
                i = i + 1
            end
        else
            table.insert(out, "?")
            i = i + 1
        end
    end
    return table.concat(out)
end

local function sanitize_value(value, depth)
    if depth and depth > 6 then
        return value
    end
    local t = type(value)
    if t == "string" then
        return sanitize_utf8(value)
    end
    if t == "table" then
        local out = {}
        for k, v in pairs(value) do
            local key = k
            if type(k) == "string" then
                key = sanitize_utf8(k)
            end
            out[key] = sanitize_value(v, (depth or 0) + 1)
        end
        return out
    end
    return value
end

build_prompt_text = function(prompt, context)
    local parts = {}
    table.insert(parts, "You are AstralAI. Return JSON only, strictly following the schema.")
    table.insert(parts, "Do not include markdown or extra text.")
    table.insert(parts, "Allowed ops: set_setting, set_stream_field, set_adapter_field, enable_stream, disable_stream, enable_adapter, disable_adapter, rename_stream, rename_adapter.")
    table.insert(parts, "Never use destructive ops (delete/remove/replace-all).")
    table.insert(parts, "If asked for charts, include a 'charts' array with line/bar series values.")
    if context then
        table.insert(parts, "Context:")
        table.insert(parts, json.encode(sanitize_value(context)))
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
    if plan.charts ~= nil then
        if type(plan.charts) ~= "table" then
            return nil, "plan.charts must be array"
        end
        for cidx, chart in ipairs(plan.charts) do
            if type(chart) ~= "table" then
                return nil, "plan.charts[" .. cidx .. "] must be object"
            end
            if chart.series == nil or type(chart.series) ~= "table" then
                return nil, "plan.charts[" .. cidx .. "].series required"
            end
            for sidx, series in ipairs(chart.series) do
                if type(series) ~= "table" or type(series.values) ~= "table" then
                    return nil, "plan.charts[" .. cidx .. "].series[" .. sidx .. "] values required"
                end
            end
        end
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

local function validate_summary_output(summary)
    if type(summary) ~= "table" then
        return nil, "summary must be object"
    end
    if type(summary.summary) ~= "string" then
        return nil, "summary.summary must be string"
    end
    if type(summary.top_issues) ~= "table" then
        return nil, "summary.top_issues must be array"
    end
    if type(summary.suggestions) ~= "table" then
        return nil, "summary.suggestions must be array"
    end
    if summary.charts ~= nil then
        if type(summary.charts) ~= "table" then
            return nil, "summary.charts must be array"
        end
        for cidx, chart in ipairs(summary.charts) do
            if type(chart) ~= "table" then
                return nil, "summary.charts[" .. cidx .. "] must be object"
            end
            if chart.series == nil or type(chart.series) ~= "table" then
                return nil, "summary.charts[" .. cidx .. "].series required"
            end
            for sidx, series in ipairs(chart.series) do
                if type(series) ~= "table" or type(series.values) ~= "table" then
                    return nil, "summary.charts[" .. cidx .. "].series[" .. sidx .. "] values required"
                end
            end
        end
    end
    for idx, item in ipairs(summary.top_issues) do
        if type(item) ~= "string" then
            return nil, "summary.top_issues[" .. idx .. "] must be string"
        end
    end
    for idx, item in ipairs(summary.suggestions) do
        if type(item) ~= "string" then
            return nil, "summary.suggestions[" .. idx .. "] must be string"
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

local function schedule_openai_plan(job, prompt, context_opts)
    if not ai_openai_client or not ai_openai_client.request_json_schema then
        job.status = "error"
        job.error = "openai client unavailable"
        return
    end
    if not ai_openai_client.has_api_key or not ai_openai_client.has_api_key() then
        job.status = "error"
        job.error = "api key missing"
        return
    end
    local context = ai_prompt and ai_prompt.build_context and ai_prompt.build_context({}) or {}
    if ai_context and ai_context.build_context then
        local extra = ai_context.build_context(build_context_options(context_opts, prompt))
        if extra then
            context.ai_context = extra
        end
    end
    local attachments, attach_err = normalize_attachments(context_opts and context_opts.attachments)
    if attach_err then
        job.status = "error"
        job.error = attach_err
        return
    end
    local input = build_openai_input(prompt, context, attachments)
    ai_runtime.request_seq = ai_runtime.request_seq + 1
    local req_id = ai_runtime.request_seq
    job.status = "running"
    job.request_id = req_id
    job.attempts = 0
    job.max_attempts = 3
    ai_openai_client.request_json_schema({
        input = input,
        json_schema = build_json_schema(),
        model = ai_runtime.config.model,
        max_output_tokens = ai_runtime.config.max_tokens or 512,
        temperature = ai_runtime.config.temperature or 0,
        store = ai_runtime.config.store == true,
        max_attempts = job.max_attempts,
        on_retry = function(attempt, delay, meta)
            job.status = "retry"
            job.error = meta and meta.code and ("http " .. tostring(meta.code)) or "retry"
            job.attempts = attempt
            job.next_try_ts = os.time() + delay
            job.rate_limits = meta and meta.rate_limits or nil
        end,
    }, function(ok, result, meta)
        job.rate_limits = meta and meta.rate_limits or nil
        job.attempts = meta and meta.attempts or job.attempts
        if not ok then
            job.status = "error"
            job.error = result or "request failed"
            job.error_detail = meta and meta.error_detail or nil
            job.model = meta and meta.model or job.model
            log_audit(job, false, job.error, { mode = "prompt", code = meta and meta.code })
            return
        end
        local plan = result
        local valid, plan_err = validate_plan_output(plan)
        if not valid then
            job.status = "error"
            job.error = plan_err or "plan validation failed"
            log_audit(job, false, job.error, { mode = "prompt" })
            return
        end
        local diff = nil
        local diff_error = nil
        if context_opts and context_opts.preview_diff then
            if ai_tools and ai_tools.apply_ops then
                local current, snap_err = ai_tools.config_snapshot()
                if current then
                    local next_config, apply_err = ai_tools.apply_ops(current, plan.ops or {})
                    if next_config then
                        local diff_out, diff_err = ai_tools.config_diff(current, next_config)
                        if diff_out then
                            diff = diff_out
                        else
                            diff_error = diff_err or "diff failed"
                        end
                    else
                        diff_error = apply_err or "apply ops failed"
                    end
                else
                    diff_error = snap_err or "snapshot failed"
                end
            else
                diff_error = "diff preview unavailable"
            end
        end
        job.status = "done"
        job.result = {
            plan = plan,
            summary = plan.summary or "",
            diff = diff,
            diff_error = diff_error,
        }
        log_audit(job, true, "plan ready", {
            mode = "prompt",
            plan_id = job.id,
            diff_summary = diff and diff.summary or nil,
            diff_error = diff_error,
        })
    end)
end

function ai_runtime.configure()
    local cfg = ai_runtime.config
    cfg.enabled = setting_bool("ai_enabled", false)
    cfg.model = setting_string("ai_model", "gpt-5.2")
    cfg.max_tokens = setting_number("ai_max_tokens", 512)
    cfg.temperature = setting_number("ai_temperature", 0.2)
    cfg.store = setting_bool("ai_store", false)
    cfg.allow_apply = setting_bool("ai_allow_apply", false)
    cfg.allowed_chat_ids = setting_list("ai_telegram_allowed_chat_ids")

    local has_key = false
    if ai_openai_client and ai_openai_client.has_api_key then
        has_key = ai_openai_client.has_api_key()
    end
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
    if not ai_openai_client or not ai_openai_client.request_json_schema then
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

function ai_runtime.get_last_summary()
    return ai_runtime.last_summary
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

local function build_help_plan()
    return {
        summary = "AstralAI help",
        help_lines = {
            "help — show this list",
            "refresh channel <id>",
            "show channel graphs (24h)",
            "show errors last 24h",
            "analyze stream <id>",
            "scan dvb adapter <n>",
            "list busy adapters",
            "check signal lock (femon)",
            "backup config now",
            "restart stream <id>",
        },
    }
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
        job.payload.proposed_config = validated.proposed_config
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
        local prompt_text = tostring(validated.prompt or "")
        local prompt_clean = prompt_text:lower():gsub("^%s+", ""):gsub("%s+$", "")
        if prompt_clean == "/help" or prompt_clean == "help" then
            job.status = "done"
            job.result = { plan = build_help_plan() }
            log_audit(job, true, "plan ready", { mode = "prompt", help = true })
            return job
        end
        log_audit(job, true, "plan requested", {
            mode = "prompt",
            prompt_len = #prompt_text,
            include_logs = payload and payload.include_logs or nil,
            include_cli = payload and payload.include_cli or nil,
        })
        if not ai_runtime.is_ready() then
            job.status = "error"
            job.error = "ai not configured"
            log_audit(job, false, job.error, { mode = "prompt" })
            return job
        end
        schedule_openai_plan(job, tostring(validated.prompt), payload)
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

function ai_runtime.validate_summary_output(summary)
    return validate_summary_output(summary)
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
    local plan = payload.plan
    if payload.plan_id and ai_runtime.jobs then
        local plan_job = ai_runtime.jobs[tostring(payload.plan_id)]
        if plan_job and plan_job.result and plan_job.result.plan then
            plan = plan_job.result.plan
        end
    end
    local mode = tostring(payload.mode or "merge")
    if mode ~= "merge" and mode ~= "replace" then
        job.status = "error"
        job.error = "invalid apply mode"
        log_audit(job, false, job.error)
        return nil, job.error
    end
    job.plan_id = payload.plan_id

    local current, snap_err = ai_tools.config_snapshot()
    if not current then
        job.status = "error"
        job.error = snap_err or "snapshot failed"
        log_audit(job, false, job.error)
        return nil, job.error
    end

    if type(proposed) ~= "table" then
        if plan and type(plan.ops) == "table" then
            if ai_tools and ai_tools.apply_ops then
                local next_config, apply_err = ai_tools.apply_ops(current, plan.ops)
                if not next_config then
                    job.status = "error"
                    job.error = apply_err or "apply ops failed"
                    log_audit(job, false, job.error)
                    return nil, job.error
                end
                proposed = next_config
                job.plan_id = payload.plan_id
                job.plan_ops = plan.ops
            else
                job.status = "error"
                job.error = "apply ops unavailable"
                log_audit(job, false, job.error)
                return nil, job.error
            end
        else
            job.status = "error"
            job.error = "proposed_config required"
            log_audit(job, false, job.error)
            return nil, job.error
        end
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

    local diff, diff_err = ai_tools.config_diff(current, proposed)
    if not diff then
        job.status = "error"
        job.error = diff_err or "diff failed"
        log_audit(job, false, job.error)
        return nil, job.error
    end

    local allow_destructive = payload.allow_destructive == true or payload.force == true
    local ops_total = op_count(plan)
    local max_ops = get_op_limit()
    if ops_total > max_ops and not allow_destructive then
        job.status = "error"
        job.error = "too many ops (" .. tostring(ops_total) .. "), allow_destructive required"
        log_audit(job, false, job.error, { mode = mode, op_count = ops_total })
        return nil, job.error
    end
    local destructive_ops = count_ops(plan, {
        disable_stream = true,
        disable_adapter = true,
    })
    if destructive_ops > 0 and not allow_destructive then
        job.status = "error"
        job.error = "disable ops require allow_destructive"
        log_audit(job, false, job.error, { mode = mode, op_count = ops_total, disable_ops = destructive_ops })
        return nil, job.error
    end
    if mode == "replace" and not allow_destructive then
        job.status = "error"
        job.error = "destructive replace requires allow_destructive"
        log_audit(job, false, job.error, { mode = mode, diff_summary = diff.summary })
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
        plan_id = payload.plan_id,
        plan_ops = job.plan_ops,
    })
    if config and config.add_audit_event then
        config.add_audit_event("ai_change", {
            actor_user_id = job.actor_user_id or 0,
            actor_username = job.actor_username or "",
            ip = job.actor_ip or "",
            ok = true,
            message = "ai apply",
            meta = {
                revision_id = revision_id,
                diff_summary = diff.summary,
                plan_id = payload.plan_id,
                plan_ops = job.plan_ops,
            },
        })
    end
    return job
end

function ai_runtime.handle_telegram(payload)
    if ai_telegram and ai_telegram.handle then
        return ai_telegram.handle(payload)
    end
    return nil, "ai telegram handler unavailable"
end

function ai_runtime.request_summary(payload, callback)
    if type(callback) ~= "function" then
        return nil, "callback required"
    end
    if not ai_runtime.is_ready() then
        return nil, "ai not configured"
    end
    if not ai_openai_client or not ai_openai_client.request_json_schema then
        return nil, "openai client unavailable"
    end
    local summary_payload = {}
    if payload and type(payload) == "table" then
        for key, value in pairs(payload) do
            summary_payload[key] = value
        end
    end
    if ai_context and ai_context.build_context then
        summary_payload.context = ai_context.build_context(build_context_options(payload, payload and payload.prompt))
    end
    local prompt = build_summary_prompt(summary_payload)
    ai_openai_client.request_json_schema({
        input = prompt,
        json_schema = build_summary_schema(),
        model = ai_runtime.config.model,
        max_output_tokens = ai_runtime.config.max_tokens or 512,
        temperature = ai_runtime.config.temperature or 0,
        store = ai_runtime.config.store == true,
    }, function(ok, result, meta)
        if not ok then
            callback(false, result or "request failed")
            return
        end
        local valid, err = validate_summary_output(result)
        if not valid then
            callback(false, err or "summary validation failed")
            return
        end
        ai_runtime.last_summary = {
            ts = os.time(),
            summary = result,
            rate_limits = meta and meta.rate_limits or nil,
        }
        callback(true, result)
    end)
    return true
end
