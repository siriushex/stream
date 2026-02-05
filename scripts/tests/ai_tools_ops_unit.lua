log.set({ debug = true })

dofile("scripts/base.lua")
dofile("scripts/ai_tools.lua")

local function assert_true(cond, msg)
    if not cond then
        error(msg or "assert failed")
    end
end

local function find_stream(payload, id)
    for _, item in ipairs(payload.make_stream or {}) do
        if tostring(item.id) == tostring(id) then
            return item
        end
    end
    return nil
end

local function find_adapter(payload, id)
    for _, item in ipairs(payload.dvb_tune or {}) do
        if tostring(item.id) == tostring(id) then
            return item
        end
    end
    return nil
end

local snapshot = {
    settings = {
        http_play_stream = false,
    },
    make_stream = {
        { id = "s1", name = "Old", enable = false },
    },
    dvb_tune = {
        { id = "a1", enable = false },
    },
}

local next_config, err = ai_tools.apply_ops(snapshot, {
    { op = "set_setting", target = "http_play_stream", value = true },
    { op = "enable_stream", target = "s1" },
    { op = "set_stream_field", target = "s1", field = "name", value = "New" },
    { op = "enable_adapter", target = "a1" },
    { op = "rename_stream", target = "s1", value = "s2" },
})
assert_true(next_config ~= nil, err or "apply_ops failed")
assert_true(next_config.settings.http_play_stream == true, "setting not applied")
local s2 = find_stream(next_config, "s2")
assert_true(s2 ~= nil, "stream rename failed")
assert_true(s2.enable == true, "stream enable failed")
assert_true(s2.name == "New", "stream field set failed")
local a1 = find_adapter(next_config, "a1")
assert_true(a1 ~= nil and a1.enable == true, "adapter enable failed")

local conflict_config = {
    make_stream = {
        { id = "s1" },
        { id = "s2" },
    },
}
local conflict, conflict_err = ai_tools.apply_ops(conflict_config, {
    { op = "rename_stream", target = "s1", value = "s2" },
})
assert_true(conflict == nil, "expected rename conflict to fail")
assert_true(conflict_err and conflict_err:find("already exists"), "expected conflict error")

local bad, bad_err = ai_tools.apply_ops(snapshot, {
    { op = "delete_everything", target = "*" },
})
assert_true(bad == nil, "expected unsupported op to fail")
assert_true(bad_err and bad_err:find("unsupported op"), "expected unsupported op error")

print("ai_tools_ops_unit: ok")
astra.exit()
