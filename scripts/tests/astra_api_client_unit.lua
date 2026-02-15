-- Cesbo Astra API client unit tests (basic request building + retries + errors)

dofile("scripts/base.lua")
dofile("scripts/astra_api_client.lua")

local function assert_true(v, msg)
    if not v then
        error(msg or "assert")
    end
end

local function assert_eq(a, b, msg)
    if a ~= b then
        error((msg or "assert") .. ": expected " .. tostring(b) .. ", got " .. tostring(a))
    end
end

local function find_header(headers, prefix)
    for _, line in ipairs(headers or {}) do
        if tostring(line):find(prefix, 1, true) == 1 then
            return tostring(line)
        end
    end
    return nil
end

-- timer stub: execute immediately (so retry happens synchronously in unit tests)
timer = function(opts)
    local self = { close = function() end }
    if opts and type(opts.callback) == "function" then
        opts.callback(self)
    end
    return self
end

-- http_request stub
local requests = {}
local scripted_responses = {}
http_request = function(req)
    table.insert(requests, req)
    local idx = #requests
    local response = scripted_responses[idx]
    if type(response) == "function" then
        response = response(req, idx)
    end
    if response == nil then
        response = { code = 0, message = "timeout", headers = {}, content = "" }
    end
    if type(req.callback) == "function" then
        req.callback(req, response)
    end
end

-- 1) GET /api/system-status builds path + Basic Auth header
do
    requests = {}
    scripted_responses = {
        { code = 200, headers = {}, content = "{\"ok\":true}" },
    }

    local client, err = AstraApiClient.new({
        baseUrl = "http://example.com:8000",
        login = "admin",
        password = "pass",
        max_attempts = 1,
        debug = false,
    })
    assert_true(client ~= nil, err)

    client:GetSystemStatus(1, function(ok, data)
        assert_eq(ok, true, "GetSystemStatus ok")
        assert_true(type(data) == "table" and data.ok == true, "GetSystemStatus json parsed")
    end)

    assert_eq(#requests, 1, "one request")
    local req = requests[1]
    assert_eq(req.method, "GET", "method get")
    assert_eq(req.path, "/api/system-status?t=1", "path with query")
    local auth = find_header(req.headers, "Authorization: Basic ")
    assert_true(auth ~= nil, "basic auth header present")
    local expect = "Authorization: Basic " .. base64.encode("admin:pass")
    assert_eq(auth, expect, "basic auth header value")
end

-- 2) POST /control/ restart-stream builds JSON body
do
    requests = {}
    scripted_responses = {
        { code = 200, headers = {}, content = "{\"result\":\"ok\"}" },
    }

    local client, err = AstraApiClient.new({
        baseUrl = "http://127.0.0.1:8000",
        login = "u",
        password = "p",
        max_attempts = 1,
    })
    assert_true(client ~= nil, err)

    client:RestartStream("a001", function(ok, data)
        assert_eq(ok, true, "RestartStream ok")
        assert_true(type(data) == "table" and data.result == "ok", "RestartStream parsed")
    end)

    assert_eq(#requests, 1, "one request")
    local req = requests[1]
    assert_eq(req.method, "POST", "method post")
    assert_eq(req.path, "/control/", "control path")
    local decoded = json.decode(req.content or "{}")
    assert_eq(decoded.cmd, "restart-stream", "cmd")
    assert_eq(decoded.id, "a001", "id")
end

-- 3) Retry: first timeout(code=0) then success
do
    requests = {}
    scripted_responses = {
        { code = 0, message = "timeout", headers = {}, content = "" },
        { code = 200, headers = {}, content = "{\"x\":1}" },
    }

    local client, err = AstraApiClient.new({
        baseUrl = "http://127.0.0.1:8000",
        login = "u",
        password = "p",
        max_attempts = 3,
        retry_backoff_ms = 1,
        retry_jitter_pct = 0,
    })
    assert_true(client ~= nil, err)

    client:GetVersion(function(ok, data)
        assert_eq(ok, true, "retry ok")
        assert_true(type(data) == "table" and data.x == 1, "retry json parsed")
    end)

    assert_eq(#requests, 2, "two attempts")
end

-- 4) HTTP error propagates (no retry for 4xx)
do
    requests = {}
    scripted_responses = {
        { code = 403, headers = {}, content = "{\"err\":\"denied\"}" },
    }

    local client, err = AstraApiClient.new({
        baseUrl = "http://127.0.0.1:8000",
        login = "u",
        password = "p",
        max_attempts = 3,
        retry_backoff_ms = 1,
        retry_jitter_pct = 0,
    })
    assert_true(client ~= nil, err)

    client:GetSessions(function(ok, data)
        assert_eq(ok, false, "4xx fails")
        assert_true(tostring(data):find("http 403", 1, true) ~= nil, "error contains status")
    end)

    assert_eq(#requests, 1, "no retry on 4xx")
end

print("astra_api_client_unit: ok")
astra.exit()

