gid = 10816

settings = {
    http_play_stream = false,
    hls_duration = 5,
}

users = {
    demo = {
        cipher = "5f4dcc3b5aa765d61d8327deb882cf99",
        type = 1,
        enable = true,
    },
}

make_stream = {
    {
        id = "stream-demo",
        name = "Demo Stream",
        type = "udp",
        enable = false,
        input = { "udp://239.0.0.1:1234" },
        output = {},
        backup_input = {},
    },
}

dvb_tune = {
    {
        id = "adapter-demo",
        name = "Demo Adapter",
        adapter = 0,
        device = 0,
        type = "S",
        frequency = 0,
        symbolrate = 0,
        polarization = "H",
        buffer_size = 0,
        raw_signal = 0,
        enable = false,
    },
}

softcam = {
    {
        id = "cam-demo",
        name = "Demo Softcam",
        type = "newcamd",
        host = "127.0.0.1",
        port = 10000,
        user = "user",
        pass = "pass",
        enable = false,
    },
}
