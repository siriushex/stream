#!/usr/bin/env python3
"""Проверка PSI/SI для MPTS (PAT/SDT/NIT) с учётом multi-section.

Скрипт слушает UDP порт, собирает секции PSI (по PID 0x0000/0x0010/0x0011),
объединяет данные из нескольких секций (section_number/last_section_number) и
проверяет базовые ожидания по количеству сервисов.

Использование (пример):
  python3 tools/mpts_si_verify.py --port 12346 --duration 5 \
    --expect-programs 160 --expect-sdt 160 --expect-nit-services 160 --expect-nit-lcn 160
"""

from __future__ import annotations

import argparse
import json
import socket
import time

TS_PACKET_SIZE = 188
SYNC_BYTE = 0x47

PID_PAT = 0x0000
PID_NIT = 0x0010
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
    """Сборщик PSI секции из TS payload.

    Минимальный, но достаточный для CI:
    - поддерживает pointer_field при PUSI
    - поддерживает секции, растянутые на несколько TS пакетов
    """

    def __init__(self):
        self.buf = bytearray()
        self.expected: int | None = None

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
            # В одном payload могут лежать несколько секций подряд.
            while payload:
                if len(payload) < 3:
                    self.buf = bytearray(payload)
                    self.expected = None
                    return sections
                sec_len = ((payload[1] & 0x0F) << 8) | payload[2]
                total = 3 + sec_len
                if len(payload) >= total:
                    sections.append(bytes(payload[:total]))
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


def parse_pat(section: bytes) -> dict | None:
    if not section or section[0] != 0x00:
        return None
    if len(section) < 12:
        return None
    crc = int.from_bytes(section[-4:], "big")
    if crc != crc32_mpegts(section[:-4]):
        return None
    tsid = (section[3] << 8) | section[4]
    programs = {}
    idx = 8
    end = len(section) - 4
    while idx + 4 <= end:
        pnr = (section[idx] << 8) | section[idx + 1]
        pid = ((section[idx + 2] & 0x1F) << 8) | section[idx + 3]
        idx += 4
        if pnr == 0:
            continue
        programs[pnr] = pid
    return {"tsid": tsid, "programs": programs}


def _parse_service_descriptor(data: bytes) -> dict | None:
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


def parse_sdt(section: bytes) -> dict | None:
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
    services: dict[int, dict] = {}
    while idx + 5 <= end:
        service_id = (section[idx] << 8) | section[idx + 1]
        idx += 3  # service_id (2) + flags (1)
        desc_len = ((section[idx] & 0x0F) << 8) | section[idx + 1]
        idx += 2
        desc_end = idx + desc_len
        info: dict = {}
        while idx + 2 <= desc_end and idx + 2 <= end:
            tag = section[idx]
            length = section[idx + 1]
            idx += 2
            data = section[idx: idx + length]
            idx += length
            if tag == 0x48:
                parsed = _parse_service_descriptor(data)
                if parsed:
                    info.update(parsed)
        services[service_id] = info
        idx = desc_end
    return {"tsid": tsid, "onid": onid, "services": services}


def parse_nit(section: bytes) -> dict | None:
    if not section or section[0] != 0x40:
        return None
    if len(section) < 12:
        return None
    crc = int.from_bytes(section[-4:], "big")
    if crc != crc32_mpegts(section[:-4]):
        return None

    # section_length включает CRC, поэтому полезные данные до len(section) - 4.
    sec_len = ((section[1] & 0x0F) << 8) | section[2]
    sec_end = min(len(section), 3 + sec_len)
    if sec_end < 12:
        return None

    service_list: dict[int, int] = {}
    lcn_list: dict[int, int] = {}
    ts_list: set[str] = set()

    pos = 8
    if pos + 2 > sec_end:
        return None
    network_desc_len = ((section[pos] & 0x0F) << 8) | section[pos + 1]
    pos += 2 + network_desc_len
    if pos + 2 > sec_end:
        return {"service_list": service_list, "lcn_list": lcn_list, "ts_list": ts_list}

    ts_loop_len = ((section[pos] & 0x0F) << 8) | section[pos + 1]
    pos += 2
    ts_loop_end = min(sec_end - 4, pos + ts_loop_len)

    while pos + 6 <= ts_loop_end:
        tsid = (section[pos] << 8) | section[pos + 1]
        onid = (section[pos + 2] << 8) | section[pos + 3]
        desc_len = ((section[pos + 4] & 0x0F) << 8) | section[pos + 5]
        pos += 6
        ts_list.add(f"{tsid}:{onid}")

        desc_end = min(ts_loop_end, pos + desc_len)
        while pos + 2 <= desc_end:
            tag = section[pos]
            length = section[pos + 1]
            pos += 2
            if pos + length > desc_end:
                break
            data = section[pos: pos + length]
            pos += length

            if tag == 0x41 and length >= 3:
                # service_list_descriptor: (service_id, service_type)
                off = 0
                while off + 3 <= length:
                    sid = (data[off] << 8) | data[off + 1]
                    stype = data[off + 2]
                    service_list[sid] = stype
                    off += 3
            elif tag == 0x83 and length >= 4:
                # NorDig logical_channel_descriptor: service_id + flags + lcn(10 bits)
                off = 0
                while off + 4 <= length:
                    sid = (data[off] << 8) | data[off + 1]
                    lcn = ((data[off + 2] & 0x03) << 8) | data[off + 3]
                    lcn_list[sid] = lcn
                    off += 4

        pos = desc_end

    return {"service_list": service_list, "lcn_list": lcn_list, "ts_list": ts_list}


