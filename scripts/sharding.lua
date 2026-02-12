-- Stream sharding orchestration helpers (systemd).
--
-- NOTE: Sharding is multi-process. This module only manages systemd units/env files.
-- It does not change the streaming pipeline itself.

sharding = sharding or {}

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

    local enabled = false
    if config and config.get_setting then
        enabled = (config.get_setting("stream_sharding_enabled") == true)
    end

    local shards = 1
    local base_port = nil
    if config and config.get_setting then
        shards = clamp_int(config.get_setting("stream_sharding_shards"), 1, 64) or 1
        base_port = clamp_int(config.get_setting("stream_sharding_base_port"), 1, 65535)
    end
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
    local max_disable = math.max(last, shards, 1)
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
function sharding.broadcast_reload()
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
            pcall(http_request, {
                host = "127.0.0.1",
                port = p,
                path = "/api/v1/reload",
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
