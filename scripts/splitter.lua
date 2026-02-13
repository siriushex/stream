-- HLSSplitter service manager

splitter = {
    instances = {},
    health_interval_sec = 10,
    probe_timeout_sec = 4,
}

local function ensure_dir(path)
    local stat = utils.stat(path)
    if not stat or stat.type ~= "directory" then
        os.execute("mkdir -p " .. path)
    end
end

local function get_data_dir()
    local db_path = config and config.db_path or "./data/astra.db"
    local dir = db_path:match("^(.*)/[^/]+$")
    return dir or "."
end

local function default_config_path(id)
    local dir = get_data_dir() .. "/splitters"
    ensure_dir(dir)
    return dir .. "/" .. tostring(id) .. ".xml"
end

local function xml_escape(value)
    local text = tostring(value or "")
    text = text:gsub("&", "&amp;")
    text = text:gsub("<", "&lt;")
    text = text:gsub(">", "&gt;")
    text = text:gsub("\"", "&quot;")
    text = text:gsub("'", "&apos;")
    return text
end

local function parse_ipv4(value)
    if not value then
        return nil
    end
    local a, b, c, d = tostring(value):match("^%s*(%d+)%.(%d+)%.(%d+)%.(%d+)%s*$")
    if not a then
        return nil
    end
    a = tonumber(a)
    b = tonumber(b)
    c = tonumber(c)
    d = tonumber(d)
    if not a or not b or not c or not d then
        return nil
    end
    if a > 255 or b > 255 or c > 255 or d > 255 then
        return nil
    end
    return a * 16777216 + b * 65536 + c * 256 + d
end

local function ipv4_from_int(value)
    if value == nil then
        return nil
    end
    local n = math.floor(value)
    local a = math.floor(n / 16777216) % 256
    local b = math.floor(n / 65536) % 256
    local c = math.floor(n / 256) % 256
    local d = n % 256
    return string.format("%d.%d.%d.%d", a, b, c, d)
end

local function cidr_to_range(value)
    local base, prefix = tostring(value or ""):match("^%s*(.-)%s*/%s*(%d+)%s*$")
    if not base then
        return nil
    end
    local num = tonumber(prefix)
    if not num or num < 0 or num > 32 then
        return nil
    end
    local ip = parse_ipv4(base)
    if not ip then
        return nil
    end
    local shift = 32 - num
    local block = 2 ^ shift
    local start = math.floor(ip / block) * block
    local finish = start + block - 1
    return ipv4_from_int(start), ipv4_from_int(finish)
end

local function build_link_attrs(link)
    local attrs = {}
    if link.bandwidth then
        table.insert(attrs, "bandwidth=\"" .. tostring(link.bandwidth) .. "\"")
    end
    if link.buffering then
        table.insert(attrs, "buffering=\"" .. tostring(link.buffering) .. "\"")
    end
    if #attrs == 0 then
        return ""
    end
    return " " .. table.concat(attrs, " ")
end

local function build_config_xml(instance)
    local lines = { "<resources>" }
    local links = instance.links or {}
    for _, link in ipairs(links) do
        if link.enable ~= 0 and link.url and link.url ~= "" then
            table.insert(lines,
                "  <link" .. build_link_attrs(link) .. ">" .. xml_escape(link.url) .. "</link>")
        end
    end

    local allow = instance.allow or {}
    if #allow == 0 then
        table.insert(lines, "  <allow>0.0.0.0</allow>")
    else
        for _, rule in ipairs(allow) do
            if rule.kind == "allow" then
                table.insert(lines, "  <allow>" .. xml_escape(rule.value) .. "</allow>")
            elseif rule.kind == "allowRange" then
                local from_ip, to_ip = tostring(rule.value or ""):match("^%s*([^%s,%-]+)%s*[,%-]%s*([^%s,%-]+)%s*$")
                if not from_ip or not to_ip then
                    from_ip, to_ip = tostring(rule.value or ""):match("^%s*([^%s]+)%s*%.%.%s*([^%s]+)%s*$")
                end
                if not from_ip or not to_ip then
                    from_ip, to_ip = cidr_to_range(rule.value)
                end
                if from_ip and to_ip then
                    table.insert(lines, "  <allowRange>")
                    table.insert(lines, "    <from>" .. xml_escape(from_ip) .. "</from>")
                    table.insert(lines, "    <to>" .. xml_escape(to_ip) .. "</to>")
                    table.insert(lines, "  </allowRange>")
                end
            end
        end
    end

    table.insert(lines, "</resources>")
    return table.concat(lines, "\n") .. "\n"
