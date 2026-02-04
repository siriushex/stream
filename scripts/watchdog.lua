-- Resource watchdog (CPU/RAM) with optional auto-restart

watchdog = watchdog or {}

watchdog.state = {
    enabled = false,
    interval_sec = 10,
    cpu_limit_pct = 95,
    rss_limit_mb = 0,
    rss_limit_pct = 80,
    max_strikes = 6,
    min_uptime_sec = 180,
    action = "exit",
}

watchdog.timer = nil
watchdog.start_ts = os.time()
watchdog.last_proc = nil
watchdog.last_total = nil
watchdog.strikes = 0
watchdog.last_log_ts = 0
watchdog.mem_total_kb = nil

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

local function read_file(path)
    local file = io.open(path, "r")
    if not file then
        return nil
    end
    local content = file:read("*a")
    file:close()
    return content
end

local function read_proc_stat_total()
    local content = read_file("/proc/stat")
    if not content then
        return nil
    end
    local line = content:match("^(cpu%s+.-)\n")
    if not line then
        return nil
    end
    local nums = {}
    for value in line:gmatch("%s(%d+)") do
        table.insert(nums, tonumber(value))
    end
    if #nums == 0 then
        return nil
    end
    local total = 0
    for _, v in ipairs(nums) do
        total = total + v
    end
    return total
end

local function read_proc_self_time()
    local content = read_file("/proc/self/stat")
    if not content then
        return nil
    end
    local pid, comm, rest = content:match("^(%d+)%s+%((.-)%)%s+(.*)$")
    if not rest then
        return nil
    end
    local fields = {}
    for value in rest:gmatch("%S+") do
        table.insert(fields, value)
    end
    local utime = tonumber(fields[13])
    local stime = tonumber(fields[14])
    if not utime or not stime then
        return nil
    end
    return utime + stime
end

local function read_rss_kb()
    local content = read_file("/proc/self/status")
    if not content then
        return nil
    end
    local value = content:match("VmRSS:%s+(%d+)%s+kB")
    if not value then
        return nil
    end
    return tonumber(value)
end

local function read_mem_total_kb()
    if watchdog.mem_total_kb then
        return watchdog.mem_total_kb
    end
    local content = read_file("/proc/meminfo")
    if not content then
        return nil
    end
    local value = content:match("MemTotal:%s+(%d+)%s+kB")
    if not value then
        return nil
    end
    watchdog.mem_total_kb = tonumber(value)
    return watchdog.mem_total_kb
end

local function calc_cpu_pct()
    local total = read_proc_stat_total()
    local proc = read_proc_self_time()
    if not total or not proc then
        return nil
    end
    if watchdog.last_total == nil or watchdog.last_proc == nil then
        watchdog.last_total = total
        watchdog.last_proc = proc
        return nil
    end
    local delta_total = total - watchdog.last_total
    local delta_proc = proc - watchdog.last_proc
    watchdog.last_total = total
    watchdog.last_proc = proc
    if delta_total <= 0 then
        return nil
    end
    local pct = (delta_proc / delta_total) * 100
    if pct < 0 then pct = 0 end
    return pct
end

local function calc_rss_mb()
    local rss_kb = read_rss_kb()
    if not rss_kb then
        return nil
    end
    return rss_kb / 1024
end

local function limit_rss_mb()
    local cfg = watchdog.state
    if cfg.rss_limit_mb and cfg.rss_limit_mb > 0 then
        return cfg.rss_limit_mb
    end
    if cfg.rss_limit_pct and cfg.rss_limit_pct > 0 then
        local total_kb = read_mem_total_kb()
        if total_kb then
            return (total_kb * cfg.rss_limit_pct / 100) / 1024
        end
    end
    return nil
end

local function maybe_log(message, interval_sec)
    local now = os.time()
    local gap = interval_sec or 30
    if now - (watchdog.last_log_ts or 0) >= gap then
        watchdog.last_log_ts = now
        log.warning(message)
    end
end

