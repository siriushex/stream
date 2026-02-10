-- System observability: lightweight CPU/MEM/Disk/Net metrics for UI

system_metrics = system_metrics or {}

system_metrics.state = system_metrics.state or {
    enabled = false,
    rollup_enabled = false,
    rollup_interval_sec = 60,
    retention_sec = 3600,
    include_virtual_ifaces = false,
}

system_metrics.cache = system_metrics.cache or {
    cpu = nil, -- { ts=unix_sec, idle=..., total=... }
    net = nil, -- { ts=unix_sec, ifaces={ iface={ rx_bytes=..., tx_bytes=... } } }
}

system_metrics.timer_rollup = system_metrics.timer_rollup or nil
system_metrics.ring = system_metrics.ring or nil

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

local function setting_bool(key, fallback)
    if config and config.get_setting then
        local value = config.get_setting(key)
        if value == nil then
            return fallback
        end
        if value == true or value == 1 or value == "1" or value == "true" or value == "yes" or value == "on" then
            return true
        end
        if value == false or value == 0 or value == "0" or value == "false" or value == "no" or value == "off" then
            return false
        end
    end
    return fallback
end

local function observability_enabled()
    -- Keep in sync with web/app.js isViewEnabled('observability')
    local on_demand = setting_bool("ai_metrics_on_demand", true)
    local logs_days = setting_number("ai_logs_retention_days", 0)
    local metrics_days = setting_number("ai_metrics_retention_days", 0)
    if on_demand then
        metrics_days = 0
    end
    return (logs_days or 0) > 0 or (metrics_days or 0) > 0
end

local function sanitize_interval(value)
    local num = tonumber(value) or 60
    if num < 1 then num = 1 end
    if num > 3600 then num = 3600 end
    return math.floor(num)
end

local function sanitize_retention(value)
    local num = tonumber(value) or 3600
    if num < 0 then num = 0 end
    if num > 86400 then num = 86400 end
    return math.floor(num)
end

local function is_virtual_iface(name)
    if not name or name == "" then
        return true
    end
    if name == "lo" then
        return true
    end
    if name:match("^docker") or name:match("^veth") or name:match("^br%-") or name:match("^virbr") then
        return true
    end
    return false
end

local function read_first_line(path)
    local f = io.open(path, "r")
    if not f then
        return nil
    end
    local line = f:read("*l")
    f:close()
    return line
end

local function read_lines(path)
    local f = io.open(path, "r")
    if not f then
        return nil
    end
    local lines = {}
    for line in f:lines() do
        table.insert(lines, line)
    end
    f:close()
    return lines
end

local function sample_cpu(now)
    local line = read_first_line("/proc/stat")
    if not line then
        return nil
    end
    if not line:match("^cpu%s") then
        return nil
    end
    local fields = {}
    for num in line:gmatch("(%d+)") do
        table.insert(fields, tonumber(num))
    end
    if #fields < 4 then
        return nil
    end
    local user = fields[1] or 0
    local nice = fields[2] or 0
    local system = fields[3] or 0
    local idle = fields[4] or 0
    local iowait = fields[5] or 0
    local irq = fields[6] or 0
    local softirq = fields[7] or 0
    local steal = fields[8] or 0

    local idle_all = idle + iowait
    local total = idle_all + user + nice + system + irq + softirq + steal
    return { ts = now, idle = idle_all, total = total }
end

local function compute_cpu_usage(prev, cur)
    if not prev or not cur then
        return nil
    end
    local dt = (cur.ts or 0) - (prev.ts or 0)
    if dt <= 0 then
        return nil
    end
    local d_total = (cur.total or 0) - (prev.total or 0)
    if d_total <= 0 then
        return nil
    end
    local d_idle = (cur.idle or 0) - (prev.idle or 0)
    local usage = 1 - (d_idle / d_total)
    if usage < 0 then usage = 0 end
    if usage > 1 then usage = 1 end
    return usage
end