end

local function write_config_file(path, content)
    if not path or path == "" then
        return nil, "config path missing"
    end
    local tmp_path = path .. ".tmp"
    local tmp, err = io.open(tmp_path, "w")
    if tmp then
        tmp:write(content)
        tmp:close()
        if os.rename(tmp_path, path) then
            return true
        end
    end

    local file, err = io.open(path, "w")
    if not file then
        return nil, err
    end
    file:write(content)
    file:close()
    return true
end

local function find_binary()
    local candidates = {
        "./hlssplitter/hlssplitter",
        "./hlssplitter/source/hlssplitter/hlssplitter",
    }
    for _, path in ipairs(candidates) do
        local stat = utils.stat(path)
        if stat and stat.type == "file" then
            return path
        end
    end
    return nil
end

local function prune_history(history, cutoff)
    local filtered = {}
    for _, ts in ipairs(history or {}) do
        if ts >= cutoff then
            table.insert(filtered, ts)
        end
    end
    return filtered
end

local function restart_allowed(instance)
    local now = os.time()
    instance.restart_history = prune_history(instance.restart_history or {}, now - 600)
    return #instance.restart_history < 10
end

local function parse_http_url(url)
    local parsed = parse_url(url)
    if not parsed or parsed.format ~= "http" then
        return nil
    end
    parsed.path = parsed.path or "/"
    return parsed
end

local function normalize_path(path)
    if not path or path == "" then
        return "/"
    end
    if path:sub(1, 1) ~= "/" then
        return "/" .. path
    end
    return path
end

local function build_output_url(port, resource_path)
    return "http://127.0.0.1:" .. tostring(port) .. normalize_path(resource_path)
end

local function stop_probe(status)
    local probe = status and status.probe
    if not probe then
        return
    end
    if probe.timer then
        probe.timer:close()
        probe.timer = nil
    end
    if probe.request then
        probe.request:close()
        probe.request = nil
    end
    probe.analyze = nil
    status.probe = nil
end

local function mark_status_ok(status)
    status.state = "OK"
    status.last_ok_ts = os.time()
    status.last_error = nil
end

local function mark_status_down(status, reason)
    status.state = "DOWN"
    status.last_error = reason or "unknown"
end

