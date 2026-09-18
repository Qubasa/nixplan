"""What the machines currently hold, asked the way the command asks it.

This module holds no question, no argv, no remote script and no verdict
vocabulary. It calls the machine report's own status reading with the runner
it is handed and renders the records that reading answers with, so the view
and `planner status` cannot disagree about one fleet, and a fact the report
does not answer is a seam against the report's own capability rather than a
question invented here.

It asks when a reader asks, once per request, and the answer carries when it
was taken: nothing here is a timer, a poll or an answer kept from an earlier
request.
"""

from __future__ import annotations

import dataclasses
from collections.abc import Callable, Mapping
from datetime import UTC, datetime
from pathlib import Path
from typing import Any

import remote
import report
from manifest import Deployment

ENTRY = "entry"
VALUE = "value"
HOLDING = "holding"


def taken() -> str:
    """Return the moment an answer was taken, to the second, in UTC."""
    return datetime.now(UTC).isoformat(timespec="seconds")


def answers(
    deployment: Deployment,
    runner: remote.Runner,
    *,
    ssh_key: Path | None = None,
    user: str = "root",
    base_env: Mapping[str, str] | None = None,
    clock: Callable[[], str] = taken,
) -> dict[str, Any]:
    """Return what the machines hold, as the report's own records.

    Args:
        deployment: The build the questions are asked about.
        runner: The channel the questions are asked over, which is the one the
            command uses.
        ssh_key: The private key to connect with, where one is named.
        user: The login on each machine.
        base_env: The environment the channel is opened in, the process's own
            where none is named.
        clock: What answers when this answer was taken.

    Returns:
        One record per answer the report made, the machines it could not ask,
        the lines the report printed, and the time the questions were put. A
        machine that answered nothing is in `unasked` rather than shown as
        holding nothing: absence is an endpoint's own answer and silence is
        not one.
    """
    at = clock()
    answered = report.status(deployment, runner, ssh_key=ssh_key, user=user, base_env=base_env)
    return {
        "taken": at,
        "answers": [_answer(verdict) for verdict in answered.answers],
        "unasked": list(answered.unasked),
        "lines": list(answered.lines),
    }


def _answer(verdict: report.Verdict) -> dict[str, Any]:
    """Return one record of the report's, with the lines it renders into."""
    return {
        "kind": _kind(verdict),
        "record": dataclasses.asdict(verdict),
        "lines": list(report.lines_of(verdict)),
    }


def _kind(verdict: report.Verdict) -> str:
    """Return which of the three answers a record is."""
    if isinstance(verdict, report.EntryAnswer):
        return ENTRY
    if isinstance(verdict, report.ValueAnswer):
        return VALUE
    return HOLDING
