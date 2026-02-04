-- Clean-room stub: srt_input module interface

local srt_input = {}

function srt_input.new(opts)
    assert(type(opts) == "table", "opts required")
    assert(opts.name, "name required")

    local self = {
        name = opts.name,
        mode = opts.mode or "listener", -- "listener" or "caller"
        host = opts.host,
        port = opts.port,
        passphrase = opts.passphrase,
        pbkeylen = opts.pbkeylen,
        latency = opts.latency,
        oheadbw = opts.oheadbw,
        rcvbuf = opts.rcvbuf,
        sndbuf = opts.sndbuf,
        streamid = opts.streamid,
        packetfilter = opts.packetfilter,
        tsbpd = opts.tsbpd,
        live = opts.live,
        statsout = opts.statsout,
    }

    return self
end

return srt_input
