-- Astra Base Script
-- https://cesbo.com/astra/
--
-- Copyright (C) 2014-2015, Andrey Dyldin <and@cesbo.com>
--
-- This program is free software: you can redistribute it and/or modify
-- it under the terms of the GNU General Public License as published by
-- the Free Software Foundation, either version 3 of the License, or
-- (at your option) any later version.
--
-- This program is distributed in the hope that it will be useful,
-- but WITHOUT ANY WARRANTY; without even the implied warranty of
-- MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
-- GNU General Public License for more details.
--
-- You should have received a copy of the GNU General Public License
-- along with this program.  If not, see <http://www.gnu.org/licenses/>.

table.dump = function(t, p, i)
    if not p then p = print end
    if not i then
        p("{")
        table.dump(t, p, "    ")
        p("}")
        return
    end

    for key,val in pairs(t) do
        if type(val) == "table" then
            p(i .. tostring(key) .. " = {")
            table.dump(val, p, i .. "    ")
            p(i .. "}")
        elseif type(val) == "string" then
            p(i .. tostring(key) .. " = \"" .. val .. "\"")
        else
            p(i .. tostring(key) .. " = " .. tostring(val))
        end
    end
end

-- Deprecated
function dump_table(t, p, i)
    log.error("dump_table() method deprecated. use table.dump() instead")
    return table.dump(t, p, i)
end

string.split = function(s, d)
    if s == nil then
        return nil
    elseif type(s) == "string" then
        --
    elseif type(s) == "number" then
        s = tostring(s)
    else
        log.error("[split] string required")
        astra.abort()
    end

    local p = 1
    local t = {}
    while true do
        b = s:find(d, p)
        if not b then table.insert(t, s:sub(p)) return t end
        table.insert(t, s:sub(p, b - 1))
        p = b + 1
    end
end

-- Deprecated
function split(s, d)
    log.error("split() method deprecated. use string.split() instead")
    return string.split(s, d)
end

ifaddr_list = nil
if utils.ifaddrs then ifaddr_list = utils.ifaddrs() end

local function tool_exists(path)
    if not path or path == "" then
        return false
    end
    if not utils or type(utils.stat) ~= "function" then
        return false
    end
    local stat = utils.stat(path)
    return stat and stat.type == "file"
end

local function read_setting(key)
    if config and config.get_setting then
        return config.get_setting(key)
    end
    return nil
end

local function join_path(base, suffix)
    if not base or base == "" then
        return suffix or ""
    end
    if not suffix or suffix == "" then
        return base
    end
    if base:sub(-1) == "/" then
        base = base:sub(1, -2)
    end
    if suffix:sub(1, 1) == "/" then
        suffix = suffix:sub(2)
    end
    return base .. "/" .. suffix
end

local function resolve_bundle_candidate(name)
    local base = os.getenv("ASTRA_BASE_DIR")
        or os.getenv("ASTRAL_BASE_DIR")
        or os.getenv("ASTRA_HOME")
        or os.getenv("ASTRAL_HOME")
    if base and base ~= "" then
        local candidate = join_path(base, "bin/" .. name)
        if tool_exists(candidate) then
            return candidate
        end
    end
    local local_candidate = join_path(".", "bin/" .. name)
    if tool_exists(local_candidate) then
        return local_candidate
    end
    return nil
end

function astra_brand_version()
    local name = os.getenv("ASTRAL_NAME")
        or os.getenv("ASTRA_NAME")
        or "Astral"
    local version = os.getenv("ASTRAL_VERSION")
        or os.getenv("ASTRA_VERSION")
        or "1.0"
    return name .. " " .. version
end

function resolve_tool_path(name, opts)
    opts = opts or {}
    local prefer = opts.prefer
    if prefer and prefer ~= "" then
        return prefer, "config", tool_exists(prefer), false
    end

    local setting_key = opts.setting_key
    if setting_key then
        local value = read_setting(setting_key)
        if value ~= nil and tostring(value) ~= "" then
            local path = tostring(value)
            return path, "settings", tool_exists(path), false
        end
    end

    local env_key = opts.env_key
    if env_key then
        local env_value = os.getenv(env_key)
        if env_value and env_value ~= "" then
            return env_value, "env", tool_exists(env_value), false
        end
    end

    local bundled = resolve_bundle_candidate(name)
    if bundled then
        return bundled, "bundle", true, true
    end

    return name, "path", nil, false
end

-- ooooo  oooo oooooooooo  ooooo
--  888    88   888    888  888
--  888    88   888oooo88   888
--  888    88   888  88o    888      o
--   888oo88   o888o  88o8 o888ooooo88

parse_url_format = {}

parse_url_format.udp = function(url, data)
    local b = url:find("/")
    if b then
        url = url:sub(1, b - 1)
    end
    local b = url:find("@")
    if b then
        if b > 1 then
            data.localaddr = url:sub(1, b - 1)
            if ifaddr_list then
                local ifaddr = ifaddr_list[data.localaddr]
                if ifaddr and ifaddr.ipv4 then data.localaddr = ifaddr.ipv4[1] end
            end
        end
        url = url:sub(b + 1)
    end
    local b = url:find(":")
    if b then
        data.port = tonumber(url:sub(b + 1))
        data.addr = url:sub(1, b - 1)
    else
        data.port = 1234
        data.addr = url
    end

    -- check address
    if not data.port or data.port < 0 or data.port > 65535 then
        return false
    end

    local o = data.addr:split("%.")
    for _,i in ipairs(o) do
        local n = tonumber(i)
        if n == nil or n < 0 or n > 255 then
            return false
        end
    end

    return true
end

parse_url_format.rtp = parse_url_format.udp

parse_url_format._http = function(url, data)
    local b = url:find("/")
    if b then
        data.path = url:sub(b)
        url = url:sub(1, b - 1)
    else
        data.path = "/"
    end
    local b = url:find("@")
    if b then
        if b > 1 then
            local a = url:sub(1, b - 1)
            local bb = a:find(":")
            if bb then
                data.login = a:sub(1, bb - 1)
                data.password = a:sub(bb + 1)
            end
        end
        url = url:sub(b + 1)
    end
    local b = url:find(":")
    if b then
        data.host = url:sub(1, b - 1)
        data.port = tonumber(url:sub(b + 1))
    else
        data.host = url
        data.port = nil
    end

    return true
end

parse_url_format.http = function(url, data)
    local r = parse_url_format._http(url, data)
    if data.port == nil then data.port = 80 end
    return r
end

parse_url_format.https = function(url, data)
    local r = parse_url_format._http(url, data)
    if data.port == nil then data.port = 443 end
    return r
end

parse_url_format.hls = function(url, data)
    local r = parse_url_format._http(url, data)
    if data.port == nil then data.port = 80 end
    return r
end

parse_url_format.rtsp = function(url, data)
    local r = parse_url_format._http(url, data)
    if data.port == nil then data.port = 554 end
    return r
