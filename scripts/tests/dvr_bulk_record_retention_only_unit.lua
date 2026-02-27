log.set({ debug = true })

dofile("scripts/base.lua")
dofile("scripts/config.lua")
dofile("scripts/dvr.lua")

local function assert_true(value, message)
    if not value then
        error(message or "assert failed")
    end
end

local tmp = "/tmp/dvr_bulk_record_retention_only_unit"
os.execute("rm -rf " .. tmp .. " >/dev/null 2>&1 || true")
os.execute("mkdir -p " .. tmp)

config.init({
    data_dir = tmp,
    db_path = tmp .. "/stream.db",
})

local ok1, err1 = dvr.upsert_stream({
    stream_id = "rec_on",
    name = "Record ON",
    source_url = "http://127.0.0.1/play/rec_on",
    record_enabled = true,
    retention_days = 3,
})
assert_true(ok1 ~= nil, err1 or "upsert rec_on failed")

local ok2, err2 = dvr.upsert_stream({
    stream_id = "rec_off",
    name = "Record OFF",
    source_url = "http://127.0.0.1/play/rec_off",
    record_enabled = false,
    retention_days = 3,
})
assert_true(ok2 ~= nil, err2 or "upsert rec_off failed")

local result_retention = dvr.bulk_record({
    stream_ids = { "rec_on", "rec_off" },
    retention_days = 7,
})
assert_true(type(result_retention) == "table", "bulk_record retention-only must return table")
assert_true((tonumber(result_retention.affected) or 0) == 2, "retention-only affected must be 2")

local row_on = dvr.get_stream("rec_on")
local row_off = dvr.get_stream("rec_off")
assert_true(type(row_on) == "table", "rec_on missing")
assert_true(type(row_off) == "table", "rec_off missing")
assert_true(row_on.record_enabled == true, "retention-only must not disable rec_on")
assert_true(row_off.record_enabled == false, "retention-only must not enable rec_off")
assert_true((tonumber(row_on.retention_days) or 0) == 7, "rec_on retention must be 7")
assert_true((tonumber(row_off.retention_days) or 0) == 7, "rec_off retention must be 7")

local result_enable = dvr.bulk_record({
    stream_ids = { "rec_off" },
    record_enabled = true,
})
assert_true(type(result_enable) == "table", "bulk_record enable must return table")
local row_off_enabled = dvr.get_stream("rec_off")
assert_true(type(row_off_enabled) == "table", "rec_off missing after enable")
assert_true(row_off_enabled.record_enabled == true, "record_enabled toggle must still work")

log.info("[unit] dvr_bulk_record_retention_only_unit ok")
astra.exit()
