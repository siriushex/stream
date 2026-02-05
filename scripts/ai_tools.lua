-- AstralAI tool layer scaffold (backup/validate/apply helpers)

ai_tools = ai_tools or {}

local function is_array(tbl)
    if type(tbl) ~= "table" then
        return false
    end
    local count = 0
    for k, _ in pairs(tbl) do
        if type(k) ~= "number" then
            return false
        end
        if k > count then
            count = k
        end
    end
    return count == #tbl
end

local function deep_equal(a, b)
    if a == b then
        return true
    end
    if type(a) ~= type(b) then
        return false
    end
    if type(a) ~= "table" then
        return a == b
    end
    if is_array(a) and is_array(b) then
        if #a ~= #b then
            return false
        end
        for i = 1, #a do
            if not deep_equal(a[i], b[i]) then
                return false
            end
        end
        return true
    end
    for k, v in pairs(a) do
        if b[k] == nil then
            return false
        end
        if not deep_equal(v, b[k]) then
            return false
        end
    end
    for k, _ in pairs(b) do
        if a[k] == nil then
            return false
        end
    end
    return true
end

local function index_list(list, id_key)
    local out = {}
    local ids = {}
    if type(list) ~= "table" then
        return out, ids
    end
    for idx, item in ipairs(list) do
        if type(item) == "table" then
            local raw = item[id_key] or item.id or item.name or item.adapter_id
            local id = raw ~= nil and tostring(raw) or ("index_" .. tostring(idx))
            out[id] = item
            table.insert(ids, id)
        end
    end
    return out, ids
end

local function diff_list(old_list, new_list, id_key)
    local old_map = index_list(old_list, id_key)
    local new_map = index_list(new_list, id_key)
    local added = {}
    local removed = {}
    local updated = {}
    local unchanged = 0
    for id, item in pairs(new_map) do
        local old_item = old_map[id]
        if old_item == nil then
            table.insert(added, id)
        else
            if deep_equal(old_item, item) then
                unchanged = unchanged + 1
            else
                table.insert(updated, id)
            end
        end
    end
    for id, _ in pairs(old_map) do
        if new_map[id] == nil then
            table.insert(removed, id)
        end
    end
    table.sort(added)
    table.sort(removed)
    table.sort(updated)
    return {
        added = added,
        removed = removed,
        updated = updated,
        unchanged = unchanged,
    }
end

local function diff_settings(old_settings, new_settings)
    local added = {}
    local removed = {}
    local updated = {}
    local old = old_settings or {}
    local new = new_settings or {}
    for k, v in pairs(new) do
        if old[k] == nil then
            table.insert(added, k)
        else
            if not deep_equal(old[k], v) then
                table.insert(updated, k)
            end
        end
    end
    for k, _ in pairs(old) do
        if new[k] == nil then
            table.insert(removed, k)
        end
    end
    table.sort(added)
    table.sort(removed)
    table.sort(updated)
    return {
        added = added,
        removed = removed,
        updated = updated,
        unchanged = math.max(0, (old and (next(old) and 1 or 0) or 0)),
    }
end

function ai_tools.config_snapshot(opts)
    if not config or not config.export_astra then
        return nil, "config export unavailable"
    end
    return config.export_astra(opts or {})
end

function ai_tools.config_backup(opts)
    if not config or not config.export_astra_file or not config.build_snapshot_path then
        return nil, "config backup unavailable"
    end
    local path = config.build_snapshot_path(nil, os.time())
    local ok, err = config.export_astra_file(path, opts or {})
    if not ok then
        return nil, err or "backup failed"
    end
    return path
end

function ai_tools.config_validate(payload)
    if not config or not config.validate_payload then
        return nil, "config validation unavailable"
    end
    return config.validate_payload(payload)
end

