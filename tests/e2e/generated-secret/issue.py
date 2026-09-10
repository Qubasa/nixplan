"""The provider's unit: attest a request that carries the generated secret.

The secret is read from ``$TOKEN_FILE`` per request, so what is observed is the
bytes present on this machine when the request arrived and not the order the
operator happened to generate, deliver and activate in.

Both answers are logged and neither log line holds the secret: the whole point
of the folder is that a generated secret reaches a machine without passing
through anything an observer of the run gets to read.
"""

from __future__ import annotations

import hmac
import http.server
import os
import sys
from pathlib import Path

TOKEN_FILE = Path(os.environ["TOKEN_FILE"])
ATTESTED = b"attested"
UNATTESTED = b"unattested"


class Handler(http.server.BaseHTTPRequestHandler):
    """Answer 200 for the delivered bearer and 401 for anything else."""

    def do_GET(self) -> None:
        offered = self.headers.get("Authorization", "")
        want = f"Bearer {TOKEN_FILE.read_text().strip()}"
        attested = hmac.compare_digest(offered, want)
        body = ATTESTED if attested else UNATTESTED
        self.log_message("%s", body.decode())
        self.send_response(200 if attested else 401)
        self.send_header("Content-Type", "text/plain")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)


def main() -> None:
    """Serve the port the plan exported, on every address."""
    port = int(sys.argv[1])
    with http.server.HTTPServer(("0.0.0.0", port), Handler) as server:
        server.serve_forever()


if __name__ == "__main__":
    main()
