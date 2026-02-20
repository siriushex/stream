log.set({ debug = true })

dofile("scripts/base.lua")
dofile("scripts/config.lua")
dofile("scripts/api.lua")

local function assert_true(value, message)
    if not value then
        error(message or "assert_true failed")
    end
end

local function assert_equal(actual, expected, message)
    if actual ~= expected then
        error((message or "assert_equal failed") .. ": expected=" .. tostring(expected) .. " actual=" .. tostring(actual))
    end
end

local row_c = {
    id = "c0",
    config = {
        type = "C",
    },
}
local plan_c, err_c = dvb_plan_from_custom(row_c, {
    custom = {
        frequency_from = 330000,
        frequency_to = 346000,
    },
})
assert_true(plan_c ~= nil, "expected custom C plan")
assert_true(err_c == nil, "unexpected C plan error")
assert_equal(#plan_c, 3, "C plan should use default 8MHz step")
assert_equal(tonumber(plan_c[1].frequency), 330000, "C first frequency")
assert_equal(tonumber(plan_c[2].frequency), 338000, "C second frequency")
assert_equal(tonumber(plan_c[3].frequency), 346000, "C third frequency")

local row_s2 = {
    id = "s20",
    config = {
        type = "S2",
        symbolrate = 27500,
    },
}
local plan_s2, err_s2 = dvb_plan_from_custom(row_s2, {
    custom = {
        frequency_from = 12322000,
        frequency_to = 12323000,
        symbolrates = { 27500 },
    },
})
assert_true(plan_s2 ~= nil, "expected custom S2 plan")
assert_true(err_s2 == nil, "unexpected S2 plan error")
assert_equal(#plan_s2, 4, "S2 plan should include H/V for each step")
assert_equal(tostring(plan_s2[1].tp), "12322000:H:27500", "S2 first tp")
assert_equal(tostring(plan_s2[2].tp), "12322000:V:27500", "S2 second tp")

log.info("[unit] dvb_full_scan_plan_custom_unit ok")
astra.exit()