function ai_tools.config_diff(old_payload, new_payload)
    if type(old_payload) ~= "table" or type(new_payload) ~= "table" then
        return nil, "invalid payload"
    end
    local diff = {
        summary = {},
        sections = {},
    }

    diff.sections.settings = diff_settings(old_payload.settings, new_payload.settings)
    diff.sections.streams = diff_list(old_payload.make_stream, new_payload.make_stream, "id")
    diff.sections.adapters = diff_list(old_payload.dvb_tune, new_payload.dvb_tune, "id")
    diff.sections.softcam = diff_list(old_payload.softcam, new_payload.softcam, "id")
    diff.sections.splitters = diff_list(old_payload.splitters, new_payload.splitters, "id")
    diff.sections.servers = diff_list(old_payload.servers, new_payload.servers, "id")

    if type(old_payload.users) == "table" or type(new_payload.users) == "table" then
        local users_old = {}
        local users_new = {}
        if type(old_payload.users) == "table" then
            for k, v in pairs(old_payload.users) do
                users_old[tostring(k)] = v
            end
        end
        if type(new_payload.users) == "table" then
            for k, v in pairs(new_payload.users) do
                users_new[tostring(k)] = v
            end
        end
        local added = {}
        local removed = {}
        local updated = {}
        local unchanged = 0
        for id, item in pairs(users_new) do
            local old_item = users_old[id]
            if old_item == nil then
                table.insert(added, id)
            else
                if deep_equal(old_item, item) then
                    unchanged = unchanged + 1
                else
                    table.insert(updated, id)
                end
            end
        end
        for id, _ in pairs(users_old) do
            if users_new[id] == nil then
                table.insert(removed, id)
            end
        end
        table.sort(added)
        table.sort(removed)
        table.sort(updated)
        diff.sections.users = {
            added = added,
            removed = removed,
            updated = updated,
            unchanged = unchanged,
        }
    end

    local summary = {
        added = 0,
        removed = 0,
        updated = 0,
    }
    for _, section in pairs(diff.sections) do
        if type(section) == "table" then
            summary.added = summary.added + (section.added and #section.added or 0)
            summary.removed = summary.removed + (section.removed and #section.removed or 0)
            summary.updated = summary.updated + (section.updated and #section.updated or 0)
        end
    end
    diff.summary = summary
    return diff
end

local function deep_copy(value)
    if type(value) ~= "table" then
        return value
    end
    if json and json.encode then
        local ok, encoded = pcall(json.encode, value)
        if ok and encoded then
            local decoded = json.decode(encoded)
            if type(decoded) == "table" then
                return decoded
            end
        end
    end
    local out = {}
    for k, v in pairs(value) do
        out[k] = deep_copy(v)
    end
    return out
end

local function find_item(list, id)
    if type(list) ~= "table" then
        return nil
    end
    for _, item in ipairs(list) do
        if type(item) == "table" then
            local item_id = item.id or item.name
            if item_id ~= nil and tostring(item_id) == tostring(id) then
                return item
            end
        end
    end
    return nil
end

local function ensure_list(payload, key)
    if type(payload[key]) ~= "table" then
        payload[key] = {}
    end
    return payload[key]
end

local function set_path(target, path, value)
    if type(target) ~= "table" or type(path) ~= "string" or path == "" then
        return false
    end
    local parts = {}
    for part in path:gmatch("[^%.]+") do
        table.insert(parts, part)
    end
    if #parts == 0 then
        return false
    end
    local node = target
    for i = 1, #parts - 1 do
        local key = parts[i]
        if type(node[key]) ~= "table" then
            node[key] = {}
        end
        node = node[key]
    end
    node[parts[#parts]] = value
    return true
end

function ai_tools.apply_ops(snapshot, ops)
    if type(snapshot) ~= "table" then
        return nil, "snapshot required"
    end
    if type(ops) ~= "table" then
        return nil, "ops required"
    end
    local payload = deep_copy(snapshot)
    local errors = {}
    local warnings = {}
    local applied = 0

    local streams = ensure_list(payload, "make_stream")
    local adapters = payload.dvb_tune or payload.adapters
    if type(adapters) ~= "table" then
        adapters = {}
        payload.dvb_tune = adapters
    else
        payload.dvb_tune = adapters
    end

    for _, item in ipairs(ops) do
        local op = tostring(item.op or ""):lower()
        local target = item.target
        local field = item.field
        local value = item.value
        local ok = false

        if op == "set_setting" or op == "set_settings" then
            if type(target) == "string" and target ~= "" then
                payload.settings = payload.settings or {}
                payload.settings[target] = value
                ok = true
            end
        elseif op == "set_stream_field" then
            local stream = find_item(streams, target)
            if stream and type(field) == "string" and field ~= "" then
                ok = set_path(stream, field, value)
            end
        elseif op == "set_adapter_field" then
            local adapter = find_item(adapters, target)
            if adapter and type(field) == "string" and field ~= "" then
                ok = set_path(adapter, field, value)
            end
        elseif op == "enable_stream" or op == "disable_stream" then
            local stream = find_item(streams, target)
            if stream then
                stream.enable = (op == "enable_stream")
                ok = true
            end
        elseif op == "enable_adapter" or op == "disable_adapter" then
            local adapter = find_item(adapters, target)
            if adapter then
                adapter.enable = (op == "enable_adapter")
                ok = true
            end
        elseif op == "rename_stream" then
            local stream = find_item(streams, target)
            if stream and value and tostring(value) ~= "" then
                if find_item(streams, tostring(value)) then
                    table.insert(errors, "stream id already exists: " .. tostring(value))
                else
                    stream.id = tostring(value)
                    ok = true
                end
            end
        elseif op == "rename_adapter" then
            local adapter = find_item(adapters, target)
            if adapter and value and tostring(value) ~= "" then
                if find_item(adapters, tostring(value)) then
                    table.insert(errors, "adapter id already exists: " .. tostring(value))
                else
                    adapter.id = tostring(value)
                    ok = true
                end
            end
        else
            table.insert(errors, "unsupported op: " .. tostring(item.op))
        end

        if ok then
            applied = applied + 1
        elseif op ~= "" then
            table.insert(warnings, "op skipped: " .. tostring(item.op))
        end
    end

    if #errors > 0 then
        return nil, table.concat(errors, "; ")
    end
    return payload, { applied = applied, warnings = warnings }
end

function ai_tools.config_apply(payload, opts)
    if not config or not config.import_astra then
        return nil, "config apply unavailable"
    end
    opts = opts or {}
    local mode = opts.mode or "merge"
    if mode ~= "merge" and mode ~= "replace" then
        return nil, "invalid apply mode"
    end
    local summary, err = config.import_astra(payload, {
        mode = mode,
        transaction = (opts.transaction ~= false),
    })
    if not summary then
        return nil, err or "apply failed"
    end
    return summary
end

function ai_tools.config_verify()
    return true
end

function ai_tools.config_rollback(snapshot_path)
    if not config or not config.restore_snapshot then
        return nil, "config rollback unavailable"
    end
    return config.restore_snapshot(snapshot_path)
end
