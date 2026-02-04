-- Clean-room stub: mux module interface

local mux = {}

function mux.new(opts)
    assert(type(opts) == "table", "opts required")
    assert(opts.name, "name required")

    local self = {
        name = opts.name,
        mux_pid = opts.mux_pid,
        remux_eit = opts.remux_eit == true,
        pids = opts.pids or {}, -- list of pid maps
    }

    return self
end

return mux
