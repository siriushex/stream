-- System observability: lightweight CPU/MEM/Disk/Net metrics for UI

system_metrics = system_metrics or {}

system_metrics.state = system_metrics.state or {
    enabled = true,
    collection_enabled = false,
    rollup_enabled = false,
    rollup_interval_sec = 60,
    retention_sec = 3600,
    logs_retention_days = 0,
    retention_source = "setting",
    include_virtual_ifaces = false,
}

system_metrics.cache = system_metrics.cache or {
    cpu = nil, -- { ts=unix_sec, idle=..., total=... }
    net = nil, -- { ts=unix_sec, ifaces={ iface={ rx_bytes=..., tx_bytes=... } } }
    disk = nil, -- { ts=unix_sec, devices={ dev={ read_bytes=..., write_bytes=... } } }
}

system_metrics.timer_rollup = system_metrics.timer_rollup or nil
system_metrics.timer_prune = system_metrics.timer_prune or nil
system_metrics.last_prune_ts = system_metrics.last_prune_ts or 0

local function setting_raw(key)
    if config and config.get_setting then
        return config.get_setting(key)
    end
    return nil
end

local function setting_number(key, fallback)
    if config and config.get_setting then
        local value = setting_raw(key)
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

local function observability_collection_enabled()
    return setting_bool("observability_enabled", false) == true
end

local function observability_read_enabled()
    return true
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
    if num > 31536000 then num = 31536000 end -- 365 days
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

local function is_virtual_disk(name)
    if not name or name == "" then
        return true
    end
    if name:match("^loop") or name:match("^ram") or name:match("^zram") or name:match("^fd") then
        return true
    end
    return false
end

local function is_block_device(name)
    if is_virtual_disk(name) then
        return false
    end
    return read_first_line("/sys/block/" .. tostring(name) .. "/dev") ~= nil
end

local function sample_disk_io(now)
    local lines = read_lines("/proc/diskstats")
    if not lines or #lines == 0 then
        return nil
    end
    local devices = {}
    for _, line in ipairs(lines) do
        local _major, _minor, name, rest = line:match("^%s*(%d+)%s+(%d+)%s+([^%s]+)%s+(.*)$")
        if name and rest and is_block_device(name) then
            local nums = {}
            for num in rest:gmatch("(%d+)") do
                table.insert(nums, tonumber(num))
            end
            local sectors_read = nums[3] or 0
            local sectors_written = nums[7] or 0
            devices[name] = {
                read_bytes = sectors_read * 512,
                write_bytes = sectors_written * 512,
            }
        end
    end
    return { ts = now, devices = devices }
end

