-- Stream runtime
-- https://cesbo.com/astra/
--
-- Copyright (C) 2013-2015, Andrey Dyldin <and@cesbo.com>
--
-- This program is free software: you can redistribute it and/or modify
-- it under the terms of the GNU General Public License as published by
-- the Free Software Foundation, either version 3 of the License, or
-- (at your option) any later version.
--
-- This program is distributed in the hope that it will be useful,
-- but WITHOUT ANY WARRANTY; without even the implied warranty of
-- MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
-- GNU General Public License for more details.
--
-- You should have received a copy of the GNU General Public License
-- along with this program.  If not, see <http://www.gnu.org/licenses/>.

--      o      oooo   oooo     o      ooooo    ooooo  oooo ooooooooooo ooooooooooo
--     888      8888o  88     888      888       888  88   88    888    888    88
--    8  88     88 888o88    8  88     888         888         888      888ooo8
--   8oooo88    88   8888   8oooo88    888      o  888       888    oo  888    oo
-- o88o  o888o o88o    88 o88o  o888o o888ooooo88 o888o    o888oooo888 o888ooo8888

dump_psi_info = {}

dump_psi_info["pat"] = function(name, info)
    log.info(name .. ("PAT: tsid: %d"):format(info.tsid))
    for _, program_info in pairs(info.programs) do
        if program_info.pnr == 0 then
            log.info(name .. ("PAT: pid: %d NIT"):format(program_info.pid))
        else
            log.info(name .. ("PAT: pid: %d PMT pnr: %d"):format(program_info.pid, program_info.pnr))
        end
    end
    log.info(name .. ("PAT: crc32: 0x%X"):format(info.crc32))
end

function dump_descriptor(prefix, descriptor_info)
    if descriptor_info.type_name == "cas" then
        local data = ""
        if descriptor_info.data then data = " data: " .. descriptor_info.data end
        log.info(prefix .. ("CAS: caid: 0x%04X pid: %d%s")
                           :format(descriptor_info.caid, descriptor_info.pid, data))
    elseif descriptor_info.type_name == "lang" then
        log.info(prefix .. "Language: " .. descriptor_info.lang)
    elseif descriptor_info.type_name == "stream_id" then
        log.info(prefix .. "Stream ID: " .. descriptor_info.stream_id)
    elseif descriptor_info.type_name == "service" then
        log.info(prefix .. "Service: " .. descriptor_info.service_name)
        log.info(prefix .. "Provider: " .. descriptor_info.service_provider)
    elseif descriptor_info.type_name == "unknown" then
        log.info(prefix .. "descriptor: " .. descriptor_info.data)
    else
        log.info(prefix .. ("unknown descriptor. type: %s 0x%02X")
                           :format(tostring(descriptor_info.type_name), descriptor_info.type_id))
    end
end

dump_psi_info["cat"] = function(name, info)
    for _, descriptor_info in pairs(info.descriptors) do
        dump_descriptor(name .. "CAT: ", descriptor_info)
    end
end

dump_psi_info["pmt"] = function(name, info)
    log.info(name .. ("PMT: pnr: %d"):format(info.pnr))
    log.info(name .. ("PMT: pid: %d PCR"):format(info.pcr))

    for _, descriptor_info in pairs(info.descriptors) do
        dump_descriptor(name .. "PMT: ", descriptor_info)
    end

    for _, stream_info in pairs(info.streams) do
        log.info(name .. ("%s: pid: %d type: 0x%02X")
                         :format(stream_info.type_name, stream_info.pid, stream_info.type_id))
        for _, descriptor_info in pairs(stream_info.descriptors) do
            dump_descriptor(name .. stream_info.type_name .. ": ", descriptor_info)
        end
    end
    log.info(name .. ("PMT: crc32: 0x%X"):format(info.crc32))
end

dump_psi_info["sdt"] = function(name, info)
    log.info(name .. ("SDT: tsid: %d"):format(info.tsid))

    for _, service in pairs(info.services) do
        log.info(name .. ("SDT: sid: %d"):format(service.sid))
        for _, descriptor_info in pairs(service.descriptors) do
            dump_descriptor(name .. "SDT:    ", descriptor_info)
        end
    end
    log.info(name .. ("SDT: crc32: 0x%X"):format(info.crc32))
end

dump_psi_info["nit"] = function(name, info)
    local network_id = info.network_id or 0
    local table_id = info.table_id or 0
    log.info(name .. ("NIT: network_id: %d table_id: 0x%02X"):format(network_id, table_id))
    if info.network_name then
        log.info(name .. ("NIT: network_name: %s"):format(info.network_name))
    end
    if info.delivery == "cable" or info.delivery == "satellite" then
        local tsid = info.tsid or 0
        local onid = info.onid or 0
        local freq = info.frequency_khz or 0
        local sr = info.symbolrate_ksps or 0
        local modulation = info.modulation or "unknown"
        local fec = info.fec_inner or "unknown"
        log.info(name .. ("NIT: delivery: %s tsid: %d onid: %d freq_khz: %d symbolrate_ksps: %d modulation: %s fec: %s")
            :format(info.delivery, tsid, onid, freq, sr, modulation, fec))
    elseif info.delivery == "terrestrial" then
        local tsid = info.tsid or 0
        local onid = info.onid or 0
        local freq = info.frequency_khz or 0
        local modulation = info.modulation or "unknown"
        log.info(name .. ("NIT: delivery: %s tsid: %d onid: %d freq_khz: %d modulation: %s")
            :format(info.delivery, tsid, onid, freq, modulation))
    end
    if info.service_list then
        local entries = {}
        for sid, stype in pairs(info.service_list) do
            table.insert(entries, string.format("%d=%d", sid, stype))
        end
        table.sort(entries)
        if #entries > 0 then
            log.info(name .. ("NIT: service_list: %s"):format(table.concat(entries, ",")))
        end
    end
    if info.ts_list then
        local entries = {}
        for _, value in pairs(info.ts_list) do
            table.insert(entries, value)
        end
        table.sort(entries)
        if #entries > 0 then
            log.info(name .. ("NIT: ts_list: %s"):format(table.concat(entries, ",")))
        end
    end
    if info.lcn then
        local entries = {}
        for sid, lcn in pairs(info.lcn) do
            table.insert(entries, string.format("%d=%d", sid, lcn))
        end
        table.sort(entries)
        if #entries > 0 then
            log.info(name .. ("NIT: lcn: %s"):format(table.concat(entries, ",")))
        end
    end
    if info.crc32 then
        log.info(name .. ("NIT: crc32: 0x%X"):format(info.crc32))
    end
end

dump_psi_info["tdt"] = function(name, _info)
    log.info(name .. "TDT: present")
end

dump_psi_info["tot"] = function(name, info)
    log.info(name .. "TOT: present")
    if info.crc32 then
        log.info(name .. ("TOT: crc32: 0x%X"):format(info.crc32))
    end
end

local function get_setting(key)
    if config and config.get_setting then
        return config.get_setting(key)
    end
    return nil
end

local function setting_number(key, fallback)
    local value = tonumber(get_setting(key))
    if value == nil then
        return fallback
    end
    return value
end

local function setting_bool(key, fallback)
    local value = get_setting(key)
    if value == nil then
        return fallback
    end
    if value == true or value == 1 or value == "1" then
        return true
    end
    return false
end

local function psi_debug_enabled()
    return setting_bool("psi_debug_logs", false)
end

local psi_debug_only = {
    nit = true,
    tdt = true,
    tot = true,
}

local function setting_string(key, fallback)
    local value = get_setting(key)
    if value == nil or value == "" then
        return fallback
    end
    return tostring(value)
end

local function join_path(base, suffix)
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

local function resolve_hls_output_config(channel_data, conf)
    local stream_id = channel_data.config.id or channel_data.config.name or ""
    local hls_dir = setting_string("hls_dir", "")
    if (not conf.path or conf.path == "") and hls_dir ~= "" and stream_id ~= "" then
        conf.path = join_path(hls_dir, stream_id)
    end

    if conf.target_duration == nil then
        conf.target_duration = setting_number("hls_duration", 6)
    end
    if conf.window == nil then
        conf.window = setting_number("hls_quantity", 5)
    end
    if conf.cleanup == nil then
        local cleanup = setting_number("hls_cleanup", conf.window * 2)
        conf.cleanup = cleanup
    end

    if conf.naming == nil or conf.naming == "" then
        conf.naming = setting_string("hls_naming", "sequence")
    end
    if conf.round_duration == nil then
        conf.round_duration = setting_bool("hls_round_duration", false)
    end
    if conf.ts_extension == nil or conf.ts_extension == "" then
        conf.ts_extension = setting_string("hls_ts_extension", "ts")
    end
    if conf.pass_data == nil then
        conf.pass_data = setting_bool("hls_pass_data", true)
    end

    if conf.storage == nil or conf.storage == "" then
        conf.storage = setting_string("hls_storage", "disk")
    end
    if conf.stream_id == nil or conf.stream_id == "" then
        conf.stream_id = stream_id
    end
    if conf.storage == "memfd" then
        if conf.on_demand == nil then
            conf.on_demand = setting_bool("hls_on_demand", true)
        end
        if conf.idle_timeout_sec == nil then
            conf.idle_timeout_sec = setting_number("hls_idle_timeout_sec", 30)
        end
        if conf.max_bytes == nil then
            conf.max_bytes = setting_number("hls_max_bytes_per_stream", 64 * 1024 * 1024)
        end
        if conf.max_segments == nil then
            conf.max_segments = setting_number("hls_max_segments", conf.cleanup)
        end
    end

    local resource_path = setting_string("hls_resource_path", "absolute")
    if resource_path == "relative" then
        conf.base_url = nil
    elseif conf.base_url == nil or conf.base_url == "" then
        if stream_id ~= "" then
            local base = setting_string("hls_base_url", "")
            if base ~= "" then
                conf.base_url = join_path(base, stream_id)
            end
        end
    end
end

local warned_disk_hls_storage = false

-- http_play_hls historically injected an implicit HLS output into stream configs.
-- That mutation leaks into the UI (OUTPUT LIST) on any config update (including transcode),
-- so we keep HLS behavior as a runtime-only output and never write it into channel_config.output.
local function ensure_auto_hls_output(channel_config, output_list)
    if channel_config and channel_config.__disable_auto_hls then
        return
    end
    if not setting_bool("http_play_hls", false) then
        return
    end

    if not warned_disk_hls_storage then
        local storage = setting_string("hls_storage", "disk")
        if storage ~= "memfd" then
            warned_disk_hls_storage = true
            log.warning("[hls] http_play_hls=true with hls_storage=disk: will write segments to disk. " ..
                "For zero disk I/O use hls_storage=memfd.")
        end
    end

    if type(output_list) ~= "table" then
        return
    end

    for _, item in ipairs(output_list) do
        local conf = nil
        if type(item) == "table" then
            conf = item.config or item
        end
        if conf and tostring(conf.format or ""):lower() == "hls" then
            return
        end
    end

    local idx = #output_list + 1
    local label = tostring(channel_config and channel_config.name or "Stream")
    table.insert(output_list, {
        config = {
            format = "hls",
            auto = true,
            name = label .. " output #" .. tostring(idx) .. " (auto hls)",
        },
    })
end

local function apply_stream_defaults(channel_config)
    if not channel_config then
        return
    end
    local function apply_number(field, setting_key)
        if channel_config[field] ~= nil then
            return
        end
        local value = setting_number(setting_key)
        if value ~= nil then
            channel_config[field] = value
        end
    end
    apply_number("no_data_timeout_sec", "no_data_timeout_sec")
    apply_number("probe_interval_sec", "probe_interval_sec")
    apply_number("stable_ok_sec", "stable_ok_sec")
    apply_number("backup_initial_delay_sec", "backup_initial_delay_sec")
    apply_number("backup_start_delay_sec", "backup_start_delay_sec")
    apply_number("backup_return_delay_sec", "backup_return_delay_sec")
    apply_number("backup_stop_if_all_inactive_sec", "backup_stop_if_all_inactive_sec")
    if channel_config.http_keep_active == nil then
        local value = setting_number("http_keep_active")
        if value ~= nil then
            channel_config.http_keep_active = value
        end
    end
    if channel_config.cas == nil then
        local value = setting_bool("cas_default", nil)
        if value ~= nil then
            channel_config.cas = value
        end
    end
end

