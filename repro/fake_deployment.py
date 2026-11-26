"""Minimal fake Restate deployment (HTTP/1.1, REQUEST_RESPONSE mode).

Discovery advertises one service `Repro` with handler `run`. On invocation it answers with a
single protocol frame whose 16-bit type is TYPE (default 0x040F: unassigned, inside the
spec's *command* range 0x0400–0x7FFF), flags 0, empty payload.

Usage: python3 -I fake_deployment.py [port] [type_hex]
"""

import json
import sys
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

PORT = int(sys.argv[1]) if len(sys.argv) > 1 else 9080
TYPE = int(sys.argv[2], 16) if len(sys.argv) > 2 else 0x040F

MANIFEST = {
    "protocolMode": "REQUEST_RESPONSE",
    "minProtocolVersion": 5,
    "maxProtocolVersion": 5,
    "services": [
        {"name": "Repro", "ty": "SERVICE", "handlers": [{"name": "run"}]},
    ],
}


def frame(ty: int, flags: int = 0, payload: bytes = b"") -> bytes:
    header = (ty << 48) | (flags << 32) | len(payload)
    return header.to_bytes(8, "big") + payload


class Handler(BaseHTTPRequestHandler):
    protocol_version = "HTTP/1.1"

    def log_message(self, fmt, *args):
        sys.stderr.write("[fake] " + (fmt % args) + "\n")

    def _send(self, status, ctype, body):
        self.send_response(status)
        self.send_header("content-type", ctype)
        self.send_header("content-length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def do_GET(self):
        if self.path.startswith("/discover"):
            self._send(200, "application/vnd.restate.endpointmanifest.v1+json",
                       json.dumps(MANIFEST).encode())
        else:
            self._send(404, "text/plain", b"not found")

    def do_POST(self):
        n = int(self.headers.get("content-length") or 0)
        if n:
            self.rfile.read(n)
        elif "chunked" in (self.headers.get("transfer-encoding") or ""):
            while True:  # drain the chunked request body
                size = int(self.rfile.readline().split(b";")[0], 16)
                self.rfile.read(size + 2)
                if size == 0:
                    break
        if self.path.startswith("/discover"):
            return self.do_GET()
        ctype = self.headers.get("content-type", "application/vnd.restate.invocation.v5")
        sys.stderr.write(f"[fake] invoke {self.path} ctype={ctype} -> frame type {TYPE:#06x}\n")
        self._send(200, ctype, frame(TYPE))


if __name__ == "__main__":
    ThreadingHTTPServer(("0.0.0.0", PORT), Handler).serve_forever()
