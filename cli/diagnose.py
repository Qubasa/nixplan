"""The rows of a deployment and the table rendered from them, for a target this
command does not build.

Two kinds of target and two readings. A directory a build produced carries both
halves as files, so it is answered with no `nix` at all. Anything else is a flake
reference, and one evaluation selects the two attributes `mkDeployment` publishes
by name: the record as a whole is the refusal for an inapplicable deployment, so
a caller who asked for everything would be handed the refusal in place of the
table it is about, and that is exactly the deployment an author is iterating on.

Nothing here computes, re-orders or re-renders a row. The rows are the ones the
planner's own table ordered and the text is the one the planner rendered, so a
person and a program read one answer in two shapes rather than two answers.
"""

from __future__ import annotations

import json
import subprocess
from dataclasses import dataclass, fields
from pathlib import Path
from typing import Any

import manifest
from errors import ApplyError

ROWS = "diagnostics"
TABLE = "rendered"

# The two attributes, selected by name and never by evaluating the record around
# them. `or null` is what turns a target that publishes neither into the
# command's own refusal instead of the interpreter's missing attribute.
SELECTED = " ".join(f"{name} = deployment.{name} or null;" for name in (ROWS, TABLE))
SELECT = f"deployment: {{ {SELECTED} }}"

FIELDS = tuple(field.name for field in fields(manifest.Diagnostic))

ERROR = "error"


@dataclass(frozen=True)
class Answer:
    """One deployment's table, in the two shapes it is published in.

    ``rows`` are the rows as the planner's table ordered them, each carrying
    every field a producer built it with. ``rendered`` is the text the build
    writes beside them.
    """

    rows: tuple[dict[str, str], ...]
    rendered: str

    @property
    def errors(self) -> tuple[dict[str, str], ...]:
        """The rows that make the deployment inapplicable."""
        return tuple(row for row in self.rows if row.get("severity") == ERROR)


def answer(target: str) -> Answer:
    """Return the rows and the rendered table of ``target``.

    Args:
        target: A directory a build produced, or a flake reference naming an
            attribute that publishes the two.

    Returns:
        The deployment's table, read from the two files a build wrote or from
        the two attributes an evaluation answers.

    Raises:
        ApplyError: If the target does not evaluate, or if it answers neither
            attribute, naming the target and both attributes.
    """
    named = Path(target)
    if (named / manifest.MANIFEST).is_file():
        deployment = manifest.read(named)
        return Answer(
            rows=tuple(_row(row) for row in deployment.diagnostics),
            rendered=deployment.table,
        )
    return _evaluated(target)


def _row(row: manifest.Diagnostic) -> dict[str, str]:
    """One decoded row as data, in the field order the record states."""
    return {name: str(getattr(row, name)) for name in FIELDS}


def _evaluated(target: str) -> Answer:
    """Read the two attributes of ``target`` in one evaluation.

    Raises:
        ApplyError: If the evaluation refuses, if its answer is not a record,
            or if the target publishes neither attribute.
    """
    evaluated = subprocess.run(
        ["nix", "eval", "--json", target, "--apply", SELECT],
        capture_output=True,
        text=True,
        check=False,
    )
    if evaluated.returncode != 0:
        raise ApplyError(f"{target} does not evaluate:\n{evaluated.stderr.strip()}")
    try:
        answered = json.loads(evaluated.stdout)
    except ValueError as malformed:
        raise ApplyError(
            f"{target} answered something that is not JSON: {malformed}"
        ) from malformed
    if not isinstance(answered, dict):
        raise ApplyError(f"{target} answered {answered!r}, which is not a record")
    rows = answered.get(ROWS)
    rendered = answered.get(TABLE)
    if rows is None and rendered is None:
        raise ApplyError(
            f"{target} publishes neither {ROWS} nor {TABLE}: a deployment answers both, so name "
            f"the attribute that is one, or a directory a build of it produced"
        )
    if not isinstance(rows, list) or not isinstance(rendered, str):
        raise ApplyError(
            f"{target} publishes {ROWS} as {type(rows).__name__} and {TABLE} as "
            f"{type(rendered).__name__}, and a table is a list of rows beside the text they render "
            f"into"
        )
    return Answer(rows=tuple(_stated(target, row) for row in rows), rendered=rendered)


def _stated(target: str, row: Any) -> dict[str, str]:
    """One evaluated row, held to the fields a produced row carries.

    Raises:
        ApplyError: If the row is not a record, naming the target.
    """
    if not isinstance(row, dict):
        raise ApplyError(f"{target} publishes {row!r} among its rows, which is not a row")
    return {name: str(row.get(name, "")) for name in FIELDS}
