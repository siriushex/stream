log.set({ debug = true })

dofile("scripts/base.lua")
dofile("scripts/ai_observability.lua")

local function assert_true(cond, msg)
    if not cond then
        error(msg or "assert failed")
    end
end

local enabled = true
local start_calls = 0
local stop_calls = 0
local closed_timers = 0

observability_worker = {
    start = function(_)
        start_calls = start_calls + 1
        return true
    end,
    stop = function()
        stop_calls = stop_calls + 1
        return true
    end,
    enqueue_batch = function(rows)
        return { accepted = #rows, dropped = 0 }
    end,
    status = function()
        return {
            running = enabled,
            thread_started = enabled,
            queue_depth = 0,
            queue_max = 100,
            rows_written = 0,
            rows_dropped = 0,
            db_busy_count = 0,
            last_flush_ms = 0,
            db_path = "/tmp/observability-unit.db",
            affinity = "auto:last-2",
            last_error = "",
        }
    end,
}

timer = function(_)
    return {
        close = function()
            closed_timers = closed_timers + 1
        end,
    }
end

config = {
    get_setting = function(key)
        if key == "observability_enabled" then return enabled end
        if key == "ai_logs_retention_days" then return 7 end
        if key == "ai_metrics_retention_days" then return 30 end
        if key == "ai_metrics_on_demand" then return false end
        if key == "observability_affinity_enabled" then return true end
        if key == "observability_cpu_policy" then return "auto" end
        if key == "observability_cpu_auto_cores" then return 2 end
        if key == "observability_writer_batch_max" then return 200 end
        if key == "observability_writer_flush_ms" then return 20 end
        if key == "observability_writer_max_queue" then return 1000 end
        return nil
    end,
    get_observability_storage_info = function()
        return { db_path = "/tmp/observability-unit.db", isolated = true }
    end,
}

ai_observability.configure()
assert_true(start_calls == 1, "worker start should be called when enabled")
assert_true(ai_observability.state.worker_backend == "thread", "worker backend should be thread")

enabled = false
ai_observability.configure()
assert_true(stop_calls >= 1, "worker stop should be called when disabled")
assert_true(ai_observability.state.worker_backend == "inprocess", "worker backend should fallback when disabled")
assert_true(closed_timers >= 1, "timers should be closed on reconfigure")

print("ai_observability_worker_lifecycle_unit: ok")
astra.exit()