def main() -> int:
    parser = argparse.ArgumentParser(description="Verify PAT/SDT/NIT across multi-section output")
    parser.add_argument("--addr", default="127.0.0.1")
    parser.add_argument("--port", type=int, required=True)
    parser.add_argument("--duration", type=float, default=5.0)
    parser.add_argument("--expect-programs", type=int, default=0)
    parser.add_argument("--expect-sdt", type=int, default=0)
    parser.add_argument("--expect-nit-services", type=int, default=0)
    parser.add_argument("--expect-nit-lcn", type=int, default=0)
    args = parser.parse_args()

    sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
    sock.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
    sock.bind((args.addr, args.port))
    sock.settimeout(0.2)

    asm_pat = SectionAssembler()
    asm_sdt = SectionAssembler()
    asm_nit = SectionAssembler()

    pat_programs: dict[int, int] = {}
    sdt_services: dict[int, dict] = {}
    nit_services: dict[int, int] = {}
    nit_lcn: dict[int, int] = {}
    nit_ts: set[str] = set()

    deadline = time.time() + args.duration
    while time.time() < deadline:
        try:
            data, _ = sock.recvfrom(65536)
        except socket.timeout:
            continue

        for off in range(0, len(data) - TS_PACKET_SIZE + 1, TS_PACKET_SIZE):
            pkt = data[off:off + TS_PACKET_SIZE]
            if not pkt or pkt[0] != SYNC_BYTE:
                continue

            pid = ((pkt[1] & 0x1F) << 8) | pkt[2]
            if pid not in (PID_PAT, PID_NIT, PID_SDT):
                continue

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
                for sec in asm_pat.feed(payload, pusi):
                    parsed = parse_pat(sec)
                    if not parsed:
                        continue
                    pat_programs.update(parsed["programs"])
            elif pid == PID_SDT:
                for sec in asm_sdt.feed(payload, pusi):
                    parsed = parse_sdt(sec)
                    if not parsed:
                        continue
                    sdt_services.update(parsed["services"])
            elif pid == PID_NIT:
                for sec in asm_nit.feed(payload, pusi):
                    parsed = parse_nit(sec)
                    if not parsed:
                        continue
                    nit_services.update(parsed["service_list"])
                    nit_lcn.update(parsed["lcn_list"])
                    nit_ts |= set(parsed["ts_list"])

    sock.close()

    summary = {
        "pat_programs": len(pat_programs),
        "sdt_services": len(sdt_services),
        "nit_services": len(nit_services),
        "nit_lcn": len(nit_lcn),
        "nit_ts": sorted(nit_ts),
    }
    print(json.dumps(summary, ensure_ascii=False))

    # Проверки (только если ожидания заданы).
    errors = []
    if args.expect_programs and len(pat_programs) != args.expect_programs:
        errors.append(f"PAT programs mismatch: expected {args.expect_programs}, got {len(pat_programs)}")
    if args.expect_sdt and len(sdt_services) != args.expect_sdt:
        errors.append(f"SDT services mismatch: expected {args.expect_sdt}, got {len(sdt_services)}")
    if args.expect_nit_services and len(nit_services) != args.expect_nit_services:
        errors.append(f"NIT service_list mismatch: expected {args.expect_nit_services}, got {len(nit_services)}")
    if args.expect_nit_lcn and len(nit_lcn) != args.expect_nit_lcn:
        errors.append(f"NIT LCN mismatch: expected {args.expect_nit_lcn}, got {len(nit_lcn)}")

    # Базовая склейка: если есть все таблицы, IDs должны совпадать.
    if pat_programs and sdt_services:
        missing = sorted(set(pat_programs.keys()) - set(sdt_services.keys()))
        if missing:
            errors.append(f"SDT missing {len(missing)} services from PAT (first: {missing[:10]})")
    if pat_programs and nit_services:
        missing = sorted(set(pat_programs.keys()) - set(nit_services.keys()))
        if missing:
            errors.append(f"NIT missing {len(missing)} services from PAT (first: {missing[:10]})")

    if errors:
        for e in errors:
            print(e)
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

