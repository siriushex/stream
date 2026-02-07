#!/usr/bin/env python3
import argparse
import time
from http.server import BaseHTTPRequestHandler, HTTPServer

TS_PACKET = b'\x47' + (b'\x00' * 187)

class Handler(BaseHTTPRequestHandler):
    server_version = "MockHLS"
    protocol_version = "HTTP/1.1"

    def do_GET(self):
        args = self.server.args
        if self.path.endswith('.m3u8'):
            playlist = build_playlist(args)
            data = playlist.encode('utf-8')
            self.send_response(200)
            self.send_header('Content-Type', 'application/vnd.apple.mpegurl')
            self.send_header('Content-Length', str(len(data)))
            self.end_headers()
            self.wfile.write(data)
            return

        if self.path.endswith('.ts'):
            name = self.path.rsplit('/', 1)[-1]
            seq = parse_seq(name)
            if args.missing_seq and seq == args.missing_seq:
                self.send_response(404)
                self.end_headers()
                return
            size_packets = args.segment_packets
            data = TS_PACKET * size_packets
            self.send_response(200)
            self.send_header('Content-Type', 'video/MP2T')
            self.send_header('Content-Length', str(len(data)))
            self.end_headers()
            self.wfile.write(data)
            return

        self.send_response(404)
        self.end_headers()

    def log_message(self, format, *args):
        if self.server.args.quiet:
            return
        super().log_message(format, *args)


def parse_seq(name):
    try:
        base = name.split('.')[0]
        if '_' in base:
            return int(base.split('_')[-1])
    except Exception:
        return None
    return None


def build_playlist(args):
    seq = args.sequence
    lines = [
        '#EXTM3U',
        '#EXT-X-VERSION:3',
        f'#EXT-X-TARGETDURATION:{args.target_duration}',
        f'#EXT-X-MEDIA-SEQUENCE:{seq}',
    ]
    for i in range(args.segment_count):
        num = seq + i
        lines.append(f'#EXTINF:{args.target_duration}.0,')
        lines.append(f'segment_{num:04d}.ts')
    return '\n'.join(lines) + '\n'


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--port', type=int, default=19001)
    parser.add_argument('--sequence', type=int, default=1)
    parser.add_argument('--segment-count', type=int, default=3)
    parser.add_argument('--segment-packets', type=int, default=500)
    parser.add_argument('--target-duration', type=int, default=2)
    parser.add_argument('--missing-seq', type=int, default=0)
    parser.add_argument('--quiet', action='store_true')
    args = parser.parse_args()

    server = HTTPServer(('0.0.0.0', args.port), Handler)
    server.args = args
    print(f"mock_hls_server listening on :{args.port}")
    server.serve_forever()


if __name__ == '__main__':
    main()
