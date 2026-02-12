-- Stream sharding orchestration helpers (systemd).
--
-- NOTE: Sharding is multi-process. This module only manages systemd units/env files.
-- It does not change the streaming pipeline itself.

sharding = sharding or {}

local function header_value(headers, key)
    if not headers then
        return nil
    end
    return headers[key] or headers[string.lower(key)] or headers[string.upper(key)]
end

local function sh_quote(text)
    local value = tostring(text or "")
    return "'" .. value:gsub("'", "'\\''") .. "'"
end

local function path_dirname(path)
    if type(path) ~= "string" then
        return nil
    end
    local dir = path:match("^(.*)/[^/]+$")
    if not dir or dir == "" then
        return nil
    end
    return dir
end

local function read_file(path)
    local f = io.open(path, "rb")
    if not f then
        return nil
    end
    local body = f:read("*a")
    f:close()
    return body
end

local function write_file_atomic(path, body)
    if type(path) ~= "string" or path == "" then
        return nil, "empty path"
    end
    local dir = path_dirname(path)
    if dir and dir ~= "" then
        os.execute("mkdir -p " .. sh_quote(dir))
    end
    local tmp = path .. ".tmp." .. tostring(os.time()) .. "." .. tostring(math.random(1000, 9999))
    local f, err = io.open(tmp, "wb")
    if not f then
        return nil, err
    end
    f:write(body or "")
    f:close()
    os.execute("chmod 600 " .. sh_quote(tmp) .. " >/dev/null 2>&1 || true")
    local ok = os.rename(tmp, path)
    if not ok then
        os.execute("rm -f " .. sh_quote(tmp) .. " >/dev/null 2>&1 || true")
        return nil, "rename failed"
    end
    return true
end

local function exec_ok(cmd)
    local res = os.execute(cmd)
    if res == true or res == 0 then
        return true
    end
    return nil, tostring(res)
end

local function clamp_int(v, min_v, max_v)
    local n = tonumber(v)
    if not n then
        return nil
    end
    n = math.floor(n)
    if n < min_v then
        n = min_v
    end
    if n > max_v then
        n = max_v
    end
    return n
end

local function setting_bool(key, fallback)
    if not (config and config.get_setting) then
        return fallback
    end
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
    return fallback
end

local function setting_number(key, fallback)
    if not (config and config.get_setting) then
        return fallback
    end
    local value = tonumber(config.get_setting(key))
    if value == nil then
        return fallback
    end
    return value
end

local function detect_systemd_unit_name()
    -- Prefer cgroup info (works inside systemd service).
    local raw = read_file("/proc/self/cgroup") or ""
    local unit = raw:match("(astral%-sharded@[^/%s]+%.service)")
    if unit then
        return unit
    end
    unit = raw:match("(astral@[^/%s]+%.service)")
    if unit then
        return unit
    end
    return nil
end

local function parse_shard_prefix(unit_name)
    if not unit_name then
        return nil, nil, "systemd unit not detected"
    end
    local instance = unit_name:match("^astral%-sharded@(.+)%.service$")
    if instance then
        local prefix, idx = instance:match("^(.+)%-%s*sh(%d+)$")
        if prefix then
            return prefix, tonumber(idx) or 0
        end
        return instance, 0
    end
    instance = unit_name:match("^astral@(.+)%.service$")
    if instance then
        return instance, 0
    end
    return nil, nil, "unsupported unit: " .. tostring(unit_name)
end

local function sanitize_prefix(prefix)
    local value = tostring(prefix or "")
    if value == "" then
        return nil
    end
    if not value:match("^[A-Za-z0-9][A-Za-z0-9_-]*$") then
        return nil
    end
    return value
end

local function build_env_text(vars)
    local lines = {}
    for k, v in pairs(vars or {}) do
        if v ~= nil and v ~= "" then
            table.insert(lines, tostring(k) .. "=" .. tostring(v))
        end
    end
    table.sort(lines)
    return table.concat(lines, "\n") .. "\n"
end

local function systemctl_available()
    local ok = os.execute("command -v systemctl >/dev/null 2>&1")
    return ok == true or ok == 0
end