local function start_probe(instance, link, status)
    if status.probe then
        return
    end
    local parsed = parse_http_url(link.url)
    if not parsed then
        mark_status_down(status, "http_only")
        return
    end

    local resource_path = normalize_path(parsed.path)
    local output_url = build_output_url(instance.port, resource_path)
    local output_parsed = parse_http_url(output_url)
    if not output_parsed then
        mark_status_down(status, "invalid_output_url")
        return
    end

    status.state = "PROBING"
    status.last_error = nil

    local probe = {
        started_ts = os.time(),
        ok = false,
    }
    status.probe = probe

    local request
    request = http_request({
        host = output_parsed.host,
        port = output_parsed.port,
        path = output_parsed.path,
        stream = true,
        timeout = instance.probe_timeout_sec,
        headers = {
            "User-Agent: Stream",
            "Host: " .. output_parsed.host .. ":" .. tostring(output_parsed.port),
            "Connection: close",
        },
        callback = function(self, response)
            if not response then
                mark_status_down(status, "no_response")
                stop_probe(status)
                return
            end
            if response.code ~= 200 then
                mark_status_down(status, "http_" .. tostring(response.code))
                stop_probe(status)
                return
            end
            if response.stream then
                if type(analyze) ~= "function" then
                    mark_status_down(status, "analyze_unavailable")
                    stop_probe(status)
                    return
                end
                probe.analyze = analyze({
                    upstream = self:stream(),
                    name = "splitter_probe",
                    callback = function(data)
                        if data and data.error then
                            mark_status_down(status, tostring(data.error))
                            stop_probe(status)
                            return
                        end
                        if data and (data.analyze or data.psi) then
                            mark_status_ok(status)
                            stop_probe(status)
                        end
                    end,
                })
                return
            end

            mark_status_down(status, "no_stream")
            stop_probe(status)
        end,
    })

    probe.request = request
    probe.timer = timer({
        interval = 1,
        callback = function(self)
            if not status or not status.probe then
                self:close()
                return
            end
            if os.time() - probe.started_ts >= instance.probe_timeout_sec then
                mark_status_down(status, "probe_timeout")
                stop_probe(status)
                self:close()
            end
        end,
    })
    if request then
        probe.request = request
    end
end

local function ensure_link_status(instance)
    instance.link_status = instance.link_status or {}
    for _, link in ipairs(instance.links or {}) do
        local status = instance.link_status[link.id]
        if not status then
            status = {
                link_id = link.id,
                url = link.url,
                state = "DOWN",
                last_ok_ts = nil,
                last_error = "not_checked",
            }
            instance.link_status[link.id] = status
        end
        status.url = link.url
        local parsed = parse_http_url(link.url)
        local resource_path = parsed and normalize_path(parsed.path) or ""
        status.resource_path = resource_path
        status.output_url = build_output_url(instance.port, resource_path)
        status.enable = link.enable ~= 0
    end

    for id, status in pairs(instance.link_status) do
        local exists = false
        for _, link in ipairs(instance.links or {}) do
            if link.id == id then
                exists = true
                break
            end
        end
        if not exists then
            stop_probe(status)
            instance.link_status[id] = nil
        end
    end
end

local function update_health(instance)
    if not instance or instance.state ~= "RUNNING" then
        return
    end
    if not instance.next_health_ts then
        instance.next_health_ts = os.time() + instance.health_interval_sec
        return
    end
    if os.time() < instance.next_health_ts then
        return
    end
    instance.next_health_ts = os.time() + instance.health_interval_sec

    ensure_link_status(instance)
    for _, link in ipairs(instance.links or {}) do
        local status = instance.link_status[link.id]
        if link.enable ~= 0 then
            start_probe(instance, link, status)
        else
            status.state = "DOWN"
            status.last_error = "disabled"
        end
    end
end

local function start_instance(instance)
    if instance.state == "ERROR" then
        return false
    end
    if not process or type(process.spawn) ~= "function" then
        instance.state = "ERROR"
        instance.last_error = "process module not available"
        return false
    end
    if not instance.port or instance.port < 1 or instance.port > 65535 then
        instance.state = "ERROR"
        instance.last_error = "invalid port"
        return false
    end
    for _, other in pairs(splitter.instances) do
        if other ~= instance and other.port == instance.port and other.proc then
            instance.state = "ERROR"
            instance.last_error = "port already in use by another splitter"
            return false
        end
    end
    local bin = find_binary()
    if not bin then
        instance.state = "ERROR"
        instance.last_error = "hlssplitter binary not found"
        return false
    end

    if not instance.config_path or instance.config_path == "" then
        instance.config_path = default_config_path(instance.id)
    end

    local xml = build_config_xml(instance)
    local ok, err = write_config_file(instance.config_path, xml)
    if not ok then
        instance.state = "ERROR"
        instance.last_error = "config write failed: " .. tostring(err)
        return false
    end

    local argv = { bin }
    if instance.in_interface and instance.in_interface ~= "" then
        table.insert(argv, "--in_interface")
        table.insert(argv, instance.in_interface)
    end
    if instance.out_interface and instance.out_interface ~= "" then
        table.insert(argv, "--out_interface")
        table.insert(argv, instance.out_interface)
    end
    if instance.logtype and instance.logtype ~= "" then
        table.insert(argv, "--logtype")
        table.insert(argv, instance.logtype)
    end
    if instance.logpath and instance.logpath ~= "" then
        table.insert(argv, "--logpath")
        table.insert(argv, instance.logpath)
    end
    table.insert(argv, instance.config_path)
    table.insert(argv, tostring(instance.port))

    local ok_spawn, proc = pcall(process.spawn, argv)
    if not ok_spawn or not proc then
        instance.state = "ERROR"
        instance.last_error = "hlssplitter spawn failed"
        return false
    end

    instance.proc = proc
    instance.pid = proc:pid()
    instance.state = "RUNNING"
    instance.last_error = nil
    instance.last_start_ts = os.time()
    instance.restart_backoff = 1
    instance.next_health_ts = os.time() + 1

    return true
