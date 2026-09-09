"""The one fixture every end-to-end folder shares by name rather than by import.

``rookery.snapshot`` resolves ``state_root`` by name to place each run's live
state - overlays, monitor and control sockets - and falls back to its own default
when no fixture answers (``rookery/snapshot/plugin.py:256-279``). This repository
answers, because the runner owns that directory: it keeps it when a run fails and
removes it when one passes, and it keeps the prefix short enough that the sockets
underneath it fit ``AF_UNIX``'s 108 bytes.

The snapshot *cache* is deliberately not redirected here. It lives under the real
``$XDG_CACHE_HOME`` so the cut one run publishes is the cut the next run resumes,
which is the whole point.

``$PLANNER_CLI_SRC`` is not put on the import path here. pytest loads no conftest
above the directory of the ini file it found, so a run naming one folder never
reads this file at all: the runner puts both roots on ``PYTHONPATH`` instead.
"""

from __future__ import annotations

from pathlib import Path

import pytest

import delivery


@pytest.fixture(scope="session")
def state_root() -> Path:
    """The directory this run's live machine state is placed under."""
    return delivery.state_root()
