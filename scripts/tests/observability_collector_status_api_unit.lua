log.set({ debug = true })

dofile("scripts/base.lua")
dofile("scripts/config.lua")
dofile("scripts/api.lua")

local function assert_true(v, msg)
    if not v then
        error(msg or "assert")
    end
end

config = config or {}
config.get_setting = function(key)
    if key == "http_auth_enabled" then
        return false
    end
    if key == "observability_enabled" then
        return true
    end
    return nil
end
config.get_user_by_username = function(username)
    if username == "admin" then
        return { id = 1, username = "admin", is_admin = 1 }
    end
    return nil
end
config.get_user_by_id = function(id)
    if tonumber(id) == 1 then
        return { id = 1, username = "admin", is_admin = 1 }
    end
    return nil
end

ai_observability = {
    get_collector_status = function()
        return {
            collection_enabled = true,
            read_only_mode = false,
            worker_isolated = false,
            worker_affinity = "auto:last-2",
            worker_backend = "thread",
            writer_db = "/var/lib/stream/observability.db",
            degrade_mode = false,
            writer_queue_depth = 12,
        }
    end,
}

local sent = nil
local server = {
    send = function(_, _, payload)
        sent = payload
    end,
}
local client = {}

api.handle_request(server, client, {
    method = "GET",
    path = "/api/v1/observability/collector/status",
    addr = "127.0.0.1",
    headers = {},
    query = {},
})

assert_true(sent ~= nil, "expected response")
assert_true(tonumber(sent.code) == 200, "expected 200")
local ok, payload = pcall(json.decode, sent.content or "{}")
assert_true(ok and type(payload) == "table", "expected json payload")
assert_true(payload.collection_enabled == true, "expected collection_enabled=true")
assert_true(payload.worker_affinity == "auto:last-2", "expected worker_affinity")
assert_true(payload.worker_backend == "thread", "expected worker_backend")
assert_true(payload.writer_db == "/var/lib/stream/observability.db", "expected writer_db")
assert_true(payload.writer_queue_depth == 12, "expected writer_queue_depth")

print("observability_collector_status_api_unit: ok")
astra.exit()
