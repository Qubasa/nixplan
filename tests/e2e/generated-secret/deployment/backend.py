"""A real store backend: one age file per (name, file) pair, under one directory.

The external contract asks a store backend for six commands, each invoked as its
own program with the pair as arguments and the payload path in the environment.
This program is all six, selected by its first argument, so the deployment can
render one package per command from one file.

The layout is ``$PLANNER_SECRETS_AGE_DIR/<name>/<file>.age``. A projected name
carries a colon, which is a legal filename character on every filesystem this
runs on, so nothing is mangled and nothing has to be un-mangled to answer
``list``. Encryption is to ``$PLANNER_SECRETS_AGE_RECIPIENT`` and decryption is
with ``$PLANNER_SECRETS_AGE_IDENTITY``, both read at the moment they are needed:
``exists``, ``delete`` and ``list`` answer without either.

Every failure is a message on stderr naming the variable or the pair, and a
non-zero exit. A refused ``get`` removes what it had begun to write, because a
truncated secret that reads as success is worse than no secret at all.
"""

from __future__ import annotations

import os
import shutil
import subprocess
import sys
from collections.abc import Sequence
from pathlib import Path
from typing import NoReturn

DIRECTORY_VARIABLE = "PLANNER_SECRETS_AGE_DIR"
RECIPIENT_VARIABLE = "PLANNER_SECRETS_AGE_RECIPIENT"
IDENTITY_VARIABLE = "PLANNER_SECRETS_AGE_IDENTITY"

# The two statuses `exists` may answer with. Anything else is a failed backend.
HELD = 0
NOT_HELD = 42

SUFFIX = ".age"
DIRECTORY_MODE = 0o700
FILE_MODE = 0o600
PAIRED = ("get", "set", "exists", "delete")
COMMANDS = (*PAIRED, "list", "fixup")


def refuse(message: str) -> NoReturn:
    """Write one refusal to stderr and exit non-zero.

    Args:
        message: What could not be done, naming the variable or the pair.

    Raises:
        SystemExit: Always.
    """
    sys.stderr.write(f"backend: {message}\n")
    raise SystemExit(1)


def variable(name: str) -> str:
    """Return an environment variable's value, or refuse naming the variable."""
    value = os.environ.get(name, "")
    if not value:
        refuse(f"{name} is unset, so this backend has nowhere to read or write")
    return value


def age() -> str:
    """Return the `age` binary's path, or refuse naming what is missing."""
    found = shutil.which("age")
    if found is None:
        refuse("no 'age' on PATH, so nothing can be encrypted or decrypted")
    return found


def root() -> Path:
    """Return the directory this backend stores everything under."""
    return Path(variable(DIRECTORY_VARIABLE))


def stored(name: str, file: str) -> Path:
    """Return where one pair's ciphertext lives."""
    return root() / name / f"{file}{SUFFIX}"


def run(argv: Sequence[str], *, what: str) -> None:
    """Run one `age` invocation, refusing with its own stderr on a non-zero exit."""
    result = subprocess.run(argv, capture_output=True, text=True, check=False)
    if result.returncode != 0:
        refuse(f"age could not {what} [exit {result.returncode}]: {result.stderr.strip()}")


def listing() -> list[tuple[str, str]]:
    """Return every stored pair, sorted, as `exec.py:list_secrets` parses it."""
    directory = root()
    if not directory.is_dir():
        return []
    pairs = [
        (holder.name, held.name[: -len(SUFFIX)])
        for holder in directory.iterdir()
        if holder.is_dir()
        for held in holder.iterdir()
        if held.is_file() and held.name.endswith(SUFFIX)
    ]
    return sorted(pairs)


def decrypt(name: str, file: str, out: Path) -> None:
    """Decrypt one pair into the path `$out` names, or refuse naming the pair."""
    source = stored(name, file)
    if not source.is_file():
        refuse(f"nothing stored for {name}/{file}")
    identity = variable(IDENTITY_VARIABLE)
    binary = age()
    try:
        run(
            [binary, "--decrypt", "--identity", identity, "--output", str(out), str(source)],
            what=f"decrypt {name}/{file}",
        )
    except SystemExit:
        out.unlink(missing_ok=True)
        raise


def encrypt(name: str, file: str, source: Path) -> None:
    """Encrypt the path `$in` names into one pair, through a rename.

    The temporary file is a sibling of the target, so the rename is within one
    filesystem and a reader either sees the previous ciphertext or the new one.

    Args:
        name: The value's projected name.
        file: The declared file of that value.
        source: What to encrypt.
    """
    if not source.is_file():
        refuse(f"{name}/{file} was to be set from {source}, which is not a file")
    recipient = variable(RECIPIENT_VARIABLE)
    binary = age()
    target = stored(name, file)
    target.parent.mkdir(parents=True, exist_ok=True)
    os.chmod(root(), DIRECTORY_MODE)
    os.chmod(target.parent, DIRECTORY_MODE)
    staged = target.with_name(f".{target.name}.{os.getpid()}")
    try:
        run(
            [binary, "--encrypt", "--recipient", recipient, "--output", str(staged), str(source)],
            what=f"encrypt {name}/{file}",
        )
        os.chmod(staged, FILE_MODE)
        os.replace(staged, target)
    except SystemExit:
        staged.unlink(missing_ok=True)
        raise


def main(argv: Sequence[str]) -> int:
    """Answer one store-backend command.

    Args:
        argv: The command, then the pair where the command takes one.

    Returns:
        The status to exit with: `NOT_HELD` for an `exists` that holds nothing,
        and zero otherwise.
    """
    if not argv:
        refuse(f"usage: backend.py <{'|'.join(COMMANDS)}> [<name> [<file>]]")
    command, rest = argv[0], argv[1:]
    if command == "fixup":
        return 0
    if command == "list":
        for name, file in listing():
            print(f"{name} {file}")
        return 0
    if command not in PAIRED:
        refuse(f"unknown command {command!r}, expected one of {', '.join(COMMANDS)}")
    if len(rest) != 2:
        refuse(f"{command} takes a name and a file, got {len(rest)} argument(s)")
    name, file = rest
    if command == "exists":
        return HELD if stored(name, file).is_file() else NOT_HELD
    if command == "get":
        decrypt(name, file, Path(variable("out")))
    elif command == "set":
        encrypt(name, file, Path(variable("in")))
    else:
        stored(name, file).unlink(missing_ok=True)
    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))