local function sample_mem()
    local lines = read_lines("/proc/meminfo")
    if not lines then
        return nil
    end
    local mem_total = nil
    local mem_avail = nil
    local mem_free = 0
    local buffers = 0
    local cached = 0
    for _, line in ipairs(lines) do
        local k, v = line:match("^(%w+):%s*(%d+)")
        if k and v then
            local n = tonumber(v) or 0
            if k == "MemTotal" then
                mem_total = n
            elseif k == "MemAvailable" then
                mem_avail = n
            elseif k == "MemFree" then
                mem_free = n
            elseif k == "Buffers" then
                buffers = n
            elseif k == "Cached" then
                cached = n
            end
        end
    end
    if not mem_total then
        return nil
    end
    if not mem_avail then
        mem_avail = mem_free + buffers + cached
    end
    local used_kb = mem_total - mem_avail
    if used_kb < 0 then used_kb = 0 end
    local used_percent = mem_total > 0 and (used_kb / mem_total) * 100 or 0
    return {
        total_kb = mem_total,
        available_kb = mem_avail,
        used_kb = used_kb,
        used_percent = used_percent,
    }
end

local function sample_loadavg()
    local line = read_first_line("/proc/loadavg")
    if not line then
        return nil
    end
    local la1, la5, la15 = line:match("^(%S+)%s+(%S+)%s+(%S+)")
    return {
        la1 = tonumber(la1),
        la5 = tonumber(la5),
        la15 = tonumber(la15),
    }
end

local function sample_uptime()
    local line = read_first_line("/proc/uptime")
    if not line then
        return nil
    end
    local sec = line:match("^(%S+)")
    return tonumber(sec)
end

local function sample_net(now, include_virtual)
    local lines = read_lines("/proc/net/dev")
    if not lines or #lines < 3 then
        return nil
    end
    local ifaces = {}
    for idx = 3, #lines do
        local line = lines[idx]
        local name, rest = line:match("^%s*([^:]+):%s*(.*)$")
        if name and rest then
            name = name:gsub("^%s+", ""):gsub("%s+$", "")
            if include_virtual or not is_virtual_iface(name) then
                local nums = {}
                for num in rest:gmatch("(%d+)") do
                    table.insert(nums, tonumber(num))
                end
                local rx_bytes = nums[1] or 0
                local tx_bytes = nums[9] or 0
                ifaces[name] = { rx_bytes = rx_bytes, tx_bytes = tx_bytes }
            end
        end
    end
    return { ts = now, ifaces = ifaces }
end

local function compute_net_rates(prev, cur)
    if not prev or not cur then
        return {}
    end
    local dt = (cur.ts or 0) - (prev.ts or 0)
    if dt <= 0 then
        return {}
    end
    local out = {}
    for name, curv in pairs(cur.ifaces or {}) do
        local prevv = prev.ifaces and prev.ifaces[name] or nil
        if prevv then
            local rx = (curv.rx_bytes or 0) - (prevv.rx_bytes or 0)
            local tx = (curv.tx_bytes or 0) - (prevv.tx_bytes or 0)
            if rx < 0 then rx = 0 end
            if tx < 0 then tx = 0 end
            out[name] = {
                rx_bps = rx / dt,
                tx_bps = tx / dt,
            }
        end
    end
    return out
end

local function build_disk_snapshot()
    if not utils or not utils.statvfs then
        return nil
    end
    local paths = { "/" }
    if config and type(config.data_dir) == "string" and config.data_dir ~= "" and config.data_dir ~= "/" then
        table.insert(paths, config.data_dir)
    end
    local disks = {}
    local seen = {}
    for _, path in ipairs(paths) do
        if not seen[path] then
            seen[path] = true
            local ok, stat = pcall(utils.statvfs, path)
            if ok and type(stat) == "table" and not stat.error then
                stat.path = path
                table.insert(disks, stat)
            end
        end
    end
    return disks
end

local function ring_new(capacity)
    return { cap = capacity, idx = 0, size = 0, points = {} }
end

local function ring_push(ring, point)
    if not ring or not ring.cap or ring.cap <= 0 then
        return
    end
    ring.idx = (ring.idx % ring.cap) + 1
    ring.points[ring.idx] = point
    ring.size = math.min((ring.size or 0) + 1, ring.cap)
end

local function ring_iter_since(ring, since_ms)
    local out = {}
    if not ring or not ring.points or not ring.size or ring.size <= 0 then
        return out
    end
    local start = ring.idx - ring.size + 1
    for i = 0, ring.size - 1 do
        local pos = start + i
        local idx = ((pos - 1) % ring.cap) + 1
        local pt = ring.points[idx]
        if pt and pt.t_ms and (since_ms == nil or pt.t_ms >= since_ms) then
            table.insert(out, pt)
        end
    end
    return out
end

