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

-- Внутренний источник stream://<id> для использования в MPTS.
parse_url_format.stream = function(url, data)
    if not url or url == "" then
        return false
    end
    data.stream_id = url
    data.addr = url
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
        -- Support legacy/misused option separator "#" inside the fragment.
        -- Historically Astra uses a single "#k=v&k2=v2" fragment, but configs and
        -- UI sometimes use "#k=v#k2=v2". Treat extra "#" as "&" separators.
        opts = opts:gsub("#", "&")
        url = url:sub(1, b - 1)
    end
    if not opts and (data.format == "udp" or data.format == "rtp") then
        -- Historically Astra uses "#k=v" for URL options, but ffmpeg-style UDP URLs often
        -- use "?k=v". Support both to avoid "invalid input format" on common configs.
        local q = url:find("%?")
        if q then
            opts = url:sub(q + 1)
            url = url:sub(1, q - 1)
        end
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
            if not o or o == "" then
                return
            end
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

    -- Важно: некоторые IPTV-панели используют путь вида `/play/...` на внешних хостах.
    -- Поэтому auto-`sync=1` включаем только для "локального" TS fanout (Astra endpoints),
    -- иначе можно ухудшить стабильность приёма внешних HTTP-TS источников.
    if (data.format == "http" or data.format == "https") and data.path and data.sync == nil then
        local path_only = data.path:match("^(.-)%?") or data.path
        local is_fanout = (path_only:sub(1, 6) == "/play/")
            or (path_only:sub(1, 8) == "/stream/")
            or (path_only:sub(1, 6) == "/live/")
        if is_fanout then
            local host = tostring(data.host or ""):lower()
            local local_host = (host == "localhost") or (host == "::1") or (host:match("^127%.") ~= nil)
            local http_port = tonumber(config and config.get_setting and config.get_setting("http_port") or nil)
            local same_port = (http_port ~= nil) and (tonumber(data.port) == http_port)
            if local_host or same_port then
                data.sync = 1
            end
        end
    end

    return data
end

local NET_RESILIENCE_DEFAULTS = {
    connect_timeout_ms = 3000,
    read_timeout_ms = 8000,
    stall_timeout_ms = 5000,
    max_retries = 10,
    backoff_min_ms = 500,
    backoff_max_ms = 10000,
    backoff_jitter_pct = 20,
    cooldown_sec = 30,
    low_speed_limit_bytes_sec = 1024,
    low_speed_time_sec = 5,
    keepalive = false,
}

local NET_RESILIENCE_KEYS = {
    "connect_timeout_ms",
    "read_timeout_ms",
    "stall_timeout_ms",
    "max_retries",
    "backoff_min_ms",
    "backoff_max_ms",
    "backoff_jitter_pct",
    "cooldown_sec",
    "low_speed_limit_bytes_sec",
    "low_speed_time_sec",
    "user_agent",
    "keepalive",
    "dns_cache_ttl_sec",
}

-- Профили устойчивости сети для HTTP/HLS входов. Важно: по умолчанию выключено,
-- чтобы не менять поведение старых конфигов без явного включения.
	local INPUT_RESILIENCE_DEFAULTS = {
	    enabled = false,
	    default_profile = "wan",
	    -- Дефолты для auto-тюнинга (net_auto_*). Применяются только в profile-mode.
	    -- Если input уже содержит net_auto / net_auto_* опции, они имеют приоритет.
	    net_auto_defaults = {
	        dc = { enabled = false },
	        wan = { enabled = false },
	        bad = {
	            enabled = true,
	            max_level = 4,
	            relax_sec = 180,
	            window_sec = 25,
	            min_interval_sec = 5,
	            burst_threshold = 3,
	        },
	        max = {
	            enabled = true,
	            max_level = 6,
	            relax_sec = 600,
	            window_sec = 60,
	            min_interval_sec = 10,
	            burst_threshold = 1,
	        },
	        superbad = {
	            enabled = true,
	            max_level = 8,
	            relax_sec = 900,
	            window_sec = 120,
	            min_interval_sec = 10,
	            burst_threshold = 1,
	        },
	    },
	    profiles = {
	        dc = {
	            connect_timeout_ms = 2500,
	            read_timeout_ms = 8000,
            stall_timeout_ms = 4000,
            max_retries = 0,
            backoff_min_ms = 300,
            backoff_max_ms = 4000,
            backoff_jitter_pct = 20,
            cooldown_sec = 10,
            low_speed_limit_bytes_sec = 32768,
            low_speed_time_sec = 4,
            keepalive = true,
            user_agent = "Astral/1.0",
        },
        wan = {
            connect_timeout_ms = 5000,
            read_timeout_ms = 15000,
            stall_timeout_ms = 7000,
            max_retries = 0,
            backoff_min_ms = 700,
            backoff_max_ms = 10000,
            backoff_jitter_pct = 25,
            cooldown_sec = 20,
            low_speed_limit_bytes_sec = 16384,
            low_speed_time_sec = 6,
            keepalive = true,
            user_agent = "Astral/1.0",
        },
	        bad = {
	            connect_timeout_ms = 8000,
	            read_timeout_ms = 25000,
	            stall_timeout_ms = 10000,
	            max_retries = 0,
            backoff_min_ms = 1000,
            backoff_max_ms = 20000,
            backoff_jitter_pct = 30,
            cooldown_sec = 45,
	            low_speed_limit_bytes_sec = 8192,
	            low_speed_time_sec = 10,
	            keepalive = true,
	            user_agent = "VLC/3.0.20",
	        },
	        max = {
	            connect_timeout_ms = 12000,
	            read_timeout_ms = 40000,
            stall_timeout_ms = 20000,
            max_retries = 0,
            backoff_min_ms = 1500,
            backoff_max_ms = 30000,
            backoff_jitter_pct = 35,
            cooldown_sec = 60,
	            low_speed_limit_bytes_sec = 4096,
	            low_speed_time_sec = 15,
	            keepalive = true,
	            user_agent = "VLC/3.0.20",
	        },
	        superbad = {
	            -- Крайне нестабильные источники: делаем запас по таймаутам + низкий low-speed,
	            -- а "запас" по стабильности достигается в основном jitter буфером.
	            connect_timeout_ms = 20000,
	            read_timeout_ms = 60000,
	            -- Желательно не ждать дольше, чем target jitter buffer.
	            stall_timeout_ms = 20000,
	            max_retries = 0,
	            backoff_min_ms = 2000,
	            backoff_max_ms = 60000,
	            backoff_jitter_pct = 40,
	            cooldown_sec = 90,
	            low_speed_limit_bytes_sec = 2048,
	            low_speed_time_sec = 25,
	            keepalive = true,
	            user_agent = "VLC/3.0.20",
	        },
	    },
	    hls_defaults = {
	        max_segments = 10,
        max_gap_segments = 3,
        segment_retries = 3,
        max_parallel = 1,
    },
	    jitter_defaults_ms = {
	        dc = 200,
	        wan = 400,
	        -- Для нестабильных HTTP-TS/HLS источников лучше иметь ощутимый запас буфера,
	        -- иначе клиент видит частые паузы на коротких сетевых дырах.
	        bad = 2000,
	        max = 3000,
	        -- "С запасом" для источников, которые могут подвисать на десятки секунд.
	        -- Даёт стабильное вещание ценой увеличения задержки.
	        superbad = 20000,
	    },
	    -- Оценка ожидаемого битрейта для авто-расчёта лимита jitter буфера (MB).
	    jitter_assumed_mbps = {
	        dc = 20,
	        wan = 12,
	        bad = 16,
	        max = 20,
	        superbad = 20,
	    },
	    -- Жёсткий авто-лимит памяти jitter буфера (MB) при включённых профилях.
	    jitter_max_auto_mb = 64,
	    max_active_resilient_inputs = 50,
	}

local function copy_shallow(tbl)
    if type(tbl) ~= "table" then
        return {}
    end
    local out = {}
    for k, v in pairs(tbl) do
        out[k] = v
    end
    return out
end

local function normalize_net_profile(value)
    if value == nil then
        return nil
    end
    local s = tostring(value or ""):lower()
    if s == "dc" or s == "wan" or s == "bad" or s == "max" or s == "superbad" then
        return s
    end
    return nil
end

local function get_performance_profile()
    local value = read_setting("performance_profile")
    if value == nil then
        return "compat"
    end
    local profile = tostring(value or ""):lower()
    if profile == "mass" or profile == "low_latency" or profile == "compat" then
        return profile
    end
    return "compat"
end

local function profile_playout_max_buffer_default_mb()
    local profile = get_performance_profile()
    if profile == "mass" then
        return 12
    elseif profile == "low_latency" then
        return 8
    end
    return 16
end

local function apply_performance_profile_input_resilience_defaults(out)
    if type(out) ~= "table" then
        return
    end
    local profile = get_performance_profile()
    if profile == "compat" then
        return
    end
    if type(out.hls_defaults) == "table" then
        if profile == "mass" then
            out.hls_defaults.max_segments = math.min(tonumber(out.hls_defaults.max_segments) or 10, 8)
            out.hls_defaults.max_gap_segments = math.min(tonumber(out.hls_defaults.max_gap_segments) or 3, 2)
            out.hls_defaults.segment_retries = math.min(tonumber(out.hls_defaults.segment_retries) or 3, 2)
        elseif profile == "low_latency" then
            out.hls_defaults.max_segments = math.min(tonumber(out.hls_defaults.max_segments) or 10, 6)
            out.hls_defaults.max_gap_segments = math.min(tonumber(out.hls_defaults.max_gap_segments) or 3, 2)
            out.hls_defaults.segment_retries = math.min(tonumber(out.hls_defaults.segment_retries) or 3, 1)
        end
        if tonumber(out.hls_defaults.max_parallel) == nil or tonumber(out.hls_defaults.max_parallel) < 1 then
            out.hls_defaults.max_parallel = 1
        end
    end

    if profile == "mass" then
        out.jitter_max_auto_mb = math.min(tonumber(out.jitter_max_auto_mb) or 64, 32)
    elseif profile == "low_latency" then
        out.jitter_max_auto_mb = math.min(tonumber(out.jitter_max_auto_mb) or 64, 16)
    end
