#!/usr/bin/env python3
"""
Generate a config for mass UDP passthrough perf tests.

Python 3.5+ compatible (no f-strings, no type annotations).
"""

import argparse
import json


def make_stream(i, in_addr, in_port, out_addr, out_port):
    sid = "pt_{:04d}".format(i)
    return {
        "id": sid,
        "name": "Passthrough {}".format(sid),
        "type": "stream",
        "enable": True,
        "input": [
            "udp://{}:{}".format(in_addr, in_port),
        ],
        "output": [
            "udp://{}:{}".format(out_addr, out_port),
        ],
    }


def main():
    ap = argparse.ArgumentParser(description="Generate UDP passthrough perf config")
    ap.add_argument("--count", type=int, default=200)
    ap.add_argument("--out", default="tools/perf/passthrough_udp.json")
    ap.add_argument("--http-port", type=int, default=19360)

    ap.add_argument("--in-addr", default="127.0.0.1")
    ap.add_argument("--in-base-port", type=int, default=20000)
    ap.add_argument("--out-addr", default="127.0.0.1")
    ap.add_argument("--out-base-port", type=int, default=30000)

    ap.add_argument("--udp-batching", action="store_true", help="Enable recvmmsg/sendmmsg via global settings")
    ap.add_argument("--udp-rx-batch", type=int, default=32)
    ap.add_argument("--udp-tx-batch", type=int, default=32)

    ap.add_argument("--dataplane", default="off", choices=["off", "auto", "force"])
    ap.add_argument("--dp-workers", type=int, default=0)
    ap.add_argument("--dp-rx-batch", type=int, default=32)

    args = ap.parse_args()

    count = max(1, int(args.count))

    settings = {
        # Perf harness expects auth to be off.
        "http_auth_enabled": False,
        "http_play_allow": True,

        # Server port is still passed via CLI (-p). This value is used by some UI helpers.
        "http_port": int(args.http_port),
    }

    if args.udp_batching:
        settings["performance_udp_batching"] = True
        settings["performance_udp_rx_batch"] = int(args.udp_rx_batch)
        settings["performance_udp_tx_batch"] = int(args.udp_tx_batch)

    settings["performance_passthrough_dataplane"] = str(args.dataplane)
    settings["performance_passthrough_workers"] = int(args.dp_workers)
    settings["performance_passthrough_rx_batch"] = int(args.dp_rx_batch)

    streams = []
    for i in range(count):
        streams.append(make_stream(
            i + 1,
            args.in_addr,
            int(args.in_base_port) + i,
            args.out_addr,
            int(args.out_base_port) + i,
        ))

    payload = {
        "settings": settings,
        "make_stream": streams,
    }

    with open(args.out, "w", encoding="utf-8") as f:
        json.dump(payload, f, ensure_ascii=False, indent=2)
    print("written config: {} (streams: {})".format(args.out, len(streams)))


if __name__ == "__main__":
    main()

