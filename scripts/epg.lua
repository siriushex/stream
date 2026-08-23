-- EPG export helpers (minimal XMLTV/JSON channels list)

epg = epg or {}

local function join_path(base, suffix)
    if not base or base == "" then
        return suffix
    end
    if not suffix or suffix == "" then
        return base
    end
    if base:sub(-1) == "/" then
        return base .. suffix
    end
    return base .. "/" .. suffix
end

local function dirname(path)
    if not path or path == "" then
        return ""
    end
    local idx = path:match("^.*()/")
    if not idx then
        return ""
    end
    return path:sub(1, idx - 1)
end

local function ensure_dir(path)
    if not path or path == "" then
        return
    end
    local stat = utils and utils.stat and utils.stat(path)
    if stat and stat.type == "directory" then
        return
    end
    os.execute("mkdir -p " .. path)
end

local function normalize_format(value)
    local text = tostring(value or ""):lower()
    if text == "json" then
        return "json"
    end
    return "xmltv"
end

local function legacy_file_destination(value)
    if type(value) ~= "string" then
        return nil
    end
    local text = value:gsub("^%s+", ""):gsub("%s+$", "")
    if text == "" then
        return nil
    end
    if text:sub(1, 7):lower() == "file://" then
        local path = text:sub(8)
        if path:sub(1, 1) == "/" then
            return path
        end
        return nil
    end
    if text:sub(1, 1) == "/" then
        return text
    end
    return nil
end

function epg.resolve_stream_config(row)
    local cfg = type(row) == "table" and row.config or nil
    if type(cfg) ~= "table" then
        return nil
    end

    local stream_id = tostring(row.id or cfg.id or "")
    local modern = cfg.epg
    if type(modern) == "table" and next(modern) ~= nil then
        local xmltv_id = tostring(modern.xmltv_id or stream_id)
        if xmltv_id == "" then
            return nil
        end
        return {
            xmltv_id = xmltv_id,
            destination = modern.destination,
            format = normalize_format(modern.format),
            codepage = modern.codepage,
            legacy = false,
        }
    end

    local destination = legacy_file_destination(cfg.epg_export)
    if not destination or stream_id == "" then
        return nil
    end
    return {
        xmltv_id = stream_id,
        destination = destination,
        format = "xmltv",
        codepage = cfg.codepage,
        legacy = true,
    }
end

local function utf8_continuation(value)
    return value ~= nil and value >= 0x80 and value <= 0xBF
end

