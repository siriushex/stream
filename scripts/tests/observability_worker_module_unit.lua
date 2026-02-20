log.set({ debug = true })

dofile("scripts/base.lua")

local function assert_true(v, msg)
    if not v then
        error(msg or "assert")
    end
end

local worker = rawget(_G, "observability_worker")
if type(worker) ~= "table" or type(worker.start) ~= "function" then
    print("observability_worker_module_unit: skipped (module unavailable)")
    astra.exit()
    return
end

local db_path = "/tmp/observability-worker-unit-" .. tostring(os.time()) .. ".db"
local ok, err = worker.start({
    db_path = db_path,
    batch_max = 16,
    flush_ms = 5,
    queue_max = 128,
    affinity_enabled = false,
    cpu_policy = "none",
})
assert_true(ok == true, "worker start failed: " .. tostring(err))

local enqueue = worker.enqueue_batch({
    {
        ts_bucket = os.time(),
        scope = "stream",
        scope_id = "unit",
        metric_key = "stream.bitrate_kbps.avg",
        resolution_sec = 60,
        value = 111.0,
        mode = "replace",
        tags_json = "{}",
    },
    {
        ts_bucket = os.time(),
        scope = "stream",
        scope_id = "unit",
        metric_key = "stream.cc_errors.delta",
        resolution_sec = 10,
        value = 1.0,
        mode = "sum",
        tags_json = "{}",
    },
})
assert_true(type(enqueue) == "table", "enqueue_batch should return table")
assert_true((enqueue.accepted or 0) >= 1, "expected accepted rows")

local flushed = false
local started = os.clock()
while (os.clock() - started) < 1.0 do
    local st = worker.status()
    if type(st) == "table" and (tonumber(st.rows_written) or 0) >= 1 then
        flushed = true
        break
    end
end
assert_true(flushed, "worker did not flush rows")
assert_true(worker.stop() == true, "worker stop failed")

print("observability_worker_module_unit: ok")
astra.exit()
