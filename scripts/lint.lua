-- Astra config lint helper

dofile("scripts/base.lua")
dofile("scripts/config.lua")

local opt = {
    config_path = nil,
    strict = false,
}

options_usage = [[
    --config PATH     config file path (.json or .lua)
    --strict          treat warnings as errors
]]

options = {
    ["--config"] = function(idx)
        opt.config_path = argv[idx + 1]
        return 1
    end,
    ["--strict"] = function(idx)
        opt.strict = true
        return 0
    end,
    ["*"] = function(idx)
        if not opt.config_path then
            opt.config_path = argv[idx]
            return 0
        end
        return -1
    end,
}

function main()
    if not opt.config_path or opt.config_path == "" then
        log.error("[lint] config path required")
        astra.abort()
    end

    local payload, err = config.read_payload(opt.config_path)
    if not payload then
        log.error("[lint] failed to read config: " .. tostring(err))
        astra.abort()
    end

    local ok, err = config.validate_payload(payload)
    if not ok then
        log.error("[lint] invalid config: " .. tostring(err))
        astra.abort()
    end

    local errors, warnings = config.lint_payload(payload)
    if warnings and #warnings > 0 then
        for _, msg in ipairs(warnings) do
            log.warning("[lint] " .. msg)
        end
    end
    if errors and #errors > 0 then
        for _, msg in ipairs(errors) do
            log.error("[lint] " .. msg)
        end
        astra.abort()
    end
    if opt.strict and warnings and #warnings > 0 then
        log.error("[lint] warnings present (strict mode)")
        astra.abort()
    end

    log.info("[lint] ok")
    astra.exit()
end
