log.set({ debug = true })

dofile("scripts/base.lua")
dofile("scripts/config.lua")
dofile("scripts/api.lua")

runtime = runtime or {}
runtime.refresh = runtime.refresh or function()
    return true
end
runtime.refresh_adapters = runtime.refresh_adapters or function() end
runtime.apply_stream_row = runtime.apply_stream_row or function()
    return true
end
runtime.streams = runtime.streams or {}

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

local tmp = "/tmp/stream_dvr_backup_autoinput_unit"
os.execute("rm -rf " .. tmp .. " >/dev/null 2>&1 || true")
os.execute("mkdir -p " .. tmp)

config.init({
    data_dir = tmp,
    db_path = tmp .. "/stream.db",
})
config.set_setting("http_auth_enabled", false)
config.set_setting("http_port", 9060)
config.set_setting("http_play_port", 0)

local sent = nil
local server = {
    send = function(_, _, payload)
        sent = payload
    end,
}
local client = {}

local function make_request(path, body)
    return {
        method = "POST",
        path = path,
        addr = "127.0.0.1",
        headers = { ["content-type"] = "application/json" },
        query = {},
        content = json.encode(body),
    }
end

local function post_stream(body)
    sent = nil
    api.handle_request(server, client, make_request("/api/v1/streams", body))
    assert_true(sent ~= nil, "expected response")
    assert_eq(tonumber(sent.code), 200, "expected 200 from stream upsert")
end

local stream_id = "dvr_auto_input"
local expected_backup_input = "http://127.0.0.1:9060/dvr/internal/play/" .. stream_id .. "?internal=1"

post_stream({
    id = stream_id,
    enabled = true,
    config = {
        id = stream_id,
        name = "DVR auto input",
        type = "spts",
        input = {
            "http://origin.example/live",
        },
        backup_type = "disabled",
        dvr = {
            enabled = true,
            backup_enabled = true,
            retention_days = 3,
        },
    },
})

local row = config.get_stream(stream_id)
assert_true(type(row) == "table", "stream row must exist")
local cfg = row.config or {}
assert_eq(tostring(cfg.backup_type or ""), "passive", "backup_type must auto-switch to passive for DVR backup")
assert_true(type(cfg.input) == "table", "input must be a table")

local count = 0
for _, value in ipairs(cfg.input) do
    if tostring(value) == expected_backup_input then
        count = count + 1
    end
end
assert_eq(count, 1, "DVR backup input must be auto-added exactly once")

post_stream({
    id = stream_id,
    enabled = true,
    config = cfg,
})

local row2 = config.get_stream(stream_id)
local cfg2 = row2 and row2.config or {}
local count2 = 0
for _, value in ipairs(cfg2.input or {}) do
    if tostring(value) == expected_backup_input then
        count2 = count2 + 1
    end
end
assert_eq(count2, 1, "DVR backup input must not be duplicated on re-save")

cfg2.backup_type = "active"
post_stream({
    id = stream_id,
    enabled = true,
    config = cfg2,
})

local row3 = config.get_stream(stream_id)
local cfg3 = row3 and row3.config or {}
assert_eq(tostring(cfg3.backup_type or ""), "passive", "DVR backup must force passive mode even when active requested")
local count3 = 0
for _, value in ipairs(cfg3.input or {}) do
    if tostring(value) == expected_backup_input then
        count3 = count3 + 1
    end
end
assert_eq(count3, 1, "DVR backup input must remain unique after forced passive normalization")

cfg3.input = {
    "http://origin.example/live",
    "http://127.0.0.1:9060/dvr/play/" .. stream_id,
    "http://127.0.0.1:9060/dvr/play/" .. stream_id .. "?internal=1",
    expected_backup_input,
}
post_stream({
    id = stream_id,
    enabled = true,
    config = cfg3,
})

local row4 = config.get_stream(stream_id)
local cfg4 = row4 and row4.config or {}
local count4 = 0
for _, value in ipairs(cfg4.input or {}) do
    if tostring(value) == expected_backup_input then
        count4 = count4 + 1
    end
    assert_true(tostring(value) ~= "http://127.0.0.1:9060/dvr/play/" .. stream_id,
        "legacy /dvr/play input without internal=1 must be removed")
    assert_true(tostring(value) ~= "http://127.0.0.1:9060/dvr/play/" .. stream_id .. "?internal=1",
        "legacy /dvr/play input with internal=1 must be removed")
end
assert_eq(count4, 1, "DVR backup input must be normalized to single internal URL")

log.info("[unit] stream_dvr_backup_autoinput_unit ok")
astra.exit()
