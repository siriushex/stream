log.set({ debug = true })

local function read_file(path)
    local file = assert(io.open(path, "rb"))
    local source = file:read("*a")
    file:close()
    return source
end

local function assert_true(cond, msg)
    if not cond then error(msg or "assert failed") end
end

local index_source = read_file("web/index.html")
assert_true(index_source:find('/app.js?v=20260823a', 1, true) ~= nil,
    "EPG UI cache version was not bumped")
assert_true(index_source:find('/styles.css?v=20260823a', 1, true) ~= nil,
    "core UI asset versions must advance together")
assert_true(index_source:find('UI build 20260823a', 1, true) ~= nil,
    "visible UI build stamp is stale")

local server_source = read_file("scripts/server.lua")
assert_true(server_source:find('local is_core_ui_asset = rel == "app.js" or rel == "styles.css"', 1, true) ~= nil,
    "core UI cache classification missing")
assert_true(server_source:find('is_versioned_web_request(raw_path, request) and not is_core_ui_asset', 1, true) ~= nil,
    "core UI assets must not receive immutable caching")

print("web_epg_cache_policy_unit: ok")
astra.exit()