end

local function stop_instance(instance)
    if instance.proc then
        instance.proc:terminate()
        instance.proc:kill()
        instance.proc:close()
        instance.proc = nil
    end
    instance.state = "STOPPED"
    instance.pid = nil
    instance.next_health_ts = nil
    if instance.link_status then
        for _, status in pairs(instance.link_status) do
            stop_probe(status)
        end
    end
end

local function schedule_restart(instance, reason)
    if not restart_allowed(instance) then
        instance.state = "ERROR"
        instance.last_error = "restart limit reached"
        return
    end
    table.insert(instance.restart_history, os.time())
    instance.state = "RESTARTING"
    instance.restart_due_ts = os.time() + (instance.restart_backoff or 1)
    instance.restart_backoff = math.min((instance.restart_backoff or 1) * 2, 30)
    instance.last_error = reason
end

local function tick_instance(instance)
    if instance.proc then
        local status = instance.proc:poll()
        if status then
            instance.proc:close()
            instance.proc = nil
            instance.pid = nil
            instance.last_exit_ts = os.time()
            if instance.enable then
                log.error("[splitter " .. instance.id .. "] exited: " .. tostring(status))
                schedule_restart(instance, "exit")
            else
                instance.state = "STOPPED"
            end
        end
    end

    if instance.state == "RESTARTING" and instance.restart_due_ts then
        if os.time() >= instance.restart_due_ts then
            instance.restart_due_ts = nil
            start_instance(instance)
        end
    end

    update_health(instance)
end

function splitter.apply_config(id)
    local instance = splitter.instances[id]
    if not instance then
        return nil
    end
    if not instance.config_path or instance.config_path == "" then
        instance.config_path = default_config_path(instance.id)
    end
    local xml = build_config_xml(instance)
    local ok, err = write_config_file(instance.config_path, xml)
    if not ok then
        instance.last_error = "config write failed: " .. tostring(err)
        return nil
    end
    return true
end

function splitter.render_config(id)
    local row = config.get_splitter(id)
    if not row then
        return nil, "splitter not found"
    end
    local instance = {
        id = id,
        links = config.list_splitter_links(id),
        allow = config.list_splitter_allow(id),
    }
    return build_config_xml(instance)
end

function splitter.start(id)
    local instance = splitter.instances[id]
    if not instance then
        return nil
    end
    if instance.proc then
        return true
    end
    if instance.state == "ERROR" then
        instance.state = "STOPPED"
        instance.last_error = nil
    end
    instance.enable = true
    return start_instance(instance)
end

function splitter.stop(id)
    local instance = splitter.instances[id]
    if not instance then
        return nil
    end
    instance.enable = false
    stop_instance(instance)
    return true
end

function splitter.restart(id)
    local instance = splitter.instances[id]
    if not instance then
        return nil
    end
    stop_instance(instance)
    instance.enable = true
    instance.state = "STOPPED"
    instance.last_error = nil
    return start_instance(instance)
