-- Auth backend unit tests (Flussonic-like allow/deny, multi-backend, session keys)

dofile("scripts/base.lua")
dofile("scripts/auth.lua")

local function assert_eq(a, b, label)
    if a ~= b then
        error((label or "assert") .. ": expected " .. tostring(b) .. ", got " .. tostring(a))
    end
end

-- Minimal config stub
config = config or {}
config._settings = {}
function config.get_setting(key)
    return config._settings[key]
end
function config.add_alert()
    -- ignore in unit tests
end

-- http_request stub: immediate responses by host
local responses_by_host = {}
http_request = function(req)
    local host = tostring(req.host or "")
    local response = responses_by_host[host]
    if type(response) == "function" then
        response = response(req)
    end
    if response == nil then
        response = { code = 0, message = "timeout", headers = {} }
    end
    if type(req.callback) == "function" then
        req.callback(req, response)
    end
end

-- Common ctx
local function make_request(headers, query)
    return {
        addr = "1.2.3.4",
        path = "/play/test.ts",
        headers = headers or {},
        query = query or {},
    }
end

-- 1) Rule allow token bypasses backend + allows even when allow_no_token=false
do
    config._settings = {
        auth_backends = {
            main = {
                allow_default = false,
                rules = { allow = { token = { "ok" } }, deny = {} },
                backends = { { url = "http://backend-deny/on_play" } },
            }
        },
        auth_allow_no_token = false,
    }
    responses_by_host["backend-deny"] = { code = 403, headers = {} }

    local ctx = {
        stream_id = "test",
        stream_name = "Test",
        stream_cfg = { on_play = "auth://main" },
        proto = "http_ts",
        request = make_request({ ["user-agent"] = "UA" }, { token = "ok" }),
        ip = "1.2.3.4",
    }
    auth.check_play(ctx, function(allowed, entry, reason)
        assert_eq(allowed, true, "rule allow")
        assert(entry and entry.session_id, "entry exists")
        assert_eq(reason, "rule_allow_token", "reason")
    end)
end

-- 2) Multi-backend: one denies, one allows -> allow
do
    config._settings = {
        auth_backends = {
            main = {
                allow_default = false,
                mode = "parallel",
                backends = {
                    { url = "http://backend-deny/on_play" },
                    { url = "http://backend-allow/on_play" },
                },
            }
        },
        auth_allow_no_token = true,
    }
    responses_by_host["backend-deny"] = { code = 403, headers = {} }
    responses_by_host["backend-allow"] = { code = 200, headers = { ["x-authduration"] = "10" } }

    local ctx = {
        stream_id = "test",
        stream_name = "Test",
        stream_cfg = { on_play = "auth://main" },
        proto = "http_ts",
        request = make_request({ ["user-agent"] = "UA" }, { token = "t1" }),
        ip = "1.2.3.4",
    }
    auth.check_play(ctx, function(allowed, entry)
        assert_eq(allowed, true, "multi allow")
        assert_eq(entry.status, "ALLOW", "status allow")
        assert(entry.expires_at and entry.expires_at > os.time(), "ttl set")
    end)
end

-- 2b) Sequential mode: 403 then 200 -> allow (try next backend)
do
    config._settings = {
        auth_backends = {
            main = {
                allow_default = false,
                mode = "sequential",
                backends = {
                    { url = "http://backend-deny/on_play" },
                    { url = "http://backend-allow/on_play" },
                },
            }
        },
        auth_allow_no_token = true,
    }
    responses_by_host["backend-deny"] = { code = 403, headers = {} }
    responses_by_host["backend-allow"] = { code = 200, headers = {} }

    local ctx = {
        stream_id = "test",
        stream_name = "Test",
        stream_cfg = { on_play = "auth://main" },
        proto = "http_ts",
        request = make_request({ ["user-agent"] = "UA" }, { token = "t1" }),
        ip = "1.2.3.4",
    }
    auth.check_play(ctx, function(allowed, entry)
        assert_eq(allowed, true, "sequential allow")
        assert_eq(entry.status, "ALLOW", "status allow")
    end)
end

