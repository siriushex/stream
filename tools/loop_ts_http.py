#!/usr/bin/env python3
"""Serve a paced looping MPEG-TS fixture, with optional PID fault injection."""

import argparse
import os
import signal
import time
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

PACKET_SIZE = 188


def packet_pid(packet: bytes) -> int:
    return ((packet[1] & 0x1F) << 8) | packet[2]


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser()
    parser.add_argument("--file", required=True)
    parser.add_argument("--host", default="127.0.0.1")
    parser.add_argument("--port", type=int, required=True)
    parser.add_argument("--bitrate-kbps", type=int, default=1200)
    parser.add_argument("--drop-video-pid", type=int)
    parser.add_argument("--drop-audio-pid", type=int)
    parser.add_argument("--drop-video-flag")
    parser.add_argument("--drop-audio-flag")
    return parser.parse_args()


def main() -> int:
    args = parse_args()
    raw = open(args.file, "rb").read()
    usable = len(raw) - (len(raw) % PACKET_SIZE)
    packets = [raw[i : i + PACKET_SIZE] for i in range(0, usable, PACKET_SIZE)]
    if not packets or any(packet[0] != 0x47 for packet in packets):
        raise SystemExit("fixture is not aligned MPEG-TS")

    bytes_per_second = max(1, args.bitrate_kbps * 1000 // 8)
    batch_packets = max(1, bytes_per_second // PACKET_SIZE // 20)
    batch_sleep = batch_packets * PACKET_SIZE / bytes_per_second

    class Handler(BaseHTTPRequestHandler):
        protocol_version = "HTTP/1.1"

        def log_message(self, _format: str, *_values: object) -> None:
            return

        def do_GET(self) -> None:  # noqa: N802
            self.send_response(200)
            self.send_header("Content-Type", "video/mp2t")
            self.send_header("Connection", "close")
            self.end_headers()
            cursor = 0
            try:
                while True:
                    emitted = 0
                    chunk = bytearray()
                    drop_video = bool(
                        args.drop_video_pid is not None
                        and args.drop_video_flag
                        and os.path.exists(args.drop_video_flag)
                    )
                    drop_audio = bool(
                        args.drop_audio_pid is not None
                        and args.drop_audio_flag
                        and os.path.exists(args.drop_audio_flag)
                    )
                    while emitted < batch_packets:
                        packet = packets[cursor]
                        cursor = (cursor + 1) % len(packets)
                        pid = packet_pid(packet)
                        if drop_video and pid == args.drop_video_pid:
                            continue
                        if drop_audio and pid == args.drop_audio_pid:
                            continue
                        chunk.extend(packet)
                        emitted += 1
                    self.wfile.write(chunk)
                    self.wfile.flush()
                    time.sleep(batch_sleep)
            except (BrokenPipeError, ConnectionResetError):
                return

    server = ThreadingHTTPServer((args.host, args.port), Handler)

    def stop_server(*_args: object) -> None:
        raise KeyboardInterrupt

    signal.signal(signal.SIGTERM, stop_server)
    try:
        server.serve_forever(poll_interval=0.2)
    except KeyboardInterrupt:
        pass
    finally:
        server.server_close()
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
