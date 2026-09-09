"""The provider's unit: answer only a request carrying the delivered secret.

The token is read from ``$TOKEN_FILE`` per request rather than at startup, so the
observation is about the bytes on this machine at the moment of the request and
not about the order the operator happened to deliver and activate in.

``BaseHTTPRequestHandler`` already logs each request to stderr, which is the
journal of the unit the plan describes.
"""

from __future__ import annotations

import http.server
import os
import sys
from pathlib import Path

TOKEN_FILE = Path(os.environ["TOKEN_FILE"])


class Handler(http.server.BaseHTTPRequestHandler):
    """Compare the request's bearer against the delivered file, and say which."""

    def do_GET(self) -> None:
        want = TOKEN_FILE.read_text().strip()
        offered = self.headers.get("Authorization", "")
        authorized = offered == f"Bearer {want}"
        body = b"authorized\n" if authorized else b"unauthorized\n"
        self.send_response(200 if authorized else 401)
        self.send_header("Content-Type", "text/plain")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)


def main() -> None:
    """Serve on the port the plan claimed, on every address."""
    port = int(sys.argv[1])
    # Binds every address because the unit starts before the DHCP lease exists.
    with http.server.HTTPServer(("0.0.0.0", port), Handler) as server:
        server.serve_forever()


if __name__ == "__main__":
    main()
