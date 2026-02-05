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


def build_pat(tsid: int, programs, version: int = 0) -> bytes:
    # PAT без NIT (допускает несколько программ для тестов)
    section = bytearray()
    section.append(0x00)  # table_id
    # section_length placeholder
    section.extend(b"\x00\x00")
    section.extend(struct.pack("!H", tsid & 0xFFFF))
    section.append(0xC1 | ((version & 0x1F) << 1))  # current_next=1
    section.append(0x00)  # section_number
    section.append(0x00)  # last_section_number
    # program loop
    for pnr, pmt_pid in programs:
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
    return build_pmt_with_ca(pnr, pcr_pid, es_pid, stream_type=stream_type, version=version)


def hex_to_bytes(text: str) -> bytes:
    if not text:
        return b""
    s = str(text).strip().replace(" ", "").replace("\t", "")
    if s.lower().startswith("0x"):
        s = s[2:]
    if not s:
        return b""
    if (len(s) % 2) == 1:
        raise ValueError("hex string must have even length")
    return bytes.fromhex(s)


def build_ca_descriptor(ca_system_id: int, ca_pid: int, private_data_hex: str = "") -> bytes:
    priv = hex_to_bytes(private_data_hex)
    if len(priv) > (255 - 4):
        raise ValueError("CA private_data too long (max 251 bytes)")
    payload = struct.pack("!H", ca_system_id & 0xFFFF)
    payload += bytes([0xE0 | ((ca_pid >> 8) & 0x1F), ca_pid & 0xFF])
    payload += priv
    return bytes([0x09, len(payload)]) + payload


def build_pmt_with_ca(
    pnr: int,
    pcr_pid: int,
    es_pid: int,
    stream_type: int = 0x1B,
    version: int = 0,
    ca_system_id=None,
    ca_pid=None,
    ca_private_data_hex: str = "",
) -> bytes:
    section = bytearray()
    section.append(0x02)  # table_id
    section.extend(b"\x00\x00")  # section_length placeholder
    section.extend(struct.pack("!H", pnr & 0xFFFF))
    section.append(0xC1 | ((version & 0x1F) << 1))
    section.append(0x00)
    section.append(0x00)
    section.append(0xE0 | ((pcr_pid >> 8) & 0x1F))
    section.append(pcr_pid & 0xFF)

    program_info = b""
    if ca_system_id is not None and ca_pid is not None:
        program_info = build_ca_descriptor(int(ca_system_id), int(ca_pid), ca_private_data_hex)

    section.append(0xF0 | ((len(program_info) >> 8) & 0x0F))
    section.append(len(program_info) & 0xFF)  # program_info_length
    if program_info:
        section.extend(program_info)
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

def build_service_descriptor(service_type: int, provider: str, name: str) -> bytes:
    provider_bytes = provider.encode("ascii", "ignore")
    name_bytes = name.encode("ascii", "ignore")
    data = bytes([service_type & 0xFF, len(provider_bytes)]) + provider_bytes + bytes([len(name_bytes)]) + name_bytes
    return bytes([0x48, len(data)]) + data


def build_sdt(tsid: int, onid: int, services, version: int = 0) -> bytes:
    section = bytearray()
    section.append(0x42)  # SDT actual
    section.extend(b"\x00\x00")
    section.extend(struct.pack("!H", tsid & 0xFFFF))
    section.append(0xC1 | ((version & 0x1F) << 1))
    section.append(0x00)
    section.append(0x00)
    section.extend(struct.pack("!H", onid & 0xFFFF))
    section.append(0xFF)  # reserved
    for svc in services:
        pnr = svc["pnr"]
        service_type = svc["service_type"]
        provider = svc["provider"]
        name = svc["name"]
        desc = build_service_descriptor(service_type, provider, name)
        section.extend(struct.pack("!H", pnr & 0xFFFF))
        section.append(0xFC)  # EIT flags + reserved
        section.append(0xF0 | ((len(desc) >> 8) & 0x0F))
        section.append(len(desc) & 0xFF)
        section.extend(desc)
    sec_len = len(section) - 3 + 4
    section[1] = 0xB0 | ((sec_len >> 8) & 0x0F)
    section[2] = sec_len & 0xFF
    crc = crc32_mpegts(section)
    section.extend(struct.pack("!I", crc))
    return bytes(section)


