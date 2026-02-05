log.set({ debug = true })

dofile("scripts/base.lua")
dofile("scripts/config.lua")
dofile("scripts/ai_openai_client.lua")
dofile("scripts/ai_tools.lua")
dofile("scripts/ai_prompt.lua")
dofile("scripts/ai_context.lua")
dofile("scripts/ai_runtime.lua")

config.init({ data_dir = "/tmp/ai_attach_data", db_path = "/tmp/ai_attach_data/ai_attach.db" })

local function assert_true(cond, msg)
    if not cond then
        error(msg or "assert failed")
    end
end

local calls = {}
ai_openai_client.request_json_schema = function(opts, cb)
    calls[#calls + 1] = opts
    local fake = {
        summary = "ok",
        warnings = {},
        ops = {},
    }
    cb(true, fake, { attempts = 1 })
end
ai_openai_client.has_api_key = function() return true end

config.set_setting("ai_enabled", true)
config.set_setting("ai_model", "test")
ai_runtime.configure()

local tiny_png = "data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8/5+hHgAHggJ/PV4W8gAAAABJRU5ErkJggg=="
local payload = {
    prompt = "Test attachments",
    attachments = {
        { data_url = tiny_png },
    },
}

local job = ai_runtime.plan(payload, { user = "test" })
assert_true(job and job.status == "done", "plan job failed")
assert_true(#calls == 1, "expected one openai request")
assert_true(type(calls[1].input) == "table", "expected multimodal input")

config.set_setting("ai_attachments_max_bytes", 128000)
ai_runtime.configure()
local big_payload = {
    prompt = "Test big attachment",
    attachments = {
        { data_url = "data:image/png;base64," .. string.rep("a", 200000) },
    },
}
local job2 = ai_runtime.plan(big_payload, { user = "test" })
assert_true(job2 and job2.status == "error", "expected attachment error")

print("ai_runtime_attachments_unit: ok")
astra.exit()
