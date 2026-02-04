#!/usr/bin/env python3
import json
from http.server import BaseHTTPRequestHandler, HTTPServer
from urllib.parse import urlparse, parse_qs

HOST = "127.0.0.1"
PORT = 9100


class AuthHandler(BaseHTTPRequestHandler):
    def _send(self, code, body=b"", headers=None):
        self.send_response(code)
        if headers:
            for key, value in headers.items():
                self.send_header(key, value)
        self.send_header("Content-Length", str(len(body)))
        self.send_header("Connection", "close")
        self.end_headers()
        if body:
            self.wfile.write(body)

    def _allow(self, extra_headers=None):
        headers = {
            "Content-Type": "text/plain",
            "X-AuthDuration": "2",
            "X-UserId": "demo",
        }
        if extra_headers:
            headers.update(extra_headers)
        self._send(
            200,
            b"ok",
            headers,
        )

    def _deny(self):
        self._send(403, b"denied", {"Content-Type": "text/plain"})

    def do_GET(self):
        parsed = urlparse(self.path)
        if parsed.path != "/on_play":
            self._send(404, b"not found", {"Content-Type": "text/plain"})
            return

        query = parse_qs(parsed.query)
        if query.get("fail", ["0"])[0] == "1":
            self._send(500, b"error", {"Content-Type": "text/plain"})
            return

        token = query.get("token", [""])[0]
        if token.startswith("token"):
            extra = {}
            max_sessions = query.get("max_sessions", [""])[0]
            if max_sessions.isdigit():
                extra["X-Max-Sessions"] = max_sessions
            unique = query.get("unique", [""])[0].lower()
            if unique in ("1", "true", "yes", "on"):
                extra["X-Unique"] = "true"
            elif unique:
                extra["X-Unique"] = "false"
            self._allow(extra)
        else:
            self._deny()

    def do_POST(self):
        parsed = urlparse(self.path)
        if parsed.path != "/on_publish":
            self._send(404, b"not found", {"Content-Type": "text/plain"})
            return

        length = int(self.headers.get("Content-Length", "0") or 0)
        raw = self.rfile.read(length) if length > 0 else b""
        token = ""
        if raw:
            try:
                payload = json.loads(raw.decode("utf-8"))
                token = payload.get("token", "")
            except json.JSONDecodeError:
                token = ""

        if token.startswith("token"):
            self._allow()
        else:
            self._deny()

    def log_message(self, fmt, *args):
        return


def main():
    server = HTTPServer((HOST, PORT), AuthHandler)
    server.serve_forever()


if __name__ == "__main__":
    main()