-- 3) All backends down: allow_default=true -> allow
do
    config._settings = {
        auth_backends = {
            main = {
                allow_default = true,
                cache = { default_allow_sec = 5, default_deny_sec = 5 },
                backends = {
                    { url = "http://backend-a/on_play" },
                    { url = "http://backend-b/on_play" },
                },
            }
        },
        auth_allow_no_token = true,
    }
    responses_by_host["backend-a"] = { code = 0, message = "timeout", headers = {} }
    responses_by_host["backend-b"] = { code = 0, message = "timeout", headers = {} }

    local ctx = {
        stream_id = "test",
        stream_name = "Test",
        stream_cfg = { on_play = "auth://main" },
        proto = "http_ts",
        request = make_request({ ["user-agent"] = "UA" }, { token = "t2" }),
        ip = "1.2.3.4",
    }
    auth.check_play(ctx, function(allowed, entry, reason)
        assert_eq(allowed, true, "allow default")
        assert_eq(reason, "backend_default_allow", "reason")
        assert_eq(entry.status, "ALLOW", "status")
    end)
end

-- 4) Redirect: backend returns 302 Location -> deny + redirect_location
do
    config._settings = {
        auth_backends = {
            main = {
                allow_default = false,
                backends = {
                    { url = "http://backend-redirect/on_play" },
                },
            }
        },
        auth_allow_no_token = true,
    }
    responses_by_host["backend-redirect"] = {
        code = 302,
        headers = { location = "http://example.com/redirect" },
    }

    local ctx = {
        stream_id = "test",
        stream_name = "Test",
        stream_cfg = { on_play = "auth://main" },
        proto = "http_ts",
        request = make_request({ ["user-agent"] = "UA" }, { token = "t3" }),
        ip = "1.2.3.4",
    }
    auth.check_play(ctx, function(allowed, entry, reason)
        assert_eq(allowed, false, "redirect denies stream")
        assert(entry and entry.redirect_location, "redirect location present")
        assert_eq(entry.redirect_location, "http://example.com/redirect", "redirect url")
        assert_eq(reason, "backend_redirect", "reason")
    end)
end

-- 5) session_keys: header.x-playback-session-id affects session_id
do
    config._settings = {
        auth_backends = {
            main = {
                allow_default = false,
                backends = { { url = "http://backend-allow/on_play" } },
                session_keys_default = { "ip", "name", "proto", "token", "header.x-playback-session-id" },
            }
        },
        auth_allow_no_token = true,
    }
    responses_by_host["backend-allow"] = { code = 200, headers = {} }

    local ctx1 = {
        stream_id = "test",
        stream_name = "Test",
        stream_cfg = { on_play = "auth://main" },
        proto = "http_ts",
        request = make_request({ ["x-playback-session-id"] = "AAA" }, { token = "t4" }),
        ip = "1.2.3.4",
    }
    local sid1 = nil
    auth.check_play(ctx1, function(_, entry)
        sid1 = entry and entry.session_id
    end)
    local ctx2 = {
        stream_id = "test",
        stream_name = "Test",
        stream_cfg = { on_play = "auth://main" },
        proto = "http_ts",
        request = make_request({ ["x-playback-session-id"] = "BBB" }, { token = "t4" }),
        ip = "1.2.3.4",
    }
    auth.check_play(ctx2, function(_, entry)
        assert(sid1 ~= nil and entry and entry.session_id ~= nil, "session ids exist")
        assert(sid1 ~= entry.session_id, "session id differs by playback-session-id")
    end)
end

-- 7) Token source: query/header/cookie + Bearer parsing
do
    local req = make_request({ ["authorization"] = "Bearer XYZ" }, {})
    local token = auth.get_token(req, "token", "header:authorization")
    assert_eq(token, "XYZ", "token header bearer")

    local req2 = make_request({ ["cookie"] = "stb_token=ABC; other=1" }, {})
    local token2 = auth.get_token(req2, "token", "cookie:stb_token")
    assert_eq(token2, "ABC", "token cookie")

    local req3 = make_request({}, { sid = "QQ" })
    local token3 = auth.get_token(req3, "token", "query:sid")
    assert_eq(token3, "QQ", "token query")

    -- legacy default: query token + cookie astra_token
    local req4 = make_request({ ["cookie"] = "astra_token=LEGACY" }, {})
    local token4 = auth.get_token(req4, "token", "")
    assert_eq(token4, "LEGACY", "token legacy cookie")
end

print("auth_backend_unit: ok")
astra.exit()
