-- AstralAI runtime scaffold (plan/apply orchestration)

ai_runtime = ai_runtime or {}

ai_runtime.config = ai_runtime.config or {}
ai_runtime.jobs = ai_runtime.jobs or {}
ai_runtime.next_job_id = ai_runtime.next_job_id or 1

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
    if not ai_runtime.is_ready() then
        job.status = "error"
        job.error = "ai not configured"
        return nil, job.error
    end
    if type(payload) ~= "table" then
        job.status = "error"
        job.error = "invalid payload"
        return nil, job.error
    end
    local ok, err = ai_tools.config_validate(payload)
    if not ok then
        job.status = "error"
        job.error = err or "validation failed"
        return nil, job.error
    end
    local current, snap_err = ai_tools.config_snapshot()
    if not current then
        job.status = "error"
        job.error = snap_err or "snapshot failed"
        return nil, job.error
    end
    local diff, diff_err = ai_tools.config_diff(current, payload)
    if not diff then
        job.status = "error"
        job.error = diff_err or "diff failed"
        return nil, job.error
    end
    job.status = "done"
    job.result = {
        validated = true,
        diff = diff,
        summary = diff.summary or {},
    }
    return job.result
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