end

local function get_input_resilience_settings()
    local raw = nil
    if config and config.get_setting then
        local value = config.get_setting("input_resilience")
        if type(value) == "table" then
            raw = value
        end
    end

    local out = {
        enabled = INPUT_RESILIENCE_DEFAULTS.enabled == true,
        default_profile = INPUT_RESILIENCE_DEFAULTS.default_profile,
	        profiles = {
	            dc = copy_shallow(INPUT_RESILIENCE_DEFAULTS.profiles.dc),
	            wan = copy_shallow(INPUT_RESILIENCE_DEFAULTS.profiles.wan),
	            bad = copy_shallow(INPUT_RESILIENCE_DEFAULTS.profiles.bad),
	            max = copy_shallow(INPUT_RESILIENCE_DEFAULTS.profiles.max),
	            superbad = copy_shallow(INPUT_RESILIENCE_DEFAULTS.profiles.superbad),
	        },
	        net_auto_defaults = {
	            dc = copy_shallow(INPUT_RESILIENCE_DEFAULTS.net_auto_defaults.dc),
	            wan = copy_shallow(INPUT_RESILIENCE_DEFAULTS.net_auto_defaults.wan),
	            bad = copy_shallow(INPUT_RESILIENCE_DEFAULTS.net_auto_defaults.bad),
	            max = copy_shallow(INPUT_RESILIENCE_DEFAULTS.net_auto_defaults.max),
	            superbad = copy_shallow(INPUT_RESILIENCE_DEFAULTS.net_auto_defaults.superbad),
	        },
	        hls_defaults = copy_shallow(INPUT_RESILIENCE_DEFAULTS.hls_defaults),
	        jitter_defaults_ms = copy_shallow(INPUT_RESILIENCE_DEFAULTS.jitter_defaults_ms),
	        jitter_assumed_mbps = copy_shallow(INPUT_RESILIENCE_DEFAULTS.jitter_assumed_mbps),
	        jitter_max_auto_mb = INPUT_RESILIENCE_DEFAULTS.jitter_max_auto_mb,
        max_active_resilient_inputs = INPUT_RESILIENCE_DEFAULTS.max_active_resilient_inputs,
    }

    apply_performance_profile_input_resilience_defaults(out)

    if type(raw) ~= "table" then
        return out
    end

    if raw.enabled ~= nil then
        out.enabled = raw.enabled == true
    end

    local dp = normalize_net_profile(raw.default_profile)
    if dp then
        out.default_profile = dp
    end

    if raw.max_active_resilient_inputs ~= nil then
        local n = tonumber(raw.max_active_resilient_inputs)
        if n ~= nil and n >= 0 then
            out.max_active_resilient_inputs = math.floor(n)
        end
    end

	    if type(raw.profiles) == "table" then
	        for _, name in ipairs({ "dc", "wan", "bad", "max", "superbad" }) do
	            local p = raw.profiles[name]
	            if type(p) == "table" then
	                for k, v in pairs(p) do
	                    out.profiles[name][k] = v
	                end
	            end
	        end
	    end
	
	    if type(raw.net_auto_defaults) == "table" then
	        for _, name in ipairs({ "dc", "wan", "bad", "max", "superbad" }) do
	            local p = raw.net_auto_defaults[name]
	            if type(p) == "table" then
	                for k, v in pairs(p) do
	                    out.net_auto_defaults[name][k] = v
	                end
	            end
	        end
	    end

	    if type(raw.hls_defaults) == "table" then
	        for k, v in pairs(raw.hls_defaults) do
	            out.hls_defaults[k] = v
        end
    end

    if type(raw.jitter_defaults_ms) == "table" then
        for k, v in pairs(raw.jitter_defaults_ms) do
            out.jitter_defaults_ms[k] = v
        end
    end

    if type(raw.jitter_assumed_mbps) == "table" then
        for k, v in pairs(raw.jitter_assumed_mbps) do
            out.jitter_assumed_mbps[k] = v
        end
    end

    if raw.jitter_max_auto_mb ~= nil then
        local n = tonumber(raw.jitter_max_auto_mb)
        if n ~= nil and n > 0 then
            out.jitter_max_auto_mb = math.floor(n)
        end
    end

    return out
end

local function resolve_input_resilience(conf)
    local settings = get_input_resilience_settings()
    local configured = normalize_net_profile(conf and conf.net_profile)
    local enabled = (settings.enabled == true) or (configured ~= nil)
    local effective = configured or settings.default_profile or "wan"
    if not normalize_net_profile(effective) then
        effective = "wan"
    end

    local base = nil
    if type(settings.profiles) == "table" then
        base = settings.profiles[effective]
    end
    if type(base) ~= "table" then
        base = settings.profiles.wan or INPUT_RESILIENCE_DEFAULTS.profiles.wan
    end

    local jitter_ms = nil
    if type(settings.jitter_defaults_ms) == "table" then
        jitter_ms = tonumber(settings.jitter_defaults_ms[effective])
    end
    if jitter_ms ~= nil and jitter_ms < 0 then
        jitter_ms = nil
    end

    local hls_defaults = nil
    if type(settings.hls_defaults) == "table" then
        hls_defaults = settings.hls_defaults
    end

	    return {
	        enabled = enabled,
	        profile_configured = configured,
	        profile_effective = effective,
	        net_defaults = base,
	        jitter_default_ms = jitter_ms,
	        jitter_assumed_mbps = settings.jitter_assumed_mbps,
	        jitter_max_auto_mb = settings.jitter_max_auto_mb,
	        net_auto_defaults = type(settings.net_auto_defaults) == "table" and settings.net_auto_defaults[effective] or nil,
	        hls_defaults = hls_defaults,
	    }
	end

local function net_bool(value)
    if value == nil then
        return nil
    end
    if value == true or value == 1 or value == "1" or value == "true" then
        return true
    end
    if value == false or value == 0 or value == "0" or value == "false" then
        return false
    end
    return nil
end

local function net_number(value)
    if value == nil then
        return nil
    end
    local num = tonumber(value)
    if num == nil or num < 0 then
        return nil
    end
    return num
end

local function net_has_values(tbl)
    if type(tbl) ~= "table" then
        return false
    end
    for _, key in ipairs(NET_RESILIENCE_KEYS) do
        if tbl[key] ~= nil then
            return true
        end
    end
    return false
end

	local function apply_auto_jitter_max_mb(conf, res)
    if not res or res.enabled ~= true then
        return
    end
    if conf.jitter_max_buffer_mb ~= nil or conf.max_buffer_mb ~= nil then
        return
    end
    local jitter_ms = tonumber(conf.jitter_buffer_ms or conf.jitter_ms)
    if not jitter_ms or jitter_ms <= 0 then
        return
    end

    local assumed_mbps = nil
    if type(res.jitter_assumed_mbps) == "table" then
        assumed_mbps = tonumber(res.jitter_assumed_mbps[res.profile_effective])
    end
    if not assumed_mbps or assumed_mbps <= 0 then
        assumed_mbps = 10
    end

	    -- Небольшой запас по памяти помогает переживать burst delivery и колебания битрейта.
	    -- Это только верхний лимит; фактический расход ~= bitrate * jitter_ms.
	    local safety = 4
	    local bytes = (jitter_ms / 1000) * (assumed_mbps * 1000 * 1000 / 8) * safety
	    local mb = math.ceil(bytes / (1024 * 1024))
	    if mb < 8 then
	        mb = 8
	    end

    local max_auto = tonumber(res.jitter_max_auto_mb) or 32
    if max_auto < 4 then
        max_auto = 4
    end
    if mb > max_auto then
        mb = max_auto
    end

	    conf.jitter_max_buffer_mb = mb
	end

	local function apply_profile_net_auto_defaults(conf, res)
	    if not conf or not res or res.enabled ~= true then
	        return
	    end
	    -- Если net_auto задан явно (включен или отключен) — не трогаем.
	    if conf.net_auto ~= nil then
	        return
	    end
	    local d = res.net_auto_defaults
	    if type(d) ~= "table" or d.enabled ~= true then
	        return
	    end
	    conf.net_auto = true
	    if conf.net_auto_max_level == nil and d.max_level ~= nil then
	        conf.net_auto_max_level = d.max_level
	    end
	    if conf.net_auto_relax_sec == nil and d.relax_sec ~= nil then
	        conf.net_auto_relax_sec = d.relax_sec
	    end
	    if conf.net_auto_window_sec == nil and d.window_sec ~= nil then
	        conf.net_auto_window_sec = d.window_sec
	    end
	    if conf.net_auto_min_interval_sec == nil and d.min_interval_sec ~= nil then
	        conf.net_auto_min_interval_sec = d.min_interval_sec
	    end
	    if conf.net_auto_burst == nil and conf.net_auto_burst_threshold == nil and d.burst_threshold ~= nil then
	        conf.net_auto_burst = d.burst_threshold
	    end
	end

local function net_auto_enabled(conf)
    return net_bool(conf and conf.net_auto) == true
end

local function net_auto_init(conf, base_cfg)
    if not net_auto_enabled(conf) or type(base_cfg) ~= "table" then
        return nil
    end
    local max_level = tonumber(conf.net_auto_max_level) or 3
    if max_level < 0 then max_level = 0 end
    local relax_sec = tonumber(conf.net_auto_relax_sec) or 120
    if relax_sec < 10 then relax_sec = 10 end
    local window_sec = tonumber(conf.net_auto_window_sec) or 30
    if window_sec < 5 then window_sec = 5 end
    local min_interval = tonumber(conf.net_auto_min_interval_sec) or 5
    if min_interval < 1 then min_interval = 1 end
    local burst_threshold = tonumber(conf.net_auto_burst or conf.net_auto_burst_threshold) or 2
    if burst_threshold < 1 then burst_threshold = 1 end
    return {
        enabled = true,
        level = 0,
        max_level = math.floor(max_level),
        relax_sec = math.floor(relax_sec),
        window_sec = math.floor(window_sec),
        min_interval_sec = math.floor(min_interval),
        burst_threshold = math.floor(burst_threshold),
        base = copy_shallow(base_cfg),
        window_ts = nil,
        error_burst = 0,
        last_error_ts = nil,
        last_ok_ts = os.time(),
        last_change_ts = os.time(),
        last_change_reason = nil,
    }
