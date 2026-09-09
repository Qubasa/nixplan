"""The consumer's unit: prove the delivered secret is the credential.

Exits zero only when all three hold, so "the credential worked" is a unit state
rather than something the harness re-derives:

1. a request carrying the value at ``$TOKEN_FILE`` is accepted,
2. the same request without it is refused by the provider,
3. ``$CA_CERT`` - a public generated value no machine holds a file of - arrived
   through the artifact's environment.

The retries are for cross-machine boot ordering, not for flakiness: nothing
orders one guest's socket against another guest's client.
"""

from __future__ import annotations

import json
import os
import sys
import time
import urllib.error
import urllib.request
from pathlib import Path

URL = os.environ["API_URL"]
TOKEN_FILE = Path(os.environ["TOKEN_FILE"])
CA_CERT = os.environ["CA_CERT"]
RECORD_PATH = Path(os.environ["RECORD_PATH"])
ATTEMPTS = 10


def fetch(headers: dict[str, str]) -> tuple[int, str]:
    """Return the status and body of one request, retrying a dead socket."""
    last: Exception | None = None
    for _attempt in range(ATTEMPTS):
        request = urllib.request.Request(URL, headers=headers)
        try:
            with urllib.request.urlopen(request, timeout=10) as answer:
                return answer.status, answer.read().decode()
        except urllib.error.HTTPError as refused:
            return refused.code, refused.read().decode()
        except OSError as unreachable:
            last = unreachable
            time.sleep(2)
    raise SystemExit(f"probe: {URL} unreachable after {ATTEMPTS} attempts: {last}")


def main() -> None:
    token = TOKEN_FILE.read_text().strip()
    authorized_status, authorized_body = fetch({"Authorization": f"Bearer {token}"})
    anonymous_status, anonymous_body = fetch({})

    record = {
        "url": URL,
        "tokenFile": str(TOKEN_FILE),
        "authorizedStatus": authorized_status,
        "authorizedBody": authorized_body.strip(),
        "anonymousStatus": anonymous_status,
        "anonymousBody": anonymous_body.strip(),
        "caCertLength": len(CA_CERT),
        "caCertFirstLine": CA_CERT.splitlines()[0] if CA_CERT else "",
    }
    RECORD_PATH.write_text(json.dumps(record, indent=2, sort_keys=True) + "\n")

    problems = []
    if authorized_status != 200:
        problems.append(f"authorized request answered {authorized_status}")
    if anonymous_status != 401:
        problems.append(f"anonymous request answered {anonymous_status}")
    if not CA_CERT.strip():
        problems.append("CA_CERT is empty")
    if problems:
        sys.stderr.write("probe: " + "; ".join(problems) + "\n")
        raise SystemExit(1)


if __name__ == "__main__":
    main()
