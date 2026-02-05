-- AstralAI Telegram commands unit tests

math.randomseed(12345)

dofile("scripts/base.lua")

dofile("scripts/ai_telegram.lua")

local sent = {}

telegram = {
    config = {},
    send_text = function(message, opts)
        table.insert(sent, { message = message, opts = opts })
        return true
    end,
}

ai_runtime = {
    config = { allowed_chat_ids = { "1" }, allow_apply = true },
    jobs = {
        ["42"] = {
            id = "42",
            status = "done",
            result = { plan = { summary = "ok" } },
        },
    },
    plan = function(payload, ctx)
        return { id = "42" }
    end,
    apply = function(payload, ctx)
        return { result = { revision_id = 7 } }
    end,
    is_ready = function()
        return false
    end,
}

config = {
    get_setting = function(key)
        if key == "ai_metrics_on_demand" then
            return true
        end
        return nil
    end,
}

local function assert_true(value, label)
    if not value then
        error(label or "assert failed")
    end
end

local function last_message()
    return sent[#sent] and sent[#sent].message or ""
end

-- reset state
ai_telegram.state = { dedupe = {}, throttle = {}, pending = {}, seeded = false }

-- /ai suggest
ai_telegram.handle({ message = { text = "/ai suggest", chat = { id = "1" } } })
assert_true(last_message():find("Plan queued"), "suggest should queue plan")

-- /ai apply -> confirm token
ai_telegram.handle({ message = { text = "/ai apply plan_id=42", chat = { id = "1" } } })
local confirm_msg = last_message()
local token = confirm_msg:match("confirm%s+(%d+)") or confirm_msg:match("/ai%s+confirm%s+(%d+)")
assert_true(token ~= nil, "confirm token should be issued")

-- /ai confirm
ai_telegram.handle({ message = { text = "/ai confirm " .. tostring(token), chat = { id = "1" } } })
assert_true(last_message():find("Apply OK"), "confirm should apply")

print("ai_telegram_commands_unit: ok")
astra.exit()
