local function script_path(name)
    return "scripts/" .. name
end

log.set({ debug = true })

dofile(script_path("base.lua"))
dofile(script_path("ai_runtime.lua"))

local function assert_true(cond, msg)
    if not cond then
        error(msg or "assert failed")
    end
end

local function assert_has_all(required, props, label)
    local set = {}
    for _, v in ipairs(required or {}) do
        set[v] = true
    end
    for k, _ in pairs(props or {}) do
        assert_true(set[k] == true, (label or "schema") .. ": required missing '" .. tostring(k) .. "'")
    end
end

-- Stub settings + audit to keep ai_runtime happy.
config = {
    get_setting = function(key)
        if key == "ai_enabled" then return true end
        if key == "ai_model" then return "test-model" end
        if key == "ai_max_tokens" then return 64 end
        if key == "ai_temperature" then return 0 end
        if key == "ai_store" then return false end
        if key == "ai_allow_apply" then return false end
        return nil
    end,
    add_audit_event = function() end,
}

ai_prompt = { build_context = function() return {} end }

ai_openai_client = {
    has_api_key = function() return true end,
    request_json_schema = function(opts, cb)
        local js = opts and opts.json_schema or nil
        assert_true(type(js) == "table", "json_schema missing")
        assert_true(type(js.name) == "string" and js.name ~= "", "schema name missing")
        assert_true(js.strict == true, "schema strict must be true")
        assert_true(type(js.schema) == "table", "schema.schema missing")

        local root = js.schema
        assert_true(type(root.properties) == "table", "root.properties missing")
        assert_has_all(root.required, root.properties, js.name .. ": root")

        local charts = root.properties.charts
        assert_true(type(charts) == "table" and type(charts.items) == "table", "charts schema missing")
        assert_true(type(charts.items.properties) == "table", "charts.items.properties missing")
        assert_has_all(charts.items.required, charts.items.properties, js.name .. ": chart item")

        local series = charts.items.properties.series
        assert_true(type(series) == "table" and type(series.items) == "table", "series schema missing")
        assert_true(type(series.items.properties) == "table", "series.items.properties missing")
        assert_has_all(series.items.required, series.items.properties, js.name .. ": series item")

        if js.name == "astral_ai_plan" then
            local ops = root.properties.ops
            assert_true(type(ops) == "table" and type(ops.items) == "table", "ops schema missing")
            assert_true(type(ops.items.properties) == "table", "ops.items.properties missing")
            assert_has_all(ops.items.required, ops.items.properties, js.name .. ": op item")
            return cb(true, { summary = "ok", warnings = {}, ops = {}, charts = {} }, { attempts = 1, model = "test-model" })
        end

        if js.name == "astral_ai_summary" then
            return cb(true, { summary = "ok", top_issues = {}, suggestions = {}, charts = {} }, { attempts = 1, model = "test-model" })
        end

        return cb(false, "unexpected schema name: " .. tostring(js.name))
    end,
}

ai_runtime.configure()

local job = ai_runtime.plan({ prompt = "test" }, { user = "unit", source = "unit" })
assert_true(job and job.status == "done", "expected plan job done")

local ok, err = ai_runtime.request_summary({ prompt = "test summary" }, function(success)
    assert_true(success == true, "expected summary ok")
end)
assert_true(ok == true and err == nil, "request_summary failed")

print("ai_openai_strict_schema_unit: ok")
astra.exit()

