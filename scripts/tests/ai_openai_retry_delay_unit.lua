local function script_path(name)
  return "scripts/" .. name
end

log.set({ debug = true })

dofile(script_path("base.lua"))
dofile(script_path("ai_openai_client.lua"))

local function assert_eq(actual, expected, msg)
  if actual ~= expected then
    error((msg or "assert_eq") .. ": expected=" .. tostring(expected) .. " actual=" .. tostring(actual))
  end
end

-- Default fallback delay.
assert_eq(ai_openai_client.compute_retry_delay({}, 5), 5, "default delay must pass through")

-- retry-after should win when larger.
assert_eq(ai_openai_client.compute_retry_delay({ rate_limits = { ["retry-after"] = "7" } }, 1), 7, "retry-after seconds")
assert_eq(ai_openai_client.compute_retry_delay({ rate_limits = { ["retry-after"] = "1500ms" } }, 1), 2, "retry-after ms rounded up")

-- x-ratelimit-reset-* should win when larger.
assert_eq(ai_openai_client.compute_retry_delay({ rate_limits = { ["x-ratelimit-reset-requests"] = "12s" } }, 1), 12, "reset requests")
assert_eq(ai_openai_client.compute_retry_delay({ rate_limits = { ["x-ratelimit-reset-tokens"] = "2m" } }, 1), 120, "reset tokens minutes")

-- Hard cap at 300s.
assert_eq(ai_openai_client.compute_retry_delay({ rate_limits = { ["retry-after"] = "900s" } }, 1), 300, "cap")

-- HTTP 429 without rate-limit headers should back off more aggressively.
assert_eq(ai_openai_client.compute_retry_delay({ code = 429, attempts = 1 }, 1), 10, "429 min backoff (attempt 1)")
assert_eq(ai_openai_client.compute_retry_delay({ code = 429, attempts = 2 }, 5), 30, "429 min backoff (attempt 2)")
assert_eq(ai_openai_client.compute_retry_delay({ code = 429, attempts = 3 }, 15), 60, "429 min backoff (attempt 3)")

-- Some proxies strip rate headers but keep retry hints in the message body.
assert_eq(ai_openai_client.compute_retry_delay({ code = 429, error_detail = "Please try again in 12s." }, 1), 12, "429 retry hint parsing")

print("ai_openai_retry_delay_unit: ok")
astra.exit()
