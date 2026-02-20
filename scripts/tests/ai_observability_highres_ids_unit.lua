log.set({ debug = true })

dofile("scripts/base.lua")
dofile("scripts/ai_observability.lua")

local function assert_true(v, msg)
    if not v then
        error(msg or "assert")
    end
end

local callbacks = {}
timer = function(opts)
    local t = {
        interval = opts and opts.interval,
        callback = opts and opts.callback,
        closed = false,
        close = function(self)
            self.closed = true
        end,
    }
    callbacks[#callbacks + 1] = t
    return t
end

local calls = {
    list_status = 0,
    list_status_lite = 0,
    list_status_ids = 0,
    list_status_lite_ids = 0,
    writes = 0,
}

config = {
    get_setting = function(key)
        if key == "observability_enabled" then return true end
        if key == "ai_logs_retention_days" then return 7 end
        if key == "ai_metrics_retention_days" then return 30 end
        if key == "ai_metrics_on_demand" then return false end
        if key == "ai_rollup_interval_sec" then return 60 end
        if key == "observability_stream_highres_enabled" then return true end
        if key == "observability_writer_batch_max" then return 200 end
        if key == "observability_writer_flush_ms" then return 10 end
        if key == "observability_writer_max_queue" then return 2000 end
        if key == "observability_affinity_enabled" then return false end
        if key == "observability_cpu_policy" then return "none" end
        return nil
    end,
    get_observability_storage_info = function()
        return { db_path = "/tmp/obs-highres-unit.db", isolated = false }
    end,
    upsert_ai_metrics_batch = function(rows)
        calls.writes = calls.writes + (type(rows) == "table" and #rows or 0)
        return true
    end,
}

runtime = {
    list_status = function()
        calls.list_status = calls.list_status + 1
        return {}
    end,
    list_status_lite = function()
        calls.list_status_lite = calls.list_status_lite + 1
        return {}
    end,
    list_status_ids = function(ids)
        calls.list_status_ids = calls.list_status_ids + 1
        return {}
    end,
    list_status_lite_ids = function(ids)
        calls.list_status_lite_ids = calls.list_status_lite_ids + 1
        local out = {}
        for _, id in ipairs(ids or {}) do
            out[id] = {
                id = id,
                on_air = true,
                bitrate_kbps = 1234,
                cc_errors = 0,
                pes_errors = 0,
                input_switches = 0,
            }
        end
        return out
    end,
}

system_metrics = {
    snapshot = function()
        return { cpu = { usage = 0.2 } }
    end,
}

ai_observability.highres_pool = {
    s1 = { severity = 2, until_ts = os.time() + 120, last_incident_ts = os.time() },
}

ai_observability.configure()

local highres_cb = nil
for _, t in ipairs(callbacks) do
    if t.interval == 10 and type(t.callback) == "function" then
        highres_cb = t.callback
        break
    end
end
assert_true(type(highres_cb) == "function", "expected highres timer callback")

local base_list_status_calls = calls.list_status
local base_list_status_lite_calls = calls.list_status_lite
local base_lite_ids_calls = calls.list_status_lite_ids

highres_cb()

assert_true(calls.list_status == base_list_status_calls, "highres tick must not call full list_status")
assert_true(calls.list_status_lite == base_list_status_lite_calls, "highres tick should use ids API, not full lite list")
assert_true(calls.list_status_lite_ids > base_lite_ids_calls, "highres tick must call list_status_lite_ids")

print("ai_observability_highres_ids_unit: ok")
astra.exit()
