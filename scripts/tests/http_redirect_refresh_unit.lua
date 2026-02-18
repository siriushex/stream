log.set({ debug = true })

dofile("scripts/base.lua")
dofile("scripts/config.lua")

config.init({
  data_dir = "/tmp/http_redirect_refresh_unit_data",
  db_path = "/tmp/http_redirect_refresh_unit_data/http_redirect_refresh_unit.db",
})

local function assert_true(value, message)
  if not value then
    error(message or "assert_true failed")
  end
end

local original_http_request = http_request
local original_timer = timer
local original_transmit = transmit
local original_os_time = os.time

local request_log = {}
local net_states = {}
local phase = 0
local fake_now = 1000

os.time = function()
  return fake_now
end

timer = function(opts)
  local handle = {
    close = function()
      -- no-op in unit test
    end,
  }
  if opts and opts.callback then
    fake_now = fake_now + math.max(1, tonumber(opts.interval) or 1)
    opts.callback(handle)
  end
  return handle
end

transmit = function(options)
  return {
    __options = options or {},
    set_upstream = function(self, stream)
      self.__upstream = stream
    end,
  }
end

http_request = function(cfg)
  phase = phase + 1
  request_log[#request_log + 1] = {
    host = cfg.host,
    port = cfg.port,
    path = cfg.path,
    ssl = cfg.ssl,
    https = cfg.https,
  }

  local req = {
    close = function() end,
    stream = function()
      return "unit-stream"
    end,
  }

  if phase == 1 then
    cfg.callback(req, {
      code = 302,
      headers = {
        location = "http://edge.example/live.ts?token=abc123",
      },
    })
  elseif phase == 2 then
    cfg.callback(req, {
      code = 404,
      message = "Not Found",
    })
  elseif phase == 3 then
    cfg.callback(req, {
      code = 200,
      message = "OK",
    })
  else
    cfg.callback(req, {
      code = 200,
      message = "OK",
    })
  end

  return req
end

local conf = parse_url("http://origin.example/live.ts#redirect_origin_fast_retry_ms=300")
conf.name = "redirect-refresh-unit"
conf.on_net_stats = function(state)
  net_states[#net_states + 1] = state
end

local module = init_input_module.http(conf)
assert_true(module ~= nil, "http module must start")

assert_true(#request_log >= 3, "expected origin -> redirect -> refreshed origin request flow")
assert_true(request_log[1].host == "origin.example", "first request must use origin")
assert_true(request_log[2].host == "edge.example", "second request must use redirect host")
assert_true(request_log[3].host == "origin.example", "third request must refresh back to origin")

local saw_fast_retry = false
for _, s in ipairs(net_states) do
  if tonumber(s.current_backoff_ms or 0) > 0 and tonumber(s.current_backoff_ms or 0) <= 300 then
    saw_fast_retry = true
    break
  end
end
assert_true(saw_fast_retry, "expected fast retry <= redirect_origin_fast_retry_ms after origin refresh")

kill_input_module.http(module, conf)

http_request = original_http_request
timer = original_timer
transmit = original_transmit
os.time = original_os_time

print("http_redirect_refresh_unit: ok")
astra.exit()
