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

-- 6) Portal-only backend config: Ministra endpoint is auto-resolved
do
    config._settings = {
        auth_backends = {
            main = {
                provider = "ministra",
                portal_url = "http://name.com/stalker_portal",
                allow_default = false,
            },
        },
        auth_allow_no_token = true,
    }
    responses_by_host["name.com"] = function(req)
        local path = tostring(req and req.path or "")
        if path:find("^/stalker_portal/server/api/chk_flussonic_tmp_link%.php%?") then
            return { code = 200, headers = {} }
        end
        return { code = 404, headers = {} }
    end

    local ctx = {
        stream_id = "test",
        stream_name = "Test",
        stream_cfg = { on_play = "auth://main" },
        proto = "http_ts",
        request = make_request({ ["user-agent"] = "UA" }, { token = "m1" }),
        ip = "1.2.3.4",
    }
    auth.check_play(ctx, function(allowed, entry)
        assert_eq(allowed, true, "portal-only ministra allow")
        assert_eq(entry.status, "ALLOW", "portal-only ministra status")
    end)
end

-- 6b) Portal-only backend config: TMS endpoint is auto-resolved
do
    config._settings = {
        auth_backends = {
            main = {
                provider = "tms",
                portal_url = "http://name.com/",
                allow_default = false,
            },
        },
        auth_allow_no_token = true,
    }
    responses_by_host["name.com"] = function(req)
        local path = tostring(req and req.path or "")
        if path:find("^/api/drm/auth_token%?") then
            return { code = 200, headers = {} }
        end
        return { code = 404, headers = {} }
    end

    local ctx = {
        stream_id = "test",
        stream_name = "Test",
        stream_cfg = { on_play = "auth://main" },
        proto = "http_ts",
        request = make_request({ ["user-agent"] = "UA" }, { token = "tms1" }),
        ip = "1.2.3.4",
    }
    auth.check_play(ctx, function(allowed, entry)
        assert_eq(allowed, true, "portal-only tms allow")
        assert_eq(entry.status, "ALLOW", "portal-only tms status")
    end)
end

-- 6c) Portal-only backend config: static portal_params are propagated
do
    config._settings = {
        auth_backends = {
            main = {
                provider = "tms",
                portal_url = "http://name.com/",
                portal_params = {
                    token = "abc",
                    foo = "bar",
                },
                allow_default = false,
            },
        },
        auth_allow_no_token = true,
    }
    responses_by_host["name.com"] = function(req)
        local path = tostring(req and req.path or "")
        if path:find("^/api/drm/auth_token%?") and path:find("token=abc", 1, true) and path:find("foo=bar", 1, true) then
            return { code = 200, headers = {} }
        end
        return { code = 404, headers = {} }
    end

    local ctx = {
        stream_id = "test",
        stream_name = "Test",
        stream_cfg = { on_play = "auth://main" },
        proto = "http_ts",
        request = make_request({ ["user-agent"] = "UA" }, { token = "tms2" }),
        ip = "1.2.3.4",
    }
    auth.check_play(ctx, function(allowed, entry)
        assert_eq(allowed, true, "portal-only params allow")
        assert_eq(entry.status, "ALLOW", "portal-only params status")
    end)
end

-- 6d) backend list + portal_params: first backend receives params when params are absent
do
    config._settings = {
        auth_backends = {
            main = {
                provider = "tms",
                portal_url = "http://name.com/",
                portal_params = {
                    token = "from_portal",
                },
                backends = {
                    { url = "http://name.com/api/drm/auth_token" },
                },
                allow_default = false,
            },
        },
        auth_allow_no_token = true,
    }
    responses_by_host["name.com"] = function(req)
        local path = tostring(req and req.path or "")
        if path:find("^/api/drm/auth_token%?") and path:find("token=from_portal", 1, true) then
            return { code = 200, headers = {} }
        end
        return { code = 404, headers = {} }
    end

    local ctx = {
        stream_id = "test",
        stream_name = "Test",
        stream_cfg = { on_play = "auth://main" },
        proto = "http_ts",
        request = make_request({ ["user-agent"] = "UA" }, { token = "tms3" }),
        ip = "1.2.3.4",
    }
    auth.check_play(ctx, function(allowed, entry)
        assert_eq(allowed, true, "backend list + portal params allow")
        assert_eq(entry.status, "ALLOW", "backend list + portal params status")
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

    -- legacy default: query token + cookie stream_token (fallback: astra_token)
    local req4 = make_request({ ["cookie"] = "stream_token=LEGACY" }, {})
    local token4 = auth.get_token(req4, "token", "")
    assert_eq(token4, "LEGACY", "token legacy cookie")

    local req5 = make_request({ ["cookie"] = "astra_token=LEGACY2" }, {})
    local token5 = auth.get_token(req5, "token", "")
    assert_eq(token5, "LEGACY2", "token legacy cookie fallback")
end

-- 8) Trusted IPs may read media without credentials, but not the UI/API.
do
    config._settings = {
        http_auth_enabled = true,
        http_auth_users = false,
        http_auth_allow = "185.216.46.0/24,185.216.44.0/24",
        http_auth_deny = "",
        http_auth_tokens = "",
    }

    local media_paths = {
        "/play/channel_id",
        "/live/channel_id",
        "/input/channel_id",
        "/dvr/play/channel_id",
    }
    for _, path in ipairs(media_paths) do
        local allowed = http_auth_check({
            addr = "185.216.46.23",
            path = path,
            headers = {},
            query = {},
        })
        assert_eq(allowed, true, "trusted media path " .. path)
    end

    local ui_allowed = http_auth_check({
        addr = "185.216.46.23",
        path = "/",
        headers = {},
        query = {},
    })
    assert_eq(ui_allowed, false, "trusted UI still requires credentials")

    local api_allowed = http_auth_check({
        addr = "185.216.46.23",
        path = "/api/v1/streams",
        headers = {},
        query = {},
    })
    assert_eq(api_allowed, false, "trusted API still requires credentials")
end

-- 9) Outside addresses remain blocked and deny always wins over allow.
do
    config._settings = {
        http_auth_enabled = true,
        http_auth_users = false,
        http_auth_allow = "185.216.46.0/24,185.216.44.0/24",
        http_auth_deny = "",
        http_auth_tokens = "",
    }
    local outside_allowed = http_auth_check({
        addr = "185.216.45.23",
        path = "/play/channel_id",
        headers = {},
        query = {},
    })
    assert_eq(outside_allowed, false, "outside media blocked")

    config._settings.http_auth_deny = "185.216.46.23"
    local denied_allowed = http_auth_check({
        addr = "185.216.46.23",
        path = "/play/channel_id",
        headers = {},
        query = {},
    })
    assert_eq(denied_allowed, false, "deny overrides trusted media allow")
end

print("auth_backend_unit: ok")
astra.exit()