function system_metrics.snapshot()
    local now = os.time()
    local enabled = observability_enabled()
    if not enabled then
        return { enabled = false, ts = now }
    end

    local cpu_cur = sample_cpu(now)
    local cpu_prev = system_metrics.cache.cpu
    local cpu_usage = compute_cpu_usage(cpu_prev, cpu_cur)
    if cpu_cur then
        system_metrics.cache.cpu = cpu_cur
    end

    local include_virtual = system_metrics.state.include_virtual_ifaces == true
    local net_cur = sample_net(now, include_virtual)
    local net_prev = system_metrics.cache.net
    local net_rates = compute_net_rates(net_prev, net_cur)
    if net_cur then
        system_metrics.cache.net = net_cur
    end

    local net_list = {}
    if net_cur and net_cur.ifaces then
        local names = {}
        for name, _ in pairs(net_cur.ifaces) do
            table.insert(names, name)
        end
        table.sort(names)
        for _, name in ipairs(names) do
            local v = net_cur.ifaces[name]
            local r = net_rates[name] or {}
            table.insert(net_list, {
                iface = name,
                rx_bytes = v.rx_bytes or 0,
                tx_bytes = v.tx_bytes or 0,
                rx_bps = r.rx_bps,
                tx_bps = r.tx_bps,
            })
        end
    end

    local mem = sample_mem()
    local loadavg = sample_loadavg() or {}
    local uptime = sample_uptime()
    local disks = build_disk_snapshot()

    return {
        enabled = true,
        ts = now,
        cpu = { usage = cpu_usage, la1 = loadavg.la1, la5 = loadavg.la5, la15 = loadavg.la15 },
        mem = mem,
        disk = disks,
        net = net_list,
        uptime_sec = uptime,
    }
end

function system_metrics.get_timeseries(range_sec)
    local enabled = observability_enabled()
    if not enabled then
        return { enabled = false, rollup = false, items = {} }
    end
    if not system_metrics.state.rollup_enabled or not system_metrics.ring then
        return { enabled = true, rollup = false, items = {} }
    end
    local now_ms = os.time() * 1000
    local since_ms = nil
    if range_sec and tonumber(range_sec) and tonumber(range_sec) > 0 then
        since_ms = now_ms - (tonumber(range_sec) * 1000)
    end
    local pts = ring_iter_since(system_metrics.ring, since_ms)
    return { enabled = true, rollup = true, items = pts }
end

local function rollup_tick()
    local snap = system_metrics.snapshot()
    if not snap or not snap.enabled then
        return
    end
    local t_ms = (snap.ts or os.time()) * 1000
    local root_disk_used = nil
    if snap.disk and snap.disk[1] and snap.disk[1].used_percent ~= nil then
        root_disk_used = tonumber(snap.disk[1].used_percent)
    end
    local net_map = {}
    for _, item in ipairs(snap.net or {}) do
        net_map[item.iface] = { rx_bps = item.rx_bps, tx_bps = item.tx_bps }
    end
    ring_push(system_metrics.ring, {
        t_ms = t_ms,
        cpu_usage = snap.cpu and snap.cpu.usage or nil,
        mem_used_percent = snap.mem and snap.mem.used_percent or nil,
        disk_used_percent = root_disk_used,
        net = net_map,
    })
end

function system_metrics.configure()
    system_metrics.state.enabled = observability_enabled()
    system_metrics.state.rollup_enabled = setting_bool("observability_system_rollup_enabled", false)
    system_metrics.state.rollup_interval_sec = sanitize_interval(setting_number("observability_system_rollup_interval_sec", 60))
    system_metrics.state.retention_sec = sanitize_retention(setting_number("observability_system_retention_sec", 3600))
    system_metrics.state.include_virtual_ifaces = setting_bool("observability_system_include_virtual_ifaces", false)

    if system_metrics.timer_rollup then
        system_metrics.timer_rollup:close()
        system_metrics.timer_rollup = nil
    end
    system_metrics.ring = nil

    if system_metrics.state.enabled and system_metrics.state.rollup_enabled and system_metrics.state.retention_sec > 0 then
        local cap = math.floor(system_metrics.state.retention_sec / math.max(1, system_metrics.state.rollup_interval_sec))
        if cap < 10 then cap = 10 end
        if cap > 20000 then cap = 20000 end
        system_metrics.ring = ring_new(cap)
        system_metrics.timer_rollup = timer({
            interval = system_metrics.state.rollup_interval_sec,
            callback = function()
                rollup_tick()
            end,
        })
        -- Prime baseline; first tick may not have deltas.
        rollup_tick()
    end
end