def build_eit(service_id: int, tsid: int, onid: int, version: int = 0) -> bytes:
    section = bytearray()
    section.append(0x4E)  # EIT p/f actual
    section.extend(b"\x00\x00")
    section.extend(struct.pack("!H", service_id & 0xFFFF))
    section.append(0xC1 | ((version & 0x1F) << 1))
    section.append(0x00)
    section.append(0x00)
    section.extend(struct.pack("!H", tsid & 0xFFFF))
    section.extend(struct.pack("!H", onid & 0xFFFF))
    section.append(0x00)  # segment_last_section_number
    section.append(0x4E)  # last_table_id
    sec_len = len(section) - 3 + 4
    section[1] = 0xB0 | ((sec_len >> 8) & 0x0F)
    section[2] = sec_len & 0xFF
    crc = crc32_mpegts(section)
    section.extend(struct.pack("!I", crc))
    return bytes(section)


def build_cat(version: int = 0) -> bytes:
    section = bytearray()
    section.append(0x01)  # CAT
    section.extend(b"\x00\x00")
    section.append(0xC1 | ((version & 0x1F) << 1))
    section.append(0x00)
    section.append(0x00)
    sec_len = len(section) - 3 + 4
    section[1] = 0xB0 | ((sec_len >> 8) & 0x0F)
    section[2] = sec_len & 0xFF
    crc = crc32_mpegts(section)
    section.extend(struct.pack("!I", crc))
    return bytes(section)


