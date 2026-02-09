#!/usr/bin/env python3
import argparse
import time
import socketserver
from http.server import BaseHTTPRequestHandler

TS_PACKET = b'\x47' + (b'\x00' * 187)

class Handler(BaseHTTPRequestHandler):
    server_version = "MockHTTP" 
    protocol_version = "HTTP/1.1"

    def do_GET(self):
        args = self.server.args
        self.send_response(200)
        self.send_header('Content-Type', 'video/MP2T')
        self.send_header('Connection', 'close')
        self.end_headers()

        start = time.time()
        try:
            while True:
                now = time.time()
                if args.drop_after and (now - start) >= args.drop_after:
                    break
                # Burst mode: "пришло много -> пауза -> пришло много", как у панелей/плохого TCP.
                if args.burst_on_sec and args.burst_off_sec:
                    period = args.burst_on_sec + args.burst_off_sec
                    if period > 0:
                        phase = (now - start) % period
                        if phase >= args.burst_on_sec:
                            time.sleep(0.2)
                            continue
                if args.stall_after and args.stall_duration:
                    if args.stall_after <= (now - start) < (args.stall_after + args.stall_duration):
                        time.sleep(0.2)
                        continue
                self.wfile.write(TS_PACKET)
                self.wfile.flush()
                interval = args.packet_interval
                if args.burst_packet_interval and args.burst_on_sec and args.burst_off_sec:
                    interval = args.burst_packet_interval
                time.sleep(interval)
        except (BrokenPipeError, ConnectionResetError):
            return

    def log_message(self, format, *args):
        if self.server.args.quiet:
            return
        super().log_message(format, *args)


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--port', type=int, default=19000)
    parser.add_argument('--packet-interval', type=float, default=0.02, help='Seconds between TS packets')
    parser.add_argument('--burst-on-sec', type=float, default=0.0, help='Burst ON duration in seconds (repeat)')
    parser.add_argument('--burst-off-sec', type=float, default=0.0, help='Burst OFF duration in seconds (repeat)')
    parser.add_argument('--burst-packet-interval', type=float, default=0.0, help='Packet interval during burst ON (seconds)')
    parser.add_argument('--drop-after', type=float, default=0.0, help='Close connection after N seconds')
    parser.add_argument('--stall-after', type=float, default=0.0, help='Start stalling after N seconds')
    parser.add_argument('--stall-duration', type=float, default=0.0, help='Stall duration in seconds')
    parser.add_argument('--quiet', action='store_true')
    args = parser.parse_args()

    class Server(socketserver.ThreadingMixIn, socketserver.TCPServer):
        allow_reuse_address = True

    with Server(('0.0.0.0', args.port), Handler) as httpd:
        httpd.args = args
        print(f"mock_http_ts listening on :{args.port}")
        httpd.serve_forever()


if __name__ == '__main__':
    main()
