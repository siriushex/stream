log.set({ debug = true })

dofile("scripts/base.lua")
dofile("scripts/config.lua")
dofile("scripts/dvr.lua")

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

local tmp = "/tmp/dvr_archive_path_unit"
os.execute("rm -rf " .. tmp .. " >/dev/null 2>&1 || true")
os.execute("mkdir -p " .. tmp)

config.init({
    data_dir = tmp,
    db_path = tmp .. "/stream.db",
})

local stream_id = "dvr_path_test"
local base_ts = 1700020000

local settings_default = dvr.settings_for_stream({})
assert_eq(settings_default.archive_path, nil, "default archive path must be nil")
local default_paths = dvr.segment_paths(stream_id, base_ts)
assert_eq(default_paths.dir, tmp .. "/dvr/" .. stream_id, "default dvr dir must use data_dir/dvr")

local settings_absolute = dvr.settings_for_stream({
    dvr = {
        path = tmp .. "/archive_abs/",
    },
})
assert_eq(settings_absolute.archive_path, tmp .. "/archive_abs", "absolute path must be normalized")
local absolute_paths = dvr.segment_paths(stream_id, base_ts, {
    archive_path = settings_absolute.archive_path,
})
assert_eq(absolute_paths.dir, tmp .. "/archive_abs/" .. stream_id, "absolute archive path must be used")

local settings_relative = dvr.settings_for_stream({
    dvr = {
        path = "archive_rel",
    },
})
assert_eq(settings_relative.archive_path, tmp .. "/archive_rel", "relative path must resolve under data_dir")
local relative_paths = dvr.segment_paths(stream_id, base_ts, settings_relative.archive_path)
assert_eq(relative_paths.dir, tmp .. "/archive_rel/" .. stream_id, "relative archive path must be used")

local settings_alias = dvr.settings_for_stream({
    dvr = {
        archive_path = "file://" .. tmp .. "/archive_alias",
    },
})
assert_eq(settings_alias.archive_path, tmp .. "/archive_alias", "archive_path alias must be normalized")

local settings_preserve = dvr.settings_for_stream({
    dvr = {
        enabled = true,
        backup_enabled = true,
        retention_days = 5,
    },
})
assert_true(settings_preserve.archive_enabled == true, "archive enabled must be preserved")
assert_true(settings_preserve.backup_enabled == true, "backup enabled must be preserved")
assert_eq(settings_preserve.retention_days, 5, "retention days must be preserved")

log.info("[unit] dvr_archive_path_unit ok")
astra.exit()