local function detect_active_shard_max_index(prefix)
    local safe_prefix = sanitize_prefix(prefix)
    if not safe_prefix or not systemctl_available() then
        return -1
    end
    local pattern = "astral%-sharded@" .. safe_prefix .. "%-sh(%d+)%.service"
    local filter = "astral-sharded@" .. safe_prefix .. "-sh*.service"
    local cmd = "systemctl list-units --type=service --all --no-legend --plain "
        .. sh_quote(filter) .. " 2>/dev/null"
    local f = io.popen(cmd, "r")
    if not f then
        return -1
    end
    local max_idx = -1
    for line in f:lines() do
        local idx = tonumber((line or ""):match(pattern))
        if idx and idx > max_idx then
            max_idx = idx
        end
    end
    f:close()
    return max_idx
end

local stream_map_cache = { raw = nil, map = nil }

local function decode_stream_sharding_map()
    if not (config and config.get_setting) then
        return nil
    end
    local raw = config.get_setting("stream_sharding_map")
    if raw == stream_map_cache.raw then
        return stream_map_cache.map
    end
    stream_map_cache.raw = raw
    stream_map_cache.map = nil
    if raw == nil or raw == "" then
        return nil
    end
    if not json or type(json.decode) ~= "function" then
        return nil
    end
    local ok, decoded = pcall(json.decode, raw)
    if not ok or type(decoded) ~= "table" then
        return nil
    end
    stream_map_cache.map = decoded
    return decoded
end

local function encode_stream_sharding_map(map)
    if not json or type(json.encode) ~= "function" then
        return nil
    end
    local ok, encoded = pcall(json.encode, map)
    if not ok then
        return nil
    end
    return encoded
end

local function build_shard_env(prefix, idx, shard_count, base_port, config_path, env_dir, shared_data_dir)
    local instance = tostring(prefix) .. "-sh" .. tostring(idx)
    local port = base_port + idx
    local data_dir = tostring(shared_data_dir or "")
    if data_dir == "" then
        data_dir = env_dir .. "/" .. tostring(prefix) .. "-sh0.data"
    end

    local extra = {}
    -- Explicit sharding via CLI keeps runtime deterministic even if settings are not loaded.
    if shard_count and shard_count > 1 then
        table.insert(extra, "--stream-shard " .. tostring(idx) .. "/" .. tostring(shard_count))
    end
    table.insert(extra, "--data-dir " .. sh_quote(data_dir))
    table.insert(extra, "--http-play-port " .. tostring(port))
    -- In shared-db sharded setups only one instance should import the config file on boot.
    -- This avoids SQLite write contention during parallel restarts.
    if idx ~= 0 then
        table.insert(extra, "--no-import")
    end

    local env = {
        CONFIG = config_path,
        PORT = tostring(port),
        EXTRA_OPTS = table.concat(extra, " "),
    }

    local web_dir = os.getenv("ASTRA_WEB_DIR") or os.getenv("ASTRAL_WEB_DIR")
    if web_dir and web_dir ~= "" then
        env.ASTRA_WEB_DIR = web_dir
    end
    local cpus = os.getenv("CPUS")
    if cpus and cpus ~= "" then
        env.CPUS = cpus
    end

    return {
        instance = instance,
        service = "astral-sharded@" .. instance .. ".service",
        env_path = env_dir .. "/" .. instance .. ".env",
        data_dir = data_dir,
        port = port,
        env_text = build_env_text(env),
    }
end