def packetize_section(pid: int, section: bytes, cc_map: dict[int, int]) -> list[bytes]:
    """Пакетизация PSI секции в TS пакеты по 188 байт.

    ВАЖНО: старый pack_section работал только для секций <= 183 байта и ломался на больших PAT/SDT.
    """
    packets: list[bytes] = []
    offset = 0
    pusi = True
    cc = cc_map.get(pid, 0)
    while offset < len(section):
        pkt = bytearray([0xFF] * TS_PACKET_SIZE)
        pkt[0] = SYNC_BYTE
        pkt[1] = ((0x40 if pusi else 0x00) | ((pid >> 8) & 0x1F))
        pkt[2] = pid & 0xFF
        pkt[3] = 0x10 | (cc & 0x0F)
        cc = (cc + 1) & 0x0F

        idx = 4
        if pusi:
            pkt[idx] = 0x00  # pointer_field
            idx += 1

        take = min(len(section) - offset, TS_PACKET_SIZE - idx)
        pkt[idx:idx + take] = section[offset:offset + take]
        offset += take
        packets.append(bytes(pkt))
        pusi = False

    cc_map[pid] = cc
    return packets


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
    def parse_int_auto(text: str) -> int:
        return int(str(text), 0)

    parser = argparse.ArgumentParser(description="Generate minimal SPTS over UDP")
    parser.add_argument("--addr", default="127.0.0.1")
    parser.add_argument("--port", type=int, required=True)
    parser.add_argument("--pnr", type=int, default=1)
    parser.add_argument("--pmt-pid", type=int, default=0x1000)
    parser.add_argument("--video-pid", type=int, default=0x0100)
    parser.add_argument("--pcr-pid", type=int, default=0x0100)
    parser.add_argument("--program-count", type=int, default=1,
                        help="Generate N programs in one TS (multi-program input). Default: 1")
    parser.add_argument("--extra-pnr", type=int, default=0)
    parser.add_argument("--extra-pmt-pid", type=int, default=0)
    parser.add_argument("--extra-video-pid", type=int, default=0)
    parser.add_argument("--extra-pcr-pid", type=int, default=0)
    parser.add_argument("--tsid", type=int, default=1)
    parser.add_argument("--onid", type=int, default=1)
    parser.add_argument("--service-name", default="Service")
    parser.add_argument("--provider-name", default="Provider")
    parser.add_argument("--service-type", type=int, default=1)
    parser.add_argument("--emit-sdt", action="store_true")
    parser.add_argument("--emit-eit", action="store_true")
    parser.add_argument("--emit-cat", action="store_true")
    parser.add_argument("--pmt-ca-system-id", type=parse_int_auto, default=None,
                        help="Optional PMT CA_descriptor CA_system_id (e.g. 0x0B00)")
    parser.add_argument("--pmt-ca-pid", type=parse_int_auto, default=None,
                        help="Optional PMT CA_descriptor CA_PID (ECM PID)")
    parser.add_argument("--pmt-ca-private-data", default="",
                        help="Optional PMT CA_descriptor private_data (hex)")
    parser.add_argument("--duration", type=float, default=6.0)
    parser.add_argument("--pps", type=int, default=200)
    parser.add_argument("--payload-per-program", type=int, default=3,
                        help="Dummy ES payload packets per program per tick. Default: 3")
    args = parser.parse_args()

    program_count = max(1, int(args.program_count))
    programs = []
    if program_count > 1:
        # Мультипрограммный вход: PNR/PMT PID/Video PID делаем уникальными по индексам.
        for i in range(program_count):
            pnr = args.pnr + i
            pmt_pid = args.pmt_pid + i
            video_pid = args.video_pid + i
            if pmt_pid >= NULL_PID or video_pid >= NULL_PID:
                raise SystemExit("program-count too large: PID exceeds 0x1FFF")
            programs.append((pnr, pmt_pid, video_pid, video_pid))
    else:
        programs = [(args.pnr, args.pmt_pid, args.video_pid, args.pcr_pid)]
        if args.extra_pnr > 0 and args.extra_pmt_pid > 0:
            # Дополнительная программа для проверки multi-PAT/strict_pnr.
            extra_video = args.extra_video_pid if args.extra_video_pid > 0 else args.video_pid + 1
            extra_pcr = args.extra_pcr_pid if args.extra_pcr_pid > 0 else extra_video
            programs.append((args.extra_pnr, args.extra_pmt_pid, extra_video, extra_pcr))

    pat = build_pat(args.tsid, [(pnr, pmt_pid) for pnr, pmt_pid, _, _ in programs])
    pmt_map = {pmt_pid: build_pmt_with_ca(
                   pnr,
                   pcr_pid,
                   video_pid,
                   ca_system_id=args.pmt_ca_system_id,
                   ca_pid=args.pmt_ca_pid,
                   ca_private_data_hex=args.pmt_ca_private_data,
               )
               for pnr, pmt_pid, video_pid, pcr_pid in programs}
    services = []
    for idx, (pnr, _, _, _) in enumerate(programs, start=1):
        suffix = "" if len(programs) == 1 else f" {idx}"
        services.append({
            "pnr": pnr,
            "service_type": args.service_type,
            "provider": args.provider_name,
            "name": f"{args.service_name}{suffix}",
        })
    sdt = build_sdt(args.tsid, args.onid, services) if args.emit_sdt else None
    eit_map = {pnr: build_eit(pnr, args.tsid, args.onid) for pnr, _, _, _ in programs} if args.emit_eit else {}
    cat = build_cat() if args.emit_cat else None

    sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
    target = (args.addr, args.port)

    start = time.time()
    next_tick = start
    cc_map = {}

    def next_cc(pid: int) -> int:
        value = cc_map.get(pid, 0)
        cc_map[pid] = (value + 1) & 0x0F
        return value

    # Basic pacing: packets per second
    interval = 1.0 / max(1, args.pps)

    while time.time() - start < args.duration:
        now = time.time()
        if now < next_tick:
            time.sleep(max(0, next_tick - now))
        next_tick += interval

        for pkt in packetize_section(0x0000, pat, cc_map):
            sock.sendto(pkt, target)
        for pnr, pmt_pid, video_pid, _ in programs:
            pmt = pmt_map[pmt_pid]
            for pkt in packetize_section(pmt_pid, pmt, cc_map):
                sock.sendto(pkt, target)
            # Few dummy payload packets for ES PID
            for _ in range(max(0, int(args.payload_per_program))):
                sock.sendto(pack_payload(video_pid, next_cc(video_pid)), target)
        if sdt:
            for pkt in packetize_section(0x0011, sdt, cc_map):
                sock.sendto(pkt, target)
        if eit_map:
            for pnr, eit in eit_map.items():
                for pkt in packetize_section(0x0012, eit, cc_map):
                    sock.sendto(pkt, target)
        if cat:
            for pkt in packetize_section(0x0001, cat, cc_map):
                sock.sendto(pkt, target)

        # Null padding
        for _ in range(2):
            sock.sendto(pack_null(next_cc(NULL_PID)), target)

    sock.close()
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
