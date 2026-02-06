log.set({ debug = true })

local function assert_true(value, message)
    if not value then
        error(message or "assert")
    end
end

local function has_seq(args, seq)
    if type(args) ~= "table" or type(seq) ~= "table" then
        return false
    end
    if #seq == 0 then
        return true
    end
    for i = 1, (#args - #seq + 1) do
        local ok = true
        for j = 1, #seq do
            if args[i + j - 1] ~= seq[j] then
                ok = false
                break
            end
        end
        if ok then
            return true
        end
    end
    return false
end

local function find_arg_value(args, key)
    if type(args) ~= "table" then
        return nil
    end
    for i = 1, (#args - 1) do
        if args[i] == key then
            return args[i + 1]
        end
    end
    return nil
end

-- Изолируем тестовый tmp root, чтобы не мусорить в data/.
local tmp_base = os.getenv("TMPDIR") or "/tmp"
local root = tmp_base .. "/astra_preview_unit_" .. tostring(os.time()) .. "_" .. tostring(math.random(1000000))

-- Стабим минимальный config/runtime для scripts/preview.lua.
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

runtime = {
    streams = {
        s1 = {
            kind = "stream",
            channel = {
                config = { id = "s1", name = "S1" },
            },
        },
    },
}

-- Таймеры в unit-тесте не нужны (cleaner запускается отдельно в smoke).
timer = function(_opts)
    return { close = function() end }
end

channel_retain = function(_channel, _reason) end
channel_release = function(_channel, _reason) end

local spawned = {
    count = 0,
    args = nil,
    opts = nil,
    proc = nil,
}

process = {
    spawn = function(args, opts)
        spawned.count = spawned.count + 1
        spawned.args = args
        spawned.opts = opts

        local proc = {
            terminate_called = 0,
            kill_called = 0,
            close_called = 0,
            poll = function() return nil end,
            terminate = function(self) self.terminate_called = self.terminate_called + 1 end,
            kill = function(self) self.kill_called = self.kill_called + 1 end,
            close = function(self) self.close_called = self.close_called + 1 end,
        }
        spawned.proc = proc
        return proc
    end,
}

preview = nil
dofile("scripts/preview.lua")

-- audio_aac mode: video copy + audio->aac
local result, err, code = preview.start("s1", { audio_aac = true })
assert_true(result and result.token, "expected preview token, got err=" .. tostring(err) .. " code=" .. tostring(code))
assert_true(spawned.count == 1, "expected one ffmpeg spawn")
assert_true(type(spawned.args) == "table" and #spawned.args > 0, "expected spawn args")

assert_true(has_seq(spawned.args, { "-c:v", "copy" }), "expected -c:v copy")
assert_true(has_seq(spawned.args, { "-c:a", "aac" }), "expected -c:a aac")

local input_url = find_arg_value(spawned.args, "-i")
assert_true(type(input_url) == "string" and input_url ~= "", "expected -i <url>")
assert_true(input_url:find("/play/s1?internal=1", 1, true) ~= nil, "expected internal=1 in input url: " .. tostring(input_url))

assert_true(type(spawned.opts) == "table" and type(spawned.opts.cwd) == "string", "expected spawn cwd option")
assert_true(spawned.opts.cwd:find(root, 1, true) == 1, "expected cwd under tmp root: " .. tostring(spawned.opts.cwd))

local session = preview.get_session(result.token)
assert_true(session and session.audio_aac == true, "expected session.audio_aac=true")
assert_true(session.video_only ~= true, "expected session.video_only=false")

local stopped = preview.stop("s1")
assert_true(stopped == true, "expected stop=true")
assert_true(spawned.proc and spawned.proc.terminate_called > 0, "expected proc:terminate() to be called")

-- Cleanup: корень tmp может оставаться (rm_rf удаляет только base_path/token).
os.execute("rm -rf " .. root)

print("preview_audio_aac_unit: ok")
astra.exit()

