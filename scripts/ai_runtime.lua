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
                return
            end
            if response.code < 200 or response.code >= 300 then
                job.status = "error"
                job.error = "http " .. tostring(response.code)
                return
            end
            if not response.content then
                job.status = "error"
                job.error = "empty response"
                return
            end
            local decoded = json.decode(response.content)
            if type(decoded) ~= "table" then
                job.status = "error"
                job.error = "invalid json"
                return
            end
            local text, err = extract_output_json(decoded)
            if not text then
                job.status = "error"
                job.error = err or "missing output"
                return
            end
            local plan = json.decode(text)
            if type(plan) ~= "table" then
                job.status = "error"
                job.error = "invalid plan json"
                return
            end
            job.status = "done"
            job.result = {
                plan = plan,
                summary = plan.summary or "",
            }
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

function ai_runtime.plan(payload, ctx)
    local job = create_job("plan", {
        requested_by = ctx and ctx.user or "",
        source = ctx and ctx.source or "api",
    })
    if type(payload) ~= "table" then
        job.status = "error"
        job.error = "invalid payload"
        return job
    end
    if not ai_runtime.is_enabled() then
        job.status = "error"
        job.error = "ai disabled"
        return job
    end
    if payload.proposed_config ~= nil and type(payload.proposed_config) == "table" then
        local ok, err = ai_tools.config_validate(payload.proposed_config)
        if not ok then
            job.status = "error"
            job.error = err or "validation failed"
            return job
        end
        local current, snap_err = ai_tools.config_snapshot()
        if not current then
            job.status = "error"
            job.error = snap_err or "snapshot failed"
            return job
        end
        local diff, diff_err = ai_tools.config_diff(current, payload.proposed_config)
        if not diff then
            job.status = "error"
            job.error = diff_err or "diff failed"
            return job
        end
        job.status = "done"
        job.result = {
            validated = true,
            diff = diff,
            summary = diff.summary or {},
        }
        return job
    end
    if payload.prompt and payload.prompt ~= "" then
        if not ai_runtime.is_ready() then
            job.status = "error"
            job.error = "ai not configured"
            return job
        end
        schedule_openai_plan(job, tostring(payload.prompt))
        return job
    end
    job.status = "error"
    job.error = "prompt or proposed_config required"
    return job
end

function ai_runtime.apply(payload, ctx)
    local job = create_job("apply", {
        requested_by = ctx and ctx.user or "",
        source = ctx and ctx.source or "api",
    })
    job.status = "not_implemented"
    return nil, "ai apply not implemented"
end

function ai_runtime.handle_telegram(payload)
    return nil, "ai telegram not implemented"
end
