"""The `root` generator: mint the value everything else in the folder derives from.

The tool runs this inside bubblewrap with an empty environment, no stdin, and a
writable directory at ``$out``. It is given no dependency and asks no prompt, so
the only thing it can be is a source of randomness.

The file carries no trailing newline. A delivered secret is compared byte for
byte against what a consumer holds, and a newline is a byte the consumer would
otherwise have to know to strip.
"""

from __future__ import annotations

import os
import secrets
from pathlib import Path

KEY_BYTES = 32


def main() -> None:
    """Write the one file this generator declares, `key`."""
    out = Path(os.environ["out"])  # noqa: SIM112
    (out / "key").write_text(secrets.token_hex(KEY_BYTES))


if __name__ == "__main__":
    main()