end

parse_url_format.np = function(url, data)
    local r = parse_url_format._http(url, data)
    if data.port == nil then data.port = 80 end
    return r
end

parse_url_format.srt = function(url, data)
    local q = url:find("%?")
    if q then
        data.query = url:sub(q + 1)
        url = url:sub(1, q - 1)
    end

    local colon = url:find(":")
    if colon then
        data.host = url:sub(1, colon - 1)
        data.port = tonumber(url:sub(colon + 1))
    else
        data.host = url
        data.port = nil
    end

    if not data.port then
        return false
    end

    return true
end

parse_url_format.dvb = function(url, data)
    data.addr = url
    return true
end

parse_url_format.file = function(url, data)
    data.filename = url
    return true
end

function parse_url(url)
    if not url then return nil end

    local original_url = url
    local hash = original_url:find("#")
    if hash then
        original_url = original_url:sub(1, hash - 1)
    end
    local data={}
    local b = url:find("://")
    if not b then return nil end
    data.format = url:sub(1, b - 1)
    url = url:sub(b + 3)
    data.source_url = original_url

    local b = url:find("#")
    local opts = nil
    if b then
        opts = url:sub(b + 1)
        url = url:sub(1, b - 1)
    end

    local _parse_url_format = parse_url_format[data.format]
    if _parse_url_format then
        if _parse_url_format(url, data) ~= true then
            return nil
        end
    else
        data.addr = url
    end

    if opts then
        local function parse_key_val(o)
            local k, v
            local x = o:find("=")
            if x then
                k = o:sub(1, x - 1)
                v = o:sub(x + 1)
            else
                k = o
                v = true
            end
            local x = k:find("%.")
            if x then
                local _k = k:sub(x + 1)
                k = k:sub(1, x - 1)
                if type(data[k]) ~= "table" then data[k] = {} end
                table.insert(data[k], { _k, v })
            else
                data[k] = v
            end
        end
        local p = 1
        while true do
            local x = opts:find("&", p)
            if x then
                parse_key_val(opts:sub(p, x - 1))
                p = x + 1
            else
                parse_key_val(opts:sub(p))
                break
            end
        end
    end

    return data
end

local function http_auth_bool(value, fallback)
    if value == nil then
        return fallback
    end
    if value == true or value == 1 or value == "1" or value == "true" then
        return true
    end
    if value == false or value == 0 or value == "0" or value == "false" then
        return false
    end
    return fallback
end

local function http_auth_list(value)
    if not value then
        return {}
    end
    if type(value) == "table" then
        return value
    end
    local out = {}
    local text = tostring(value)
    for item in text:gmatch("[^,%s]+") do
        table.insert(out, item)
    end
    return out
end

local function http_auth_has(list, value)
    if not value or value == "" then
        return false
    end
    for _, item in ipairs(list) do
        if item == value then
            return true
        end
    end
    return false
end

local function http_auth_realm()
    if not config or not config.get_setting then
        return "Astra"
    end
    local value = config.get_setting("http_auth_realm")
    if value == nil or value == "" then
        return "Astra"
    end
    return tostring(value)
end

function http_auth_check(request)
    if not config or not config.get_setting then
        return true, {}
    end
    local enabled = http_auth_bool(config.get_setting("http_auth_enabled"), false)

    local info = {
        basic = http_auth_bool(config.get_setting("http_auth_users"), true),
        realm = http_auth_realm(),
    }

    local ip = request and request.addr or ""
    local allow = http_auth_list(config.get_setting("http_auth_allow"))
    local deny = http_auth_list(config.get_setting("http_auth_deny"))

    if #deny > 0 and http_auth_has(deny, ip) then
        return false, info
    end
    if #allow > 0 and not http_auth_has(allow, ip) then
        return false, info
    end

    if not enabled then
        return true, info
    end

    local headers = request and request.headers or {}
    local auth = headers["authorization"] or headers["Authorization"] or ""
    local token = nil
    if auth:find("Bearer ") == 1 then
        token = auth:sub(8)
    end
    if not token and request and request.query then
        token = request.query.token or request.query.access_token
    end
    local tokens = http_auth_list(config.get_setting("http_auth_tokens"))
    if token and http_auth_has(tokens, token) then
        return true, info
    end

    if info.basic and auth:find("Basic ") == 1 then
        local raw = auth:sub(7)
        local decoded = base64.decode(raw or "")
        if decoded then
            local user, pass = decoded:match("^(.*):(.*)$")
            if user and pass then
                local verified = config.verify_user(user, pass)
                if verified then
                    return true, info
                end
            end
        end
    end

    return false, info
end

-- ooooo oooo   oooo oooooooooo ooooo  oooo ooooooooooo
--  888   8888o  88   888    888 888    88  88  888  88
--  888   88 888o88   888oooo88  888    88      888
--  888   88   8888   888        888    88      888
-- o888o o88o    88  o888o        888oo88      o888o

init_input_module = {}
kill_input_module = {}

function init_input(conf)
    local instance = { config = conf, }

    if not conf.name then
        log.error("[init_input] option 'name' is required")
        astra.abort()
    end

    if not init_input_module[conf.format] then
        log.error("[" .. conf.name .. "] unknown input format")
        astra.abort()
    end
    instance.input = init_input_module[conf.format](conf)
    if not instance.input then
        log.error("[" .. conf.name .. "] input init failed")
        return nil
    end
    instance.tail = instance.input

    if conf.pnr == nil then
        local function check_dependent()
            if conf.set_pnr ~= nil then return true end
            if conf.set_tsid ~= nil then return true end
            if conf.service_provider ~= nil then return true end
            if conf.service_name ~= nil then return true end
            if conf.no_sdt == true then return true end
            if conf.no_eit == true then return true end
            if conf.map then return true end
            if conf.filter then return true end
            if conf["filter~"] then return true end
            return false
        end
        if check_dependent() then conf.pnr = 0 end
    end

    if conf.pnr ~= nil then
        if conf.cam and conf.cam ~= true then conf.cas = true end

        instance.channel = channel({
            upstream = instance.tail:stream(),
            name = conf.name,
            pnr = conf.pnr,
            pid = conf.pid,
            no_sdt = conf.no_sdt,
            no_eit = conf.no_eit,
            cas = conf.cas,
            pass_sdt = conf.pass_sdt,
            pass_eit = conf.pass_eit,
            set_pnr = conf.set_pnr,
            set_tsid = conf.set_tsid,
            service_provider = conf.service_provider,
            service_name = conf.service_name,
            map = conf.map,
            filter = string.split(conf.filter, ","),
            ["filter~"] = string.split(conf["filter~"], ","),
            no_reload = conf.no_reload,
        })
        instance.tail = instance.channel
    end

    if conf.biss then
        instance.decrypt = decrypt({
            upstream = instance.tail:stream(),
            name = conf.name,
            biss = conf.biss,
        })
        instance.tail = instance.decrypt
    elseif conf.cam == true then
        -- DVB-CI
    elseif conf.cam then
        local function get_softcam()
            if type(conf.cam) == "table" then
                if conf.cam.cam then
                    return conf.cam
                end
            else
                if type(softcam_list) == "table" then
                    for _, i in ipairs(softcam_list) do
                        if tostring(i.__options.id) == conf.cam then return i end
                    end
                end
                local i = _G[tostring(conf.cam)]
                if type(i) == "table" and i.cam then return i end
            end
            log.error("[" .. conf.name .. "] cam is not found")
            return nil
        end
        local cam = get_softcam()
        if cam then
            local cas_pnr = nil
            if conf.pnr and conf.set_pnr then cas_pnr = conf.pnr end

            instance.decrypt = decrypt({
                upstream = instance.tail:stream(),
                name = conf.name,
                cam = cam:cam(),
                cas_data = conf.cas_data,
                cas_pnr = cas_pnr,
                disable_emm = conf.no_emm,
                ecm_pid = conf.ecm_pid,
                shift = conf.shift,
            })
            instance.tail = instance.decrypt
        end
    end

    return instance
