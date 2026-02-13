-- Unit: timer supports fractional intervals (0.2 sec etc) and must not abort the process.

local fired = 0

local t = timer({
    interval = 0.2,
    callback = function(self)
        fired = fired + 1
        self:close()
    end,
})

-- We don't rely on the callback firing here (tests run without a long event loop).
-- The important part is: timer() with 0.2 must not trigger assert/abort in C.
t:close()

print("timer_fractional_interval_unit: ok")
astra.exit()
