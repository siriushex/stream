#!/usr/bin/env python3
"""Минимальный генератор SPTS для тестов MPTS.
Отправляет PAT/PMT и фиктивные пакеты по UDP.
"""

import argparse
import socket
import struct
import time

TS_PACKET_SIZE = 188
SYNC_BYTE = 0x47
NULL_PID = 0x1FFF


def crc32_mpegts(data: bytes) -> int:
    crc = 0xFFFFFFFF
    for b in data:
        crc ^= (b << 24) & 0xFFFFFFFF
        for _ in range(8):
            if crc & 0x80000000:
                crc = ((crc << 1) ^ 0x04C11DB7) & 0xFFFFFFFF
            else:
                crc = (crc << 1) & 0xFFFFFFFF
    return crc & 0xFFFFFFFF


def build_pat(tsid: int, pnr: int, pmt_pid: int, version: int = 0) -> bytes:
    # PAT section without NIT (single program)
    section = bytearray()
    section.append(0x00)  # table_id
    # section_length placeholder
    section.extend(b"\x00\x00")
    section.extend(struct.pack("!H", tsid & 0xFFFF))
    section.append(0xC1 | ((version & 0x1F) << 1))  # current_next=1
    section.append(0x00)  # section_number
    section.append(0x00)  # last_section_number
    # program loop
    section.extend(struct.pack("!H", pnr & 0xFFFF))
    section.append(0xE0 | ((pmt_pid >> 8) & 0x1F))
    section.append(pmt_pid & 0xFF)
    # section_length
    sec_len = len(section) - 3 + 4  # after section_length to CRC
    section[1] = 0xB0 | ((sec_len >> 8) & 0x0F)
    section[2] = sec_len & 0xFF
    crc = crc32_mpegts(section)
    section.extend(struct.pack("!I", crc))
    return bytes(section)


def build_pmt(pnr: int, pcr_pid: int, es_pid: int, stream_type: int = 0x1B, version: int = 0) -> bytes:
    section = bytearray()
    section.append(0x02)  # table_id
    section.extend(b"\x00\x00")  # section_length placeholder
    section.extend(struct.pack("!H", pnr & 0xFFFF))
    section.append(0xC1 | ((version & 0x1F) << 1))
    section.append(0x00)
    section.append(0x00)
    section.append(0xE0 | ((pcr_pid >> 8) & 0x1F))
    section.append(pcr_pid & 0xFF)
    section.append(0xF0)
    section.append(0x00)  # program_info_length
    # stream info
    section.append(stream_type & 0xFF)
    section.append(0xE0 | ((es_pid >> 8) & 0x1F))
    section.append(es_pid & 0xFF)
    section.append(0xF0)
    section.append(0x00)  # ES_info_length
    sec_len = len(section) - 3 + 4
    section[1] = 0xB0 | ((sec_len >> 8) & 0x0F)
    section[2] = sec_len & 0xFF
    crc = crc32_mpegts(section)
    section.extend(struct.pack("!I", crc))
    return bytes(section)


def pack_section(pid: int, section: bytes, cc: int) -> bytes:
    pkt = bytearray([0xFF] * TS_PACKET_SIZE)
    pkt[0] = SYNC_BYTE
    pkt[1] = 0x40 | ((pid >> 8) & 0x1F)
    pkt[2] = pid & 0xFF
    pkt[3] = 0x10 | (cc & 0x0F)
    pkt[4] = 0x00  # pointer_field
    end = 5 + len(section)
    pkt[5:end] = section
    return bytes(pkt)


def pack_payload(pid: int, cc: int, payload: bytes = b"") -> bytes:
    pkt = bytearray([0xFF] * TS_PACKET_SIZE)
    pkt[0] = SYNC_BYTE
    pkt[1] = (pid >> 8) & 0x1F
    pkt[2] = pid & 0xFF
    pkt[3] = 0x10 | (cc & 0x0F)
    if payload:
        size = min(len(payload), TS_PACKET_SIZE - 4)
        pkt[4:4 + size] = payload[:size]
    return bytes(pkt)


def pack_null(cc: int) -> bytes:
    return bytes([0x47, 0x1F, 0xFF, 0x10 | (cc & 0x0F)] + [0xFF] * (TS_PACKET_SIZE - 4))


def main() -> int:
    parser = argparse.ArgumentParser(description="Generate minimal SPTS over UDP")
    parser.add_argument("--addr", default="127.0.0.1")
    parser.add_argument("--port", type=int, required=True)
    parser.add_argument("--pnr", type=int, default=1)
    parser.add_argument("--pmt-pid", type=int, default=0x1000)
    parser.add_argument("--video-pid", type=int, default=0x0100)
    parser.add_argument("--pcr-pid", type=int, default=0x0100)
    parser.add_argument("--duration", type=float, default=6.0)
    parser.add_argument("--pps", type=int, default=200)
    args = parser.parse_args()

    pat = build_pat(1, args.pnr, args.pmt_pid)
    pmt = build_pmt(args.pnr, args.pcr_pid, args.video_pid)

    sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
    target = (args.addr, args.port)

    start = time.time()
    next_tick = start
    pat_cc = 0
    pmt_cc = 0
    vid_cc = 0
    null_cc = 0

    # Basic pacing: packets per second
    interval = 1.0 / max(1, args.pps)

    while time.time() - start < args.duration:
        now = time.time()
        if now < next_tick:
            time.sleep(max(0, next_tick - now))
        next_tick += interval

        sock.sendto(pack_section(0x0000, pat, pat_cc), target)
        pat_cc = (pat_cc + 1) & 0x0F
        sock.sendto(pack_section(args.pmt_pid, pmt, pmt_cc), target)
        pmt_cc = (pmt_cc + 1) & 0x0F

        # Few dummy payload packets for ES PID
        for _ in range(3):
            sock.sendto(pack_payload(args.video_pid, vid_cc), target)
            vid_cc = (vid_cc + 1) & 0x0F

        # Null padding
        for _ in range(2):
            sock.sendto(pack_null(null_cc), target)
            null_cc = (null_cc + 1) & 0x0F

    sock.close()
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