-- Apply sharding by (re)starting `astral-sharded@<prefix>-shX` units.
-- This is intentionally conservative:
-- - Requires systemd + running under astral-sharded@... service (to derive prefix).
-- - Writes env files next to the primary config (usually /etc/astral).
-- - Restarts services after env update.
function sharding.apply_systemd()
    if not systemctl_available() then
        return nil, "systemctl not found"
    end
    if runtime and tonumber(runtime.stream_shard_count or 0) > 1 and tonumber(runtime.stream_shard_index or 0) ~= 0 then
        return nil, "apply sharding must be executed on shard 0"
    end

    local unit = detect_systemd_unit_name()
    local prefix, _, err = parse_shard_prefix(unit)
    prefix = sanitize_prefix(prefix)
    if not prefix then
        return nil, err or "invalid shard prefix"
    end

    local enabled = setting_bool("stream_sharding_enabled", false)

    local shards = clamp_int(setting_number("stream_sharding_shards", 1), 1, 64) or 1
    local base_port = clamp_int(setting_number("stream_sharding_base_port", 0), 1, 65535)
    if not enabled then
        shards = 1
    elseif shards < 2 then
        shards = 2
    end

    local config_path = (config and config.get_primary_config_path and config.get_primary_config_path()) or os.getenv("CONFIG")
    if not config_path or config_path == "" then
        return nil, "primary config path not set (start with --config)"
    end
    local env_dir = path_dirname(config_path) or "/etc/astral"
    local shared_data_dir = (config and config.data_dir) or (env_dir .. "/" .. tostring(prefix) .. "-sh0.data")

    if not base_port then
        -- Fall back to current http_port or current listen port.
        local stored = (config and config.get_setting and config.get_setting("http_port")) or nil
        base_port = clamp_int(stored, 1, 65535) or 0
    end
    if base_port <= 0 then
        return nil, "missing base port"
    end
    if base_port + shards - 1 > 65535 then
        return nil, "port range out of bounds"
    end

    -- Stable stream_id -> shard mapping.
    -- Why: users expect stream ports to stay the same across sharding enable/disable cycles.
    -- The mapping lives in settings (shared sqlite) and is used by runtime.lua for stream filtering,
    -- and by master API/UI for routing (/play, /live, status aggregation).
    if enabled and shards >= 2 and config and config.set_setting and config.list_streams then
        local map_initialized = setting_bool("stream_sharding_map_initialized", false)
        local map_shards = clamp_int(setting_number("stream_sharding_map_shards", 0), 0, 64) or 0
        local applied = clamp_int(setting_number("stream_sharding_applied_shards", 0), 0, 64) or 0

        local map = decode_stream_sharding_map()
        if not map_initialized or type(map) ~= "table" then
            map = {}

            -- Preserve the current legacy bucket distribution when sharding was already applied before mapping existed.
            -- This avoids "stream migration" on upgrade.
            local init_shards = shards
            if applied and applied >= 2 then
                init_shards = applied
            end

            local ids = {}
            for _, row in ipairs(config.list_streams() or {}) do
                if row and row.id then
                    ids[#ids + 1] = tostring(row.id)
                end
            end
            table.sort(ids)
            for i, sid in ipairs(ids) do
                if applied and applied >= 2 then
                    map[sid] = sharding.stream_bucket(sid, applied)
                else
                    map[sid] = (i - 1) % init_shards
                end
            end

            local encoded = encode_stream_sharding_map(map)
            if not encoded then
                return nil, "failed to encode stream sharding map"
            end
            config.set_setting("stream_sharding_map", encoded)
            config.set_setting("stream_sharding_map_initialized", true)
            config.set_setting("stream_sharding_map_shards", init_shards)
            map_shards = init_shards
            log.warning(string.format(
                "[sharding] stream map initialized (%s, shards=%d, streams=%d)",
                (applied and applied >= 2) and "preserve-md5" or "round-robin",
                init_shards,
                #ids
            ))
        end

        -- Validate existing map against the requested shard count.
        -- We allow increasing shard count (new shards start empty), but disallow shrinking below used indices.
        if map_shards > 0 and map_shards > shards then
            return nil, string.format(
                "stream sharding map was created for %d shards; refusing to apply %d shards (would move streams). " ..
                "Increase shard count or reset mapping.",
                map_shards,
                shards
            )
        end

        local counts = {}
        for i = 0, shards - 1 do
            counts[i] = 0
        end
        local max_idx = -1
        for sid, v in pairs(map or {}) do
            local idx = tonumber(v)
            if idx and idx >= 0 then
                idx = math.floor(idx)
                if idx > max_idx then
                    max_idx = idx
                end
                if idx < shards then
                    counts[idx] = (counts[idx] or 0) + 1
                end
            end
        end
        if max_idx >= shards then
            return nil, string.format(
                "stream sharding map contains shard index %d, but shard count is %d. " ..
                "Increase shard count or reset mapping.",
                max_idx,
                shards
            )
        end

        -- Ensure new streams are assigned deterministically (least-loaded shard), without changing existing ids.
        local changed = false
        for _, row in ipairs(config.list_streams() or {}) do
            local sid = row and row.id and tostring(row.id) or nil
            if sid and sid ~= "" then
                local cur = map[sid]
                local idx = tonumber(cur)
                if not idx or idx < 0 or idx >= shards then
                    -- Find least-loaded shard.
                    local best = 0
                    local best_count = counts[0] or 0
                    for i = 1, shards - 1 do
                        local c = counts[i] or 0
                        if c < best_count then
                            best = i
                            best_count = c
                        end
                    end
                    map[sid] = best
                    counts[best] = (counts[best] or 0) + 1
                    changed = true
                end
            end
        end
        if changed then
            local encoded = encode_stream_sharding_map(map)
            if encoded then
                config.set_setting("stream_sharding_map", encoded)
                log.warning("[sharding] stream map updated (new streams assigned)")
            end
        end
    end

    -- Ensure primary config is exported before restarting shards, so they import latest settings/streams.
    if config and config.primary_config_is_json and config.primary_config_is_json()
        and config.export_primary_config
    then
        local ok, export_err = config.export_primary_config()
        if not ok then
            return nil, "config export failed: " .. tostring(export_err)
        end
    end

    -- Reconfigure shard units.
    local plan = {}
    for i = 0, shards - 1 do
        table.insert(plan, build_shard_env(prefix, i, shards, base_port, config_path, env_dir, shared_data_dir))
    end

    -- Disable extra shards from previous runs.
    local last = clamp_int((config and config.get_setting and config.get_setting("stream_sharding_applied_shards")) or 0, 0, 64) or 0
    local map_shards = clamp_int((config and config.get_setting and config.get_setting("stream_sharding_map_shards")) or 0, 0, 64) or 0
    local running_max_idx = detect_active_shard_max_index(prefix)
    local running_count = (running_max_idx and running_max_idx >= 0) and (running_max_idx + 1) or 0
    local max_disable = math.max(last, map_shards, running_count, shards, 1)
    for i = shards, max_disable - 1 do
        local instance = tostring(prefix) .. "-sh" .. tostring(i)
        local service = "astral-sharded@" .. instance .. ".service"
        -- Best-effort stop/disable (ignore errors if unit does not exist).
        os.execute("systemctl disable --now " .. sh_quote(service) .. " >/dev/null 2>&1 || true")
    end

    for _, item in ipairs(plan) do
        os.execute("mkdir -p " .. sh_quote(item.data_dir) .. " >/dev/null 2>&1 || true")
        local ok, werr = write_file_atomic(item.env_path, item.env_text)
        if not ok then
            return nil, "failed to write env: " .. tostring(item.env_path) .. ": " .. tostring(werr)
        end
        local ok1 = exec_ok("systemctl enable " .. sh_quote(item.service) .. " >/dev/null 2>&1")
        if not ok1 then
            return nil, "systemctl enable failed: " .. item.service
        end
    end

    -- Restart in one batch so config import is consistent across all shards.
    local services = {}
    for _, item in ipairs(plan) do
        table.insert(services, sh_quote(item.service))
    end
    local restart_cmd = "systemctl restart " .. table.concat(services, " ")
    local ok2, e2 = exec_ok(restart_cmd)
    if not ok2 then
        return nil, "systemctl restart failed: " .. tostring(e2)
    end

    if config and config.set_setting then
        config.set_setting("stream_sharding_applied_shards", shards)
        config.set_setting("stream_sharding_applied_base_port", base_port)
    end

    return true
end

-- Best-effort reload of all shard processes after config/settings changes.
-- Used when shards share one sqlite store; otherwise each process keeps old in-memory config.
-- force=nil/true  -> full reload (историческое поведение)
-- force=false     -> soft reload без force-пересборки всех стримов
function sharding.broadcast_reload(force)
    if not http_request then
        return false
    end
    local shard_count = tonumber(runtime and runtime.stream_shard_count or 0) or 0
    local shard_index = tonumber(runtime and runtime.stream_shard_index or 0) or 0
    if shard_count < 2 then
        return false
    end
    local port = tonumber((config and config.get_setting and config.get_setting("http_port")) or 0) or 0
    if port <= 0 then
        return false
    end
    local base_port = port - shard_index
    if base_port <= 0 then
        return false
    end

    for i = 0, shard_count - 1 do
        local p = base_port + i
        if p ~= port then
            local host_header = "127.0.0.1:" .. tostring(p)
            local path = "/api/v1/reload-internal"
            if force == false then
                path = path .. "?force=0"
            end
            pcall(http_request, {
                host = "127.0.0.1",
                port = p,
                path = path,
                method = "POST",
                headers = {
                    "Host: " .. host_header,
                    "Connection: close",
                    "Content-Length: 0",
                },
                callback = function(self, response)
                    -- ignore failures; shards might be down during restart.
                    return
                end,
            })
        end
    end
    return true
end

-- ==========
-- Routing helpers (multi-process sharding)
-- ==========

-- Return true when this process is running in an active multi-shard mode.
-- NOTE: This depends on runtime (stream filtering), not just settings.
function sharding.is_active()
    local n = tonumber(runtime and runtime.stream_shard_count or 0) or 0
    local i = runtime and runtime.stream_shard_index
    return n > 1 and i ~= nil
end

function sharding.get_shard_count()
    return tonumber(runtime and runtime.stream_shard_count or 0) or 0
end

function sharding.get_shard_index()
    local i = runtime and runtime.stream_shard_index
    if i == nil then
        return nil
    end
    return tonumber(i) or 0
end

function sharding.is_master()
    local i = sharding.get_shard_index()
    return i ~= nil and i == 0
end

-- Current process listen port (runtime override).
local function local_port()
    local p = tonumber(config and config.get_setting and config.get_setting("http_port") or 0) or 0
    if p <= 0 then
        return nil
    end
    return p
end

-- Base port for the sharded cluster. Derived from local port and shard index.
function sharding.get_base_port()
    if not sharding.is_active() then
        return nil
    end
    local p = local_port()
    if not p then
        return nil
    end
    local idx = tonumber(sharding.get_shard_index() or 0) or 0
    return p - idx
end

function sharding.get_shard_port(idx)
    if not sharding.is_active() then
        return nil
    end
    local base = sharding.get_base_port()
    if not base then
        return nil
    end
    local i = tonumber(idx)
    if not i or i < 0 then
        return nil
    end
    return base + i
end

-- Deterministic shard bucket for a stream id.
-- Must match runtime.lua (stream_shard_bucket) logic.
function sharding.stream_bucket(id, shard_count)
    local text = tostring(id or "")
    local n = tonumber(shard_count) or 0
    if text == "" or n <= 1 then
        return 0
    end
    local hex = string.hex(string.md5(text))
    local head = hex and hex:sub(1, 8) or "0"
    local v = tonumber(head, 16) or 0
    return v % n
end

function sharding.get_stream_shard_index(stream_id)
    if not sharding.is_active() then
        return 0
    end
    local n = tonumber(runtime and runtime.stream_shard_count or 0) or 0
    if n <= 1 then
        return 0
    end
    local id = tostring(stream_id or "")
    if id ~= "" then
        local map = decode_stream_sharding_map()
        if type(map) == "table" then
            local v = map[id]
            local idx = tonumber(v)
            if idx and idx >= 0 and idx < n then
                return math.floor(idx)
            end
        end
    end
    return sharding.stream_bucket(id, n)
end

function sharding.get_stream_shard_port(stream_id)
    if not sharding.is_active() then
        return nil
    end
    local idx = sharding.get_stream_shard_index(stream_id)
    return sharding.get_shard_port(idx)
end

function sharding.get_cluster_ports()
    if not sharding.is_active() then
        return {}
    end
    local n = tonumber(runtime and runtime.stream_shard_count or 0) or 0
    local base = sharding.get_base_port()
    if not base or n < 2 then
        return {}
    end
    local out = {}
    for i = 0, n - 1 do
        out[#out + 1] = base + i
    end
    return out
end

-- Build headers for internal shard-to-shard API requests.
-- We only forward auth-related headers; other values (Host/Connection/Content-Length)
-- are always re-generated.
function sharding.forward_auth_headers(request, port, extra)
    local headers = {}
    local req_headers = request and request.headers or {}

    local cookie = header_value(req_headers, "cookie")
    if cookie and cookie ~= "" then
        headers[#headers + 1] = "Cookie: " .. tostring(cookie)
    end
    local authz = header_value(req_headers, "authorization")
    if authz and authz ~= "" then
        headers[#headers + 1] = "Authorization: " .. tostring(authz)
    end
    local csrf = header_value(req_headers, "x-csrf-token")
    if csrf and csrf ~= "" then
        headers[#headers + 1] = "X-CSRF-Token: " .. tostring(csrf)
    end

    headers[#headers + 1] = "Host: 127.0.0.1:" .. tostring(port)
    headers[#headers + 1] = "Connection: close"

    if type(extra) == "table" then
        for _, h in ipairs(extra) do
            if h and h ~= "" then
                headers[#headers + 1] = h
            end
        end
    end
    return headers
end
