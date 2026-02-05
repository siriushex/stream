#!/usr/bin/env python3
"""Сканер PAT/SDT для подсказки MPTS сервисов.

Использование:
  python3 tools/mpts_pat_scan.py --addr 239.1.1.1 --port 1234 --duration 3 \
    --input "udp://239.1.1.1:1234" --pretty
"""

import argparse
import json
import socket
import time

TS_PACKET_SIZE = 188
SYNC_BYTE = 0x47
PID_PAT = 0x0000
PID_SDT = 0x0011


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


class SectionAssembler:
    def __init__(self):
        self.buf = bytearray()
        self.expected = None

    def reset(self):
        self.buf = bytearray()
        self.expected = None

    def feed(self, payload: bytes, pusi: bool):
        sections = []
        if pusi:
            if not payload:
                return sections
            pointer = payload[0]
            idx = 1 + pointer
            if idx >= len(payload):
                return sections
            payload = payload[idx:]
            # Пытаемся разобрать все секции из payload.
            while payload:
                if len(payload) < 3:
                    self.buf = bytearray(payload)
                    self.expected = None
                    return sections
                sec_len = ((payload[1] & 0x0F) << 8) | payload[2]
                total = 3 + sec_len
                if len(payload) >= total:
                    sections.append(payload[:total])
                    payload = payload[total:]
                else:
                    self.buf = bytearray(payload)
                    self.expected = total
                    return sections
            return sections

        if not self.buf:
            return sections
        self.buf.extend(payload)
        if self.expected is None and len(self.buf) >= 3:
            sec_len = ((self.buf[1] & 0x0F) << 8) | self.buf[2]
            self.expected = 3 + sec_len
        if self.expected is not None and len(self.buf) >= self.expected:
            sections.append(bytes(self.buf[: self.expected]))
            self.reset()
        return sections


def parse_pat(section: bytes):
    if not section or section[0] != 0x00:
        return None
    if len(section) < 12:
        return None
    # Проверяем CRC
    crc = int.from_bytes(section[-4:], "big")
    if crc != crc32_mpegts(section[:-4]):
        return None
    tsid = (section[3] << 8) | section[4]
    programs = []
    idx = 8
    end = len(section) - 4
    while idx + 4 <= end:
        pnr = (section[idx] << 8) | section[idx + 1]
        pid = ((section[idx + 2] & 0x1F) << 8) | section[idx + 3]
        idx += 4
        if pnr == 0:
            continue
        programs.append({"pnr": pnr, "pmt_pid": pid})
    return {"tsid": tsid, "programs": programs}


def parse_service_descriptor(data: bytes):
    if len(data) < 3:
        return None
    service_type = data[0]
    prov_len = data[1]
    if 2 + prov_len >= len(data):
        return None
    provider = data[2:2 + prov_len].decode("latin-1", "ignore")
    name_len_idx = 2 + prov_len
    name_len = data[name_len_idx]
    name_start = name_len_idx + 1
    name = data[name_start:name_start + name_len].decode("latin-1", "ignore")
    return {
        "service_type_id": service_type,
        "service_provider": provider,
        "service_name": name,
    }


def parse_sdt(section: bytes):
    if not section or section[0] != 0x42:
        return None
    if len(section) < 12:
        return None
    crc = int.from_bytes(section[-4:], "big")
    if crc != crc32_mpegts(section[:-4]):
        return None
    tsid = (section[3] << 8) | section[4]
    onid = (section[8] << 8) | section[9]
    idx = 11
    end = len(section) - 4
    services = {}
    while idx + 5 <= end:
        service_id = (section[idx] << 8) | section[idx + 1]
        idx += 3  # service_id (2) + flags (1)
        desc_len = ((section[idx] & 0x0F) << 8) | section[idx + 1]
        idx += 2
        desc_end = idx + desc_len
        info = {}
        while idx + 2 <= desc_end and idx + 2 <= end:
            tag = section[idx]
            length = section[idx + 1]
            idx += 2
            data = section[idx: idx + length]
            idx += length
            if tag == 0x48:
                parsed = parse_service_descriptor(data)
                if parsed:
                    info.update(parsed)
        services[service_id] = info
        idx = desc_end
    return {"tsid": tsid, "onid": onid, "services": services}


def main() -> int:
    parser = argparse.ArgumentParser(description="Scan PAT/SDT to build MPTS services list")
    parser.add_argument("--addr", default="127.0.0.1")
    parser.add_argument("--port", type=int, required=True)
    parser.add_argument("--duration", type=float, default=3.0)
    parser.add_argument("--input", default="")
    parser.add_argument("--pretty", action="store_true")
    args = parser.parse_args()

    sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
    sock.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
    sock.bind((args.addr, args.port))
    try:
        first_octet = int(args.addr.split(".")[0])
        if 224 <= first_octet <= 239:
            mreq = socket.inet_aton(args.addr) + socket.inet_aton("0.0.0.0")
            sock.setsockopt(socket.IPPROTO_IP, socket.IP_ADD_MEMBERSHIP, mreq)
    except Exception:
        pass
    sock.settimeout(0.2)

    pat_asm = SectionAssembler()
    sdt_asm = SectionAssembler()
    pat = None
    sdt = None

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
            pusi = (pkt[1] & 0x40) != 0
            afc = (pkt[3] >> 4) & 0x03
            offset = 4
            if afc in (2, 3):
                if offset >= TS_PACKET_SIZE:
                    continue
                offset += 1 + pkt[4]
            if afc == 2 or offset >= TS_PACKET_SIZE:
                continue
            payload = pkt[offset:]

            if pid == PID_PAT:
                for section in pat_asm.feed(payload, pusi):
                    parsed = parse_pat(section)
                    if parsed:
                        pat = parsed
            elif pid == PID_SDT:
                for section in sdt_asm.feed(payload, pusi):
                    parsed = parse_sdt(section)
                    if parsed:
                        sdt = parsed
        if pat and sdt:
            break

    sock.close()

    services = []
    programs = pat["programs"] if pat else []
    sdt_services = sdt["services"] if sdt else {}
    for item in programs:
        pnr = item["pnr"]
        entry = {"pnr": pnr}
        if args.input:
            entry["input"] = args.input
        info = sdt_services.get(pnr)
        if info:
            if info.get("service_name"):
                entry["service_name"] = info["service_name"]
            if info.get("service_provider"):
                entry["service_provider"] = info["service_provider"]
            if info.get("service_type_id") is not None:
                entry["service_type_id"] = info["service_type_id"]
        services.append(entry)

    payload = {"services": services}
    output = json.dumps(payload, ensure_ascii=False, indent=2 if args.pretty else None)
    print(output)

    if not services:
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
