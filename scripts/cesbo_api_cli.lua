-- Cesbo Stream API CLI demo (Stream project)
--
-- Пример использования CesboApiClient:
-- 1) чтение system-status
-- 2) restart-stream
-- 3) sessions + close-session
--
-- Usage:
--   stream scripts/cesbo_api_cli.lua --base http://127.0.0.1:8000 --login admin --password admin --status
--   stream scripts/cesbo_api_cli.lua --base http://127.0.0.1:8000 --login admin --password admin --restart-stream a001
--   stream scripts/cesbo_api_cli.lua --base http://127.0.0.1:8000 --login admin --password admin --sessions
--   stream scripts/cesbo_api_cli.lua --base http://127.0.0.1:8000 --login admin --password admin --close-session 123

dofile("scripts/base.lua")
dofile("scripts/cesbo_api_client.lua")

log.set({ color = true })

options_usage = [[
    --base URL           base url, example: http://server:8000
    --login USER        basic auth login
    --password PASS     basic auth password

    --status [t]        GET /api/system-status?t=... (default t=1)
    --restart           POST /control/ {"cmd":"restart"}
    --restart-stream ID POST /control/ {"cmd":"restart-stream","id":ID}
    --sessions          POST /control/ {"cmd":"sessions"}
    --close-session ID  POST /control/ {"cmd":"close-session","id":ID}
]]

local cli = {
    base = "",
    login = "",
    password = "",
    status = false,
    status_t = 1,
    restart = false,
    restart_stream = nil,
    sessions = false,
    close_session = nil,
}

options = {
    ["--base"] = function(idx)
        cli.base = tostring(argv[idx + 1] or "")
        return 1
    end,
    ["--login"] = function(idx)
        cli.login = tostring(argv[idx + 1] or "")
        return 1
    end,
    ["--password"] = function(idx)
        cli.password = tostring(argv[idx + 1] or "")
        return 1
    end,
    ["--status"] = function(idx)
        cli.status = true
        local nextv = argv[idx + 1]
        if nextv and tostring(nextv):match("^%d+$") then
            cli.status_t = tonumber(nextv) or 1
            return 1
        end
        return 0
    end,
    ["--restart"] = function(idx)
        cli.restart = true
        return 0
    end,
    ["--restart-stream"] = function(idx)
        cli.restart_stream = tostring(argv[idx + 1] or "")
        return 1
    end,
    ["--sessions"] = function(idx)
        cli.sessions = true
        return 0
    end,
    ["--close-session"] = function(idx)
        cli.close_session = tostring(argv[idx + 1] or "")
        return 1
    end,
}

local function fatal(msg)
    log.error("[cli] " .. tostring(msg))
    astra.exit()
end

local function mk_client()
    local client, err = CesboApiClient.new({
        baseUrl = cli.base,
        login = cli.login,
        password = cli.password,
        debug = true,
        connect_timeout_ms = 800,
        read_timeout_ms = 2000,
        timeout_ms = 3000,
        max_attempts = 3,
    })
    if not client then
        fatal(err or "client init failed")
    end
    return client
end

local function pretty(v)
    if json and json.encode_pretty then
        return json.encode_pretty(v, { indent = "  ", final_newline = false })
    end
    return json.encode(v)
end

local function run_sequence(steps)
    local i = 0
    local function next_step()
        i = i + 1
        local fn = steps[i]
        if not fn then
            astra.exit()
            return
        end
        fn(next_step)
    end
    next_step()
end

function main()
    if cli.base == "" then
        astra_usage()
        return
    end

    local client = mk_client()
    local steps = {}

    if cli.status then
        steps[#steps + 1] = function(done)
            client:GetSystemStatus(cli.status_t, function(ok, data, err)
                if not ok then
                    return fatal(err or "GetSystemStatus failed")
                end
                log.info("[system-status] " .. pretty(data))
                done()
            end)
        end
    end

    if cli.restart then
        steps[#steps + 1] = function(done)
            client:RestartServer(function(ok, data, err)
                if not ok then
                    return fatal(err or "RestartServer failed")
                end
                log.info("[restart] " .. pretty(data))
                done()
            end)
        end
    end

    if cli.restart_stream and cli.restart_stream ~= "" then
        steps[#steps + 1] = function(done)
            client:RestartStream(cli.restart_stream, function(ok, data, err)
                if not ok then
                    return fatal(err or "RestartStream failed")
                end
                log.info("[restart-stream] " .. pretty(data))
                done()
            end)
        end
    end

    if cli.sessions then
        steps[#steps + 1] = function(done)
            client:GetSessions(function(ok, data, err)
                if not ok then
                    return fatal(err or "GetSessions failed")
                end
                log.info("[sessions] " .. pretty(data))
                done()
            end)
        end
    end

    if cli.close_session and cli.close_session ~= "" then
        steps[#steps + 1] = function(done)
            client:CloseSession(cli.close_session, function(ok, data, err)
                if not ok then
                    return fatal(err or "CloseSession failed")
                end
                log.info("[close-session] " .. pretty(data))
                done()
            end)
        end
    end

    if #steps == 0 then
        astra_usage()
        return
    end

    run_sequence(steps)
end

astra_parse_options(1)
main()
