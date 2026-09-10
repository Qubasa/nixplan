"""The `token` generator: derive a secret and its public digest from a dependency.

The tool fetches every file of every declared dependency into ``$in``, one
directory per dependency named by that dependency's projected name. The
projected name is the reading's business, not this program's, so the dependency
is resolved as "the one directory ``$in`` holds" and a different count is a
refusal rather than a guess.

``secret`` is the deliverable half and ``fingerprint`` is the public one: a
digest of the secret, which is publishable exactly because it is not invertible.
Neither file carries a trailing newline.
"""

from __future__ import annotations

import hashlib
import hmac
import os
from pathlib import Path

LABEL = b"planner-e2e-token"
SOURCE_FILE = "key"


def dependency(root: Path) -> Path:
    """Return the single dependency directory the generator was given.

    Args:
        root: The directory ``$in`` names.

    Returns:
        That directory's one subdirectory, whatever the dependency is called.

    Raises:
        SystemExit: If ``$in`` holds no subdirectory, or more than one.
    """
    held = sorted(entry for entry in root.iterdir() if entry.is_dir())
    if len(held) != 1:
        found = ", ".join(entry.name for entry in held) or "nothing"
        raise SystemExit(f"derive: $in must hold exactly one dependency, it holds {found}")
    return held[0]


def main() -> None:
    """Write both files this generator declares, from the dependency's key."""
    out = Path(os.environ["out"])  # noqa: SIM112
    source = dependency(Path(os.environ["in"]))  # noqa: SIM112
    key = source / SOURCE_FILE
    if not key.is_file():
        raise SystemExit(f"derive: dependency {source.name!r} carries no {SOURCE_FILE!r}")
    secret = hmac.new(key.read_bytes(), LABEL, hashlib.sha256).hexdigest()
    (out / "secret").write_text(secret)
    (out / "fingerprint").write_text(hashlib.sha256(secret.encode()).hexdigest())


if __name__ == "__main__":
    main()
