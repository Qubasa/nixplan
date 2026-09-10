"""The consumer's unit: what the delivered secret is, said without saying it.

Two requests are made, one carrying the value at ``$TOKEN_FILE`` and one
carrying nothing, and one JSON object is written to ``$RECORD_PATH``. The record
holds a digest of the bytes read, never the bytes, so a run's artifacts stay
readable evidence.

Nothing here knows the public half. A unit's environment is rendered before the
value exists, so the fingerprint the generator published cannot reach this
machine at all. Comparing the digest recorded here against the fingerprint the
plan published is the operator's step, and that separation is the claim.

The retries cover cross-machine boot ordering, not flakiness: nothing orders one
guest's socket against another guest's client.
"""

from __future__ import annotations

import hashlib
import json
import os
import time
import urllib.error
import urllib.request
from pathlib import Path

URL = os.environ["API_URL"]
TOKEN_FILE = Path(os.environ["TOKEN_FILE"])
RECORD_PATH = Path(os.environ["RECORD_PATH"])
ATTEMPTS = 10
PAUSE = 2
TIMEOUT = 10


def fetch(headers: dict[str, str]) -> tuple[int, str]:
    """Return the status and body of one request.

    Args:
        headers: What to send, either the bearer or nothing.

    Returns:
        The status and the body, a refusal included: a 401 is an answer.

    Raises:
        SystemExit: If no answer arrived at all within the attempts.
    """
    unreachable: OSError | None = None
    for _attempt in range(ATTEMPTS):
        request = urllib.request.Request(URL, headers=headers)
        try:
            with urllib.request.urlopen(request, timeout=TIMEOUT) as answer:
                return answer.status, answer.read().decode()
        except urllib.error.HTTPError as refused:
            return refused.code, refused.read().decode()
        except OSError as failed:
            unreachable = failed
            time.sleep(PAUSE)
    raise SystemExit(f"attest: {URL} answered nothing in {ATTEMPTS} attempts: {unreachable}")


def main() -> None:
    """Perform both requests and write the record."""
    held = TOKEN_FILE.read_bytes()
    token = held.decode().strip()
    authorized_status, authorized_body = fetch({"Authorization": f"Bearer {token}"})
    anonymous_status, anonymous_body = fetch({})

    record = {
        "url": URL,
        "tokenFile": str(TOKEN_FILE),
        "authorizedStatus": authorized_status,
        "authorizedBody": authorized_body.strip(),
        "anonymousStatus": anonymous_status,
        "anonymousBody": anonymous_body.strip(),
        "tokenFingerprint": hashlib.sha256(held).hexdigest(),
        "tokenLength": len(token),
    }
    RECORD_PATH.write_text(json.dumps(record, indent=2, sort_keys=True) + "\n")


if __name__ == "__main__":
    main()
