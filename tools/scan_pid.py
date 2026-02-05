#!/usr/bin/env python3
"""Мини-сканер TS для проверки PID/таблиц в CI."""

import argparse
import socket
import time

TS_PACKET_SIZE = 188
SYNC_BYTE = 0x47


def parse_int(value: str) -> int:
    return int(value, 0)


def main() -> int:
    parser = argparse.ArgumentParser(description="Scan TS PID/table_id on UDP")
    parser.add_argument("--addr", default="127.0.0.1")
    parser.add_argument("--port", type=int, required=True)
    parser.add_argument("--duration", type=float, default=3.0)
    parser.add_argument("--pid", required=True, type=parse_int)
    parser.add_argument("--table-id", type=parse_int, default=None)
    args = parser.parse_args()

    target_pid = args.pid
    target_table = args.table_id

    sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
    sock.bind((args.addr, args.port))
    sock.settimeout(0.2)

    found_pid = False
    found_table = False

    deadline = time.time() + args.duration
    while time.time() < deadline:
        try:
            data, _ = sock.recvfrom(2048)
        except socket.timeout:
            continue
        for off in range(0, len(data) - TS_PACKET_SIZE + 1, TS_PACKET_SIZE):
            pkt = data[off:off + TS_PACKET_SIZE]
            if not pkt or pkt[0] != SYNC_BYTE:
                continue
            pid = ((pkt[1] & 0x1F) << 8) | pkt[2]
            if pid != target_pid:
                continue
            found_pid = True
            if target_table is None:
                continue
            payload_unit_start = (pkt[1] & 0x40) != 0
            afc = (pkt[3] >> 4) & 0x03
            offset = 4
            if afc in (2, 3):
                if offset >= TS_PACKET_SIZE:
                    continue
                offset += 1 + pkt[4]
            if afc == 2:
                continue
            if payload_unit_start:
                if offset >= TS_PACKET_SIZE:
                    continue
                pointer = pkt[offset]
                offset += 1 + pointer
            if offset < TS_PACKET_SIZE:
                table_id = pkt[offset]
                if table_id == target_table:
                    found_table = True
                    break
        if found_table:
            break

    sock.close()
    if not found_pid:
        print(f"PID {target_pid} not found")
        return 1
    if target_table is not None and not found_table:
        print(f"table_id 0x{target_table:02X} not found on PID {target_pid}")
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
