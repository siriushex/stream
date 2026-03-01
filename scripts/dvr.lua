-- DVR archive and backup state helpers.
-- Runtime playback orchestration is implemented in stream.lua,
-- this module provides storage/state/cycle primitives.

dvr = dvr or {}

local dvr_json = rawget(_G, "json")
if type(dvr_json) ~= "table" then
    local ok_json, mod_json = pcall(require, "json")
    if ok_json and type(mod_json) == "table" then
        dvr_json = mod_json
    end
end

local function dvr_json_encode(value)
    if dvr_json and type(dvr_json.encode) == "function" then
        return dvr_json.encode(value)
    end
    return nil, "json.encode unavailable"
end

local function dvr_json_decode(value)
    if dvr_json and type(dvr_json.decode) == "function" then
        return dvr_json.decode(value)
    end
    return nil, "json.decode unavailable"
end

local function dvr_sql_escape(value)
    return tostring(value or ""):gsub("'", "''")
end

local function dvr_db()
    if not (config and config.db) then
        return nil
    end
    return config.db
end

local function dvr_db_exec(sql)
    local db = dvr_db()
    if not db then
        return nil, "database unavailable"
    end
    local ok, err = db:exec(sql)
    if ok ~= true then
        return nil, tostring(err or "exec failed")
    end
    return true
end

local function dvr_db_query(sql)
    local db = dvr_db()
    if not db then
        return nil, "database unavailable"
    end
    local rows, err = db:query(sql)
    if not rows then
        return nil, tostring(err or "query failed")
    end
    return rows
end

local function dvr_bool(value, fallback)
    if value == nil then
        return fallback
    end
    if value == true or value == 1 or value == "1" or value == "true" or value == "yes" or value == "on" then
        return true
    end
    if value == false or value == 0 or value == "0" or value == "false" or value == "no" or value == "off" then
        return false
    end
    return fallback
end

local function dvr_number(value, fallback, min_value)
    local n = tonumber(value)
    if n == nil then
        return fallback
    end
    if min_value ~= nil and n < min_value then
        n = min_value
    end
    return n
end

local function dvr_trim(value)
    return tostring(value or ""):gsub("^%s+", ""):gsub("%s+$", "")
end

local function dvr_parse_query_number(value)
    local n = tonumber(value)
    if n ~= nil then
        return n
    end
    if type(value) == "string" then
        local token = value:match("^%s*([%+%-]?%d+%.?%d*)")
        if token and token ~= "" then
            return tonumber(token)
        end
    end
    return nil
end

local function dvr_backup_start_mode(value, fallback)
    local mode = dvr_trim(value):lower()
    if mode == "time_offset" or mode == "offset" or mode == "time" then
        return "time_offset"
    end
    if mode == "sequential" or mode == "default" then
        return "sequential"
    end
    return fallback or "sequential"
end

local function dvr_setting(key, fallback)
    if not (config and config.get_setting) then
        return fallback
    end
    local value = config.get_setting(key)
    if value == nil then
        return fallback
    end
    return value
end

local function dvr_setting_alias(keys, fallback)
    for _, key in ipairs(keys or {}) do
        local value = dvr_setting(key, nil)
        if value ~= nil then
            return value
        end
    end
    return fallback
end

local function dvr_sanitize_id(value)
    local s = tostring(value or "")
    if s == "" then
        return "stream"
    end
    s = s:gsub("[^%w%-%_%.]", "_")
    if s == "" then
        s = "stream"
    end
    return s
end

local function dvr_join_path(base, suffix)
    if not base or base == "" then
        return suffix or ""
    end
    if not suffix or suffix == "" then
        return base
    end
    if base:sub(-1) == "/" then
        base = base:sub(1, -2)
    end
    if suffix:sub(1, 1) == "/" then
        suffix = suffix:sub(2)
    end
    return base .. "/" .. suffix
end

local function dvr_ensure_dir(path)
    if not path or path == "" then
        return
    end
    if utils and type(utils.stat) == "function" then
        local st = utils.stat(path)
        if st and st.type == "directory" then
            return
        end
    end
    os.execute("mkdir -p '" .. tostring(path):gsub("'", "'\\''") .. "'")
end

local function dvr_normalize_archive_path(path)
    local value = dvr_trim(path)
    if value == "" then
        return nil
    end
    value = value:gsub("^file://", "")
    if value == "" then
        return nil
    end
    if value:sub(1, 1) ~= "/" then
        local data_dir = (config and config.data_dir) or "./data"
        value = dvr_join_path(data_dir, value)
    end
    value = value:gsub("/+$", "")
    if value == "" then
        value = "/"
    end
    return value
end

local dvr_storage_cache = {
    updated_ts = 0,
    recommended_path = nil,
    candidates = nil,
}

local function dvr_unescape_mount_path(path)
    local value = tostring(path or "")
    if value == "" then
        return value
    end
    value = value:gsub("\\040", " ")
    value = value:gsub("\\011", "\t")
    value = value:gsub("\\012", "\n")
    value = value:gsub("\\134", "\\")
    return value
end

local function dvr_is_system_fs(fs_type)
    local value = tostring(fs_type or ""):lower()
    if value == "" then
        return false
    end
    return value == "proc"
        or value == "sysfs"
        or value == "devtmpfs"
        or value == "devpts"
        or value == "tmpfs"
        or value == "cgroup"
        or value == "cgroup2"
        or value == "pstore"
        or value == "securityfs"
        or value == "debugfs"
        or value == "tracefs"
        or value == "squashfs"
        or value == "overlay"
        or value == "autofs"
        or value == "mqueue"
        or value == "hugetlbfs"
        or value == "fusectl"
        or value == "rpc_pipefs"
        or value == "binfmt_misc"
end

local function dvr_is_mount_prefix_candidate(path)
    local value = tostring(path or "")
    if value == "" or value == "/" then
        return false
    end
    return value:find("^/media/") ~= nil
        or value:find("^/mnt/") ~= nil
        or value:find("^/srv/") ~= nil
        or value == "/media"
        or value == "/mnt"
        or value == "/srv"
end

local function dvr_statvfs(path)
    if not (utils and type(utils.statvfs) == "function") then
        return nil
    end
    local ok, st = pcall(utils.statvfs, path)
    if not ok or type(st) ~= "table" or st.error then
        return nil
    end
    local total = tonumber(st.total_bytes) or 0
    local avail = tonumber(st.avail_bytes) or tonumber(st.free_bytes) or 0
    local used_percent = tonumber(st.used_percent)
    return {
        total_bytes = total >= 0 and total or 0,
        avail_bytes = avail >= 0 and avail or 0,
        used_percent = used_percent,
    }
end

local function dvr_collect_mount_points()
    local mounts_path = "/proc/mounts"
    local fp = io.open(mounts_path, "r")
    if not fp then
        mounts_path = "/etc/mtab"
        fp = io.open(mounts_path, "r")
    end
    if not fp then
        return {}
    end
    local items = {}
    local seen = {}
    while true do
        local line = fp:read("*l")
        if not line then
            break
        end
        local _device, mount_point_raw, fs_type = line:match("^(%S+)%s+(%S+)%s+(%S+)")
        if mount_point_raw and fs_type and not dvr_is_system_fs(fs_type) then
            local mount_point = dvr_unescape_mount_path(mount_point_raw)
            if mount_point ~= "" then
                mount_point = mount_point:gsub("/+$", "")
                if mount_point == "" then
                    mount_point = "/"
                end
                if not seen[mount_point] then
                    seen[mount_point] = true
                    items[#items + 1] = {
                        mount_point = mount_point,
                        fs_type = fs_type,
                        from_proc = mounts_path == "/proc/mounts",
                    }
                end
            end
        end
    end
    fp:close()
    return items
end

local function dvr_storage_candidates_compute()
    local now = os.time()
    local candidates = {}
    local seen_paths = {}
    local recommended_path = nil

    local function push_candidate(path, source, mount_point, fs_type, stat)
        local normalized = dvr_normalize_archive_path(path)
        if not normalized or seen_paths[normalized] then
            return
        end
        seen_paths[normalized] = true
        local avail_bytes = stat and tonumber(stat.avail_bytes) or nil
        local total_bytes = stat and tonumber(stat.total_bytes) or nil
        local used_percent = stat and tonumber(stat.used_percent) or nil
        local is_system = (source == "fallback_root")
        candidates[#candidates + 1] = {
            path = normalized,
            source = source,
            mount_point = mount_point,
            fs_type = fs_type,
            avail_bytes = avail_bytes,
            total_bytes = total_bytes,
            used_percent = used_percent,
            is_system = is_system,
        }
        if not recommended_path then
            recommended_path = normalized
        end
    end

    local forced_root = dvr_normalize_archive_path(
        dvr_setting_alias({ "dvr_archive_path", "dvr.archive_path" }, nil)
    )
    if forced_root then
        push_candidate(forced_root, "setting", forced_root, nil, dvr_statvfs(forced_root))
    end

    local mounts = dvr_collect_mount_points()
    for _, row in ipairs(mounts) do
        local mount_point = tostring(row.mount_point or "")
        if dvr_is_mount_prefix_candidate(mount_point) then
            local st = utils and utils.stat and utils.stat(mount_point) or nil
            if st and not st.error and st.type == "directory" then
                local root_path = dvr_join_path(mount_point, "stream-dvr")
                push_candidate(root_path, "mount", mount_point, row.fs_type, dvr_statvfs(mount_point))
            end
        end
    end

    if #candidates > 1 then
        table.sort(candidates, function(a, b)
            if (a.source == "setting") ~= (b.source == "setting") then
                return a.source == "setting"
            end
            if (a.is_system == true) ~= (b.is_system == true) then
                return a.is_system ~= true
            end
            local a_avail = tonumber(a.avail_bytes) or -1
            local b_avail = tonumber(b.avail_bytes) or -1
            if a_avail ~= b_avail then
                return a_avail > b_avail
            end
            return tostring(a.path or "") < tostring(b.path or "")
        end)
        recommended_path = candidates[1] and candidates[1].path or recommended_path
    end

    if not recommended_path then
        local data_dir = (config and config.data_dir) or "./data"
        local fallback_root = dvr_join_path(data_dir, "dvr")
        push_candidate(fallback_root, "fallback_root", "/", nil, dvr_statvfs(data_dir))
    end

    dvr_storage_cache.updated_ts = now
    dvr_storage_cache.recommended_path = recommended_path
    dvr_storage_cache.candidates = candidates
    return {
        recommended_path = recommended_path,
        candidates = candidates,
    }
end

function dvr.storage_candidates(opts)
    local refresh = type(opts) == "table" and opts.refresh == true
    local ttl = 30
    if not refresh and dvr_storage_cache.candidates
        and (os.time() - (tonumber(dvr_storage_cache.updated_ts) or 0)) < ttl
    then
        return {
            recommended_path = dvr_storage_cache.recommended_path,
            candidates = dvr_storage_cache.candidates,
        }
    end
    return dvr_storage_candidates_compute()
end

function dvr.segment_start(ts, segment_sec)
    local seg = dvr_number(segment_sec, 3600, 1)
    local now = math.floor(dvr_number(ts, os.time(), 0))
    return now - (now % seg)
end

function dvr.segment_duration(segment)
    if type(segment) ~= "table" then
        return 0
    end
    local from = tonumber(segment.seg_start_ts) or 0
    local to = tonumber(segment.seg_end_ts) or from
    local duration = math.floor(to - from)
    if duration < 0 then
        duration = 0
    end
    return duration
end

function dvr.should_use_segment_lock(segment, lock_path)
    local lock = dvr_trim(lock_path)
    if lock == "" then
        return false
    end
    if type(segment) ~= "table" then
        return false
    end
    if segment.is_complete == true then
        return false
    end
    if tonumber(segment.is_complete) == 1 then
        return false
    end
    return true
end

function dvr.should_force_skip_stalled_segment(segment, elapsed_sec, played_sec)
    if type(segment) ~= "table" then
        return false
    end
    local is_complete = (segment.is_complete == true) or (tonumber(segment.is_complete) == 1)
    if not is_complete then
        return false
    end
    local elapsed = math.max(0, math.floor(tonumber(elapsed_sec) or 0))
    local played = math.max(0, math.floor(tonumber(played_sec) or 0))
    -- Complete DVR segment with almost no playback progress for a long time
    -- is treated as stalled/corrupted and should be skipped to prevent loops.
    if elapsed >= 20 and played <= 1 then
        return true
    end
    return false
end

function dvr.segment_paths(stream_id, seg_start_ts, opts)
    local root = nil
    if type(opts) == "table" then
        root = dvr_normalize_archive_path(opts.archive_path or opts.path or opts.root)
    elseif type(opts) == "string" then
        root = dvr_normalize_archive_path(opts)
    end
    if not root then
        local data_dir = (config and config.data_dir) or "./data"
        root = dvr_join_path(data_dir, "dvr")
    end
    local sid = dvr_sanitize_id(stream_id)
    local dir = dvr_join_path(root, sid)
    dvr_ensure_dir(root)
    dvr_ensure_dir(dir)
    local base = tostring(math.floor(tonumber(seg_start_ts) or 0))
    return {
        dir = dir,
        part_path = dvr_join_path(dir, base .. ".part.ts"),
        final_path = dvr_join_path(dir, base .. ".ts"),
        lock_path = dvr_join_path(dir, base .. ".lock"),
    }
end