local function trigger_restart(reason)
    log.error("[watchdog] restart: " .. reason)
    watchdog.state.enabled = false
    if watchdog.timer then
        watchdog.timer:close()
        watchdog.timer = nil
    end
    if watchdog.state.action == "log" then
        return
    end
    if watchdog.state.action == "reload" then
        if type(reload_runtime) == "function" then
            local ok, err = reload_runtime(true)
            if not ok then
                log.error("[watchdog] reload failed: " .. tostring(err))
            end
        end
        return
    end
    timer({
        interval = 0.2,
        callback = function(self)
            self:close()
            astra.exit()
        end,
    })
end

function watchdog.tick()
    local cfg = watchdog.state
    if not cfg.enabled then
        return
    end
    local now = os.time()
    if cfg.min_uptime_sec and cfg.min_uptime_sec > 0 then
        if (now - watchdog.start_ts) < cfg.min_uptime_sec then
            return
        end
    end

    local cpu_pct = calc_cpu_pct()
    local rss_mb = calc_rss_mb()
    local rss_limit = limit_rss_mb()

    local over_cpu = cpu_pct and cfg.cpu_limit_pct and cfg.cpu_limit_pct > 0 and cpu_pct >= cfg.cpu_limit_pct
    local over_rss = rss_mb and rss_limit and rss_mb >= rss_limit

    if over_cpu or over_rss then
        watchdog.strikes = watchdog.strikes + 1
        local details = string.format("cpu=%.1f%% (limit %.1f%%) rss=%.1fMB (limit %.1fMB) strikes=%d/%d",
            cpu_pct or -1, cfg.cpu_limit_pct or 0,
            rss_mb or -1, rss_limit or 0,
            watchdog.strikes, cfg.max_strikes)
        maybe_log("[watchdog] high resource usage: " .. details, 20)
        if watchdog.strikes >= cfg.max_strikes then
            trigger_restart("resource limits exceeded")
        end
        return
    end

    if watchdog.strikes > 0 then
        watchdog.strikes = 0
        maybe_log("[watchdog] resource usage back to normal", 10)
    end
end

function watchdog.configure()
    local enabled = setting_bool("resource_watchdog_enabled", true)
    local interval = setting_number("resource_watchdog_interval_sec", 10)
    if interval < 5 then interval = 5 end
    local cpu_limit = setting_number("resource_watchdog_cpu_pct", 95)
    local rss_limit_mb = setting_number("resource_watchdog_rss_mb", 0)
    local rss_limit_pct = setting_number("resource_watchdog_rss_pct", 80)
    local max_strikes = setting_number("resource_watchdog_max_strikes", 6)
    local min_uptime = setting_number("resource_watchdog_min_uptime_sec", 180)
    local action = setting_string("resource_watchdog_action", "exit")

    if not read_proc_stat_total() then
        enabled = false
        log.warning("[watchdog] /proc not available, watchdog disabled")
    end

    watchdog.state.enabled = enabled
    watchdog.state.interval_sec = interval
    watchdog.state.cpu_limit_pct = cpu_limit
    watchdog.state.rss_limit_mb = rss_limit_mb
    watchdog.state.rss_limit_pct = rss_limit_pct
    watchdog.state.max_strikes = max_strikes
    watchdog.state.min_uptime_sec = min_uptime
    if action ~= "exit" and action ~= "reload" and action ~= "log" then
        action = "exit"
    end
    watchdog.state.action = action
    watchdog.start_ts = os.time()
    watchdog.strikes = 0
    watchdog.last_proc = nil
    watchdog.last_total = nil

    if watchdog.timer then
        watchdog.timer:close()
        watchdog.timer = nil
    end
    if enabled then
        watchdog.timer = timer({
            interval = interval,
            callback = function()
                watchdog.tick()
            end,
        })
        log.info(string.format(
            "[watchdog] enabled: interval=%ds cpu_limit=%.1f%% rss_limit=%.1fMB rss_pct=%.1f%% strikes=%d uptime=%ds",
            interval,
            cpu_limit or 0,
            rss_limit_mb or 0,
            rss_limit_pct or 0,
            max_strikes or 0,
            min_uptime or 0
        ))
    else
        log.info("[watchdog] disabled")
    end
end