end

function kill_input(instance)
    if not instance then return nil end

    instance.tail = nil

    kill_input_module[instance.config.format](instance.input, instance.config)
    instance.input = nil
    instance.config = nil

    instance.channel = nil
    instance.decrypt = nil
end

local function append_bridge_args(args, extra)
    if type(extra) == "table" then
        for _, value in ipairs(extra) do
            args[#args + 1] = tostring(value)
        end
    elseif type(extra) == "string" and extra ~= "" then
        args[#args + 1] = extra
    end
end

local function strip_url_hash(url)
    if not url or url == "" then
        return url
    end
    local hash = url:find("#")
    if hash then
        return url:sub(1, hash - 1)
    end
    return url
end

local function build_bridge_source_url(conf)
    if conf.url and conf.url ~= "" then
        return strip_url_hash(conf.url)
    end
    if conf.source_url and conf.source_url ~= "" then
        return strip_url_hash(conf.source_url)
    end
    local host = conf.host or conf.addr
    local port = conf.port
    if not host or not port then
        return nil
    end
    local url = conf.format .. "://" .. host .. ":" .. tostring(port)
    if conf.path and conf.path ~= "" then
        url = url .. conf.path
    end
    if conf.query and conf.query ~= "" then
        url = url .. "?" .. conf.query
    end
    return url
end

local function build_bridge_udp_url(conf, bridge_addr, bridge_port)
    local pkt_size = tonumber(conf.bridge_pkt_size) or 1316
    local url = "udp://" .. bridge_addr .. ":" .. tostring(bridge_port)
    if pkt_size > 0 then
        url = url .. "?pkt_size=" .. tostring(pkt_size)
    end
    return url
end

local function stop_bridge_process(conf)
    if conf.__bridge_proc then
        conf.__bridge_proc:terminate()
        conf.__bridge_proc:kill()
        conf.__bridge_proc:close()
        conf.__bridge_proc = nil
    end
end

-- ooooo         ooooo  oooo ooooooooo  oooooooooo
--  888           888    88   888    88o 888    888
--  888 ooooooooo 888    88   888    888 888oooo88
--  888           888    88   888    888 888
-- o888o           888oo88   o888ooo88  o888o

udp_input_instance_list = {}

init_input_module.udp = function(conf)
    local instance_id = tostring(conf.localaddr) .. "@" .. conf.addr .. ":" .. conf.port
    local instance = udp_input_instance_list[instance_id]

    if not instance then
        instance = { clients = 0, }
        udp_input_instance_list[instance_id] = instance

        instance.input = udp_input({
            addr = conf.addr, port = conf.port, localaddr = conf.localaddr,
            socket_size = conf.socket_size,
            renew = conf.renew,
            rtp = conf.rtp,
        })
    end

    instance.clients = instance.clients + 1
    return instance.input
end

kill_input_module.udp = function(module, conf)
    local instance_id = tostring(conf.localaddr) .. "@" .. conf.addr .. ":" .. conf.port
    local instance = udp_input_instance_list[instance_id]

    instance.clients = instance.clients - 1
    if instance.clients == 0 then
        instance.input = nil
        udp_input_instance_list[instance_id] = nil
    end
end

init_input_module.rtp = function(conf)
    conf.rtp = true
    return init_input_module.udp(conf)
end

kill_input_module.rtp = function(module, conf)
    kill_input_module.udp(module, conf)
end

-- ooooo         ooooooooooo ooooo ooooo       ooooooooooo
--  888           888    88   888   888         888    88
--  888 ooooooooo 888oo8      888   888         888ooo8
--  888           888         888   888      o  888    oo
-- o888o         o888o       o888o o888ooooo88 o888ooo8888

init_input_module.file = function(conf)
    conf.callback = function()
        log.error("[" .. conf.name .. "] end of file")
        if conf.on_error then conf.on_error() end
    end
    return file_input(conf)
end

kill_input_module.file = function(module)
    --
end

-- ooooo         ooooo ooooo ooooooooooo ooooooooooo oooooooooo
--  888           888   888  88  888  88 88  888  88  888    888
--  888 ooooooooo 888ooo888      888         888      888oooo88
--  888           888   888      888         888      888
-- o888o         o888o o888o    o888o       o888o    o888o

http_user_agent = "Astra"
http_input_instance_list = {}
https_input_instance_list = {}
https_bridge_port_map = {}

local function https_instance_key(conf)
    if conf.source_url and conf.source_url ~= "" then
        return conf.source_url
    end
    if conf.url and conf.url ~= "" then
        return conf.url
    end
    local host = conf.host or conf.addr or ""
    local port = conf.port or ""
    local path = conf.path or ""
    return tostring(conf.format or "https") .. "://" .. host .. ":" .. tostring(port) .. tostring(path)
end

local function hash_string(text)
    local h = 0
    if not text then
        return h
    end
    for i = 1, #text do
        h = (h * 131 + text:byte(i)) % 2147483647
    end
    return h
end

local function ensure_https_bridge_port(conf)
    local port = tonumber(conf.bridge_port)
    if port then
        return port
    end
    local key = https_instance_key(conf)
    if key == "" then
        return nil
    end
    local cached = https_bridge_port_map[key]
    if cached then
        conf.bridge_port = cached
        return cached
    end
    local base_port = 20000
    local range = 30000
    local start = base_port + (hash_string(key) % range)
    local bind_host = conf.bridge_addr or "127.0.0.1"
    for i = 0, range - 1 do
        local candidate = base_port + ((start - base_port + i) % range)
        local ok = true
        if utils and utils.can_bind then
            ok = utils.can_bind(bind_host, candidate)
        end
        if ok then
            https_bridge_port_map[key] = candidate
            conf.bridge_port = candidate
            return candidate
        end
    end
    return nil
end

init_input_module.http = function(conf)
    local instance_id = conf.host .. ":" .. conf.port .. conf.path
    local instance = http_input_instance_list[instance_id]

    if not instance then
        instance = { clients = 0, }
        http_input_instance_list[instance_id] = instance

        instance.on_error = function(message)
            log.error("[" .. conf.name .. "] " .. message)
            if conf.on_error then conf.on_error(message) end
        end

        if conf.ua and not conf.user_agent then
            conf.user_agent = conf.ua
        end

        local http_conf = {
            host = conf.host,
            port = conf.port,
            path = conf.path,
            stream = true,
            sync = conf.sync,
            buffer_size = conf.buffer_size,
            timeout = conf.timeout,
            sctp = conf.sctp,
            headers = {
                "User-Agent: " .. (conf.user_agent or http_user_agent),
                "Host: " .. conf.host .. ":" .. conf.port,
                "Connection: close",
            }
        }

        if conf.login and conf.password then
            local auth = base64.encode(conf.login .. ":" .. conf.password)
            table.insert(http_conf.headers, "Authorization: Basic " .. auth)
        end

        local timer_conf = {
            interval = 5,
            callback = function(self)
                instance.timeout:close()
                instance.timeout = nil

                if instance.request then instance.request:close() end
                instance.request = http_request(http_conf)
            end
        }

        http_conf.callback = function(self, response)
            if not response then
                instance.request:close()
                instance.request = nil
                instance.timeout = timer(timer_conf)

            elseif response.code == 200 then
                if instance.timeout then
                    instance.timeout:close()
                    instance.timeout = nil
                end

                instance.transmit:set_upstream(self:stream())

            elseif response.code == 301 or response.code == 302 then
                if instance.timeout then
                    instance.timeout:close()
                    instance.timeout = nil
                end

                instance.request:close()
                instance.request = nil

                local o = parse_url(response.headers["location"])
                if o then
                    http_conf.host = o.host
                    http_conf.port = o.port
                    http_conf.path = o.path
                    http_conf.headers[2] = "Host: " .. o.host .. ":" .. o.port

                    log.info("[" .. conf.name .. "] Redirect to http://" .. o.host .. ":" .. o.port .. o.path)
                    instance.request = http_request(http_conf)
                else
                    instance.on_error("HTTP Error: Redirect failed")
                    instance.timeout = timer(timer_conf)
                end

            else
                instance.request:close()
                instance.request = nil
                instance.on_error("HTTP Error: " .. response.code .. ":" .. response.message)
                instance.timeout = timer(timer_conf)
            end
        end

        instance.transmit = transmit({ instance_id = instance_id })
        instance.request = http_request(http_conf)
    end

    instance.clients = instance.clients + 1
    return instance.transmit
end

local function start_https_bridge(conf)
    if not process or type(process.spawn) ~= "function" then
        log.error("[" .. conf.name .. "] process module not available")
        return false
    end

    local bridge_port = ensure_https_bridge_port(conf)
    if not bridge_port then
        log.error("[" .. conf.name .. "] https bridge_port is required or no free port found")
        return false
    end

    local bridge_addr = conf.bridge_addr or "127.0.0.1"
    local source_url = build_bridge_source_url(conf)
    if not source_url then
        log.error("[" .. conf.name .. "] source url is required")
        return false
    end

    local udp_url = build_bridge_udp_url(conf, bridge_addr, bridge_port)
    local bin = resolve_tool_path("ffmpeg", {
        setting_key = "ffmpeg_path",
        env_key = "ASTRA_FFMPEG_PATH",
        prefer = conf.bridge_bin,
    })
    local args = {
        bin,
        "-hide_banner",
        "-nostdin",
        "-loglevel",
        conf.bridge_log_level or "warning",
    }
    local ua = conf.user_agent or conf.ua
    if ua and ua ~= "" then
        args[#args + 1] = "-user_agent"
        args[#args + 1] = tostring(ua)
    end
    append_bridge_args(args, conf.bridge_input_args)
    args[#args + 1] = "-i"
    args[#args + 1] = source_url
    args[#args + 1] = "-c"
    args[#args + 1] = "copy"
    args[#args + 1] = "-f"
    args[#args + 1] = "mpegts"
    append_bridge_args(args, conf.bridge_output_args)
    args[#args + 1] = udp_url

    local ok, proc = pcall(process.spawn, args)
    if not ok or not proc then
        log.error("[" .. conf.name .. "] https bridge spawn failed")
        return false
    end

    conf.__bridge_proc = proc
    conf.__bridge_args = args
    conf.__bridge_udp_conf = {
        addr = bridge_addr,
        port = bridge_port,
        localaddr = conf.bridge_localaddr or conf.localaddr,
        socket_size = tonumber(conf.bridge_socket_size) or conf.socket_size,
        renew = conf.renew,
    }
    return true
end

init_input_module.https = function(conf)
    local instance_id = https_instance_key(conf)
    local instance = https_input_instance_list[instance_id]
    if not instance then
        if conf.ua and not conf.user_agent then
            conf.user_agent = conf.ua
        end
        if not start_https_bridge(conf) then
            return nil
        end
        instance = { clients = 0, config = conf }
        https_input_instance_list[instance_id] = instance
    end

    instance.clients = instance.clients + 1
    return init_input_module.udp(conf.__bridge_udp_conf)
end

kill_input_module.https = function(module, conf)
    local instance_id = https_instance_key(conf)
    local instance = https_input_instance_list[instance_id]
    if not instance then
        return
    end

    instance.clients = instance.clients - 1
    if conf.__bridge_udp_conf then
        kill_input_module.udp(module, conf.__bridge_udp_conf)
    end
    if instance.clients <= 0 then
        stop_bridge_process(conf)
        https_input_instance_list[instance_id] = nil
    end
end

kill_input_module.http = function(module)
    local instance_id = module.__options.instance_id
    local instance = http_input_instance_list[instance_id]

    instance.clients = instance.clients - 1
    if instance.clients == 0 then
        if instance.timeout then
            instance.timeout:close()
            instance.timeout = nil
        end
        if instance.request then
            instance.request:close()
            instance.request = nil
        end
        instance.transmit = nil
        http_input_instance_list[instance_id] = nil
    end
end

-- ooooo         ooooo  oooo ooooo       ooooooooooo
--  888           888    88   888         888    88
--  888 ooooooooo 888    88   888         888ooo8
--  888           888    88   888      o  888    oo
-- o888o           888oo88   o888ooooo88 o888ooo8888

hls_input_instance_list = {}

local function hls_trim(s)
    return (s:gsub("^%s+", ""):gsub("%s+$", ""))
end

local function hls_base_dir(path)
    local dir = path:match("(.*/)")
    if not dir then return "/" end
    return dir
end

local function hls_build_base(conf)
    local host = conf.host
    if conf.port then host = host .. ":" .. conf.port end
    return "http://" .. host
end

local function hls_resolve_url(base_url, base_dir, ref)
    if ref:match("^https?://") then
        return ref
    end
    if ref:sub(1, 2) == "//" then
        return "http:" .. ref
    end
    if ref:sub(1, 1) == "/" then
        return base_url .. ref
    end
    return base_url .. base_dir .. ref
end

local function hls_parse_attributes(line)
    local attrs = {}
    for part in line:gmatch("([^,]+)") do
        local key, value = part:match("([^=]+)=(.*)")
        if key and value then
            attrs[hls_trim(key)] = hls_trim(value)
        end
    end
    return attrs
end

local function hls_parse_master(content, base_url, base_dir)
    local variants = {}
    local next_is_uri = false
    local current = nil

    for line in content:gmatch("[^\r\n]+") do
        line = hls_trim(line)
        if line ~= "" then
            if next_is_uri then
                current.uri = hls_resolve_url(base_url, base_dir, line)
                table.insert(variants, current)
                current = nil
                next_is_uri = false
            elseif line:find("#EXT%-X%-STREAM%-INF:") == 1 then
                local attrs = hls_parse_attributes(line:sub(19))
                current = { attrs = attrs }
                current.bandwidth = tonumber(attrs.BANDWIDTH) or 0
                next_is_uri = true
            end
        end
    end

    return variants
end

local function hls_parse_media(content, base_url, base_dir)
    local seq = 0
    local target_duration = 5
    local endlist = false
    local segments = {}
    local current = {}

    for line in content:gmatch("[^\r\n]+") do
        line = hls_trim(line)
        if line ~= "" then
            if line:find("#EXT%-X%-MEDIA%-SEQUENCE:") == 1 then
                seq = tonumber(line:sub(23)) or 0
            elseif line:find("#EXT%-X%-TARGETDURATION:") == 1 then
                target_duration = tonumber(line:sub(23)) or 5
            elseif line == "#EXT-X-ENDLIST" then
                endlist = true
            elseif line == "#EXT-X-DISCONTINUITY" then
                current.discontinuity = true
            elseif line:find("#EXTINF:") == 1 then
                current.duration = tonumber(line:sub(9)) or 0
            elseif line:sub(1, 1) ~= "#" then
                current.uri = hls_resolve_url(base_url, base_dir, line)
                current.seq = seq
                table.insert(segments, current)
                seq = seq + 1
                current = {}
            end
        end
    end

    return {
        segments = segments,
        target_duration = target_duration,
        endlist = endlist,
    }
end

local function hls_start_next_segment(instance)
    if instance.segment_request or #instance.queue == 0 then
        return
    end

    local item = table.remove(instance.queue, 1)
    if instance.queued then
        instance.queued[item.seq] = nil
    end
    instance.active_seq = item.seq

    local seg_conf = parse_url(item.uri)
    if not seg_conf or seg_conf.format ~= "http" then
        log.error("[hls] unsupported segment url: " .. item.uri)
        return
    end

    local headers = {
        "User-Agent: " .. (instance.config.user_agent or http_user_agent),
        "Host: " .. seg_conf.host .. ":" .. seg_conf.port,
        "Connection: close",
    }

    if seg_conf.login and seg_conf.password then
        local auth = base64.encode(seg_conf.login .. ":" .. seg_conf.password)
        table.insert(headers, "Authorization: Basic " .. auth)
    end

    local req = http_request({
        host = seg_conf.host,
        port = seg_conf.port,
        path = seg_conf.path,
        stream = true,
        headers = headers,
        callback = function(self, response)
            if not response then
                instance.segment_request = nil
                instance.last_seq = instance.active_seq
                instance.active_seq = nil
                hls_start_next_segment(instance)
                return
            end

            if response.code ~= 200 then
                log.error("[hls] segment http error: " .. response.code)
                self:close()
                instance.segment_request = nil
                return
            end

            instance.transmit:set_upstream(self:stream())
        end,
    })

    instance.segment_request = req
end

local function hls_schedule_refresh(instance, interval)
    if instance.timer then
        instance.timer:close()
        instance.timer = nil
    end

    instance.timer = timer({
        interval = interval,
        callback = function(self)
            self:close()
            instance.timer = nil
            if instance.running then
                instance.request_playlist()
            end
        end,
    })
end

local function hls_handle_playlist(instance, content)
    local base_url = hls_build_base(instance.playlist_conf)
    local base_dir = hls_base_dir(instance.playlist_conf.path)

    if content:find("#EXT%-X%-STREAM%-INF") then
        local variants = hls_parse_master(content, base_url, base_dir)
        if #variants == 0 then
            log.error("[hls] no variants found")
            return
        end

        table.sort(variants, function(a, b)
            return a.bandwidth > b.bandwidth
        end)

        local variant = variants[1]
        local vconf = parse_url(variant.uri)
        if not vconf or vconf.format ~= "http" then
            log.error("[hls] unsupported variant url")
            return
        end

        instance.playlist_conf = vconf
        instance.force_refresh = true
        return
    end

    local media = hls_parse_media(content, base_url, base_dir)
    for _, item in ipairs(media.segments) do
        if (not instance.last_seq or item.seq > instance.last_seq)
           and not instance.queued[item.seq]
        then
            table.insert(instance.queue, item)
            instance.queued[item.seq] = true
        end
    end

    hls_start_next_segment(instance)
    hls_schedule_refresh(instance, math.max(1, math.floor(media.target_duration / 2)))
end

local function hls_start(instance)
    instance.running = true

    function instance.request_playlist()
        if instance.playlist_request then
            return
        end

        local conf = instance.playlist_conf
        local headers = {
            "User-Agent: " .. (instance.config.user_agent or http_user_agent),
            "Host: " .. conf.host .. ":" .. conf.port,
            "Connection: close",
        }

        if conf.login and conf.password then
            local auth = base64.encode(conf.login .. ":" .. conf.password)
            table.insert(headers, "Authorization: Basic " .. auth)
        end

        instance.playlist_request = http_request({
            host = conf.host,
            port = conf.port,
            path = conf.path,
            headers = headers,
            callback = function(self, response)
                if response and response.code == 200 and response.content then
                    hls_handle_playlist(instance, response.content)
                elseif response then
                    log.error("[hls] playlist http error: " .. response.code)
                end

                if instance.playlist_request then
                    instance.playlist_request:close()
                    instance.playlist_request = nil
                end

                if instance.force_refresh then
                    instance.force_refresh = nil
                    instance.request_playlist()
                end
            end,
        })
    end

    instance.request_playlist()
end

local function hls_stop(instance)
    instance.running = false
    if instance.timer then
        instance.timer:close()
        instance.timer = nil
    end
    if instance.playlist_request then
        instance.playlist_request:close()
        instance.playlist_request = nil
    end
    if instance.segment_request then
        instance.segment_request:close()
        instance.segment_request = nil
    end
end

init_input_module.hls = function(conf)
    local instance_id = conf.host .. ":" .. conf.port .. conf.path
    local instance = hls_input_instance_list[instance_id]

    if not instance then
        if conf.ua and not conf.user_agent then
            conf.user_agent = conf.ua
        end
        instance = {
            clients = 0,
            config = conf,
            queue = {},
            queued = {},
            transmit = transmit({ instance_id = instance_id }),
            playlist_conf = {
                host = conf.host,
                port = conf.port,
                path = conf.path,
                login = conf.login,
                password = conf.password,
                format = "http",
            },
        }

        hls_input_instance_list[instance_id] = instance
        hls_start(instance)
    end

    instance.clients = instance.clients + 1
    return instance.transmit
end

kill_input_module.hls = function(module)
    local instance_id = module.__options.instance_id
    local instance = hls_input_instance_list[instance_id]
    if not instance then
        return
    end

    instance.clients = instance.clients - 1
    if instance.clients <= 0 then
        hls_stop(instance)
        hls_input_instance_list[instance_id] = nil
    end
end

local function start_bridge_input(conf, is_rtsp)
    if not process or type(process.spawn) ~= "function" then
        log.error("[" .. conf.name .. "] process module not available")
        return nil
    end

    local bridge_port = tonumber(conf.bridge_port)
    if not bridge_port then
        log.error("[" .. conf.name .. "] bridge_port is required")
        return nil
    end

    local bridge_addr = conf.bridge_addr or "127.0.0.1"
    local source_url = build_bridge_source_url(conf)
    if not source_url then
        log.error("[" .. conf.name .. "] source url is required")
        return nil
    end

    local udp_url = build_bridge_udp_url(conf, bridge_addr, bridge_port)
    local bin = resolve_tool_path("ffmpeg", {
        setting_key = "ffmpeg_path",
        env_key = "ASTRA_FFMPEG_PATH",
        prefer = conf.bridge_bin,
    })
    local args = {
        bin,
        "-hide_banner",
        "-nostdin",
        "-loglevel",
        conf.bridge_log_level or "warning",
    }
    if is_rtsp and conf.rtsp_transport then
        args[#args + 1] = "-rtsp_transport"
        args[#args + 1] = tostring(conf.rtsp_transport)
    end
    append_bridge_args(args, conf.bridge_input_args)
    args[#args + 1] = "-i"
    args[#args + 1] = source_url
    args[#args + 1] = "-c"
    args[#args + 1] = "copy"
    args[#args + 1] = "-f"
    args[#args + 1] = "mpegts"
    append_bridge_args(args, conf.bridge_output_args)
    args[#args + 1] = udp_url

    local ok, proc = pcall(process.spawn, args)
    if not ok or not proc then
        log.error("[" .. conf.name .. "] bridge spawn failed")
        return nil
    end

    conf.__bridge_proc = proc
    conf.__bridge_args = args
    conf.__bridge_udp_conf = {
        addr = bridge_addr,
        port = bridge_port,
        localaddr = conf.bridge_localaddr or conf.localaddr,
        socket_size = tonumber(conf.bridge_socket_size) or conf.socket_size,
        renew = conf.renew,
    }

    return init_input_module.udp(conf.__bridge_udp_conf)
end

init_input_module.srt = function(conf)
    return start_bridge_input(conf, false)
end

kill_input_module.srt = function(module, conf)
    stop_bridge_process(conf)
    if conf.__bridge_udp_conf then
        kill_input_module.udp(module, conf.__bridge_udp_conf)
        conf.__bridge_udp_conf = nil
    end
    conf.__bridge_args = nil
end

init_input_module.rtsp = function(conf)
    return start_bridge_input(conf, true)
end

kill_input_module.rtsp = function(module, conf)
    stop_bridge_process(conf)
    if conf.__bridge_udp_conf then
        kill_input_module.udp(module, conf.__bridge_udp_conf)
        conf.__bridge_udp_conf = nil
    end
    conf.__bridge_args = nil
end

-- ooooo         ooooooooo  ooooo  oooo oooooooooo
--  888           888    88o 888    88   888    888
--  888 ooooooooo 888    888  888  88    888oooo88
--  888           888    888   88888     888    888
-- o888o         o888ooo88      888     o888ooo888

dvb_input_instance_list = {}
dvb_list = nil

local function dvb_frontend_available(conf)
    local adapter = tonumber(conf.adapter)
    local device = tonumber(conf.device or 0)
    if adapter == nil or device == nil then
        return true
    end
    if conf.type and tostring(conf.type):lower() == "asi" then
        return true
    end
    local path = "/dev/dvb/adapter" .. tostring(adapter) .. "/frontend" .. tostring(device)
    local fp, err = io.open(path, "rb")
    if not fp then
        log.error("[dvb_tune] failed to open frontend " .. path .. " [" .. tostring(err) .. "]")
        return false
    end
    fp:close()
    return true
end

function dvb_tune(conf)
    if conf.mac then
        conf.adapter = nil
        conf.device = nil

        if dvb_list == nil then
            if dvbls then
                dvb_list = dvbls()
            else
                dvb_list = {}
            end
        end
        local mac = conf.mac:upper()
        for _, a in ipairs(dvb_list) do
            if a.mac == mac then
                log.info("[dvb_tune] adapter: " .. a.adapter .. "." .. a.device .. ". " ..
                         "MAC address: " .. mac)
                conf.adapter = a.adapter
                conf.device = a.device
                break
            end
        end

        if conf.adapter == nil then
            log.error("[dvb_tune] failed to get an adapter. MAC address: " .. mac)
            astra.abort()
        end
    else
        if conf.adapter == nil then
            log.error("[dvb_tune] option 'adapter' or 'mac' is required")
            astra.abort()
        end

        local a = string.split(tostring(conf.adapter), "%.")
        if #a == 1 then
            conf.adapter = tonumber(a[1])
            if conf.device == nil then conf.device = 0 end
        elseif #a == 2 then
            conf.adapter = tonumber(a[1])
            conf.device = tonumber(a[2])
        end
    end

    local instance_id = conf.adapter .. "." .. conf.device
    local instance = dvb_input_instance_list[instance_id]
    if not instance then
        if not dvb_frontend_available(conf) then
            return nil
        end
        if not conf.type then
            instance = dvb_input(conf)
            dvb_input_instance_list[instance_id] = instance
            return instance
        end

        if conf.tp then
            local a = string.split(conf.tp, ":")
            if #a ~= 3 then
                log.error("[dvb_tune " .. instance_id .. "] option 'tp' has wrong format")
                astra.abort()
            end
            conf.frequency, conf.polarization, conf.symbolrate = a[1], a[2], a[3]
        end

        if conf.lnb then
            local a = string.split(conf.lnb, ":")
            if #a ~= 3 then
                log.warning("[dvb_tune " .. instance_id .. "] option 'lnb' has wrong format, ignoring")
                conf.lnb = nil
                conf.lof1, conf.lof2, conf.slof = nil, nil, nil
            else
                conf.lof1, conf.lof2, conf.slof = a[1], a[2], a[3]
            end
        end

        if conf.unicable then
            local a = string.split(conf.unicable, ":")
            if #a ~= 2 then
                log.error("[dvb_tune " .. instance_id .. "] option 'unicable' has wrong format")
                astra.abort()
            end
            conf.uni_scr, conf.uni_frequency = a[1], a[2]
        end

        if conf.type == "S" and conf.s2 == true then conf.type = "S2" end
        if conf.type == "T" and conf.t2 == true then conf.type = "T2" end

        if conf.type:lower() == "asi" then
            instance = asi_input(conf)
        else
            instance = dvb_input(conf)
        end
        dvb_input_instance_list[instance_id] = instance
    end

    return instance
end

init_input_module.dvb = function(conf)
    local instance = nil

    if conf.addr == nil or #conf.addr == 0 then
        conf.channels = 0
        instance = dvb_tune(conf)
        if not instance then
            return nil
        end
        if instance.__options.channels ~= nil then
            instance.__options.channels = instance.__options.channels + 1
        end
    else
        local function get_dvb_tune()
            local adapter_addr = tostring(conf.addr)
            for _, i in pairs(dvb_input_instance_list) do
                if tostring(i.__options.id) == adapter_addr then
                    return i
                end
            end
            local i = _G[adapter_addr]
            local module_name = tostring(i)
            if  module_name == "dvb_input" or
                module_name == "asi_input" or
                module_name == "ddci"
            then
                return i
            end
            log.error("[" .. conf.name .. "] dvb is not found")
            return nil
        end
        instance = get_dvb_tune()
    end

    if not instance then
        return nil
    end

    if conf.cam == true and conf.pnr then
        instance:ca_set_pnr(conf.pnr, true)
    end

    return instance
end

kill_input_module.dvb = function(module, conf)
    if conf.cam == true and conf.pnr then
        module:ca_set_pnr(conf.pnr, false)
    end

    if module.__options.channels ~= nil then
        module.__options.channels = module.__options.channels - 1
        if module.__options.channels == 0 then
            module:close()
            local instance_id = module.__options.adapter .. "." .. module.__options.device
            dvb_input_instance_list[instance_id] = nil
        end
    end
end

-- ooooo         oooooooooo  ooooooooooo ooooo         ooooooo      o      ooooooooo
--  888           888    888  888    88   888        o888   888o   888      888    88o
--  888 ooooooooo 888oooo88   888ooo8     888        888     888  8  88     888    888
--  888           888  88o    888    oo   888      o 888o   o888 8oooo88    888    888
-- o888o         o888o  88o8 o888ooo8888 o888ooooo88   88ooo88 o88o  o888o o888ooo88

init_input_module.reload = function(conf)
    return transmit({
        timer = timer({
            interval = tonumber(conf.addr),
            callback = function(self)
                self:close()
                astra.reload()
            end,
        })
    })
end

kill_input_module.reload = function(module)
    module.__options.timer:close()
end

-- ooooo          oooooooo8 ooooooooooo   ooooooo  oooooooooo
--  888          888        88  888  88 o888   888o 888    888
--  888 ooooooooo 888oooooo     888     888     888 888oooo88
--  888                  888    888     888o   o888 888
-- o888o         o88oooo888    o888o      88ooo88  o888o

init_input_module.stop = function(conf)
    return transmit({})
end

kill_input_module.stop = function(module)
    --
end

-- ooooo         ooooooo      o      ooooooooo
--  888        o888   888o   888      888    88o
--  888        888     888  8  88     888    888
--  888      o 888o   o888 8oooo88    888    888
-- o888ooooo88   88ooo88 o88o  o888o o888ooo88

function astra_usage()
    log.info(astra_brand_version())
    print([[

Usage: astra APP [OPTIONS]

Available Applications:
    --stream            Astra Stream is a main application for
                        the digital television streaming
    --relay             Astra Relay  is an application for
                        the digital television relaying
                        via the HTTP protocol
    --analyze           Astra Analyze is a MPEG-TS stream analyzer
    --dvbls             DVB Adapters information list
    SCRIPT              launch Astra script

Astra Options:
    -h, --help          command line arguments
    -v, --version       version number
    --pid FILE          create PID-file
    --syslog NAME       send log messages to syslog
    --log FILE          write log to file
    --no-stdout         do not print log messages into console
    --color             colored log messages in console
    --debug             print debug messages
]])

    if _G.options_usage then
        print("Application Options:")
        print(_G.options_usage)
    end
    astra.exit()
end

function astra_version()
    log.info(astra_brand_version())
    astra.exit()
end

astra_options = {
    ["-h"] = function(idx)
        astra_usage()
        return 0
    end,
    ["--help"] = function(idx)
        astra_usage()
        return 0
    end,
    ["-v"] = function(idx)
        astra_version()
        return 0
    end,
    ["--version"] = function(idx)
        astra_version()
        return 0
    end,
    ["--pid"] = function(idx)
        pidfile(argv[idx + 1])
        return 1
    end,
    ["--syslog"] = function(idx)
        log.set({ syslog = argv[idx + 1] })
        return 1
    end,
    ["--log"] = function(idx)
        log.set({ filename = argv[idx + 1] })
        return 1
    end,
    ["--no-stdout"] = function(idx)
        log.set({ stdout = false })
        return 0
    end,
    ["--color"] = function(udx)
        log.set({ color = true })
        return 0
    end,
    ["--debug"] = function(idx)
        log.set({ debug = true })
        return 0
    end,
}

function astra_parse_options(idx)
    function set_option(idx)
        local a = argv[idx]
        local c = nil

        if _G.options then c = _G.options[a] end
        if not c then c = astra_options[a] end
        if not c and _G.options then c = _G.options["*"] end

        if not c then return -1 end
        local ac = c(idx)
        if ac == -1 then return -1 end
        idx = idx + ac + 1
        return idx
    end

    while idx <= #argv do
        local next_idx = set_option(idx)
        if next_idx == -1 then
            print("unknown option: " .. argv[idx])
            astra.exit()
        end
        idx = next_idx
    end
end

-- Log buffer for web UI
if not log_store then
    log_store = {
        entries = {},
        next_id = 1,
        max_entries = 2000,
        retention_sec = 86400,
    }
end

local function log_store_prune()
    local retention = tonumber(log_store.retention_sec) or 0
    if retention > 0 then
        local cutoff = os.time() - retention
        while #log_store.entries > 0 do
            local ts = tonumber(log_store.entries[1].ts) or 0
            if ts >= cutoff then
                break
            end
            table.remove(log_store.entries, 1)
        end
    end
    local max_entries = tonumber(log_store.max_entries) or 0
    if max_entries > 0 then
        while #log_store.entries > max_entries do
            table.remove(log_store.entries, 1)
        end
    end
end

function log_store.configure(opts)
    if type(opts) ~= "table" then
        return
    end
    if opts.max_entries ~= nil then
        local value = tonumber(opts.max_entries)
        if value then
            value = math.floor(value)
            if value < 0 then
                value = 0
            end
            log_store.max_entries = value
        end
    end
    if opts.retention_sec ~= nil then
        local value = tonumber(opts.retention_sec)
        if value then
            value = math.floor(value)
            if value < 0 then
                value = 0
            end
            log_store.retention_sec = value
        end
    end
    log_store_prune()
end

local function log_store_add(level, message)
    local entry = {
        id = log_store.next_id,
        ts = os.time(),
        level = level,
        message = tostring(message),
    }
    log_store.next_id = log_store.next_id + 1
    table.insert(log_store.entries, entry)
    log_store_prune()
end

function log_store.list(since_id, limit, level, text, stream_id)
    log_store_prune()
    local out = {}
    local max_items = tonumber(limit) or 200
    local since = tonumber(since_id) or 0
    local level_filter = level and tostring(level):lower() or nil
    if level_filter == "" or level_filter == "all" then
        level_filter = nil
    end
    local text_filter = text and tostring(text):lower() or nil
    if text_filter == "" then
        text_filter = nil
    end
    local stream_filter = stream_id and tostring(stream_id):lower() or nil
    if stream_filter == "" then
        stream_filter = nil
    end
    for _, entry in ipairs(log_store.entries) do
        if entry.id > since then
            local ok = true
            if level_filter and tostring(entry.level):lower() ~= level_filter then
                ok = false
            end
            if ok and text_filter then
                local msg = tostring(entry.message):lower()
                if not msg:find(text_filter, 1, true) then
                    ok = false
                end
            end
            if ok and stream_filter then
                local msg = tostring(entry.message):lower()
                local exact = "[stream " .. stream_filter .. "]"
                local transcode = "[transcode " .. stream_filter .. "]"
                if not msg:find(exact, 1, true)
                    and not msg:find(transcode, 1, true)
                    and not msg:find(stream_filter, 1, true) then
                    ok = false
                end
            end
            if ok then
                table.insert(out, entry)
                if #out >= max_items then
                    break
                end
            end
        end
    end
    return out
end

-- Access log buffer for HTTP/HLS clients
if not access_log then
    access_log = {
        entries = {},
        next_id = 1,
        max_entries = 2000,
        retention_sec = 86400,
    }
end

local function access_log_prune()
    local retention = tonumber(access_log.retention_sec) or 0
    if retention > 0 then
        local cutoff = os.time() - retention
        while #access_log.entries > 0 do
            local ts = tonumber(access_log.entries[1].ts) or 0
            if ts >= cutoff then
                break
            end
            table.remove(access_log.entries, 1)
        end
    end
    local max_entries = tonumber(access_log.max_entries) or 0
    if max_entries > 0 then
        while #access_log.entries > max_entries do
            table.remove(access_log.entries, 1)
        end
    end
end

function access_log.configure(opts)
    if type(opts) ~= "table" then
        return
    end
    if opts.max_entries ~= nil then
        local value = tonumber(opts.max_entries)
        if value then
            value = math.floor(value)
            if value < 0 then
                value = 0
            end
            access_log.max_entries = value
        end
    end
    if opts.retention_sec ~= nil then
        local value = tonumber(opts.retention_sec)
        if value then
            value = math.floor(value)
            if value < 0 then
                value = 0
            end
            access_log.retention_sec = value
        end
    end
    access_log_prune()
end

function access_log.add(entry)
    if type(entry) ~= "table" then
        return
    end
    local item = {
        id = access_log.next_id,
        ts = entry.ts or os.time(),
        event = entry.event or "connect",
        protocol = entry.protocol or "",
        stream_id = entry.stream_id,
        stream_name = entry.stream_name,
        ip = entry.ip,
        login = entry.login,
        user_agent = entry.user_agent,
        path = entry.path,
        reason = entry.reason,
    }
    access_log.next_id = access_log.next_id + 1
    table.insert(access_log.entries, item)
    access_log_prune()
end

function access_log.list(since_id, limit, event, stream_id, ip, login, text)
    access_log_prune()
    local out = {}
    local max_items = tonumber(limit) or 200
    local since = tonumber(since_id) or 0
    local event_filter = event and tostring(event):lower() or nil
    if event_filter == "" or event_filter == "all" then
        event_filter = nil
    end
    local stream_filter = stream_id and tostring(stream_id):lower() or nil
    if stream_filter == "" then
        stream_filter = nil
    end
    local ip_filter = ip and tostring(ip):lower() or nil
    if ip_filter == "" then
        ip_filter = nil
    end
    local login_filter = login and tostring(login):lower() or nil
    if login_filter == "" then
        login_filter = nil
    end
    local text_filter = text and tostring(text):lower() or nil
    if text_filter == "" then
        text_filter = nil
    end

    local function matches(needle, value)
        if not needle then
            return true
        end
        if not value then
            return false
        end
        return tostring(value):lower():find(needle, 1, true) ~= nil
    end

    for _, entry in ipairs(access_log.entries) do
        if entry.id > since then
            local ok = true
            if event_filter and tostring(entry.event):lower() ~= event_filter then
                ok = false
            end
            if ok and stream_filter then
                if not matches(stream_filter, entry.stream_id)
                    and not matches(stream_filter, entry.stream_name) then
                    ok = false
                end
            end
            if ok and ip_filter and not matches(ip_filter, entry.ip) then
                ok = false
            end
            if ok and login_filter and not matches(login_filter, entry.login) then
                ok = false
            end
            if ok and text_filter then
                local hay = table.concat({
                    entry.stream_name or "",
                    entry.stream_id or "",
                    entry.ip or "",
                    entry.login or "",
                    entry.user_agent or "",
                    entry.path or "",
                    entry.protocol or "",
                    entry.event or "",
                }, " ")
                if not matches(text_filter, hay) then
                    ok = false
                end
            end
            if ok then
                table.insert(out, entry)
                if #out >= max_items then
                    break
                end
            end
        end
    end
    return out
end

local function join_log_message(first, ...)
    if select("#", ...) == 0 then
        return tostring(first)
    end
    local parts = { tostring(first) }
    for i = 1, select("#", ...) do
        parts[#parts + 1] = tostring(select(i, ...))
    end
    return table.concat(parts, " ")
end

local function wrap_logger(level)
    if not log or type(log[level]) ~= "function" then
        return
    end
    local original = log[level]
    log[level] = function(...)
        local message = join_log_message(...)
        log_store_add(level, message)
        return original(...)
    end
end

wrap_logger("error")
wrap_logger("warning")
wrap_logger("notice")
wrap_logger("info")
wrap_logger("debug")