function dvr.settings_for_stream(stream_cfg)
    local cfg = (type(stream_cfg) == "table" and type(stream_cfg.dvr) == "table") and stream_cfg.dvr or {}
    local mode = dvr_trim(cfg.mode):lower()
    local archive_enabled = dvr_bool(cfg.enabled, nil)
    if archive_enabled == nil then
        archive_enabled = dvr_bool(dvr_setting_alias({ "dvr_enabled", "dvr.enabled" }, false), false)
    end

    local backup_enabled = dvr_bool(cfg.backup_enabled, nil)
    if backup_enabled == nil then
        backup_enabled = dvr_bool(dvr_setting_alias({ "dvr_backup_enabled", "dvr.backup_enabled" }, false), false)
    end

    local retention_days = dvr_number(cfg.retention_days, nil, 1)
    if retention_days == nil then
        retention_days = dvr_number(dvr_setting_alias({ "dvr_retention_days", "dvr.retention_days" }, 3), 3, 1)
    end

    local trigger_no_data_sec = dvr_number(cfg.backup_trigger_no_data_sec, nil, 1)
    if trigger_no_data_sec == nil then
        trigger_no_data_sec = dvr_number(
            dvr_setting_alias({ "dvr_backup_trigger_no_data_sec", "dvr.backup_trigger_no_data_sec" }, 8),
            8,
            1
        )
    end

    local recover_stable_sec = dvr_number(cfg.backup_recover_stable_sec, nil, 1)
    if recover_stable_sec == nil then
        recover_stable_sec = dvr_number(
            dvr_setting_alias({ "dvr_backup_recover_stable_sec", "dvr.backup_recover_stable_sec" }, 30),
            30,
            1
        )
    end

    local segment_guard_sec = dvr_number(cfg.segment_guard_sec, nil, 0)
    if segment_guard_sec == nil then
        segment_guard_sec = dvr_number(
            dvr_setting_alias({ "dvr_segment_guard_sec", "dvr.segment_guard_sec" }, 3),
            3,
            0
        )
    end

    local cursor_flush_sec = dvr_number(cfg.cursor_flush_sec, nil, 1)
    if cursor_flush_sec == nil then
        cursor_flush_sec = dvr_number(
            dvr_setting_alias({ "dvr_cursor_flush_sec", "dvr.cursor_flush_sec" }, 1),
            1,
            1
        )
    end

    local writer_flush_sec = dvr_number(cfg.writer_flush_sec, nil, 1)
    if writer_flush_sec == nil then
        writer_flush_sec = dvr_number(
            dvr_setting_alias({ "dvr_writer_flush_sec", "dvr.writer_flush_sec" }, 5),
            5,
            1
        )
    end

    local min_partial_sec = dvr_number(cfg.min_partial_sec, nil, 1)
    if min_partial_sec == nil then
        min_partial_sec = dvr_number(
            dvr_setting_alias({ "dvr_backup_min_partial_sec", "dvr.backup_min_partial_sec" }, 30),
            30,
            1
        )
    end

    local backup_start_mode = dvr_backup_start_mode(cfg.backup_start_mode, nil)
    if not backup_start_mode then
        backup_start_mode = dvr_backup_start_mode(
            dvr_setting_alias({ "dvr_backup_start_mode", "dvr.backup_start_mode" }, "sequential"),
            "sequential"
        )
    end

    local backup_start_offset_hours = dvr_number(cfg.backup_start_offset_hours, nil)
    if backup_start_offset_hours == nil then
        backup_start_offset_hours = dvr_number(
            dvr_setting_alias({ "dvr_backup_start_offset_hours", "dvr.backup_start_offset_hours" }, nil),
            nil
        )
    end
    if backup_start_mode == "time_offset" and backup_start_offset_hours == nil then
        backup_start_offset_hours = -24
    end
    if backup_start_offset_hours ~= nil then
        backup_start_offset_hours = math.floor(backup_start_offset_hours)
    else
        backup_start_offset_hours = 0
    end

    local backup_fail_checks = dvr_number(cfg.backup_fail_checks, nil, 1)
    if backup_fail_checks == nil then
        backup_fail_checks = dvr_number(
            dvr_setting_alias({ "dvr_backup_fail_checks", "dvr.backup_fail_checks" }, 3),
            3,
            1
        )
    end

    local backup_recover_checks = dvr_number(cfg.backup_recover_checks, nil, 1)
    if backup_recover_checks == nil then
        backup_recover_checks = dvr_number(
            dvr_setting_alias({ "dvr_backup_recover_checks", "dvr.backup_recover_checks" }, 5),
            5,
            1
        )
    end

    local backup_min_rearm_sec = dvr_number(cfg.backup_min_rearm_sec, nil, 0)
    if backup_min_rearm_sec == nil then
        backup_min_rearm_sec = dvr_number(
            dvr_setting_alias({ "dvr_backup_min_rearm_sec", "dvr.backup_min_rearm_sec" }, 120),
            120,
            0
        )
    end

    local min_free_gb = dvr_number(cfg.min_free_gb, nil, 0)
    if min_free_gb == nil then
        min_free_gb = dvr_number(
            dvr_setting_alias({ "dvr_min_free_gb", "dvr.min_free_gb" }, 0),
            0,
            0
        )
    end

    local max_storage_gb = dvr_number(cfg.max_storage_gb, nil, 0)
    if max_storage_gb == nil then
        max_storage_gb = dvr_number(
            dvr_setting_alias({ "dvr_max_storage_gb", "dvr.max_storage_gb" }, 0),
            0,
            0
        )
    end

    local high_watermark_pct = dvr_number(cfg.high_watermark_pct, nil, 0)
    if high_watermark_pct == nil then
        high_watermark_pct = dvr_number(
            dvr_setting_alias({ "dvr_high_watermark_pct", "dvr.high_watermark_pct" }, 0),
            0,
            0
        )
    end
    if high_watermark_pct > 100 then
        high_watermark_pct = 100
    end

    local low_watermark_pct = dvr_number(cfg.low_watermark_pct, nil, 0)
    if low_watermark_pct == nil then
        low_watermark_pct = dvr_number(
            dvr_setting_alias({ "dvr_low_watermark_pct", "dvr.low_watermark_pct" }, 0),
            0,
            0
        )
    end
    if low_watermark_pct > 100 then
        low_watermark_pct = 100
    end

    local archive_path = dvr_normalize_archive_path(cfg.path or cfg.archive_path)
    if not archive_path then
        archive_path = dvr_normalize_archive_path(
            dvr_setting_alias({ "dvr_archive_path", "dvr.archive_path" }, nil)
        )
    end

    if mode == "remote" then
        -- Remote DVR mode must not write archive locally.
        archive_enabled = false
    end

    return {
        mode = mode ~= "" and mode or "local",
        archive_enabled = archive_enabled == true,
        backup_enabled = backup_enabled == true,
        archive_path = archive_path,
        segment_sec = 3600,
        retention_days = math.floor(retention_days),
        backup_trigger_no_data_sec = math.floor(trigger_no_data_sec),
        backup_recover_stable_sec = math.floor(recover_stable_sec),
        segment_guard_sec = math.floor(segment_guard_sec),
        cursor_flush_sec = math.floor(cursor_flush_sec),
        writer_flush_sec = math.floor(writer_flush_sec),
        min_partial_sec = math.floor(min_partial_sec),
        backup_start_mode = backup_start_mode,
        backup_start_offset_hours = backup_start_offset_hours,
        backup_fail_checks = math.floor(backup_fail_checks),
        backup_recover_checks = math.floor(backup_recover_checks),
        backup_min_rearm_sec = math.floor(backup_min_rearm_sec),
        min_free_gb = tonumber(min_free_gb) or 0,
        max_storage_gb = tonumber(max_storage_gb) or 0,
        high_watermark_pct = tonumber(high_watermark_pct) or 0,
        low_watermark_pct = tonumber(low_watermark_pct) or 0,
    }
end

function dvr.upsert_segment(row)
    if type(row) ~= "table" then
        return nil, "invalid segment row"
    end
    local stream_id = tostring(row.stream_id or "")
    if stream_id == "" then
        return nil, "stream_id is required"
    end
    local seg_start_ts = math.floor(tonumber(row.seg_start_ts) or 0)
    if seg_start_ts <= 0 then
        return nil, "seg_start_ts is required"
    end
    local now = math.floor(tonumber(row.updated_ts) or os.time())
    local existing_rows = dvr_db_query("SELECT created_ts FROM dvr_segments WHERE stream_id='" ..
        dvr_sql_escape(stream_id) .. "' AND seg_start_ts=" .. seg_start_ts .. " LIMIT 1;")
    local created_ts = now
    if existing_rows and #existing_rows > 0 then
        created_ts = tonumber(existing_rows[1].created_ts) or created_ts
    else
        created_ts = math.floor(tonumber(row.created_ts) or now)
    end
    local seg_end_ts = math.floor(tonumber(row.seg_end_ts) or seg_start_ts)
    if seg_end_ts < seg_start_ts then
        seg_end_ts = seg_start_ts
    end
    local size_bytes = math.floor(tonumber(row.size_bytes) or 0)
    if size_bytes < 0 then
        size_bytes = 0
    end
    local is_complete = dvr_bool(row.is_complete, false) and 1 or 0
    local path = tostring(row.path or "")
    if path == "" then
        return nil, "path is required"
    end

    local rows = dvr_db_query("SELECT id FROM dvr_segments WHERE stream_id='" ..
        dvr_sql_escape(stream_id) .. "' AND seg_start_ts=" .. seg_start_ts .. " LIMIT 1;")
    if rows and #rows > 0 then
        local id = tonumber(rows[1].id) or 0
        if id > 0 then
            return dvr_db_exec("UPDATE dvr_segments SET " ..
                "seg_end_ts=" .. seg_end_ts .. ", " ..
                "path='" .. dvr_sql_escape(path) .. "', " ..
                "size_bytes=" .. size_bytes .. ", " ..
                "is_complete=" .. is_complete .. ", " ..
                "updated_ts=" .. now .. " " ..
                "WHERE id=" .. id .. ";")
        end
    end

    return dvr_db_exec("INSERT INTO dvr_segments(" ..
        "stream_id, seg_start_ts, seg_end_ts, path, size_bytes, is_complete, created_ts, updated_ts" ..
        ") VALUES(" ..
        "'" .. dvr_sql_escape(stream_id) .. "', " ..
        seg_start_ts .. ", " ..
        seg_end_ts .. ", " ..
        "'" .. dvr_sql_escape(path) .. "', " ..
        size_bytes .. ", " ..
        is_complete .. ", " ..
        created_ts .. ", " ..
        now .. ");")
end

function dvr.get_segment(stream_id, seg_start_ts)
    local sid = tostring(stream_id or "")
    local start_ts = tonumber(seg_start_ts)
    if sid == "" or not start_ts then
        return nil
    end
    local rows = dvr_db_query("SELECT * FROM dvr_segments WHERE stream_id='" ..
        dvr_sql_escape(sid) .. "' AND seg_start_ts=" .. math.floor(start_ts) ..
        " ORDER BY updated_ts DESC LIMIT 1;")
    if not rows or #rows == 0 then
        return nil
    end
    local row = rows[1]
    row.seg_start_ts = tonumber(row.seg_start_ts) or 0
    row.seg_end_ts = tonumber(row.seg_end_ts) or row.seg_start_ts
    row.size_bytes = tonumber(row.size_bytes) or 0
    row.is_complete = tonumber(row.is_complete) == 1
    return row
end

function dvr.delete_segment(stream_id, seg_start_ts)
    local sid = tostring(stream_id or "")
    local start_ts = tonumber(seg_start_ts)
    if sid == "" or not start_ts then
        return nil, "stream_id/seg_start_ts required"
    end
    return dvr_db_exec("DELETE FROM dvr_segments WHERE stream_id='" ..
        dvr_sql_escape(sid) .. "' AND seg_start_ts=" .. math.floor(start_ts) .. ";")
end

