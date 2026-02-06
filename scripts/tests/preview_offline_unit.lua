log.set({ debug = true })

local function assert_true(value, message)
    if not value then
        error(message or "assert")
    end
end

-- Изолируем тестовый tmp root, чтобы не мусорить в data/.
local tmp_base = os.getenv("TMPDIR") or "/tmp"
local root = tmp_base .. "/astra_preview_offline_unit_" .. tostring(os.time()) .. "_" .. tostring(math.random(1000000))

local settings = {
    preview_tmp_root = root,
    http_port = 12345,
    http_play_port = 0,
    http_play_hls = false,
}

config = {
    data_dir = root,
    get_setting = function(key)
        return settings[key]
    end,
}

timer = function(_opts)
    return { close = function() end }
end

channel_retain = function(_channel, _reason) end
channel_release = function(_channel, _reason) end

-- В offline тесте нам не важно реальное HLS; заглушаем.
hls_output = function(_opts)
    return { close = function() end }
end

runtime = {
    streams = {
        -- Сигнал отсутствует, но input уже запущен: preview.start должен вернуть 409 offline.
        s1 = {
            kind = "stream",
            channel = {
                config = { id = "s1", name = "S1" },
                active_input_id = 1,
                input = {
                    {
                        input = {}, -- признак "запущено"
                        on_air = false,
                        stats = { on_air = false, bitrate = 0 },
                        fail_count = 1,
                        last_error = "no signal",
                        last_ok_ts = 0,
                    },
                },
            },
        },

        -- Сигнал отсутствует и input ещё не запускался: preview.start должен дать шанс запуску.
        s2 = {
            kind = "stream",
            channel = {
                config = { id = "s2", name = "S2" },
                active_input_id = 0,
                tail = { stream = function() return {} end },
                input = {
                    {
                        input = nil,
                        on_air = false,
                        stats = { on_air = false, bitrate = 0 },
                        last_ok_ts = 0,
                    },
                },
            },
        },
    },
}

preview = nil
dofile("scripts/preview.lua")

local result, err, code = preview.start("s1", {})
assert_true(result == nil, "expected nil result")
assert_true(code == 409, "expected 409, got " .. tostring(code))
assert_true(tostring(err):lower():find("offline", 1, true) ~= nil, "expected offline error, got " .. tostring(err))

local result2, err2, code2 = preview.start("s2", {})
assert_true(result2 and result2.token, "expected preview token, got err=" .. tostring(err2) .. " code=" .. tostring(code2))

os.execute("rm -rf " .. root)

print("preview_offline_unit: ok")
astra.exit()