local function apply_mpts_config(channel_config)
    if not channel_config or type(channel_config.mpts_config) ~= "table" then
        return
    end
    local mpts = channel_config.mpts_config
    local general = type(mpts.general) == "table" and mpts.general or {}
    local nit = type(mpts.nit) == "table" and mpts.nit or {}
    local adv = type(mpts.advanced) == "table" and mpts.advanced or {}

    if general.codepage and channel_config.codepage == nil then
        channel_config.codepage = tostring(general.codepage)
    end
    if general.provider_name and channel_config.service_provider == nil then
        channel_config.service_provider = tostring(general.provider_name)
    end
    if general.tsid ~= nil and channel_config.set_tsid == nil then
        local tsid = tonumber(general.tsid)
        if tsid ~= nil then
            channel_config.set_tsid = tsid
        end
    end
    if adv.pass_sdt and channel_config.pass_sdt == nil then
        channel_config.pass_sdt = true
    end
    if adv.pass_eit and channel_config.pass_eit == nil then
        channel_config.pass_eit = true
    end

    local unsupported = {}
    local function note(label)
        unsupported[#unsupported + 1] = label
    end
    if general.country ~= nil then note("general.country") end
    if general.utc_offset ~= nil then note("general.utc_offset") end
    if general.network_id ~= nil then note("general.network_id") end
    if general.network_name ~= nil then note("general.network_name") end
    if general.onid ~= nil then note("general.onid") end
    if nit.lcn_descriptor_tag ~= nil then note("nit.lcn_descriptor_tag") end
    if nit.delivery ~= nil and nit.delivery ~= "" then note("nit.delivery") end
    if nit.frequency ~= nil then note("nit.frequency") end
    if nit.symbolrate ~= nil then note("nit.symbolrate") end
    if nit.fec ~= nil and nit.fec ~= "" then note("nit.fec") end
    if nit.modulation ~= nil and nit.modulation ~= "" then note("nit.modulation") end
    if nit.network_search ~= nil and nit.network_search ~= "" then note("nit.network_search") end
    if adv.si_interval_ms ~= nil then note("advanced.si_interval_ms") end
    if adv.pat_version ~= nil then note("advanced.pat_version") end
    if adv.nit_version ~= nil then note("advanced.nit_version") end
    if adv.cat_version ~= nil then note("advanced.cat_version") end
    if adv.sdt_version ~= nil then note("advanced.sdt_version") end
    if adv.pass_nit then note("advanced.pass_nit") end
    if adv.pass_tdt then note("advanced.pass_tdt") end
    if adv.pass_cat then note("advanced.pass_cat") end
    if adv.disable_auto_remap then note("advanced.disable_auto_remap") end
    if adv.pcr_smoothing then note("advanced.pcr_smoothing") end
    if adv.pcr_smooth_alpha ~= nil then note("advanced.pcr_smooth_alpha") end
    if adv.pcr_smooth_max_offset_ms ~= nil then note("advanced.pcr_smooth_max_offset_ms") end
    if adv.spts_only ~= nil then note("advanced.spts_only") end
    if adv.eit_source ~= nil then note("advanced.eit_source") end
    if adv.cat_source ~= nil then note("advanced.cat_source") end
    if #unsupported > 0 then
        log.warning("[" .. channel_config.name .. "] mpts_config fields not supported: " ..
            table.concat(unsupported, ", "))
    end
end

-- Нормализация списка MPTS-сервисов для backend.
local function normalize_mpts_services(value)
    if type(value) ~= "table" then
        return {}
    end
    local result = {}
    for _, item in ipairs(value) do
        if type(item) == "string" then
            table.insert(result, { input = item })
        elseif type(item) == "table" then
            table.insert(result, item)
        end
    end
    return result
end

local function collect_mpts_input(item)
    if type(item) == "string" then
        return item
    end
    if type(item) ~= "table" then
        return nil
    end
    if type(item.input) == "string" then
        return item.input
    end
    if type(item.url) == "string" then
        return item.url
    end
    return nil
end

-- Поиск локального stream:// источника по id или name.
local function resolve_stream_ref(ref)
    if not ref or ref == "" then
        return nil
    end
    local channel = find_channel("id", ref)
    if not channel then
        channel = find_channel("name", ref)
    end
    if not channel then
        local numeric = tonumber(ref)
        if numeric then
            channel = find_channel("id", numeric)
        end
    end
    return channel
end

-- Экранирование аргументов для shell-команд (безопасный запуск).
local function shell_escape(value)
    local text = tostring(value or "")
    return "'" .. text:gsub("'", "'\\''") .. "'"
end

-- Проверка наличия timeout для ограничения длительности скана.
local function has_timeout()
    local ok = os.execute("command -v timeout >/dev/null 2>&1")
    return ok == true or ok == 0
end

-- Запуск команды с ограничением по времени (если timeout доступен).
local function run_command(cmd, timeout_sec)
    local timeout_cmd = ""
    if timeout_sec and timeout_sec > 0 and has_timeout() then
        timeout_cmd = "timeout " .. tostring(math.floor(timeout_sec)) .. " "
    end
    local ok, handle = pcall(io.popen, timeout_cmd .. cmd .. " 2>&1")
    if not ok or not handle then
        return nil, "exec failed"
    end
    local output = handle:read("*a") or ""
    handle:close()
    return output
end

-- Автоматический скан PAT/SDT для заполнения списка сервисов MPTS.
local auto_probe_timeout_warned = false

local function probe_mpts_services(input_url, duration_sec)
    local cfg = parse_url(input_url)
    if not cfg or not cfg.format then
        return nil, "invalid input"
    end
    local format = tostring(cfg.format or ""):lower()
    if format ~= "udp" and format ~= "rtp" then
        return nil, "unsupported input"
    end
    if not cfg.addr or not cfg.port then
        return nil, "invalid input addr/port"
    end

    local duration = tonumber(duration_sec) or 3
    if duration < 1 then duration = 1 end
    if duration > 10 then duration = 10 end

    local script_path = "tools/mpts_pat_scan.py"
    local handle = io.open(script_path, "r")
    if not handle then
        return nil, "mpts_pat_scan.py not found"
    end
    handle:close()

    local cmd = table.concat({
        "python3",
        shell_escape(script_path),
        "--addr",
        shell_escape(cfg.addr),
        "--port",
        shell_escape(cfg.port),
        "--duration",
        shell_escape(duration),
        "--input",
        shell_escape(input_url),
    }, " ")
    if not has_timeout() and not auto_probe_timeout_warned then
        log.warning("[mpts] auto_probe: 'timeout' not found, running scan without wrapper")
        auto_probe_timeout_warned = true
    end
    local output, err = run_command(cmd, duration + 2)
    if not output or output == "" then
        return nil, err or "empty output"
    end
    local ok, parsed = pcall(json.decode, output)
    if not ok or type(parsed) ~= "table" then
        return nil, "invalid output"
    end
    local services = parsed.services or {}
    if type(services) ~= "table" then
        services = {}
    end
    return services
end

local function build_mpts_mux_options(channel_config)
    local mpts = type(channel_config.mpts_config) == "table" and channel_config.mpts_config or {}
    local general = type(mpts.general) == "table" and mpts.general or {}
    local nit = type(mpts.nit) == "table" and mpts.nit or {}
    local adv = type(mpts.advanced) == "table" and mpts.advanced or {}

    local opts = {
        name = channel_config.name,
    }

    -- CAT CA_descriptors (EMM PID). Поскольку C-модуль получает только плоские options,
    -- сериализуем список в строку формата "caid:pid[:private_data];...".
    if mpts.ca ~= nil then
        if type(mpts.ca) == "string" then
            if mpts.ca ~= "" then
                opts.ca = tostring(mpts.ca)
            end
        elseif type(mpts.ca) == "table" then
            local parts = {}
            for idx, entry in ipairs(mpts.ca) do
                if type(entry) == "string" then
                    if entry ~= "" then
                        table.insert(parts, entry)
                    end
                elseif type(entry) == "table" then
                    local caid = tonumber(entry.ca_system_id or entry.caid)
                    local pid = tonumber(entry.ca_pid or entry.pid)
                    local priv = entry.private_data or entry.data
                    if caid == nil or caid < 0 or caid > 65535 then
                        log.warning("[" .. channel_config.name .. "] mpts_config.ca[" .. idx .. "].ca_system_id вне диапазона 0..65535")
                    elseif pid == nil or pid < 0 or pid >= 8191 then
                        log.warning("[" .. channel_config.name .. "] mpts_config.ca[" .. idx .. "].ca_pid вне диапазона 0..8190")
                    else
                        local part = string.format("0x%04X:%d", caid, pid)
                        if type(priv) == "string" and priv ~= "" then
                            local hex = tostring(priv):gsub("%s+", "")
                            hex = hex:gsub("^0[xX]", "")
                            if not hex:match("^[0-9a-fA-F]+$") or (string.len(hex) % 2) == 1 then
                                log.warning("[" .. channel_config.name .. "] mpts_config.ca[" .. idx .. "].private_data должен быть hex строкой чётной длины")
                            else
                                part = part .. ":" .. hex
                            end
                        end
                        table.insert(parts, part)
                    end
                else
                    log.warning("[" .. channel_config.name .. "] mpts_config.ca[" .. idx .. "] должен быть строкой или объектом")
                end
            end
            if #parts > 0 then
                opts.ca = table.concat(parts, ";")
            end
        else
            log.warning("[" .. channel_config.name .. "] mpts_config.ca должен быть строкой или массивом")
        end
    end

    if general.tsid ~= nil then opts.tsid = tonumber(general.tsid) end
    if general.onid ~= nil then opts.onid = tonumber(general.onid) end
    if general.network_id ~= nil then opts.network_id = tonumber(general.network_id) end
    if general.network_name ~= nil then opts.network_name = tostring(general.network_name) end
    if general.provider_name ~= nil then opts.provider_name = tostring(general.provider_name) end
    if general.codepage ~= nil then opts.codepage = tostring(general.codepage) end
    if general.country ~= nil then opts.country = tostring(general.country) end
    if general.utc_offset ~= nil then opts.utc_offset = tonumber(general.utc_offset) end
    if type(general.dst) == "table" then
        local dst = general.dst
        if dst.time_of_change ~= nil and tostring(dst.time_of_change) ~= "" then
            -- dst_time_of_change может быть epoch (seconds) или ISO-8601 UTC.
            -- На C-стороне парсим строку (чтобы не зависеть от типа в UI/JSON).
            opts.dst_time_of_change = tostring(dst.time_of_change)
        end
        if dst.next_offset_minutes ~= nil then
            opts.dst_next_offset_minutes = tonumber(dst.next_offset_minutes)
        end
    end

    if nit.delivery ~= nil then opts.delivery = tostring(nit.delivery) end
    if nit.frequency ~= nil then opts.frequency = tonumber(nit.frequency) end
    if nit.symbolrate ~= nil then opts.symbolrate = tonumber(nit.symbolrate) end
    if nit.fec ~= nil then opts.fec = tostring(nit.fec) end
    if nit.modulation ~= nil then opts.modulation = tostring(nit.modulation) end
    if nit.network_search ~= nil then opts.network_search = tostring(nit.network_search) end
    if nit.bandwidth ~= nil then opts.bandwidth = tonumber(nit.bandwidth) end
    if nit.orbital_position ~= nil then opts.orbital_position = tostring(nit.orbital_position) end
    if nit.polarization ~= nil then opts.polarization = tostring(nit.polarization) end
    if nit.rolloff ~= nil then opts.rolloff = tostring(nit.rolloff) end
    if nit.lcn_descriptor_tag ~= nil then
        local tag = tonumber(nit.lcn_descriptor_tag)
        if tag ~= nil then
            opts.lcn_descriptor_tag = tag
        else
            log.warning("[" .. channel_config.name .. "] mpts_config.nit.lcn_descriptor_tag не распознан")
        end
    end
    if nit.lcn_descriptor_tags ~= nil then
        if type(nit.lcn_descriptor_tags) == "table" then
            local tags = {}
            for _, value in ipairs(nit.lcn_descriptor_tags) do
                local tag = tonumber(value)
                if tag ~= nil and tag >= 1 and tag <= 255 then
                    table.insert(tags, tostring(tag))
                else
                    log.warning("[" .. channel_config.name .. "] mpts_config.nit.lcn_descriptor_tags содержит неверное значение")
                end
            end
            if #tags > 0 then
                opts.lcn_descriptor_tags = table.concat(tags, ",")
            end
        elseif type(nit.lcn_descriptor_tags) == "string" then
            if nit.lcn_descriptor_tags ~= "" then
                opts.lcn_descriptor_tags = tostring(nit.lcn_descriptor_tags)
            end
        else
            log.warning("[" .. channel_config.name .. "] mpts_config.nit.lcn_descriptor_tags должен быть строкой или массивом")
        end
    end
    if nit.lcn_version ~= nil then
        local lcn_version = tonumber(nit.lcn_version)
        if lcn_version == nil then
            log.warning("[" .. channel_config.name .. "] mpts_config.nit.lcn_version не распознан")
        elseif adv.nit_version ~= nil then
            -- Если явно задан nit_version, lcn_version игнорируем.
            log.warning("[" .. channel_config.name .. "] mpts_config.nit.lcn_version игнорируется: задан advanced.nit_version")
        elseif lcn_version < 0 or lcn_version > 31 then
            log.warning("[" .. channel_config.name .. "] mpts_config.nit.lcn_version вне диапазона 0..31, игнорируем")
        else
            -- LCN version используется для совместимости и напрямую задаёт версию NIT.
            opts.nit_version = lcn_version
        end
    end

    if adv.si_interval_ms ~= nil then
        local interval = tonumber(adv.si_interval_ms)
        if interval ~= nil then
            if interval < 50 then
                -- Интервал SI меньше 50мс нестабилен, игнорируем.
                log.warning("[" .. channel_config.name .. "] mpts_config.advanced.si_interval_ms < 50, игнорируем")
            else
                opts.si_interval_ms = interval
            end
        end
    end
    if adv.pat_version ~= nil then opts.pat_version = tonumber(adv.pat_version) end
    if adv.nit_version ~= nil then opts.nit_version = tonumber(adv.nit_version) end
    if adv.cat_version ~= nil then opts.cat_version = tonumber(adv.cat_version) end
    if adv.sdt_version ~= nil then opts.sdt_version = tonumber(adv.sdt_version) end
    if adv.disable_auto_remap then opts.disable_auto_remap = true end
    if adv.pass_nit then opts.pass_nit = true end
    if adv.pass_sdt then opts.pass_sdt = true end
    if adv.pass_eit then opts.pass_eit = true end
    if adv.pass_tdt then opts.pass_tdt = true end
    if adv.disable_tot then opts.disable_tot = true end
    if adv.pass_cat then opts.pass_cat = true end
    if adv.pcr_restamp then opts.pcr_restamp = true end
    if adv.pcr_smoothing then opts.pcr_smoothing = true end
    if adv.pcr_smooth_alpha ~= nil then
        opts.pcr_smooth_alpha = tostring(adv.pcr_smooth_alpha)
    end
    if adv.pcr_smooth_max_offset_ms ~= nil then
        opts.pcr_smooth_max_offset_ms = tonumber(adv.pcr_smooth_max_offset_ms)
    end
    if adv.strict_pnr then opts.strict_pnr = true end
    if adv.spts_only == false then opts.spts_only = false end
    if adv.spts_only == true then opts.spts_only = true end
    if adv.eit_source ~= nil then opts.eit_source = tonumber(adv.eit_source) end
    if adv.eit_table_ids ~= nil then
        if type(adv.eit_table_ids) == "table" then
            local parts = {}
            for _, value in ipairs(adv.eit_table_ids) do
                if value ~= nil and tostring(value) ~= "" then
                    table.insert(parts, tostring(value))
                end
            end
            if #parts > 0 then
                opts.eit_table_ids = table.concat(parts, ",")
            end
        elseif type(adv.eit_table_ids) == "string" then
            if adv.eit_table_ids ~= "" then
                opts.eit_table_ids = tostring(adv.eit_table_ids)
            end
        else
            opts.eit_table_ids = tostring(adv.eit_table_ids)
        end
    end
    if adv.cat_source ~= nil then opts.cat_source = tonumber(adv.cat_source) end
    if adv.target_bitrate ~= nil then
        local bitrate = tonumber(adv.target_bitrate)
        if bitrate ~= nil then
            if bitrate <= 0 then
                -- Нулевой/отрицательный bitrate выключает CBR, используем default (0).
                log.warning("[" .. channel_config.name .. "] mpts_config.advanced.target_bitrate <= 0, игнорируем")
            else
                opts.target_bitrate = bitrate
            end
        end
    end

    return opts
end

local function normalize_backup_type(value, has_multiple)
    if value == nil or value == "" then
        if has_multiple then
            return "passive"
        end
        return "disabled"
    end
    if type(value) == "string" then
        value = value:lower()
    end
    if value == "disable" then
        return "disabled"
    end
    if value == "passive" or value == "active" then
        return value
    end
    if value == "active_stop_if_all_inactive" or value == "active_stop" or value == "active_stop_if_all" then
        return "active_stop_if_all_inactive"
    end
    if value == "disabled" or value == "none" or value == "off" then
        return "disabled"
    end
    if has_multiple then
        return "active"
    end
    return "disabled"
end

local function is_active_backup_mode(mode)
    return mode == "active" or mode == "active_stop_if_all_inactive"
end

local function default_initial_delay(format)
    if not format then
        return 10
    end
    local f = tostring(format):lower()
    if f == "udp" or f == "rtp" or f == "srt" then
        return 5
    end
    if f == "hls" or f == "http" or f == "https" or f == "rtsp" then
        return 10
    end
    if f == "dvb" then
        return 120
    end
    return 10
end

local function read_number_opt(cfg, ...)
    for i = 1, select("#", ...) do
        local key = select(i, ...)
        local value = tonumber(cfg[key])
        if value ~= nil then
            return value
        end
    end
    return nil
end

local function format_input_url(conf)
    if not conf or not conf.format then
        return nil
    end

    local format = conf.format
    if format == "udp" or format == "rtp" then
        local iface = ""
        if conf.localaddr and conf.localaddr ~= "" then
            iface = conf.localaddr .. "@"
        end
        local addr = conf.addr or ""
        local port = conf.port and (":" .. tostring(conf.port)) or ""
        return format .. "://" .. iface .. addr .. port
    end

    if format == "http" or format == "https" or format == "hls" or format == "np" then
        local auth = ""
        if conf.login and conf.login ~= "" then
            auth = conf.login
            if conf.password and conf.password ~= "" then
                auth = auth .. ":" .. conf.password
            end
            auth = auth .. "@"
        end
        local host = conf.host or ""
        local port = conf.port and (":" .. tostring(conf.port)) or ""
        local path = conf.path or "/"
        return format .. "://" .. auth .. host .. port .. path
    end

    if format == "file" then
        return "file://" .. tostring(conf.filename or "")
    end

    if format == "dvb" then
        return "dvb://" .. tostring(conf.addr or "")
    end

    return nil
end

local INPUT_NO_AUDIO_DEFAULT_SEC = 5
local INPUT_STOP_VIDEO_DEFAULT_SEC = 5
local INPUT_AV_DESYNC_THRESHOLD_MS_DEFAULT = 800
local INPUT_AV_DESYNC_HOLD_SEC_DEFAULT = 3
local INPUT_AV_DESYNC_STABLE_SEC_DEFAULT = 10
local INPUT_AV_DESYNC_RESEND_SEC_DEFAULT = 60
local INPUT_SILENCE_DURATION_DEFAULT = 20
local INPUT_SILENCE_INTERVAL_DEFAULT = 10
local INPUT_SILENCE_NOISE_DEFAULT = -30
local INPUT_SILENCE_PROBE_MAX_DEFAULT = 2
local INPUT_VIDEO_FREEZE_SEC_DEFAULT = 10

local function is_truthy(value)
    if value == true or value == 1 then
        return true
    end
    if type(value) == "string" then
        local v = value:lower()
        return v == "1" or v == "true" or v == "yes" or v == "on"
    end
    return false
end

local function parse_number(value)
    local n = tonumber(value)
    if n == nil then
        return nil
    end
    return n
end

local function normalize_silencedetect(conf)
    if not conf then
        return nil
    end
    local raw = conf.silencedetect
    if raw == nil then
        return nil
    end
    local duration = nil
    local interval = nil
    local noise = nil
    if type(raw) == "string" and raw:find(",") then
        local a, b, c = raw:match("^%s*([^,]+)%s*,%s*([^,]+)%s*,%s*([^,]+)%s*$")
        duration = tonumber(a)
        interval = tonumber(b)
        noise = tonumber(c)
    elseif is_truthy(raw) then
        -- defaults
    elseif tonumber(raw) then
        duration = tonumber(raw)
    end

    duration = duration or parse_number(conf.silence_duration) or parse_number(conf.silencedetect_duration) or INPUT_SILENCE_DURATION_DEFAULT
    interval = interval or parse_number(conf.silence_interval) or parse_number(conf.silencedetect_interval) or INPUT_SILENCE_INTERVAL_DEFAULT
    noise = noise or parse_number(conf.silence_noise) or parse_number(conf.silencedetect_noise) or INPUT_SILENCE_NOISE_DEFAULT

    if duration <= 0 then
        return nil
    end
    if interval < 1 then
        interval = INPUT_SILENCE_INTERVAL_DEFAULT
    end
    return {
        enabled = true,
        duration_sec = duration,
        interval_sec = interval,
        noise_db = noise,
    }
end

local function normalize_input_detectors(conf)
    if type(conf) ~= "table" then
        return nil
    end

    local detectors = {}

    local no_audio = conf.no_audio_on
    if no_audio ~= nil then
        local timeout = tonumber(no_audio)
        if is_truthy(no_audio) or timeout == nil then
            timeout = INPUT_NO_AUDIO_DEFAULT_SEC
        end
        if timeout and timeout > 0 then
            detectors.no_audio = {
                enabled = true,
                timeout_sec = timeout,
            }
        end
    end

    local stop_video = conf.stop_video
    if stop_video ~= nil then
        local mode = "pts"
        if type(stop_video) == "string" and stop_video:lower() == "freeze" then
            mode = "freeze"
        elseif not is_truthy(stop_video) then
            mode = nil
        end
        if mode then
            local timeout = tonumber(conf.stop_video_timeout_sec) or INPUT_STOP_VIDEO_DEFAULT_SEC
            local freeze_sec = tonumber(conf.stop_video_freeze_sec) or INPUT_VIDEO_FREEZE_SEC_DEFAULT
            detectors.stop_video = {
                enabled = true,
                mode = mode,
                timeout_sec = timeout,
                freeze_sec = freeze_sec,
            }
        end
    end

    local detect_av = conf.detect_av
    if detect_av ~= nil and is_truthy(detect_av) then
        detectors.av_desync = {
            enabled = true,
            threshold_ms = tonumber(conf.detect_av_threshold_ms or conf.av_threshold_ms) or INPUT_AV_DESYNC_THRESHOLD_MS_DEFAULT,
            hold_sec = tonumber(conf.detect_av_hold_sec or conf.av_hold_sec) or INPUT_AV_DESYNC_HOLD_SEC_DEFAULT,
            stable_sec = tonumber(conf.detect_av_stable_sec or conf.av_stable_sec) or INPUT_AV_DESYNC_STABLE_SEC_DEFAULT,
            resend_interval_sec = tonumber(conf.detect_av_resend_interval_sec or conf.av_resend_interval_sec) or INPUT_AV_DESYNC_RESEND_SEC_DEFAULT,
        }
    end

    local silence = normalize_silencedetect(conf)
    if silence then
        detectors.silence = silence
    end

    if next(detectors) == nil then
        return nil
    end
    return detectors
end

local function get_silence_probe_limit()
    local limit = tonumber(setting_number("silencedetect_max_probes", INPUT_SILENCE_PROBE_MAX_DEFAULT))
    if not limit or limit < 1 then
        limit = INPUT_SILENCE_PROBE_MAX_DEFAULT
    end
    return limit
end

local function build_local_input_url(stream_id, input_id)
    local http_port = tonumber(config and config.get_setting and config.get_setting("http_port") or nil) or 8000
    local suffix = ""
    if input_id and tonumber(input_id) and tonumber(input_id) > 0 then
        suffix = "~" .. tostring(input_id)
    end
    return "http://127.0.0.1:" .. tostring(http_port) .. "/input/" .. tostring(stream_id) .. suffix .. "?internal=1"
end

local AUDIO_FIX_TARGET_TYPE_DEFAULT = 0x0F
local AUDIO_FIX_PROBE_INTERVAL_DEFAULT = 30
local AUDIO_FIX_PROBE_DURATION_DEFAULT = 2
local AUDIO_FIX_MISMATCH_HOLD_DEFAULT = 10
local AUDIO_FIX_RESTART_COOLDOWN_DEFAULT = 1200
local AUDIO_FIX_AAC_BITRATE_DEFAULT = 128
local AUDIO_FIX_AAC_SAMPLE_RATE_DEFAULT = 48000
local AUDIO_FIX_AAC_CHANNELS_DEFAULT = 2
local AUDIO_FIX_ARESAMPLE_ASYNC_DEFAULT = 1
local AUDIO_FIX_INPUT_PROBE_TIMEOUT_DEFAULT = 10
local AUDIO_FIX_DRIFT_PROBE_INTERVAL_DEFAULT = 60
local AUDIO_FIX_DRIFT_PROBE_DURATION_DEFAULT = 2
local AUDIO_FIX_DRIFT_THRESHOLD_MS_DEFAULT = 800
local AUDIO_FIX_DRIFT_FAIL_COUNT_DEFAULT = 3
local AUDIO_FIX_ANALYZE_MAX_DEFAULT = 4
local AUDIO_FIX_PLAY_BUFFER_KB_DEFAULT = 512
local AUDIO_FIX_PLAY_BUFFER_FILL_KB_DEFAULT = 16
local audio_fix_analyze_active = 0
local silence_probe_active = 0

local function format_audio_type_hex(value)
    if not value then
        return nil
    end
    return ("0x%02X"):format(value)
end

local function resolve_output_localaddr(conf)
    local localaddr = conf and conf.localaddr or nil
    if type(localaddr) == "string" then
        localaddr = localaddr:match("^%s*(.-)%s*$")
        if localaddr == "" then
            return nil
        end
    end
    if localaddr and ifaddr_list then
        local ifaddr = ifaddr_list[localaddr]
        if ifaddr and ifaddr.ipv4 then
            localaddr = ifaddr.ipv4[1]
        end
    end
    if type(localaddr) ~= "string" or localaddr == "" then
        return nil
    end
    if not localaddr:match("^%d+%.%d+%.%d+%.%d+$") then
        return nil
    end
    return localaddr
end

local function format_udp_output_url(conf, include_params)
    if not conf then
        return nil
    end
    local format = conf.format or "udp"
    local addr = conf.addr or ""
    local port = conf.port and tostring(conf.port) or ""
    if addr == "" or port == "" then
        return nil
    end
    local iface = ""
    local localaddr = resolve_output_localaddr(conf) or conf.localaddr
    if localaddr and localaddr ~= "" then
        iface = localaddr .. "@"
    end
    local url = format .. "://" .. iface .. addr .. ":" .. port
    if not include_params then
        return url
    end
    local params = {}
    table.insert(params, "pkt_size=1316")
    local ttl = tonumber(conf.ttl)
    if ttl and ttl > 0 then
        table.insert(params, "ttl=" .. tostring(ttl))
    end
    if #params > 0 then
        url = url .. "?" .. table.concat(params, "&")
    end
    return url
end

local function normalize_audio_fix_config(conf)
    if type(conf) ~= "table" then
        conf = {}
    end
    local enabled = conf.enabled == true
    local force_on = conf.force_on == true
    local mode = conf.mode
    if type(mode) == "string" then
        mode = mode:lower()
    else
        mode = nil
    end
    if mode ~= "aac" and mode ~= "auto" then
        mode = "aac"
    end
    local target = conf.target_audio_type
    if type(target) == "string" then
        target = tonumber(target) or tonumber(target, 16)
    elseif type(target) ~= "number" then
        target = nil
    end
    target = target or AUDIO_FIX_TARGET_TYPE_DEFAULT
    local interval = tonumber(conf.probe_interval_sec) or AUDIO_FIX_PROBE_INTERVAL_DEFAULT
    if interval < 1 then interval = 1 end
    local duration = tonumber(conf.probe_duration_sec) or AUDIO_FIX_PROBE_DURATION_DEFAULT
    if duration < 1 then duration = 1 end
    local hold = tonumber(conf.mismatch_hold_sec) or AUDIO_FIX_MISMATCH_HOLD_DEFAULT
    if hold < 1 then hold = 1 end
    local cooldown = tonumber(conf.restart_cooldown_sec) or AUDIO_FIX_RESTART_COOLDOWN_DEFAULT
    if cooldown < 0 then cooldown = 0 end
    local bitrate_kbps = tonumber(conf.aac_bitrate_kbps) or AUDIO_FIX_AAC_BITRATE_DEFAULT
    if bitrate_kbps < 8 then bitrate_kbps = AUDIO_FIX_AAC_BITRATE_DEFAULT end
    local sample_rate = tonumber(conf.aac_sample_rate) or AUDIO_FIX_AAC_SAMPLE_RATE_DEFAULT
    if sample_rate < 8000 then sample_rate = AUDIO_FIX_AAC_SAMPLE_RATE_DEFAULT end
    local channels = tonumber(conf.aac_channels) or AUDIO_FIX_AAC_CHANNELS_DEFAULT
    if channels < 1 then channels = AUDIO_FIX_AAC_CHANNELS_DEFAULT end
    local profile = ""
    if type(conf.aac_profile) == "string" then
        profile = conf.aac_profile:match("^%s*(.-)%s*$") or ""
    end
    local async_value = nil
    if conf.aresample_async ~= nil then
        async_value = tonumber(conf.aresample_async)
    end
    if async_value == nil or async_value < 0 then
        async_value = AUDIO_FIX_ARESAMPLE_ASYNC_DEFAULT
    end
    local silence_fallback = conf.silence_fallback == true
    local input_probe_timeout = tonumber(conf.input_probe_timeout_sec) or AUDIO_FIX_INPUT_PROBE_TIMEOUT_DEFAULT
    if input_probe_timeout < 1 then input_probe_timeout = 1 end
    local max_interleave_delta_sec = tonumber(conf.max_interleave_delta_sec)
    if max_interleave_delta_sec ~= nil and max_interleave_delta_sec <= 0 then
        max_interleave_delta_sec = nil
    end
    local genpts = conf.genpts == true
    local drift_probe_enabled = conf.drift_probe_enabled == true
    local drift_probe_interval = tonumber(conf.drift_probe_interval_sec) or AUDIO_FIX_DRIFT_PROBE_INTERVAL_DEFAULT
    if drift_probe_interval < 1 then drift_probe_interval = 1 end
    local drift_probe_duration = tonumber(conf.drift_probe_duration_sec) or AUDIO_FIX_DRIFT_PROBE_DURATION_DEFAULT
    if drift_probe_duration < 1 then drift_probe_duration = 1 end
    local drift_threshold_ms = tonumber(conf.drift_threshold_ms) or AUDIO_FIX_DRIFT_THRESHOLD_MS_DEFAULT
    if drift_threshold_ms < 0 then drift_threshold_ms = 0 end
    local drift_fail_count = tonumber(conf.drift_fail_count) or AUDIO_FIX_DRIFT_FAIL_COUNT_DEFAULT
    if drift_fail_count < 1 then drift_fail_count = 1 end
    local input_url = nil
    if type(conf.input_url) == "string" then
        input_url = conf.input_url:match("^%s*(.-)%s*$") or ""
        if input_url == "" then
            input_url = nil
        end
    end
    local play_buffer_kb = conf.play_buffer_kb
    if play_buffer_kb == nil then
        play_buffer_kb = conf.input_play_buffer_kb
    end
    local has_play_buffer = play_buffer_kb ~= nil
    if play_buffer_kb ~= nil then
        play_buffer_kb = tonumber(play_buffer_kb)
        if not play_buffer_kb or play_buffer_kb <= 0 then
            play_buffer_kb = nil
        end
    end
    if not has_play_buffer then
        play_buffer_kb = AUDIO_FIX_PLAY_BUFFER_KB_DEFAULT
    end

    local play_buffer_fill_kb = conf.play_buffer_fill_kb
    if play_buffer_fill_kb == nil then
        play_buffer_fill_kb = conf.input_play_buffer_fill_kb
    end
    local has_play_buffer_fill = play_buffer_fill_kb ~= nil
    if play_buffer_fill_kb ~= nil then
        play_buffer_fill_kb = tonumber(play_buffer_fill_kb)
        if not play_buffer_fill_kb or play_buffer_fill_kb <= 0 then
            play_buffer_fill_kb = nil
        end
    end
    if not has_play_buffer_fill then
        play_buffer_fill_kb = AUDIO_FIX_PLAY_BUFFER_FILL_KB_DEFAULT
    end
    return {
        enabled = enabled,
        force_on = force_on,
        mode = mode,
        target_audio_type = target,
        probe_interval_sec = interval,
        probe_duration_sec = duration,
        mismatch_hold_sec = hold,
        restart_cooldown_sec = cooldown,
        auto_disable_when_ok = conf.auto_disable_when_ok == true,
        aac_bitrate_kbps = bitrate_kbps,
        aac_sample_rate = sample_rate,
        aac_channels = channels,
        aac_profile = profile,
        aresample_async = async_value,
        silence_fallback = silence_fallback,
        input_probe_timeout_sec = input_probe_timeout,
        max_interleave_delta_sec = max_interleave_delta_sec,
        genpts = genpts,
        drift_probe_enabled = drift_probe_enabled,
        drift_probe_interval_sec = drift_probe_interval,
        drift_probe_duration_sec = drift_probe_duration,
        drift_threshold_ms = drift_threshold_ms,
        drift_fail_count = drift_fail_count,
        restart_on_drift = conf.restart_on_drift == true,
        auto_copy_require_lc = conf.auto_copy_require_lc == true,
        play_buffer_kb = play_buffer_kb,
        play_buffer_fill_kb = play_buffer_fill_kb,
        input_url = input_url,
    }
end

local function get_audio_fix_analyze_limit()
    local limit = nil
    if config and config.get_setting then
        limit = tonumber(config.get_setting("monitor_analyze_max_concurrency"))
    end
    if not limit or limit <= 0 then
        limit = AUDIO_FIX_ANALYZE_MAX_DEFAULT
    end
    return limit
end

local function build_analyze_args(url, duration_sec)
    local seconds = tonumber(duration_sec) or 1
    if seconds < 1 then
        seconds = 1
    end
    return {
        "./astra",
        "scripts/analyze.lua",
        "-n",
        tostring(seconds),
        tostring(url),
    }
end

local function parse_analyze_audio_type(line)
    if not line or line == "" then
        return nil
    end
    local value = line:match("[Aa][Uu][Dd][Ii][Oo]%s*:?%s*pid:%s*%d+%s*type:%s*0x([0-9A-Fa-f]+)")
    if not value then
        return nil
    end
    return tonumber(value, 16)
end

local function consume_lines(target, buffer_key, chunk, handler)
    if not chunk or chunk == "" then
        return
    end
    target[buffer_key] = (target[buffer_key] or "") .. chunk
    while true do
        local line, rest = target[buffer_key]:match("^(.-)\n(.*)$")
        if not line then
            break
        end
        target[buffer_key] = rest
        handler(line:gsub("\r$", ""))
    end
end

local function send_stream_event(channel_data, event, payload)
    local endpoint = setting_string("event_request", "")
    if endpoint == "" then
        return
    end
    local parsed = parse_url(endpoint)
    if not parsed or (parsed.format ~= "http" and parsed.format ~= "https") then
        if channel_data and not channel_data.detector_event_warned then
            log.warning("[stream " .. get_stream_label(channel_data) .. "] invalid event_request: " .. tostring(endpoint))
            channel_data.detector_event_warned = true
        end
        return
    end
    if parsed.format == "https" and not (astra and astra.features and astra.features.ssl) then
        if channel_data and not channel_data.detector_event_warned then
            log.warning("[stream " .. get_stream_label(channel_data) .. "] https not supported for event_request")
            channel_data.detector_event_warned = true
        end
        return
    end

    local port = parsed.port or (parsed.format == "https" and 443 or 80)
    local path = parsed.path or "/"
    local host_header = parsed.host or ""
    if port then
        host_header = host_header .. ":" .. tostring(port)
    end

    local base = {
        event = event,
        stream_id = channel_data and channel_data.config and channel_data.config.id or "",
        ts = os.time(),
    }
    if payload then
        for key, value in pairs(payload) do
            base[key] = value
        end
    end
    local body = json.encode(base)

    http_request({
        host = parsed.host,
        port = port,
        path = path,
        method = "POST",
        ssl = (parsed.format == "https"),
        headers = {
            "Content-Type: application/json",
            "Content-Length: " .. tostring(#body),
            "Host: " .. host_header,
            "Connection: close",
        },
        content = body,
        callback = function(self, response)
            if not response then
                return
            end
            if response.code and response.code >= 400 then
                log.warning("[stream " .. get_stream_label(channel_data) .. "] event_request failed: " ..
                    tostring(response.code))
            end
        end,
    })
end

local function ensure_detector_state(input_data)
    if not input_data.detector_state then
        input_data.detector_state = {}
    end
    return input_data.detector_state
end

local function emit_detector_event(channel_data, input_id, input_data, detector_key, level, code, message, meta, now, resend_sec)
    local state = ensure_detector_state(input_data)
    state[detector_key] = state[detector_key] or {}
    local det = state[detector_key]
    local last = det.last_event_ts or 0
    if resend_sec and resend_sec > 0 and last > 0 and (now - last) < resend_sec then
        return
    end
    det.last_event_ts = now
    local payload = meta or {}
    payload.input_index = input_id and (input_id - 1) or nil
    payload.input_url = input_data and input_data.source_url or nil
    emit_stream_alert(channel_data, level, code, message, payload)
    send_stream_event(channel_data, code:lower(), payload)
end

local function update_detector_state_entry(entry, state, now, extra)
    entry.state = state
    if state == "ALERT" then
        if not entry.since then
            entry.since = now
        end
    else
        entry.since = nil
    end
    if extra then
        for key, value in pairs(extra) do
            entry[key] = value
        end
    end
end

local function stop_silence_probe(input_data)
    if not input_data then
        return
    end
    local probe = input_data.silence_probe
    if not probe or not probe.proc then
        input_data.silence_probe = nil
        return
    end
    probe.proc:terminate()
    probe.proc:kill()
    probe.proc:close()
    silence_probe_active = math.max(0, silence_probe_active - 1)
    input_data.silence_probe = nil
end

local function tick_silence_probe(channel_data, input_id, input_data, det, now)
    if not det or det.enabled ~= true then
        return
    end
    if not process or type(process.spawn) ~= "function" then
        det.last_error = "process module not available"
        return
    end
    local probe = input_data.silence_probe
    if probe and probe.proc then
        local err_chunk = probe.proc:read_stderr()
        if err_chunk then
            consume_lines(probe, "stderr_buf", err_chunk, function(line)
                if line:find("silence_start") then
                    det.silence_active = true
                    if det.state ~= "ALERT" then
                        update_detector_state_entry(det, "ALERT", now, { noise_db = det.noise_db })
                        emit_detector_event(channel_data, input_id, input_data, "silence", "WARNING",
                            "AUDIO_SILENCE_DETECTED", "audio silence detected", {
                                detector = "silence",
                                noise_db = det.noise_db,
                            }, now, det.resend_interval_sec)
                    end
                elseif line:find("silence_end") then
                    det.silence_active = false
                    if det.state == "ALERT" then
                        update_detector_state_entry(det, "OK", now, { noise_db = det.noise_db })
                        emit_detector_event(channel_data, input_id, input_data, "silence", "INFO",
                            "AUDIO_SILENCE_END", "audio silence ended", {
                                detector = "silence",
                            }, now, nil)
                    end
                end
            end)
        end
        local status = probe.proc:poll()
        if status or (now - probe.start_ts) >= (probe.timeout_sec or det.duration_sec) then
            if not status then
                probe.proc:kill()
            end
            probe.proc:close()
            silence_probe_active = math.max(0, silence_probe_active - 1)
            input_data.silence_probe = nil
            det.next_probe_ts = now + (det.interval_sec or INPUT_SILENCE_INTERVAL_DEFAULT)
        end
        return
    end

    if det.next_probe_ts and now < det.next_probe_ts then
        return
    end

    local limit = get_silence_probe_limit()
    if silence_probe_active >= limit then
        det.last_error = "probe_limit"
        det.next_probe_ts = now + (det.interval_sec or INPUT_SILENCE_INTERVAL_DEFAULT)
        return
    end

    local stream_id = channel_data and channel_data.config and channel_data.config.id or ""
    if stream_id == "" then
        det.last_error = "stream_id_missing"
        det.next_probe_ts = now + (det.interval_sec or INPUT_SILENCE_INTERVAL_DEFAULT)
        return
    end
    local input_url = build_local_input_url(stream_id, input_id)
    if not input_url or input_url == "" then
        det.last_error = "input_url_missing"
        det.next_probe_ts = now + (det.interval_sec or INPUT_SILENCE_INTERVAL_DEFAULT)
        return
    end

    local ffmpeg_bin = resolve_tool_path("ffmpeg", {
        setting_key = "ffmpeg_path",
        env_key = "ASTRA_FFMPEG_PATH",
    })
    local args = {
        ffmpeg_bin,
        "-hide_banner",
        "-nostdin",
        "-loglevel",
        "info",
        "-i",
        tostring(input_url),
        "-vn",
        "-af",
        ("silencedetect=noise=%sdB:d=%s"):format(tostring(det.noise_db or INPUT_SILENCE_NOISE_DEFAULT),
            tostring(det.duration_sec or INPUT_SILENCE_DURATION_DEFAULT)),
        "-t",
        tostring(det.duration_sec or INPUT_SILENCE_DURATION_DEFAULT),
        "-f",
        "null",
        "-",
    }
    local ok, proc = pcall(process.spawn, args, { stderr = "pipe" })
    if not ok or not proc then
        det.last_error = "ffmpeg_spawn_failed"
        det.next_probe_ts = now + (det.interval_sec or INPUT_SILENCE_INTERVAL_DEFAULT)
        return
    end
    silence_probe_active = silence_probe_active + 1
    det.last_error = nil
    input_data.silence_probe = {
        proc = proc,
        stderr_buf = "",
        start_ts = now,
        timeout_sec = (det.duration_sec or INPUT_SILENCE_DURATION_DEFAULT) + 2,
    }
end

local function update_input_detectors(channel_data, input_id, input_data, total, now)
    if not input_data or type(total) ~= "table" then
        return
    end

    local detectors = normalize_input_detectors(input_data.config)
    input_data.detectors_config = detectors
    if not detectors then
        input_data.health = nil
        return
    end

    local state = ensure_detector_state(input_data)
    local health = input_data.health or {}
    input_data.health = health
    health.audio_present = total.audio_present == true
    health.video_present = total.video_present == true
    health.audio_bitrate = total.audio_bitrate
    health.video_bitrate = total.video_bitrate

    local active_only = (channel_data and channel_data.active_input_id and channel_data.active_input_id == input_id)
    if not active_only then
        return
    end

    -- NO AUDIO
    if detectors.no_audio and detectors.no_audio.enabled then
        local det = state.no_audio or {}
        state.no_audio = det
        det.timeout_sec = detectors.no_audio.timeout_sec
        if total.audio_present == true then
            input_data.last_audio_seen_ts = now
        end
        if total.audio_pts_ms and total.audio_pts_ms ~= input_data.last_audio_pts_ms then
            input_data.last_audio_pts_ms = total.audio_pts_ms
            input_data.last_audio_pts_change_ts = now
        end
        local last_activity = input_data.last_audio_pts_change_ts or input_data.last_audio_seen_ts
        if not last_activity then
            last_activity = now
        end
        if (now - last_activity) >= det.timeout_sec then
            if det.state ~= "ALERT" then
                update_detector_state_entry(det, "ALERT", now, {})
                emit_detector_event(channel_data, input_id, input_data, "no_audio", "WARNING",
                    "NO_AUDIO_DETECTED", "no audio detected", {
                        detector = "no_audio",
                        timeout_sec = det.timeout_sec,
                    }, now, det.resend_interval_sec)
            end
        else
            if det.state == "ALERT" then
                update_detector_state_entry(det, "OK", now, {})
                emit_detector_event(channel_data, input_id, input_data, "no_audio", "INFO",
                    "NO_AUDIO_END", "audio recovered", {
                        detector = "no_audio",
                    }, now, nil)
            end
        end
        health.no_audio_state = det.state or "OK"
        health.no_audio_since = det.since
    end

    -- STOP VIDEO / FREEZE
    if detectors.stop_video and detectors.stop_video.enabled then
        local det = state.stop_video or {}
        state.stop_video = det
        det.mode = detectors.stop_video.mode
        det.timeout_sec = detectors.stop_video.timeout_sec
        det.freeze_sec = detectors.stop_video.freeze_sec
        if total.video_present == true then
            input_data.last_video_seen_ts = now
        end
        if total.video_pts_ms and total.video_pts_ms ~= input_data.last_video_pts_ms then
            input_data.last_video_pts_ms = total.video_pts_ms
            input_data.last_video_pts_change_ts = now
        end
        if det.mode == "freeze" and total.video_idr_hash then
            if input_data.last_video_idr_hash ~= total.video_idr_hash then
                input_data.last_video_idr_hash = total.video_idr_hash
                input_data.last_video_idr_change_ts = now
                if det.state == "ALERT" then
                    update_detector_state_entry(det, "OK", now, {})
                    emit_detector_event(channel_data, input_id, input_data, "stop_video", "INFO",
                        "VIDEO_FREEZE_END", "video freeze ended", {
                            detector = "video_freeze",
                        }, now, nil)
                end
            end
            local last_change = input_data.last_video_idr_change_ts or now
            if (now - last_change) >= (det.freeze_sec or INPUT_VIDEO_FREEZE_SEC_DEFAULT) then
                if det.state ~= "ALERT" then
                    update_detector_state_entry(det, "ALERT", now, {})
                    emit_detector_event(channel_data, input_id, input_data, "stop_video", "WARNING",
                        "VIDEO_FREEZE_DETECTED", "video freeze detected", {
                            detector = "video_freeze",
                            freeze_sec = det.freeze_sec,
                        }, now, det.resend_interval_sec)
                end
            end
        else
            local last_activity = input_data.last_video_pts_change_ts or input_data.last_video_seen_ts
            if not last_activity then
                last_activity = now
            end
            if (now - last_activity) >= det.timeout_sec then
                if det.state ~= "ALERT" then
                    update_detector_state_entry(det, "ALERT", now, {})
                    emit_detector_event(channel_data, input_id, input_data, "stop_video", "WARNING",
                        "VIDEO_STOP_DETECTED", "video stopped", {
                            detector = "stop_video",
                            timeout_sec = det.timeout_sec,
                        }, now, det.resend_interval_sec)
                end
            else
                if det.state == "ALERT" then
                    update_detector_state_entry(det, "OK", now, {})
                    emit_detector_event(channel_data, input_id, input_data, "stop_video", "INFO",
                        "VIDEO_STOP_END", "video recovered", {
                            detector = "stop_video",
                        }, now, nil)
                end
            end
        end
        health.stop_video_state = det.state or "OK"
        health.stop_video_since = det.since
        health.stop_video_mode = det.mode
    end

    -- AV DESYNC
    if detectors.av_desync and detectors.av_desync.enabled then
        local det = state.av_desync or {}
        state.av_desync = det
        det.threshold_ms = detectors.av_desync.threshold_ms
        det.hold_sec = detectors.av_desync.hold_sec
        det.stable_sec = detectors.av_desync.stable_sec
        det.resend_interval_sec = detectors.av_desync.resend_interval_sec
        if total.audio_pts_ms and total.video_pts_ms then
            local diff = math.abs(tonumber(total.video_pts_ms) - tonumber(total.audio_pts_ms))
            det.current_ms = diff
            if diff >= det.threshold_ms then
                det.exceed_since = det.exceed_since or now
                det.ok_since = nil
                if det.state ~= "ALERT" and (now - det.exceed_since) >= det.hold_sec then
                    update_detector_state_entry(det, "ALERT", now, { current_ms = diff })
                    emit_detector_event(channel_data, input_id, input_data, "av_desync", "WARNING",
                        "AV_DESYNC_DETECTED", "av desync detected", {
                            detector = "av_desync",
                            current_ms = diff,
                            threshold_ms = det.threshold_ms,
                        }, now, det.resend_interval_sec)
                elseif det.state == "ALERT" and det.resend_interval_sec and det.resend_interval_sec > 0 then
                    emit_detector_event(channel_data, input_id, input_data, "av_desync", "WARNING",
                        "AV_DESYNC_DETECTED", "av desync detected", {
                            detector = "av_desync",
                            current_ms = diff,
                            threshold_ms = det.threshold_ms,
                        }, now, det.resend_interval_sec)
                end
            else
                det.exceed_since = nil
                det.ok_since = det.ok_since or now
                if det.state == "ALERT" and (now - det.ok_since) >= det.stable_sec then
                    update_detector_state_entry(det, "OK", now, { current_ms = diff })
                    emit_detector_event(channel_data, input_id, input_data, "av_desync", "INFO",
                        "AV_DESYNC_END", "av desync resolved", {
                            detector = "av_desync",
                            current_ms = diff,
                        }, now, nil)
                end
            end
        end
        health.av_desync_state = det.state or "OK"
        health.av_desync_since = det.since
        health.av_desync_ms = det.current_ms
    end

    -- SILENCE DETECT (ffmpeg probe)
    if detectors.silence and detectors.silence.enabled then
        local det = state.silence or {}
        state.silence = det
        det.enabled = true
        det.duration_sec = detectors.silence.duration_sec
        det.interval_sec = detectors.silence.interval_sec
        det.noise_db = detectors.silence.noise_db
        tick_silence_probe(channel_data, input_id, input_data, det, now)
        health.silence_state = det.state or "OK"
        health.silence_since = det.since
        health.silence_noise_db = det.noise_db
    end
end

function on_analyze_spts(channel_data, input_id, data)
    local input_data = channel_data.input[input_id]
    local now = os.time()

    if data.error then
        log.error("[" .. input_data.config.name .. "] Error: " .. data.error)
        input_data.last_error = data.error
        input_data.fail_count = (input_data.fail_count or 0) + 1
        if not input_data.fail_since then
            input_data.fail_since = now
        end

    elseif data.psi then
        local handler = dump_psi_info[data.psi]
        if handler then
            if not psi_debug_only[data.psi] or psi_debug_enabled() then
                handler("[" .. input_data.config.name .. "] ", data)
            end
        else
            if psi_debug_enabled() then
                -- Debug-only: not actionable for most users, but useful while troubleshooting PSI parsing.
                -- TOT/TDT/NIT встречаются часто и не являются проблемой сами по себе, поэтому не шумим ими.
                local psi = tostring(data.psi or "")
                if not psi_debug_only[psi] then
                    log.debug("[" .. input_data.config.name .. "] Unknown PSI: " .. psi)
                end
            end
        end

    elseif data.analyze then
        local total = data.total or {}
        input_data.stats = {
            bitrate = total.bitrate,
            cc_errors = total.cc_errors,
            pes_errors = total.pes_errors,
            scrambled = total.scrambled,
            on_air = data.on_air,
            updated_at = os.time(),
        }
        input_data.last_seen_ts = now

        -- Feed observability stream timeseries with lightweight throttled samples.
        -- Write only for the active input to avoid duplicate points per stream bucket.
        local active_id = channel_data.active_input_id or 0
        if (active_id == 0 or active_id == input_id)
            and ai_observability and ai_observability.ingest_stream_sample
            and channel_data and channel_data.config and channel_data.config.id then
            pcall(ai_observability.ingest_stream_sample, channel_data.config.id, {
                ts = now,
                bitrate_kbps = total.bitrate,
                cc_errors = total.cc_errors,
                pes_errors = total.pes_errors,
                on_air = data.on_air == true,
            })
        end

        local ok_det, det_err = pcall(update_input_detectors, channel_data, input_id, input_data, total, now)
        if not ok_det then
            -- Не спамим логами: 1 раз в минуту на input.
            input_data.detector_error_last_ts = input_data.detector_error_last_ts or 0
            if (now - input_data.detector_error_last_ts) >= 60 then
                input_data.detector_error_last_ts = now
                log.warning("[" .. input_data.config.name .. "] detector update failed: " .. tostring(det_err))
            end
        end

        if data.on_air ~= input_data.on_air then
            local analyze_message = "[" .. input_data.config.name .. "] Bitrate:" .. data.total.bitrate .. "Kbit/s"

            if data.on_air == false then
                local m = nil
                if data.total.scrambled then
                    m = " Scrambled"
                else
                    m = " PES:" .. data.total.pes_errors .. " CC:" .. data.total.cc_errors
                end
                log.error(analyze_message .. m)
            else
                log.info(analyze_message)
            end

            input_data.on_air = data.on_air
        end

        if data.on_air == true then
            input_data.last_ok_ts = now
            input_data.ok_since = input_data.ok_since or now
            input_data.fail_since = nil
            input_data.last_error = nil
            input_data.health_reason = nil
            input_data.fail_count = 0
        else
            if not input_data.fail_since then
                input_data.fail_since = now
            end
            input_data.ok_since = nil
            input_data.fail_count = (input_data.fail_count or 0) + 1
            if total.scrambled then
                input_data.last_error = "scrambled"
            elseif (total.pes_errors or 0) > 0 or (total.cc_errors or 0) > 0 then
                input_data.last_error = "cc_pes_errors"
            else
                input_data.last_error = "no_data"
            end
        end
    end
end

-- oooooooooo  ooooooooooo  oooooooo8 ooooooooooo oooooooooo ooooo  oooo ooooooooooo
--  888    888  888    88  888         888    88   888    888 888    88   888    88
--  888oooo88   888ooo8     888oooooo  888ooo8     888oooo88   888  88    888ooo8
--  888  88o    888    oo          888 888    oo   888  88o     88888     888    oo
-- o888o  88o8 o888ooo8888 o88oooo888 o888ooo8888 o888o  88o8    888     o888ooo8888

function start_reserve(channel_data)
    local active_input_id = 0
    for input_id, input_data in ipairs(channel_data.input) do
        if input_data.on_air == true then
            channel_data.transmit:set_upstream(input_data.input.tail:stream())
            log.info("[" .. channel_data.config.name .. "] Active input #" .. input_id)
            active_input_id = input_id
            break
        end
    end

    if active_input_id == 0 then
        local activated = false
        for input_id, input_data in ipairs(channel_data.input) do
            if not input_data.input then
                if channel_init_input(channel_data, input_id) then
                    activated = true
                    break
                end
            end
        end
        if not activated then
            log.error("[" .. channel_data.config.name .. "] Failed to switch to reserve")
        end
    else
        channel_data.active_input_id = active_input_id
        channel_data.delay = channel_data.config.timeout

        for input_id, input_data in ipairs(channel_data.input) do
            if input_data.input and input_id > active_input_id then
                channel_kill_input(channel_data, input_id)
                log.debug("[" .. channel_data.config.name .. "] Destroy input #" .. input_id)
                input_data.on_air = nil
            end
        end
        collectgarbage()
    end
end

local function get_stream_label(channel_data)
    if channel_data and channel_data.config then
        return channel_data.config.id or channel_data.config.name or "stream"
    end
    return "stream"
end

local function emit_stream_alert(channel_data, level, code, message, meta)
    if not (config and config.add_alert) then
        return
    end
    local stream_id = channel_data and channel_data.config and channel_data.config.id or ""
    local payload = meta or {}
    if channel_data and channel_data.config and channel_data.config.name then
        payload.stream_name = channel_data.config.name
    end
    config.add_alert(level, stream_id, code, message or "", payload)
end

local function maybe_emit_input_down(channel_data, input_id, input_data)
    if not input_data then
        return
    end
    local prev_state = input_data.alert_state
    local new_state = input_data.state
    if prev_state == nil then
        input_data.alert_state = new_state
        return
    end
    if prev_state == new_state then
        return
    end
    input_data.alert_state = new_state
    if new_state == "DOWN" and input_id == (channel_data.active_input_id or 0) then
        local stats = input_data.stats or {}
        emit_stream_alert(channel_data, "WARNING", "INPUT_DOWN", "active input down", {
            input_index = input_id - 1,
            reason = input_data.last_error or "",
            active_input_url = input_data.source_url,
            bitrate_kbps = stats.bitrate,
            cc_errors = stats.cc_errors,
            pes_errors = stats.pes_errors,
        })
    end
end

local function maybe_emit_stream_state(channel_data)
    local active_id = channel_data.active_input_id or 0
    local active_input = active_id > 0 and channel_data.input and channel_data.input[active_id] or nil
    local fo = channel_data.failover
    local state = "DOWN"
    if fo and fo.global_state == "INACTIVE" then
        state = "DOWN"
    elseif active_input and active_input.is_ok then
        state = "UP"
    end
    if channel_data.alert_stream_state == nil then
        channel_data.alert_stream_state = state
        return
    end
    if channel_data.alert_stream_state == state then
        return
    end
    channel_data.alert_stream_state = state
    if state == "DOWN" then
        local stats = active_input and active_input.stats or nil
        emit_stream_alert(channel_data, "CRITICAL", "STREAM_DOWN", "no data", {
            active_input_index = active_id > 0 and (active_id - 1) or nil,
            active_input_url = active_input and active_input.source_url or nil,
            no_data_timeout_sec = fo and fo.no_data_timeout or channel_data.config.no_data_timeout_sec,
            bitrate_kbps = stats and stats.bitrate or nil,
            cc_errors = stats and stats.cc_errors or nil,
            pes_errors = stats and stats.pes_errors or nil,
            reason = active_input and active_input.last_error or nil,
        })
    else
        emit_stream_alert(channel_data, "INFO", "STREAM_UP", "recovered", {
            active_input_index = active_id > 0 and (active_id - 1) or nil,
            active_input_url = active_input and active_input.source_url or nil,
            bitrate_kbps = active_input and active_input.stats and active_input.stats.bitrate or nil,
        })
    end
end

local function send_failover_event(channel_data, from_index, to_index, reason)
    local endpoint = setting_string("event_request", "")
    if endpoint == "" then
        return
    end

    local parsed = parse_url(endpoint)
    if not parsed or (parsed.format ~= "http" and parsed.format ~= "https") then
        if channel_data.failover and not channel_data.failover.event_warned then
            log.warning("[stream " .. get_stream_label(channel_data) .. "] invalid event_request: " .. tostring(endpoint))
            channel_data.failover.event_warned = true
        end
        return
    end

    if parsed.format == "https" and not (astra and astra.features and astra.features.ssl) then
        if channel_data.failover and not channel_data.failover.event_warned then
            log.warning("[stream " .. get_stream_label(channel_data) .. "] https not supported for event_request")
            channel_data.failover.event_warned = true
        end
        return
    end

    local port = parsed.port or (parsed.format == "https" and 443 or 80)
    local path = parsed.path or "/"
    local host_header = parsed.host or ""
    if port then
        host_header = host_header .. ":" .. tostring(port)
    end

    local payload = {
        event = "failover_switch",
        stream_id = channel_data.config.id,
        from = from_index,
        to = to_index,
        reason = reason,
        ts = os.time(),
    }
    local body = json.encode(payload)

    http_request({
        host = parsed.host,
        port = port,
        path = path,
        method = "POST",
        ssl = (parsed.format == "https"),
        headers = {
            "Content-Type: application/json",
            "Content-Length: " .. tostring(#body),
            "Host: " .. host_header,
            "Connection: close",
        },
        content = body,
        callback = function(self, response)
            if not response then
                return
            end
            if response.code and response.code >= 400 then
                log.warning("[stream " .. get_stream_label(channel_data) .. "] event_request failed: " ..
                    tostring(response.code))
            end
        end,
    })
end

local channel_audio_fix_on_input_switch

local function mark_hls_discontinuity(channel_data)
    if not channel_data or type(channel_data.output) ~= "table" then
        return
    end
    for _, output_data in ipairs(channel_data.output) do
        if output_data and output_data.config and output_data.config.format == "hls" then
            local out = output_data.output
            if out and out.discontinuity then
                pcall(function() out:discontinuity() end)
            end
        end
    end
end

local function channel_prepare_input(channel_data, input_id, opts)
    opts = opts or {}
    local input_data = channel_data.input[input_id]
    if input_data.input then
        return true
    end

    -- Network/HLS resilience stats callback (used by UI/health).
    if input_data.config then
        input_data.config.on_net_stats = function(state)
            input_data.net = state
            if state then
                if state.last_error and state.last_error ~= "" then
                    input_data.last_error = state.last_error
                    input_data.health_reason = state.last_error
                elseif state.state == "running" then
                    -- Если input восстановился, очищаем "залипший" reason, иначе UI/авто-тюнинг
                    -- видят устаревшую ошибку даже при `on_air=true`.
                    input_data.last_error = nil
                    input_data.health_reason = nil
                end
                if state.state then
                    input_data.health_state = state.state
                end
            end
        end
        input_data.config.on_hls_stats = function(stats)
            input_data.hls = stats
            if stats and stats.state then
                input_data.health_state = stats.state
                if stats.last_error and stats.last_error ~= "" then
                    input_data.health_reason = stats.last_error
                elseif stats.state == "running" then
                    input_data.last_error = nil
                    input_data.health_reason = nil
                end
            end
        end
    end

    local input = init_input(input_data.config)
    if not input or not input.tail then
        input_data.input = nil
        input_data.last_error = "init_failed"
        input_data.fail_count = (input_data.fail_count or 0) + 1
        if not input_data.fail_since then
            input_data.fail_since = os.time()
        end
        return false
    end

    input_data.input = input
    input_data.last_error = nil
    input_data.is_ok = nil
    input_data.on_air = nil
    input_data.ok_since = nil
    input_data.fail_since = nil
    input_data.last_seen_ts = nil
    input_data.last_ok_ts = nil
    input_data.stats = nil
    input_data.fail_count = 0

    local detectors = normalize_input_detectors(input_data.config)
    input_data.detectors_config = detectors

    if input_data.config.no_analyze ~= true then
        -- Важно: если на входе включен carrier/playout (NULL stuffing), анализатор должен смотреть
        -- ДО него, иначе поток будет выглядеть "on_air" даже при полном отсутствии контента.
        local analyze_tail = input_data.input and (input_data.input.analyze_tail or input_data.input.tail) or nil
        local analyze_opts = {
            upstream = analyze_tail and analyze_tail:stream() or input_data.input.tail:stream(),
            name = input_data.config.name,
            cc_limit = input_data.config.cc_limit,
            bitrate_limit = input_data.config.bitrate_limit,
            callback = function(data)
                on_analyze_spts(channel_data, input_id, data)
            end,
        }
        if detectors and detectors.stop_video and detectors.stop_video.mode == "freeze" then
            analyze_opts.video_fingerprint = true
            analyze_opts.video_fingerprint_bytes = 512
        end
        input_data.analyze = analyze(analyze_opts)
    else
        local now = os.time()
        input_data.analyze = nil
        input_data.on_air = true
        input_data.last_seen_ts = now
        input_data.last_ok_ts = now
        input_data.ok_since = input_data.ok_since or now
        input_data.fail_since = nil
        input_data.fail_count = 0
        input_data.last_error = nil
    end

    if opts.probing then
        input_data.probing = true
    end
    if opts.warm then
        input_data.warm = true
    end

    if auth and auth.check_publish and not opts.probing and not opts.warm then
        local format = input_data.config.format or ""
        local allowed = {
            http = true,
            https = true,
            hls = true,
            rtsp = true,
            srt = true,
        }
        if allowed[format] then
            local source_url = input_data.source_url or format_input_url(input_data.config)
            local token = auth.token_from_url and auth.token_from_url(source_url) or nil
            local ip = input_data.config.host or input_data.config.addr or ""
            auth.check_publish({
                stream_id = channel_data.config and channel_data.config.id or "",
                stream_name = channel_data.config and channel_data.config.name or "",
                stream_cfg = channel_data.config,
                proto = format,
                ip = ip,
                token = token,
                uri = source_url or "",
                user_agent = http_user_agent or "Stream",
            }, function(allowed_result)
                if not allowed_result then
                    log.warning("[" .. input_data.config.name .. "] publish denied by backend")
                    input_data.last_error = "auth_publish_denied"
                    channel_kill_input(channel_data, input_id)
                end
            end)
        end
    end

    return true
end

local function channel_activate_input(channel_data, input_id, reason)
    local input_data = channel_data.input[input_id]
    if not input_data then
        return false
    end
    local ok = channel_prepare_input(channel_data, input_id)
    if not ok then
        return false
    end

    channel_data.transmit:set_upstream(input_data.input.tail:stream())

    local prev_id = channel_data.active_input_id or 0
    if prev_id ~= input_id then
        channel_data.active_input_id = input_id
        local now = os.time()
        local from_index = prev_id > 0 and (prev_id - 1) or -1
        local to_index = input_id - 1
        if prev_id > 0 and channel_data.input and channel_data.input[prev_id] then
            stop_silence_probe(channel_data.input[prev_id])
        end
        local from_label = from_index >= 0 and tostring(from_index) or "none"
        log.info("[stream " .. get_stream_label(channel_data) .. "] switch input " ..
            from_label .. " -> " .. tostring(to_index) .. ", reason=" .. tostring(reason))
        if channel_data.failover then
            channel_data.failover.last_switch = {
                from = from_index,
                to = to_index,
                reason = reason,
                ts = now,
            }
        end
        if prev_id > 0 and reason ~= "start" then
            mark_hls_discontinuity(channel_data)
        end
        if prev_id > 0 and reason ~= "start" then
            emit_stream_alert(channel_data, "WARNING", "INPUT_SWITCH", "input switch", {
                from_index = from_index,
                to_index = to_index,
                reason = reason,
            })
        end
        send_failover_event(channel_data, from_index, to_index, reason)
        if channel_audio_fix_on_input_switch then
            channel_audio_fix_on_input_switch(channel_data, prev_id, input_id, reason)
        end
    end

    input_data.probing = nil
    input_data.warm = nil
    input_data.probe_until = nil
    stop_silence_probe(input_data)
    return true
end

local function update_input_health(input_data, now, no_data_timeout)
    if not input_data then
        return false
    end

    local ok = false
    if input_data.input then
        if input_data.analyze then
            ok = input_data.on_air == true
            if input_data.last_seen_ts and (now - input_data.last_seen_ts) > no_data_timeout then
                ok = false
            end
        else
            ok = true
            input_data.last_seen_ts = now
        end
    end

    if ok then
        input_data.is_ok = true
        input_data.ok_since = input_data.ok_since or now
        input_data.fail_since = nil
        input_data.last_ok_ts = now
    else
        input_data.is_ok = false
        input_data.ok_since = nil
        if not input_data.fail_since then
            input_data.fail_since = now
        end
    end

    -- Network/HLS health overrides: degraded/offline should trigger failover.
    local health_state = "online"
    if input_data.net and input_data.net.state and input_data.net.state ~= "running" and input_data.net.state ~= "init" then
        health_state = input_data.net.state
    end
    if input_data.hls and input_data.hls.state and input_data.hls.state ~= "running" and input_data.hls.state ~= "init" then
        health_state = input_data.hls.state
    end
    input_data.health_state = health_state
    if health_state ~= "online" and health_state ~= "running" and health_state ~= "init" then
        input_data.is_ok = false
        if not input_data.fail_since then
            input_data.fail_since = now
        end
    end

    return input_data.is_ok
end

local function update_input_state(channel_data, input_id, input_data)
    local state = "DOWN"
    if input_id == channel_data.active_input_id then
        state = input_data.is_ok and "ACTIVE" or "DOWN"
    elseif input_data.input then
        if input_data.probing then
            state = "PROBING"
        elseif input_data.warm then
            state = input_data.is_ok and "STANDBY" or "PROBING"
        else
            if input_data.is_ok then
                state = (channel_data.failover and is_active_backup_mode(channel_data.failover.mode)) and "STANDBY" or "PROBING"
            else
                state = "DOWN"
            end
        end
    else
        local fo = channel_data.failover
        if fo and fo.mode == "passive" then
            if fo.passive_state == "FAILOVER_SEARCH" then
                state = "DOWN"
            else
                state = "UNKNOWN"
            end
        else
            state = "DOWN"
        end
    end
    input_data.state = state
end

local function pick_next_input(channel_data, active_id, prefer_ok)
    local total = #channel_data.input
    if total == 0 then
        return nil
    end

    for offset = 1, total do
        local idx = ((active_id - 1 + offset) % total) + 1
        local input_data = channel_data.input[idx]
        if input_data then
            if not prefer_ok or input_data.is_ok then
                return idx
            end
        end
    end

    return nil
end

local function activate_next_available(channel_data, active_id, reason)
    local total = #channel_data.input
    if total == 0 then
        return false
    end

    for pass = 1, 2 do
        local prefer_ok = pass == 1
        for offset = 1, total do
            local idx = ((active_id - 1 + offset) % total) + 1
            local input_data = channel_data.input[idx]
            if input_data and (not prefer_ok or input_data.is_ok) then
                if channel_activate_input(channel_data, idx, reason) then
                    return true
                end
            end
        end
    end

    return false
end

local function schedule_probe(channel_data, now, keep_connected)
    local fo = channel_data.failover
    if not fo or not is_active_backup_mode(fo.mode) then
        return
    end
    if fo.probe_interval <= 0 then
        return
    end
    if fo.next_probe_ts and now < fo.next_probe_ts then
        return
    end

    for _, input_data in ipairs(channel_data.input) do
        if input_data.probing and input_data.input then
            return
        end
    end

    local candidates = {}
    for idx, input_data in ipairs(channel_data.input) do
        if not keep_connected[idx] and not input_data.input then
            table.insert(candidates, idx)
        end
    end
    if #candidates == 0 then
        fo.next_probe_ts = now + fo.probe_interval
        return
    end

    local cursor = fo.probe_cursor or 1
    if cursor > #candidates then
        cursor = 1
    end
    local probe_id = candidates[cursor]
    fo.probe_cursor = cursor + 1

    if channel_prepare_input(channel_data, probe_id, { probing = true }) then
        local input_data = channel_data.input[probe_id]
        input_data.probing = true
        input_data.probe_until = now + math.max(fo.no_data_timeout, fo.stable_ok)
        keep_connected[probe_id] = true
    end

    fo.next_probe_ts = now + fo.probe_interval
end

local function update_connections(channel_data, now)
    local fo = channel_data.failover
    if not fo then
        return
    end

    local keep_connected = {}
    local active_id = channel_data.active_input_id or 0
    if active_id > 0 then
        keep_connected[active_id] = true
    end

    if is_active_backup_mode(fo.mode) and fo.warm_max > 0 and fo.global_state ~= "INACTIVE" then
        local count = 0
        for idx, _ in ipairs(channel_data.input) do
            if idx ~= active_id then
                keep_connected[idx] = true
                count = count + 1
                if count >= fo.warm_max then
                    break
                end
            end
        end
    elseif fo.mode == "passive" then
        -- passive mode keeps only the active input
    end

    for idx, input_data in ipairs(channel_data.input) do
        if input_data.probing and input_data.probe_until and input_data.probe_until > now then
            keep_connected[idx] = true
        elseif input_data.probing and input_data.probe_until and input_data.probe_until <= now then
            input_data.probing = nil
            input_data.probe_until = nil
        end
    end

    schedule_probe(channel_data, now, keep_connected)

    for idx, input_data in ipairs(channel_data.input) do
        if keep_connected[idx] then
            local ok = channel_prepare_input(channel_data, idx, {
                warm = is_active_backup_mode(fo.mode) and idx ~= active_id,
            })
            if ok then
                input_data.warm = (is_active_backup_mode(fo.mode) and idx ~= active_id)
            else
                input_data.warm = nil
            end
        else
            if input_data.input then
                channel_kill_input(channel_data, idx)
            end
            input_data.warm = nil
            input_data.probing = nil
            input_data.probe_until = nil
        end
    end
end

local function channel_failover_tick(channel_data)
    local fo = channel_data.failover
    if not fo or fo.paused then
        return
    end

    local now = os.time()
    local total = #channel_data.input
    if total == 0 then
        return
    end

    local passive_mode = fo.mode == "passive"
    if passive_mode then
        local active_id = channel_data.active_input_id or 0
        for idx, input_data in ipairs(channel_data.input) do
            if idx == active_id or input_data.input then
                update_input_health(input_data, now, fo.no_data_timeout)
            else
                input_data.is_ok = nil
                input_data.ok_since = nil
                input_data.fail_since = nil
            end
        end
    else
        for _, input_data in ipairs(channel_data.input) do
            update_input_health(input_data, now, fo.no_data_timeout)
        end
    end

    if not fo.enabled then
        for idx, input_data in ipairs(channel_data.input) do
            update_input_state(channel_data, idx, input_data)
            maybe_emit_input_down(channel_data, idx, input_data)
        end
        maybe_emit_stream_state(channel_data)
        return
    end

    local stop_on_inactive = fo.mode == "active_stop_if_all_inactive"
    local active_mode = is_active_backup_mode(fo.mode)
    local any_ok = false
    if stop_on_inactive then
        for _, input_data in ipairs(channel_data.input) do
            if input_data.is_ok then
                any_ok = true
                break
            end
        end
    end

    if stop_on_inactive then
        if not any_ok then
            fo.inactive_since = fo.inactive_since or now
            if (now - fo.inactive_since) >= fo.stop_if_all_inactive_sec then
                if fo.global_state ~= "INACTIVE" then
                    fo.global_state = "INACTIVE"
                    fo.return_pending = nil
                    for idx, input_data in ipairs(channel_data.input) do
                        if input_data.input then
                            channel_kill_input(channel_data, idx)
                        end
                        input_data.warm = nil
                        input_data.probing = nil
                        input_data.probe_until = nil
                    end
                    channel_data.active_input_id = 0
                end
            end
        else
            fo.inactive_since = nil
            if fo.global_state == "INACTIVE" then
                fo.global_state = "RUNNING"
            end
        end
    else
        fo.inactive_since = nil
        fo.global_state = "RUNNING"
    end

    if fo.global_state == "INACTIVE" then
        update_connections(channel_data, now)
        for idx, input_data in ipairs(channel_data.input) do
            update_input_state(channel_data, idx, input_data)
            maybe_emit_input_down(channel_data, idx, input_data)
        end
        maybe_emit_stream_state(channel_data)
        return
    end

    local active_id = channel_data.active_input_id or 0
    local initial_ready = now >= (fo.started_at + fo.initial_delay)

    if active_id == 0 then
        activate_next_available(channel_data, 0, "start")
        active_id = channel_data.active_input_id or 0
    end

    if passive_mode then
        fo.return_pending = nil
        if active_id == 0 then
            if fo.passive_state ~= "FAILOVER_SEARCH" then
                log.info("[stream " .. get_stream_label(channel_data) .. "] passive: no active input, searching")
            end
            fo.passive_state = "FAILOVER_SEARCH"
            if not fo.next_probe_ts or now >= fo.next_probe_ts then
                local switched = activate_next_available(channel_data, 0, "start")
                if not switched and fo.probe_interval > 0 then
                    fo.next_probe_ts = now + fo.probe_interval
                end
            end
            update_connections(channel_data, now)
            for idx, input_data in ipairs(channel_data.input) do
                update_input_state(channel_data, idx, input_data)
                maybe_emit_input_down(channel_data, idx, input_data)
            end
            maybe_emit_stream_state(channel_data)
            return
        end
        local active_input = active_id > 0 and channel_data.input[active_id] or nil
        local active_ok = active_input and active_input.is_ok
        if active_ok then
            if fo.passive_state ~= "RUNNING_OK" then
                log.info("[stream " .. get_stream_label(channel_data) .. "] passive: input #" ..
                    tostring(active_id) .. " OK, staying until fault")
            end
            fo.passive_state = "RUNNING_OK"
            fo.passive_cycle_start_id = nil
            fo.next_probe_ts = nil
        else
            if fo.passive_state ~= "FAILOVER_SEARCH" then
                local reason = active_input and active_input.last_error or "no_data"
                log.info("[stream " .. get_stream_label(channel_data) .. "] passive: active input fault (" ..
                    tostring(reason) .. "), searching next input")
            end
            fo.passive_state = "FAILOVER_SEARCH"
            local down_for = 0
            if active_input and active_input.fail_since then
                down_for = now - active_input.fail_since
            end
            local allow_switch = initial_ready or active_id ~= 1
            if active_id > 0 and allow_switch and down_for >= fo.start_delay then
                if fo.next_probe_ts and now < fo.next_probe_ts then
                    -- wait for next probe window
                else
                    local prev_id = active_id
                    local switched = activate_next_available(channel_data, active_id, "no_data_timeout")
                    local new_id = channel_data.active_input_id or 0
                    if switched then
                        if not fo.passive_cycle_start_id then
                            fo.passive_cycle_start_id = (prev_id > 0) and prev_id or new_id
                        end
                        if fo.passive_cycle_start_id and new_id == fo.passive_cycle_start_id then
                            if fo.probe_interval > 0 then
                                fo.next_probe_ts = now + fo.probe_interval
                            end
                            fo.passive_cycle_start_id = nil
                        end
                    elseif fo.probe_interval > 0 then
                        fo.next_probe_ts = now + fo.probe_interval
                    end
                end
            end
        end

        update_connections(channel_data, now)
        for idx, input_data in ipairs(channel_data.input) do
            update_input_state(channel_data, idx, input_data)
        end
        return
    end

    if active_id > 0 then
        local active_input = channel_data.input[active_id]
        local active_ok = active_input and active_input.is_ok
        local down_for = 0
        if active_input and active_input.fail_since then
            down_for = now - active_input.fail_since
        end

        local allow_switch = initial_ready or active_id ~= 1
        if not active_ok and allow_switch then
            local delay = fo.start_delay
            if down_for >= delay then
                activate_next_available(channel_data, active_id, "no_data_timeout")
            end
        end
    end

    if active_id > 1 and active_mode then
        local primary = channel_data.input[1]
        if primary and primary.is_ok and primary.ok_since and
            (now - primary.ok_since) >= fo.stable_ok then
            if not fo.return_pending then
                fo.return_pending = {
                    target = 1,
                    ready_at = now + fo.return_delay,
                    reason = "return_primary",
                }
            end
        else
            fo.return_pending = nil
        end

        if fo.return_pending and now >= fo.return_pending.ready_at then
            channel_activate_input(channel_data, fo.return_pending.target, fo.return_pending.reason)
            fo.return_pending = nil
        end
    else
        fo.return_pending = nil
    end

    update_connections(channel_data, now)

    for idx, input_data in ipairs(channel_data.input) do
        update_input_state(channel_data, idx, input_data)
        maybe_emit_input_down(channel_data, idx, input_data)
    end
    maybe_emit_stream_state(channel_data)
end

local failover_housekeeping_timer = nil

local function use_aggregated_stream_timers()
    return setting_bool("performance_aggregate_stream_timers", false)
end

local function ensure_failover_housekeeping_timer()
    if failover_housekeeping_timer then
        return
    end
    failover_housekeeping_timer = timer({
        interval = 1,
        callback = function(self)
            local any = false
            for _, channel_data in pairs(channel_list or {}) do
                if channel_data and channel_data.__need_failover_tick then
                    any = true
                    channel_failover_tick(channel_data)
                end
            end
            if not any then
                self:close()
                failover_housekeeping_timer = nil
            end
        end,
    })
end

local function ensure_failover_timer(channel_data)
    if not channel_data.failover then
        return
    end
    if use_aggregated_stream_timers() then
        channel_data.__need_failover_tick = true
        ensure_failover_housekeeping_timer()
        return
    end
    if channel_data.failover_timer then
        return
    end
    channel_data.failover_timer = timer({
        interval = 1,
        callback = function(self)
            channel_failover_tick(channel_data)
        end,
    })
end

local function channel_pause_failover(channel_data)
    if not channel_data.failover or not channel_data.failover.enabled then
        return
    end
    channel_data.failover.paused = true
    channel_data.failover.return_pending = nil
    channel_data.__need_failover_tick = nil
end

local function channel_resume_failover(channel_data)
    if not channel_data.failover or not channel_data.failover.enabled then
        return
    end
    channel_data.failover.paused = false
    channel_data.failover.started_at = os.time()
    channel_data.failover.next_probe_ts = channel_data.failover.started_at
    channel_data.failover.passive_state = nil
    channel_data.failover.passive_cycle_start_id = nil
    ensure_failover_timer(channel_data)
end

-- ooooo oooo   oooo oooooooooo ooooo  oooo ooooooooooo
--  888   8888o  88   888    888 888    88  88  888  88
--  888   88 888o88   888oooo88  888    88      888
--  888   88   8888   888        888    88      888
-- o888o o88o    88  o888o        888oo88      o888o

function channel_init_input(channel_data, input_id)
    return channel_prepare_input(channel_data, input_id, {})
end

function channel_kill_input(channel_data, input_id)
    local input_data = channel_data.input[input_id]

    -- TODO: kill additional modules

    input_data.analyze = nil
    input_data.stats = nil
    input_data.on_air = nil
    input_data.is_ok = nil
    input_data.ok_since = nil
    input_data.fail_since = nil
    input_data.last_seen_ts = nil
    input_data.probing = nil
    input_data.warm = nil
    input_data.probe_until = nil

    if input_data.input then
        kill_input(input_data.input)
        input_data.input = nil
    end
end

--   ooooooo  ooooo  oooo ooooooooooo oooooooooo ooooo  oooo ooooooooooo
-- o888   888o 888    88  88  888  88  888    888 888    88  88  888  88
-- 888     888 888    88      888      888oooo88  888    88      888
-- 888o   o888 888    88      888      888        888    88      888
--   88ooo88    888oo88      o888o    o888o        888oo88      o888o

init_output_option = {}
kill_output_option = {}

init_output_option.biss = function(channel_data, output_id)
    local output_data = channel_data.output[output_id]

    if biss_encrypt == nil then
        log.error("[" .. output_data.config.name .. "] biss_encrypt module is not found")
        return nil
    end

    output_data.biss = biss_encrypt({
        upstream = channel_data.tail:stream(),
        key = output_data.config.biss,
    })
    channel_data.tail = output_data.biss
end

kill_output_option.biss = function(channel_data, output_id)
    local output_data = channel_data.output[output_id]
    output_data.biss = nil
end

init_output_module = {}
kill_output_module = {}

function channel_init_output(channel_data, output_id)
    local output_data = channel_data.output[output_id]

    for key,_ in pairs(output_data.config) do
        if init_output_option[key] then
            init_output_option[key](channel_data, output_id)
        end
    end

    init_output_module[output_data.config.format](channel_data, output_id)
end

function channel_kill_output(channel_data, output_id)
    local output_data = channel_data.output[output_id]

    for key,_ in pairs(output_data.config) do
        if kill_output_option[key] then
            kill_output_option[key](channel_data, output_id)
        end
    end

    kill_output_module[output_data.config.format](channel_data, output_id)
    channel_data.output[output_id] = { config = output_data.config, }
end

--   ooooooo            ooooo  oooo ooooooooo  oooooooooo
-- o888   888o           888    88   888    88o 888    888
-- 888     888 ooooooooo 888    88   888    888 888oooo88
-- 888o   o888           888    88   888    888 888
--   88ooo88              888oo88   o888ooo88  o888o

init_output_module.udp = function(channel_data, output_id)
    local output_data = channel_data.output[output_id]
    local localaddr = resolve_output_localaddr(output_data.config)
    output_data.output = udp_output({
        upstream = channel_data.tail:stream(),
        addr = output_data.config.addr,
        port = output_data.config.port,
        ttl = output_data.config.ttl,
        localaddr = localaddr,
        socket_size = output_data.config.socket_size,
        rtp = (output_data.config.format == "rtp"),
        sync = output_data.config.sync,
        cbr = output_data.config.cbr,
    })
end

kill_output_module.udp = function(channel_data, output_id)
    local output_data = channel_data.output[output_id]
    output_data.output = nil
end

init_output_module.rtp = function(channel_data, output_id)
    init_output_module.udp(channel_data, output_id)
end

kill_output_module.rtp = function(channel_data, output_id)
    kill_output_module.udp(channel_data, output_id)
end

local function append_srt_args(args, extra)
    if type(extra) == "table" then
        for _, value in ipairs(extra) do
            args[#args + 1] = tostring(value)
        end
    elseif type(extra) == "string" and extra ~= "" then
        args[#args + 1] = extra
    end
end

local function build_srt_url(conf)
    local function strip(url)
        if not url or url == "" then
            return url
        end
        local hash = url:find("#")
        if hash then
            return url:sub(1, hash - 1)
        end
        return url
    end

    if conf.url and conf.url ~= "" then
        return strip(conf.url)
    end
    if conf.source_url and conf.source_url ~= "" then
        return strip(conf.source_url)
    end
    local host = conf.host or conf.addr
    local port = conf.port
    if not host or not port then
        return nil
    end
    local url = "srt://" .. host .. ":" .. tostring(port)
    if conf.query and conf.query ~= "" then
        url = url .. "?" .. conf.query
    end
    return url
end

local function stop_srt_process(output_data)
    if output_data.proc then
        output_data.proc:terminate()
        output_data.proc:kill()
        output_data.proc:close()
        output_data.proc = nil
    end
end

init_output_module.srt = function(channel_data, output_id)
    local output_data = channel_data.output[output_id]
    local conf = output_data.config

    if not process or type(process.spawn) ~= "function" then
        log.error("[" .. conf.name .. "] process module not available")
        return
    end

    local bridge_port = tonumber(conf.bridge_port)
    if not bridge_port then
        log.error("[" .. conf.name .. "] bridge_port is required")
        return
    end

    local srt_url = build_srt_url(conf)
    if not srt_url then
        log.error("[" .. conf.name .. "] srt url is required")
        return
    end

    local bridge_addr = conf.bridge_addr or "127.0.0.1"
    local pkt_size = tonumber(conf.bridge_pkt_size) or 1316
    local udp_url = "udp://" .. bridge_addr .. ":" .. tostring(bridge_port)
    if pkt_size > 0 then
        udp_url = udp_url .. "?pkt_size=" .. tostring(pkt_size)
    end

    local bin = resolve_tool_path("ffmpeg", {
        setting_key = "ffmpeg_path",
        env_key = "ASTRA_FFMPEG_PATH",
        prefer = conf.bridge_bin,
    })
    local args = {
        bin,
        "-hide_banner",
        "-nostdin",
        "-loglevel",
        conf.bridge_log_level or "warning",
    }
    append_srt_args(args, conf.bridge_input_args)
    args[#args + 1] = "-i"
    args[#args + 1] = udp_url
    args[#args + 1] = "-c"
    args[#args + 1] = "copy"
    args[#args + 1] = "-f"
    args[#args + 1] = "mpegts"
    append_srt_args(args, conf.bridge_output_args)
    args[#args + 1] = srt_url

    local ok, proc = pcall(process.spawn, args)
    if not ok or not proc then
        log.error("[" .. conf.name .. "] bridge spawn failed")
        return
    end

    output_data.proc = proc
    output_data.proc_args = args
    output_data.output = udp_output({
        upstream = channel_data.tail:stream(),
        addr = bridge_addr,
        port = bridge_port,
        ttl = conf.bridge_ttl or conf.ttl,
        localaddr = conf.bridge_localaddr or conf.localaddr,
        socket_size = tonumber(conf.bridge_socket_size) or conf.socket_size,
        rtp = false,
        sync = conf.sync,
        cbr = conf.cbr,
    })
end

kill_output_module.srt = function(channel_data, output_id)
    local output_data = channel_data.output[output_id]
    stop_srt_process(output_data)
    output_data.proc_args = nil
    output_data.output = nil
end

--   ooooooo            ooooooooooo ooooo ooooo       ooooooooooo
-- o888   888o           888    88   888   888         888    88
-- 888     888 ooooooooo 888oo8      888   888         888ooo8
-- 888o   o888           888         888   888      o  888    oo
--   88ooo88            o888o       o888o o888ooooo88 o888ooo8888

init_output_module.file = function(channel_data, output_id)
    local output_data = channel_data.output[output_id]
    output_data.output = file_output({
        upstream = channel_data.tail:stream(),
        filename = output_data.config.filename,
        m2ts = output_data.config.m2ts,
        buffer_size = output_data.config.buffer_size,
        aio = output_data.config.aio,
        directio = output_data.config.directio,
    })
end

kill_output_module.file = function(channel_data, output_id)
    local output_data = channel_data.output[output_id]
    output_data.output = nil
end

--   ooooooo            ooooo ooooo ooooooooooo ooooooooooo oooooooooo
-- o888   888o           888   888  88  888  88 88  888  88  888    888
-- 888     888 ooooooooo 888ooo888      888         888      888oooo88
-- 888o   o888           888   888      888         888      888
--   88ooo88            o888o o888o    o888o       o888o    o888o

http_output_client_list = {}
http_output_instance_list = {}
http_output_keepalive = nil -- instance ids to keep open during refresh

local function is_transcode_stream(cfg)
    if type(cfg) ~= "table" then
        return false
    end
    local stype = tostring(cfg.type or ""):lower()
    return stype == "transcode" or stype == "ffmpeg"
end

local function normalize_stream_list(value)
    if type(value) == "string" then
        return { value }
    end
    if type(value) == "table" then
        return value
    end
    return nil
end

local function https_bridge_enabled(entry)
    local function truthy(v)
        return v == true or v == 1 or v == "1" or v == "true" or v == "yes" or v == "on"
    end
    if entry and (truthy(entry.https_bridge) or truthy(entry.bridge) or truthy(entry.ffmpeg)) then
        return true
    end
    return setting_bool("https_bridge_enabled", false)
end

local function https_native_supported()
    return astra and astra.features and astra.features.ssl
end

local function resolve_io_config(entry, is_input)
    if type(entry) == "string" then
        return parse_url(entry)
    end
    if type(entry) ~= "table" then
        return nil
    end
    if entry.format then
        return entry
    end
    if entry.url and type(entry.url) == "string" then
        return parse_url(entry.url)
    end
    if is_input then
        local url = format_input_url(entry)
        if url then
            return parse_url(url)
        end
    end
    return nil
end

local function check_http_output_port(output_config, opts)
    local host = output_config.host or output_config.addr or "0.0.0.0"
    if host == "" then
        host = "0.0.0.0"
    end
    local port = tonumber(output_config.port)
    if not port then
        return false, "http output port is required"
    end
    if config and config.get_setting then
        local server_port = tonumber(config.get_setting("http_port"))
        if server_port and port == server_port then
            return false, "http output port conflicts with http_port (" .. tostring(server_port) .. ")"
        end
        local play_port = tonumber(config.get_setting("http_play_port"))
        if play_port and port == play_port then
            return false, "http output port conflicts with http_play_port (" .. tostring(play_port) .. ")"
        end
    end
    local instance_id = host .. ":" .. port
    if http_output_instance_list[instance_id] then
        return true
    end
    if utils and utils.can_bind then
        local ok, err = utils.can_bind(host, port)
        if not ok then
            return false, "http output port is in use: " .. host .. ":" .. port .. (err and (" (" .. err .. ")") or "")
        end
    end
    return true
end

local function check_port_range(port, label)
    local value = tonumber(port)
    if not value then
        return nil, label .. " port is required"
    end
    if value < 1 or value > 65535 then
        return nil, label .. " port must be between 1 and 65535"
    end
    return value
end

local function require_output_path(path, label)
    if not path or path == "" then
        return nil, label .. " path is required"
    end
    return true
end

local function validate_output_entry(output_config, stream_config, opts)
    local format = tostring(output_config.format or ""):lower()
    if format == "http" then
        local ok, err = check_http_output_port(output_config, opts)
        if not ok then
            return nil, err
        end
        ok, err = check_port_range(output_config.port, "http output")
        if not ok then
            return nil, err
        end
        ok, err = require_output_path(output_config.path, "http output")
        if not ok then
            return nil, err
        end
        return true
    end
    if format == "udp" or format == "rtp" then
        local addr = output_config.addr or output_config.host
        if not addr or addr == "" then
            return nil, format .. " output addr is required"
        end
        local ok, err = check_port_range(output_config.port, format .. " output")
        if not ok then
            return nil, err
        end
        return true
    end
    if format == "srt" then
        local ok, err = check_port_range(output_config.bridge_port, "srt bridge")
        if not ok then
            return nil, err
        end
        local srt_url = build_srt_url(output_config)
        if not srt_url then
            return nil, "srt url is required"
        end
        return true
    end
    if format == "file" then
        local filename = output_config.filename or output_config.path
        if not filename or tostring(filename) == "" then
            return nil, "file output filename is required"
        end
        return true
    end
    if format == "np" then
        local host = output_config.host or output_config.addr
        if not host or host == "" then
            return nil, "np output host is required"
        end
        local ok, err = check_port_range(output_config.port, "np output")
        if not ok then
            return nil, err
        end
        ok, err = require_output_path(output_config.path, "np output")
        if not ok then
            return nil, err
        end
        return true
    end
    if format == "hls" then
        local storage = output_config.storage
        if storage == nil or storage == "" then
            storage = setting_string("hls_storage", "disk")
        end
        if storage ~= "memfd" and (not output_config.path or output_config.path == "") then
            local stream_id = tostring(stream_config.id or stream_config.name or "")
            local hls_dir = setting_string("hls_dir", "")
            if hls_dir == "" or stream_id == "" then
                return nil, "hls output requires path or hls_dir"
            end
        end
        return true
    end
    return true
end

local function validate_string_list(value, label)
    if value == nil then
        return true
    end
    local t = type(value)
    if t == "string" or t == "table" then
        return true
    end
    return nil, label .. " must be string or array"
end

local function softcam_is_truthy(value)
    return value == true or value == 1 or value == "1" or value == "true" or value == "yes" or value == "on"
end

local function normalize_hex_string(value)
    if value == nil then
        return nil
    end
    local v = tostring(value or ""):gsub("%s+", "")
    if v == "" then
        return nil
    end
    if v:sub(1, 2):lower() == "0x" then
        v = v:sub(3)
    end
    return v
end

local function validate_softcam_entry(entry)
    if type(entry) ~= "table" then
        return false, "softcam entry is not an object"
    end
    if entry.enable == false or entry.enabled == false then
        return false, "softcam disabled"
    end
    local stype = tostring(entry.type or "newcamd"):lower()
    if stype ~= "newcamd" then
        return false, "unsupported type: " .. tostring(entry.type or "")
    end
    local host = tostring(entry.host or "")
    if host == "" then
        return false, "host is required"
    end
    local port = tonumber(entry.port or 0) or 0
    if port <= 0 then
        return false, "port is required"
    end
    local user = tostring(entry.user or "")
    if user == "" then
        return false, "user is required"
    end
    local pass = entry.pass
    if pass == nil then
        pass = entry.password
    end
    if pass == nil or tostring(pass) == "" then
        return false, "pass is required"
    end
    local key = normalize_hex_string(entry.key)
    if key and (not key:match("^[0-9a-fA-F]+$") or #key ~= 28) then
        return false, "key must be 28 hex chars"
    end
    local caid = normalize_hex_string(entry.caid)
    if caid and (not caid:match("^[0-9a-fA-F]+$") or #caid ~= 4) then
        return false, "caid must be 4 hex chars"
    end
    return true
end

local function build_softcam_index()
    if not config or not config.get_setting then
        return {}
    end
    local list = config.get_setting("softcam")
    if type(list) ~= "table" then
        return {}
    end
    local out = {}
    for _, entry in ipairs(list) do
        if type(entry) == "table" then
            local id = entry.id
            if id ~= nil and tostring(id) ~= "" then
                out[tostring(id)] = entry
            end
        end
    end
    return out
end

local function extract_cam_value(item, key)
    if type(item) == "string" then
        local parsed = parse_url(item)
        if parsed then
            return parsed[key]
        end
        return nil
    end
    if type(item) == "table" then
        if item[key] ~= nil then
            return item[key]
        end
        if type(item.url) == "string" then
            local parsed = parse_url(item.url)
            if parsed then
                return parsed[key]
            end
        end
    end
    return nil
end

local function validate_input_softcam(items)
    if type(items) ~= "table" then
        return true
    end
    local index = build_softcam_index()
    local has_index = (next(index) ~= nil)
    for idx, entry in ipairs(items) do
        local cam = extract_cam_value(entry, "cam")
        if has_index and cam ~= nil and not softcam_is_truthy(cam) then
            local cam_id = tostring(cam)
            local softcam_entry = index[cam_id]
            if not softcam_entry then
                return nil, "cam \"" .. cam_id .. "\" not found (input #" .. tostring(idx) .. ")"
            end
            local ok, err = validate_softcam_entry(softcam_entry)
            if not ok then
                return nil, "cam \"" .. cam_id .. "\" invalid: " .. tostring(err)
            end
        end
        local cam_backup = extract_cam_value(entry, "cam_backup")
        if has_index and cam_backup ~= nil and not softcam_is_truthy(cam_backup) then
            local cam_id = tostring(cam_backup)
            local softcam_entry = index[cam_id]
            if not softcam_entry then
                return nil, "cam_backup \"" .. cam_id .. "\" not found (input #" .. tostring(idx) .. ")"
            end
            local ok, err = validate_softcam_entry(softcam_entry)
            if not ok then
                return nil, "cam_backup \"" .. cam_id .. "\" invalid: " .. tostring(err)
            end
        end

        local cam_backup_mode = extract_cam_value(entry, "cam_backup_mode")
        if cam_backup_mode ~= nil and cam_backup_mode ~= true then
            local mode = tostring(cam_backup_mode):lower()
            if mode ~= "race" and mode ~= "hedge" and mode ~= "failover" then
                return nil, "cam_backup_mode must be race|hedge|failover (input #" .. tostring(idx) .. ")"
            end
        end

        local hedge = extract_cam_value(entry, "cam_backup_hedge_ms")
        if hedge == nil then
            hedge = extract_cam_value(entry, "dual_cam_hedge_ms")
        end
        if hedge ~= nil and hedge ~= true then
            local n = tonumber(hedge)
            if not n or n < 0 or n > 500 then
                return nil, "cam_backup_hedge_ms must be in range 0..500 (input #" .. tostring(idx) .. ")"
            end
        end

        local prefer_primary = extract_cam_value(entry, "cam_prefer_primary_ms")
        if prefer_primary ~= nil and prefer_primary ~= true then
            local n = tonumber(prefer_primary)
            if not n or n < 0 or n > 500 then
                return nil, "cam_prefer_primary_ms must be in range 0..500 (input #" .. tostring(idx) .. ")"
            end
        end
    end
    return true
end

local function truthy_input_option(value)
    if value == true then
        return true
    end
    if value == false then
        return false
    end
    if value == 1 or value == "1" then
        return true
    end
    if value == 0 or value == "0" then
        return false
    end
    local s = tostring(value or ""):lower()
    if s == "" then
        return false
    end
    if s == "true" or s == "yes" or s == "on" then
        return true
    end
    if s == "false" or s == "no" or s == "off" then
        return false
    end
    return nil
end

local function validate_input_detectors(parsed, idx)
    if type(parsed) ~= "table" then
        return true
    end
    local function fail(msg)
        return nil, "input #" .. tostring(idx) .. " " .. msg
    end

    local no_audio = parsed.no_audio_on
    if no_audio ~= nil then
        if no_audio == true then
            -- ok, default timeout
        else
            local timeout = tonumber(no_audio)
            if not timeout or timeout < 1 then
                return fail("no_audio_on must be >= 1")
            end
        end
    end

    local stop_video = parsed.stop_video
    if stop_video ~= nil then
        local mode = tostring(stop_video):lower()
        local truth = truthy_input_option(stop_video)
        if mode ~= "freeze" and truth == nil then
            return fail("stop_video must be on/off/freeze")
        end
        local timeout = tonumber(parsed.stop_video_timeout_sec or parsed.stop_video_timeout)
        if timeout ~= nil and timeout < 1 then
            return fail("stop_video_timeout_sec must be >= 1")
        end
        local freeze = tonumber(parsed.stop_video_freeze_sec)
        if mode == "freeze" and freeze ~= nil and freeze < 1 then
            return fail("stop_video_freeze_sec must be >= 1")
        end
    end

    local detect_av = parsed.detect_av
    if detect_av ~= nil then
        local truth = truthy_input_option(detect_av)
        if truth == nil then
            return fail("detect_av must be on/off")
        end
        local threshold = tonumber(parsed.detect_av_threshold_ms)
        if threshold ~= nil and threshold < 1 then
            return fail("detect_av_threshold_ms must be >= 1")
        end
        local hold = tonumber(parsed.detect_av_hold_sec)
        if hold ~= nil and hold < 1 then
            return fail("detect_av_hold_sec must be >= 1")
        end
        local stable = tonumber(parsed.detect_av_stable_sec)
        if stable ~= nil and stable < 1 then
            return fail("detect_av_stable_sec must be >= 1")
        end
        local resend = tonumber(parsed.detect_av_resend_interval_sec)
        if resend ~= nil and resend < 1 then
            return fail("detect_av_resend_interval_sec must be >= 1")
        end
    end

    local silence = parsed.silencedetect
    local silence_duration = tonumber(parsed.silencedetect_duration or parsed.silence_duration)
    local silence_interval = tonumber(parsed.silencedetect_interval or parsed.silence_interval)
    local silence_noise = tonumber(parsed.silencedetect_noise or parsed.silence_noise)
    if silence ~= nil or silence_duration ~= nil or silence_interval ~= nil or silence_noise ~= nil then
        if silence ~= nil then
            local truth = truthy_input_option(silence)
            if truth == nil then
                return fail("silencedetect must be on/off")
            end
        end
        if silence_duration ~= nil and silence_duration < 1 then
            return fail("silencedetect_duration must be >= 1")
        end
        if silence_interval ~= nil and silence_interval < 1 then
            return fail("silencedetect_interval must be >= 1")
        end
        if silence_noise ~= nil and (silence_noise > 0 or silence_noise < -120) then
            return fail("silencedetect_noise must be between -120 and 0")
        end
    end

    return true
end

function validate_stream_config(cfg, opts)
    if type(cfg) ~= "table" then
        return nil, "stream config is required"
    end

    local ok, err = validate_string_list(cfg.map, "map")
    if not ok then
        return nil, err
    end
    ok, err = validate_string_list(cfg.filter, "filter")
    if not ok then
        return nil, err
    end
    ok, err = validate_string_list(cfg["filter~"], "filter~")
    if not ok then
        return nil, err
    end

    local is_transcode = is_transcode_stream(cfg)
    local is_mpts = cfg.mpts == true
    local inputs = normalize_stream_list(cfg.input)
    local ok_cam, cam_err = validate_input_softcam(inputs)
    if not ok_cam then
        return nil, cam_err or "invalid cam reference"
    end

    if is_mpts then
        local services = normalize_mpts_services(cfg.mpts_services)
        if #services == 0 then
            if not inputs or #inputs == 0 then
                return nil, "at least one MPTS service input is required"
            end
            services = {}
            for _, entry in ipairs(inputs) do
                table.insert(services, { input = entry })
            end
        end
        local mpts_config = type(cfg.mpts_config) == "table" and cfg.mpts_config or {}
        local adv = type(mpts_config.advanced) == "table" and mpts_config.advanced or nil
        if adv and (adv.pass_nit or adv.pass_sdt or adv.pass_eit or adv.pass_tdt) and #services > 1 then
            local label = cfg.name or cfg.id or "MPTS"
            log.warning("[" .. tostring(label) .. "] pass_* режимы корректны только для одного сервиса; будет генерация")
        end
        if adv and adv.pass_sdt then
            for _, service in ipairs(services) do
                if service.service_name or service.service_provider or service.service_type_id or service.scrambled then
                    local label = cfg.name or cfg.id or "MPTS"
                    log.warning("[" .. tostring(label) .. "] pass_sdt включает SDT из входа; "
                        .. "service_name/provider/type/scrambled будут проигнорированы")
                    break
                end
            end
        end
        if adv and adv.pass_nit then
            local general = type(mpts_config.general) == "table" and mpts_config.general or {}
            local nit = type(mpts_config.nit) == "table" and mpts_config.nit or {}
            if general.network_id or general.network_name or nit.delivery or nit.frequency or nit.symbolrate
                or nit.fec or nit.modulation or nit.network_search or nit.lcn_version then
                local label = cfg.name or cfg.id or "MPTS"
                log.warning("[" .. tostring(label) .. "] pass_nit включает NIT из входа; "
                    .. "поля NIT будут проигнорированы")
            end
        end
        if adv and adv.pass_tdt then
            local general = type(mpts_config.general) == "table" and mpts_config.general or {}
            if general.country or general.utc_offset then
                local label = cfg.name or cfg.id or "MPTS"
                log.warning("[" .. tostring(label) .. "] pass_tdt включает TDT/TOT из входа; "
                    .. "country/utc_offset будут проигнорированы")
            end
        end
        for idx, service in ipairs(services) do
            local url = collect_mpts_input(service)
            if not url then
                return nil, "invalid MPTS service #" .. idx .. " input"
            end
            local resolved = resolve_io_config(url, true)
            if not resolved or not resolved.format then
                return nil, "invalid MPTS service #" .. idx .. " input format"
            end
            local ok_det, det_err = validate_input_detectors(resolved, idx)
            if not ok_det then
                return nil, det_err
            end
            if resolved.format == "stream" then
                local stream_id = resolved.stream_id or resolved.addr or resolved.id
                if not stream_id or stream_id == "" then
                    return nil, "MPTS service #" .. idx .. " requires stream://<id>"
                end
            elseif not init_input_module[resolved.format] then
                return nil, "invalid MPTS service #" .. idx .. " input format"
            end
            if resolved.format == "https" and not (https_native_supported() or https_bridge_enabled(resolved)) then
                return nil, "https input requires native TLS (OpenSSL) or ffmpeg bridge (enable https_bridge_enabled or add #https_bridge=1)"
            end
        end
    else
        if not inputs or #inputs == 0 then
            return nil, "at least one input is required"
        end
        for idx, entry in ipairs(inputs) do
            local resolved = resolve_io_config(entry, true)
            if not resolved or not resolved.format then
                return nil, "invalid input #" .. idx .. " format"
            end
            local ok_det, det_err = validate_input_detectors(resolved, idx)
            if not ok_det then
                return nil, det_err
            end
            if resolved.format == "stream" then
                if not is_transcode then
                    return nil, "stream:// inputs are supported only in MPTS mode"
                end
                local stream_id = resolved.stream_id or resolved.addr or resolved.id
                if not stream_id or stream_id == "" then
                    return nil, "transcode input #" .. idx .. " requires stream://<id>"
                end
            elseif not init_input_module[resolved.format] then
                return nil, "invalid input #" .. idx .. " format"
            end
            if resolved.format == "https" and not (https_native_supported() or https_bridge_enabled(resolved)) then
                return nil, "https input requires native TLS (OpenSSL) or ffmpeg bridge (enable https_bridge_enabled or add #https_bridge=1)"
            end
        end
    end

    local input_count = (type(inputs) == "table") and #inputs or 0
    local backup_type = normalize_backup_type(cfg.backup_type, input_count > 1)
    local function check_nonneg(value, label)
        if value ~= nil and value < 0 then
            return nil, label .. " must be >= 0"
        end
        return true
    end
    local function check_min(value, min_value, label)
        if value ~= nil and value < min_value then
            return nil, label .. " must be >= " .. tostring(min_value)
        end
        return true
    end
    local initial_delay = read_number_opt(cfg, "backup_initial_delay_sec", "backup_initial_delay")
    local start_delay = read_number_opt(cfg, "backup_start_delay_sec", "backup_start_delay")
    local return_delay = read_number_opt(cfg, "backup_return_delay_sec", "backup_return_delay")
    local stable_ok = read_number_opt(cfg, "stable_ok_sec")
    local probe_interval = read_number_opt(cfg, "probe_interval_sec")
    local stall_switch_cooldown = read_number_opt(cfg, "backup_stall_switch_cooldown_sec")
    local no_data_timeout = read_number_opt(cfg, "no_data_timeout_sec")
    local stop_if_all_inactive = read_number_opt(cfg, "stop_if_all_inactive_sec", "backup_stop_if_all_inactive_sec")

    local ok, err = check_nonneg(initial_delay, "backup_initial_delay")
    if not ok then return nil, err end
    ok, err = check_nonneg(start_delay, "backup_start_delay")
    if not ok then return nil, err end
    ok, err = check_nonneg(return_delay, "backup_return_delay")
    if not ok then return nil, err end
    ok, err = check_nonneg(stable_ok, "stable_ok_sec")
    if not ok then return nil, err end
    ok, err = check_nonneg(probe_interval, "probe_interval_sec")
    if not ok then return nil, err end
    ok, err = check_nonneg(stall_switch_cooldown, "backup_stall_switch_cooldown_sec")
    if not ok then return nil, err end
    if no_data_timeout ~= nil and no_data_timeout < 1 then
        return nil, "no_data_timeout_sec must be >= 1"
    end
    if backup_type == "active_stop_if_all_inactive" then
        ok, err = check_min(stop_if_all_inactive, 5, "stop_if_all_inactive_sec")
        if not ok then return nil, err end
    end

    if is_transcode then
        local tc = cfg.transcode or {}
        local has_outputs = type(tc.outputs) == "table" and #tc.outputs > 0
        local has_profiles = type(tc.profiles) == "table" and #tc.profiles > 0
        if not has_outputs and not has_profiles then
            return nil, "transcode.outputs or transcode.profiles is required"
        end
        return true
    end

    local outputs = normalize_stream_list(cfg.output)
    if outputs and #outputs > 0 then
        for idx, entry in ipairs(outputs) do
            local resolved = resolve_io_config(entry, false)
            if not resolved or not resolved.format or not init_output_module[resolved.format] then
                return nil, "invalid output #" .. idx .. " format"
            end
            local ok, err = validate_output_entry(resolved, cfg, opts)
            if not ok then
                return nil, "output #" .. idx .. " " .. tostring(err)
            end
        end
    end

    return true
end

function sanitize_stream_config(cfg)
    if type(cfg) ~= "table" then
        return cfg
    end
    local function trim_text(value)
        return tostring(value or ""):gsub("^%s+", ""):gsub("%s+$", "")
    end
    local function bridge_output_key(resolved)
        if type(resolved) ~= "table" then
            return nil
        end
        local fmt = tostring(resolved.format or ""):lower()
        if fmt ~= "udp" and fmt ~= "rtp" then
            return nil
        end
        local addr = tostring(resolved.addr or ""):lower()
        local port = tonumber(resolved.port)
        if addr == "" or not port or port <= 0 then
            return nil
        end
        local localaddr = tostring(resolved.localaddr or ""):lower()
        local sync = tonumber(resolved.sync) or 0
        return fmt .. "|" .. localaddr .. "|" .. addr .. ":" .. tostring(port) .. "|" .. tostring(sync)
    end
    local function bridge_output_endpoint_key(resolved)
        if type(resolved) ~= "table" then
            return nil
        end
        local fmt = tostring(resolved.format or ""):lower()
        if fmt ~= "udp" and fmt ~= "rtp" then
            return nil
        end
        local addr = tostring(resolved.addr or ""):lower()
        local port = tonumber(resolved.port)
        if addr == "" or not port or port <= 0 then
            return nil
        end
        local sync = tonumber(resolved.sync) or 0
        return fmt .. "|" .. addr .. ":" .. tostring(port) .. "|" .. tostring(sync)
    end
    local function sync_bridge_outputs()
        local tc = cfg.transcode
        if type(tc) ~= "table" then
            return
        end
        local publish = tc.publish
        if type(publish) ~= "table" or #publish == 0 then
            return
        end

        local outputs = normalize_stream_list(cfg.output) or {}
        local keys = {}
        local endpoint_keys = {}
        for _, entry in ipairs(outputs) do
            local resolved = resolve_io_config(entry, false)
            local key = bridge_output_key(resolved)
            if key then
                keys[key] = true
            end
            local endpoint_key = bridge_output_endpoint_key(resolved)
            if endpoint_key then
                endpoint_keys[endpoint_key] = true
            end
        end

        local changed = false
        for _, pub in ipairs(publish) do
            if type(pub) == "table" then
                local kind = tostring(pub.type or ""):lower()
                if kind == "udp" or kind == "rtp" then
                    local raw_url = trim_text(pub.url)
                    if raw_url ~= "" then
                        local resolved = resolve_io_config(raw_url, false)
                        local key = bridge_output_key(resolved)
                        local endpoint_key = bridge_output_endpoint_key(resolved)
                        if key and not keys[key] and not (endpoint_key and endpoint_keys[endpoint_key]) then
                            table.insert(outputs, raw_url)
                            keys[key] = true
                            if endpoint_key then
                                endpoint_keys[endpoint_key] = true
                            end
                            changed = true
                        end
                    end
                end
            end
        end

        if changed and #outputs > 0 then
            cfg.output = outputs
        end
    end
    local function unset_if_below(keys, min_value)
        for _, key in ipairs(keys) do
            local value = tonumber(cfg[key])
            if value ~= nil and value < min_value then
                cfg[key] = nil
            end
        end
    end
    local function unset_if_negative(keys)
        unset_if_below(keys, 0)
    end

    unset_if_below({ "no_data_timeout_sec" }, 1)
    unset_if_below({ "stop_if_all_inactive_sec", "backup_stop_if_all_inactive_sec" }, 5)
    unset_if_negative({ "backup_initial_delay_sec", "backup_initial_delay" })
    unset_if_negative({ "backup_start_delay_sec", "backup_start_delay" })
    unset_if_negative({ "backup_return_delay_sec", "backup_return_delay" })
    unset_if_negative({ "probe_interval_sec" })
    unset_if_negative({ "stable_ok_sec" })
    unset_if_negative({ "backup_stall_switch_cooldown_sec" })
    -- Сохраняем dual-mode bridge outputs (UDP/RTP) даже если редактирование шло через transcode.publish.
    -- Это не меняет runtime pipeline, но предотвращает "пропажу" passthrough outputs при toggle transcoding.
    sync_bridge_outputs()
    return cfg
end

local function log_http_access(event, entry, request)
    if not access_log or type(access_log.add) ~= "function" then
        return
    end
    local req = request or (entry and entry.request) or {}
    local headers = req.headers or {}
    local user_agent = headers["user-agent"] or headers["User-Agent"] or ""
    local login = ""
    if req.query then
        login = req.query.user or req.query.login or ""
    end
    access_log.add({
        event = event,
        protocol = "http",
        stream_id = entry and entry.stream_id,
        stream_name = entry and entry.stream_name,
        ip = req.addr,
        login = login,
        user_agent = user_agent,
        path = req.path or "",
        reason = req.error or nil,
    })
end

local function http_output_auth(server, client, request)
    local ok, info = http_auth_check(request)
    if ok then
        return true
    end
    local headers = {
        "Content-Type: text/plain",
        "Connection: close",
    }
    if info and info.basic then
        local realm = info.realm or "Stream"
        table.insert(headers, 'WWW-Authenticate: Basic realm="' .. realm .. '"')
    end
    server:send(client, {
        code = 401,
        headers = headers,
        content = "unauthorized",
    })
    return false
end

local function header_value(headers, key)
    if not headers then
        return nil
    end
    return headers[key] or headers[string.lower(key)] or headers[string.upper(key)]
end

local function build_request_uri(request)
    if not request then
        return ""
    end
    local path = request.path or ""
    local query = request.query or {}
    local parts = {}
    for key, value in pairs(query) do
        table.insert(parts, tostring(key) .. "=" .. tostring(value))
    end
    table.sort(parts)
    local uri = path
    if #parts > 0 then
        uri = uri .. "?" .. table.concat(parts, "&")
    end
    local host = header_value(request.headers or {}, "host")
    if host and host ~= "" then
        uri = "http://" .. host .. uri
    end
    return uri
end

local function resolve_http_keep_active(channel_data, output_data)
    local keep_active = nil
    if output_data and output_data.config then
        local value = output_data.config.keep_active
        if value ~= nil then
            if value == true then
                return -1
            end
            if value == false then
                return 0
            end
            local numeric = tonumber(value)
            if numeric ~= nil then
                return numeric
            end
        end
    end
    keep_active = tonumber(channel_data.config.http_keep_active or 0) or 0
    return keep_active
end

-- Канал считается неактивным, если нет клиентов и нет удержания (retain).
local function channel_is_idle(channel_data)
    if not channel_data then
        return true
    end
    local clients = tonumber(channel_data.clients or 0) or 0
    local retained = tonumber(channel_data.retain_count or 0) or 0
    return (clients + retained) == 0
end

local function channel_stop_if_idle(channel_data, output_data)
    if not channel_is_idle(channel_data) then
        return
    end
    if not channel_data.input or not channel_data.input[1] or channel_data.input[1].input == nil then
        return
    end
    if channel_data.keep_timer then
        channel_data.keep_timer:close()
        channel_data.keep_timer = nil
    end
    local keep_active = resolve_http_keep_active(channel_data, output_data)
    if keep_active == 0 then
        for input_id, input_data in ipairs(channel_data.input) do
            if input_data.input then
                channel_kill_input(channel_data, input_id)
            end
        end
        channel_data.active_input_id = 0
        channel_pause_failover(channel_data)
    elseif keep_active > 0 then
        channel_data.keep_timer = timer({
            interval = keep_active,
            callback = function(self)
                self:close()
                channel_data.keep_timer = nil
                if channel_is_idle(channel_data) then
                    for input_id, input_data in ipairs(channel_data.input) do
                        if input_data.input then
                            channel_kill_input(channel_data, input_id)
                        end
                    end
                    channel_data.active_input_id = 0
                    channel_pause_failover(channel_data)
                end
            end,
        })
    end
end

-- Удержание канала активным (для MPTS stream:// источников).
local function channel_retain(channel_data, reason)
    if not channel_data then
        return false
    end
    channel_data.retain_count = (channel_data.retain_count or 0) + 1
    local active_id = tonumber(channel_data.active_input_id or 0) or 0
    if active_id ~= 0 then
        return true
    end
    if channel_data.failover and channel_data.failover.enabled then
        channel_resume_failover(channel_data)
    end
    if #channel_data.input > 0 then
        if not channel_activate_input(channel_data, 1, reason or "retain") then
            for input_id = 2, #channel_data.input do
                if channel_activate_input(channel_data, input_id, reason or "retain") then
                    break
                end
            end
        end
    end
    return true
end

local function channel_release(channel_data, reason)
    if not channel_data or not channel_data.retain_count then
        return false
    end
    if channel_data.retain_count <= 0 then
        channel_data.retain_count = 0
        return false
    end
    channel_data.retain_count = channel_data.retain_count - 1
    if channel_data.retain_count == 0 then
        channel_stop_if_idle(channel_data, nil)
    end
    return true
end

-- Экспортируем удержание канала для внешних модулей (например, preview-менеджера).
-- Важно: функции замыкают внутреннюю логику channel_stop_if_idle и failover.
if _G.channel_retain == nil then _G.channel_retain = channel_retain end
if _G.channel_release == nil then _G.channel_release = channel_release end

function http_output_client(server, client, request, output_data)
    local client_data = server:data(client)

    if not request then
        if client_data.auth_session_id and auth and auth.unregister_client then
            auth.unregister_client(client_data.auth_session_id, server, client)
            client_data.auth_session_id = nil
        end
        local entry = client_data.client_id and http_output_client_list[client_data.client_id] or nil
        if entry then
            log_http_access("disconnect", entry, nil)
        end
        if client_data.client_id ~= nil then
            http_output_client_list[client_data.client_id] = nil
        end
        client_data.client_id = nil
        return nil
    end

    local function get_unique_client_id()
        local _id = math.random(10000000, 99000000)
        if http_output_client_list[_id] ~= nil then
            return nil
        end
        return _id
    end

    repeat
        client_data.client_id = get_unique_client_id()
    until client_data.client_id ~= nil

    local stream_id = nil
    local stream_name = nil
    if output_data and output_data.channel_data and output_data.channel_data.config then
        stream_id = output_data.channel_data.config.id
        stream_name = output_data.channel_data.config.name
    end

    http_output_client_list[client_data.client_id] = {
        server = server,
        client = client,
        request = request,
        st   = os.time(),
        stream_id = stream_id,
        stream_name = stream_name,
    }
    log_http_access("connect", http_output_client_list[client_data.client_id], request)
end

function http_output_on_request(server, client, request)
    local client_data = server:data(client)

    if not request then
        if client_data.client_id then
            local channel_data = client_data.output_data.channel_data
            channel_data.clients = channel_data.clients - 1
            if channel_data.keep_timer then
                channel_data.keep_timer:close()
                channel_data.keep_timer = nil
            end
            channel_stop_if_idle(channel_data, client_data.output_data)

            http_output_client(server, client, nil)
            collectgarbage()
        end
        return nil
    end

    if not http_output_auth(server, client, request) then
        return nil
    end

    local output_data = server.__options.channel_list[request.path]
    if not output_data then
        server:abort(client, 404)
        return nil
    end

    local channel_data = output_data.channel_data
    local function start_stream(session)
        client_data.output_data = output_data
        http_output_client(server, client, request, client_data.output_data)

        if session and session.session_id and auth and auth.register_client then
            auth.register_client(session.session_id, server, client)
            client_data.auth_session_id = session.session_id
        end

        if channel_data.keep_timer then
            channel_data.keep_timer:close()
            channel_data.keep_timer = nil
        end
        channel_data.clients = channel_data.clients + 1

        if channel_data.is_mpts then
            for input_id, input_data in ipairs(channel_data.input) do
                if not input_data.input then
                    channel_prepare_input(channel_data, input_id, {})
                end
            end
        else
            if not channel_data.input[1].input then
                channel_init_input(channel_data, 1)
            end
        end

        local buffer_size = math.max(128, output_data.config.buffer_size or 4000)
        local buffer_fill = math.floor(buffer_size / 4)
        server:send(client, {
            upstream = channel_data.tail:stream(),
            buffer_size = buffer_size,
            buffer_fill = buffer_fill,
        })
    end

    if auth and auth.check_play then
        local headers = request.headers or {}
        auth.check_play({
            stream_id = channel_data.config and channel_data.config.id or "",
            stream_name = channel_data.config and channel_data.config.name or "",
            stream_cfg = channel_data.config,
            proto = "http_ts",
            request = request,
            ip = request.addr,
            token = auth.get_token and auth.get_token(request) or nil,
            user_agent = header_value(headers, "user-agent") or "",
            referer = header_value(headers, "referer") or "",
            uri = build_request_uri(request),
        }, function(allowed, session)
            if not allowed then
                server:send(client, {
                    code = 403,
                    headers = {
                        "Content-Type: text/plain",
                        "Connection: close",
                    },
                    content = "forbidden",
                })
                return
            end
            start_stream(session)
        end)
        return nil
    end

    http_output_client(server, client, request, output_data)
    if channel_data.keep_timer then
        channel_data.keep_timer:close()
        channel_data.keep_timer = nil
    end
    channel_data.clients = channel_data.clients + 1

    local allow_channel = function()
        channel_resume_failover(channel_data)
        if channel_data.active_input_id == 0 then
            if not channel_activate_input(channel_data, 1, "client") then
                for input_id = 2, #channel_data.input do
                    if channel_activate_input(channel_data, input_id, "client") then
                        break
                    end
                end
            end
        end

        server:send(client, {
            upstream = channel_data.tail:stream(),
            buffer_size = client_data.output_data.config.buffer_size,
            buffer_fill = client_data.output_data.config.buffer_fill,
        })
    end

    allow_channel()
end

init_output_module.http = function(channel_data, output_id)
    local output_data = channel_data.output[output_id]

    local instance_id = output_data.config.host .. ":" .. output_data.config.port
    local instance = http_output_instance_list[instance_id]

    if not instance then
        local http_request_line_max = setting_number("http_request_line_max", 4096)
        local http_headers_max = setting_number("http_headers_max", 12288)
        local http_header_max = setting_number("http_header_max", 4096)
        local http_content_length_max = setting_number("http_content_length_max", 8 * 1024 * 1024)
        instance = http_server({
            addr = output_data.config.host,
            port = output_data.config.port,
            sctp = output_data.config.sctp,
            route = {
                { "/*", http_upstream({ callback = http_output_on_request }) },
            },
            channel_list = {},
            request_line_max = http_request_line_max,
            headers_max = http_headers_max,
            header_max = http_header_max,
            content_length_max = http_content_length_max,
        })
        http_output_instance_list[instance_id] = instance
    end

    output_data.instance = instance
    output_data.instance_id = instance_id
    output_data.channel_data = channel_data

    instance.__options.channel_list[output_data.config.path] = output_data
end

kill_output_module.http = function(channel_data, output_id)
    local output_data = channel_data.output[output_id]

    local instance = output_data.instance
    local instance_id = output_data.instance_id

    for _, client in pairs(http_output_client_list) do
        if client.server == instance then
            instance:close(client.client)
        end
    end

    instance.__options.channel_list[output_data.config.path] = nil

    local is_instance_empty = true
    for _ in pairs(instance.__options.channel_list) do
        is_instance_empty = false
        break
    end

    if is_instance_empty then
        if not (http_output_keepalive and http_output_keepalive[instance_id]) then
            instance:close()
            http_output_instance_list[instance_id] = nil
        end
    end

    output_data.instance = nil
    output_data.instance_id = nil
    output_data.channel_data = nil
end

--   ooooooo            ooooo ooooo ooooo         ooooooooooo
-- o888   888o           888   888  888           888    88
-- 888     888 ooooooooo 888ooo888  888           888ooo8
-- 888o   o888           888   888  888      o    888    oo
--   88ooo88             o888o o888o o888ooooo88 o888ooo8888

init_output_module.hls = function(channel_data, output_id)
    local output_data = channel_data.output[output_id]
    local conf = output_data.config

    resolve_hls_output_config(channel_data, conf)

    if conf.storage ~= "memfd" and not conf.path then
        log.error("[" .. conf.name .. "] HLS output requires path")
        return
    end

    output_data.output = hls_output({
        upstream = channel_data.tail:stream(),
        path = conf.path,
        playlist = conf.playlist,
        prefix = conf.prefix,
        base_url = conf.base_url,
        target_duration = conf.target_duration,
        window = conf.window,
        cleanup = conf.cleanup,
        use_wall = conf.use_wall,
        naming = conf.naming,
        round_duration = conf.round_duration,
        ts_extension = conf.ts_extension,
        pass_data = conf.pass_data,
        storage = conf.storage,
        stream_id = conf.stream_id,
        on_demand = conf.on_demand,
        idle_timeout_sec = conf.idle_timeout_sec,
        max_segments = conf.max_segments,
        max_bytes = conf.max_bytes,
        debug_hold_sec = conf.debug_hold_sec,
    })
end

kill_output_module.hls = function(channel_data, output_id)
    local output_data = channel_data.output[output_id]
    output_data.output = nil
end

--   ooooooo            oooo   oooo oooooooooo
-- o888   888o           8888o  88   888    888
-- 888     888 ooooooooo 88 888o88   888oooo88
-- 888o   o888           88   8888   888
--   88ooo88            o88o    88  o888o

init_output_module.np = function(channel_data, output_id)
    local output_data = channel_data.output[output_id]
    local conf = output_data.config

    local buffer_size = conf.buffer_size
    local buffer_fill = conf.buffer_fill or buffer_size

    local http_conf = {
        host = conf.host,
        port = conf.port,
        path = conf.path,
        upstream = channel_data.tail:stream(),
        buffer_size = buffer_size,
        buffer_fill = buffer_fill,
        timeout = conf.timeout,
        sctp = conf.sctp,
        headers = {
            "User-Agent: " .. http_user_agent,
            "Host: " .. conf.host,
            "Connection: keep-alive",
        },
    }

    local timer_conf = {
        interval = 5,
        callback = function(self)
            output_data.timeout:close()
            output_data.timeout = nil

            if output_data.request then output_data.request:close() end
            output_data.request = http_request(http_conf)
        end
    }

    http_conf.callback = function(self, response)
        if not response then
            output_data.request:close()
            output_data.request = nil
            output_data.timeout = timer(timer_conf)

        elseif response.code == 200 then
            if output_data.timeout then
                output_data.timeout:close()
                output_data.timeout = nil
            end

        elseif response.code == 301 or response.code == 302 then
            if output_data.timeout then
                output_data.timeout:close()
                output_data.timeout = nil
            end

            output_data.request:close()
            output_data.request = nil

            local o = parse_url(response.headers["location"])
            if o then
                http_conf.host = o.host
                http_conf.port = o.port
                http_conf.path = o.path
                http_conf.headers[2] = "Host: " .. o.host

                log.info("[" .. conf.name .. "] Redirect to http://" .. o.host .. ":" .. o.port .. o.path)
                output_data.request = http_request(http_conf)
            else
                log.error("[" .. conf.name .. "] NP Error: Redirect failed")
                output_data.timeout = timer(timer_conf)
            end

        else
            output_data.request:close()
            output_data.request = nil
            log.error("[" .. conf.name .. "] NP Error: " .. response.code .. ":" .. response.message)
            output_data.timeout = timer(timer_conf)
        end
    end

    output_data.request = http_request(http_conf)
end

kill_output_module.np = function(channel_data, output_id)
    local output_data = channel_data.output[output_id]
    if output_data.timeout then
        output_data.timeout:close()
        output_data.timeout = nil
    end
    if output_data.request then
        output_data.request:close()
        output_data.request = nil
    end
end

local function get_active_input_source_url(channel_data)
    if not channel_data or not channel_data.input then
        return nil
    end
    local active_id = channel_data.active_input_id or 0
    if active_id > 0 then
        local input_data = channel_data.input[active_id]
        if input_data then
            return input_data.source_url or format_input_url(input_data.config)
        end
    end
    return nil
end

local function strip_url_hash(url)
    if not url or url == "" then
        return url
    end
    local hash = tostring(url):find("#")
    if hash then
        return tostring(url):sub(1, hash - 1)
    end
    return tostring(url)
end

local function append_play_buffer(url, buffer_kb)
    if not url or url == "" then
        return url
    end
    local value = tonumber(buffer_kb)
    if not value or value <= 0 then
        return url
    end
    local suffix = "buf_kb=" .. tostring(math.floor(value))
    if tostring(url):find("?", 1, true) then
        return tostring(url) .. "&" .. suffix
    end
    return tostring(url) .. "?" .. suffix
end

local function append_play_buffer_fill(url, fill_kb)
    if not url or url == "" then
        return url
    end
    local value = tonumber(fill_kb)
    if not value or value <= 0 then
        return url
    end
    local suffix = "buf_fill_kb=" .. tostring(math.floor(value))
    if tostring(url):find("?", 1, true) then
        return tostring(url) .. "&" .. suffix
    end
    return tostring(url) .. "?" .. suffix
end

local function normalize_setting_bool(value, fallback)
    if value == nil then
        return fallback
    end
    if value == true then
        return true
    end
    if value == false then
        return false
    end
    local s = tostring(value):lower():gsub("%s+", "")
    if s == "1" or s == "true" or s == "yes" or s == "on" then
        return true
    end
    if s == "0" or s == "false" or s == "no" or s == "off" then
        return false
    end
    return fallback
end

local function is_ffmpeg_url_supported(url)
    if not url or url == "" then
        return false
    end
    local u = strip_url_hash(url):lower()
    if u:find("^http://") == 1 or u:find("^https://") == 1 then
        return true
    end
    if u:find("^udp://") == 1 or u:find("^rtp://") == 1 or u:find("^srt://") == 1 or u:find("^tcp://") == 1 then
        return true
    end
    if u:find("^file:") == 1 then
        return true
    end
    if u:find("^/") == 1 then
        return true
    end
    return false
end

local function build_audio_fix_input_url(channel_data)
    if not (channel_data and channel_data.config and channel_data.config.id) then
        return nil
    end
    if not (config and config.get_setting) then
        return nil
    end
    -- /input должен быть "сырой" стадией для внутренних ffmpeg потребителей (transcode/audio-fix),
    -- поэтому всегда используем основной http_port (а не http_play_port).
    local port = tonumber(config.get_setting("http_port"))
    if not port or port <= 0 then
        return nil
    end
    local stream_id = tostring(channel_data.config.id)
    if stream_id == "" then
        return nil
    end
    -- Pass internal=1 so localhost ffmpeg can bypass http auth for /input (см. http_auth_check()).
    return "http://127.0.0.1:" .. tostring(port) .. "/input/" .. stream_id .. "?internal=1"
end

local function resolve_audio_fix_input_url(channel_data, audio_fix)
    if audio_fix and audio_fix.config and audio_fix.config.input_url and audio_fix.config.input_url ~= "" then
        return strip_url_hash(audio_fix.config.input_url), nil
    end

    local loop_url = build_audio_fix_input_url(channel_data)
    if loop_url then
        -- Loopback buffering is enforced server-side for /input. Keep the ffmpeg input URL stable.
        return loop_url, nil
    end

    local active = get_active_input_source_url(channel_data)
    if active and is_ffmpeg_url_supported(active) then
        return strip_url_hash(active), nil
    end
    if active and active ~= "" then
        return nil, "input unavailable; no ffmpeg-compatible input url (active=" .. tostring(active) .. ")"
    end
    return nil, "input unavailable; active input url is required"
end

local function set_udp_output_passthrough(channel_data, output_id, enabled)
    local output_data = channel_data.output[output_id]
    if not output_data then
        return
    end
    if enabled then
        if not output_data.output then
            init_output_module.udp(channel_data, output_id)
        end
    elseif output_data.output then
        output_data.output = nil
    end
end

local function release_audio_fix_slot(probe)
    if not probe or not probe.analyze_slot then
        return
    end
    audio_fix_analyze_active = math.max(0, audio_fix_analyze_active - 1)
    probe.analyze_slot = false
end

local function stop_audio_fix_probe(audio_fix)
    if not audio_fix or not audio_fix.probe then
        return
    end
    local probe = audio_fix.probe
    if probe.analyzer then
        local mod = probe.analyzer
        probe.analyzer = nil
        if type(mod.close) == "function" then
            pcall(mod.close, mod)
        end
    end
    release_audio_fix_slot(probe)
    audio_fix.probe = nil
end

local function stop_audio_fix_input_probe(audio_fix)
    if not audio_fix or not audio_fix.input_probe then
        return
    end
    local probe = audio_fix.input_probe
    if probe.proc then
        probe.proc:kill()
        probe.proc:close()
    end
    audio_fix.input_probe = nil
end

local function stop_audio_fix_drift_probe(audio_fix)
    local probe = audio_fix and audio_fix.drift_probe or nil
    if not probe then
        return
    end
    if probe.audio and probe.audio.proc then
        probe.audio.proc:kill()
        probe.audio.proc:close()
        probe.audio.proc = nil
    end
    if probe.video and probe.video.proc then
        probe.video.proc:kill()
        probe.video.proc:close()
        probe.video.proc = nil
    end
    audio_fix.drift_probe = nil
end

local function stop_audio_fix_process(channel_data, audio_fix)
    if not audio_fix then
        return
    end
    local warm = audio_fix.warm_restart
    if warm then
        if warm.new_proc then
            local proc = warm.new_proc
            warm.new_proc = nil
            pcall(function() proc:terminate() end)
            pcall(function() proc:kill() end)
            pcall(function() proc:close() end)
        end
        if warm.old_proc and warm.old_proc ~= audio_fix.proc then
            local proc = warm.old_proc
            warm.old_proc = nil
            pcall(function() proc:terminate() end)
            pcall(function() proc:kill() end)
            pcall(function() proc:close() end)
        end
    end
    audio_fix.warm_restart = nil
    if audio_fix.proc then
        audio_fix.proc:terminate()
        audio_fix.proc:kill()
        audio_fix.proc:close()
        audio_fix.proc = nil
    end
    audio_fix.proc_input_url = nil
    audio_fix.proc_output_url = nil
    audio_fix.proxy_switch = nil
    audio_fix.proxy_listen_port = nil
end

local function is_audio_fix_cooldown_active(audio_fix, now)
    local cooldown = audio_fix and audio_fix.config and audio_fix.config.restart_cooldown_sec or 0
    if cooldown <= 0 then
        return false
    end
    local last = audio_fix.last_restart_ts
    if not last then
        return false
    end
    return (now - last) < cooldown
end

local function is_audio_fix_force_run(conf)
    if not conf then
        return false
    end
    local mode = conf.mode
    return conf.force_on == true or mode == "auto" or mode == "aac" or conf.silence_fallback == true
end

local function normalize_aac_profile(profile)
    if not profile or profile == "" then
        return nil
    end
    local value = tostring(profile):lower():gsub("%s+", "")
    if value == "lc" or value == "aaclc" or value == "aac-lc" or value == "aac_low" then
        return "aac_low"
    end
    return tostring(profile)
end

local function resolve_ffprobe_bin()
    return resolve_tool_path("ffprobe", {
        setting_key = "ffprobe_path",
        env_key = "ASTRA_FFPROBE_PATH",
    })
end

local function build_anullsrc_spec(sample_rate, channels)
    local sr = tonumber(sample_rate) or AUDIO_FIX_AAC_SAMPLE_RATE_DEFAULT
    if sr < 8000 then
        sr = AUDIO_FIX_AAC_SAMPLE_RATE_DEFAULT
    end
    local ch = tonumber(channels) or AUDIO_FIX_AAC_CHANNELS_DEFAULT
    if ch < 1 then
        ch = AUDIO_FIX_AAC_CHANNELS_DEFAULT
    end
    local layout = nil
    if ch == 1 then
        layout = "mono"
    elseif ch == 2 then
        layout = "stereo"
    end
    local spec = "anullsrc=r=" .. tostring(sr)
    if layout then
        spec = spec .. ":cl=" .. layout
    end
    return spec
end

local function build_audio_fix_ffmpeg_args(bin, input_url, output_url, audio_fix, effective_mode)
    local cfg = audio_fix and audio_fix.config or {}
    local mode = effective_mode or "aac"
    if mode ~= "aac" and mode ~= "copy" and mode ~= "silence" then
        mode = "aac"
    end

    local aac_profile = normalize_aac_profile(cfg.aac_profile)
    local args = {
        bin,
        "-hide_banner",
        "-nostats",
        "-nostdin",
        "-loglevel",
        "warning",
    }
    if cfg.genpts then
        table.insert(args, "-fflags")
        table.insert(args, "+genpts")
    end
    table.insert(args, "-i")
    table.insert(args, tostring(input_url))
    if mode == "silence" then
        table.insert(args, "-f")
        table.insert(args, "lavfi")
        table.insert(args, "-i")
        table.insert(args, build_anullsrc_spec(cfg.aac_sample_rate, cfg.aac_channels))
    end
    table.insert(args, "-map")
    table.insert(args, "0:v:0?")
    table.insert(args, "-map")
    if mode == "silence" then
        table.insert(args, "1:a:0")
    else
        table.insert(args, "0:a:0?")
    end
    table.insert(args, "-c:v")
    table.insert(args, "copy")

    if mode == "copy" then
        table.insert(args, "-c:a")
        table.insert(args, "copy")
    else
        table.insert(args, "-c:a")
        table.insert(args, "aac")
        table.insert(args, "-b:a")
        table.insert(args, tostring(tonumber(cfg.aac_bitrate_kbps) or AUDIO_FIX_AAC_BITRATE_DEFAULT) .. "k")
        table.insert(args, "-ac")
        table.insert(args, tostring(tonumber(cfg.aac_channels) or AUDIO_FIX_AAC_CHANNELS_DEFAULT))
        table.insert(args, "-ar")
        table.insert(args, tostring(tonumber(cfg.aac_sample_rate) or AUDIO_FIX_AAC_SAMPLE_RATE_DEFAULT))
        if aac_profile and aac_profile ~= "" then
            table.insert(args, "-profile:a")
            table.insert(args, aac_profile)
        end
        local async_value = tonumber(cfg.aresample_async)
        if async_value and async_value > 0 then
            table.insert(args, "-af")
            table.insert(args, "aresample=async=" .. tostring(async_value))
        end
    end
    if cfg.max_interleave_delta_sec and tonumber(cfg.max_interleave_delta_sec) then
        table.insert(args, "-max_interleave_delta")
        table.insert(args, tostring(cfg.max_interleave_delta_sec))
    end
    table.insert(args, "-f")
    table.insert(args, "mpegts")
    table.insert(args, tostring(output_url))
    return args
end

local function set_audio_fix_tail_upstream(channel_data, upstream)
    if not channel_data or not upstream then
        return
    end
    local tail = channel_data.audio_fix_transmit
    if tail and type(tail.set_upstream) == "function" then
        pcall(tail.set_upstream, tail, upstream)
    end
end

local function get_audio_fix_raw_upstream(channel_data)
    if channel_data and channel_data.transmit and type(channel_data.transmit.stream) == "function" then
        return channel_data.transmit:stream()
    end
    return nil
end

local function apply_audio_fix_upstream(channel_data)
    if not channel_data then
        return
    end
    local audio_fix = channel_data.audio_fix
    local upstream = nil
    if audio_fix and audio_fix.proc and audio_fix.proxy_switch and type(audio_fix.proxy_switch.stream) == "function" then
        upstream = audio_fix.proxy_switch:stream()
    else
        upstream = get_audio_fix_raw_upstream(channel_data)
    end
    set_audio_fix_tail_upstream(channel_data, upstream)
end

local function start_audio_fix_process(channel_data, reason, opts)
    opts = opts or {}
    local audio_fix = channel_data and channel_data.audio_fix or nil
    if not audio_fix or not audio_fix.config or audio_fix.config.enabled ~= true then
        return false
    end
    if not process or type(process.spawn) ~= "function" then
        audio_fix.last_error = "process module not available"
        log.error("[stream " .. get_stream_label(channel_data) .. "] audio-fix: process module not available")
        return false
    end
    if not udp_switch then
        audio_fix.last_error = "udp_switch module not available"
        log.error("[stream " .. get_stream_label(channel_data) .. "] audio-fix: udp_switch module not available")
        return false
    end

    local input_url, input_err = resolve_audio_fix_input_url(channel_data, audio_fix)
    if not input_url or input_url == "" then
        audio_fix.last_error = input_err or "active input url is required"
        log.warning("[stream " .. get_stream_label(channel_data) .. "] audio-fix: " .. tostring(audio_fix.last_error))
        return false
    end

    stop_audio_fix_process(channel_data, audio_fix)

    local bin = resolve_tool_path("ffmpeg", {
        setting_key = "ffmpeg_path",
        env_key = "ASTRA_FFMPEG_PATH",
    })

    local effective_mode = opts.effective_mode or audio_fix.effective_mode or "aac"
    if effective_mode ~= "aac" and effective_mode ~= "copy" and effective_mode ~= "silence" then
        effective_mode = "aac"
    end
    audio_fix.effective_mode = effective_mode
    audio_fix.silence_active = effective_mode == "silence"

    local proxy_switch = udp_switch({
        addr = "127.0.0.1",
        port = 0,
    })
    local listen_port = proxy_switch and proxy_switch:port() or nil
    if not listen_port or listen_port <= 0 then
        audio_fix.last_error = "udp_switch init failed"
        log.error("[stream " .. get_stream_label(channel_data) .. "] audio-fix: udp_switch init failed")
        return false
    end

    audio_fix.proxy_switch = proxy_switch
    audio_fix.proxy_listen_port = listen_port

    local output_url = "udp://127.0.0.1:" .. tostring(listen_port) .. "?pkt_size=1316"
    local args = build_audio_fix_ffmpeg_args(bin, input_url, output_url, audio_fix, effective_mode)

    local ok, proc = pcall(process.spawn, args, { stdout = "pipe", stderr = "pipe" })
    if not ok or not proc then
        audio_fix.last_error = "ffmpeg spawn failed"
        log.error("[stream " .. get_stream_label(channel_data) .. "] audio-fix: ffmpeg spawn failed")
        stop_audio_fix_process(channel_data, audio_fix)
        apply_audio_fix_upstream(channel_data)
        return false
    end

    local now = os.time()
    audio_fix.proc = proc
    audio_fix.proc_args = args
    audio_fix.proc_input_url = input_url
    audio_fix.proc_output_url = output_url
    audio_fix.state = "RUNNING"
    audio_fix.cooldown_active = false
    audio_fix.last_error = nil
    audio_fix.last_fix_start_ts = now
    audio_fix.last_restart_ts = now
    audio_fix.mismatch_since = nil
    audio_fix.last_restart_reason = reason or "mismatch"

    apply_audio_fix_upstream(channel_data)
    log.info("[stream " .. get_stream_label(channel_data) .. "] audio-fix: start (" .. tostring(reason or "mismatch") .. ")")
    return true
end

local function restart_audio_fix_process(channel_data, reason, opts)
    opts = opts or {}
    local audio_fix = channel_data and channel_data.audio_fix or nil
    if not audio_fix then
        return false
    end
    if not opts.ignore_cooldown and is_audio_fix_cooldown_active(audio_fix, os.time()) then
        audio_fix.cooldown_active = true
        audio_fix.state = "COOLDOWN"
        return false
    end
    stop_audio_fix_process(channel_data, audio_fix)
    apply_audio_fix_upstream(channel_data)
    if start_audio_fix_process(channel_data, reason or "restart", opts) then
        return true
    end
    apply_audio_fix_upstream(channel_data)
    return false
end

local function abort_audio_fix_warm_restart(audio_fix)
    local warm = audio_fix and audio_fix.warm_restart or nil
    if not warm then
        return
    end
    if warm.new_proc then
        pcall(function() warm.new_proc:terminate() end)
        pcall(function() warm.new_proc:kill() end)
        pcall(function() warm.new_proc:close() end)
        warm.new_proc = nil
    end
    if warm.old_proc and warm.old_proc ~= audio_fix.proc then
        pcall(function() warm.old_proc:terminate() end)
        pcall(function() warm.old_proc:kill() end)
        pcall(function() warm.old_proc:close() end)
        warm.old_proc = nil
    end
    audio_fix.warm_restart = nil
end

local function start_audio_fix_warm_restart(channel_data, reason, opts)
    opts = opts or {}
    local audio_fix = channel_data and channel_data.audio_fix or nil
    if not audio_fix or not audio_fix.proc or audio_fix.warm_restart then
        return false
    end
    if not opts.ignore_cooldown and is_audio_fix_cooldown_active(audio_fix, os.time()) then
        audio_fix.cooldown_active = true
        audio_fix.state = "COOLDOWN"
        return false
    end
    if not audio_fix.proxy_switch or type(audio_fix.proxy_switch.senders) ~= "function"
        or type(audio_fix.proxy_switch.set_source) ~= "function" then
        return false
    end
    if not process or type(process.spawn) ~= "function" then
        return false
    end

    local input_url, input_err = resolve_audio_fix_input_url(channel_data, audio_fix)
    if not input_url or input_url == "" then
        audio_fix.last_error = input_err or "active input url is required"
        return false
    end
    local listen_port = tonumber(audio_fix.proxy_listen_port)
    if not listen_port or listen_port <= 0 then
        return false
    end

    local bin = resolve_tool_path("ffmpeg", {
        setting_key = "ffmpeg_path",
        env_key = "ASTRA_FFMPEG_PATH",
    })

    local desired_mode = opts.effective_mode or audio_fix.effective_mode or "aac"
    if desired_mode ~= "aac" and desired_mode ~= "copy" and desired_mode ~= "silence" then
        desired_mode = "aac"
    end

    local output_url = audio_fix.proc_output_url or ("udp://127.0.0.1:" .. tostring(listen_port) .. "?pkt_size=1316")
    local args = build_audio_fix_ffmpeg_args(bin, input_url, output_url, audio_fix, desired_mode)

    local ok, proc = pcall(process.spawn, args, { stdout = "pipe", stderr = "pipe" })
    if not ok or not proc then
        return false
    end

    local old_src = nil
    if audio_fix.proxy_switch and type(audio_fix.proxy_switch.source) == "function" then
        local ok_s, src = pcall(audio_fix.proxy_switch.source, audio_fix.proxy_switch)
        if ok_s and type(src) == "table" and src.addr and src.port then
            old_src = { addr = tostring(src.addr), port = tonumber(src.port) }
        end
    end

    audio_fix.warm_restart = {
        reason = reason or "restart",
        start_ts = os.time(),
        timeout_sec = 3,
        desired_mode = desired_mode,
        old_proc = audio_fix.proc,
        old_src = old_src,
        old_args = audio_fix.proc_args,
        old_input_url = audio_fix.proc_input_url,
        old_output_url = audio_fix.proc_output_url,
        old_effective_mode = audio_fix.effective_mode,
        old_silence_active = audio_fix.silence_active,
        new_proc = proc,
        new_args = args,
        new_input_url = input_url,
        new_output_url = output_url,
        last_error = nil,
        switched = false,
        cutover_ts = nil,
        old_term_ts = nil,
    }
    return true
end

local function tick_audio_fix_warm_restart(channel_data, now)
    local audio_fix = channel_data and channel_data.audio_fix or nil
    local warm = audio_fix and audio_fix.warm_restart or nil
    if not warm then
        return
    end

    -- If config was disabled while warm restart was in-flight, stop the standby proc.
    if not (audio_fix and audio_fix.config and audio_fix.config.enabled) then
        abort_audio_fix_warm_restart(audio_fix)
        apply_audio_fix_upstream(channel_data)
        return
    end

    if warm.new_proc then
        local err_chunk = warm.new_proc:read_stderr()
        if err_chunk then
            consume_lines(warm, "stderr_buf", err_chunk, function(line)
                if line ~= "" then
                    warm.last_error = line
                end
            end)
        end
        local st = warm.new_proc:poll()
        if st then
            pcall(function() warm.new_proc:close() end)
            warm.new_proc = nil
            warm.new_exit_status = st
            if not warm.switched then
                -- Standby failed; keep old proc running.
                audio_fix.last_error = warm.last_error or "ffmpeg exited"
                audio_fix.warm_restart = nil
                return
            end
        end
    end

    if not warm.switched then
        local senders = {}
        do
            local ok_s, s = pcall(audio_fix.proxy_switch.senders, audio_fix.proxy_switch)
            if ok_s and type(s) == "table" then
                senders = s
            end
        end

        local best = nil
        local old_port = warm.old_src and warm.old_src.port or nil
        for _, entry in ipairs(senders) do
            if type(entry) == "table" and entry.addr and entry.port then
                local port = tonumber(entry.port)
                if port and port > 0 then
                    if not old_port or port ~= old_port then
                        local ts = tonumber(entry.last_seen_ts) or 0
                        if not best or ts >= (best.last_seen_ts or 0) then
                            best = { addr = tostring(entry.addr), port = port, last_seen_ts = ts }
                        end
                    end
                end
            end
        end

        if best and warm.new_proc then
            local ok_call, ok_set = pcall(audio_fix.proxy_switch.set_source, audio_fix.proxy_switch, best.addr, best.port)
            if ok_call and ok_set then
                warm.switched = true

                -- Ownership transfer: new proc becomes the main proc for normal tick_* handling.
                audio_fix.proc = warm.new_proc
                audio_fix.proc_args = warm.new_args
                audio_fix.proc_input_url = warm.new_input_url
                audio_fix.proc_output_url = warm.new_output_url
                audio_fix.effective_mode = warm.desired_mode
                audio_fix.silence_active = warm.desired_mode == "silence"
                audio_fix.last_error = nil
                audio_fix.last_fix_start_ts = now
                audio_fix.last_restart_ts = now
                audio_fix.last_restart_reason = warm.reason

                warm.new_proc = nil
                -- Delay stopping the old proc: keep it around briefly so we can revert
                -- if the new proc exits immediately after cutover.
                warm.cutover_ts = now
                warm.old_term_ts = nil
            end
        end

        if not warm.switched and (now - (warm.start_ts or now)) >= (warm.timeout_sec or 3) then
            -- Timeout: stop standby and keep the current proc.
            if warm.new_proc then
                pcall(function() warm.new_proc:terminate() end)
                pcall(function() warm.new_proc:kill() end)
                pcall(function() warm.new_proc:close() end)
                warm.new_proc = nil
            end
            audio_fix.warm_restart = nil
            return
        end
    end

    if warm.switched and warm.old_proc then
        local st_old = warm.old_proc:poll()
        if st_old then
            pcall(function() warm.old_proc:close() end)
            warm.old_proc = nil
        else
            if not warm.old_term_ts then
                local cut_ts = warm.cutover_ts or now
                if (now - cut_ts) >= 1 then
                    pcall(function() warm.old_proc:terminate() end)
                    warm.old_term_ts = now
                else
                    return
                end
            end
            if (now - (warm.old_term_ts or now)) >= 2 then
                pcall(function() warm.old_proc:kill() end)
            end
        end
    end

    if warm.switched and warm.old_proc == nil then
        audio_fix.warm_restart = nil
    end
end

local function build_ffprobe_input_audio_args(url, ffprobe_bin)
    local bin = ffprobe_bin or "ffprobe"
    return {
        bin,
        "-v",
        "error",
        "-print_format",
        "json",
        "-select_streams",
        "a:0",
        "-show_entries",
        "stream=codec_name,codec_type,profile,sample_rate,channels,bit_rate",
        "-show_streams",
        "-i",
        tostring(url),
    }
end

local function start_audio_fix_input_probe(channel_data, audio_fix)
    if not audio_fix or not audio_fix.config.enabled then
        return
    end
    if audio_fix.input_probe then
        return
    end
    if not process or type(process.spawn) ~= "function" then
        audio_fix.input_probe_error = "process module not available"
        return
    end
    local input_url, input_err = resolve_audio_fix_input_url(channel_data, audio_fix)
    if not input_url or input_url == "" then
        audio_fix.input_probe_error = input_err or "active input url is required"
        return
    end
    local ffprobe_bin = resolve_ffprobe_bin()
    local args = build_ffprobe_input_audio_args(input_url, ffprobe_bin)
    local ok, proc = pcall(process.spawn, args, { stdout = "pipe", stderr = "pipe" })
    if not ok or not proc then
        audio_fix.input_probe_error = "ffprobe spawn failed"
        return
    end
    audio_fix.input_probe_error = nil
    audio_fix.input_probe = {
        proc = proc,
        stdout_buf = "",
        stderr_buf = "",
        start_ts = os.time(),
        timeout_sec = tonumber(audio_fix.config.input_probe_timeout_sec) or AUDIO_FIX_INPUT_PROBE_TIMEOUT_DEFAULT,
        input_url = input_url,
    }
end

local function handle_audio_fix_input_probe_result(audio_fix, info, err, now)
    audio_fix.input_probe_ts = now
    audio_fix.input_probe_error = err
    audio_fix.input_audio = info
    audio_fix.input_audio_missing = info and info.missing or false
end

local function tick_audio_fix_input_probe(channel_data, audio_fix, now)
    local probe = audio_fix and audio_fix.input_probe or nil
    if not probe or not probe.proc then
        return
    end

    local out_chunk = probe.proc:read_stdout()
    if out_chunk then
        probe.stdout_buf = (probe.stdout_buf or "") .. out_chunk
    end

    local err_chunk = probe.proc:read_stderr()
    if err_chunk then
        probe.stderr_buf = (probe.stderr_buf or "") .. err_chunk
    end

    local status = probe.proc:poll()
    if status or (now - probe.start_ts) >= (probe.timeout_sec or AUDIO_FIX_INPUT_PROBE_TIMEOUT_DEFAULT) then
        if not status then
            probe.proc:kill()
        end
        probe.proc:close()
        audio_fix.input_probe = nil

        local err = nil
        local info = nil
        local decoded = nil
        if probe.stdout_buf and probe.stdout_buf ~= "" and json and json.decode then
            local ok, parsed = pcall(json.decode, probe.stdout_buf)
            if ok and type(parsed) == "table" then
                decoded = parsed
            end
        end
        if decoded and type(decoded.streams) == "table" then
            if decoded.streams[1] then
                local s = decoded.streams[1]
                info = {
                    missing = false,
                    codec_name = s.codec_name,
                    profile = s.profile,
                    sample_rate = tonumber(s.sample_rate),
                    channels = tonumber(s.channels),
                    bit_rate = tonumber(s.bit_rate),
                }
            else
                info = { missing = true }
                err = "audio_missing"
            end
        else
            local timeout = (probe.timeout_sec or AUDIO_FIX_INPUT_PROBE_TIMEOUT_DEFAULT)
            if (now - probe.start_ts) >= timeout and not status then
                err = "ffprobe_timeout"
            else
                err = "ffprobe_failed"
            end
        end
        handle_audio_fix_input_probe_result(audio_fix, info, err, now)
        audio_fix.next_input_probe_ts = now + (audio_fix.config.probe_interval_sec or AUDIO_FIX_PROBE_INTERVAL_DEFAULT)
    end
end

local function build_ffprobe_pts_args(url, stream_spec, ffprobe_bin)
    local bin = ffprobe_bin or "ffprobe"
    return {
        bin,
        "-v",
        "error",
        "-select_streams",
        tostring(stream_spec),
        "-show_entries",
        "packet=pts_time",
        "-of",
        "csv=p=0",
        "-show_packets",
        tostring(url),
    }
end

local function build_audio_fix_output_url(channel_data)
    if not (channel_data and channel_data.config and channel_data.config.id) then
        return nil
    end
    if not (config and config.get_setting) then
        return nil
    end
    local port = tonumber(config.get_setting("http_port"))
    if not port or port <= 0 then
        return nil
    end
    -- /play — это "выходной" поток (включая audio-fix, если он активен).
    return "http://127.0.0.1:" .. tostring(port) .. "/play/" .. tostring(channel_data.config.id) .. "?internal=1"
end

local function start_audio_fix_drift_probe(channel_data, audio_fix)
    if not audio_fix or not audio_fix.config or not audio_fix.config.drift_probe_enabled then
        return
    end
    if audio_fix.drift_probe then
        return
    end
    if not process or type(process.spawn) ~= "function" then
        return
    end
    -- Drift probe не должен конкурировать за UDP порт с udp_switch. Используем внутренний /play loopback.
    local url = build_audio_fix_output_url(channel_data)
    if not url then
        return
    end
    local ffprobe_bin = resolve_ffprobe_bin()
    local audio_args = build_ffprobe_pts_args(url, "a:0", ffprobe_bin)
    local video_args = build_ffprobe_pts_args(url, "v:0", ffprobe_bin)
    local ok_a, proc_a = pcall(process.spawn, audio_args, { stdout = "pipe", stderr = "pipe" })
    local ok_v, proc_v = pcall(process.spawn, video_args, { stdout = "pipe", stderr = "pipe" })
    if not ok_a or not proc_a or not ok_v or not proc_v then
        if proc_a then proc_a:kill(); proc_a:close() end
        if proc_v then proc_v:kill(); proc_v:close() end
        return
    end
    local now = os.time()
    local duration = tonumber(audio_fix.config.drift_probe_duration_sec) or AUDIO_FIX_DRIFT_PROBE_DURATION_DEFAULT
    if duration < 1 then duration = 1 end
    audio_fix.drift_probe = {
        audio = { proc = proc_a, stdout_buf = "", last_pts = nil },
        video = { proc = proc_v, stdout_buf = "", last_pts = nil },
        start_ts = now,
        timeout_sec = duration + 2,
        duration_sec = duration,
    }
end

local function parse_pts_lines(target, chunk)
    if not chunk or chunk == "" then
        return
    end
    target.stdout_buf = (target.stdout_buf or "") .. chunk
    while true do
        local line, rest = target.stdout_buf:match("^(.-)\n(.*)$")
        if not line then
            break
        end
        target.stdout_buf = rest
        local value = tonumber(line:gsub("\r$", ""))
        if value then
            target.last_pts = value
        end
    end
end

local function finalize_audio_fix_drift_probe(channel_data, audio_fix, now)
    local probe = audio_fix and audio_fix.drift_probe or nil
    if not probe then
        return
    end
    local a_pts = probe.audio and probe.audio.last_pts or nil
    local v_pts = probe.video and probe.video.last_pts or nil
    audio_fix.drift_probe = nil
    audio_fix.last_drift_ts = now

    if a_pts == nil or v_pts == nil then
        return
    end
    local drift_ms = math.floor(math.abs(a_pts - v_pts) * 1000 + 0.5)
    audio_fix.last_drift_ms = drift_ms
    local threshold = tonumber(audio_fix.config.drift_threshold_ms) or AUDIO_FIX_DRIFT_THRESHOLD_MS_DEFAULT
    local max_fail = tonumber(audio_fix.config.drift_fail_count) or AUDIO_FIX_DRIFT_FAIL_COUNT_DEFAULT
    if max_fail < 1 then max_fail = 1 end
    if threshold < 0 then threshold = 0 end

    if drift_ms > threshold then
        audio_fix.drift_fail_streak = (audio_fix.drift_fail_streak or 0) + 1
        if audio_fix.drift_fail_streak >= max_fail then
            emit_stream_alert(channel_data, "WARNING", "AUDIO_FIX_DRIFT_HIGH", "audio drift too high", {
                drift_ms = drift_ms,
                threshold_ms = threshold,
            })
            if audio_fix.config.restart_on_drift then
                local restart_opts = { ignore_cooldown = true }
                if not start_audio_fix_warm_restart(channel_data, "audio_drift", restart_opts) then
                    restart_audio_fix_process(channel_data, "audio_drift", restart_opts)
                end
            end
            audio_fix.drift_fail_streak = 0
        end
    else
        audio_fix.drift_fail_streak = 0
    end
end

local function tick_audio_fix_drift_probe(channel_data, audio_fix, now)
    local probe = audio_fix and audio_fix.drift_probe or nil
    if not probe then
        return
    end

    if probe.audio and probe.audio.proc then
        local chunk = probe.audio.proc:read_stdout()
        if chunk then
            parse_pts_lines(probe.audio, chunk)
        end
    end
    if probe.video and probe.video.proc then
        local chunk = probe.video.proc:read_stdout()
        if chunk then
            parse_pts_lines(probe.video, chunk)
        end
    end

    local a_done = true
    local v_done = true
    if probe.audio and probe.audio.proc then
        local st = probe.audio.proc:poll()
        if st then
            probe.audio.proc:close()
            probe.audio.proc = nil
        else
            a_done = false
        end
    end
    if probe.video and probe.video.proc then
        local st = probe.video.proc:poll()
        if st then
            probe.video.proc:close()
            probe.video.proc = nil
        else
            v_done = false
        end
    end

    if (now - (probe.start_ts or now)) >= (probe.timeout_sec or (AUDIO_FIX_DRIFT_PROBE_DURATION_DEFAULT + 2)) then
        if probe.audio and probe.audio.proc then
            probe.audio.proc:kill()
            probe.audio.proc:close()
            probe.audio.proc = nil
        end
        if probe.video and probe.video.proc then
            probe.video.proc:kill()
            probe.video.proc:close()
            probe.video.proc = nil
        end
        finalize_audio_fix_drift_probe(channel_data, audio_fix, now)
        return
    end

    if a_done and v_done then
        finalize_audio_fix_drift_probe(channel_data, audio_fix, now)
    end
end

local function extract_first_audio_type_id(info)
    if type(info) ~= "table" then
        return nil
    end
    local streams = info.streams
    if type(streams) ~= "table" then
        return nil
    end
    for _, s in ipairs(streams) do
        if type(s) == "table" and s.type_name == "AUDIO" and s.type_id ~= nil then
            local v = tonumber(s.type_id)
            if v ~= nil then
                return v
            end
        end
    end
    return nil
end

local function start_audio_fix_probe(channel_data, audio_fix)
    if not audio_fix or not audio_fix.config.enabled then
        return
    end
    if audio_fix.probe then
        return
    end
    -- Module constructors may be callable tables (metatable __call), not plain functions.
    if not analyze then
        audio_fix.last_error = "analyze module not available"
        return
    end
    local limit = get_audio_fix_analyze_limit()
    if audio_fix_analyze_active >= limit then
        audio_fix.analyze_pending = true
        return
    end

    local upstream = nil
    if audio_fix.proc and audio_fix.proxy_switch and type(audio_fix.proxy_switch.stream) == "function" then
        upstream = audio_fix.proxy_switch:stream()
    else
        upstream = get_audio_fix_raw_upstream(channel_data)
    end
    if not upstream then
        audio_fix.last_error = "probe upstream unavailable"
        return
    end

    local probe = {
        analyzer = nil,
        detected_type = nil,
        last_error = nil,
        analyze_slot = true,
        start_ts = os.time(),
        duration_sec = math.max(1, tonumber(audio_fix.config.probe_duration_sec) or AUDIO_FIX_PROBE_DURATION_DEFAULT),
    }

    local ok, analyzer = pcall(analyze, {
        upstream = upstream,
        name = get_stream_label(channel_data) .. ":audio-fix",
        join_pid = true,
        callback = function(data)
            if type(data) ~= "table" then
                return
            end
            if data.error then
                probe.last_error = tostring(data.error)
                return
            end
            if data.psi == "pmt" then
                local t = extract_first_audio_type_id(data)
                if t ~= nil then
                    probe.detected_type = t
                end
            end
        end,
    })
    if not ok or not analyzer then
        audio_fix.last_error = "analyze init failed"
        return
    end
    audio_fix_analyze_active = audio_fix_analyze_active + 1
    audio_fix.analyze_pending = false
    probe.analyzer = analyzer
    audio_fix.probe = probe
end

local function handle_audio_fix_probe_result(channel_data, audio_fix, detected_type, err, now)
    audio_fix.last_probe_ts = now
    audio_fix.detected_audio_type = detected_type
    audio_fix.detected_audio_type_hex = format_audio_type_hex(detected_type)
    audio_fix.last_error = err

    local type_mismatch = detected_type ~= nil and detected_type ~= audio_fix.config.target_audio_type
    local unknown = detected_type == nil
    local mismatch = type_mismatch or (unknown and not audio_fix.proc and not is_audio_fix_force_run(audio_fix.config))
    if mismatch then
        if not audio_fix.mismatch_since then
            audio_fix.mismatch_since = now
        end
    else
        audio_fix.mismatch_since = nil
    end

    local hold = audio_fix.config.mismatch_hold_sec or AUDIO_FIX_MISMATCH_HOLD_DEFAULT
    if mismatch and audio_fix.mismatch_since and (now - audio_fix.mismatch_since) >= hold then
        local restart_opts = { effective_mode = "aac" }
        -- Use restart helper for both start and restart paths so restart_cooldown_sec is respected
        -- and we don't thrash when ffmpeg exits quickly.
        local restarted = start_audio_fix_warm_restart(channel_data, "audio_mismatch", restart_opts)
        if not restarted then
            restarted = restart_audio_fix_process(channel_data, "audio_mismatch", restart_opts)
        end
        if restarted then
            audio_fix.state = "RUNNING"
        end
    elseif audio_fix.proc then
        audio_fix.state = audio_fix.cooldown_active and "COOLDOWN" or "RUNNING"
    else
        audio_fix.state = audio_fix.cooldown_active and "COOLDOWN" or "PROBING"
    end

    if audio_fix.proc and audio_fix.config.auto_disable_when_ok and detected_type ~= nil and not mismatch
        and not is_audio_fix_force_run(audio_fix.config) then
        stop_audio_fix_process(channel_data, audio_fix)
        apply_audio_fix_upstream(channel_data)
        audio_fix.state = "PROBING"
    end
end

local function tick_audio_fix_probe(channel_data, audio_fix, now)
    local probe = audio_fix and audio_fix.probe or nil
    if not probe or not probe.analyzer then
        return
    end
    local duration = tonumber(probe.duration_sec) or AUDIO_FIX_PROBE_DURATION_DEFAULT
    if (now - (probe.start_ts or now)) < duration then
        return
    end
    local detected = probe.detected_type
    local perr = probe.last_error
    stop_audio_fix_probe(audio_fix)

    local err = nil
    if not detected then
        err = perr or "audio_type_not_found"
    end
    handle_audio_fix_probe_result(channel_data, audio_fix, detected, err, now)
    audio_fix.next_probe_ts = now + (audio_fix.config.probe_interval_sec or AUDIO_FIX_PROBE_INTERVAL_DEFAULT)
end

local function tick_audio_fix_process(channel_data, audio_fix, now)
    if not audio_fix or not audio_fix.proc then
        return
    end
    local err_chunk = audio_fix.proc:read_stderr()
    if err_chunk then
        consume_lines(audio_fix, "proc_stderr_buf", err_chunk, function(line)
            if line ~= "" then
                audio_fix.last_error = line
            end
        end)
    end
    local status = audio_fix.proc:poll()
    if status then
        audio_fix.proc:close()
        audio_fix.proc = nil
        audio_fix.last_error = audio_fix.last_error or "ffmpeg exited"
        audio_fix.last_exit_status = status
        log.error("[stream " .. get_stream_label(channel_data) .. "] audio-fix: ffmpeg exited (" ..
            tostring(audio_fix.last_error) .. ", status=" .. tostring(status) .. ")")
        local warm = audio_fix.warm_restart
        if warm and warm.switched then
            -- New proc died right after cutover. Try to revert to the old proc (if still alive).
            if not warm.old_term_ts and warm.old_proc and warm.old_src and audio_fix.proxy_switch
                and type(audio_fix.proxy_switch.set_source) == "function" then
                local st_old = warm.old_proc:poll()
                if st_old then
                    pcall(function() warm.old_proc:close() end)
                    warm.old_proc = nil
                end
                local ok_call, ok_set = pcall(audio_fix.proxy_switch.set_source, audio_fix.proxy_switch,
                    tostring(warm.old_src.addr), tonumber(warm.old_src.port))
                if ok_call and ok_set and warm.old_proc then
                    audio_fix.proc = warm.old_proc
                    audio_fix.proc_args = warm.old_args
                    audio_fix.proc_input_url = warm.old_input_url
                    audio_fix.proc_output_url = warm.old_output_url
                    audio_fix.effective_mode = warm.old_effective_mode or "aac"
                    audio_fix.silence_active = warm.old_silence_active == true
                    warm.old_proc = nil
                    audio_fix.warm_restart = nil
                    return
                end
            end
            -- Revert failed; fall back to passthrough.
            stop_audio_fix_process(channel_data, audio_fix)
            apply_audio_fix_upstream(channel_data)
        elseif not warm then
            stop_audio_fix_process(channel_data, audio_fix)
            apply_audio_fix_upstream(channel_data)
        end
    end
end

local function is_audio_fix_auto_copy_match(audio_fix)
    if not audio_fix or not audio_fix.config or audio_fix.config.mode ~= "auto" then
        return false
    end
    local info = audio_fix.input_audio
    if not info or info.missing then
        return false
    end
    if tostring(info.codec_name or ""):lower() ~= "aac" then
        return false
    end
    local sr = tonumber(info.sample_rate)
    local ch = tonumber(info.channels)
    if not sr or not ch then
        return false
    end
    if sr ~= tonumber(audio_fix.config.aac_sample_rate) then
        return false
    end
    if ch ~= tonumber(audio_fix.config.aac_channels) then
        return false
    end
    if audio_fix.config.auto_copy_require_lc then
        local prof = tostring(info.profile or ""):lower()
        if not prof:find("lc", 1, true) then
            return false
        end
    end
    return true
end

local function pick_audio_fix_effective_mode(audio_fix)
    if not audio_fix or not audio_fix.config then
        return "aac"
    end
    local current = audio_fix.effective_mode or "aac"

    if audio_fix.config.silence_fallback then
        -- When ffprobe temporarily fails, avoid flip-flopping between silence/aac/copy.
        if audio_fix.input_audio and audio_fix.input_audio.missing == true then
            return "silence"
        end
        if audio_fix.proc and audio_fix.input_probe_error ~= nil then
            return current
        end
    end

    if audio_fix.config.mode == "auto" then
        -- Auto mode depends on ffprobe input probe to decide whether we can safely copy audio.
        -- Keep the current mode when ffprobe didn't provide a valid descriptor to avoid frequent
        -- warm restarts (output "jerks") on transient probe errors/timeouts.
        if audio_fix.proc and (audio_fix.input_audio == nil or audio_fix.input_probe_error ~= nil) then
            return current
        end
        if is_audio_fix_auto_copy_match(audio_fix) then
            return "copy"
        end
        return "aac"
    end

    return "aac"
end

local function audio_fix_tick(channel_data)
    local now = os.time()
    local audio_fix = channel_data and channel_data.audio_fix or nil
    if not audio_fix then
        -- Инициализация должна происходить в channel_audio_fix_init(), но на всякий случай
        -- делаем защиту для старых/частично созданных каналов.
        audio_fix = {
            config = normalize_audio_fix_config(channel_data and channel_data.config and channel_data.config.audio_fix or nil),
            state = "OFF",
            detected_audio_type = nil,
            detected_audio_type_hex = nil,
            last_probe_ts = nil,
            last_error = nil,
            mismatch_since = nil,
            next_probe_ts = nil,
            next_input_probe_ts = nil,
            next_drift_probe_ts = nil,
            proc = nil,
            proc_args = nil,
            proc_input_url = nil,
            proc_output_url = nil,
            probe = nil,
            input_probe = nil,
            input_probe_ts = nil,
            input_probe_error = nil,
            input_audio = nil,
            input_audio_missing = false,
            effective_mode = "aac",
            silence_active = false,
            last_restart_reason = nil,
            last_drift_ms = nil,
            last_drift_ts = nil,
            drift_fail_streak = 0,
            drift_probe = nil,
            cooldown_active = false,
            last_fix_start_ts = nil,
            last_restart_ts = nil,
            warm_restart = nil,
        }
        channel_data.audio_fix = audio_fix
    end

    -- Обновляем конфиг из stream-level cfg.audio_fix.
    audio_fix.config = normalize_audio_fix_config(channel_data and channel_data.config and channel_data.config.audio_fix or audio_fix.config)
    if audio_fix.cooldown_active and not is_audio_fix_cooldown_active(audio_fix, now) then
        audio_fix.cooldown_active = false
    end

    if not audio_fix.config.enabled then
        abort_audio_fix_warm_restart(audio_fix)
        stop_audio_fix_probe(audio_fix)
        stop_audio_fix_input_probe(audio_fix)
        stop_audio_fix_drift_probe(audio_fix)
        stop_audio_fix_process(channel_data, audio_fix)
        apply_audio_fix_upstream(channel_data)

        audio_fix.state = "OFF"
        audio_fix.mismatch_since = nil
        audio_fix.next_probe_ts = nil
        audio_fix.next_input_probe_ts = nil
        audio_fix.next_drift_probe_ts = nil

        if channel_data.audio_fix_timer then
            channel_data.audio_fix_timer:close()
            channel_data.audio_fix_timer = nil
        end
        channel_data.__need_audio_fix_tick = nil
        return
    end

    if audio_fix.state == "OFF" then
        audio_fix.state = "PROBING"
    end

    tick_audio_fix_warm_restart(channel_data, now)
    tick_audio_fix_process(channel_data, audio_fix, now)
    tick_audio_fix_probe(channel_data, audio_fix, now)
    tick_audio_fix_input_probe(channel_data, audio_fix, now)
    tick_audio_fix_drift_probe(channel_data, audio_fix, now)

    if audio_fix.analyze_pending and audio_fix.probe == nil then
        start_audio_fix_probe(channel_data, audio_fix)
    end

    if audio_fix.probe == nil and (audio_fix.next_probe_ts == nil or now >= audio_fix.next_probe_ts) then
        start_audio_fix_probe(channel_data, audio_fix)
    end

    local need_input_probe = audio_fix.config.mode == "auto" or audio_fix.config.silence_fallback == true
    if need_input_probe and audio_fix.input_probe == nil and
        (audio_fix.next_input_probe_ts == nil or now >= audio_fix.next_input_probe_ts) then
        start_audio_fix_input_probe(channel_data, audio_fix)
    end

    if audio_fix.config.drift_probe_enabled then
        if audio_fix.next_drift_probe_ts == nil then
            audio_fix.next_drift_probe_ts = now + (audio_fix.config.drift_probe_interval_sec or AUDIO_FIX_DRIFT_PROBE_INTERVAL_DEFAULT)
        end
        if audio_fix.drift_probe == nil and now >= audio_fix.next_drift_probe_ts then
            start_audio_fix_drift_probe(channel_data, audio_fix)
            audio_fix.next_drift_probe_ts = now + (audio_fix.config.drift_probe_interval_sec or AUDIO_FIX_DRIFT_PROBE_INTERVAL_DEFAULT)
        end
    else
        audio_fix.next_drift_probe_ts = nil
    end

    local desired_mode = pick_audio_fix_effective_mode(audio_fix)
    if is_audio_fix_force_run(audio_fix.config) then
        if desired_mode == "silence" and not audio_fix.silence_active then
            emit_stream_alert(channel_data, "WARNING", "AUDIO_FIX_SILENCE_FALLBACK",
                "audio missing, injecting silence", {})
        end
        if not audio_fix.proc then
            start_audio_fix_process(channel_data, "force_on", {
                effective_mode = desired_mode,
            })
        elseif desired_mode ~= (audio_fix.effective_mode or "aac") and not is_audio_fix_cooldown_active(audio_fix, now) then
            if not start_audio_fix_warm_restart(channel_data, "mode_change", {
                    effective_mode = desired_mode,
                }) then
                restart_audio_fix_process(channel_data, "mode_change", {
                    effective_mode = desired_mode,
                })
            end
        end
    end

    if audio_fix.proc then
        audio_fix.state = audio_fix.cooldown_active and "COOLDOWN" or "RUNNING"
    else
        audio_fix.state = audio_fix.cooldown_active and "COOLDOWN" or "PROBING"
    end

    apply_audio_fix_upstream(channel_data)
end

local audio_fix_housekeeping_timer = nil

local function ensure_audio_fix_housekeeping_timer()
    if audio_fix_housekeeping_timer then
        return
    end
    audio_fix_housekeeping_timer = timer({
        interval = 1,
        callback = function(self)
            local any = false
            for _, channel_data in pairs(channel_list or {}) do
                if channel_data and channel_data.__need_audio_fix_tick then
                    any = true
                    audio_fix_tick(channel_data)
                end
            end
            if not any then
                self:close()
                audio_fix_housekeeping_timer = nil
            end
        end,
    })
end

local function ensure_audio_fix_timer(channel_data)
    if use_aggregated_stream_timers() then
        channel_data.__need_audio_fix_tick = true
        ensure_audio_fix_housekeeping_timer()
        return
    end
    if channel_data.audio_fix_timer then
        return
    end
    channel_data.audio_fix_timer = timer({
        interval = 1,
        callback = function()
            audio_fix_tick(channel_data)
        end,
    })
end

function stream_reconfigure_timer_mode()
    local aggregate = use_aggregated_stream_timers()
    local need_failover = false
    local need_audio_fix = false

    if aggregate then
        for _, channel_data in pairs(channel_list or {}) do
            if channel_data then
                if channel_data.failover_timer then
                    channel_data.failover_timer:close()
                    channel_data.failover_timer = nil
                end
                if channel_data.failover and channel_data.failover.enabled and channel_data.failover.paused ~= true then
                    channel_data.__need_failover_tick = true
                    need_failover = true
                end

                if channel_data.audio_fix_timer then
                    channel_data.audio_fix_timer:close()
                    channel_data.audio_fix_timer = nil
                end
                channel_data.__need_audio_fix_tick = nil
                local audio_fix = channel_data.audio_fix
                if audio_fix and audio_fix.config and audio_fix.config.enabled then
                    channel_data.__need_audio_fix_tick = true
                    need_audio_fix = true
                end
            end
        end
        if need_failover then
            ensure_failover_housekeeping_timer()
        end
        if need_audio_fix then
            ensure_audio_fix_housekeeping_timer()
        end
        return
    end

    if failover_housekeeping_timer then
        failover_housekeeping_timer:close()
        failover_housekeeping_timer = nil
    end
    if audio_fix_housekeeping_timer then
        audio_fix_housekeeping_timer:close()
        audio_fix_housekeeping_timer = nil
    end

    for _, channel_data in pairs(channel_list or {}) do
        if channel_data then
            channel_data.__need_failover_tick = nil
            if channel_data.failover and channel_data.failover.enabled and channel_data.failover.paused ~= true then
                ensure_failover_timer(channel_data)
            end

            channel_data.__need_audio_fix_tick = nil
            local audio_fix = channel_data.audio_fix
            if audio_fix and audio_fix.config and audio_fix.config.enabled then
                ensure_audio_fix_timer(channel_data)
            end
        end
    end
end

local function derive_legacy_audio_fix_config(channel_data)
    for _, output_data in ipairs(channel_data.output or {}) do
        local conf = output_data and output_data.config and output_data.config.audio_fix or nil
        if type(conf) == "table" then
            return conf
        end
    end
    return nil
end

local function channel_audio_fix_init(channel_data)
    local raw = nil
    if channel_data and channel_data.config and type(channel_data.config.audio_fix) == "table" then
        raw = channel_data.config.audio_fix
    else
        -- Backward compatibility: старые конфиги хранили audio_fix внутри UDP output.
        raw = derive_legacy_audio_fix_config(channel_data)
    end

    channel_data.audio_fix = {
        config = normalize_audio_fix_config(raw),
        state = "OFF",
        detected_audio_type = nil,
        detected_audio_type_hex = nil,
        last_probe_ts = nil,
        last_error = nil,
        mismatch_since = nil,
        next_probe_ts = os.time(),
        next_input_probe_ts = os.time(),
        next_drift_probe_ts = nil,
        proc = nil,
        proc_args = nil,
        proc_input_url = nil,
        proc_output_url = nil,
        probe = nil,
        input_probe = nil,
        input_probe_ts = nil,
        input_probe_error = nil,
        input_audio = nil,
        input_audio_missing = false,
        effective_mode = "aac",
        silence_active = false,
        last_restart_reason = nil,
        last_drift_ms = nil,
        last_drift_ts = nil,
        drift_fail_streak = 0,
        drift_probe = nil,
        cooldown_active = false,
        last_fix_start_ts = nil,
        last_restart_ts = nil,
        warm_restart = nil,
    }

    if channel_data.audio_fix.config.enabled then
        ensure_audio_fix_timer(channel_data)
    else
        channel_data.__need_audio_fix_tick = nil
        apply_audio_fix_upstream(channel_data)
    end
end

local function channel_audio_fix_cleanup(channel_data)
    channel_data.__need_audio_fix_tick = nil
    if channel_data.audio_fix_timer then
        channel_data.audio_fix_timer:close()
        channel_data.audio_fix_timer = nil
    end
    local audio_fix = channel_data.audio_fix
    if audio_fix then
        abort_audio_fix_warm_restart(audio_fix)
        stop_audio_fix_probe(audio_fix)
        stop_audio_fix_input_probe(audio_fix)
        stop_audio_fix_drift_probe(audio_fix)
        stop_audio_fix_process(channel_data, audio_fix)
        channel_data.audio_fix = nil
    end
    apply_audio_fix_upstream(channel_data)
end

channel_audio_fix_on_input_switch = function(channel_data, prev_id, input_id, reason)
    local audio_fix = channel_data and channel_data.audio_fix or nil
    if not (audio_fix and audio_fix.config and audio_fix.config.enabled) then
        return
    end

    audio_fix.input_audio = nil
    audio_fix.input_audio_missing = false
    audio_fix.next_input_probe_ts = os.time()
    stop_audio_fix_input_probe(audio_fix)

    local force_run = is_audio_fix_force_run(audio_fix.config)
    local needs_restart = false
    if audio_fix.proc then
        -- When audio-fix reads the loopback /input URL, input switching happens inside the same
        -- HTTP stream and ffmpeg does not need a restart. Restarting causes visible "jerks".
        local base_input = build_audio_fix_input_url(channel_data)
        local cur_input = audio_fix.proc_input_url
        local using_loop = base_input and cur_input and cur_input:sub(1, #base_input) == base_input
        needs_restart = not using_loop
    elseif force_run then
        needs_restart = true
    end

    if needs_restart then
        log.info("[stream " .. get_stream_label(channel_data) .. "] audio-fix: restart due to input switch (" .. tostring(reason) .. ")")
        local restart_opts = {
            ignore_cooldown = true,
            effective_mode = "aac",
        }
        if not start_audio_fix_warm_restart(channel_data, "input_switch", restart_opts) then
            restart_audio_fix_process(channel_data, "input_switch", restart_opts)
        end
    end
end

--   oooooooo8 ooooo ooooo      o      oooo   oooo oooo   oooo ooooooooooo ooooo
-- o888     88  888   888      888      8888o  88   8888o  88   888    88   888
-- 888          888ooo888     8  88     88 888o88   88 888o88   888ooo8     888
-- 888o     oo  888   888    8oooo88    88   8888   88   8888   888    oo   888      o
--  888oooo88  o888o o888o o88o  o888o o88o    88  o88o    88  o888ooo8888 o888ooooo88

channel_list = {}

-- Создание MPTS-канала с собственным muxer.
local function make_mpts_channel(channel_config)
    if not channel_config.name then
        log.error("[make_mpts_channel] option 'name' is required")
        return nil
    end

    local services = normalize_mpts_services(channel_config.mpts_services)
    local mpts_cfg = type(channel_config.mpts_config) == "table" and channel_config.mpts_config or {}
    local adv_cfg = type(mpts_cfg.advanced) == "table" and mpts_cfg.advanced or {}
    local auto_probe = adv_cfg.auto_probe == true
    local auto_probe_duration = tonumber(adv_cfg.auto_probe_duration_sec or adv_cfg.auto_probe_duration) or 3

    local function extract_input_url(entry)
        if type(entry) == "string" then
            return entry
        end
        if type(entry) == "table" then
            if entry.url then
                return entry.url
            end
            return format_input_url(entry)
        end
        return nil
    end

    if #services == 0 and channel_config.input then
        local inputs = normalize_stream_list(channel_config.input)
        -- Если список сервисов пустой, можно попробовать авто-скан входов.
        if auto_probe then
            local seen = {}
            for _, entry in ipairs(inputs) do
                local input_url = extract_input_url(entry)
                if input_url and not seen[input_url] then
                    seen[input_url] = true
                    local scanned, err = probe_mpts_services(input_url, auto_probe_duration)
                    if scanned and #scanned > 0 then
                        for _, svc in ipairs(scanned) do
                            if not svc.input or svc.input == "" then
                                svc.input = input_url
                            end
                            table.insert(services, svc)
                        end
                    else
                        log.warning("[" .. channel_config.name .. "] auto_probe failed for " ..
                            tostring(input_url) .. ": " .. tostring(err))
                    end
                end
            end
        end
        if #services == 0 then
            for _, entry in ipairs(inputs) do
                local input_url = extract_input_url(entry)
                if input_url then
                    table.insert(services, { input = input_url })
                end
            end
        end
    end
    if #services == 0 then
        log.error("[" .. channel_config.name .. "] option 'mpts_services' is required for MPTS")
        return nil
    end

    if channel_config.output == nil then channel_config.output = {} end
    apply_stream_defaults(channel_config)
    if channel_config.timeout == nil then channel_config.timeout = 0 end
    if channel_config.enable == nil then channel_config.enable = true end
    if channel_config.http_keep_active == nil then channel_config.http_keep_active = 0 end

    if channel_config.enable == false then
        log.info("[" .. channel_config.name .. "] channel is disabled")
        return nil
    end

    local channel_data = {
        config = channel_config,
        input = {},
        output = {},
        delay = 3,
        clients = 1, -- MPTS должен работать постоянно
        is_mpts = true,
    }

    local function check_output_list()
        local url_list = channel_config.output
        local config_list = channel_data.output
        local module_list = init_output_module
        local function check_module(config)
            if not config then return false end
            if not config.format then return false end
            if not module_list[config.format] then return false end
            return true
        end
        for n, url in ipairs(url_list) do
            local item = {}
            if type(url) == "string" then
                item.config = parse_url(url)
            elseif type(url) == "table" then
                if url.url then
                    local u = parse_url(url.url)
                    for k,v in pairs(u) do url[k] = v end
                end
                item.config = url
            end
            if not check_module(item.config) then
                log.error("[" .. channel_config.name .. "] wrong output #" .. n .. " format")
                return false
            end
            item.config.name = channel_config.name .. " output #" .. n
            table.insert(config_list, item)
        end
        return true
    end

    if not check_output_list() then
        return nil
    end
    ensure_auto_hls_output(channel_config, channel_data.output)

    local mux_opts = build_mpts_mux_options(channel_config)
    channel_data.mpts_mux = mpts_mux(mux_opts)
    channel_data.tail = channel_data.mpts_mux

    local service_entries = {}
    for idx, service in ipairs(services) do
        local input_url = collect_mpts_input(service)
        if not input_url then
            log.error("[" .. channel_config.name .. "] mpts service #" .. idx .. " input is required")
            return nil
        end

        local input_cfg = parse_url(input_url)
        if not input_cfg or not input_cfg.format then
            log.error("[" .. channel_config.name .. "] wrong mpts input #" .. idx .. " format")
            return nil
        end
        local is_stream_ref = (input_cfg.format == "stream")
        if not is_stream_ref and not init_input_module[input_cfg.format] then
            log.error("[" .. channel_config.name .. "] wrong mpts input #" .. idx .. " format")
            return nil
        end
        input_cfg.name = channel_config.name .. " svc #" .. idx

        table.insert(service_entries, {
            index = idx,
            input_url = input_url,
            config = input_cfg,
            is_stream_ref = is_stream_ref,
            service = service,
        })
    end

    local shared_inputs = {}
    local shared_streams = {}

    local function release_mpts_sources()
        for _, input_data in ipairs(channel_data.input) do
            if input_data.source_channel then
                channel_release(input_data.source_channel, "mpts")
                input_data.source_channel = nil
            end
        end
    end

    for _, entry in ipairs(service_entries) do
        if entry.is_stream_ref then
            local ref_id = entry.config.stream_id or entry.config.addr or entry.config.id
            if not ref_id and entry.input_url then
                ref_id = tostring(entry.input_url):gsub("^stream://", "")
            end
            local source_channel = resolve_stream_ref(ref_id)
            if not source_channel then
                log.error("[" .. channel_config.name .. "] mpts service #" .. entry.index ..
                    " stream not found: " .. tostring(ref_id))
                release_mpts_sources()
                return nil
            end
            if source_channel.is_mpts then
                log.error("[" .. channel_config.name .. "] mpts service #" .. entry.index ..
                    " stream refers to MPTS: " .. tostring(ref_id))
                release_mpts_sources()
                return nil
            end
            if source_channel.config then
                if channel_config.id and source_channel.config.id == channel_config.id then
                    log.error("[" .. channel_config.name .. "] mpts service #" .. entry.index ..
                        " stream refers to itself: " .. tostring(ref_id))
                    release_mpts_sources()
                    return nil
                end
                if channel_config.name and source_channel.config.name == channel_config.name then
                    log.error("[" .. channel_config.name .. "] mpts service #" .. entry.index ..
                        " stream refers to itself: " .. tostring(ref_id))
                    release_mpts_sources()
                    return nil
                end
            end
            local ref_key = source_channel.config and (source_channel.config.id or source_channel.config.name) or tostring(ref_id)
            local shared = shared_streams[ref_key]
            if not shared then
                channel_retain(source_channel, "mpts")
                local input_item = {
                    source_url = entry.input_url,
                    config = entry.config,
                    is_stream_ref = true,
                    source_channel = source_channel,
                }
                table.insert(channel_data.input, input_item)
                shared = {
                    stream = source_channel.tail:stream(),
                }
                shared_streams[ref_key] = shared
            end
            entry.upstream = shared.stream
        else
            local key = entry.input_url
            local input_item = shared_inputs[key]
            if not input_item then
                input_item = {
                    source_url = entry.input_url,
                    config = entry.config,
                    is_stream_ref = false,
                }
                table.insert(channel_data.input, input_item)
                shared_inputs[key] = input_item
            end
            entry.shared_input = input_item
        end
    end

    for input_id, input_data in ipairs(channel_data.input) do
        if not input_data.is_stream_ref then
            if not channel_prepare_input(channel_data, input_id, {}) then
                log.error("[" .. channel_config.name .. "] mpts input #" .. input_id .. " init failed")
                release_mpts_sources()
                return nil
            end
        end
    end

    for _, entry in ipairs(service_entries) do
        local upstream = entry.upstream
        if not upstream then
            local input_item = entry.shared_input
            if not input_item or not input_item.input or not input_item.input.tail then
                log.error("[" .. channel_config.name .. "] mpts service #" .. entry.index .. " input is not ready")
                release_mpts_sources()
                return nil
            end
            upstream = input_item.input.tail:stream()
        end

        local svc = entry.service or {}
        local service_type_id = tonumber(svc.service_type_id)
        if service_type_id ~= nil and (service_type_id < 1 or service_type_id > 255) then
            -- service_type_id в DVB должен быть 1..255; неверные значения игнорируем.
            log.warning("[" .. channel_config.name .. "] mpts service #" .. entry.index ..
                " service_type_id должен быть 1..255; игнорируем " .. tostring(svc.service_type_id))
            service_type_id = nil
        end
        local svc_opts = {
            name = svc.name or ("svc_" .. tostring(entry.index)),
            pnr = tonumber(svc.pnr),
            service_name = svc.service_name or svc.name,
            service_provider = svc.service_provider or svc.provider_name,
            service_type_id = service_type_id,
            lcn = tonumber(svc.lcn),
            scrambled = svc.scrambled == true,
        }
        channel_data.mpts_mux:add_input(upstream, svc_opts)
    end

    channel_data.active_input_id = (#channel_data.input > 0) and 1 or 0

    for output_id in ipairs(channel_data.output) do
        channel_init_output(channel_data, output_id)
    end

    table.insert(channel_list, channel_data)
    return channel_data
end

function make_channel(channel_config)
    if channel_config and channel_config.mpts == true then
        return make_mpts_channel(channel_config)
    end
    if not channel_config.name then
        log.error("[make_channel] option 'name' is required")
        return nil
    end

    if not channel_config.input or #channel_config.input == 0 then
        log.error("[" .. channel_config.name .. "] option 'input' is required")
        return nil
    end

    if channel_config.output == nil then channel_config.output = {} end
    apply_stream_defaults(channel_config)
    apply_mpts_config(channel_config)
    if channel_config.timeout == nil then channel_config.timeout = 0 end
    if channel_config.enable == nil then channel_config.enable = true end
    if channel_config.http_keep_active == nil then channel_config.http_keep_active = 0 end

    if channel_config.enable == false then
        log.info("[" .. channel_config.name .. "] channel is disabled")
        return nil
    end

    local function bridge_output_keys(resolved)
        if type(resolved) ~= "table" then
            return nil, nil
        end
        local fmt = tostring(resolved.format or ""):lower()
        if fmt ~= "udp" and fmt ~= "rtp" then
            return nil, nil
        end
        local addr = tostring(resolved.addr or ""):lower()
        local port = tonumber(resolved.port)
        if addr == "" or not port or port <= 0 then
            return nil, nil
        end
        local localaddr = tostring(resolved.localaddr or ""):lower()
        local sync = tonumber(resolved.sync) or 0
        local strict_key = fmt .. "|" .. localaddr .. "|" .. addr .. ":" .. tostring(port) .. "|" .. tostring(sync)
        local endpoint_key = fmt .. "|" .. addr .. ":" .. tostring(port) .. "|" .. tostring(sync)
        return strict_key, endpoint_key
    end

    local function suppress_passthrough_bridge_outputs_for_transcode()
        local tc = channel_config.transcode
        if type(tc) ~= "table" or tc.enabled ~= true then
            return
        end
        local publish = tc.publish
        if type(publish) ~= "table" or #publish == 0 then
            return
        end
        local output_list = normalize_stream_list(channel_config.output)
        if type(output_list) ~= "table" or #output_list == 0 then
            return
        end

        local publish_strict = {}
        local publish_endpoint = {}
        for _, entry in ipairs(publish) do
            if type(entry) == "table" and entry.enabled ~= false then
                local kind = tostring(entry.type or ""):lower()
                if kind == "udp" or kind == "rtp" then
                    local raw = tostring(entry.url or ""):gsub("^%s+", ""):gsub("%s+$", "")
                    if raw ~= "" then
                        local resolved = resolve_io_config(raw, false)
                        local strict_key, endpoint_key = bridge_output_keys(resolved)
                        if strict_key then
                            publish_strict[strict_key] = true
                        end
                        if endpoint_key then
                            publish_endpoint[endpoint_key] = true
                        end
                    end
                end
            end
        end

        if next(publish_strict) == nil and next(publish_endpoint) == nil then
            return
        end

        local filtered = {}
        local suppressed = 0
        for _, output_entry in ipairs(output_list) do
            local resolved = resolve_io_config(output_entry, false)
            local strict_key, endpoint_key = bridge_output_keys(resolved)
            local is_bridge = strict_key ~= nil
            local duplicate = is_bridge and (publish_strict[strict_key] == true
                or (endpoint_key and publish_endpoint[endpoint_key] == true))
            if duplicate then
                suppressed = suppressed + 1
            else
                table.insert(filtered, output_entry)
            end
        end

        if suppressed > 0 then
            channel_config.output = filtered
            log.info("[" .. channel_config.name .. "] transcode enabled: suppressed " .. tostring(suppressed)
                .. " duplicate passthrough UDP/RTP outputs (published by transcode)")
        end
    end

    -- Unified OUTPUT LIST stores bridge outputs in both cfg.output and transcode.publish.
    -- During transcoding this can produce duplicate senders to the same multicast endpoint.
    -- Keep config intact, but suppress duplicate legacy bridge outputs at runtime.
    suppress_passthrough_bridge_outputs_for_transcode()

    local channel_data = {
        config = channel_config,
        input = {},
        output = {},
        delay = 3,
        clients = 0,
    }

    local function check_url_format(obj)
        local url_list = channel_config[obj]
        local config_list = channel_data[obj]
        local module_list = _G["init_" .. obj .. "_module"]
        local is_input = obj == "input"
        local function check_module(config)
            if not config then return false end
            if not config.format then return false end
            if not module_list[config.format] then return false end
            return true
        end
        for n, url in ipairs(url_list) do
            local item = {}
            if type(url) == "string" then
                if is_input then
                    item.source_url = url
                end
                item.config = parse_url(url)
            elseif type(url) == "table" then
                if is_input then
                    item.source_url = url.url or format_input_url(url)
                end
                if url.url then
                    local u = parse_url(url.url)
                    for k,v in pairs(u) do url[k] = v end
                end
                item.config = url
            end
            if not check_module(item.config) then
                log.error("[" .. channel_config.name .. "] wrong " .. obj .. " #" .. n .. " format")
                return false
            end
            item.config.name = channel_config.name .. " #" .. n
            table.insert(config_list, item)
        end
        return true
    end

    if not check_url_format("input") then return nil end
    if not check_url_format("output") then return nil end
    ensure_auto_hls_output(channel_config, channel_data.output)

    local has_backups = #channel_data.input > 1
    local backup_type = normalize_backup_type(channel_config.backup_type, has_backups)
    channel_config.backup_type = backup_type
    local no_data_timeout = read_number_opt(channel_config, "no_data_timeout_sec") or 3
    local probe_interval = read_number_opt(channel_config, "probe_interval_sec") or 3
    local stable_ok = read_number_opt(channel_config, "stable_ok_sec") or 5
    local primary_format = channel_data.input[1] and channel_data.input[1].config and channel_data.input[1].config.format
    local initial_delay = read_number_opt(channel_config, "backup_initial_delay_sec", "backup_initial_delay")
    if initial_delay == nil then
        initial_delay = default_initial_delay(primary_format)
    end
    local return_delay = read_number_opt(channel_config, "backup_return_delay_sec", "backup_return_delay") or 10
    local start_delay = read_number_opt(channel_config, "backup_start_delay_sec", "backup_start_delay") or 5
    local stop_if_all_inactive_sec = read_number_opt(channel_config,
        "stop_if_all_inactive_sec", "backup_stop_if_all_inactive_sec") or 20
    local warm_max = tonumber(channel_config.backup_active_warm_max)
    if warm_max == nil then
        warm_max = setting_number("backup_active_warm_max", 2)
    end
    if warm_max < 0 then warm_max = 0 end
    if no_data_timeout < 1 then no_data_timeout = 1 end
    if probe_interval < 0 then probe_interval = 0 end
    if stable_ok < 0 then stable_ok = 0 end
    if initial_delay < 0 then initial_delay = 0 end
    if return_delay < 0 then return_delay = 0 end
    if start_delay < 0 then start_delay = 0 end
    if stop_if_all_inactive_sec < 5 then stop_if_all_inactive_sec = 5 end

    local function sanitize_pid_list(list, name)
        if type(list) ~= "table" then
            return list
        end
        local cleaned = {}
        for _, pid in ipairs(list) do
            local value = tonumber(pid)
            if value and value >= 32 and value <= 8190 then
                table.insert(cleaned, value)
            else
                log.warning("[" .. name .. "] filter pid ignored: " .. tostring(pid))
            end
        end
        return cleaned
    end

    if channel_config.map then
        local o = channel_config.map
        if type(o) == "string" then o = o:gsub("%s+", ""):split(",") end
        if type(o) ~= "table" then
            log.error("[" .. channel_config.name .. "] option 'map' has wrong format")
            astra.exit()
        end

        local function normalize_map_key(key)
            if key == nil then
                return nil
            end
            local text = tostring(key)
            if #text <= 5 then
                return text
            end
            local dot = text:find("%.")
            if dot then
                local short = text:sub(dot + 1)
                if #short <= 5 then
                    return short
                end
            end
            return nil
        end

        local map = {}
        for _, v in ipairs(o) do
            local pair = v
            if type(v) == "string" then
                pair = v:split("=")
            end
            if type(pair) == "table" then
                local key = normalize_map_key(pair[1])
                if key then
                    table.insert(map, { key, pair[2] })
                else
                    log.warning("[" .. channel_config.name .. "] map key ignored: " .. tostring(pair[1]))
                end
            end
        end
        local function sanitize_map_list(list, name)
            if type(list) ~= "table" then
                return list
            end
            local cleaned = {}
            for _, pair in ipairs(list) do
                if type(pair) == "table" then
                    local key = normalize_map_key(pair[1])
                    if key then
                        table.insert(cleaned, { key, pair[2] })
                    else
                        log.warning("[" .. name .. "] map key ignored: " .. tostring(pair[1]))
                    end
                end
            end
            return cleaned
        end

        for _,v in ipairs(channel_data.input) do
            if v.config.map then
                v.config.map = sanitize_map_list(v.config.map, channel_config.name)
                for _,vv in ipairs(map) do table.insert(v.config.map, vv) end
            else
                v.config.map = map
            end
        end
    end

    if channel_config.filter then
        local o = channel_config.filter
        if type(o) == "string" then o = o:gsub("%s+", ""):split(",") end
        if type(o) ~= "table" then
            log.error("[" .. channel_config.name .. "] option 'filter' has wrong format")
            astra.exit()
        end
        local filter = sanitize_pid_list(o, channel_config.name)
        for _,v in ipairs(channel_data.input) do
            if v.config.filter then
                v.config.filter = sanitize_pid_list(v.config.filter, channel_config.name)
                for _,vv in ipairs(filter) do table.insert(v.config.filter, vv) end
            else
                v.config.filter = filter
            end
        end
    end

    if channel_config["filter~"] then
        local o = channel_config["filter~"]
        if type(o) == "string" then o = o:gsub("%s+", ""):split(",") end
        if type(o) ~= "table" then
            log.error("[" .. channel_config.name .. "] option 'filter~' has wrong format")
            astra.exit()
        end
        local filter_exclude = sanitize_pid_list(o, channel_config.name)
        for _,v in ipairs(channel_data.input) do
            if v.config["filter~"] then
                v.config["filter~"] = sanitize_pid_list(v.config["filter~"], channel_config.name)
                for _,vv in ipairs(filter_exclude) do table.insert(v.config["filter~"], vv) end
            else
                v.config["filter~"] = filter_exclude
            end
        end
    end

    if channel_config.set_pnr then
        for _,v in ipairs(channel_data.input) do
            if v.config.set_pnr == nil then v.config.set_pnr = channel_config.set_pnr end
        end
    end

    if channel_config.set_tsid then
        for _,v in ipairs(channel_data.input) do
            if v.config.set_tsid == nil then v.config.set_tsid = channel_config.set_tsid end
        end
    end

    local function apply_stream_flag(flag)
        if channel_config[flag] then
            for _,v in ipairs(channel_data.input) do
                if v.config[flag] == nil then v.config[flag] = true end
            end
        end
    end

    apply_stream_flag("no_sdt")
    apply_stream_flag("no_eit")
    apply_stream_flag("pass_sdt")
    apply_stream_flag("pass_eit")
    apply_stream_flag("no_reload")

    local function encode_service_text(codepage, text)
        if text == nil or text == "" or codepage == nil or codepage == "" then
            return text
        end
        local key = tostring(codepage):lower()
        local part = nil
        if key == "1" or key == "iso-8859-1" or key == "iso8859-1" or key == "8859-1" or key == "latin1" then
            part = 1
        elseif key == "5" or key == "iso-8859-5" or key == "iso8859-5" or key == "8859-5" or key == "cyrillic" then
            part = 5
        elseif key == "utf-8" or key == "utf8" then
            return text
        end
        if part and iso8859 and iso8859.encode then
            local ok, encoded = pcall(iso8859.encode, part, text)
            if ok and encoded and encoded ~= "" then
                return encoded
            end
        end
        return text
    end

    local service_provider = channel_config.service_provider
    local service_name = channel_config.service_name
    local codepage = channel_config.codepage
    if codepage then
        service_provider = encode_service_text(codepage, service_provider)
        service_name = encode_service_text(codepage, service_name)
    end

    if service_provider then
        for _,v in ipairs(channel_data.input) do
            if v.config.service_provider == nil then v.config.service_provider = service_provider end
        end
    end

    if service_name then
        for _,v in ipairs(channel_data.input) do
            if v.config.service_name == nil then v.config.service_name = service_name end
        end
    end

    if channel_config.service_type_id then
        for _,v in ipairs(channel_data.input) do
            if v.config.service_type_id == nil then v.config.service_type_id = channel_config.service_type_id end
        end
    end

    if channel_config.hbbtv_url then
        for _,v in ipairs(channel_data.input) do
            if v.config.hbbtv_url == nil then v.config.hbbtv_url = channel_config.hbbtv_url end
        end
    end

    if channel_config.cas then
        for _,v in ipairs(channel_data.input) do
            if v.config.cas == nil then v.config.cas = channel_config.cas end
        end
    end

    if #channel_data.output == 0 then
        -- Internal loop channels (used by transcode via /play) must not keep inputs running
        -- without active HTTP clients, otherwise failover would keep multiple inputs alive.
        if channel_config and channel_config.__internal_loop == true then
            channel_data.clients = 0
        else
            channel_data.clients = 1
        end
    else
        for _, o in pairs(channel_data.output) do
            if o.config.format ~= "http" or o.config.keep_active == true then
                channel_data.clients = channel_data.clients + 1
            end
        end
    end
    if channel_data.clients == 0 and tonumber(channel_data.config.http_keep_active or 0) == -1 then
        channel_data.clients = 1
    end

    channel_data.failover = {
        enabled = backup_type ~= "disabled",
        has_backups = has_backups,
        mode = backup_type,
        initial_delay = initial_delay,
        start_delay = start_delay,
        return_delay = return_delay,
        stop_if_all_inactive_sec = stop_if_all_inactive_sec,
        no_data_timeout = no_data_timeout,
        probe_interval = probe_interval,
        stable_ok = stable_ok,
        warm_max = warm_max,
        started_at = os.time(),
        paused = false,
        global_state = "RUNNING",
        passive_state = nil,
        passive_cycle_start_id = nil,
    }

    channel_data.active_input_id = 0
    -- transmit: выбирает активный input (failover/switching) и всегда выдаёт "сырой" TS.
    channel_data.transmit = transmit()
    -- tail: отдельный transmit для переключения "сырой" vs "audio-fix" без пересоздания outputs.
    channel_data.audio_fix_transmit = transmit()
    channel_data.audio_fix_transmit:set_upstream(channel_data.transmit:stream())
    channel_data.tail = channel_data.audio_fix_transmit

    if channel_data.clients > 0 then
        if channel_data.failover.enabled then
            channel_resume_failover(channel_data)
        end
        if channel_data.active_input_id == 0 then
            if not channel_activate_input(channel_data, 1, "start") then
                for input_id = 2, #channel_data.input do
                    if channel_activate_input(channel_data, input_id, "start") then
                        break
                    end
                end
            end
        end
    end

    for output_id in ipairs(channel_data.output) do
        channel_init_output(channel_data, output_id)
    end
    channel_audio_fix_init(channel_data)

    table.insert(channel_list, channel_data)
    return channel_data
end

function kill_channel(channel_data)
    if not channel_data then return nil end

    local channel_id = 0
    for key, value in pairs(channel_list) do
        if value == channel_data then
            channel_id = key
            break
        end
    end

    if channel_id == 0 then
        log.error("[kill_channel] channel is not found")
        return nil
    end

    if channel_data.is_mpts and channel_data.input then
        for _, input_data in ipairs(channel_data.input) do
            if input_data.source_channel then
                channel_release(input_data.source_channel, "mpts")
                input_data.source_channel = nil
            end
        end
    end

    if channel_data.keep_timer then
        channel_data.keep_timer:close()
        channel_data.keep_timer = nil
    end
    if channel_data.failover_timer then
        channel_data.failover_timer:close()
        channel_data.failover_timer = nil
    end
    channel_data.__need_failover_tick = nil
    channel_audio_fix_cleanup(channel_data)

    while #channel_data.input > 0 do
        channel_kill_input(channel_data, 1)
        table.remove(channel_data.input, 1)
    end
    channel_data.input = nil

    while #channel_data.output > 0 do
        channel_kill_output(channel_data, 1)
        table.remove(channel_data.output, 1)
    end
    channel_data.output = nil

    channel_data.tail = nil
    channel_data.transmit = nil
    channel_data.config = nil
    channel_data.failover = nil

    table.remove(channel_list, channel_id)
    collectgarbage()
end

function find_channel(key, value)
    for _, channel_data in pairs(channel_list) do
        if channel_data.config[key] == value then
            return channel_data
        end
    end
    return nil
end

--  oooooooo8 ooooooooooo oooooooooo  ooooooooooo      o      oooo     oooo
-- 888        88  888  88  888    888  888    88      888      8888o   888
--  888oooooo     888      888oooo88   888ooo8       8  88     88 888o8 88
--         888    888      888  88o    888    oo    8oooo88    88  888  88
-- o88oooo888    o888o    o888o  88o8 o888ooo8888 o88o  o888o o88o  8  o88o

options_usage = [[
    FILE                Stream script
]]

options = {
    ["*"] = function(idx)
        local filename = argv[idx]
        if utils.stat(filename).type == "file" then
            dofile(filename)
            return 0
        end
        return -1
    end,
}

function main()
    log.info("Starting " .. astra_brand_version())
end