function dvr.list_segments(stream_id, from_ts, to_ts, include_partial, limit)
    local sid = tostring(stream_id or "")
    if sid == "" then
        return {}
    end
    local where = {
        "stream_id='" .. dvr_sql_escape(sid) .. "'",
    }
    if dvr_bool(include_partial, false) ~= true then
        where[#where + 1] = "is_complete=1"
    end
    if tonumber(from_ts) then
        where[#where + 1] = "seg_end_ts>=" .. math.floor(tonumber(from_ts))
    end
    if tonumber(to_ts) then
        where[#where + 1] = "seg_start_ts<=" .. math.floor(tonumber(to_ts))
    end
    local row_limit = math.floor(dvr_number(limit, 1000, 1))
    if row_limit > 10000 then
        row_limit = 10000
    end
    local sql = "SELECT * FROM dvr_segments WHERE " .. table.concat(where, " AND ") ..
        " ORDER BY seg_start_ts ASC LIMIT " .. row_limit .. ";"
    local rows = dvr_db_query(sql) or {}
    for _, row in ipairs(rows) do
        row.seg_start_ts = tonumber(row.seg_start_ts) or 0
        row.seg_end_ts = tonumber(row.seg_end_ts) or row.seg_start_ts
        row.size_bytes = tonumber(row.size_bytes) or 0
        row.is_complete = tonumber(row.is_complete) == 1
    end
    return rows
end

function dvr.select_archive_segment(stream_id, opts)
    opts = opts or {}
    local sid = dvr_trim(stream_id)
    if sid == "" then
        return nil, "stream_id is required"
    end
    local include_partial = dvr_bool(opts.include_partial, false) == true
    local from_ts = tonumber(opts.from_ts)
    local min_partial_sec = math.floor(dvr_number(opts.min_partial_sec, 30, 1))
    local where = {
        "stream_id='" .. dvr_sql_escape(sid) .. "'",
    }
    if include_partial then
        where[#where + 1] = "(is_complete=1 OR (is_complete=0 AND (seg_end_ts - seg_start_ts) >= " .. min_partial_sec .. "))"
    else
        where[#where + 1] = "is_complete=1"
    end
    if from_ts and from_ts > 0 then
        where[#where + 1] = "seg_start_ts<=" .. math.floor(from_ts)
    end
    local where_sql = table.concat(where, " AND ")
    local rows = dvr_db_query("SELECT * FROM dvr_segments WHERE " .. where_sql ..
        " ORDER BY seg_start_ts DESC LIMIT 1;") or {}
    if #rows == 0 and dvr_bool(opts.fallback_oldest, true) == true then
        local where_oldest = {
            "stream_id='" .. dvr_sql_escape(sid) .. "'",
        }
        if include_partial then
            where_oldest[#where_oldest + 1] = "(is_complete=1 OR (is_complete=0 AND (seg_end_ts - seg_start_ts) >= " .. min_partial_sec .. "))"
        else
            where_oldest[#where_oldest + 1] = "is_complete=1"
        end
        rows = dvr_db_query("SELECT * FROM dvr_segments WHERE " .. table.concat(where_oldest, " AND ") ..
            " ORDER BY seg_start_ts ASC LIMIT 1;") or {}
    end
    if #rows == 0 then
        return nil, "no segments"
    end
    local row = rows[1]
    row.seg_start_ts = tonumber(row.seg_start_ts) or 0
    row.seg_end_ts = tonumber(row.seg_end_ts) or row.seg_start_ts
    row.size_bytes = tonumber(row.size_bytes) or 0
    row.is_complete = tonumber(row.is_complete) == 1
    local path = dvr_trim(row.path)
    local size = math.floor(tonumber(row.size_bytes) or 0)
    if size <= 0 and path ~= "" and utils and type(utils.stat) == "function" then
        local st = utils.stat(path)
        if st and not st.error then
            size = math.floor(tonumber(st.size) or 0)
        end
    end
    if size <= 0 and path ~= "" and path:sub(-8) == ".part.ts" and utils and type(utils.stat) == "function" then
        local alt_path = path:sub(1, -9) .. ".ts"
        local alt_st = utils.stat(alt_path)
        local alt_size = (alt_st and not alt_st.error) and math.floor(tonumber(alt_st.size) or 0) or 0
        if alt_size > 0 then
            path = alt_path
            size = alt_size
        end
    end
    if size <= 0 then
        return nil, "segment not found"
    end
    row.path = path
    row.size_bytes = size
    local offset_sec = 0
    if from_ts and from_ts > row.seg_start_ts then
        offset_sec = math.floor(from_ts - row.seg_start_ts)
    end
    if offset_sec < 0 then
        offset_sec = 0
    end
    return {
        stream_id = sid,
        segment = row,
        cursor_offset_sec = offset_sec,
    }
end

function dvr.resolve_archive_from_query(query, now_ts)
    if type(query) ~= "table" then
        return nil
    end

    local from_ts = dvr_parse_query_number(query.from_ts or query.ts)
    if from_ts and from_ts > 0 then
        return math.floor(from_ts)
    end

    local timeshift_hours = dvr_parse_query_number(query.timeshift
        or query.timeshift_hours
        or query.shift_hours
        or query.time_shift)
    if timeshift_hours == nil or timeshift_hours == 0 then
        return nil
    end

    local hours = math.abs(timeshift_hours)
    if hours > 24 * 365 * 10 then
        hours = 24 * 365 * 10
    end
    local base_now = math.floor(tonumber(now_ts) or os.time())
    local resolved = base_now - math.floor(hours * 3600)
    if resolved < 1 then
        resolved = 1
    end
    return resolved
end

function dvr.cleanup_segments(stream_id, retention_days, keep_seg_start_ts)
    local sid = tostring(stream_id or "")
    if sid == "" then
        return 0
    end
    local days = math.floor(dvr_number(retention_days, 3, 1))
    local cutoff = os.time() - (days * 86400)
    local where = "stream_id='" .. dvr_sql_escape(sid) .. "' AND seg_end_ts<" .. cutoff
    if tonumber(keep_seg_start_ts) then
        where = where .. " AND seg_start_ts<>" .. math.floor(tonumber(keep_seg_start_ts))
    end
    local rows = dvr_db_query("SELECT id, path FROM dvr_segments WHERE " .. where .. ";") or {}
    local deleted = 0
    for _, row in ipairs(rows) do
        if row.path and row.path ~= "" then
            pcall(os.remove, tostring(row.path))
        end
        local id = tonumber(row.id) or 0
        if id > 0 then
            local ok = dvr_db_exec("DELETE FROM dvr_segments WHERE id=" .. id .. ";")
            if ok then
                deleted = deleted + 1
            end
        end
    end
    return deleted
end

function dvr.add_event(stream_id, code, severity, message, details)
    local sid = tostring(stream_id or "")
    if sid == "" then
        return nil
    end
    local now = os.time()
    local details_json = nil
    if type(details) == "table" then
        details_json = dvr_json_encode(details)
    elseif details ~= nil then
        details_json = tostring(details)
    end
    local ok = dvr_db_exec("INSERT INTO dvr_events(ts, stream_id, code, severity, message, details_json) VALUES(" ..
        now .. ", " ..
        "'" .. dvr_sql_escape(sid) .. "', " ..
        "'" .. dvr_sql_escape(code or "DVR_EVENT") .. "', " ..
        "'" .. dvr_sql_escape(severity or "INFO") .. "', " ..
        "'" .. dvr_sql_escape(message or "") .. "', " ..
        (details_json and ("'" .. dvr_sql_escape(details_json) .. "'") or "NULL") ..
        ");")
    return ok
end

function dvr.get_backup_state(stream_id)
    local sid = tostring(stream_id or "")
    if sid == "" then
        return {
            mode = "LIVE",
            cycle_id = nil,
            cursor_seg_start_ts = 0,
            cursor_offset_sec = 0,
            recording_paused = false,
            last_state_seq = 0,
            last_reason = nil,
            updated_ts = 0,
        }
    end
    local rows = dvr_db_query("SELECT * FROM dvr_backup_state WHERE stream_id='" ..
        dvr_sql_escape(sid) .. "' LIMIT 1;") or {}
    if #rows == 0 then
        return {
            mode = "LIVE",
            cycle_id = nil,
            cursor_seg_start_ts = 0,
            cursor_offset_sec = 0,
            recording_paused = false,
            last_state_seq = 0,
            last_reason = nil,
            updated_ts = 0,
        }
    end
    local row = rows[1]
    row.mode = tostring(row.mode or "LIVE")
    row.cursor_seg_start_ts = tonumber(row.cursor_seg_start_ts) or 0
    row.cursor_offset_sec = tonumber(row.cursor_offset_sec) or 0
    row.recording_paused = tonumber(row.recording_paused) == 1
    row.last_state_seq = tonumber(row.last_state_seq) or 0
    row.updated_ts = tonumber(row.updated_ts) or 0
    return row
end

function dvr.save_backup_state(stream_id, state)
    local sid = tostring(stream_id or "")
    if sid == "" then
        return nil, "stream_id is required"
    end
    state = state or {}
    local mode = tostring(state.mode or "LIVE")
    local cycle_id = state.cycle_id and tostring(state.cycle_id) or nil
    local cursor_seg_start_ts = math.floor(tonumber(state.cursor_seg_start_ts) or 0)
    local cursor_offset_sec = math.floor(tonumber(state.cursor_offset_sec) or 0)
    if cursor_offset_sec < 0 then
        cursor_offset_sec = 0
    end
    local recording_paused = dvr_bool(state.recording_paused, false) and 1 or 0
    local last_state_seq = math.floor(tonumber(state.last_state_seq) or 0)
    if last_state_seq < 0 then
        last_state_seq = 0
    end
    local last_reason = state.last_reason and tostring(state.last_reason) or nil
    local updated_ts = math.floor(tonumber(state.updated_ts) or os.time())
    return dvr_db_exec("INSERT OR REPLACE INTO dvr_backup_state(" ..
        "stream_id, mode, cycle_id, cursor_seg_start_ts, cursor_offset_sec, recording_paused, last_state_seq, last_reason, updated_ts" ..
        ") VALUES(" ..
        "'" .. dvr_sql_escape(sid) .. "', " ..
        "'" .. dvr_sql_escape(mode) .. "', " ..
        (cycle_id and ("'" .. dvr_sql_escape(cycle_id) .. "'") or "NULL") .. ", " ..
        cursor_seg_start_ts .. ", " ..
        cursor_offset_sec .. ", " ..
        recording_paused .. ", " ..
        last_state_seq .. ", " ..
        (last_reason and ("'" .. dvr_sql_escape(last_reason) .. "'") or "NULL") .. ", " ..
        updated_ts .. ");")
end

function dvr.reset_backup_state(stream_id)
    local sid = tostring(stream_id or "")
    if sid == "" then
        return nil, "stream_id is required"
    end
    return dvr.save_backup_state(sid, {
        mode = "LIVE",
        cycle_id = nil,
        cursor_seg_start_ts = 0,
        cursor_offset_sec = 0,
        recording_paused = false,
        last_state_seq = 0,
        last_reason = "manual_reset",
        updated_ts = os.time(),
    })
end

function dvr.clear_cycle(stream_id, cycle_id)
    local sid = tostring(stream_id or "")
    local cid = tostring(cycle_id or "")
    if sid == "" or cid == "" then
        return nil, "stream_id/cycle_id required"
    end
    return dvr_db_exec("DELETE FROM dvr_backup_cycle_items WHERE stream_id='" ..
        dvr_sql_escape(sid) .. "' AND cycle_id='" .. dvr_sql_escape(cid) .. "';")
end

function dvr.build_cycle(stream_id, opts)
    opts = opts or {}
    local sid = tostring(stream_id or "")
    if sid == "" then
        return nil, "stream_id is required"
    end
    local include_partial = dvr_bool(opts.include_partial, true)
    local min_partial_sec = math.floor(dvr_number(opts.min_partial_sec, 30, 1))
    local rows = dvr_db_query("SELECT seg_start_ts, seg_end_ts FROM dvr_segments " ..
        "WHERE stream_id='" .. dvr_sql_escape(sid) .. "' AND is_complete=1 " ..
        "ORDER BY seg_start_ts ASC;") or {}

    if #rows == 0 and include_partial then
        rows = dvr_db_query("SELECT seg_start_ts, seg_end_ts FROM dvr_segments " ..
            "WHERE stream_id='" .. dvr_sql_escape(sid) .. "' AND is_complete=0 " ..
            "AND (seg_end_ts - seg_start_ts) >= " .. min_partial_sec .. " " ..
            "ORDER BY seg_start_ts ASC;") or {}
    end
    if #rows == 0 then
        return nil, "no segments"
    end

    local cycle_id = tostring(math.floor(os.time())) .. "-" .. tostring(math.random(1000, 9999))
    local now = os.time()
    for _, row in ipairs(rows) do
        local seg_start_ts = math.floor(tonumber(row.seg_start_ts) or 0)
        if seg_start_ts > 0 then
            local ok, err = dvr_db_exec("INSERT OR REPLACE INTO dvr_backup_cycle_items(" ..
                "stream_id, cycle_id, seg_start_ts, status, played_sec, updated_ts" ..
                ") VALUES(" ..
                "'" .. dvr_sql_escape(sid) .. "', " ..
                "'" .. dvr_sql_escape(cycle_id) .. "', " ..
                seg_start_ts .. ", " ..
                "'pending', 0, " .. now .. ");")
            if not ok then
                return nil, err
            end
        end
    end
    return cycle_id, nil
end

function dvr.next_pending(stream_id, cycle_id)
    local sid = tostring(stream_id or "")
    local cid = tostring(cycle_id or "")
    if sid == "" or cid == "" then
        return nil
    end
    local rows = dvr_db_query("SELECT seg_start_ts FROM dvr_backup_cycle_items " ..
        "WHERE stream_id='" .. dvr_sql_escape(sid) .. "' AND cycle_id='" .. dvr_sql_escape(cid) .. "' " ..
        "AND status='pending' ORDER BY seg_start_ts ASC LIMIT 1;") or {}
    if #rows == 0 then
        return nil
    end
    return math.floor(tonumber(rows[1].seg_start_ts) or 0)
end

function dvr.mark_cycle_item(stream_id, cycle_id, seg_start_ts, status, played_sec)
    local sid = tostring(stream_id or "")
    local cid = tostring(cycle_id or "")
    local start_ts = tonumber(seg_start_ts)
    if sid == "" or cid == "" or not start_ts then
        return nil, "invalid args"
    end
    local p = math.floor(tonumber(played_sec) or 0)
    if p < 0 then
        p = 0
    end
    local now = os.time()
    return dvr_db_exec("UPDATE dvr_backup_cycle_items SET " ..
        "status='" .. dvr_sql_escape(status or "pending") .. "', " ..
        "played_sec=" .. p .. ", " ..
        "updated_ts=" .. now .. " " ..
        "WHERE stream_id='" .. dvr_sql_escape(sid) .. "' " ..
        "AND cycle_id='" .. dvr_sql_escape(cid) .. "' " ..
        "AND seg_start_ts=" .. math.floor(start_ts) .. ";")
end

function dvr.cycle_counts(stream_id, cycle_id)
    local sid = tostring(stream_id or "")
    local cid = tostring(cycle_id or "")
    if sid == "" or cid == "" then
        return { pending = 0, playing = 0, done = 0, skipped = 0 }
    end
    local rows = dvr_db_query("SELECT status, COUNT(*) AS total FROM dvr_backup_cycle_items " ..
        "WHERE stream_id='" .. dvr_sql_escape(sid) .. "' AND cycle_id='" .. dvr_sql_escape(cid) .. "' " ..
        "GROUP BY status;") or {}
    local out = { pending = 0, playing = 0, done = 0, skipped = 0 }
    for _, row in ipairs(rows) do
        local key = tostring(row.status or ""):lower()
        if out[key] ~= nil then
            out[key] = tonumber(row.total) or 0
        end
    end
    return out
end

function dvr.rebuild_cycle(stream_id, opts)
    local sid = tostring(stream_id or "")
    if sid == "" then
        return nil, "stream_id is required"
    end
    local cycle_id, err = dvr.build_cycle(sid, opts)
    if not cycle_id then
        return nil, err
    end
    local first = dvr.next_pending(sid, cycle_id)
    return {
        stream_id = sid,
        cycle_id = cycle_id,
        first_seg_start_ts = first,
    }
end

function dvr.get_backup_state_for_api(stream_id)
    local sid = tostring(stream_id or "")
    local state = dvr.get_backup_state(sid)
    local cycle_id = state and state.cycle_id or nil
    local counts = dvr.cycle_counts(sid, cycle_id)
    local current = nil
    if state and tonumber(state.cursor_seg_start_ts) and tonumber(state.cursor_seg_start_ts) > 0 then
        current = dvr.get_segment(sid, tonumber(state.cursor_seg_start_ts))
    end
    local seg_meta_rows = dvr_db_query("SELECT " ..
        "COUNT(*) AS total, " ..
        "SUM(CASE WHEN is_complete=1 THEN 1 ELSE 0 END) AS complete_total, " ..
        "MAX(seg_end_ts) AS last_seg_end_ts, " ..
        "MAX(updated_ts) AS last_write_ts " ..
        "FROM dvr_segments WHERE stream_id='" .. dvr_sql_escape(sid) .. "';") or {}
    local seg_meta = seg_meta_rows[1] or {}
    local segments_total = tonumber(seg_meta.total) or 0
    local segments_ready = tonumber(seg_meta.complete_total) or 0
    local last_seg_end_ts = tonumber(seg_meta.last_seg_end_ts) or 0
    local last_write_ts = tonumber(seg_meta.last_write_ts) or 0
    local archive_lag_sec = 0
    if last_seg_end_ts > 0 then
        archive_lag_sec = math.max(0, os.time() - last_seg_end_ts)
    end

    local storage = nil
    local stream_row = dvr.get_stream(sid)
    local archive_root = dvr_normalize_archive_path(stream_row and stream_row.archive_path or nil)
    if not archive_root and config and type(config.get_stream) == "function" then
        local local_row = config.get_stream(sid)
        if local_row and type(local_row.config) == "table" then
            local local_settings = dvr.settings_for_stream(local_row.config)
            archive_root = dvr_normalize_archive_path(local_settings and local_settings.archive_path or nil)
        end
    end
    if not archive_root then
        local data_dir = (config and config.data_dir) or "./data"
        archive_root = dvr_join_path(data_dir, "dvr")
    end
    local st = dvr_statvfs(archive_root)
    if st then
        storage = {
            archive_path = archive_root,
            free_bytes = tonumber(st.avail_bytes) or 0,
            total_bytes = tonumber(st.total_bytes) or 0,
            used_percent = tonumber(st.used_percent) or 0,
        }
    else
        storage = {
            archive_path = archive_root,
            free_bytes = 0,
            total_bytes = 0,
            used_percent = 0,
        }
    end

    return {
        stream_id = sid,
        mode = state.mode or "LIVE",
        cycle_id = cycle_id,
        cursor_seg_start_ts = tonumber(state.cursor_seg_start_ts) or 0,
        cursor_offset_sec = tonumber(state.cursor_offset_sec) or 0,
        recording_paused = state.recording_paused == true,
        last_state_seq = tonumber(state.last_state_seq) or 0,
        last_reason = state.last_reason,
        updated_ts = tonumber(state.updated_ts) or 0,
        current_segment = current,
        pending_count = counts.pending or 0,
        done_count = counts.done or 0,
        playing_count = counts.playing or 0,
        skipped_count = counts.skipped or 0,
        segments_total = segments_total,
        segments_ready = segments_ready,
        last_segment_end_ts = last_seg_end_ts,
        last_write_ts = last_write_ts,
        archive_lag_sec = archive_lag_sec,
        storage = storage,
    }
end

function dvr.cursor_reset(stream_id)
    local sid = tostring(stream_id or "")
    if sid == "" then
        return nil, "stream_id is required"
    end
    local state = dvr.get_backup_state(sid)
    if state and state.cycle_id then
        dvr.clear_cycle(sid, state.cycle_id)
    end
    local ok, err = dvr.reset_backup_state(sid)
    if not ok then
        return nil, err
    end
    return dvr.get_backup_state_for_api(sid)
end

function dvr.get_cycle_item(stream_id, cycle_id, seg_start_ts)
    local sid = dvr_trim(stream_id)
    local cid = dvr_trim(cycle_id)
    local seg = tonumber(seg_start_ts)
    if sid == "" or cid == "" or not seg then
        return nil
    end
    local rows = dvr_db_query("SELECT * FROM dvr_backup_cycle_items " ..
        "WHERE stream_id='" .. dvr_sql_escape(sid) .. "' " ..
        "AND cycle_id='" .. dvr_sql_escape(cid) .. "' " ..
        "AND seg_start_ts=" .. math.floor(seg) .. " LIMIT 1;") or {}
    if #rows == 0 then
        return nil
    end
    local row = rows[1]
    row.seg_start_ts = tonumber(row.seg_start_ts) or 0
    row.played_sec = tonumber(row.played_sec) or 0
    row.updated_ts = tonumber(row.updated_ts) or 0
    row.status = tostring(row.status or "pending")
    return row
end

local function dvr_segment_file_size(path)
    local p = dvr_trim(path)
    if p == "" or not (utils and type(utils.stat) == "function") then
        return 0
    end
    local st = utils.stat(p)
    if not st or st.error then
        return 0
    end
    local size = tonumber(st.size) or 0
    if size < 0 then
        size = 0
    end
    return math.floor(size)
end

local function dvr_segment_effective_location(segment)
    if type(segment) ~= "table" then
        return "", 0
    end
    local path = dvr_trim(segment.path)
    local size = math.floor(tonumber(segment.size_bytes) or 0)
    if size < 0 then
        size = 0
    end
    if size <= 0 then
        size = dvr_segment_file_size(path)
    end
    if size <= 0 and path ~= "" and path:sub(-8) == ".part.ts" then
        local alt_path = path:sub(1, -9) .. ".ts"
        local alt_size = dvr_segment_file_size(alt_path)
        if alt_size > 0 then
            return alt_path, alt_size
        end
    end
    return path, size
end

local function dvr_save_cursor_state(stream_id, state, patch)
    patch = patch or {}
    local ok, err = dvr.save_backup_state(stream_id, {
        mode = patch.mode or state.mode or "LIVE",
        cycle_id = patch.cycle_id,
        cursor_seg_start_ts = patch.cursor_seg_start_ts or 0,
        cursor_offset_sec = patch.cursor_offset_sec or 0,
        recording_paused = patch.recording_paused ~= nil and patch.recording_paused or (state.recording_paused == true),
        last_state_seq = patch.last_state_seq or tonumber(state.last_state_seq) or 0,
        last_reason = patch.last_reason or state.last_reason,
        updated_ts = patch.updated_ts or os.time(),
    })
    if not ok then
        return nil, err
    end
    return true
end

local function dvr_rebuild_cycle_for_cursor(stream_id, opts)
    local rebuilt, rebuild_err = dvr.rebuild_cycle(stream_id, {
        include_partial = opts.include_partial ~= false,
        min_partial_sec = opts.min_partial_sec,
    })
    if not rebuilt then
        return nil, rebuild_err or "no segments"
    end
    local cycle_id = rebuilt.cycle_id
    local pending_rows = dvr_db_query("SELECT seg_start_ts FROM dvr_backup_cycle_items " ..
        "WHERE stream_id='" .. dvr_sql_escape(stream_id) .. "' " ..
        "AND cycle_id='" .. dvr_sql_escape(cycle_id) .. "' " ..
        "AND status='pending' ORDER BY seg_start_ts ASC;") or {}
    local pending = {}
    for _, row in ipairs(pending_rows) do
        local seg = math.floor(tonumber(row.seg_start_ts) or 0)
        if seg > 0 then
            pending[#pending + 1] = seg
        end
    end
    local seg_start = pending[1] or tonumber(rebuilt.first_seg_start_ts) or 0
    local start_mode = dvr_backup_start_mode(opts.start_mode, "sequential")
    local use_time_offset = (opts.force_oldest ~= true) and (start_mode == "time_offset")
    if use_time_offset and #pending > 0 then
        local offset_hours = dvr_number(opts.start_offset_hours, nil)
        if offset_hours == nil then
            offset_hours = -24
        end
        local target_ts = math.floor((tonumber(opts.now_ts) or os.time()) + (tonumber(offset_hours) * 3600))
        local chosen = pending[1]
        for _, seg in ipairs(pending) do
            if seg <= target_ts then
                chosen = seg
            else
                break
            end
        end
        seg_start = chosen
        for _, seg in ipairs(pending) do
            if seg < seg_start then
                local skip_ok, skip_err = dvr.mark_cycle_item(stream_id, cycle_id, seg, "skipped", 0)
                if not skip_ok then
                    return nil, skip_err or "failed to mark skipped cycle item"
                end
            else
                break
            end
        end
    end
    if seg_start <= 0 then
        return nil, "no segments"
    end
    local mark_ok, mark_err = dvr.mark_cycle_item(stream_id, cycle_id, seg_start, "playing", 0)
    if not mark_ok then
        return nil, mark_err or "failed to mark cycle item"
    end
    return {
        cycle_id = cycle_id,
        seg_start_ts = seg_start,
        cursor_offset_sec = 0,
        cycle_restarted = true,
    }
end

local function dvr_ensure_cursor(stream_id, state, opts)
    opts = opts or {}
    local allow_cycle_restart = opts.allow_cycle_restart ~= false
    local cycle_id = dvr_trim(state and state.cycle_id)
    local cursor_seg = tonumber(state and state.cursor_seg_start_ts) or 0
    local cursor_offset = math.max(0, math.floor(tonumber(state and state.cursor_offset_sec) or 0))

    local function pick_from_cycle(cid, preferred_seg, preferred_offset)
        if cid == "" then
            return nil
        end
        if preferred_seg and preferred_seg > 0 then
            local item = dvr.get_cycle_item(stream_id, cid, preferred_seg)
            if item and (item.status == "pending" or item.status == "playing") then
                local played = math.max(0, math.floor(tonumber(item.played_sec) or 0))
                local offset = math.max(math.floor(preferred_offset or 0), played)
                if item.status ~= "playing" or played ~= offset then
                    dvr.mark_cycle_item(stream_id, cid, preferred_seg, "playing", offset)
                end
                return {
                    cycle_id = cid,
                    seg_start_ts = preferred_seg,
                    cursor_offset_sec = offset,
                    cycle_restarted = false,
                }
            end
        end
        local next_seg = dvr.next_pending(stream_id, cid)
        if next_seg and next_seg > 0 then
            local mark_ok, mark_err = dvr.mark_cycle_item(stream_id, cid, next_seg, "playing", 0)
            if not mark_ok then
                return nil, mark_err or "failed to mark next cycle item"
            end
            return {
                cycle_id = cid,
                seg_start_ts = next_seg,
                cursor_offset_sec = 0,
                cycle_restarted = false,
            }
        end
        return nil, "cycle exhausted"
    end

    local current, current_err = pick_from_cycle(cycle_id, cursor_seg, cursor_offset)
    if current then
        return current
    end
    if not allow_cycle_restart then
        return nil, current_err or "cycle exhausted"
    end
    local rebuild_opts = {
        include_partial = opts.include_partial ~= false,
        min_partial_sec = opts.min_partial_sec,
        start_mode = opts.start_mode,
        start_offset_hours = opts.start_offset_hours,
        now_ts = opts.now_ts,
    }
    if cycle_id ~= "" and current_err == "cycle exhausted" then
        rebuild_opts.force_oldest = true
    end
    return dvr_rebuild_cycle_for_cursor(stream_id, rebuild_opts)
end

function dvr.backup_select_segment(stream_id, opts)
    opts = opts or {}
    local sid = dvr_trim(stream_id)
    if sid == "" then
        return nil, "stream_id is required"
    end
    local state = dvr.get_backup_state(sid)
    local selected, select_err = dvr_ensure_cursor(sid, state, opts)
    if not selected then
        return nil, select_err
    end

    local segment = dvr.get_segment(sid, selected.seg_start_ts)
    local effective_path, effective_size = dvr_segment_effective_location(segment)
    if segment and effective_size > 0 then
        if effective_path ~= tostring(segment.path or "") or effective_size ~= (tonumber(segment.size_bytes) or 0) then
            segment.path = effective_path
            segment.size_bytes = effective_size
            dvr.upsert_segment({
                stream_id = sid,
                seg_start_ts = segment.seg_start_ts,
                seg_end_ts = segment.seg_end_ts,
                path = segment.path,
                size_bytes = segment.size_bytes,
                is_complete = segment.is_complete == true,
                created_ts = segment.created_ts,
                updated_ts = os.time(),
            })
        end
    end
    if not segment or effective_size <= 0 then
        dvr.mark_cycle_item(sid, selected.cycle_id, selected.seg_start_ts, "skipped", 0)
        local next_selected, next_err = dvr_ensure_cursor(sid, {
            mode = state.mode,
            cycle_id = selected.cycle_id,
            cursor_seg_start_ts = 0,
            cursor_offset_sec = 0,
            recording_paused = state.recording_paused,
            last_state_seq = state.last_state_seq,
            last_reason = (not segment) and "segment_missing" or "segment_empty",
        }, opts)
        if not next_selected then
            return nil, next_err or "segment not found"
        end
        selected = next_selected
        segment = dvr.get_segment(sid, selected.seg_start_ts)
        effective_path, effective_size = dvr_segment_effective_location(segment)
        if not segment or effective_size <= 0 then
            return nil, "segment not found"
        end
        if effective_path ~= tostring(segment.path or "") or effective_size ~= (tonumber(segment.size_bytes) or 0) then
            segment.path = effective_path
            segment.size_bytes = effective_size
            dvr.upsert_segment({
                stream_id = sid,
                seg_start_ts = segment.seg_start_ts,
                seg_end_ts = segment.seg_end_ts,
                path = segment.path,
                size_bytes = segment.size_bytes,
                is_complete = segment.is_complete == true,
                created_ts = segment.created_ts,
                updated_ts = os.time(),
            })
        end
    end

    local save_ok, save_err = dvr_save_cursor_state(sid, state, {
        cycle_id = selected.cycle_id,
        cursor_seg_start_ts = selected.seg_start_ts,
        cursor_offset_sec = selected.cursor_offset_sec,
        last_reason = selected.cycle_restarted and "cycle_restart" or "backup_select_segment",
    })
    if not save_ok then
        return nil, save_err
    end

    local state_row = dvr.get_backup_state_for_api(sid)
    return {
        stream_id = sid,
        state = state_row,
        segment = segment,
        cycle_restarted = selected.cycle_restarted == true,
    }
end

function dvr.backup_commit_progress(stream_id, payload)
    payload = payload or {}
    local sid = dvr_trim(stream_id)
    if sid == "" then
        return nil, "stream_id is required"
    end

    local selected, select_err = dvr.backup_select_segment(sid, {
        allow_cycle_restart = payload.allow_cycle_restart ~= false,
        include_partial = payload.include_partial ~= false,
        min_partial_sec = payload.min_partial_sec,
        start_mode = payload.start_mode,
        start_offset_hours = payload.start_offset_hours,
    })
    if not selected then
        return nil, select_err
    end

    local state = selected.state
    local cycle_id = dvr_trim(state and state.cycle_id)
    local seg_start = tonumber(payload.seg_start_ts) or tonumber(state and state.cursor_seg_start_ts) or 0
    if cycle_id == "" or seg_start <= 0 then
        return nil, "backup state is not initialized"
    end

    local segment = dvr.get_segment(sid, seg_start)
    if not segment then
        dvr.mark_cycle_item(sid, cycle_id, seg_start, "skipped", 0)
        local next_row = dvr.backup_select_segment(sid, {
            allow_cycle_restart = payload.allow_cycle_restart ~= false,
            include_partial = payload.include_partial ~= false,
            min_partial_sec = payload.min_partial_sec,
            start_mode = payload.start_mode,
            start_offset_hours = payload.start_offset_hours,
        })
        if not next_row then
            return nil, "segment missing"
        end
        return {
            ok = true,
            stream_id = sid,
            cycle_exhausted = false,
            advanced = true,
            state = next_row.state,
            segment = next_row.segment,
            event = "segment_missing_skip",
        }
    end

    local played_sec = math.max(0, math.floor(tonumber(payload.played_sec) or tonumber(state.cursor_offset_sec) or 0))
    local duration = dvr.segment_duration(segment)
    local guard_sec = math.max(0, math.floor(tonumber(payload.segment_guard_sec) or 3))
    local done_threshold = math.max(0, duration - guard_sec)
    local force_done = dvr_bool(payload.done, false) == true
    local force_skip = dvr_bool(payload.skip, false) == true
    local segment_done = force_done or (duration > 0 and played_sec >= done_threshold)

    if force_skip then
        dvr.mark_cycle_item(sid, cycle_id, seg_start, "skipped", played_sec)
    elseif segment_done then
        dvr.mark_cycle_item(sid, cycle_id, seg_start, "done", played_sec)
    else
        dvr.mark_cycle_item(sid, cycle_id, seg_start, "playing", played_sec)
    end

    if not force_skip and not segment_done then
        local save_ok, save_err = dvr_save_cursor_state(sid, state, {
            cycle_id = cycle_id,
            cursor_seg_start_ts = seg_start,
            cursor_offset_sec = played_sec,
            last_reason = "backup_progress",
        })
        if not save_ok then
            return nil, save_err
        end
        return {
            ok = true,
            stream_id = sid,
            cycle_exhausted = false,
            advanced = false,
            state = dvr.get_backup_state_for_api(sid),
            segment = segment,
            event = "progress",
        }
    end

    local next_result, next_err = dvr.backup_select_segment(sid, {
        allow_cycle_restart = payload.allow_cycle_restart ~= false,
        include_partial = payload.include_partial ~= false,
        min_partial_sec = payload.min_partial_sec,
        start_mode = payload.start_mode,
        start_offset_hours = payload.start_offset_hours,
    })
    if not next_result then
        local save_ok, save_err = dvr_save_cursor_state(sid, state, {
            cycle_id = cycle_id,
            cursor_seg_start_ts = 0,
            cursor_offset_sec = 0,
            last_reason = "cycle_exhausted",
        })
        if not save_ok then
            return nil, save_err
        end
        return {
            ok = true,
            stream_id = sid,
            cycle_exhausted = true,
            advanced = false,
            state = dvr.get_backup_state_for_api(sid),
            segment = nil,
            event = force_skip and "skip_exhausted" or "done_exhausted",
            error = next_err,
        }
    end

    return {
        ok = true,
        stream_id = sid,
        cycle_exhausted = false,
        advanced = true,
        cycle_restarted = next_result.cycle_restarted == true,
        state = next_result.state,
        segment = next_result.segment,
        event = force_skip and "skip_advance" or "done_advance",
    }
end

local function dvr_stream_defaults()
    return {
        stream_id = "",
        name = "",
        source_url = "",
        archive_path = nil,
        config_json = nil,
        config = nil,
        record_enabled = false,
        retention_days = 3,
        segment_sec = 3600,
        recording_paused = false,
        last_state_seq = 0,
        last_mode = "LIVE",
        last_reason = nil,
        created_ts = 0,
        updated_ts = 0,
    }
end

local function dvr_normalize_stream_row(row)
    if type(row) ~= "table" then
        return dvr_stream_defaults()
    end
    row.stream_id = tostring(row.stream_id or "")
    row.name = tostring(row.name or "")
    row.source_url = tostring(row.source_url or "")
    row.archive_path = dvr_normalize_archive_path(row.archive_path)
    row.config_json = row.config_json and tostring(row.config_json) or nil
    row.config = nil
    if row.config_json and row.config_json ~= "" then
        local ok_cfg, decoded_cfg = pcall(dvr_json_decode, row.config_json)
        if ok_cfg and type(decoded_cfg) == "table" then
            row.config = decoded_cfg
        end
    end
    row.record_enabled = tonumber(row.record_enabled) == 1
    row.retention_days = math.max(1, math.floor(tonumber(row.retention_days) or 3))
    row.segment_sec = 3600
    row.recording_paused = tonumber(row.recording_paused) == 1
    row.last_state_seq = math.max(0, math.floor(tonumber(row.last_state_seq) or 0))
    row.last_mode = tostring(row.last_mode or "LIVE")
    row.last_reason = row.last_reason and tostring(row.last_reason) or nil
    row.created_ts = math.floor(tonumber(row.created_ts) or 0)
    row.updated_ts = math.floor(tonumber(row.updated_ts) or 0)
    return row
end

function dvr.get_stream(stream_id)
    local sid = dvr_trim(stream_id)
    if sid == "" then
        return nil
    end
    local rows = dvr_db_query("SELECT * FROM dvr_streams WHERE stream_id='" ..
        dvr_sql_escape(sid) .. "' LIMIT 1;") or {}
    if #rows == 0 then
        return nil
    end
    return dvr_normalize_stream_row(rows[1])
end

function dvr.list_streams(opts)
    opts = opts or {}
    local where = {}
    if opts.record_enabled ~= nil then
        where[#where + 1] = "record_enabled=" .. ((dvr_bool(opts.record_enabled, false) and 1) or 0)
    end
    if opts.stream_ids and type(opts.stream_ids) == "table" and #opts.stream_ids > 0 then
        local ids = {}
        for _, value in ipairs(opts.stream_ids) do
            local sid = dvr_trim(value)
            if sid ~= "" then
                ids[#ids + 1] = "'" .. dvr_sql_escape(sid) .. "'"
            end
        end
        if #ids > 0 then
            where[#where + 1] = "stream_id IN (" .. table.concat(ids, ", ") .. ")"
        end
    end
    local sql = "SELECT * FROM dvr_streams"
    if #where > 0 then
        sql = sql .. " WHERE " .. table.concat(where, " AND ")
    end
    sql = sql .. " ORDER BY stream_id ASC"
    local limit = math.floor(dvr_number(opts.limit, 1000, 1))
    if limit > 10000 then
        limit = 10000
    end
    sql = sql .. " LIMIT " .. tostring(limit) .. ";"
    local rows = dvr_db_query(sql) or {}
    local out = {}
    for _, row in ipairs(rows) do
        out[#out + 1] = dvr_normalize_stream_row(row)
    end
    return out
end

function dvr.upsert_stream(row)
    if type(row) ~= "table" then
        return nil, "invalid stream row"
    end
    local sid = dvr_trim(row.stream_id or row.id)
    if sid == "" then
        return nil, "stream_id is required"
    end
    local source_url = dvr_trim(row.source_url)
    if source_url == "" then
        return nil, "source_url is required"
    end
    local now = math.floor(tonumber(row.updated_ts) or os.time())
    local existing = dvr.get_stream(sid)
    local created_ts = existing and existing.created_ts or math.floor(tonumber(row.created_ts) or now)
    local retention_days = math.max(1, math.floor(tonumber(row.retention_days) or (existing and existing.retention_days) or 3))
    local record_enabled = dvr_bool(row.record_enabled, existing and existing.record_enabled or false) and 1 or 0
    local recording_paused = dvr_bool(row.recording_paused, existing and existing.recording_paused or false) and 1 or 0
    local last_state_seq = math.max(0, math.floor(tonumber(row.last_state_seq) or (existing and existing.last_state_seq) or 0))
    local last_mode = dvr_trim(row.last_mode or (existing and existing.last_mode) or "LIVE")
    if last_mode == "" then
        last_mode = "LIVE"
    end
    local last_reason = row.last_reason
    if last_reason ~= nil then
        last_reason = tostring(last_reason)
        if dvr_trim(last_reason) == "" then
            last_reason = nil
        end
    elseif existing then
        last_reason = existing.last_reason
    end
    local archive_path = nil
    if row.archive_path ~= nil then
        archive_path = dvr_normalize_archive_path(row.archive_path)
    elseif existing then
        archive_path = existing.archive_path
    end
    local config_json = nil
    if type(row.config) == "table" then
        local ok_cfg, encoded_cfg = pcall(dvr_json_encode, row.config)
        if ok_cfg and encoded_cfg and tostring(encoded_cfg) ~= "" then
            config_json = tostring(encoded_cfg)
        end
    elseif row.config_json ~= nil then
        local text = dvr_trim(row.config_json)
        if text ~= "" then
            config_json = text
        end
    elseif existing then
        config_json = existing.config_json
    end
    local name = tostring(row.name or (existing and existing.name) or sid)
    if existing then
        local ok, err = dvr_db_exec("UPDATE dvr_streams SET " ..
            "name='" .. dvr_sql_escape(name) .. "', " ..
            "source_url='" .. dvr_sql_escape(source_url) .. "', " ..
            "archive_path=" .. (archive_path and ("'" .. dvr_sql_escape(archive_path) .. "'") or "NULL") .. ", " ..
            "config_json=" .. (config_json and ("'" .. dvr_sql_escape(config_json) .. "'") or "NULL") .. ", " ..
            "record_enabled=" .. record_enabled .. ", " ..
            "retention_days=" .. retention_days .. ", " ..
            "segment_sec=3600, " ..
            "recording_paused=" .. recording_paused .. ", " ..
            "last_state_seq=" .. last_state_seq .. ", " ..
            "last_mode='" .. dvr_sql_escape(last_mode) .. "', " ..
            "last_reason=" .. (last_reason and ("'" .. dvr_sql_escape(last_reason) .. "'") or "NULL") .. ", " ..
            "updated_ts=" .. now .. " " ..
            "WHERE stream_id='" .. dvr_sql_escape(sid) .. "';")
        if not ok then
            return nil, err
        end
        return {
            ok = true,
            stream_id = sid,
            updated = true,
            created = false,
        }
    end
    local ok, err = dvr_db_exec("INSERT INTO dvr_streams(" ..
        "stream_id, name, source_url, archive_path, config_json, record_enabled, retention_days, segment_sec, recording_paused, last_state_seq, last_mode, last_reason, created_ts, updated_ts" ..
        ") VALUES(" ..
        "'" .. dvr_sql_escape(sid) .. "', " ..
        "'" .. dvr_sql_escape(name) .. "', " ..
        "'" .. dvr_sql_escape(source_url) .. "', " ..
        (archive_path and ("'" .. dvr_sql_escape(archive_path) .. "'") or "NULL") .. ", " ..
        (config_json and ("'" .. dvr_sql_escape(config_json) .. "'") or "NULL") .. ", " ..
        record_enabled .. ", " ..
        retention_days .. ", " ..
        "3600, " ..
        recording_paused .. ", " ..
        last_state_seq .. ", " ..
        "'" .. dvr_sql_escape(last_mode) .. "', " ..
        (last_reason and ("'" .. dvr_sql_escape(last_reason) .. "'") or "NULL") .. ", " ..
        created_ts .. ", " ..
        now .. ");")
    if not ok then
        return nil, err
    end
    return {
        ok = true,
        stream_id = sid,
        created = true,
        updated = false,
    }
end

function dvr.delete_stream(stream_id)
    local sid = dvr_trim(stream_id)
    if sid == "" then
        return nil, "stream_id is required"
    end
    local ok, err = dvr_db_exec("DELETE FROM dvr_streams WHERE stream_id='" .. dvr_sql_escape(sid) .. "';")
    if not ok then
        return nil, err
    end
    return true
end

function dvr.bulk_record(opts)
    opts = opts or {}
    local stream_ids = type(opts.stream_ids) == "table" and opts.stream_ids or {}
    if #stream_ids == 0 then
        return {
            ok = true,
            affected = 0,
            errors = {},
        }
    end
    local has_record_enabled = opts.record_enabled ~= nil
    local record_enabled = dvr_bool(opts.record_enabled, false)
    local retention_days = opts.retention_days ~= nil and math.max(1, math.floor(tonumber(opts.retention_days) or 3)) or nil
    local affected = 0
    local errors = {}
    local now = os.time()
    for _, value in ipairs(stream_ids) do
        local sid = dvr_trim(value)
        if sid ~= "" then
            local stream_row = dvr.get_stream(sid)
            if not stream_row then
                errors[#errors + 1] = {
                    stream_id = sid,
                    error = "stream not found",
                }
            else
                local next_record_enabled = has_record_enabled and (record_enabled and 1 or 0)
                    or (stream_row.record_enabled and 1 or 0)
                local next_retention = retention_days or stream_row.retention_days or 3
                local ok, err = dvr_db_exec("UPDATE dvr_streams SET " ..
                    "record_enabled=" .. next_record_enabled .. ", " ..
                    "retention_days=" .. math.max(1, math.floor(next_retention)) .. ", " ..
                    "updated_ts=" .. now .. " " ..
                    "WHERE stream_id='" .. dvr_sql_escape(sid) .. "';")
                if ok then
                    affected = affected + 1
                else
                    errors[#errors + 1] = {
                        stream_id = sid,
                        error = tostring(err or "update failed"),
                    }
                end
            end
        end
    end
    return {
        ok = (#errors == 0),
        affected = affected,
        errors = errors,
    }
end

local function dvr_valid_mode(mode)
    local normalized = dvr_trim(mode):upper()
    if normalized == "LIVE" then
        return "LIVE"
    end
    if normalized == "FAIL_CONFIRMED" then
        return "FAIL_CONFIRMED"
    end
    if normalized == "DVR_ACTIVE" then
        return "DVR_ACTIVE"
    end
    if normalized == "RECOVERING_TO_LIVE" then
        return "RECOVERING_TO_LIVE"
    end
    return nil
end

function dvr.apply_ingest_state(payload)
    if type(payload) ~= "table" then
        return nil, "invalid ingest payload"
    end
    local stream_id = dvr_trim(payload.stream_id)
    if stream_id == "" then
        return nil, "stream_id is required"
    end
    local mode = dvr_valid_mode(payload.mode)
    if not mode then
        return nil, "invalid mode"
    end
    local state_seq = math.floor(tonumber(payload.state_seq) or 0)
    if state_seq <= 0 then
        return nil, "state_seq is required"
    end
    local reason = payload.reason and tostring(payload.reason) or nil
    local now = math.floor(tonumber(payload.ts) or os.time())

    local stream_row = dvr.get_stream(stream_id)
    if not stream_row then
        local source_url = dvr_trim(payload.source_url)
        if source_url == "" then
            source_url = "http://127.0.0.1/play/" .. dvr_sanitize_id(stream_id)
        end
        local upsert_ok, upsert_err = dvr.upsert_stream({
            stream_id = stream_id,
            name = payload.name or stream_id,
            source_url = source_url,
            record_enabled = false,
            retention_days = 3,
            recording_paused = false,
            last_mode = "LIVE",
            last_state_seq = 0,
            updated_ts = now,
        })
        if not upsert_ok then
            return nil, upsert_err or "failed to bootstrap stream"
        end
        stream_row = dvr.get_stream(stream_id)
    end

    local prev_seq = stream_row and stream_row.last_state_seq or 0
    if state_seq <= prev_seq then
        local current = dvr.get_backup_state_for_api(stream_id)
        current.applied = false
        current.ignored_duplicate = true
        return current
    end

    local recording_paused = (mode == "DVR_ACTIVE")
    local state = dvr.get_backup_state(stream_id)
    local save_ok, save_err = dvr.save_backup_state(stream_id, {
        mode = mode,
        cycle_id = state and state.cycle_id or nil,
        cursor_seg_start_ts = state and state.cursor_seg_start_ts or 0,
        cursor_offset_sec = state and state.cursor_offset_sec or 0,
        recording_paused = recording_paused,
        last_state_seq = state_seq,
        last_reason = reason,
        updated_ts = now,
    })
    if not save_ok then
        return nil, save_err
    end

    local update_ok, update_err = dvr_db_exec("UPDATE dvr_streams SET " ..
        "recording_paused=" .. (recording_paused and 1 or 0) .. ", " ..
        "last_state_seq=" .. state_seq .. ", " ..
        "last_mode='" .. dvr_sql_escape(mode) .. "', " ..
        "last_reason=" .. (reason and ("'" .. dvr_sql_escape(reason) .. "'") or "NULL") .. ", " ..
        "updated_ts=" .. now .. " " ..
        "WHERE stream_id='" .. dvr_sql_escape(stream_id) .. "';")
    if not update_ok then
        return nil, update_err
    end

    dvr.add_event(stream_id, "DVR_INGEST_STATE", "INFO",
        "mode=" .. mode .. " seq=" .. tostring(state_seq), {
            mode = mode,
            state_seq = state_seq,
            reason = reason,
            recording_paused = recording_paused,
        })

    local current = dvr.get_backup_state_for_api(stream_id)
    current.applied = true
    current.ignored_duplicate = false
    return current
end

function dvr.rebuild_cycle_and_set_cursor(stream_id, opts)
    local sid = dvr_trim(stream_id)
    if sid == "" then
        return nil, "stream_id is required"
    end
    opts = type(opts) == "table" and opts or {}
    local rebuilt, err = dvr_rebuild_cycle_for_cursor(sid, {
        include_partial = opts.include_partial ~= false,
        min_partial_sec = opts.min_partial_sec,
        start_mode = opts.start_mode,
        start_offset_hours = opts.start_offset_hours,
        now_ts = opts.now_ts,
    })
    if not rebuilt then
        return nil, err
    end
    local state = dvr.get_backup_state(sid)
    local ok, save_err = dvr.save_backup_state(sid, {
        mode = state.mode or "LIVE",
        cycle_id = rebuilt.cycle_id or nil,
        cursor_seg_start_ts = tonumber(rebuilt.seg_start_ts) or 0,
        cursor_offset_sec = math.max(0, math.floor(tonumber(rebuilt.cursor_offset_sec) or 0)),
        recording_paused = state.recording_paused == true,
        last_state_seq = tonumber(state.last_state_seq) or 0,
        last_reason = "cycle_rebuild",
        updated_ts = os.time(),
    })
    if not ok then
        return nil, save_err
    end
    return dvr.get_backup_state_for_api(sid)
end

function dvr.upsert_remote_link(row)
    if type(row) ~= "table" then
        return nil, "invalid link row"
    end
    local stream_id = dvr_trim(row.stream_id)
    local dvr_server_id = dvr_trim(row.dvr_server_id)
    local dvr_stream_id = dvr_trim(row.dvr_stream_id or row.stream_id)
    local source_play_url = dvr_trim(row.source_play_url)
    if stream_id == "" or dvr_server_id == "" or dvr_stream_id == "" or source_play_url == "" then
        return nil, "stream_id/dvr_server_id/dvr_stream_id/source_play_url required"
    end
    local now = math.floor(tonumber(row.updated_ts) or os.time())
    local ok, err = dvr_db_exec("INSERT OR REPLACE INTO dvr_remote_links(" ..
        "stream_id, dvr_server_id, dvr_stream_id, source_play_url, updated_ts" ..
        ") VALUES(" ..
        "'" .. dvr_sql_escape(stream_id) .. "', " ..
        "'" .. dvr_sql_escape(dvr_server_id) .. "', " ..
        "'" .. dvr_sql_escape(dvr_stream_id) .. "', " ..
        "'" .. dvr_sql_escape(source_play_url) .. "', " ..
        now .. ");")
    if not ok then
        return nil, err
    end
    return true
end

function dvr.list_remote_links(dvr_server_id)
    local sid = dvr_trim(dvr_server_id)
    local where = ""
    if sid ~= "" then
        where = " WHERE dvr_server_id='" .. dvr_sql_escape(sid) .. "'"
    end
    local rows = dvr_db_query("SELECT * FROM dvr_remote_links" .. where .. " ORDER BY stream_id ASC;") or {}
    for _, row in ipairs(rows) do
        row.updated_ts = tonumber(row.updated_ts) or 0
    end
    return rows
end

local function dvr_count_query(sql)
    local rows = dvr_db_query(sql) or {}
    return tonumber(rows[1] and rows[1].total) or 0
end

function dvr.get_remote_link(stream_id, dvr_server_id)
    local stream = dvr_trim(stream_id)
    local server_id = dvr_trim(dvr_server_id)
    if stream == "" or server_id == "" then
        return nil
    end
    local rows = dvr_db_query("SELECT * FROM dvr_remote_links WHERE stream_id='" ..
        dvr_sql_escape(stream) .. "' AND dvr_server_id='" .. dvr_sql_escape(server_id) .. "' LIMIT 1;") or {}
    if #rows == 0 then
        return nil
    end
    rows[1].updated_ts = tonumber(rows[1].updated_ts) or 0
    return rows[1]
end

function dvr.get_remote_sync_health(dvr_server_id)
    local server_id = dvr_trim(dvr_server_id)
    local out = {
        dvr_server_id = server_id,
        links_count = 0,
        sync_rows = 0,
        outbox_total = 0,
        ready_count = 0,
        retrying_count = 0,
        max_retries = 0,
        oldest_age_sec = 0,
        next_retry_in_sec = 0,
        last_error = nil,
        last_error_ts = 0,
        last_error_retries = 0,
        ts = os.time(),
    }
    if server_id == "" then
        return out
    end

    local sid = dvr_sql_escape(server_id)
    local now = os.time()

    out.links_count = dvr_count_query("SELECT COUNT(*) AS total FROM dvr_remote_links " ..
        "WHERE dvr_server_id='" .. sid .. "';")
    out.sync_rows = dvr_count_query("SELECT COUNT(*) AS total FROM dvr_remote_sync_state " ..
        "WHERE dvr_server_id='" .. sid .. "';")
    out.outbox_total = dvr_count_query("SELECT COUNT(*) AS total FROM dvr_remote_outbox " ..
        "WHERE dvr_server_id='" .. sid .. "';")
    out.ready_count = dvr_count_query("SELECT COUNT(*) AS total FROM dvr_remote_outbox " ..
        "WHERE dvr_server_id='" .. sid .. "' AND next_retry_ts <= " .. now .. ";")
    out.retrying_count = dvr_count_query("SELECT COUNT(*) AS total FROM dvr_remote_outbox " ..
        "WHERE dvr_server_id='" .. sid .. "' AND retries > 0;")

    local max_rows = dvr_db_query("SELECT MAX(retries) AS max_retries FROM dvr_remote_outbox " ..
        "WHERE dvr_server_id='" .. sid .. "';") or {}
    out.max_retries = tonumber(max_rows[1] and max_rows[1].max_retries) or 0

    local oldest_rows = dvr_db_query("SELECT MIN(created_ts) AS oldest_ts FROM dvr_remote_outbox " ..
        "WHERE dvr_server_id='" .. sid .. "';") or {}
    local oldest_ts = tonumber(oldest_rows[1] and oldest_rows[1].oldest_ts) or 0
    if oldest_ts > 0 then
        out.oldest_age_sec = math.max(0, now - oldest_ts)
    end

    local next_rows = dvr_db_query("SELECT MIN(next_retry_ts) AS next_retry_ts FROM dvr_remote_outbox " ..
        "WHERE dvr_server_id='" .. sid .. "' AND next_retry_ts > " .. now .. ";") or {}
    local next_retry_ts = tonumber(next_rows[1] and next_rows[1].next_retry_ts) or 0
    if next_retry_ts > 0 then
        out.next_retry_in_sec = math.max(0, next_retry_ts - now)
    end

    local last_err_rows = dvr_db_query("SELECT last_error, updated_ts, retries FROM dvr_remote_outbox " ..
        "WHERE dvr_server_id='" .. sid .. "' AND last_error IS NOT NULL AND last_error<>'' " ..
        "ORDER BY updated_ts DESC, id DESC LIMIT 1;") or {}
    if #last_err_rows > 0 then
        out.last_error = tostring(last_err_rows[1].last_error or "")
        out.last_error_ts = tonumber(last_err_rows[1].updated_ts) or 0
        out.last_error_retries = tonumber(last_err_rows[1].retries) or 0
    end

    return out
end

function dvr.upsert_remote_sync_state(row)
    if type(row) ~= "table" then
        return nil, "invalid sync row"
    end
    local stream_id = dvr_trim(row.stream_id)
    local dvr_server_id = dvr_trim(row.dvr_server_id)
    if stream_id == "" or dvr_server_id == "" then
        return nil, "stream_id/dvr_server_id required"
    end
    local last_state_seq = math.max(0, math.floor(tonumber(row.last_state_seq) or 0))
    local last_mode = row.last_mode and tostring(row.last_mode) or nil
    local updated_ts = math.floor(tonumber(row.updated_ts) or os.time())
    local ok, err = dvr_db_exec("INSERT OR REPLACE INTO dvr_remote_sync_state(" ..
        "stream_id, dvr_server_id, last_state_seq, last_mode, updated_ts" ..
        ") VALUES(" ..
        "'" .. dvr_sql_escape(stream_id) .. "', " ..
        "'" .. dvr_sql_escape(dvr_server_id) .. "', " ..
        last_state_seq .. ", " ..
        (last_mode and ("'" .. dvr_sql_escape(last_mode) .. "'") or "NULL") .. ", " ..
        updated_ts .. ");")
    if not ok then
        return nil, err
    end
    return true
end

function dvr.get_remote_sync_state(stream_id, dvr_server_id)
    local stream = dvr_trim(stream_id)
    local server_id = dvr_trim(dvr_server_id)
    if stream == "" or server_id == "" then
        return {
            stream_id = stream,
            dvr_server_id = server_id,
            last_state_seq = 0,
            last_mode = nil,
            updated_ts = 0,
        }
    end
    local rows = dvr_db_query("SELECT * FROM dvr_remote_sync_state WHERE stream_id='" ..
        dvr_sql_escape(stream) .. "' AND dvr_server_id='" .. dvr_sql_escape(server_id) ..
        "' LIMIT 1;") or {}
    if #rows == 0 then
        return {
            stream_id = stream,
            dvr_server_id = server_id,
            last_state_seq = 0,
            last_mode = nil,
            updated_ts = 0,
        }
    end
    local row = rows[1]
    row.last_state_seq = tonumber(row.last_state_seq) or 0
    row.updated_ts = tonumber(row.updated_ts) or 0
    return row
end

local function dvr_outbox_max_rows()
    local raw = dvr_setting_alias({ "dvr_remote_outbox_max", "dvr.remote_outbox_max" }, 2000)
    local max_rows = math.floor(dvr_number(raw, 2000, 1))
    if max_rows > 50000 then
        max_rows = 50000
    end
    return max_rows
end

local function dvr_outbox_decode_payload(payload_json)
    if payload_json == nil or payload_json == "" then
        return nil
    end
    local ok, payload = pcall(dvr_json_decode, tostring(payload_json))
    if not ok or type(payload) ~= "table" then
        return nil
    end
    return payload
end

local function dvr_outbox_delete_ids(ids)
    if type(ids) ~= "table" or #ids == 0 then
        return true
    end
    local unique = {}
    local sql_ids = {}
    for _, value in ipairs(ids) do
        local id = math.floor(tonumber(value) or 0)
        if id > 0 and not unique[id] then
            unique[id] = true
            sql_ids[#sql_ids + 1] = tostring(id)
        end
    end
    if #sql_ids == 0 then
        return true
    end
    return dvr_db_exec("DELETE FROM dvr_remote_outbox WHERE id IN (" .. table.concat(sql_ids, ", ") .. ");")
end

local function dvr_outbox_prune_over_limit(max_rows)
    local max_allowed = math.floor(tonumber(max_rows) or 0)
    if max_allowed <= 0 then
        return
    end
    local rows = dvr_db_query("SELECT COUNT(*) AS total FROM dvr_remote_outbox;") or {}
    local total = tonumber(rows[1] and rows[1].total) or 0
    local excess = total - max_allowed
    if excess <= 0 then
        return
    end
    dvr_db_exec("DELETE FROM dvr_remote_outbox WHERE id IN (" ..
        "SELECT id FROM dvr_remote_outbox ORDER BY id ASC LIMIT " .. tostring(excess) ..
        ");")
end

function dvr.outbox_count()
    local rows = dvr_db_query("SELECT COUNT(*) AS total FROM dvr_remote_outbox;") or {}
    return tonumber(rows[1] and rows[1].total) or 0
end

function dvr.enqueue_remote_outbox(row)
    if type(row) ~= "table" then
        return nil, "invalid outbox row"
    end
    local stream_id = dvr_trim(row.stream_id)
    local dvr_server_id = dvr_trim(row.dvr_server_id)
    local event_type = dvr_trim(row.event_type)
    if stream_id == "" or dvr_server_id == "" or event_type == "" then
        return nil, "stream_id/dvr_server_id/event_type required"
    end
    local payload = row.payload
    if type(payload) ~= "table" then
        return nil, "payload table required"
    end
    local payload_json = dvr_json_encode(payload)
    if payload_json == nil or payload_json == "" then
        return nil, "payload encode failed"
    end
    local now = math.floor(tonumber(row.created_ts) or os.time())
    local next_retry_ts = math.floor(tonumber(row.next_retry_ts) or now)

    local existing_rows = dvr_db_query("SELECT id, payload_json FROM dvr_remote_outbox WHERE " ..
        "stream_id='" .. dvr_sql_escape(stream_id) .. "' AND " ..
        "dvr_server_id='" .. dvr_sql_escape(dvr_server_id) .. "' AND " ..
        "event_type='" .. dvr_sql_escape(event_type) .. "' " ..
        "ORDER BY id DESC LIMIT 64;") or {}

    local duplicate_id = nil
    local obsolete_ids = {}
    if event_type == "ingest_state" then
        local new_seq = math.floor(tonumber(payload.state_seq) or 0)
        local new_mode = dvr_trim(payload.mode)
        local new_reason = dvr_trim(payload.reason)
        for _, ex in ipairs(existing_rows) do
            local ex_id = math.floor(tonumber(ex.id) or 0)
            local ex_payload = dvr_outbox_decode_payload(ex.payload_json)
            local ex_seq = math.floor(tonumber(ex_payload and ex_payload.state_seq) or 0)
            local ex_mode = dvr_trim(ex_payload and ex_payload.mode)
            local ex_reason = dvr_trim(ex_payload and ex_payload.reason)
            if new_seq > 0 and ex_seq > 0 then
                if ex_seq > new_seq then
                    duplicate_id = ex_id
                    break
                end
                if ex_seq == new_seq and ex_mode == new_mode and ex_reason == new_reason then
                    duplicate_id = ex_id
                    break
                end
                if ex_seq <= new_seq then
                    obsolete_ids[#obsolete_ids + 1] = ex_id
                end
            else
                if tostring(ex.payload_json or "") == payload_json then
                    duplicate_id = ex_id
                    break
                end
            end
        end
    else
        for _, ex in ipairs(existing_rows) do
            if tostring(ex.payload_json or "") == payload_json then
                duplicate_id = math.floor(tonumber(ex.id) or 0)
                break
            end
        end
    end

    if duplicate_id and duplicate_id > 0 then
        return {
            id = duplicate_id,
            stream_id = stream_id,
            dvr_server_id = dvr_server_id,
            event_type = event_type,
            payload = payload,
            duplicate = true,
        }
    end

    if #obsolete_ids > 0 then
        dvr_outbox_delete_ids(obsolete_ids)
    end

    local ok, err = dvr_db_exec("INSERT INTO dvr_remote_outbox(" ..
        "stream_id, dvr_server_id, event_type, payload_json, retries, next_retry_ts, last_error, created_ts, updated_ts" ..
        ") VALUES(" ..
        "'" .. dvr_sql_escape(stream_id) .. "', " ..
        "'" .. dvr_sql_escape(dvr_server_id) .. "', " ..
        "'" .. dvr_sql_escape(event_type) .. "', " ..
        "'" .. dvr_sql_escape(payload_json) .. "', " ..
        "0, " .. next_retry_ts .. ", NULL, " .. now .. ", " .. now .. ");")
    if not ok then
        return nil, err
    end
    dvr_outbox_prune_over_limit(dvr_outbox_max_rows())
    local rows = dvr_db_query("SELECT id FROM dvr_remote_outbox ORDER BY id DESC LIMIT 1;") or {}
    local out_id = (#rows > 0) and (tonumber(rows[1].id) or 0) or 0
    return {
        id = out_id,
        stream_id = stream_id,
        dvr_server_id = dvr_server_id,
        event_type = event_type,
        payload = payload,
    }
end

function dvr.list_outbox_ready(limit)
    local row_limit = math.floor(dvr_number(limit, 50, 1))
    if row_limit > 500 then
        row_limit = 500
    end
    local now = os.time()
    local rows = dvr_db_query("SELECT * FROM dvr_remote_outbox " ..
        "WHERE next_retry_ts <= " .. now .. " ORDER BY id ASC LIMIT " .. row_limit .. ";") or {}
    for _, row in ipairs(rows) do
        row.id = tonumber(row.id) or 0
        row.retries = tonumber(row.retries) or 0
        row.next_retry_ts = tonumber(row.next_retry_ts) or 0
        row.created_ts = tonumber(row.created_ts) or 0
        row.updated_ts = tonumber(row.updated_ts) or 0
        local ok, payload = pcall(dvr_json_decode, tostring(row.payload_json or ""))
        if ok and type(payload) == "table" then
            row.payload = payload
        else
            row.payload = nil
        end
    end
    return rows
end

function dvr.outbox_mark_sent(id)
    local out_id = tonumber(id)
    if not out_id or out_id <= 0 then
        return nil, "id is required"
    end
    return dvr_db_exec("DELETE FROM dvr_remote_outbox WHERE id=" .. math.floor(out_id) .. ";")
end

function dvr.outbox_mark_retry(id, err_text, retry_delay_sec)
    local out_id = tonumber(id)
    if not out_id or out_id <= 0 then
        return nil, "id is required"
    end
    local rows = dvr_db_query("SELECT retries FROM dvr_remote_outbox WHERE id=" ..
        math.floor(out_id) .. " LIMIT 1;") or {}
    if #rows == 0 then
        return nil, "outbox item not found"
    end
    local retries = (tonumber(rows[1].retries) or 0) + 1
    local delay = math.floor(tonumber(retry_delay_sec) or 5)
    if delay < 1 then
        delay = 1
    end
    if delay > 3600 then
        delay = 3600
    end
    local next_retry_ts = os.time() + delay
    local now = os.time()
    return dvr_db_exec("UPDATE dvr_remote_outbox SET " ..
        "retries=" .. retries .. ", " ..
        "next_retry_ts=" .. next_retry_ts .. ", " ..
        "last_error='" .. dvr_sql_escape(err_text or "") .. "', " ..
        "updated_ts=" .. now .. " " ..
        "WHERE id=" .. math.floor(out_id) .. ";")
end

local dvr_local_writer_state = dvr_local_writer_state or {
    timer = nil,
    streams = {},
    remote_streams = {},
    remote_runtime = {},
    fault_since = {},
    fault_checks = {},
    recover_since = {},
    recover_checks = {},
    last_switch_ts = {},
    storage_blocked = {},
    stream_touch = {},
    remote_open_fail_ts = {},
    remote_open_retry_until = {},
}

local function dvr_copy_table(value)
    if type(value) ~= "table" then
        return value
    end
    local out = {}
    for k, v in pairs(value) do
        out[k] = v
    end
    return out
end

local function dvr_set_remote_runtime_status(stream_id, status)
    local sid = dvr_trim(stream_id)
    if sid == "" then
        return
    end
    if type(status) ~= "table" then
        dvr_local_writer_state.remote_runtime[sid] = nil
        return
    end
    local now = os.time()
    local payload = {
        on_air = status.on_air == true,
        bitrate = tonumber(status.bitrate) or tonumber(status.bitrate_kbps) or 0,
        bitrate_kbps = tonumber(status.bitrate_kbps) or tonumber(status.bitrate) or 0,
        raw_bitrate_kbps = tonumber(status.raw_bitrate_kbps) or tonumber(status.bitrate_kbps) or tonumber(status.bitrate) or 0,
        cc_errors = tonumber(status.cc_errors) or 0,
        pes_errors = tonumber(status.pes_errors) or 0,
        active_input_id = tonumber(status.active_input_id) or 1,
        active_input_index = tonumber(status.active_input_index) or 0,
        active_input_url = status.active_input_url and tostring(status.active_input_url) or nil,
        uptime_sec = tonumber(status.uptime_sec) or 0,
        last_error = status.last_error and tostring(status.last_error) or nil,
        updated_at = tonumber(status.updated_at) or now,
    }
    dvr_local_writer_state.remote_runtime[sid] = payload
end

function dvr.get_runtime_status(stream_id)
    local sid = dvr_trim(stream_id)
    if sid == "" then
        return nil
    end
    return dvr_copy_table(dvr_local_writer_state.remote_runtime[sid])
end

function dvr.list_runtime_status(stream_ids)
    local out = {}
    if type(stream_ids) == "table" and #stream_ids > 0 then
        for _, value in ipairs(stream_ids) do
            local sid = dvr_trim(value)
            if sid ~= "" then
                local row = dvr_local_writer_state.remote_runtime[sid]
                if type(row) == "table" then
                    out[sid] = dvr_copy_table(row)
                end
            end
        end
        return out
    end
    for sid, row in pairs(dvr_local_writer_state.remote_runtime) do
        if type(row) == "table" then
            out[sid] = dvr_copy_table(row)
        end
    end
    return out
end

local function dvr_local_play_url(stream_id)
    local raw_port = dvr_setting_alias({ "http_play_port", "http_port" }, 8000)
    local port = tonumber(raw_port) or 8000
    if port < 1 or port > 65535 then
        port = 8000
    end
    return "http://127.0.0.1:" .. tostring(port) .. "/play/" .. tostring(stream_id) .. "?internal=1"
end

local function dvr_with_internal_loopback_flag(raw_url)
    local text = dvr_trim(raw_url)
    if text == "" then
        return text
    end
    if text:find("internal=", 1, true) ~= nil then
        return text
    end
    local parsed = parse_url(text)
    if not parsed then
        return text
    end
    local host = dvr_trim(parsed.host):lower()
    local is_loopback = host == "localhost"
        or host == "127.0.0.1"
        or host == "::1"
        or host:match("^127%.")
    if not is_loopback then
        return text
    end
    local path = dvr_trim(parsed.path)
    if path:find("^/play/") ~= 1
        and path:find("^/dvr/play/") ~= 1
        and path:find("^/dvr/internal/play/") ~= 1
    then
        return text
    end
    local sep = text:find("%?", 1, true) and "&" or "?"
    return text .. sep .. "internal=1"
end

function dvr.is_local_backup_input_url(raw)
    local text = tostring(raw or "")
    if text == "" then
        return false
    end
    text = text:lower()
    if text:find("/dvr/internal/play/", 1, true) ~= nil then
        return true
    end
    return text:find("/dvr/play/", 1, true) ~= nil
end

local function dvr_read_stream_cfg(stream_id, entry)
    if entry and entry.channel and type(entry.channel.config) == "table" then
        return entry.channel.config
    end
    if config and config.get_stream then
        local row = config.get_stream(stream_id)
        if row and type(row.config) == "table" then
            return row.config
        end
    end
    return nil
end

local function dvr_update_stream_runtime_row(stream_id, stream_cfg, settings, paused, mode, reason)
    local sid = dvr_trim(stream_id)
    if sid == "" then
        return
    end
    local now = os.time()
    local touch = dvr_local_writer_state.stream_touch[sid]
    local existing = dvr.get_stream(sid)
    local next_record_enabled = (settings.archive_enabled == true)
    local next_paused = (paused == true)
    local next_mode = tostring(mode or (existing and existing.last_mode) or "LIVE")
    local next_reason = reason and tostring(reason) or nil
    local same_state = false
    if existing then
        same_state =
            (existing.record_enabled == next_record_enabled)
            and (existing.recording_paused == next_paused)
            and (tostring(existing.last_mode or "LIVE") == next_mode)
            and (tostring(existing.last_reason or "") == tostring(next_reason or ""))
    end
    if touch and (now - touch) < 15 and same_state then
        return
    end
    dvr_local_writer_state.stream_touch[sid] = now
    local last_state_seq = existing and tonumber(existing.last_state_seq) or 0
    dvr.upsert_stream({
        stream_id = sid,
        name = (stream_cfg and stream_cfg.name) or sid,
        source_url = dvr_local_play_url(sid),
        archive_path = settings and settings.archive_path or nil,
        record_enabled = next_record_enabled,
        retention_days = settings.retention_days,
        recording_paused = next_paused,
        last_mode = next_mode,
        last_reason = next_reason or (existing and existing.last_reason) or nil,
        last_state_seq = last_state_seq or 0,
    })
end

local function dvr_update_local_state(stream_id, stream_cfg, settings, mode, paused, reason)
    local sid = dvr_trim(stream_id)
    if sid == "" then
        return
    end
    local state = dvr.get_backup_state(sid)
    local prev_mode = tostring(state.mode or "LIVE")
    local normalized_mode = tostring(mode or "LIVE")
    local normalized_paused = paused == true
    local normalized_reason = reason and tostring(reason) or nil

    dvr_update_stream_runtime_row(sid, stream_cfg, settings, normalized_paused, normalized_mode, normalized_reason)

    if tostring(state.mode or "LIVE") == normalized_mode
        and (state.recording_paused == true) == normalized_paused
        and tostring(state.last_reason or "") == tostring(normalized_reason or "")
    then
        return
    end

    if prev_mode ~= normalized_mode then
        dvr_local_writer_state.last_switch_ts[sid] = os.time()
        dvr_local_writer_state.fault_checks[sid] = 0
        dvr_local_writer_state.recover_checks[sid] = 0
    end

    dvr.save_backup_state(sid, {
        mode = normalized_mode,
        cycle_id = state.cycle_id,
        cursor_seg_start_ts = state.cursor_seg_start_ts,
        cursor_offset_sec = state.cursor_offset_sec,
        recording_paused = normalized_paused,
        last_state_seq = tonumber(state.last_state_seq) or 0,
        last_reason = normalized_reason,
        updated_ts = os.time(),
    })

    dvr.add_event(sid, "DVR_LOCAL_STATE", "INFO",
        "mode=" .. tostring(normalized_mode) .. " paused=" .. tostring(normalized_paused), {
            mode = normalized_mode,
            recording_paused = normalized_paused,
            reason = normalized_reason,
        })
end

local function dvr_writer_stat_size(path)
    if not path or path == "" then
        return 0
    end
    if not (utils and type(utils.stat) == "function") then
        return 0
    end
    local st = utils.stat(path)
    if not st or st.error then
        return 0
    end
    return tonumber(st.size) or 0
end

function dvr.read_lock_bytes(path)
    local lock_path = tostring(path or "")
    if lock_path == "" then
        return 0
    end
    local fp = io.open(lock_path, "rb")
    if not fp then
        return 0
    end
    local raw = fp:read("*a")
    fp:close()
    local value = tonumber(tostring(raw or ""):match("([0-9]+)")) or 0
    if value < 0 then
        value = 0
    end
    return math.floor(value)
end

function dvr.estimate_segment_played_sec(segment, lock_bytes, fallback_elapsed_sec)
    local duration = dvr.segment_duration(segment)
    local fallback = math.floor(tonumber(fallback_elapsed_sec) or 0)
    if fallback < 0 then
        fallback = 0
    end
    if duration <= 0 then
        return fallback
    end
    if fallback > duration then
        fallback = duration
    end

    local size = math.floor(tonumber(segment and segment.size_bytes) or 0)
    if size <= 0 and segment and segment.path then
        size = dvr_writer_stat_size(segment.path)
    end
    local bytes = math.floor(tonumber(lock_bytes) or 0)
    if bytes < 0 then
        bytes = 0
    end

    if size <= 0 or bytes <= 0 then
        return fallback
    end
    if bytes > size then
        bytes = size
    end

    local played = math.floor((bytes / size) * duration)
    if played < 0 then
        played = 0
    elseif played > duration then
        played = duration
    end
    return played
end

local function dvr_writer_upsert_open_segment(writer, now)
    local seg_end = now or os.time()
    local size = dvr_writer_stat_size(writer.part_path)
    dvr.upsert_segment({
        stream_id = writer.stream_id,
        seg_start_ts = writer.seg_start_ts,
        seg_end_ts = seg_end,
        path = writer.part_path,
        size_bytes = size,
        is_complete = false,
        created_ts = writer.created_ts,
        updated_ts = seg_end,
    })
end

local function dvr_writer_finalize(writer, reason)
    if type(writer) ~= "table" then
        return
    end
    local now = os.time()
    writer.output = nil
    if writer.input then
        pcall(function()
            kill_input(writer.input)
        end)
        writer.input = nil
    end

    local final_path = writer.part_path
    if writer.part_path and writer.part_path ~= "" then
        local st = utils and utils.stat and utils.stat(writer.part_path) or nil
        if st and not st.error and st.type == "file" and writer.final_path and writer.final_path ~= "" then
            pcall(os.rename, writer.part_path, writer.final_path)
            local st_final = utils and utils.stat and utils.stat(writer.final_path) or nil
            if st_final and not st_final.error and st_final.type == "file" then
                final_path = writer.final_path
            end
        end
    end

    local elapsed = now - (tonumber(writer.seg_start_ts) or now)
    if elapsed < 0 then
        elapsed = 0
    end
    local complete = elapsed >= (3600 - (tonumber(writer.segment_guard_sec) or 3))
    local is_gap = (reason == "paused" or reason == "offline" or reason == "storage_guard")
    if is_gap or reason == "disabled" then
        complete = false
    end
    local size = dvr_writer_stat_size(final_path)
    if size <= 0 then
        if final_path and final_path ~= "" then
            pcall(os.remove, final_path)
        end
        if writer.part_path and writer.part_path ~= "" and writer.part_path ~= final_path then
            pcall(os.remove, writer.part_path)
        end
        dvr.delete_segment(writer.stream_id, writer.seg_start_ts)
        dvr.add_event(writer.stream_id, "DVR_RECORD_EMPTY", "WARN",
            "segment=" .. tostring(writer.seg_start_ts), {
                segment = writer.seg_start_ts,
                reason = reason and tostring(reason) or nil,
            })
        dvr.cleanup_segments(writer.stream_id, writer.retention_days, nil)
        return
    end
    dvr.upsert_segment({
        stream_id = writer.stream_id,
        seg_start_ts = writer.seg_start_ts,
        seg_end_ts = now,
        path = final_path,
        size_bytes = size,
        is_complete = complete,
        created_ts = writer.created_ts,
        updated_ts = now,
    })
    if is_gap then
        dvr.add_event(writer.stream_id, "DVR_RECORD_GAP", "WARN",
            "recording paused with incomplete segment", {
                seg_start_ts = writer.seg_start_ts,
                seg_end_ts = now,
                duration_sec = elapsed,
                path = final_path,
                reason = reason,
                incomplete = true,
            })
    end
    dvr.cleanup_segments(writer.stream_id, writer.retention_days, nil)
end

local function dvr_writer_open_from_upstream(stream_id, upstream, settings, now)
    if type(upstream) ~= "userdata" and type(upstream) ~= "table" then
        return nil, "upstream unavailable"
    end
    local seg_start_ts = dvr.segment_start(now, 3600)
    local paths = dvr.segment_paths(stream_id, seg_start_ts, {
        archive_path = settings and settings.archive_path or nil,
    })
    local out = file_output({
        upstream = upstream,
        filename = paths.part_path,
    })
    if not out then
        return nil, "file_output init failed"
    end
    local writer = {
        stream_id = stream_id,
        seg_start_ts = seg_start_ts,
        part_path = paths.part_path,
        final_path = paths.final_path,
        created_ts = now,
        retention_days = settings.retention_days,
        segment_guard_sec = settings.segment_guard_sec,
        writer_flush_sec = settings.writer_flush_sec,
        output = out,
        last_flush_ts = 0,
        last_cleanup_ts = 0,
    }
    dvr_writer_upsert_open_segment(writer, now)
    return writer
end

local function dvr_writer_open(stream_id, channel_data, settings, now)
    if not channel_data or not channel_data.tail or type(channel_data.tail.stream) ~= "function" then
        return nil, "channel tail unavailable"
    end
    return dvr_writer_open_from_upstream(stream_id, channel_data.tail:stream(), settings, now)
end

local function dvr_writer_open_remote(stream_row, settings, now)
    local sid = dvr_trim(stream_row and stream_row.stream_id)
    local source_url = dvr_with_internal_loopback_flag(stream_row and stream_row.source_url)
    if sid == "" then
        return nil, "stream_id is required"
    end
    if source_url == "" then
        return nil, "source_url is required"
    end
    local input_conf = parse_url(source_url)
    if not input_conf then
        return nil, "source_url parse failed"
    end
    input_conf.name = "[dvr-record " .. sid .. "]"
    local input = init_input(input_conf)
    if not input or not input.tail then
        return nil, "source input init failed"
    end
    local writer, open_err = dvr_writer_open_from_upstream(sid, input.tail:stream(), settings, now)
    if not writer then
        pcall(function()
            kill_input(input)
        end)
        return nil, open_err or "writer open failed"
    end
    writer.input = input
    writer.source_url = source_url
    return writer
end

local function dvr_storage_usage_bytes(stream_id)
    local sid = dvr_trim(stream_id)
    if sid == "" then
        return 0
    end
    local rows = dvr_db_query("SELECT SUM(size_bytes) AS total FROM dvr_segments WHERE stream_id='" ..
        dvr_sql_escape(sid) .. "';") or {}
    local total = tonumber(rows[1] and rows[1].total) or 0
    if total < 0 then
        total = 0
    end
    return math.floor(total)
end

local function dvr_cleanup_oldest_segment(stream_id, keep_seg_start_ts)
    local sid = dvr_trim(stream_id)
    if sid == "" then
        return false
    end
    local where = "stream_id='" .. dvr_sql_escape(sid) .. "'"
    if tonumber(keep_seg_start_ts) then
        where = where .. " AND seg_start_ts<>" .. math.floor(tonumber(keep_seg_start_ts))
    end
    local rows = dvr_db_query("SELECT id, path FROM dvr_segments WHERE " .. where ..
        " ORDER BY seg_start_ts ASC LIMIT 1;") or {}
    if #rows == 0 then
        return false
    end
    local row = rows[1]
    if row.path and row.path ~= "" then
        pcall(os.remove, tostring(row.path))
    end
    local id = tonumber(row.id) or 0
    if id <= 0 then
        return false
    end
    local ok = dvr_db_exec("DELETE FROM dvr_segments WHERE id=" .. id .. ";")
    return ok == true
end

local function dvr_storage_guard(stream_id, settings, keep_seg_start_ts)
    if type(settings) ~= "table" then
        return false, nil
    end
    local min_free_bytes = math.floor(math.max(0, tonumber(settings.min_free_gb) or 0) * 1024 * 1024 * 1024)
    local max_usage_bytes = math.floor(math.max(0, tonumber(settings.max_storage_gb) or 0) * 1024 * 1024 * 1024)
    local high_pct = math.max(0, math.floor(tonumber(settings.high_watermark_pct) or 0))
    local low_pct = math.max(0, math.floor(tonumber(settings.low_watermark_pct) or 0))
    if low_pct <= 0 or low_pct > high_pct then
        low_pct = math.max(1, high_pct - 5)
    end
    local archive_root = dvr_normalize_archive_path(settings.archive_path)
    if not archive_root then
        local data_dir = (config and config.data_dir) or "./data"
        archive_root = dvr_join_path(data_dir, "dvr")
    end

    local function need_cleanup()
        local st = dvr_statvfs(archive_root)
        local usage = dvr_storage_usage_bytes(stream_id)
        local reason = nil
        if max_usage_bytes > 0 and usage >= max_usage_bytes then
            reason = "max_storage"
        end
        if not reason and min_free_bytes > 0 and st and st.avail_bytes < min_free_bytes then
            reason = "min_free"
        end
        if not reason and high_pct > 0 and st and st.used_percent and st.used_percent >= high_pct then
            reason = "high_watermark"
        end
        return reason, st, usage
    end

    local reason, st, usage = need_cleanup()
    if not reason then
        return false, {
            reason = nil,
            free_bytes = st and st.avail_bytes or 0,
            total_bytes = st and st.total_bytes or 0,
            used_percent = st and st.used_percent or 0,
            usage_bytes = usage or 0,
        }
    end

    local deleted = 0
    for _ = 1, 256 do
        local removed = dvr_cleanup_oldest_segment(stream_id, keep_seg_start_ts)
        if not removed then
            break
        end
        deleted = deleted + 1
        reason, st, usage = need_cleanup()
        if not reason then
            break
        end
        if st and st.used_percent and high_pct > 0 and st.used_percent <= low_pct then
            break
        end
    end
    reason, st, usage = need_cleanup()
    return reason ~= nil, {
        reason = reason,
        deleted = deleted,
        free_bytes = st and st.avail_bytes or 0,
        total_bytes = st and st.total_bytes or 0,
        used_percent = st and st.used_percent or 0,
        usage_bytes = usage or 0,
    }
end

local function dvr_writer_flush_and_cleanup(writer, now, settings)
    local flush_sec = math.max(1, tonumber(writer.writer_flush_sec) or 5)
    if (now - (tonumber(writer.last_flush_ts) or 0)) >= flush_sec then
        writer.last_flush_ts = now
        dvr_writer_upsert_open_segment(writer, now)
    end

    if (now - (tonumber(writer.last_cleanup_ts) or 0)) >= 60 then
        writer.last_cleanup_ts = now
        dvr.cleanup_segments(writer.stream_id, writer.retention_days, writer.seg_start_ts)
        local blocked, storage = dvr_storage_guard(writer.stream_id, settings, writer.seg_start_ts)
        if blocked then
            dvr.add_event(writer.stream_id, "DVR_STORAGE_GUARD", "ERROR",
                "storage pressure, recording paused", storage or {})
            return nil, "storage_guard"
        end
    end
    return true
end

local function dvr_remote_writer_update_status(sid, writer, source_url, settings, now, forced_error)
    if type(writer) ~= "table" then
        dvr_set_remote_runtime_status(sid, {
            on_air = false,
            bitrate_kbps = 0,
            raw_bitrate_kbps = 0,
            cc_errors = 0,
            pes_errors = 0,
            active_input_id = 1,
            active_input_index = 0,
            active_input_url = source_url,
            uptime_sec = 0,
            last_error = forced_error or "writer_inactive",
            updated_at = now,
        })
        return
    end

    local size = dvr_writer_stat_size(writer.part_path)
    if size <= 0 and writer.final_path and writer.final_path ~= writer.part_path then
        size = dvr_writer_stat_size(writer.final_path)
    end

    local prev_size = tonumber(writer.last_stat_size)
    if not prev_size or prev_size < 0 then
        prev_size = size
    end
    local prev_ts = tonumber(writer.last_stat_ts)
    if not prev_ts or prev_ts <= 0 then
        prev_ts = now
    end
    local delta_sec = now - prev_ts
    local delta_size = size - prev_size

    local bitrate_kbps = tonumber(writer.last_bitrate_kbps) or 0
    local progressed = false
    if delta_sec > 0 and delta_size > 0 then
        progressed = true
        bitrate_kbps = math.floor(((delta_size * 8) / delta_sec) / 1000 + 0.5)
        if bitrate_kbps < 0 then
            bitrate_kbps = 0
        end
        writer.last_data_ts = now
        if not writer.data_since then
            writer.data_since = now
        end
    end

    writer.last_stat_size = size
    writer.last_stat_ts = now
    writer.last_bitrate_kbps = bitrate_kbps

    local stale_sec = math.max(3, math.floor((tonumber(settings and settings.writer_flush_sec) or 5) * 3))
    local on_air = writer.last_data_ts ~= nil and (now - tonumber(writer.last_data_ts)) <= stale_sec
    local uptime_sec = 0
    if on_air and writer.data_since then
        uptime_sec = math.max(0, now - tonumber(writer.data_since))
    end

    local last_error = nil
    if forced_error and forced_error ~= "" then
        last_error = tostring(forced_error)
        on_air = false
        uptime_sec = 0
    elseif not on_air then
        last_error = "no_data"
        if progressed then
            last_error = nil
        end
    end

    dvr_set_remote_runtime_status(sid, {
        on_air = on_air,
        bitrate_kbps = bitrate_kbps,
        raw_bitrate_kbps = bitrate_kbps,
        cc_errors = 0,
        pes_errors = 0,
        active_input_id = 1,
        active_input_index = 0,
        active_input_url = source_url,
        uptime_sec = uptime_sec,
        last_error = last_error,
        updated_at = now,
    })
end

local function dvr_remote_open_retry_delay(err_text)
    local text = dvr_trim(err_text):lower()
    if text:find("401", 1, true) ~= nil or text:find("unauthorized", 1, true) ~= nil then
        return 60
    end
    if text:find("404", 1, true) ~= nil or text:find("not found", 1, true) ~= nil then
        return 60
    end
    if text:find("timeout", 1, true) ~= nil or text:find("timed out", 1, true) ~= nil then
        return 15
    end
    if text:find("connection refused", 1, true) ~= nil or text:find("connection reset", 1, true) ~= nil then
        return 15
    end
    return 5
end

local function dvr_remote_writer_tick(stream_row, default_settings)
    local sid = dvr_trim(stream_row and stream_row.stream_id)
    if sid == "" then
        return
    end

    local should_record = stream_row.record_enabled == true and stream_row.recording_paused ~= true
    local writer = dvr_local_writer_state.remote_streams[sid]
    if not should_record then
        if writer then
            dvr_writer_finalize(writer, stream_row.recording_paused and "paused" or "disabled")
            dvr_local_writer_state.remote_streams[sid] = nil
        end
        dvr_local_writer_state.remote_open_retry_until[sid] = nil
        dvr_remote_writer_update_status(sid, nil, dvr_trim(stream_row and stream_row.source_url), default_settings, os.time(),
            stream_row.recording_paused == true and "paused" or "disabled")
        return
    end

    local now = os.time()
    local settings = {
        retention_days = math.max(1, math.floor(tonumber(stream_row.retention_days) or tonumber(default_settings.retention_days) or 3)),
        segment_guard_sec = math.max(0, math.floor(tonumber(default_settings.segment_guard_sec) or 3)),
        writer_flush_sec = math.max(1, math.floor(tonumber(default_settings.writer_flush_sec) or 5)),
        archive_path = dvr_normalize_archive_path(stream_row.archive_path)
            or dvr_normalize_archive_path(default_settings.archive_path),
    }

    local source_url = dvr_with_internal_loopback_flag(stream_row.source_url)
    if writer and dvr_trim(writer.source_url) ~= source_url then
        dvr_writer_finalize(writer, "source_changed")
        dvr_local_writer_state.remote_streams[sid] = nil
        writer = nil
        dvr_local_writer_state.remote_open_retry_until[sid] = nil
        dvr_remote_writer_update_status(sid, nil, source_url, settings, now, "source_changed")
    end

    local seg_start_ts = dvr.segment_start(now, 3600)
    if writer and tonumber(writer.seg_start_ts) ~= seg_start_ts then
        dvr_writer_finalize(writer, "rotate")
        dvr_local_writer_state.remote_streams[sid] = nil
        writer = nil
    end

    if not writer then
        local retry_until = tonumber(dvr_local_writer_state.remote_open_retry_until[sid]) or 0
        if retry_until > now then
            dvr_remote_writer_update_status(sid, nil, source_url, settings, now, "open_backoff")
            return
        end
        local new_writer, open_err = dvr_writer_open_remote(stream_row, settings, now)
        if not new_writer then
            local prev_fail_ts = tonumber(dvr_local_writer_state.remote_open_fail_ts[sid]) or 0
            if (now - prev_fail_ts) >= 30 then
                dvr_local_writer_state.remote_open_fail_ts[sid] = now
                dvr.add_event(sid, "DVR_REMOTE_RECORD_OPEN_FAIL", "ERROR", tostring(open_err or "open failed"), {
                    source_url = source_url,
                })
            end
            dvr_local_writer_state.remote_open_retry_until[sid] = now + dvr_remote_open_retry_delay(open_err)
            dvr_remote_writer_update_status(sid, nil, source_url, settings, now, tostring(open_err or "open_failed"))
            return
        end
        dvr_local_writer_state.remote_open_fail_ts[sid] = nil
        dvr_local_writer_state.remote_open_retry_until[sid] = nil
        writer = new_writer
        writer.last_stat_ts = now
        writer.last_stat_size = dvr_writer_stat_size(writer.part_path)
        writer.last_bitrate_kbps = 0
        writer.data_since = nil
        writer.last_data_ts = nil
        dvr_local_writer_state.remote_streams[sid] = writer
        dvr.add_event(sid, "DVR_REMOTE_RECORD_OPEN", "INFO",
            "segment=" .. tostring(writer.seg_start_ts), {
                segment = writer.seg_start_ts,
                path = writer.part_path,
                source_url = source_url,
            })
    end

    local flush_ok, flush_err = dvr_writer_flush_and_cleanup(writer, now, settings)
    if not flush_ok then
        dvr_writer_finalize(writer, flush_err or "storage_guard")
        dvr_local_writer_state.remote_streams[sid] = nil
        dvr_remote_writer_update_status(sid, nil, source_url, settings, now, flush_err or "storage_guard")
        return
    end
    dvr_remote_writer_update_status(sid, writer, source_url, settings, now, nil)
end

local function dvr_local_collect_status(ids)
    if not runtime then
        return {}
    end
    if runtime.list_status_lite_ids and type(runtime.list_status_lite_ids) == "function" then
        local ok, rows = pcall(runtime.list_status_lite_ids, ids)
        if ok and type(rows) == "table" then
            return rows
        end
    end
    return {}
end

local function dvr_local_is_no_data_error(text)
    local value = dvr_trim(text)
    if value == "" then
        return false
    end
    value = value:lower()
    return value:find("no data", 1, true) ~= nil
        or value:find("inactive", 1, true) ~= nil
        or value:find("offline", 1, true) ~= nil
        or value:find("http_404", 1, true) ~= nil
end

local function dvr_local_active_input_status(status)
    if type(status) ~= "table" then
        return nil
    end
    local input_rows = type(status.inputs_status) == "table" and status.inputs_status
        or (type(status.inputs) == "table" and status.inputs or nil)
    if type(input_rows) ~= "table" then
        return nil
    end

    local active_input_id = tonumber(status.active_input_id) or 0
    if active_input_id > 0 and type(input_rows[active_input_id]) == "table" then
        return input_rows[active_input_id]
    end

    local active_input_index = tonumber(status.active_input_index)
    if active_input_index and active_input_index >= 0 then
        local row = input_rows[active_input_index + 1]
        if type(row) == "table" then
            return row
        end
    end

    for _, row in ipairs(input_rows) do
        if type(row) == "table" and row.active == true then
            return row
        end
    end

    return nil
end

local function dvr_local_detect_mode(stream_id, stream_cfg, status, settings)
    local sid = tostring(stream_id or "")
    local active_input_id = tonumber(status and status.active_input_id) or 0
    local inputs = type(stream_cfg and stream_cfg.input) == "table" and stream_cfg.input or {}
    local active_url = inputs[active_input_id]
    local on_air = status and status.on_air == true
    local last_error = tostring(status and status.last_error or "")
    local now = os.time()
    local fail_checks_required = math.max(1, math.floor(tonumber(settings and settings.backup_fail_checks) or 3))
    local recover_checks_required = math.max(1, math.floor(tonumber(settings and settings.backup_recover_checks) or 5))
    local min_rearm_sec = math.max(0, math.floor(tonumber(settings and settings.backup_min_rearm_sec) or 120))
    local last_switch_ts = tonumber(dvr_local_writer_state.last_switch_ts[sid]) or 0

    if dvr.is_local_backup_input_url(active_url) then
        dvr_local_writer_state.fault_since[sid] = nil
        dvr_local_writer_state.recover_since[sid] = nil
        dvr_local_writer_state.fault_checks[sid] = 0
        dvr_local_writer_state.recover_checks[sid] = 0
        return "DVR_ACTIVE", true, "local_backup_input_active"
    end

    if on_air then
        local state = dvr.get_backup_state(sid)
        local prev_mode = tostring(state and state.mode or "LIVE")
        if settings.backup_enabled and (prev_mode == "DVR_ACTIVE" or prev_mode == "FAIL_CONFIRMED" or prev_mode == "RECOVERING_TO_LIVE") then
            local recover_since = dvr_local_writer_state.recover_since[sid]
            if not recover_since then
                recover_since = now
                dvr_local_writer_state.recover_since[sid] = recover_since
            end
            local recover_checks = (tonumber(dvr_local_writer_state.recover_checks[sid]) or 0) + 1
            dvr_local_writer_state.recover_checks[sid] = recover_checks
            local elapsed = now - recover_since
            local stable_sec = math.max(1, tonumber(settings.backup_recover_stable_sec) or 30)
            dvr_local_writer_state.fault_since[sid] = nil
            dvr_local_writer_state.fault_checks[sid] = 0
            if elapsed >= stable_sec and recover_checks >= recover_checks_required then
                dvr_local_writer_state.recover_since[sid] = nil
                dvr_local_writer_state.recover_checks[sid] = 0
                return "LIVE", false, "recover_stable"
            end
            return "RECOVERING_TO_LIVE", true, "recovering_to_live"
        end
        dvr_local_writer_state.fault_since[sid] = nil
        dvr_local_writer_state.recover_since[sid] = nil
        dvr_local_writer_state.fault_checks[sid] = 0
        dvr_local_writer_state.recover_checks[sid] = 0
        return "LIVE", false, nil
    end

    local has_no_data = dvr_local_is_no_data_error(last_error)
    if not has_no_data then
        local active_status = dvr_local_active_input_status(status)
        if type(active_status) == "table" then
            has_no_data = dvr_local_is_no_data_error(active_status.last_error)
                or dvr_local_is_no_data_error(active_status.health_reason)
                or tostring(active_status.state or ""):upper() == "DOWN"
                or tostring(active_status.health_state or ""):lower() == "offline"
        end
    end
    if has_no_data and settings.backup_enabled then
        dvr_local_writer_state.recover_since[sid] = nil
        dvr_local_writer_state.recover_checks[sid] = 0
        local fault_since = dvr_local_writer_state.fault_since[sid]
        if not fault_since then
            fault_since = now
            dvr_local_writer_state.fault_since[sid] = fault_since
        end
        local fault_checks = (tonumber(dvr_local_writer_state.fault_checks[sid]) or 0) + 1
        dvr_local_writer_state.fault_checks[sid] = fault_checks
        local elapsed = now - fault_since
        if min_rearm_sec > 0 and last_switch_ts > 0 and (now - last_switch_ts) < min_rearm_sec then
            return "LIVE", false, "rearm_cooldown"
        end
        if elapsed >= math.max(1, tonumber(settings.backup_trigger_no_data_sec) or 8)
            and fault_checks >= fail_checks_required
        then
            return "FAIL_CONFIRMED", false, "no_data_confirmed"
        end
    else
        dvr_local_writer_state.fault_since[sid] = nil
        dvr_local_writer_state.recover_since[sid] = nil
        dvr_local_writer_state.fault_checks[sid] = 0
        dvr_local_writer_state.recover_checks[sid] = 0
    end

    return "LIVE", false, nil
end

local function dvr_local_writer_tick(stream_id, entry, stream_cfg, settings, status)
    local sid = tostring(stream_id or "")
    if sid == "" then
        return
    end

    local mode, paused, reason = dvr_local_detect_mode(sid, stream_cfg, status, settings)
    dvr_update_local_state(sid, stream_cfg, settings, mode, paused, reason)

    local writer = dvr_local_writer_state.streams[sid]
    local should_record = settings.archive_enabled == true and paused ~= true and status and status.on_air == true
    if not should_record then
        dvr_local_writer_state.storage_blocked[sid] = nil
        if writer then
            dvr_writer_finalize(writer, paused and "paused" or "offline")
            dvr_local_writer_state.streams[sid] = nil
        end
        return
    end

    local channel_data = entry and entry.channel or nil
    if not channel_data then
        dvr_local_writer_state.storage_blocked[sid] = nil
        if writer then
            dvr_writer_finalize(writer, "offline")
            dvr_local_writer_state.streams[sid] = nil
        end
        return
    end

    local now = os.time()
    local seg_start_ts = dvr.segment_start(now, 3600)
    if writer and tonumber(writer.seg_start_ts) ~= seg_start_ts then
        dvr_writer_finalize(writer, "rotate")
        dvr_local_writer_state.streams[sid] = nil
        writer = nil
    end

    if not writer then
        local new_writer, open_err = dvr_writer_open(sid, channel_data, settings, now)
        if not new_writer then
            dvr.add_event(sid, "DVR_RECORD_OPEN_FAIL", "ERROR", tostring(open_err or "open failed"))
            return
        end
        writer = new_writer
        dvr_local_writer_state.streams[sid] = writer
        dvr.add_event(sid, "DVR_RECORD_OPEN", "INFO",
            "segment=" .. tostring(writer.seg_start_ts), {
                segment = writer.seg_start_ts,
                path = writer.part_path,
            })
    end

    local flush_ok, flush_err = dvr_writer_flush_and_cleanup(writer, now, settings)
    if not flush_ok then
        dvr_local_writer_state.storage_blocked[sid] = flush_err or "storage_guard"
        dvr_writer_finalize(writer, flush_err or "storage_guard")
        dvr_local_writer_state.streams[sid] = nil
        dvr_update_local_state(sid, stream_cfg, settings, mode, true, flush_err or "storage_guard")
        return
    end
    dvr_local_writer_state.storage_blocked[sid] = nil
end

function dvr.local_tick()
    local ids = {}
    if runtime and type(runtime.streams) == "table" then
        for stream_id, _ in pairs(runtime.streams) do
            ids[#ids + 1] = tostring(stream_id)
        end
    end
    local status_map = dvr_local_collect_status(ids)
    local active_set = {}

    for _, stream_id in ipairs(ids) do
        local entry = runtime and runtime.streams and runtime.streams[stream_id] or nil
        local stream_cfg = dvr_read_stream_cfg(stream_id, entry)
        if type(stream_cfg) == "table" then
            local settings = dvr.settings_for_stream(stream_cfg)
            if settings.archive_enabled or settings.backup_enabled then
                active_set[stream_id] = true
                local status = status_map[stream_id] or {}
                dvr_local_writer_tick(stream_id, entry, stream_cfg, settings, status)
            end
        end
    end

    for stream_id, writer in pairs(dvr_local_writer_state.streams) do
        if not active_set[stream_id] then
            dvr_writer_finalize(writer, "disabled")
            dvr_local_writer_state.streams[stream_id] = nil
        end
    end
    for stream_id, _ in pairs(dvr_local_writer_state.fault_since) do
        if not active_set[stream_id] then
            dvr_local_writer_state.fault_since[stream_id] = nil
        end
    end
    for stream_id, _ in pairs(dvr_local_writer_state.fault_checks) do
        if not active_set[stream_id] then
            dvr_local_writer_state.fault_checks[stream_id] = nil
        end
    end
    for stream_id, _ in pairs(dvr_local_writer_state.recover_since) do
        if not active_set[stream_id] then
            dvr_local_writer_state.recover_since[stream_id] = nil
        end
    end
    for stream_id, _ in pairs(dvr_local_writer_state.recover_checks) do
        if not active_set[stream_id] then
            dvr_local_writer_state.recover_checks[stream_id] = nil
        end
    end
    for stream_id, _ in pairs(dvr_local_writer_state.last_switch_ts) do
        if not active_set[stream_id] then
            dvr_local_writer_state.last_switch_ts[stream_id] = nil
        end
    end
    for stream_id, _ in pairs(dvr_local_writer_state.storage_blocked) do
        if not active_set[stream_id] then
            dvr_local_writer_state.storage_blocked[stream_id] = nil
        end
    end

    local remote_active_set = {}
    local default_settings = dvr.settings_for_stream(nil)
    local remote_rows = dvr.list_streams({ record_enabled = true, limit = 10000 })
    for _, row in ipairs(remote_rows) do
        local sid = dvr_trim(row and row.stream_id)
        local has_local_runtime = false
        if runtime and type(runtime.streams) == "table" then
            has_local_runtime = runtime.streams[sid] ~= nil
            if not has_local_runtime then
                local sid_num = tonumber(sid)
                if sid_num then
                    has_local_runtime = runtime.streams[sid_num] ~= nil
                end
            end
        end
        if sid ~= "" and not active_set[sid] and not has_local_runtime then
            remote_active_set[sid] = true
            dvr_remote_writer_tick(row, default_settings)
        end
    end
    for stream_id, writer in pairs(dvr_local_writer_state.remote_streams) do
        if not remote_active_set[stream_id] then
            dvr_writer_finalize(writer, "disabled")
            dvr_local_writer_state.remote_streams[stream_id] = nil
            dvr_local_writer_state.remote_open_fail_ts[stream_id] = nil
            dvr_local_writer_state.remote_open_retry_until[stream_id] = nil
        end
    end
    for stream_id, _ in pairs(dvr_local_writer_state.remote_runtime) do
        if not remote_active_set[stream_id] and not dvr_local_writer_state.remote_streams[stream_id] then
            dvr_local_writer_state.remote_runtime[stream_id] = nil
        end
    end
end

function dvr.repair_segments(limit)
    local row_limit = math.floor(dvr_number(limit, 5000, 1))
    if row_limit > 20000 then
        row_limit = 20000
    end
    local rows = dvr_db_query("SELECT id, stream_id, seg_start_ts, seg_end_ts, path, size_bytes, is_complete, created_ts " ..
        "FROM dvr_segments ORDER BY updated_ts ASC LIMIT " .. tostring(row_limit) .. ";") or {}
    local repaired = 0
    local removed = 0
    for _, row in ipairs(rows) do
        local id = tonumber(row.id) or 0
        if id > 0 then
            local path = dvr_trim(row.path)
            local size = dvr_segment_file_size(path)
            if size <= 0 and path ~= "" and path:sub(-8) == ".part.ts" then
                local alt = path:sub(1, -9) .. ".ts"
                local alt_size = dvr_segment_file_size(alt)
                if alt_size > 0 then
                    path = alt
                    size = alt_size
                end
            end
            if size <= 0 then
                local ok = dvr_db_exec("DELETE FROM dvr_segments WHERE id=" .. id .. ";")
                if ok then
                    removed = removed + 1
                end
            else
                local prev_size = tonumber(row.size_bytes) or 0
                local prev_path = dvr_trim(row.path)
                if prev_size ~= size or prev_path ~= path then
                    dvr_db_exec("UPDATE dvr_segments SET " ..
                        "path='" .. dvr_sql_escape(path) .. "', " ..
                        "size_bytes=" .. math.floor(size) .. ", " ..
                        "updated_ts=" .. os.time() .. " " ..
                        "WHERE id=" .. id .. ";")
                    repaired = repaired + 1
                end
            end
        end
    end
    return {
        repaired = repaired,
        removed = removed,
    }
end

function dvr.configure()
    if dvr_local_writer_state.timer then
        pcall(function()
            dvr_local_writer_state.timer:close()
        end)
        dvr_local_writer_state.timer = nil
    end
    local repair = dvr.repair_segments(5000)
    if repair and (tonumber(repair.repaired) or 0) + (tonumber(repair.removed) or 0) > 0 then
        log.info("[dvr] startup repair: repaired=" .. tostring(repair.repaired) ..
            " removed=" .. tostring(repair.removed))
    end
    dvr_local_writer_state.timer = timer({
        interval = 1,
        callback = function()
            local ok, err = pcall(dvr.local_tick)
            if not ok then
                log.error("[dvr] local tick failed: " .. tostring(err))
            end
        end,
    })
end

function dvr.shutdown()
    if dvr_local_writer_state.timer then
        pcall(function()
            dvr_local_writer_state.timer:close()
        end)
        dvr_local_writer_state.timer = nil
    end
    for stream_id, writer in pairs(dvr_local_writer_state.streams) do
        dvr_writer_finalize(writer, "shutdown")
        dvr_local_writer_state.streams[stream_id] = nil
    end
    for stream_id, writer in pairs(dvr_local_writer_state.remote_streams) do
        dvr_writer_finalize(writer, "shutdown")
        dvr_local_writer_state.remote_streams[stream_id] = nil
    end
    dvr_local_writer_state.remote_runtime = {}
    dvr_local_writer_state.remote_open_fail_ts = {}
    dvr_local_writer_state.remote_open_retry_until = {}
end
