log.set({ debug = true })

dofile("scripts/base.lua")
local remote_servers = dofile("scripts/remote_servers.lua")

local function assert_true(value, message)
    if not value then
        error(message or "assert failed")
    end
end

local function assert_eq(actual, expected, message)
    if actual ~= expected then
        error((message or "assert eq failed") .. ": actual=" .. tostring(actual) .. " expected=" .. tostring(expected))
    end
end

local calls = {}

local function push_call(req)
    calls[#calls + 1] = {
        method = tostring(req.method or "GET"),
        path = tostring(req.path or ""),
        body = tostring(req.content or ""),
    }
end

local function count_calls(path)
    local total = 0
    for _, row in ipairs(calls) do
        if row.path == path then
            total = total + 1
        end
    end
    return total
end

local function find_call(path)
    for _, row in ipairs(calls) do
        if row.path == path then
            return row
        end
    end
    return nil
end

http_request = function(req)
    local function reply(code, payload)
        req.callback(req, {
            code = code,
            headers = {},
            content = json.encode(payload or {}),
        })
    end

    push_call(req)

    if req.path == "/api/v1/dvr/health" and req.method == "GET" then
        return reply(200, {
            status = "ok",
            version = "unit",
        })
    end

    if req.path == "/api/v1/dvr/backup/cursor/reset-bulk" and req.method == "POST" then
        return reply(200, {
            ok = true,
            total = 2,
            affected = 2,
            failed = {},
            items = {
                { stream_id = "s1", ok = true },
                { stream_id = "s2", ok = true },
            },
        })
    end

    if req.path == "/api/v1/dvr/backup/cycle/rebuild-bulk" and req.method == "POST" then
        return reply(404, {
            error = "not found",
        })
    end

    if req.path == "/api/v1/dvr/backup/cycle/rebuild" and req.method == "POST" then
        local ok, body = pcall(json.decode, req.content or "{}")
        local stream_id = ok and body and tostring(body.stream_id or "") or ""
        return reply(200, {
            ok = true,
            stream_id = stream_id,
            cycle_id = "cycle-" .. stream_id,
        })
    end

    return reply(404, { error = "not mocked", path = req.path, method = req.method })
end

local entry = {
    id = "dvr-main",
    host = "127.0.0.1",
    port = 17000,
    api_type = "dvr_v1",
    enabled = true,
}

local reset_result = nil
remote_servers.dvr_backup_cursor_reset(entry, {
    stream_ids = { "s1", "s2", "s2" },
}, function(ok, payload, err, code)
    reset_result = {
        ok = ok,
        payload = payload,
        err = err,
        code = code,
    }
end)

assert_true(type(reset_result) == "table", "missing reset callback result")
assert_true(reset_result.ok == true, "expected reset bulk success")
assert_eq(tonumber(reset_result.payload and reset_result.payload.affected), 2, "unexpected reset affected")
assert_eq(count_calls("/api/v1/dvr/backup/cursor/reset-bulk"), 1, "reset bulk endpoint must be called once")
assert_eq(count_calls("/api/v1/dvr/backup/cursor/reset"), 0, "legacy per-stream reset endpoint must not be called")
local reset_bulk_call = find_call("/api/v1/dvr/backup/cursor/reset-bulk")
assert_true(reset_bulk_call and reset_bulk_call.body ~= "", "missing reset bulk request body")
local ok_reset_body, reset_body = pcall(json.decode, reset_bulk_call.body)
assert_true(ok_reset_body and type(reset_body) == "table", "invalid reset bulk request body")
assert_eq(type(reset_body.stream_ids), "table", "reset bulk stream_ids must be array")
assert_eq(#reset_body.stream_ids, 2, "reset bulk stream_ids must be de-duplicated")

local rebuild_result = nil
remote_servers.dvr_backup_cycle_rebuild(entry, {
    stream_ids = { "s1", "s2" },
    include_partial = false,
    min_partial_sec = 120,
}, function(ok, payload, err, code)
    rebuild_result = {
        ok = ok,
        payload = payload,
        err = err,
        code = code,
    }
end)

assert_true(type(rebuild_result) == "table", "missing rebuild callback result")
assert_true(rebuild_result.ok == true, "expected rebuild fallback success")
assert_eq(tonumber(rebuild_result.payload and rebuild_result.payload.affected), 2, "unexpected rebuild affected")
assert_eq(count_calls("/api/v1/dvr/backup/cycle/rebuild-bulk"), 1, "rebuild bulk endpoint must be attempted once")
assert_eq(count_calls("/api/v1/dvr/backup/cycle/rebuild"), 2, "legacy rebuild endpoint must be called per stream")

local per_stream_include_partial_ok = 0
for _, row in ipairs(calls) do
    if row.path == "/api/v1/dvr/backup/cycle/rebuild" then
        local ok_body, body = pcall(json.decode, row.body or "{}")
        assert_true(ok_body and type(body) == "table", "invalid per-stream rebuild body")
        if body.include_partial == false and tonumber(body.min_partial_sec) == 120 then
            per_stream_include_partial_ok = per_stream_include_partial_ok + 1
        end
    end
end
assert_eq(per_stream_include_partial_ok, 2, "fallback per-stream rebuild must keep include_partial/min_partial_sec")

log.info("[unit] remote_servers_dvr_backup_bulk_unit ok")
astra.exit()
