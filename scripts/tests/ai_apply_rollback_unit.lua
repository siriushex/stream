log.set({ debug = true })

dofile("scripts/base.lua")
dofile("scripts/config.lua")
dofile("scripts/ai_openai_client.lua")
dofile("scripts/ai_tools.lua")
dofile("scripts/ai_prompt.lua")
dofile("scripts/ai_runtime.lua")

config.init({ data_dir = "/tmp/ai_apply_rollback_data", db_path = "/tmp/ai_apply_rollback_data/ai_apply_rollback.db" })

local function assert_true(cond, msg)
    if not cond then
        error(msg or "assert failed")
    end
end

-- baseline
config.set_setting("http_play_stream", false)

local backup_path, backup_err = ai_tools.config_backup()
assert_true(backup_path ~= nil, backup_err or "backup failed")

config.set_setting("ai_enabled", true)
config.set_setting("ai_allow_apply", true)
ai_runtime.configure()

local proposed = {
    settings = {
        http_play_stream = true,
    },
}

local plan = ai_runtime.plan({ proposed_config = proposed }, { user = "test" })
assert_true(plan and plan.status == "done", "plan failed")
assert_true(plan.result and plan.result.diff, "plan diff missing")

local job, err = ai_runtime.apply({ proposed_config = proposed }, { user = "test" })
assert_true(job and job.status == "done", err or "apply failed")

local value = config.get_setting("http_play_stream")
assert_true(value ~= nil and tostring(value) ~= "false", "setting not applied")

local ok_restore, restore_err = config.restore_snapshot(backup_path)
assert_true(ok_restore ~= nil, restore_err or "restore failed")

local reverted = config.get_setting("http_play_stream")
assert_true(reverted == nil or reverted == false or tostring(reverted) == "false", "rollback did not restore setting")

print("ai_apply_rollback_unit: ok")
astra.exit()
