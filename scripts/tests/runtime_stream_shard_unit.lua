log.set({ debug = true })

dofile("scripts/base.lua")
dofile("scripts/config.lua")
dofile("scripts/stream.lua")
dofile("scripts/runtime.lua")

config.init({
  data_dir = "/tmp/runtime_stream_shard_unit_data",
  db_path = "/tmp/runtime_stream_shard_unit_data/runtime_stream_shard_unit.db",
})

local function assert_true(v, msg)
  if not v then
    error(msg or "assert")
  end
end

local function shard_bucket(id, shard_count)
  local hex = string.hex(string.md5(tostring(id or "")))
  local head = hex:sub(1, 8)
  local n = tonumber(head, 16) or 0
  return n % shard_count
end

-- Build intentionally invalid stream configs so apply_streams() reports errors for applied rows.
local function make_bad_row(id)
  return {
    id = id,
    enabled = 1,
    config_json = "{\"id\":\"" .. tostring(id) .. "\"}",
    config = {
      id = id,
      name = "unit-" .. tostring(id),
      enable = true,
      input = {}, -- invalid: input list is required
      output = {},
    },
  }
end

do
  local rows = {
    make_bad_row("a01"),
    make_bad_row("a02"),
    make_bad_row("a03"),
    make_bad_row("a04"),
  }

  runtime.stream_shard_index = 0
  runtime.stream_shard_count = 2

  local errors = runtime.apply_streams(rows, true) or {}
  local got = {}
  for _, e in ipairs(errors) do
    got[tostring(e.id)] = true
  end

  local expected = {}
  for _, row in ipairs(rows) do
    if shard_bucket(row.id, 2) == 0 then
      expected[row.id] = true
    end
  end

  for id, _ in pairs(expected) do
    assert_true(got[id] == true, "expected error for shard row " .. id)
  end
  for id, _ in pairs(got) do
    assert_true(expected[id] == true, "unexpected row was applied outside shard: " .. id)
  end
end

do
  -- apply_stream_row must reject rows not owned by this shard (when sharding enabled)
  runtime.stream_shard_index = 1
  runtime.stream_shard_count = 2

  local id = "b01"
  local owned = (shard_bucket(id, 2) == 1)
  local ok, err = runtime.apply_stream_row(make_bad_row(id), true)
  if owned then
    assert_true(ok == false, "owned row should reach apply and fail validation")
  else
    assert_true(ok == false and tostring(err):find("does not belong to this shard"), "foreign row must be rejected")
  end
end

print("runtime_stream_shard_unit: ok")
astra.exit()

