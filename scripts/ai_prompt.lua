-- AstralAI prompt/context builder scaffold

ai_prompt = ai_prompt or {}

local function safe_string(value, fallback)
    if value == nil then
        return fallback
    end
    local text = tostring(value)
    if text == "" then
        return fallback
    end
    return text
end

local function summarize_streams(streams, limit)
    local out = {}
    if type(streams) ~= "table" then
        return out
    end
    local max = tonumber(limit) or 200
    for i, row in ipairs(streams) do
        if i > max then
            break
        end
        local cfg = row.config or row
        local name = safe_string(cfg and cfg.name, "")
        local enabled = cfg and (cfg.enable ~= false)
        local input = cfg and cfg.input
        local output = cfg and cfg.output
        local input_count = type(input) == "table" and #input or (input and 1 or 0)
        local output_count = type(output) == "table" and #output or (output and 1 or 0)
        table.insert(out, {
            id = safe_string(cfg and cfg.id or row.id, ""),
            name = name,
            enabled = enabled,
            input_count = input_count,
            output_count = output_count,
            type = safe_string(cfg and cfg.type, ""),
        })
    end
    return out
end

local function summarize_adapters(adapters, limit)
    local out = {}
    if type(adapters) ~= "table" then
        return out
    end
    local max = tonumber(limit) or 200
    for i, row in ipairs(adapters) do
        if i > max then
            break
        end
        local cfg = row.config or row
        table.insert(out, {
            id = safe_string(cfg and cfg.id or row.id, ""),
            type = safe_string(cfg and cfg.type, ""),
            enabled = cfg and (cfg.enable ~= false),
        })
    end
    return out
end

function ai_prompt.build_context(opts)
    opts = opts or {}
    local context = {
        version = "v1",
        ts = os.time(),
    }
    if not config or not config.list_streams or not config.list_adapters then
        return context
    end
    local streams = config.list_streams() or {}
    local adapters = config.list_adapters() or {}
    local enabled_streams = 0
    for _, row in ipairs(streams) do
        local cfg = row.config or row
        if cfg and cfg.enable ~= false then
            enabled_streams = enabled_streams + 1
        end
    end
    context.summary = {
        streams_total = #streams,
        streams_enabled = enabled_streams,
        adapters_total = #adapters,
    }
    if opts.include_streams ~= false then
        context.streams = summarize_streams(streams, opts.stream_limit)
    end
    if opts.include_adapters ~= false then
        context.adapters = summarize_adapters(adapters, opts.adapter_limit)
    end
    return context
end
