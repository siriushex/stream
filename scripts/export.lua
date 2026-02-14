-- Stream config export helper

dofile("scripts/base.lua")
dofile("scripts/config.lua")

local opt = {
    data_dir = "./data",
    db_path = nil,
    output = nil,
    include_users = true,
    include_settings = true,
    include_streams = true,
    include_adapters = true,
    include_softcam = true,
    include_splitters = true,
}

options_usage = [[
    --data-dir PATH     data directory (default: ./data)
    --db PATH           sqlite db path (default: data-dir/astra.db)
    --output PATH       write export to file (default: stdout)
    --no-users          exclude users from export
    --no-settings       exclude settings from export
    --no-streams        exclude streams from export
    --no-adapters       exclude adapters from export
    --no-softcam        exclude softcam list from export
    --no-splitters      exclude splitters from export
]]

options = {
    ["--data-dir"] = function(idx)
        opt.data_dir = argv[idx + 1]
        return 1
    end,
    ["--db"] = function(idx)
        opt.db_path = argv[idx + 1]
        return 1
    end,
    ["--output"] = function(idx)
        opt.output = argv[idx + 1]
        return 1
    end,
    ["--no-users"] = function(idx)
        opt.include_users = false
        return 0
    end,
    ["--no-settings"] = function(idx)
        opt.include_settings = false
        return 0
    end,
    ["--no-streams"] = function(idx)
        opt.include_streams = false
        return 0
    end,
    ["--no-adapters"] = function(idx)
        opt.include_adapters = false
        return 0
    end,
    ["--no-softcam"] = function(idx)
        opt.include_softcam = false
        return 0
    end,
    ["--no-splitters"] = function(idx)
        opt.include_splitters = false
        return 0
    end,
}

function main()
    if not opt.output then
        log.set({ stdout = false })
    end

    config.init({
        data_dir = opt.data_dir,
        db_path = opt.db_path,
    })

    local payload = config.export_astra({
        include_users = opt.include_users,
        include_settings = opt.include_settings,
        include_streams = opt.include_streams,
        include_adapters = opt.include_adapters,
        include_softcam = opt.include_softcam,
        include_splitters = opt.include_splitters,
    })

    if opt.output then
        local file, err = io.open(opt.output, "w")
        if not file then
            log.error("[export] failed to open output: " .. tostring(err))
            astra.abort()
        end
        if json and type(json.encode_pretty) == "function" then
            file:write(json.encode_pretty(payload))
        else
            file:write(json.encode(payload))
        end
        file:close()
        log.info("[export] wrote: " .. opt.output)
    else
        if json and type(json.encode_pretty) == "function" then
            io.write(json.encode_pretty(payload))
        else
            print(json.encode(payload))
        end
    end

    astra.exit()
end
