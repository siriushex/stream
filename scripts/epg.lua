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

local function xml_escape(text)
    local value = tostring(text or "")
    value = value:gsub("&", "&amp;")
    value = value:gsub("<", "&lt;")
    value = value:gsub(">", "&gt;")
    value = value:gsub("\"", "&quot;")
    value = value:gsub("'", "&apos;")
    return value
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

local function build_xmltv(channels, codepage)
    local encoding = "UTF-8"
    if codepage and codepage ~= "" then
        encoding = codepage
    end
    local lines = {}
    table.insert(lines, "<?xml version=\"1.0\" encoding=\"" .. encoding .. "\"?>")
    table.insert(lines, "<!DOCTYPE tv SYSTEM \"xmltv.dtd\">")
    table.insert(lines, "<tv generator-info-name=\"astra\">")
    for _, channel in ipairs(channels or {}) do
        local id = xml_escape(channel.id or "")
        local name = xml_escape(channel.name or channel.id or "")
        id = encode_text(codepage, id)
        name = encode_text(codepage, name)
        table.insert(lines, "  <channel id=\"" .. id .. "\">")
        table.insert(lines, "    <display-name>" .. name .. "</display-name>")
        table.insert(lines, "  </channel>")
    end
    table.insert(lines, "</tv>")
    return table.concat(lines, "\n")
end

local function build_json(channels)
    local payload = {
        channels = channels or {},
        programs = {},
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

function epg.export_destination(dest, format, channels, codepage)
    if not channels or #channels == 0 then
        return false, "no channels"
    end
    local out_format = normalize_format(format)
    local dir = dirname(dest)
    if dir ~= "" then
        ensure_dir(dir)
    end
    local payload = nil
    if out_format == "json" then
        payload = build_json(channels)
    else
        payload = build_xmltv(channels, codepage)
    end
    local file, err = io.open(dest, "w")
    if not file then
        return false, err
    end
    file:write(payload)
    file:close()
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
        local epg_conf = cfg.epg
        if epg_conf and epg_conf.xmltv_id and epg_conf.xmltv_id ~= "" then
            local dest = epg.resolve_destination(epg_conf)
            if dest then
                if not groups[dest] then
                    groups[dest] = {
                        format = epg_conf.format,
                        codepage = epg_conf.codepage,
                        channels = {},
                        channel_map = {},
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
            end
        end
    end

    local exported = false
    for dest, group in pairs(groups) do
        local ok, err = epg.export_destination(dest, group.format, group.channels, group.codepage)
        if ok then
            exported = true
            log.info("[epg] export ok: " .. dest .. (reason and (" (" .. reason .. ")") or ""))
        else
            log.error("[epg] export failed: " .. tostring(err))
        end
    end
    return exported
end

function epg.configure_timer()
    local interval = 0
    if config and config.get_setting then
        interval = tonumber(config.get_setting("epg_export_interval_sec") or 0) or 0
    end
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