end

local function net_auto_tune_cfg(base_cfg, level)
    local base = base_cfg or NET_RESILIENCE_DEFAULTS
    local out = copy_shallow(base)
    local lvl = tonumber(level) or 0
    if lvl < 0 then lvl = 0 end
    local mult = 1 + (0.5 * lvl)
    local mult_conn = 1 + (0.25 * lvl)

    local ct = tonumber(base.connect_timeout_ms) or NET_RESILIENCE_DEFAULTS.connect_timeout_ms
    local rt = tonumber(base.read_timeout_ms) or NET_RESILIENCE_DEFAULTS.read_timeout_ms
    local st = tonumber(base.stall_timeout_ms) or NET_RESILIENCE_DEFAULTS.stall_timeout_ms
    local ls_time = tonumber(base.low_speed_time_sec) or NET_RESILIENCE_DEFAULTS.low_speed_time_sec
    local ls_limit = tonumber(base.low_speed_limit_bytes_sec) or NET_RESILIENCE_DEFAULTS.low_speed_limit_bytes_sec
    local bo_min = tonumber(base.backoff_min_ms) or NET_RESILIENCE_DEFAULTS.backoff_min_ms
    local bo_max = tonumber(base.backoff_max_ms) or NET_RESILIENCE_DEFAULTS.backoff_max_ms

    out.connect_timeout_ms = math.floor(ct * mult_conn)
    out.read_timeout_ms = math.floor(rt * mult)
    -- stall_timeout_ms не увеличиваем: при росте уровня auto мы хотим быстрее отлипать
    -- от подвисших соединений, а не ждать 60-120 секунд без данных.
    out.stall_timeout_ms = math.floor(st)
    out.low_speed_time_sec = math.floor(ls_time * mult)
    out.low_speed_limit_bytes_sec = math.max(512, math.floor(ls_limit * (0.7 ^ lvl)))
    out.backoff_min_ms = math.floor(bo_min * (1 + (0.25 * lvl)))
    out.backoff_max_ms = math.floor(bo_max * mult)

    return out
end

local function net_auto_apply(instance)
    if not instance or not instance.net_auto then
        return
    end
    local auto = instance.net_auto
    instance.net_cfg = net_auto_tune_cfg(auto.base, auto.level)
    if instance.apply_net_cfg then
        instance.apply_net_cfg()
    end
    if instance.net then
        instance.net.auto_enabled = true
        instance.net.auto_level = auto.level
        instance.net.auto_ts = os.time()
        instance.net.auto_last_change_ts = auto.last_change_ts
        instance.net.auto_last_change_reason = auto.last_change_reason
    end
end

local function net_auto_escalate(instance, reason)
    if not instance or not instance.net_auto then
        return
    end
    local auto = instance.net_auto
    if auto.max_level <= 0 then
        return
    end
    local now = os.time()
    auto.last_error_ts = now
    if not auto.window_ts or (now - auto.window_ts) > auto.window_sec then
        auto.window_ts = now
        auto.error_burst = 1
    else
        auto.error_burst = (auto.error_burst or 0) + 1
    end
    if auto.level >= auto.max_level then
        return
    end
    local burst_limit = tonumber(auto.burst_threshold) or 2
    if auto.error_burst < burst_limit then
        return
    end
    if auto.last_change_ts and (now - auto.last_change_ts) < auto.min_interval_sec then
        return
    end
    auto.level = auto.level + 1
    auto.error_burst = 0
    auto.last_change_ts = now
    auto.last_change_reason = reason or "auto_escalate"
    net_auto_apply(instance)
end

local function net_auto_relax(instance)
    if not instance or not instance.net_auto then
        return
    end
    local auto = instance.net_auto
    local now = os.time()
    auto.last_ok_ts = now
    if auto.level <= 0 then
        if instance.net then
            instance.net.auto_enabled = true
            instance.net.auto_level = 0
        end
        return
    end
    if auto.last_error_ts and (now - auto.last_error_ts) < auto.relax_sec then
        return
    end
    if auto.last_change_ts and (now - auto.last_change_ts) < auto.relax_sec then
        return
    end
    auto.level = auto.level - 1
    auto.last_change_ts = now
    auto.last_change_reason = "auto_relax"
    net_auto_apply(instance)
