-- Stream config export helper (atomic multi-target writer).
--
-- This is intended for background use (spawned from the main process) to keep
-- the primary config JSON and revision snapshots in sync without blocking the
-- main event loop on large configs.

dofile("scripts/base.lua")
dofile("scripts/config.lua")

local opt = {
    data_dir = "./data",
    db_path = nil,
    primary = nil,
    lkg = nil,
    snapshot = nil,
}

options_usage = [[
    --data-dir PATH     data directory (default: ./data)
    --db PATH           sqlite db path (default: data-dir/stream.db)
    --primary PATH      write primary config json (optional)
    --lkg PATH          write LKG snapshot json (optional)
    --snapshot PATH     write revision snapshot json (optional)
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
    ["--primary"] = function(idx)
        opt.primary = argv[idx + 1]
        return 1
    end,
    ["--lkg"] = function(idx)
        opt.lkg = argv[idx + 1]
        return 1
    end,
    ["--snapshot"] = function(idx)
        opt.snapshot = argv[idx + 1]
        return 1
    end,
}

local function want_outputs()
    return (opt.primary and opt.primary ~= "")
        or (opt.lkg and opt.lkg ~= "")
        or (opt.snapshot and opt.snapshot ~= "")
end

local function write_one(path, payload, encoded, label)
    if not path or path == "" then
        return true
    end
    local ok, err = config.export_astra_file(path, { payload = payload, encoded = encoded })
    if not ok then
        log.error("[export] write failed (" .. tostring(label) .. "): " .. tostring(err))
        return nil, err
    end
    return true
end

function main()
    if not want_outputs() then
        log.error("[export] no outputs specified")
        os.exit(2)
    end

    config.init({
        data_dir = opt.data_dir,
        db_path = opt.db_path,
    })
    if opt.primary and opt.primary ~= "" and config.set_primary_config_path then
        config.set_primary_config_path(opt.primary)
    end

    local payload, encoded = config.export_astra_encoded()

    local ok, err = write_one(opt.primary, payload, encoded, "primary")
    if not ok then
        log.error("[export] failed: " .. tostring(err))
        os.exit(1)
    end

    ok, err = write_one(opt.snapshot, payload, encoded, "snapshot")
    if not ok then
        log.error("[export] failed: " .. tostring(err))
        os.exit(1)
    end

    ok, err = write_one(opt.lkg, payload, encoded, "lkg")
    if not ok then
        log.error("[export] failed: " .. tostring(err))
        os.exit(1)
    end

    astra.exit()
end