local function compute_disk_io_rates(prev, cur)
    if not prev or not cur then
        return {}
    end
    local dt = (cur.ts or 0) - (prev.ts or 0)
    if dt <= 0 then
        return {}
    end
    local out = {}
    for name, curv in pairs(cur.devices or {}) do
        local prevv = prev.devices and prev.devices[name] or nil
        if prevv then
            local read = (curv.read_bytes or 0) - (prevv.read_bytes or 0)
            local write = (curv.write_bytes or 0) - (prevv.write_bytes or 0)
            if read < 0 then read = 0 end
            if write < 0 then write = 0 end
            out[name] = {
                read_bps = read / dt,
                write_bps = write / dt,
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

local function resolve_retention_sec()
    local logs_days = setting_number("ai_logs_retention_days", 0)
    local raw = setting_raw("observability_system_retention_sec")
    local value = tonumber(raw)
    if value ~= nil and value > 0 then
        return sanitize_retention(value), "setting", logs_days
    end
    if logs_days > 0 then
        return sanitize_retention(logs_days * 86400), "logs_days", logs_days
    end
    return sanitize_retention(86400), "default", logs_days
end

local function to_rollup_point(snap)
    if not snap then
        return nil
    end
    local root_disk_used = nil
    if snap.disk and snap.disk[1] and snap.disk[1].used_percent ~= nil then
        root_disk_used = tonumber(snap.disk[1].used_percent)
    end
    local disk_io_rows = {}
    for _, item in ipairs(snap.disk_io or {}) do
        if item and item.device then
            table.insert(disk_io_rows, {
                device = tostring(item.device),
                read_bps = tonumber(item.read_bps),
                write_bps = tonumber(item.write_bps),
            })
        end
    end
    local net_rows = {}
    for _, item in ipairs(snap.net or {}) do
        if item and item.iface then
            table.insert(net_rows, {
                iface = tostring(item.iface),
                rx_bps = tonumber(item.rx_bps),
                tx_bps = tonumber(item.tx_bps),
            })
        end
    end
    return {
        ts_bucket = tonumber(snap.ts) or os.time(),
        t_ms = (tonumber(snap.ts) or os.time()) * 1000,
        cpu_usage = snap.cpu and snap.cpu.usage or nil,
        mem_used_percent = snap.mem and snap.mem.used_percent or nil,
        disk_used_percent = root_disk_used,
        disk_io = disk_io_rows,
        net = net_rows,
    }
end

local function row_to_point(row)
    if not row then
        return nil
    end
    local ts_bucket = tonumber(row.ts_bucket)
    if not ts_bucket then
        return nil
    end
    local net_map = {}
    local net_raw = row.net
    if type(net_raw) == "table" then
        if #net_raw > 0 then
            for _, item in ipairs(net_raw) do
                if item and item.iface then
                    net_map[item.iface] = {
                        rx_bps = tonumber(item.rx_bps),
                        tx_bps = tonumber(item.tx_bps),
                    }
                end
            end
        else
            -- Backward compatibility for legacy rows where `net` is already a map.
            for iface, item in pairs(net_raw) do
                if item then
                    net_map[tostring(iface)] = {
                        rx_bps = tonumber(item.rx_bps),
                        tx_bps = tonumber(item.tx_bps),
                    }
                end
            end
        end
    end
    local disk_io_map = {}
    local disk_raw = row.disk_io
    if type(disk_raw) == "table" then
        if #disk_raw > 0 then
            for _, item in ipairs(disk_raw) do
                if item and item.device then
                    disk_io_map[item.device] = {
                        read_bps = tonumber(item.read_bps),
                        write_bps = tonumber(item.write_bps),
                    }
                end
            end
        else
            -- Backward compatibility for legacy rows where `disk_io` is already a map.
            for dev, item in pairs(disk_raw) do
                if item then
                    disk_io_map[tostring(dev)] = {
                        read_bps = tonumber(item.read_bps),
                        write_bps = tonumber(item.write_bps),
                    }
                end
            end
        end
    end
    return {
        t_ms = ts_bucket * 1000,
        cpu_usage = tonumber(row.cpu_usage),
        mem_used_percent = tonumber(row.mem_used_percent),
        disk_used_percent = tonumber(row.disk_used_percent),
        disk_io = disk_io_map,
        net = net_map,
    }
end

local function prune_rollup()
    if not config or not config.prune_system_metric_rollup then
        return
    end
    local now = os.time()
    local retention_sec = tonumber(system_metrics.state.retention_sec) or 0
    if retention_sec <= 0 then
        return
    end
    local cutoff = now - retention_sec
    if cutoff <= 0 then
        return
    end
    config.prune_system_metric_rollup(cutoff)
    system_metrics.last_prune_ts = now
end

function system_metrics.snapshot()
    local now = os.time()
    if not observability_read_enabled() then
        return { enabled = false, ts = now, collection_enabled = false }
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
    local disk_cur = sample_disk_io(now)
    local disk_prev = system_metrics.cache.disk
    local disk_io_rates = compute_disk_io_rates(disk_prev, disk_cur)
    if disk_cur then
        system_metrics.cache.disk = disk_cur
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
    local disk_io_list = {}
    if disk_cur and disk_cur.devices then
        local names = {}
        for name, _ in pairs(disk_cur.devices) do
            table.insert(names, name)
        end
        table.sort(names)
        for _, name in ipairs(names) do
            local v = disk_cur.devices[name]
            local r = disk_io_rates[name] or {}
            table.insert(disk_io_list, {
                device = name,
                read_bytes = v.read_bytes or 0,
                write_bytes = v.write_bytes or 0,
                read_bps = r.read_bps,
                write_bps = r.write_bps,
            })
        end
    end

    local mem = sample_mem()
    local loadavg = sample_loadavg() or {}
    local uptime = sample_uptime()
    local disks = build_disk_snapshot()

    return {
        enabled = true,
        collection_enabled = observability_collection_enabled(),
        ts = now,
        cpu = { usage = cpu_usage, la1 = loadavg.la1, la5 = loadavg.la5, la15 = loadavg.la15 },
        mem = mem,
        disk = disks,
        disk_io = disk_io_list,
        net = net_list,
        uptime_sec = uptime,
    }
end

function system_metrics.get_timeseries(range_sec)
    if not observability_read_enabled() then
        return { enabled = false, collection_enabled = false, rollup = false, items = {} }
    end
    if not config or not config.list_system_metric_rollup then
        return { enabled = true, collection_enabled = observability_collection_enabled(), rollup = false, items = {} }
    end
    local now = os.time()
    local since = 0
    if range_sec and tonumber(range_sec) and tonumber(range_sec) > 0 then
        since = now - tonumber(range_sec)
    end
    local rows = config.list_system_metric_rollup({
        since = since,
        ["until"] = now + 1,
        limit = 300000,
    }) or {}
    local max_points = 6000
    if #rows > max_points then
        local sampled = {}
        local step = math.max(1, math.floor(#rows / max_points))
        local idx = 1
        while idx <= #rows do
            table.insert(sampled, rows[idx])
            idx = idx + step
        end
        if sampled[#sampled] ~= rows[#rows] then
            table.insert(sampled, rows[#rows])
        end
        rows = sampled
    end
    local points = {}
    for _, row in ipairs(rows) do
        local pt = row_to_point(row)
        if pt then
            table.insert(points, pt)
        end
    end
    return {
        enabled = true,
        collection_enabled = observability_collection_enabled(),
        rollup = (#points > 0) or (system_metrics.state.rollup_enabled == true),
        items = points,
    }
end

local function rollup_tick()
    if system_metrics.state.collection_enabled ~= true then
        return
    end
    if system_metrics.state.rollup_enabled ~= true then
        return
    end
    local snap = system_metrics.snapshot()
    if not snap or not snap.enabled then
        return
    end
    if not config or not config.upsert_system_metric_rollup then
        return
    end
    local point = to_rollup_point(snap)
    if not point then
        return
    end
    config.upsert_system_metric_rollup({
        ts_bucket = point.ts_bucket,
        cpu_usage = point.cpu_usage,
        mem_used_percent = point.mem_used_percent,
        disk_used_percent = point.disk_used_percent,
        disk_io = point.disk_io,
        net = point.net,
    })
end

function system_metrics.configure()
    system_metrics.state.enabled = true
    system_metrics.state.collection_enabled = observability_collection_enabled()
    system_metrics.state.rollup_enabled = setting_bool("observability_system_rollup_enabled", false)
    system_metrics.state.rollup_interval_sec = sanitize_interval(setting_number("observability_system_rollup_interval_sec", 60))
    local retention_sec, retention_source, logs_days = resolve_retention_sec()
    system_metrics.state.retention_sec = retention_sec
    system_metrics.state.retention_source = retention_source
    system_metrics.state.logs_retention_days = logs_days or 0
    system_metrics.state.include_virtual_ifaces = setting_bool("observability_system_include_virtual_ifaces", false)

    if system_metrics.timer_rollup then
        system_metrics.timer_rollup:close()
        system_metrics.timer_rollup = nil
    end
    if system_metrics.timer_prune then
        system_metrics.timer_prune:close()
        system_metrics.timer_prune = nil
    end

    if system_metrics.state.collection_enabled and system_metrics.state.rollup_enabled then
        system_metrics.timer_rollup = timer({
            interval = system_metrics.state.rollup_interval_sec,
            callback = function()
                rollup_tick()
            end,
        })
        system_metrics.timer_prune = timer({
            interval = 3600,
            callback = function()
                prune_rollup()
            end,
        })
        -- Prime baseline; first tick may not have deltas. Also trim old points on start.
        rollup_tick()
        prune_rollup()
    end
end
