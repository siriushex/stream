-- Clean-room stub: http_server module interface

local http_server = {}

function http_server.new(opts)
    assert(type(opts) == "table", "opts required")
    assert(type(opts.route) == "table", "route required")

    local self = {
        addr = opts.addr or "0.0.0.0",
        port = opts.port or 80,
        server_name = opts.server_name or "Astra",
        http_version = opts.http_version or "HTTP/1.1",
        sctp = opts.sctp == true,
        route = opts.route,
    }

    function self:send(client, response)
        -- response: { code, headers = {"Header: value"}, content }
        return nil, "not implemented"
    end

    function self:close(client)
        return nil, "not implemented"
    end

    function self:data(client)
        return {}
    end

    function self:redirect(client, location)
        return nil, "not implemented"
    end

    function self:abort(client, code, text)
        return nil, "not implemented"
    end

    return self
end

return http_server