local function sanitize_utf8(text)
    local value = tostring(text or "")
    local out = {}
    local pos = 1
    while pos <= #value do
        local first = value:byte(pos)
        if first < 0x80 then
            -- XML 1.0 permits tab, LF, CR and printable ASCII only.
            if first == 0x09 or first == 0x0A or first == 0x0D or first >= 0x20 then
                out[#out + 1] = string.char(first)
            end
            pos = pos + 1
        else
            local second = value:byte(pos + 1)
            local third = value:byte(pos + 2)
            local fourth = value:byte(pos + 3)
            local length = nil
            if first >= 0xC2 and first <= 0xDF and utf8_continuation(second) then
                length = 2
            elseif first >= 0xE0 and first <= 0xEF and utf8_continuation(third) then
                local second_ok = utf8_continuation(second)
                if first == 0xE0 then second_ok = second ~= nil and second >= 0xA0 and second <= 0xBF end
                if first == 0xED then second_ok = second ~= nil and second >= 0x80 and second <= 0x9F end
                if second_ok then length = 3 end
            elseif first >= 0xF0 and first <= 0xF4
                and utf8_continuation(third) and utf8_continuation(fourth)
            then
                local second_ok = utf8_continuation(second)
                if first == 0xF0 then second_ok = second ~= nil and second >= 0x90 and second <= 0xBF end
                if first == 0xF4 then second_ok = second ~= nil and second >= 0x80 and second <= 0x8F end
                if second_ok then length = 4 end
            end

            if length then
                out[#out + 1] = value:sub(pos, pos + length - 1)
                pos = pos + length
            else
                -- Repair a stray ISO-8859-1/Windows byte inside text that was
                -- advertised as UTF-8. This is common in live DVB EIT data.
                out[#out + 1] = string.char(0xC0 + math.floor(first / 64), 0x80 + (first % 64))
                pos = pos + 1
            end
        end
    end
    return table.concat(out)
end

local function xml_escape(text)
    local value = sanitize_utf8(text)
    value = value:gsub("&", "&amp;")
    value = value:gsub("<", "&lt;")
    value = value:gsub(">", "&gt;")
    value = value:gsub("\"", "&quot;")
    value = value:gsub("'", "&apos;")
    return value
end

local function byte_u16(data, pos)
    local hi, lo = data:byte(pos, pos + 1)
    if hi == nil or lo == nil then
        return nil
    end
    return hi * 256 + lo
end

local function bcd_byte(value)
    if value == nil then return nil end
    local hi = math.floor(value / 16)
    local lo = value % 16
    if hi > 9 or lo > 9 then return nil end
    return hi * 10 + lo
end

local function decode_dvb_text(value)
    if value == nil or value == "" then
        return ""
    end
    if iso8859 and type(iso8859.decode) == "function" then
        local ok, decoded = pcall(iso8859.decode, value)
        if ok and decoded ~= nil then
            return decoded
        end
    end
    return value
end

local function descriptor_text(data, length_pos, limit)
    local length = data:byte(length_pos)
    if length == nil then return nil, nil, "missing text length" end
    local first = length_pos + 1
    local last = first + length - 1
    if last > limit then return nil, nil, "text exceeds descriptor" end
    return decode_dvb_text(data:sub(first, last)), last + 1
end

function epg.parse_eit_section(data)
    if type(data) ~= "string" or #data < 18 then
        return nil, "EIT section is too short"
    end
    local table_id = data:byte(1)
    if table_id ~= 0x4E and not (table_id >= 0x50 and table_id <= 0x5F) then
        return nil, "not an actual EIT table"
    end
    local section_length = (data:byte(2) % 16) * 256 + data:byte(3)
    local total_length = 3 + section_length
    if total_length < 18 or #data < total_length then
        return nil, "truncated EIT section"
    end
    data = data:sub(1, total_length)

    local flags = data:byte(6)
    if flags % 2 == 0 then
        return nil, "EIT section is not current"
    end

    local parsed = {
        table_id = table_id,
        service_id = byte_u16(data, 4),
        version = math.floor(flags / 2) % 32,
        section_number = data:byte(7),
        last_section_number = data:byte(8),
        transport_stream_id = byte_u16(data, 9),
        original_network_id = byte_u16(data, 11),
        segment_last_section_number = data:byte(13),
        last_table_id = data:byte(14),
        events = {},
    }

    local events_end = total_length - 4
    local pos = 15
    while pos <= events_end do
        if pos + 11 > events_end then
            return nil, "truncated EIT event header"
        end
        local mjd = byte_u16(data, pos + 2)
        local hour = bcd_byte(data:byte(pos + 4))
        local minute = bcd_byte(data:byte(pos + 5))
        local second = bcd_byte(data:byte(pos + 6))
        local duration_h = bcd_byte(data:byte(pos + 7))
        local duration_m = bcd_byte(data:byte(pos + 8))
        local duration_s = bcd_byte(data:byte(pos + 9))
        if not hour or not minute or not second or not duration_h or not duration_m or not duration_s
            or hour > 23 or minute > 59 or second > 59 or duration_m > 59 or duration_s > 59
        then
            return nil, "invalid EIT BCD time"
        end

        local status_flags = data:byte(pos + 10)
        local descriptors_length = (status_flags % 16) * 256 + data:byte(pos + 11)
        local desc_pos = pos + 12
        local desc_end = desc_pos + descriptors_length - 1
        if desc_end > events_end then
            return nil, "EIT descriptors exceed section"
        end

        local start = (mjd - 40587) * 86400 + hour * 3600 + minute * 60 + second
        local duration = duration_h * 3600 + duration_m * 60 + duration_s
        local event = {
            event_id = byte_u16(data, pos),
            start = start,
            stop = start + duration,
            duration = duration,
            running_status = math.floor(status_flags / 32),
            free_ca = math.floor(status_flags / 16) % 2 == 1,
            title = "",
            subtitle = "",
            description = "",
            categories = {},
        }
        local extended = {}

        while desc_pos <= desc_end do
            if desc_pos + 1 > desc_end then
                return nil, "truncated EIT descriptor header"
            end
            local tag = data:byte(desc_pos)
            local length = data:byte(desc_pos + 1)
            local body = desc_pos + 2
            local limit = body + length - 1
            if limit > desc_end then
                return nil, "EIT descriptor exceeds event"
            end

            if tag == 0x4D and length >= 5 then
                event.lang = data:sub(body, body + 2)
                local title, next_pos, text_err = descriptor_text(data, body + 3, limit)
                if not title then return nil, text_err end
                local subtitle, _, subtitle_err = descriptor_text(data, next_pos, limit)
                if not subtitle then return nil, subtitle_err end
                event.title = title
                event.subtitle = subtitle
            elseif tag == 0x4E and length >= 6 then
                local descriptor_number = math.floor(data:byte(body) / 16)
                local lang = data:sub(body + 1, body + 3)
                if not event.lang or event.lang == "" then event.lang = lang end
                local items_length = data:byte(body + 4)
                local text_len_pos = body + 5 + items_length
                if text_len_pos > limit then
                    return nil, "extended-event items exceed descriptor"
                end
                local text, _, text_err = descriptor_text(data, text_len_pos, limit)
                if not text then return nil, text_err end
                extended[descriptor_number] = text
            elseif tag == 0x54 then
                local item = body
                while item + 1 <= limit do
                    local content = data:byte(item)
                    local user = data:byte(item + 1)
                    table.insert(event.categories, {
                        level1 = math.floor(content / 16),
                        level2 = content % 16,
                        user1 = math.floor(user / 16),
                        user2 = user % 16,
                    })
                    item = item + 2
                end
            end
            desc_pos = limit + 1
        end

        local parts = {}
        for number = 0, 15 do
            if extended[number] and extended[number] ~= "" then
                table.insert(parts, extended[number])
            end
        end
        event.description = table.concat(parts)
        table.insert(parsed.events, event)
        pos = desc_end + 1
    end

    return parsed
end

epg.registry = epg.registry or {}
epg.stream_status = epg.stream_status or {}

function epg.reset_registry()
    epg.registry = {}
    epg.stream_status = {}
end

local function event_key(service_id, event)
    return tostring(service_id or 0) .. ":" .. tostring(event.event_id or 0) .. ":" .. tostring(event.start or 0)
end

local function event_changed(previous, current)
    if not previous then return true end
    return previous.stop ~= current.stop
        or previous.running_status ~= current.running_status
        or previous.free_ca ~= current.free_ca
        or previous.lang ~= current.lang
        or previous.title ~= current.title
        or previous.subtitle ~= current.subtitle
        or previous.description ~= current.description
        or json.encode(previous.categories or {}) ~= json.encode(current.categories or {})
end

local function prune_registry(events, now)
    local minimum_stop = now - 86400
    local maximum_start = now + 14 * 86400
    local ordered = {}
    for key, event in pairs(events) do
        if event.stop < minimum_stop or event.start > maximum_start then
            events[key] = nil
        else
            table.insert(ordered, { key = key, start = event.start })
        end
    end
    if #ordered <= 4096 then return end
    table.sort(ordered, function(a, b) return a.start < b.start end)
    for index = 4097, #ordered do
        events[ordered[index].key] = nil
    end
end

function epg.ingest_section(stream_id, data, opts)
    opts = opts or {}
    stream_id = tostring(stream_id or "")
    if stream_id == "" then
        return false, "stream id is required"
    end
    local parsed, err = epg.parse_eit_section(data)
    if not parsed then
        local status = epg.stream_status[stream_id] or {}
        status.last_error = tostring(err or "invalid EIT")
        epg.stream_status[stream_id] = status
        return false, err
    end

    local now = tonumber(opts.now) or os.time()
    local events = epg.registry[stream_id]
    if not events then
        events = {}
        epg.registry[stream_id] = events
    end
    local changed = false
    for _, event in ipairs(parsed.events or {}) do
        event.service_id = parsed.service_id
        event.transport_stream_id = parsed.transport_stream_id
        event.original_network_id = parsed.original_network_id
        local key = event_key(parsed.service_id, event)
        if event_changed(events[key], event) then
            events[key] = event
            changed = true
        end
    end
    prune_registry(events, now)

    local count = 0
    for _ in pairs(events) do count = count + 1 end
    local status = epg.stream_status[stream_id] or {}
    status.collector = "active"
    status.last_eit_ts = now
    status.event_count = count
    status.service_id = parsed.service_id
    status.last_error = nil
    epg.stream_status[stream_id] = status

    if changed then
        -- EIT schedule tables arrive as many distinct sections every few hundred
        -- milliseconds. Exporting here turns the debounce into a continuous
        -- write loop. The configured periodic timer flushes the accumulated
        -- registry once per interval instead.
        epg.registry_dirty = true
    end
    return true, changed
end

function epg.get_status()
    local payload = {
        configured = 0,
        event_count = 0,
        streams = {},
    }
    if not config or not config.list_streams then
        return payload
    end
    for _, row in ipairs(config.list_streams() or {}) do
        local enabled = row.enabled == nil or row.enabled == true or tonumber(row.enabled) ~= 0
        local resolved = enabled and epg.resolve_stream_config(row) or nil
        if resolved then
            local id = tostring(row.id or (row.config and row.config.id) or "")
            local current = epg.stream_status[id] or {}
            local item = {}
            for key, value in pairs(current) do item[key] = value end
            item.id = id
            item.xmltv_id = resolved.xmltv_id
            item.destination = epg.resolve_destination(resolved)
            item.format = resolved.format
            item.legacy = resolved.legacy == true
            item.collector = item.collector or "waiting"
            item.event_count = tonumber(item.event_count) or 0
            payload.configured = payload.configured + 1
            payload.event_count = payload.event_count + item.event_count
            table.insert(payload.streams, item)
        end
    end
    table.sort(payload.streams, function(a, b) return tostring(a.id) < tostring(b.id) end)
    return payload
end

local function encode_text(codepage, text)
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

local function xmltv_time(timestamp)
    local value = os.date("%Y%m%d%H%M%S %z", tonumber(timestamp) or 0)
    if not value or value == "" or value:sub(-1) == " " then
        value = os.date("!%Y%m%d%H%M%S", tonumber(timestamp) or 0) .. " +0000"
    end
    return value
end

local function build_xmltv(channels, programs, codepage)
    local encoding = "UTF-8"
    if codepage and codepage ~= "" then
        encoding = codepage
    end
    local lines = {}
    table.insert(lines, "<?xml version=\"1.0\" encoding=\"" .. encoding .. "\"?>")
    table.insert(lines, "<!DOCTYPE tv SYSTEM \"xmltv.dtd\">")
    table.insert(lines, "<tv generator-info-name=\"stream\">")
    for _, channel in ipairs(channels or {}) do
        local id = xml_escape(channel.id or "")
        local name = xml_escape(channel.name or channel.id or "")
        id = encode_text(codepage, id)
        name = encode_text(codepage, name)
        table.insert(lines, "  <channel id=\"" .. id .. "\">")
        table.insert(lines, "    <display-name>" .. name .. "</display-name>")
        table.insert(lines, "  </channel>")
    end
    table.sort(programs, function(a, b)
        if a.start == b.start then
            if a.channel_id == b.channel_id then
                return (a.event_id or 0) < (b.event_id or 0)
            end
            return tostring(a.channel_id) < tostring(b.channel_id)
        end
        return (a.start or 0) < (b.start or 0)
    end)
    for _, program in ipairs(programs or {}) do
        local channel_id = encode_text(codepage, xml_escape(program.channel_id or ""))
        table.insert(lines, "  <programme start=\"" .. xmltv_time(program.start) ..
            "\" stop=\"" .. xmltv_time(program.stop) .. "\" channel=\"" .. channel_id .. "\">")
        local lang_attr = ""
        if program.lang and program.lang ~= "" then
            lang_attr = " lang=\"" .. xml_escape(program.lang) .. "\""
        end
        local title = encode_text(codepage, xml_escape(program.title or ""))
        table.insert(lines, "    <title" .. lang_attr .. ">" .. title .. "</title>")
        if program.subtitle and program.subtitle ~= "" then
            local subtitle = encode_text(codepage, xml_escape(program.subtitle))
            table.insert(lines, "    <sub-title" .. lang_attr .. ">" .. subtitle .. "</sub-title>")
        end
        if program.description and program.description ~= "" then
            local description = encode_text(codepage, xml_escape(program.description))
            table.insert(lines, "    <desc" .. lang_attr .. ">" .. description .. "</desc>")
        end
        for _, category in ipairs(program.categories or {}) do
            table.insert(lines, "    <category>" .. tostring(category.level1 or 0) .. "." ..
                tostring(category.level2 or 0) .. "</category>")
        end
        table.insert(lines, "  </programme>")
    end
    table.insert(lines, "</tv>")
    return table.concat(lines, "\n")
end

local function build_json(channels, programs)
    local payload = {
        channels = channels or {},
        programs = programs or {},
    }
    return json.encode(payload)
end

function epg.resolve_destination(epg_conf)
    local dest = epg_conf and epg_conf.destination or ""
    local base = (config and config.data_dir) and config.data_dir or "."
    if dest == nil or dest == "" then
        return join_path(base, "epg.xml")
    end
    if dest:sub(1, 1) ~= "/" then
        return join_path(base, dest)
    end
    return dest
end

function epg.export_destination(dest, format, channels, programs, codepage)
    if not channels or #channels == 0 then
        return false, "no channels"
    end
    if not programs or #programs == 0 then
        return false, "no programs"
    end
    local out_format = normalize_format(format)
    local dir = dirname(dest)
    if dir ~= "" then
        ensure_dir(dir)
    end
    local payload = nil
    if out_format == "json" then
        payload = build_json(channels, programs)
    else
        payload = build_xmltv(channels, programs, codepage)
    end
    local temporary = dest .. ".tmp"
    local file, err = io.open(temporary, "w")
    if not file then
        return false, err
    end
    local write_ok, write_err = file:write(payload)
    local close_ok, close_err = file:close()
    if not write_ok or not close_ok then
        os.remove(temporary)
        return false, write_err or close_err or "write failed"
    end
    local rename_ok, rename_err = os.rename(temporary, dest)
    if not rename_ok then
        os.remove(temporary)
        return false, rename_err or "rename failed"
    end
    return true
end

function epg.export_all(reason)
    if not config or not config.list_streams then
        return false
    end
    local rows = config.list_streams()
    local groups = {}
    for _, row in ipairs(rows or {}) do
        local cfg = row.config or {}
        local enabled = row.enabled == nil or row.enabled == true or tonumber(row.enabled) ~= 0
        local epg_conf = enabled and epg.resolve_stream_config(row) or nil
        if epg_conf and epg_conf.xmltv_id and epg_conf.xmltv_id ~= "" then
            local dest = epg.resolve_destination(epg_conf)
            if dest then
                if not groups[dest] then
                    groups[dest] = {
                        format = epg_conf.format,
                        codepage = epg_conf.codepage,
                        channels = {},
                        channel_map = {},
                        programs = {},
                    }
                end
                local group = groups[dest]
                local channel_id = tostring(epg_conf.xmltv_id)
                if not group.channel_map[channel_id] then
                    local display_name = cfg.service_name or cfg.name or row.id or channel_id
                    table.insert(group.channels, {
                        id = channel_id,
                        name = display_name,
                    })
                    group.channel_map[channel_id] = true
                end
                local events = epg.registry[tostring(row.id or cfg.id or "")] or {}
                for _, event in pairs(events) do
                    local program = {}
                    for key, value in pairs(event) do program[key] = value end
                    program.channel_id = channel_id
                    table.insert(group.programs, program)
                end
                local status = epg.stream_status[tostring(row.id or cfg.id or "")] or {}
                status.destination = dest
                status.xmltv_id = channel_id
                status.legacy = epg_conf.legacy == true
                epg.stream_status[tostring(row.id or cfg.id or "")] = status
            end
        end
    end

    local exported = false
    for dest, group in pairs(groups) do
        local ok, err = epg.export_destination(dest, group.format, group.channels, group.programs, group.codepage)
        if ok then
            exported = true
            local now = os.time()
            for channel_id in pairs(group.channel_map) do
                for stream_id, status in pairs(epg.stream_status) do
                    if status.xmltv_id == channel_id and status.destination == dest then
                        status.last_write_ts = now
                        status.last_error = nil
                    end
                end
            end
            log.info("[epg] export ok: " .. dest .. (reason and (" (" .. reason .. ")") or ""))
        else
            if err ~= "no programs" then
                log.error("[epg] export failed: " .. tostring(err))
            end
        end
    end
    if exported then
        epg.registry_dirty = false
    end
    return exported
end

-- Debounced export request. Useful to avoid blocking config apply handlers on large setups.
function epg.request_export(reason)
    epg.pending_export_reason = tostring(reason or epg.pending_export_reason or "")
    if epg.pending_export_timer then
        return true
    end
    if not timer then
        return epg.export_all(epg.pending_export_reason)
    end
    epg.pending_export_timer = timer({
        interval = 0.5,
        callback = function(self)
            if epg.pending_export_timer then
                epg.pending_export_timer:close()
                epg.pending_export_timer = nil
            end
            local r = epg.pending_export_reason
            epg.pending_export_reason = nil
            local ok, err = pcall(epg.export_all, r ~= "" and r or nil)
            if not ok then
                log.error("[epg] export failed: " .. tostring(err))
            end
        end,
    })
    return true
end

function epg.resolve_export_interval()
    local interval = 0
    if config and config.get_setting then
        interval = tonumber(config.get_setting("epg_export_interval_sec") or 0) or 0
    end
    if interval <= 0 and config and config.list_streams then
        for _, row in ipairs(config.list_streams() or {}) do
            local enabled = row.enabled == nil or row.enabled == true or tonumber(row.enabled) ~= 0
            if enabled and epg.resolve_stream_config(row) then
                return 60
            end
        end
    end
    return interval
end

function epg.configure_timer()
    local interval = epg.resolve_export_interval()
    if epg.timer then
        epg.timer:close()
        epg.timer = nil
    end
    if interval and interval > 0 then
        epg.timer = timer({
            interval = interval,
            callback = function()
                epg.export_all("interval")
            end,
        })
    end
end
