log.set({ debug = true })

dofile("scripts/base.lua")

local function assert_equal(actual, expected, label)
    if actual ~= expected then
        error(label .. ": expected=" .. tostring(expected) .. " actual=" .. tostring(actual))
    end
end

local global_value = false
config = {
    get_setting = function(key)
        if key == "softcam_key_guard" then
            return global_value
        end
        return nil
    end,
}

assert_equal(stream_softcam_key_guard_resolve({}, {}), false, "global false")
global_value = true
assert_equal(stream_softcam_key_guard_resolve({}, {}), true, "global true")
assert_equal(stream_softcam_key_guard_resolve({ key_guard = "0" }, {}), false, "CAM override")
assert_equal(stream_softcam_key_guard_resolve({ key_guard = "0" }, { key_guard = "1" }), true, "input override")
assert_equal(stream_softcam_key_guard_resolve({ key_guard = "1" }, { key_guard = "invalid" }), false,
    "invalid explicit value")

print("softcam_key_guard_scope_unit: ok")
astra.exit()
