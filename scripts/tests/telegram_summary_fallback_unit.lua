-- Telegram summary fallback unit test (works when observability rollup is disabled)

dofile("scripts/base.lua")
dofile("scripts/telegram.lua")

-- Minimal stubs: no ai_metrics tables, only runtime snapshot + alerts counter.
runtime = {
    list_status = function()
        local now = os.time()
        return {
            a = { on_air = true, bitrate = 1200, last_switch = now - 10 },
            b = { on_air = false, bitrate = 0 },
        }
    end,
}

config = {
    count_alerts = function()
        return 3
    end,
    set_setting = function()
        -- no-op
    end,
    list_alerts = function()
        return {
            { ts = os.time(), level = "ERROR", stream_id = "a", message = "test error" },
        }
    end,
}

telegram.config.available = true
telegram.curl_available = true
telegram.queue = {}
telegram.dedupe = {}
telegram.throttle = {}

local ok, err = telegram.send_summary_now()
if not ok then
    error("expected send_summary_now to succeed, got: " .. tostring(err))
end
if #telegram.queue == 0 then
    error("expected summary message to be queued")
end
local text = telegram.queue[1].text or ""
if not text:find("Summary") then
    error("expected summary text, got: " .. tostring(text))
end

print("telegram_summary_fallback_unit: ok")
astra.exit()