end

function splitter.refresh(force)
    local rows = config.list_splitters()
    local desired = {}
    for _, row in ipairs(rows) do
        desired[row.id] = row
    end

    for id, row in pairs(desired) do
        local instance = splitter.instances[id]
        local links = config.list_splitter_links(id)
        local allow = config.list_splitter_allow(id)

        if not instance then
            instance = {
                id = id,
                restart_history = {},
                restart_backoff = 1,
                state = "STOPPED",
            }
            splitter.instances[id] = instance
        end

        instance.name = row.name
        instance.enable = (tonumber(row.enable) or 0) ~= 0
        instance.port = tonumber(row.port) or 0
        instance.in_interface = row.in_interface or ""
        instance.out_interface = row.out_interface or ""
        instance.logtype = row.logtype or ""
        instance.logpath = row.logpath or ""
        instance.config_path = row.config_path
        if not instance.config_path or instance.config_path == "" then
            instance.config_path = default_config_path(id)
            config.upsert_splitter(id, {
                name = row.name,
                enable = instance.enable,
                port = instance.port,
                in_interface = instance.in_interface,
                out_interface = instance.out_interface,
                logtype = instance.logtype,
                logpath = instance.logpath,
                config_path = instance.config_path,
            })
        end
        instance.links = links
        instance.allow = allow
        instance.health_interval_sec = splitter.health_interval_sec
        instance.probe_timeout_sec = splitter.probe_timeout_sec

        local hash = json.encode({
            row = {
                id = instance.id,
                name = instance.name,
                enable = instance.enable,
                port = instance.port,
                in_interface = instance.in_interface,
                out_interface = instance.out_interface,
                logtype = instance.logtype,
                logpath = instance.logpath,
                config_path = instance.config_path,
            },
            links = links,
            allow = allow,
        })
        local changed = instance.hash ~= hash
        instance.hash = hash

        if instance.enable then
            if changed or force then
                splitter.apply_config(id)
            end
            if not instance.proc and instance.state ~= "ERROR" then
                start_instance(instance)
            end
        else
            if instance.proc then
                stop_instance(instance)
            end
        end
    end

    for id, instance in pairs(splitter.instances) do
        if not desired[id] then
            stop_instance(instance)
            splitter.instances[id] = nil
        end
    end

    if not splitter.timer then
        splitter.timer = timer({
            interval = 1,
            callback = function(self)
                if not splitter.instances then
                    self:close()
                    splitter.timer = nil
                    return
                end
                for _, instance in pairs(splitter.instances) do
                    tick_instance(instance)
                end
            end,
        })
    end
end

function splitter.list_status()
    local out = {}
    for id, instance in pairs(splitter.instances) do
        table.insert(out, splitter.get_status(id))
    end
    return out
end

function splitter.get_status(id)
    local instance = splitter.instances[id]
    if not instance then
        return nil
    end
    ensure_link_status(instance)
    local links = {}
    for _, link in ipairs(instance.links or {}) do
        local status = instance.link_status and instance.link_status[link.id] or {}
        table.insert(links, {
            link_id = link.id,
            url = link.url,
            resource_path = status.resource_path,
            output_url = status.output_url,
            state = status.state or "DOWN",
            last_ok_ts = status.last_ok_ts,
            last_error = status.last_error,
        })
    end

    local running = instance.proc ~= nil and instance.state == "RUNNING"
    local uptime = nil
    if running and instance.last_start_ts then
        uptime = os.time() - instance.last_start_ts
    end

    return {
        id = instance.id,
        name = instance.name,
        running = running,
        state = instance.state,
        pid = instance.pid,
        port = instance.port,
        uptime_sec = uptime,
        last_start_ts = instance.last_start_ts,
        last_exit_ts = instance.last_exit_ts,
        restart_count_10min = #(instance.restart_history or {}),
        last_error = instance.last_error,
        links = links,
    }
end