end

	local function build_net_resilience(conf, res)
    res = res or resolve_input_resilience(conf)
    local global = nil
    if config and config.get_setting then
        local value = config.get_setting("net_resilience")
        if type(value) == "table" then
            global = value
        end
    end
    local local_cfg = type(conf.net_resilience) == "table" and conf.net_resilience or nil
    local profile_defaults = (res and res.enabled and type(res.net_defaults) == "table") and res.net_defaults or NET_RESILIENCE_DEFAULTS
    local function pick(key)
        if local_cfg and local_cfg[key] ~= nil then
            return local_cfg[key]
        end
        if conf[key] ~= nil then
            return conf[key]
        end
        if global and global[key] ~= nil then
            return global[key]
        end
        return nil
    end

    local out = {}
    for _, key in ipairs({
        "connect_timeout_ms",
        "read_timeout_ms",
        "stall_timeout_ms",
        "max_retries",
        "backoff_min_ms",
        "backoff_max_ms",
        "backoff_jitter_pct",
        "cooldown_sec",
        "low_speed_limit_bytes_sec",
        "low_speed_time_sec",
        "dns_cache_ttl_sec",
    }) do
        local value = net_number(pick(key))
        if value == nil then
            value = net_number(profile_defaults[key])
        end
        if value == nil then
            value = NET_RESILIENCE_DEFAULTS[key]
        end
        out[key] = value
    end

    local ua = pick("user_agent")
    if ua ~= nil and ua ~= "" then
        out.user_agent = tostring(ua)
    elseif res and res.enabled and profile_defaults.user_agent ~= nil and profile_defaults.user_agent ~= "" then
        out.user_agent = tostring(profile_defaults.user_agent)
    end

    local keepalive = net_bool(pick("keepalive"))
    if keepalive == nil then
        keepalive = net_bool(profile_defaults.keepalive)
    end
    if keepalive == nil then
        keepalive = NET_RESILIENCE_DEFAULTS.keepalive
    end
    out.keepalive = keepalive

    -- Default jitter buffer can be applied only when resilience profiles are enabled
    -- (globally or per-input via #net_profile=...).
    if res and res.enabled then
        local has_jitter_opt = (conf.jitter_buffer_ms ~= nil) or (conf.jitter_ms ~= nil)
        if not has_jitter_opt and res.jitter_default_ms and res.jitter_default_ms > 0 then
            conf.jitter_buffer_ms = math.floor(res.jitter_default_ms)
        end
    end

	    apply_auto_jitter_max_mb(conf, res)
	    apply_profile_net_auto_defaults(conf, res)

	    return out
	end

local net_rand_seeded = false
local function net_rand()
    if not net_rand_seeded then
        net_rand_seeded = true
        math.randomseed(os.time())
    end
    return math.random()
end

local function calc_backoff_ms(net, attempt)
    if not net then
        return 5000
    end
    local base = tonumber(net.backoff_min_ms) or 500
    local max_ms = tonumber(net.backoff_max_ms) or 10000
    local jitter_pct = tonumber(net.backoff_jitter_pct) or 0
    local factor = 1
    if attempt and attempt > 1 then
        factor = 2 ^ math.min(attempt - 1, 6)
    end
    local delay = base * factor
    if delay > max_ms then
        delay = max_ms
    end
    if jitter_pct > 0 then
        local jitter = delay * (jitter_pct / 100)
        delay = delay + ((net_rand() * 2) - 1) * jitter
        if delay < base then
            delay = base
        end
    end
    if delay < 1 then
        delay = 1
    end
    return math.floor(delay)
end

local function net_make_state(net_cfg)
    local now = os.time()
    return {
        state = "init",
        state_ts = now,
        last_error = nil,
        last_error_ts = nil,
        fail_count = 0,
        reconnects_total = 0,
        last_recv_ts = nil,
        current_backoff_ms = 0,
        cooldown_until = nil,
        auto_enabled = false,
        auto_level = 0,
    }
end

local function net_emit(conf, state)
    if not conf or not conf.on_net_stats or not state then
        return
    end
    local payload = {}
    for k, v in pairs(state) do
        payload[k] = v
    end
    conf.on_net_stats(payload)
end

local function net_mark_error(state, reason)
    if not state then
        return
    end
    state.last_error = reason
    state.last_error_ts = os.time()
    state.fail_count = (state.fail_count or 0) + 1
end

local function net_mark_ok(state)
    if not state then
        return
    end
    state.state = "running"
    state.state_ts = os.time()
    state.last_recv_ts = os.time()
    state.current_backoff_ms = 0
    state.fail_count = 0
    state.last_error = nil
    state.last_error_ts = nil
end

-- Нормализуем текст ошибок в компактный ASCII-суффикс для health_reason.
-- Это нужно, чтобы вместо бесполезных `http_0` в статусе было что-то вроде
-- `http_err_connection_timeout` / `playlist_err_low_speed`.
local function sanitize_reason_suffix(value)
    local s = tostring(value or "")
    s = s:lower()
    -- Любые не-алфанум символы (включая UTF-8 байты) заменяем на подчёркивания.
    s = s:gsub("[^%w]+", "_")
    s = s:gsub("^_+", ""):gsub("_+$", "")
    if s == "" then
        s = "error"
    end
    -- Ограничиваем длину, чтобы reason не разрастался в логах/статусе.
    if #s > 64 then
        s = s:sub(1, 64)
    end
    return s
end

local function http_reason(response)
    if not response then
        return "http_no_response"
    end
    local code = tonumber(response.code) or 0
    if code ~= 0 then
        return "http_" .. tostring(code)
    end
    local msg = response.message or response.error or "error"
    return "http_err_" .. sanitize_reason_suffix(msg)
end

local function hls_reason(prefix, response)
    local code = tonumber(response and response.code) or 0
    if code ~= 0 then
        return prefix .. "_http_" .. tostring(code)
    end
    local msg = (response and (response.message or response.error)) or "error"
    return prefix .. "_err_" .. sanitize_reason_suffix(msg)
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

local function ip_to_u32(ip)
    if not ip or ip == "" then
        return nil
    end
    local a, b, c, d = ip:match("^(%d+)%.(%d+)%.(%d+)%.(%d+)$")
    a, b, c, d = tonumber(a), tonumber(b), tonumber(c), tonumber(d)
    if not a or not b or not c or not d then
        return nil
    end
    if a > 255 or b > 255 or c > 255 or d > 255 then
        return nil
    end
    return a * 16777216 + b * 65536 + c * 256 + d
end

local function cidr_match(ip, cidr)
    local base, mask = cidr:match("^(.-)/(%d+)$")
    if not base or not mask then
        return false
    end
    local ip_num = ip_to_u32(ip)
    local base_num = ip_to_u32(base)
    local bits = tonumber(mask)
    if not ip_num or not base_num or not bits or bits < 0 or bits > 32 then
        return false
    end
    if bits == 0 then
        return true
    end
    local shift = 32 - bits
    local factor = 2 ^ shift
    return math.floor(ip_num / factor) == math.floor(base_num / factor)
end

local function http_auth_has(list, value)
    if not value or value == "" then
        return false
    end
    for _, item in ipairs(list) do
        if item == value then
            return true
        end
        if item:find("/", 1, true) then
            if cidr_match(value, item) then
                return true
            end
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

local function is_loopback_ip(ip)
    if not ip or ip == "" then
        return false
    end
    ip = tostring(ip)
    if ip == "127.0.0.1" or ip == "::1" then
        return true
    end
    -- Treat full 127/8 as loopback.
    if ip:match("^127%.") then
        return true
    end
    -- Some servers can report IPv4 loopback as IPv6-mapped (::ffff:127.x.x.x).
    local lower = ip:lower()
    if lower:match("^::ffff:127%.") then
        return true
    end
    return false
end

local function has_forwarded_headers(headers)
    if not headers then
        return false
    end
    return headers["x-forwarded-for"] or headers["X-Forwarded-For"]
        or headers["forwarded"] or headers["Forwarded"]
        or headers["x-real-ip"] or headers["X-Real-IP"]
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

    -- Allow internal ffmpeg consumers (transcode/audio-fix/publish) to read certain endpoints
    -- without credentials.
    -- This is constrained to:
    -- - loopback source IP
    -- - no forwarded headers (avoid accidental reverse-proxy bypass)
    -- - explicit query flag (?internal=1)
    -- - /play/*, /live/*, /input/* only
    local path = request and request.path or ""
    if path:sub(1, 6) == "/play/" or path:sub(1, 6) == "/live/" or path:sub(1, 7) == "/input/" then
        local ip = request and request.addr or ""
        local headers = request and request.headers or {}
        local query = request and request.query or nil
        local flag = query and (query.internal or query._internal) or nil
        if is_loopback_ip(ip) and not has_forwarded_headers(headers) and flag ~= nil then
            local text = tostring(flag):lower()
            if text == "1" or text == "true" or text == "yes" or text == "on" then
                return true, info
            end
        end
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

    local jitter_ms = tonumber(conf.jitter_buffer_ms or conf.jitter_ms)
    if jitter_ms and jitter_ms > 0 then
        local max_mb = tonumber(conf.jitter_max_buffer_mb) or tonumber(conf.max_buffer_mb) or 4
        instance.jitter = jitter({
            upstream = instance.tail:stream(),
            name = conf.name,
            jitter_buffer_ms = jitter_ms,
            max_buffer_mb = max_mb,
        })
        instance.tail = instance.jitter
    end

    if conf.pnr == nil then
        local function check_dependent()
            if conf.set_pnr ~= nil then return true end
            if conf.set_tsid ~= nil then return true end
            if conf.service_provider ~= nil then return true end
            if conf.service_name ~= nil then return true end
            if conf.no_sdt == true then return true end
            if conf.no_eit == true then return true end
            -- Включаем channel() даже если заданы только pass_* флаги.
            if conf.pass_sdt == true then return true end
            if conf.pass_eit == true then return true end
            if conf.pass_nit == true then return true end
            if conf.pass_tdt == true then return true end
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
        local function resolve_softcam(value, label)
            if type(value) == "table" then
                if value.cam then
                    return value
                end
            else
                if type(softcam_list) == "table" then
                    for _, i in ipairs(softcam_list) do
                        if tostring(i.__options.id) == tostring(value) then return i end
                    end
                end
                local i = _G[tostring(value)]
                if type(i) == "table" and i.cam then return i end
            end
            log.error("[" .. conf.name .. "] " .. tostring(label or "cam") .. " is not found")
            return nil
        end

        local cam = resolve_softcam(conf.cam, "cam")
        if cam then
            -- split_cam: create a dedicated CAM connection per stream to avoid head-of-line blocking
            -- when many streams share one softcam instance.
            local cam_for_decrypt = cam
            local opts = type(cam) == "table" and cam.__options or nil
            local split_cam = opts and (opts.split_cam == true or opts.split_cam == 1 or opts.split_cam == "1")

            -- Save for API diagnostics.
            instance.__softcam_instance = cam
            if type(conf.cam) ~= "table" then
                instance.__softcam_id = tostring(conf.cam)
            end

            if split_cam and not (opts and opts.is_clone) then
                local tag = conf.id or conf.name or tostring(conf.pnr or "")

                -- Optional pool mode: limit number of newcamd connections while still reducing HOL blocking.
                local pool_size = 0
                if opts then
                    if type(opts.raw_cfg) == "table" and opts.raw_cfg.split_cam_pool_size ~= nil then
                        pool_size = tonumber(opts.raw_cfg.split_cam_pool_size) or 0
                    else
                        pool_size = tonumber(opts.split_cam_pool_size) or 0
                    end
                end

                if pool_size > 1 and type(cam.get_pool) == "function" then
                    local ok, cam2 = pcall(function()
                        return cam:get_pool(tag)
                    end)
                    if ok and cam2 then
                        instance.__softcam_clone = cam2
                        instance.__softcam_clone_pooled = true
                        cam_for_decrypt = cam2
                    else
                        log.error("[" .. conf.name .. "] split_cam pool failed, falling back to clone/shared cam")
                    end
                end

                if cam_for_decrypt == cam and type(cam.clone) == "function" then
                    local ok, cam2 = pcall(function()
                        return cam:clone(tag)
                    end)
                    if ok and cam2 then
                        instance.__softcam_clone = cam2
                        instance.__softcam_clone_pooled = false
                        cam_for_decrypt = cam2
                    else
                        log.error("[" .. conf.name .. "] split_cam clone failed, using shared cam")
                    end
                end
            end

            -- Optional backup CAM (dual-CAM redundancy): sends ECM to both, accepts first valid CW.
            local cam_backup_for_decrypt = nil
            local cam_backup = nil
            if conf.cam_backup then
                cam_backup = resolve_softcam(conf.cam_backup, "cam_backup")
            end
            if cam_backup then
                cam_backup_for_decrypt = cam_backup
                local opts_b = type(cam_backup) == "table" and cam_backup.__options or nil
                local split_b = opts_b and (opts_b.split_cam == true or opts_b.split_cam == 1 or opts_b.split_cam == "1")

                instance.__softcam_backup_instance = cam_backup
                if type(conf.cam_backup) ~= "table" then
                    instance.__softcam_backup_id = tostring(conf.cam_backup)
                end

                if split_b and not (opts_b and opts_b.is_clone) then
                    local tag = (conf.id or conf.name or tostring(conf.pnr or "")) .. ":b"

                    local pool_size = 0
                    if opts_b then
                        if type(opts_b.raw_cfg) == "table" and opts_b.raw_cfg.split_cam_pool_size ~= nil then
                            pool_size = tonumber(opts_b.raw_cfg.split_cam_pool_size) or 0
                        else
                            pool_size = tonumber(opts_b.split_cam_pool_size) or 0
                        end
                    end

                    if pool_size > 1 and type(cam_backup.get_pool) == "function" then
                        local ok, cam2 = pcall(function()
                            return cam_backup:get_pool(tag)
                        end)
                        if ok and cam2 then
                            instance.__softcam_backup_clone = cam2
                            instance.__softcam_backup_clone_pooled = true
                            cam_backup_for_decrypt = cam2
                        else
                            log.error("[" .. conf.name .. "] split_cam pool failed for cam_backup, falling back to clone/shared cam")
                        end
                    end

                    if cam_backup_for_decrypt == cam_backup and type(cam_backup.clone) == "function" then
                        local ok, cam2 = pcall(function()
                            return cam_backup:clone(tag)
                        end)
                        if ok and cam2 then
                            instance.__softcam_backup_clone = cam2
                            instance.__softcam_backup_clone_pooled = false
                            cam_backup_for_decrypt = cam2
                        else
                            log.error("[" .. conf.name .. "] split_cam clone failed for cam_backup, using shared cam_backup")
                        end
                    end
                end
            end

            -- Optional global guard: reject suspicious CW updates (keeps compatibility by default).
            local key_guard = false
            if type(config) == "table" and type(config.get_setting) == "function" then
                local v = config.get_setting("softcam_key_guard")
                key_guard = (v == true or v == 1 or v == "1")
            end

            -- Optional dual-CAM hedge: send ECM to backup only after this delay (ms).
            local cam_backup_hedge_ms = tonumber(conf.cam_backup_hedge_ms or conf.dual_cam_hedge_ms)
            if opts and type(opts.raw_cfg) == "table" then
                local raw = opts.raw_cfg
                if cam_backup_hedge_ms == nil then
                    local hv = raw.cam_backup_hedge_ms or raw.dual_cam_hedge_ms
                    cam_backup_hedge_ms = tonumber(hv)
                end
            end
            if cam_backup_hedge_ms == nil then
                cam_backup_hedge_ms = 80
            end
            if cam_backup_hedge_ms < 0 then
                cam_backup_hedge_ms = 0
            end

            -- Strategy for backup CAM: race / hedge / failover.
            local cam_backup_mode = conf.cam_backup_mode
            if cam_backup_mode == nil and opts and type(opts.raw_cfg) == "table" then
                cam_backup_mode = opts.raw_cfg.cam_backup_mode
            end
            if cam_backup_mode ~= nil then
                cam_backup_mode = tostring(cam_backup_mode):lower()
                if cam_backup_mode ~= "race" and cam_backup_mode ~= "hedge" and cam_backup_mode ~= "failover" then
                    cam_backup_mode = nil
                end
            end

            -- Prefer primary CW in a short window when backup responds first.
            local cam_prefer_primary_ms = tonumber(conf.cam_prefer_primary_ms)
            if cam_prefer_primary_ms == nil and opts and type(opts.raw_cfg) == "table" then
                cam_prefer_primary_ms = tonumber(opts.raw_cfg.cam_prefer_primary_ms)
            end
            if cam_prefer_primary_ms == nil then
                cam_prefer_primary_ms = 30
            end
            if cam_prefer_primary_ms < 0 then
                cam_prefer_primary_ms = 0
            end

            -- shift: if stream doesn't specify one, allow softcam entry to provide a default.
            local shift = conf.shift
            if (shift == nil or shift == 0 or shift == "0" or shift == "") and opts and type(opts.raw_cfg) == "table" then
                local sv = opts.raw_cfg.shift
                if sv ~= nil and sv ~= "" then
                    shift = tonumber(sv) or shift
                end
            end

            local cas_pnr = nil
            if conf.pnr and conf.set_pnr then cas_pnr = conf.pnr end

            instance.decrypt = decrypt({
                upstream = instance.tail:stream(),
                name = conf.name,
                cam = cam_for_decrypt:cam(),
                cam_backup = cam_backup_for_decrypt and cam_backup_for_decrypt.cam and cam_backup_for_decrypt:cam() or nil,
                cas_data = conf.cas_data,
                cas_pnr = cas_pnr,
                disable_emm = conf.no_emm,
                ecm_pid = conf.ecm_pid,
                shift = shift,
                key_guard = key_guard,
                cam_backup_hedge_ms = cam_backup_hedge_ms,
                cam_backup_mode = cam_backup_mode,
                cam_prefer_primary_ms = cam_prefer_primary_ms,
            })
            instance.tail = instance.decrypt
        end
    end

    -- Опциональный слой playout (anti-jitter / carrier): пейсит выдачу TS ровно по времени
    -- и при пустом буфере вставляет NULL (PID=0x1FFF), чтобы /play не "залипал" на паузах входа.
    --
    -- Важно для совместимости:
    -- - включается только явно (`#playout=1`) или через opt-in профиль `#net_profile=superbad`
    -- - анализатор должен смотреть ДО playout, иначе NULL stuffing будет делать `on_air=true` "вечно"
    local fmt = tostring(conf.format or ""):lower()
    local is_http_like = (fmt == "http" or fmt == "https" or fmt == "hls")
    if is_http_like then
        local playout_enabled = net_bool(conf.playout)
        if playout_enabled == nil then
            -- Авто-дефолт только для configured profile=superbad (не для effective profile по глобальным settings).
            playout_enabled = (normalize_net_profile(conf.net_profile) == "superbad")
        end

        if playout_enabled == true then
            -- Статус/health/analyze должны работать на контенте, а не на carrier (NULL stuffing).
            instance.analyze_tail = instance.tail

            local res = resolve_input_resilience(conf)
            local assumed_mbps = nil
            if res and type(res.jitter_assumed_mbps) == "table" and res.profile_effective then
                assumed_mbps = tonumber(res.jitter_assumed_mbps[res.profile_effective])
            end

            local jitter_ms = tonumber(conf.jitter_buffer_ms or conf.jitter_ms)
            local target_fill_ms = tonumber(conf.playout_target_fill_ms)
            if (not target_fill_ms or target_fill_ms <= 0) and jitter_ms and jitter_ms > 0 then
                target_fill_ms = jitter_ms
            end

            local playout_max_mb = tonumber(conf.playout_max_buffer_mb)
            if not playout_max_mb or playout_max_mb <= 0 then
                playout_max_mb = tonumber(conf.jitter_max_buffer_mb) or tonumber(conf.max_buffer_mb)
                    or profile_playout_max_buffer_default_mb()
            end
            if playout_max_mb < 4 then
                playout_max_mb = 4
            end

            local null_stuffing = conf.playout_null_stuffing
            if null_stuffing == nil then
                null_stuffing = true
            end

            instance.playout = playout({
                upstream = instance.tail:stream(),
                name = conf.name,
                playout_mode = conf.playout_mode,
                playout_target_kbps = conf.playout_target_kbps,
                playout_tick_ms = conf.playout_tick_ms,
                playout_null_stuffing = null_stuffing,
                playout_min_fill_ms = conf.playout_min_fill_ms,
                playout_target_fill_ms = target_fill_ms,
                playout_max_fill_ms = conf.playout_max_fill_ms,
                playout_max_buffer_mb = playout_max_mb,
                assumed_mbps = assumed_mbps,
            })
            instance.tail = instance.playout
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

    if instance.__softcam_clone then
        local cam = instance.__softcam_clone
        local pooled = instance.__softcam_clone_pooled
        instance.__softcam_clone = nil
        instance.__softcam_clone_pooled = nil
        -- Pooled split_cam clones are shared; they must be closed on softcam reload, not per-stream stop.
        if not pooled and cam.close then
            pcall(function() cam:close() end)
        end
    end
    if instance.__softcam_backup_clone then
        local cam = instance.__softcam_backup_clone
        local pooled = instance.__softcam_backup_clone_pooled
        instance.__softcam_backup_clone = nil
        instance.__softcam_backup_clone_pooled = nil
        if not pooled and cam.close then
            pcall(function() cam:close() end)
        end
    end
    instance.__softcam_instance = nil
    instance.__softcam_id = nil
    instance.__softcam_backup_instance = nil
    instance.__softcam_backup_id = nil
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
https_direct_instance_list = {}

local function https_native_supported()
    return astra and astra.features and astra.features.ssl
end
https_input_instance_list = {}
https_bridge_port_map = {}

local function setting_bool(key, fallback)
    if not config or not config.get_setting then
        return fallback
    end
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
    return fallback
end

local function truthy(value)
    return value == true or value == 1 or value == "1" or value == "true" or value == "yes" or value == "on"
end

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

	local function is_local_http_host(host)
	    if host == nil then
	        return false
	    end
	    local h = tostring(host):lower()
	    if h == "localhost" or h == "::1" or h == "127.0.0.1" then
	        return true
	    end
	    if h:match("^127%.") then
	        return true
	    end
	    return false
	end

init_input_module.http = function(conf)
    local instance_id = conf.host .. ":" .. conf.port .. conf.path
    local instance = http_input_instance_list[instance_id]

    if not instance then
        local res = resolve_input_resilience(conf)
        instance = {
            clients = 0,
            running = true,
        }
        http_input_instance_list[instance_id] = instance

        instance.on_error = function(message)
            log.error("[" .. conf.name .. "] " .. message)
            if conf.on_error then conf.on_error(message) end
        end

	        if conf.ua and not conf.user_agent then
	            conf.user_agent = conf.ua
	        end

	        -- Некоторые IPTV-панели отдают одноразовые URL через 302/301 (например, `token=...`).
	        -- Если дальше мы ловим 4xx на уже редиректнутом URL, имеет смысл вернуться на origin
	        -- и получить свежий redirect, иначе мы можем бесконечно ретраить протухший URL.
	        instance.origin = {
	            host = conf.host,
	            port = conf.port,
	            path = conf.path,
	        }
	        instance.last_origin_reset_ts = nil

		        local sync = conf.sync
		        if sync == nil and is_local_http_host(conf.host) and type(conf.path) == "string"
		            and (conf.path:match("^/play/") or conf.path:match("^/stream/")) then
	            -- /play and /stream are served via http_upstream (burst delivery); enabling http_request sync
	            -- makes consumption stable for downstream pipelines.
	            sync = 1
	        end
	        -- Для профильного режима (bad/max/superbad) включаем sync по умолчанию:
	        -- это помогает переживать переподключения, когда поток может начатьcя не с границы TS-пакета.
	        if sync == nil and res and res.enabled == true then
	            local p = res.profile_effective
	            if p == "bad" or p == "max" or p == "superbad" then
	                sync = 1
	            end
	        end
	        local timeout = conf.timeout
	        if timeout == nil and is_local_http_host(conf.host) and type(conf.path) == "string"
	            and (conf.path:match("^/play/") or conf.path:match("^/stream/")) then
	            -- /play and /stream can be bursty on low-bitrate streams; keep a higher receive timeout by default
	            -- so we don't reconnect on normal gaps.
	            timeout = 60
	        end

        instance.net_cfg = build_net_resilience(conf, res)
        instance.net = net_make_state(instance.net_cfg)
        instance.net_auto = net_auto_init(conf, instance.net_cfg)
        if instance.net_auto then
            net_auto_apply(instance)
        end

        local function build_headers(host, port)
            local ua = (instance.net_cfg and instance.net_cfg.user_agent) or conf.user_agent or http_user_agent
            local keepalive = instance.net_cfg and instance.net_cfg.keepalive
            local conn = keepalive and "keep-alive" or "close"
            local headers = {
                "User-Agent: " .. ua,
                "Host: " .. host .. ":" .. port,
                "Connection: " .. conn,
            }
            if conf.login and conf.password then
                local auth = base64.encode(conf.login .. ":" .. conf.password)
                table.insert(headers, "Authorization: Basic " .. auth)
            end
            return headers
        end

        local function schedule_retry(reason)
            if instance.request then
                instance.request:close()
                instance.request = nil
            end

            net_mark_error(instance.net, reason)
            instance.net.state = "degraded"
            instance.net.state_ts = os.time()
            instance.net.reconnects_total = (instance.net.reconnects_total or 0) + 1
            net_auto_escalate(instance, reason)

            local delay_ms = calc_backoff_ms(instance.net_cfg, instance.net.fail_count)
            local max_retries = tonumber(instance.net_cfg.max_retries) or 0
            if max_retries > 0 and instance.net.fail_count >= max_retries then
                instance.net.state = "offline"
                local cooldown = tonumber(instance.net_cfg.cooldown_sec) or 30
                if cooldown < 0 then cooldown = 0 end
                instance.net.cooldown_until = os.time() + math.floor(cooldown)
                delay_ms = math.max(delay_ms, math.floor(cooldown * 1000))
            end
            instance.net.current_backoff_ms = delay_ms
            net_emit(conf, instance.net)

            if instance.timeout then
                instance.timeout:close()
                instance.timeout = nil
            end
            instance.timeout = timer({
                interval = math.max(1, math.floor(delay_ms / 1000)),
                callback = function(self)
                    self:close()
                    instance.timeout = nil
                    if instance.running then
                        instance.start_request()
                    end
                end,
            })
        end

	        instance.http_conf = {
	            host = conf.host,
	            port = conf.port,
	            path = conf.path,
            stream = true,
            sync = sync,
            buffer_size = conf.buffer_size,
            timeout = timeout,
            sctp = conf.sctp,
            headers = build_headers(conf.host, conf.port),
            connect_timeout_ms = instance.net_cfg and instance.net_cfg.connect_timeout_ms or nil,
            read_timeout_ms = instance.net_cfg and instance.net_cfg.read_timeout_ms or nil,
            stall_timeout_ms = instance.net_cfg and instance.net_cfg.stall_timeout_ms or nil,
            low_speed_limit_bytes_sec = instance.net_cfg and instance.net_cfg.low_speed_limit_bytes_sec or nil,
	            low_speed_time_sec = instance.net_cfg and instance.net_cfg.low_speed_time_sec or nil,
	        }

	        local function maybe_reset_to_origin(code)
	            if not instance.origin or not instance.http_conf then
	                return
	            end
	            local origin = instance.origin
	            if instance.http_conf.host == origin.host
	                and instance.http_conf.port == origin.port
	                and instance.http_conf.path == origin.path then
	                return
	            end
	            local c = tonumber(code) or 0
	            -- 4xx на редиректнутом URL часто означает "протух токен/сессия" на панелях.
	            -- Исключаем 429, там лучше уважать backoff.
	            if c >= 400 and c < 500 and c ~= 429 then
	                instance.http_conf.host = origin.host
	                instance.http_conf.port = origin.port
	                instance.http_conf.path = origin.path
	                local now = os.time()
	                if (not instance.last_origin_reset_ts) or (now - instance.last_origin_reset_ts) > 10 then
	                    instance.last_origin_reset_ts = now
	                    log.info("[" .. conf.name .. "] Redirect URL may be expired (HTTP " .. tostring(c) ..
	                        "), refreshing via origin")
	                end
	            end
	        end
	        instance.apply_net_cfg = function()
	            if not instance.net_cfg or not instance.http_conf then
	                return
	            end
            instance.http_conf.connect_timeout_ms = instance.net_cfg.connect_timeout_ms
            instance.http_conf.read_timeout_ms = instance.net_cfg.read_timeout_ms
            instance.http_conf.stall_timeout_ms = instance.net_cfg.stall_timeout_ms
            instance.http_conf.low_speed_limit_bytes_sec = instance.net_cfg.low_speed_limit_bytes_sec
            instance.http_conf.low_speed_time_sec = instance.net_cfg.low_speed_time_sec
        end
        if instance.net_auto then
            net_auto_apply(instance)
        end

        instance.start_request = function()
            if instance.request then
                instance.request:close()
                instance.request = nil
            end
            if instance.net and instance.net.cooldown_until then
                local now = os.time()
                if now < instance.net.cooldown_until then
                    local wait = (instance.net.cooldown_until - now) * 1000
                    instance.net.current_backoff_ms = wait
                    net_emit(conf, instance.net)
                    if instance.timeout then
                        instance.timeout:close()
                        instance.timeout = nil
                    end
                    instance.timeout = timer({
                        interval = math.max(1, math.floor(wait / 1000)),
                        callback = function(self)
                            self:close()
                            instance.timeout = nil
                            if instance.running then
                                instance.start_request()
                            end
                        end,
                    })
                    return
                end
                instance.net.cooldown_until = nil
            end

            if instance.net then
                instance.net.state = "connecting"
                instance.net.state_ts = os.time()
                net_emit(conf, instance.net)
            end

            instance.http_conf.headers = build_headers(instance.http_conf.host, instance.http_conf.port)
	            instance.http_conf.callback = function(self, response)
	                if not response then
	                    -- http_request в stream-mode вызывает callback(nil) на on_close.
	                    -- Если до этого уже был error callback, не затираем причину на "no_response".
	                    local now = os.time()
	                    local ts = instance.net and instance.net.last_error_ts or nil
	                    if ts and (now - ts) <= 1 then
	                        return
	                    end
	                    schedule_retry((instance.net and instance.net.last_error) or "http_stream_closed")
	                    return
	                end

                if response.code == 200 then
                    instance.net.last_recv_ts = os.time()
                    net_mark_ok(instance.net)
                    net_auto_relax(instance)
                    net_emit(conf, instance.net)
                    instance.transmit:set_upstream(self:stream())
                    return
                end

                if response.code == 301 or response.code == 302 then
                    local o = parse_url(response.headers["location"])
                    if o then
                        instance.http_conf.host = o.host
                        instance.http_conf.port = o.port
                        instance.http_conf.path = o.path
                        log.info("[" .. conf.name .. "] Redirect to http://" .. o.host .. ":" .. o.port .. o.path)
                        instance.start_request()
                    else
                        instance.on_error("HTTP Error: Redirect failed")
                        schedule_retry("redirect_failed")
                    end
                    return
                end

	                local code = tonumber(response.code) or 0
	                local message = response.message or "error"
	                instance.on_error("HTTP Error: " .. tostring(code) .. ":" .. tostring(message))
	                maybe_reset_to_origin(code)
	                schedule_retry(http_reason(response))
	            end
	            instance.request = http_request(instance.http_conf)
	        end

        instance.transmit = transmit({ instance_id = instance_id })
        instance.start_request()
    end

    instance.clients = instance.clients + 1
    return instance.transmit
end

	local function init_input_module_https_direct(conf)
    local instance_id = "https://" .. conf.host .. ":" .. conf.port .. conf.path
    local instance = https_direct_instance_list[instance_id]

    if not instance then
        instance = {
            clients = 0,
            running = true,
        }
        https_direct_instance_list[instance_id] = instance

        instance.on_error = function(message)
            log.error("[" .. conf.name .. "] " .. message)
            if conf.on_error then conf.on_error(message) end
        end

        if conf.ua and not conf.user_agent then
            conf.user_agent = conf.ua
        end

	        local res = resolve_input_resilience(conf)
	        local sync = conf.sync
	        if sync == nil and is_local_http_host(conf.host) and type(conf.path) == "string" and conf.path:match("^/play/") then
	            sync = 1
	        end
	        if sync == nil and res and res.enabled == true then
	            local p = res.profile_effective
	            if p == "bad" or p == "max" or p == "superbad" then
	                sync = 1
	            end
	        end
	        local timeout = conf.timeout
	        if timeout == nil and is_local_http_host(conf.host) and type(conf.path) == "string" and conf.path:match("^/play/") then
	            timeout = 60
	        end

        instance.net_cfg = build_net_resilience(conf, res)
        instance.net = net_make_state(instance.net_cfg)

        local function build_headers(host, port)
            local ua = (instance.net_cfg and instance.net_cfg.user_agent) or conf.user_agent or http_user_agent
            local keepalive = instance.net_cfg and instance.net_cfg.keepalive
            local conn = keepalive and "keep-alive" or "close"
            local headers = {
                "User-Agent: " .. ua,
                "Host: " .. host .. ":" .. port,
                "Connection: " .. conn,
            }
            if conf.login and conf.password then
                local auth = base64.encode(conf.login .. ":" .. conf.password)
                table.insert(headers, "Authorization: Basic " .. auth)
            end
            return headers
        end

        local function schedule_retry(reason)
            if instance.request then
                instance.request:close()
                instance.request = nil
            end

            net_mark_error(instance.net, reason)
            instance.net.state = "degraded"
            instance.net.state_ts = os.time()
            instance.net.reconnects_total = (instance.net.reconnects_total or 0) + 1

            local delay_ms = calc_backoff_ms(instance.net_cfg, instance.net.fail_count)
            local max_retries = tonumber(instance.net_cfg.max_retries) or 0
            if max_retries > 0 and instance.net.fail_count >= max_retries then
                instance.net.state = "offline"
                local cooldown = tonumber(instance.net_cfg.cooldown_sec) or 30
                if cooldown < 0 then cooldown = 0 end
                instance.net.cooldown_until = os.time() + math.floor(cooldown)
                delay_ms = math.max(delay_ms, math.floor(cooldown * 1000))
            end
            instance.net.current_backoff_ms = delay_ms
            net_emit(conf, instance.net)

            if instance.timeout then
                instance.timeout:close()
                instance.timeout = nil
            end
            instance.timeout = timer({
                interval = math.max(1, math.floor(delay_ms / 1000)),
                callback = function(self)
                    self:close()
                    instance.timeout = nil
                    if instance.running then
                        instance.start_request()
                    end
                end,
            })
        end

        instance.http_conf = {
            host = conf.host,
            port = conf.port,
            path = conf.path,
            stream = true,
            sync = sync,
            buffer_size = conf.buffer_size,
            timeout = timeout,
            sctp = conf.sctp,
            ssl = true,
            tls_verify = conf.tls_verify,
            headers = build_headers(conf.host, conf.port),
            connect_timeout_ms = instance.net_cfg and instance.net_cfg.connect_timeout_ms or nil,
            read_timeout_ms = instance.net_cfg and instance.net_cfg.read_timeout_ms or nil,
            stall_timeout_ms = instance.net_cfg and instance.net_cfg.stall_timeout_ms or nil,
            low_speed_limit_bytes_sec = instance.net_cfg and instance.net_cfg.low_speed_limit_bytes_sec or nil,
            low_speed_time_sec = instance.net_cfg and instance.net_cfg.low_speed_time_sec or nil,
            instance_id = instance_id,
        }
        instance.apply_net_cfg = function()
            if not instance.net_cfg or not instance.http_conf then
                return
            end
            instance.http_conf.connect_timeout_ms = instance.net_cfg.connect_timeout_ms
            instance.http_conf.read_timeout_ms = instance.net_cfg.read_timeout_ms
            instance.http_conf.stall_timeout_ms = instance.net_cfg.stall_timeout_ms
            instance.http_conf.low_speed_limit_bytes_sec = instance.net_cfg.low_speed_limit_bytes_sec
            instance.http_conf.low_speed_time_sec = instance.net_cfg.low_speed_time_sec
        end
        if instance.net_auto then
            net_auto_apply(instance)
        end

        instance.start_request = function()
            if instance.request then
                instance.request:close()
                instance.request = nil
            end
            if instance.net and instance.net.cooldown_until then
                local now = os.time()
                if now < instance.net.cooldown_until then
                    local wait = (instance.net.cooldown_until - now) * 1000
                    instance.net.current_backoff_ms = wait
                    net_emit(conf, instance.net)
                    if instance.timeout then
                        instance.timeout:close()
                        instance.timeout = nil
                    end
                    instance.timeout = timer({
                        interval = math.max(1, math.floor(wait / 1000)),
                        callback = function(self)
                            self:close()
                            instance.timeout = nil
                            if instance.running then
                                instance.start_request()
                            end
                        end,
                    })
                    return
                end
                instance.net.cooldown_until = nil
            end

            if instance.net then
                instance.net.state = "connecting"
                instance.net.state_ts = os.time()
                net_emit(conf, instance.net)
            end

            instance.http_conf.headers = build_headers(instance.http_conf.host, instance.http_conf.port)
	            instance.http_conf.callback = function(self, response)
	                if not response then
	                    local now = os.time()
	                    local ts = instance.net and instance.net.last_error_ts or nil
	                    if ts and (now - ts) <= 1 then
	                        return
	                    end
	                    schedule_retry((instance.net and instance.net.last_error) or "http_stream_closed")
	                    return
	                end

                if response.code == 200 then
                    instance.net.last_recv_ts = os.time()
                    net_mark_ok(instance.net)
                    net_auto_relax(instance)
                    net_emit(conf, instance.net)
                    instance.transmit:set_upstream(self:stream())
                    return
                end

                if response.code == 301 or response.code == 302 then
                    local o = parse_url(response.headers["location"])
                    if o then
                        instance.http_conf.host = o.host
                        instance.http_conf.port = o.port
                        instance.http_conf.path = o.path
                        instance.http_conf.ssl = (o.format == "https")
                        log.info("[" .. conf.name .. "] Redirect to " .. tostring(o.format) ..
                            "://" .. o.host .. ":" .. o.port .. o.path)
                        instance.start_request()
                    else
                        instance.on_error("HTTPS Error: Redirect failed")
                        schedule_retry("redirect_failed")
                    end
                    return
                end

                local code = tonumber(response.code) or 0
                local message = response.message or "error"
                instance.on_error("HTTP Error: " .. tostring(code) .. ":" .. tostring(message))
                schedule_retry(http_reason(response))
            end
            local ok, req = pcall(http_request, instance.http_conf)
            if ok and req then
                instance.request = req
            else
                instance.request = nil
                instance.on_error("HTTPS Error: init failed")
                schedule_retry("init_failed")
            end
        end

        instance.transmit = transmit({ instance_id = instance_id })
        instance.start_request()
    end

    instance.clients = instance.clients + 1
    conf.__https_direct_instance_id = instance_id
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

local function init_input_module_https_bridge(conf)
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

init_input_module.https = function(conf)
    local bridge_enabled = truthy(conf.https_bridge) or truthy(conf.bridge) or truthy(conf.ffmpeg)
    if not bridge_enabled then
        bridge_enabled = setting_bool("https_bridge_enabled", false)
    end

    if https_native_supported() then
        local transmit, err = init_input_module_https_direct(conf)
        if transmit then
            return transmit
        end
        if not bridge_enabled then
            log.error("[" .. conf.name .. "] https input failed: " .. tostring(err or "native https unavailable"))
            return nil
        end
        log.warning("[" .. conf.name .. "] https native failed, falling back to ffmpeg bridge")
    end

    if not bridge_enabled then
        log.error("[" .. conf.name .. "] https input requires native TLS (OpenSSL) or ffmpeg bridge (enable https_bridge_enabled or add #https_bridge=1)")
        return nil
    end

    return init_input_module_https_bridge(conf)
end

kill_input_module.https = function(module, conf)
    if conf.__https_direct_instance_id then
        local instance = https_direct_instance_list[conf.__https_direct_instance_id]
        if not instance then
            return
        end
    instance.clients = instance.clients - 1
    if instance.clients <= 0 then
        instance.running = false
        if instance.timeout then
            instance.timeout:close()
            instance.timeout = nil
        end
        if instance.request then
            instance.request:close()
            instance.request = nil
        end
        instance.transmit = nil
        https_direct_instance_list[conf.__https_direct_instance_id] = nil
        end
        return
    end

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
        instance.running = false
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
    local scheme = (conf.format == "https") and "https://" or "http://"
    return scheme .. host
end

local function hls_resolve_url(base_url, base_dir, ref)
    if ref:match("^https?://") then
        return ref
    end
    if ref:sub(1, 2) == "//" then
        local scheme = base_url:match("^(https?):") or "http"
        return scheme .. ":" .. ref
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

local HLS_INPUT_DEFAULTS = {
    max_segments = 12,
    max_gap_segments = 3,
    segment_retries = 3,
    max_parallel = 1,
}

local function profile_hls_input_defaults()
    local defaults = copy_shallow(HLS_INPUT_DEFAULTS)
    local profile = get_performance_profile()
    if profile == "mass" then
        defaults.max_segments = 8
        defaults.max_gap_segments = 2
        defaults.segment_retries = 2
    elseif profile == "low_latency" then
        defaults.max_segments = 6
        defaults.max_gap_segments = 2
        defaults.segment_retries = 1
    end
    return defaults
end

local function hls_cfg_number(conf, key, fallback)
    local v = conf[key]
    if v == nil or v == "" then
        return fallback
    end
    local num = tonumber(v)
    if num == nil or num < 0 then
        return fallback
    end
    return num
end

local function hls_emit_net(instance)
    if instance and instance.net then
        net_emit(instance.config, instance.net)
    end
end

local function hls_emit_stats(instance)
    if not instance or not instance.hls or not instance.config or not instance.config.on_hls_stats then
        return
    end
    local payload = {}
    for k, v in pairs(instance.hls) do
        payload[k] = v
    end
    instance.config.on_hls_stats(payload)
end

local function hls_set_state(instance, state, reason)
    if not instance or not instance.hls then
        return
    end
    instance.hls.state = state
    instance.hls.state_ts = os.time()
    if reason then
        instance.hls.last_error = reason
        instance.hls.last_error_ts = os.time()
    end
end

local function hls_mark_error(instance, reason, is_segment)
    if not instance or not instance.hls then
        return
    end
    if is_segment then
        instance.hls.segment_errors_total = (instance.hls.segment_errors_total or 0) + 1
    end
    hls_set_state(instance, "degraded", reason)
    if instance.net_cfg and instance.net then
        net_mark_error(instance.net, reason)
        instance.net.reconnects_total = (instance.net.reconnects_total or 0) + 1
        instance.net.state = "degraded"
        instance.net.state_ts = os.time()
        net_auto_escalate(instance, reason)
    end
    hls_emit_net(instance)
    hls_emit_stats(instance)
end

local function hls_mark_ok(instance)
    if not instance or not instance.hls then
        return
    end
    instance.hls.playlist_ok = true
    instance.hls.last_ok_ts = os.time()
    hls_set_state(instance, "running")
    if instance.net then
        net_mark_ok(instance.net)
        net_auto_relax(instance)
        hls_emit_net(instance)
    end
    hls_emit_stats(instance)
end

-- Forward-declared because it's used inside hls_start_next_segment() callback.
-- Lua "local function ..." is not hoisted, so declaring this later would make the callback
-- call a global (nil) symbol and crash at runtime.
local hls_schedule_segment_retry

local function hls_start_next_segment(instance)
    if instance.segment_request or #instance.queue == 0 then
        return
    end

    local item = table.remove(instance.queue, 1)
    if instance.queued then
        instance.queued[item.seq] = nil
    end
    instance.active_seq = item.seq
    instance.segment_ok = false

    local seg_conf = parse_url(item.uri)
    if not seg_conf or (seg_conf.format ~= "http" and seg_conf.format ~= "https") then
        log.error("[hls] unsupported segment url: " .. item.uri)
        hls_mark_error(instance, "segment_url_invalid", true)
        return
    end
    if seg_conf.format == "https" and not https_native_supported() then
        log.error("[hls] https is not supported (OpenSSL not available)")
        hls_mark_error(instance, "segment_https_unsupported", true)
        return
    end

    local ua = (instance.net_cfg and instance.net_cfg.user_agent) or instance.config.user_agent or http_user_agent
    local headers = {
        "User-Agent: " .. ua,
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
        ssl = (seg_conf.format == "https"),
        headers = headers,
        connect_timeout_ms = instance.net_cfg and instance.net_cfg.connect_timeout_ms or nil,
        read_timeout_ms = instance.net_cfg and instance.net_cfg.read_timeout_ms or nil,
        stall_timeout_ms = instance.net_cfg and instance.net_cfg.stall_timeout_ms or nil,
        low_speed_limit_bytes_sec = instance.net_cfg and instance.net_cfg.low_speed_limit_bytes_sec or nil,
        low_speed_time_sec = instance.net_cfg and instance.net_cfg.low_speed_time_sec or nil,
        callback = function(self, response)
            if not response then
                instance.segment_request = nil
                if instance.segment_ok then
                    instance.last_seq = instance.active_seq
                    instance.hls.last_seq = instance.active_seq
                    instance.hls.last_segment_ts = os.time()
                    instance.hls.gap_count = 0
                    hls_mark_ok(instance)
                end
                instance.active_seq = nil
                hls_start_next_segment(instance)
                return
            end

            if response.code ~= 200 then
                local msg = response.message or "error"
                log.error("[hls] segment http error: " .. tostring(response.code) .. ":" .. tostring(msg))
                self:close()
                instance.segment_request = nil
                local retries = instance.hls.segment_retries or 0
                item.attempts = (item.attempts or 0) + 1
                if retries > 0 and item.attempts > retries then
                    instance.hls.gap_count = (instance.hls.gap_count or 0) + 1
                    if instance.hls.gap_count > (instance.hls.max_gap_segments or 0) then
                        hls_set_state(instance, "failed", "hls_gap_limit")
                    end
                    instance.last_seq = item.seq
                    instance.hls.last_seq = item.seq
                    instance.active_seq = nil
                    hls_start_next_segment(instance)
                    return
                end
                hls_mark_error(instance, hls_reason("segment", response), true)
                table.insert(instance.queue, 1, item)
                if instance.queued then
                    instance.queued[item.seq] = true
                end
                local delay_ms = 500
                if instance.net_cfg then
                    delay_ms = calc_backoff_ms(instance.net_cfg, item.attempts)
                end
                hls_schedule_segment_retry(instance, delay_ms)
                return
            end

            instance.segment_ok = true
            if instance.net then
                net_mark_ok(instance.net)
                hls_emit_net(instance)
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

local function hls_schedule_backoff(instance, reason)
    local delay_ms = 5000
    if instance.net_cfg then
        delay_ms = calc_backoff_ms(instance.net_cfg, instance.net and instance.net.fail_count or 1)
        if instance.net then
            instance.net.current_backoff_ms = delay_ms
        end
        local max_retries = tonumber(instance.net_cfg.max_retries) or 0
        if max_retries > 0 and instance.net and instance.net.fail_count >= max_retries then
            instance.net.state = "offline"
            hls_set_state(instance, "failed", "hls_retry_limit")
            local cooldown = tonumber(instance.net_cfg.cooldown_sec)
            if cooldown == nil then
                cooldown = math.max(30, math.floor((instance.net_cfg.backoff_max_ms or 10000) / 1000))
            end
            if cooldown < 0 then cooldown = 0 end
            delay_ms = math.max(delay_ms, math.floor(cooldown * 1000))
        end
    end
    if instance.hls and reason and (reason:find("timeout") or reason:find("stall")) then
        instance.hls.stall_events_total = (instance.hls.stall_events_total or 0) + 1
    end
    hls_mark_error(instance, reason, false)
    hls_schedule_refresh(instance, math.max(1, math.floor(delay_ms / 1000)))
end

hls_schedule_segment_retry = function(instance, delay_ms)
    if instance.segment_retry_timer then
        instance.segment_retry_timer:close()
        instance.segment_retry_timer = nil
    end
    instance.segment_retry_timer = timer({
        interval = math.max(1, math.floor(delay_ms / 1000)),
        callback = function(self)
            self:close()
            instance.segment_retry_timer = nil
            if instance.running then
                hls_start_next_segment(instance)
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
        if not vconf or (vconf.format ~= "http" and vconf.format ~= "https") then
            log.error("[hls] unsupported variant url")
            return
        end
        if vconf.format == "https" and not https_native_supported() then
            log.error("[hls] https is not supported (OpenSSL not available)")
            return
        end

        instance.playlist_conf = vconf
        instance.force_refresh = true
        return
    end

    local media = hls_parse_media(content, base_url, base_dir)
    instance.hls.playlist_ok = true
    instance.hls.last_reload_ts = os.time()
    instance.hls.target_duration = media.target_duration

    if instance.last_seq and #media.segments > 0 then
        local seq0 = media.segments[1].seq or instance.last_seq
        if seq0 + 1 < instance.last_seq then
            -- Источник перезапустился или откатил media sequence.
            instance.queue = {}
            instance.queued = {}
            instance.hls.gap_count = 0
            instance.last_seq = nil
            instance.hls.last_seq = nil
        end
    end

    for _, item in ipairs(media.segments) do
        if (not instance.last_seq or item.seq > instance.last_seq) and not instance.queued[item.seq] then
            table.insert(instance.queue, item)
            instance.queued[item.seq] = true
        end
    end

    local max_segments = instance.hls.max_segments or HLS_INPUT_DEFAULTS.max_segments
    while #instance.queue > max_segments do
        local dropped = table.remove(instance.queue, 1)
        if dropped and instance.queued then
            instance.queued[dropped.seq] = nil
        end
    end

    hls_mark_ok(instance)
    hls_start_next_segment(instance)
    hls_schedule_refresh(instance, math.max(1, math.floor(media.target_duration / 2)))
end

local function hls_start(instance)
    instance.running = true
    if instance.hls then
        hls_set_state(instance, "init")
    end

    function instance.request_playlist()
        if instance.playlist_request then
            return
        end

        local conf = instance.playlist_conf
        if conf.format == "https" and not https_native_supported() then
            log.error("[hls] https is not supported (OpenSSL not available)")
            return
        end
        local ua = (instance.net_cfg and instance.net_cfg.user_agent) or instance.config.user_agent or http_user_agent
        local headers = {
            "User-Agent: " .. ua,
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
            ssl = (conf.format == "https"),
            connect_timeout_ms = instance.net_cfg and instance.net_cfg.connect_timeout_ms or nil,
            read_timeout_ms = instance.net_cfg and instance.net_cfg.read_timeout_ms or nil,
            stall_timeout_ms = instance.net_cfg and instance.net_cfg.stall_timeout_ms or nil,
            low_speed_limit_bytes_sec = instance.net_cfg and instance.net_cfg.low_speed_limit_bytes_sec or nil,
            low_speed_time_sec = instance.net_cfg and instance.net_cfg.low_speed_time_sec or nil,
            callback = function(self, response)
                if not response then
                    hls_schedule_backoff(instance, "playlist_no_response")
                elseif response.code == 200 and response.content then
                    hls_handle_playlist(instance, response.content)
                else
                    local msg = response.message or "error"
                    log.error("[hls] playlist http error: " .. tostring(response.code) .. ":" .. tostring(msg))
                    hls_schedule_backoff(instance, hls_reason("playlist", response))
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
    if instance.hls then
        hls_set_state(instance, "offline")
        hls_emit_stats(instance)
    end
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
    if instance.segment_retry_timer then
        instance.segment_retry_timer:close()
        instance.segment_retry_timer = nil
    end
end

init_input_module.hls = function(conf)
    if conf.format == "https" and not https_native_supported() then
        log.error("[hls] https is not supported (OpenSSL not available)")
        return nil
    end
    local instance_id = conf.host .. ":" .. conf.port .. conf.path
    local instance = hls_input_instance_list[instance_id]

    if not instance then
        if conf.ua and not conf.user_agent then
            conf.user_agent = conf.ua
        end
        local res = resolve_input_resilience(conf)
        local hls_defaults = profile_hls_input_defaults()
        if res and res.enabled and type(res.hls_defaults) == "table" then
            -- В profile-mode используем input_resilience.hls_defaults как основу, но
            -- сохраняем совместимость: отсутствующие поля берём из старых дефолтов.
            hls_defaults = profile_hls_input_defaults()
            for k, v in pairs(res.hls_defaults) do
                hls_defaults[k] = v
            end
        end
        instance = {
            clients = 0,
            config = conf,
            queue = {},
            queued = {},
            net_cfg = build_net_resilience(conf, res),
            net = nil,
            hls = {
                state = "init",
                playlist_ok = false,
                last_seq = nil,
                last_reload_ts = nil,
                last_segment_ts = nil,
                segment_errors_total = 0,
                stall_events_total = 0,
                gap_count = 0,
                max_segments = hls_cfg_number(conf, "hls_max_segments", hls_defaults.max_segments),
                max_gap_segments = hls_cfg_number(conf, "hls_max_gap_segments", hls_defaults.max_gap_segments),
                segment_retries = hls_cfg_number(conf, "hls_segment_retries", hls_defaults.segment_retries),
                max_parallel = hls_cfg_number(conf, "hls_max_parallel", hls_defaults.max_parallel),
            },
            transmit = transmit({ instance_id = instance_id }),
            playlist_conf = {
                host = conf.host,
                port = conf.port,
                path = conf.path,
                login = conf.login,
                password = conf.password,
                format = conf.format == "https" and "https" or "http",
            },
        }
        if instance.hls.max_parallel ~= nil then
            local mp = tonumber(instance.hls.max_parallel) or 1
            if mp < 1 then mp = 1 end
            if mp > 2 then mp = 2 end
            instance.hls.max_parallel = mp
        end
        instance.net = net_make_state(instance.net_cfg)

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
