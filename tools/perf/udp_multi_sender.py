#!/usr/bin/env python3
"""
Send synthetic UDP datagrams to many ports for passthrough perf tests.

Python 3.5+ compatible (no f-strings, no type annotations).
"""

import argparse
import socket
import time


TS_PACKET_SIZE = 188
TS_SYNC = 0x47


def build_datagram(ts_packets):
    pkt = bytearray([0] * TS_PACKET_SIZE)
    pkt[0] = TS_SYNC
    # minimal header: PID 0x0000 (PAT) is fine for a synthetic stream.
    pkt[1] = 0x40
    pkt[2] = 0x00
    pkt[3] = 0x10
    block = bytes(pkt)
    return block * int(ts_packets)


def main():
    ap = argparse.ArgumentParser(description="Multi-port UDP sender")
    ap.add_argument("--addr", default="127.0.0.1")
    ap.add_argument("--base-port", type=int, default=20000)
    ap.add_argument("--count", type=int, default=200)
    ap.add_argument("--pps", type=int, default=50, help="datagrams per second per port")
    ap.add_argument("--duration", type=int, default=30, help="seconds")
    ap.add_argument("--ts-per-datagram", type=int, default=7, help="TS packets per datagram (default 7 => 1316 bytes)")
    args = ap.parse_args()

    ports = []
    for i in range(max(1, int(args.count))):
        ports.append(int(args.base_port) + i)

    pps = max(1, int(args.pps))
    interval = 1.0 / float(pps)
    duration = max(1, int(args.duration))

    payload = build_datagram(int(args.ts_per_datagram))

    sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
    sock.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)

    start = time.time()
    next_tick = start
    sent = 0

    while True:
        now = time.time()
        if now >= start + duration:
            break

        if now < next_tick:
            time.sleep(min(0.01, next_tick - now))
            continue

        # one "tick": send 1 datagram to every port
        for p in ports:
            sock.sendto(payload, (args.addr, p))
            sent += 1

        next_tick += interval

    print("done: sent_datagrams={}".format(sent))


if __name__ == "__main__":
    main()

