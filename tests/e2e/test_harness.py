"""The harness's own code, and the pure half of the command it drives.

This file asserts nothing about the planner. It is beside the harness because
the harness is code too, and its pure half - which machine a key names, which
address a delivery dials, which end-to-end tests exist - is a function of its
arguments and needs no machine.

The command's own pure half is asserted here for the same reason: the order it
applies a deployment in and everything it refuses before it dials are functions
of a built directory and a value source, so both are built on `tmp_path` and the
command is handed a recorder instead of a machine. What it then does to a booted
machine is asserted in the folders beside this one, which is the only place that
can be asserted honestly - and `portablectl` is asserted nowhere else at all:
nothing here states what a real one prints, so no verdict the command reads out
of it is measured against an invention.
"""

import base64
import grp
import hashlib
import json
import os
import pwd
import re
import shlex
import stat
import subprocess
import sys
from pathlib import Path
from typing import Any, NoReturn

import pytest

import apply
import delivery
import errors
import generation
import manifest
import order
import planner
import remote
import report
import runner
from manifest import ValueFile

SERVER_ENTRY = "site:server"
SERVER_KEY = "site:server@alpha"
CLIENT_KEY = "check:client@beta"

SESSION_VALUE = "issuer:vars/session"
CA_VALUE = "issuer:vars/ca"


def _sealed_path(path: str) -> str:
    """Where a machine keeps the copy of one value it can open by itself.

    The derivation is the library's and this repeats its answer rather than
    importing it, because the command imports nothing of `lib/` either: what it
    reads is the record, and this writes the record a build writes.
    """
    return f"/var/lib/planner/sealed{path.removeprefix('/run/vars')}.age"


def _delivered(
    path: str,
    secrecy: str,
    *,
    owner: str = "root",
    group: str = "root",
    mode: str = "0400",
) -> dict[str, str]:
    """One generated file record, at the ownership the planner defaults to."""
    return {
        "path": path,
        "sealed": _sealed_path(path),
        "secrecy": secrecy,
        "owner": owner,
        "group": group,
        "mode": mode,
    }


TOKEN = {"token": _delivered("/run/vars/issuer/session/token", "secret")}
PROGRAM = "/nix/store/3k9m2x7vqz1n5bpr4jlfg8ys6cwh0d2a-mint-token.drv"

# What a run delivers when the assertion is about what carried it. Bytes rather
# than a string, because a generated secret is bytes.
SECRET = b"s3cret-payload"

# One word of the bech32 alphabet, which is what a native age recipient is. It
# stands in the plan's own machine records, where the command reads it: the
# grammar is the library's, and a line it refused reached no plan.
RECIPIENT = "age1qpzry9x8gf2tvdw0s3jn54khce6mua7lqpzry9x8gf2tvdw0s3jn54khce"

PLAN = {
    "machine:alpha": {"address": "10.0.0.10", "tags": ["cluster"], "sealRecipient": RECIPIENT},
    "machine:beta": {"address": "10.0.0.11", "tags": ["cluster"], "sealRecipient": RECIPIENT},
    SERVER_KEY: {"key": "sha256-1111111111111111"},
    CLIENT_KEY: {"key": "sha256-2222222222222222"},
    SESSION_VALUE: {
        "per": "instance",
        "delivery": ["alpha", "beta"],
        "files": TOKEN,
    },
    CA_VALUE: {
        "per": "instance",
        "deploy": False,
        "delivery": [],
        "files": {"ca.pub": _delivered("/run/vars/issuer/ca/ca.pub", "public")},
    },
}


class Recorder:
    """A runner that records the argv it was handed instead of running it.

    The payload of a step is dropped rather than recorded. A harness that kept
    the bytes of a value would be a second copy of the leak the argv no longer
    carries, and the assertion that no recorded argv holds them would then be
    made beside a recording of them.
    """

    def __init__(self) -> None:
        self.commands: list[list[str]] = []

    def run(
        self, cmd: list[str], *, env: dict[str, str] | None = None, stdin: bytes | None = None
    ) -> object:
        self.commands.append(cmd)
        return env

    def output(
        self, cmd: list[str], *, env: dict[str, str] | None = None, stdin: bytes | None = None
    ) -> str:
        self.commands.append(cmd)
        return ""


def _asked_what_it_holds(cmd: list[str]) -> bool:
    """Whether one argv is the question of what a machine holds.

    Every recorder below answers that question before its own answers: it is
    asked of every machine of a report and of an apply, and a recorder handing
    it an endpoint record or an activation's report would be handing the
    command an answer no machine gives.
    """
    return remote.HELD in cmd[-1]


PUBLISHED = "sha256-3333333333333333"


def _stated(key: str, machine: str, address: str) -> dict[str, Any]:
    """State one placed entry the way a manifest states it."""
    instance, service = key.split("@")[0].split(":")
    return {
        "path": f"entries/{instance}-{service}-{machine}",
        "realiser": "flakelet",
        "profile": None,
        "machine": machine,
        "address": address,
        "units": [f"{instance}-{service}-serve.service"],
        "key": PUBLISHED,
    }


# What the reading publishes about each realiser it knows, verbatim as
# `operator/read.nix` emits it: the scopes it realises - flakelet's core writes
# paths only root owns, so it states one - and what a machine's own answer names
# its holdings by. flakelet's is the prefix of the identity it registers, and an
# image's is the shape of the file name it is listed under.
URL_PREFIX = "plan:"
SEPARATOR = "_"
ALPHABET = "0123456789abcdef"
DIGEST_LENGTH = 16
REALISERS: dict[str, Any] = {
    "flakelet": {"holdings": {"urlPrefix": URL_PREFIX}, "scopes": ["system"]},
    "image": {
        "holdings": {
            "digestAlphabet": ALPHABET,
            "digestLength": DIGEST_LENGTH,
            "separator": SEPARATOR,
        },
        "scopes": ["system", "user"],
    },
}


def _holds(*sections: tuple[str, int, str]) -> str:
    """Return one machine's answer to that question, section by section.

    Each section is a realiser, the exit status of its own tool and that tool's
    answer, printed the way the question prints them. Only an endpoint answer is
    ever fabricated here: an image verdict measured against an invented
    `portablectl` listing is what `tests/e2e/portable-image` exists to avoid.
    """
    return "".join(
        f"{remote.HELD} {realiser} {status}\n{said}\n" for realiser, status, said in sections
    )


def _registered(*records: dict[str, Any]) -> str:
    """Return what `flakelet status --json` with no name answers, as JSON."""
    return json.dumps(list(records))


def _registration(key: str, name: str, **fields: Any) -> dict[str, Any]:
    """One entry a flakelet endpoint registers, in the fields the locked one reports.

    The identity is the one the realiser wrote into the artifact and the
    endpoint reports back, so a record of this planner's carries the published
    prefix and the plan key behind it.
    """
    return {
        "name": name,
        "origin": "manual",
        "generation": 1,
        "units": {},
        "locked_url": f"{URL_PREFIX}{key}",
        "state": "running",
        "last_error": None,
        **fields,
    }


def _reached(plan: dict[str, Any], values: dict[str, dict[str, Any]]) -> dict[str, Any]:
    """Return the machines table of a build that seals nothing.

    One record per machine a delivered value reaches, which is the delivery set
    and never the placement, each saying that machine's copies are not sealed:
    a machine states no recipient until a test states one.
    """
    scopes = {
        key.removeprefix("machine:"): record.get("scope", "system")
        for key, record in plan.items()
        if key.startswith("machine:") and isinstance(record, dict)
    }
    return {
        machine: {"sealed": False, "scope": scopes.get(machine, "system")}
        for machine in sorted(
            {machine for value in values.values() for machine in value.get("delivery", [])}
        )
    }


def _sealing(*machines: str, scope: str = "system") -> dict[str, Any]:
    """Return machines table records for machines whose copies are sealed."""
    return {
        machine: {"sealed": True, "scope": scope, "path": f"machines/{machine}"}
        for machine in machines
    }


def _unsealers(root: Path, machines: dict[str, Any]) -> None:
    """Write the per-machine unsealer of every record that names one.

    A link into a directory beside the build, because that is what the build
    is, and carrying the three files the artifact carries: the program the
    unit runs, the trial a report asks, and the unit itself.
    """
    for machine, record in sorted(machines.items()):
        stated = record.get("path")
        if not stated:
            continue
        artifact = root / "artifacts" / f"machines-{machine}"
        (artifact / "bin").mkdir(parents=True, exist_ok=True)
        for program in ("unseal", "check"):
            (artifact / "bin" / program).write_text("#!/bin/sh\nexit 0\n")
        (artifact / "planner-unseal.service").write_text("[Unit]\nDescription=unseal\n")
        link = root / stated
        link.parent.mkdir(parents=True, exist_ok=True)
        link.symlink_to(artifact)


def _built(
    root: Path,
    *,
    plan: dict[str, Any],
    entries: dict[str, dict[str, Any]],
    values: dict[str, dict[str, Any]] | None = None,
    machines: dict[str, Any] | None = None,
    realisers: dict[str, Any] | None = None,
    rows: list[dict[str, str]] | None = None,
    table: str = "",
) -> manifest.Deployment:
    """Write a built deployment at ``root`` and read it back as the command does.

    The tests exercise the command's own reader rather than a hand-built object,
    so what a folder's build produces and what these assertions hand over are the
    same interface: a directory holding a plan, a manifest, the diagnostics and
    one artifact directory per placed entry.

    Args:
        root: A directory to write the deployment into.
        plan: The plan artifact.
        entries: The manifest's placed entries, as `_stated` states them.
        values: The manifest's value entries.
        machines: The machines a delivered value reaches, the delivery sets'
            own and sealing nothing by default.
        rows: The diagnostics rows.
        realisers: The scopes each realiser publishes, the two real ones by default.
        table: The rendered diagnostics table.

    Returns:
        The deployment, read back from what was written.
    """
    root.mkdir(parents=True, exist_ok=True)
    reached = _reached(plan, values or {}) if machines is None else machines
    (root / "plan.json").write_text(json.dumps(plan))
    (root / "manifest.json").write_text(
        json.dumps(
            {
                "version": manifest.VERSION,
                "storeDir": "/nix/store",
                "entries": entries,
                "values": values or {},
                "machines": reached,
                "realisers": REALISERS if realisers is None else realisers,
            }
        )
    )
    _unsealers(root, reached)
    (root / "diagnostics.json").write_text(json.dumps(rows or []))
    (root / "diagnostics.txt").write_text(table)
    # A symlink to a directory beside the build, because that is what a build is:
    # a farm of links into the store, and what the command copies and activates
    # is what a link resolves to.
    for key, stated in entries.items():
        if "path" not in stated:
            continue
        artifact = root / "artifacts" / Path(stated["path"]).name
        artifact.mkdir(parents=True)
        instance, service = key.split("@")[0].split(":")
        (artifact / "meta.json").write_text(json.dumps({"name": f"{instance}-{service}"}))
        # Each unit file is a link of its own, because that is what a machine's
        # endpoint reports for the generation it runs: the path of the file, not
        # the path of the artifact holding it.
        for unit in stated.get("units", []):
            (root / "units").mkdir(parents=True, exist_ok=True)
            file = root / "units" / unit
            file.write_text(f"[Unit]\nDescription={unit}\n")
            (artifact / "units").mkdir(parents=True, exist_ok=True)
            (artifact / "units" / unit).symlink_to(file)
        link = root / stated["path"]
        link.parent.mkdir(parents=True, exist_ok=True)
        link.symlink_to(artifact)
    return manifest.read(root)


def _source(root: Path, files: dict[str, str]) -> Path:
    """Write a value source holding ``files``, keyed by `<entry-key>/<file>`."""
    root.mkdir(parents=True, exist_ok=True)
    for relative, content in files.items():
        path = root / relative
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(content)
    return root


def _bytes_source(root: Path, files: dict[str, bytes]) -> Path:
    """Write a value source holding bytes, keyed by `<entry-key>/<file>`.

    A generated secret is arbitrary bytes, so the payload of an assertion about
    what a step carries is written as bytes rather than as text.
    """
    root.mkdir(parents=True, exist_ok=True)
    for relative, content in files.items():
        path = root / relative
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_bytes(content)
    return root


def _delivering(root: Path) -> manifest.Deployment:
    """One entry on alpha, which the session value's one file is delivered to."""
    return _built(
        root,
        plan=PLAN,
        entries={SERVER_KEY: _stated(SERVER_KEY, "alpha", "10.0.0.10")},
        values={SESSION_VALUE: {"delivery": ["alpha"], "files": TOKEN}},
    )


def _activated(log: tuple[str, ...]) -> list[str]:
    """Return the entry keys the log shows activated, in the order it shows them."""
    return [line.split()[1] for line in log if line.startswith("activate ")]


def test_an_entry_is_copied_before_it_is_activated(tmp_path: Path) -> None:
    """An artifact is on the machine before the endpoint is asked to use it."""
    deployment = _built(
        tmp_path,
        plan=PLAN,
        entries={SERVER_KEY: _stated(SERVER_KEY, "alpha", "10.0.0.10")},
    )
    recorder = Recorder()

    apply.apply(deployment, recorder, base_env={})

    asked, copy, activation = recorder.commands
    assert _asked_what_it_holds(asked)
    resolved = str(tmp_path / "artifacts" / "site-server-alpha")
    assert copy[:2] == ["nix", "copy"]
    assert copy[3] == "ssh://root@10.0.0.10"
    assert copy[-1] == resolved
    assert activation[0] == "ssh"
    assert activation[-2] == "root@10.0.0.10"
    assert f"flakelet activate site-server {resolved}" in activation[-1]


def test_a_provider_is_applied_before_its_consumer(tmp_path: Path) -> None:
    """The read the plan resolved decides, not the order the caller named."""
    plan = {**PLAN, CLIENT_KEY: {"reads": {"site": {"entry": SERVER_KEY}}}}
    deployment = _built(
        tmp_path,
        plan=plan,
        entries={
            CLIENT_KEY: _stated(CLIENT_KEY, "beta", "10.0.0.11"),
            SERVER_KEY: _stated(SERVER_KEY, "alpha", "10.0.0.10"),
        },
    )

    log = apply.apply(deployment, Recorder(), only=(CLIENT_KEY, SERVER_KEY), base_env={})

    assert _activated(log) == [SERVER_KEY, CLIENT_KEY]


def test_two_entries_each_read_the_others_capability(tmp_path: Path) -> None:
    """A mutual pair has no first element, so one edge is named and both are applied."""
    plan = {
        **PLAN,
        SERVER_KEY: {"reads": {"back": {"entry": CLIENT_KEY}}},
        CLIENT_KEY: {"reads": {"site": {"entry": SERVER_KEY}}},
    }
    deployment = _built(
        tmp_path,
        plan=plan,
        entries={
            SERVER_KEY: _stated(SERVER_KEY, "alpha", "10.0.0.10"),
            CLIENT_KEY: _stated(CLIENT_KEY, "beta", "10.0.0.11"),
        },
    )

    log = apply.apply(deployment, Recorder(), base_env={})

    assert sorted(_activated(log)) == [CLIENT_KEY, SERVER_KEY]
    against = [line for line in log if line.startswith("ordered against ")]
    assert len(against) == 1
    assert SERVER_KEY in against[0]
    assert CLIENT_KEY in against[0]


HUB_KEY = "aggregate:hub@alpha"
UNAPPLIED_KEY = "spare:agent@beta"


def _set_read(*providers: str) -> dict[str, Any]:
    """State one `reach = "all"` read the way the plan records it, keyed by provider."""
    return {
        "reach": "all",
        "delivered": True,
        "entries": {provider: {"url": provider} for provider in providers},
    }


def test_an_entry_reading_a_set_of_providers_follows_all_of_them(tmp_path: Path) -> None:
    """A set-valued read names its providers keyed by plan key, and each one is an edge."""
    plan = {
        **PLAN,
        HUB_KEY: {"reads": {"agents": _set_read(SERVER_KEY, CLIENT_KEY, UNAPPLIED_KEY)}},
    }
    deployment = _built(
        tmp_path,
        plan=plan,
        entries={
            HUB_KEY: _stated(HUB_KEY, "alpha", "10.0.0.10"),
            SERVER_KEY: _stated(SERVER_KEY, "alpha", "10.0.0.10"),
            CLIENT_KEY: _stated(CLIENT_KEY, "beta", "10.0.0.11"),
        },
    )

    log = apply.apply(deployment, Recorder(), base_env={})

    activated = _activated(log)
    # The consumer sorts below both providers, so the order is the read's and not
    # the key sort's, and the provider this run does not apply contributes nothing.
    assert activated[-1] == HUB_KEY
    assert sorted(activated[:2]) == [CLIENT_KEY, SERVER_KEY]
    assert [line for line in log if line.startswith("ordered against ")] == []


def test_a_mutual_pair_is_reported_however_each_side_reads_the_other(tmp_path: Path) -> None:
    """One side reading the other as a set is the same cycle, and it is reported."""
    plan = {
        **PLAN,
        SERVER_KEY: {"reads": {"clients": _set_read(CLIENT_KEY)}},
        CLIENT_KEY: {"reads": {"site": {"entry": SERVER_KEY, "delivered": True}}},
    }
    deployment = _built(
        tmp_path,
        plan=plan,
        entries={
            SERVER_KEY: _stated(SERVER_KEY, "alpha", "10.0.0.10"),
            CLIENT_KEY: _stated(CLIENT_KEY, "beta", "10.0.0.11"),
        },
    )

    log = apply.apply(deployment, Recorder(), base_env={})

    assert sorted(_activated(log)) == [CLIENT_KEY, SERVER_KEY]
    against = [line for line in log if line.startswith("ordered against ")]
    assert len(against) == 1
    assert SERVER_KEY in against[0]
    assert CLIENT_KEY in against[0]


def test_a_resolved_read_recorded_in_an_unknown_shape_is_refused(tmp_path: Path) -> None:
    """A delivered read naming its providers in neither shape is a refusal, not zero edges."""
    plan = {
        **PLAN,
        CLIENT_KEY: {
            "reads": {"site": {"reach": "all", "delivered": True, "providers": [SERVER_KEY]}}
        },
    }
    deployment = _built(
        tmp_path,
        plan=plan,
        entries={
            CLIENT_KEY: _stated(CLIENT_KEY, "beta", "10.0.0.11"),
            SERVER_KEY: _stated(SERVER_KEY, "alpha", "10.0.0.10"),
        },
    )
    recorder = Recorder()

    with pytest.raises(errors.ApplyError) as raised:
        apply.apply(deployment, recorder, base_env={})

    message = str(raised.value)
    assert CLIENT_KEY in message
    assert "site" in message
    assert recorder.commands == []


def test_a_value_the_plan_names_has_no_bytes_in_the_source(tmp_path: Path) -> None:
    """A file the plan names and the source has no bytes for is refused, not skipped."""
    deployment = _built(
        tmp_path / "built",
        plan=PLAN,
        entries={SERVER_KEY: _stated(SERVER_KEY, "alpha", "10.0.0.10")},
        values={SESSION_VALUE: {"delivery": ["alpha", "beta"], "files": TOKEN}},
    )
    recorder = Recorder()

    with pytest.raises(errors.ApplyError) as raised:
        apply.apply(deployment, recorder, source=_source(tmp_path / "values", {}), base_env={})

    assert SESSION_VALUE in str(raised.value)
    assert "token" in str(raised.value)
    assert recorder.commands == []


def test_a_value_source_carries_bytes_the_plan_does_not_name(tmp_path: Path) -> None:
    """Bytes nobody declared would be written nowhere, so the source is wrong."""
    deployment = _built(
        tmp_path / "built",
        plan=PLAN,
        entries={SERVER_KEY: _stated(SERVER_KEY, "alpha", "10.0.0.10")},
        values={SESSION_VALUE: {"delivery": ["alpha"], "files": TOKEN}},
    )
    source = _source(
        tmp_path / "values",
        {f"{SESSION_VALUE}/token": "s3cret", f"{SESSION_VALUE}/spare": "unnamed"},
    )
    recorder = Recorder()

    with pytest.raises(errors.ApplyError) as raised:
        apply.apply(deployment, recorder, source=source, base_env={})

    assert "spare" in str(raised.value)
    assert recorder.commands == []


def test_a_generated_value_is_not_asked_of_the_operator(tmp_path: Path) -> None:
    """A value entry recording a program is the generator's, so no source is wanted."""
    deployment = _built(
        tmp_path / "built",
        plan=PLAN,
        entries={SERVER_KEY: _stated(SERVER_KEY, "alpha", "10.0.0.10")},
        values={SESSION_VALUE: {"delivery": ["alpha"], "files": TOKEN, "program": PROGRAM}},
    )
    recorder = Recorder()

    log = apply.apply(deployment, recorder, base_env={})

    assert [line for line in log if line.startswith("value ")] == []
    assert _activated(log) == [SERVER_KEY]


def test_a_value_source_holds_the_bytes_of_a_generated_value(tmp_path: Path) -> None:
    """Bytes the generator owns are refused where they are, not reported as undeclared."""
    deployment = _built(
        tmp_path / "built",
        plan=PLAN,
        entries={SERVER_KEY: _stated(SERVER_KEY, "alpha", "10.0.0.10")},
        values={SESSION_VALUE: {"delivery": ["alpha"], "files": TOKEN, "program": PROGRAM}},
    )
    source = _source(tmp_path / "values", {f"{SESSION_VALUE}/token": "s3cret"})
    recorder = Recorder()

    with pytest.raises(errors.ApplyError) as raised:
        apply.apply(deployment, recorder, source=source, base_env={})

    message = str(raised.value)
    assert f"{SESSION_VALUE}/token" in message
    assert PROGRAM in message
    assert "the generator's" in message
    assert "declares" not in message
    assert recorder.commands == []


def test_a_value_the_operator_owns_still_needs_a_source(tmp_path: Path) -> None:
    """The same entry recording no program is the operator's, and a run with none is refused."""
    deployment = _built(
        tmp_path / "built",
        plan=PLAN,
        entries={SERVER_KEY: _stated(SERVER_KEY, "alpha", "10.0.0.10")},
        values={SESSION_VALUE: {"delivery": ["alpha"], "files": TOKEN}},
    )
    recorder = Recorder()

    with pytest.raises(errors.ApplyError) as raised:
        apply.apply(deployment, recorder, base_env={})

    assert SESSION_VALUE in str(raised.value)
    assert "no value source was named" in str(raised.value)
    assert recorder.commands == []


def test_a_deployment_the_planner_refuses_is_not_applied(tmp_path: Path) -> None:
    """An error row is the planner's own refusal, and the table is what it says."""
    table = "slot-reads-nothing  check:client@beta  no provider exports site\n"
    deployment = _built(
        tmp_path,
        plan=PLAN,
        entries={SERVER_KEY: _stated(SERVER_KEY, "alpha", "10.0.0.10")},
        rows=[
            {
                "id": "slot-reads-nothing",
                "subject": CLIENT_KEY,
                "severity": "error",
                "message": "no provider exports site",
                "evidence": "",
                "resolution": "",
            }
        ],
        table=table,
    )
    recorder = Recorder()

    with pytest.raises(errors.ApplyError) as raised:
        apply.apply(deployment, recorder, base_env={})

    assert table.strip() in str(raised.value)
    assert recorder.commands == []


def test_an_entry_named_on_the_command_line_is_not_in_the_plan(tmp_path: Path) -> None:
    """A key the deployment does not carry names the keys it does carry."""
    deployment = _built(
        tmp_path,
        plan=PLAN,
        entries={SERVER_KEY: _stated(SERVER_KEY, "alpha", "10.0.0.10")},
        values={SESSION_VALUE: {"delivery": [], "files": TOKEN}},
    )
    recorder = Recorder()

    with pytest.raises(errors.ApplyError) as raised:
        apply.apply(deployment, recorder, only=("site:server@gamma",), base_env={})

    message = str(raised.value)
    assert "site:server@gamma" in message
    assert SERVER_KEY in message
    assert SESSION_VALUE in message
    assert recorder.commands == []


class Reporting(Recorder):
    """A recorder that answers each question the way a machine answers it.

    Four questions reach a machine through `output` and each has its own
    answer: what the machine holds is nothing, a value write says whether the
    bytes moved, a restart says nothing, and an activation reports the steps
    the artifact's own script took.
    """

    def output(
        self, cmd: list[str], *, env: dict[str, str] | None = None, stdin: bytes | None = None
    ) -> str:
        self.commands.append(cmd)
        if _asked_what_it_holds(cmd):
            return ""
        if 'cat > "$tmp"' in cmd[-1]:
            return "unchanged"
        if "try-restart" in cmd[-1]:
            return ""
        return "started site-server-serve.service"


def _reading() -> dict[str, Any]:
    """One resolved read of the secret export backed by the session value's file."""
    return {
        "entry": "issuer:api@alpha",
        "values": {"token": {"path": TOKEN["token"]["path"], "secrecy": "secret"}},
    }


class Rotating(Reporting):
    """A recorder whose machines say every value write moved the bytes."""

    def output(
        self, cmd: list[str], *, env: dict[str, str] | None = None, stdin: bytes | None = None
    ) -> str:
        answered = super().output(cmd, env=env, stdin=stdin)
        return "changed" if answered == "unchanged" else answered


def test_a_value_read_by_two_entries_on_two_machines(tmp_path: Path) -> None:
    """One value on two machines is two writes, and a move restarts both readers.

    Each restart is its own step naming its own machine, because the readers are
    two entries and the value is one: a run that folded them would leave one
    machine's units holding the bytes the run replaced.
    """
    deployment = _built(
        tmp_path / "built",
        plan={
            **PLAN,
            SERVER_KEY: {"key": "sha256-1111111111111111", "reads": {"token": _reading()}},
            CLIENT_KEY: {"key": "sha256-2222222222222222", "reads": {"token": _reading()}},
        },
        entries={
            SERVER_KEY: _stated(SERVER_KEY, "alpha", "10.0.0.10"),
            CLIENT_KEY: _stated(CLIENT_KEY, "beta", "10.0.0.11"),
        },
        values={SESSION_VALUE: {"delivery": ["alpha", "beta"], "files": TOKEN}},
    )
    source = _source(tmp_path / "values", {f"{SESSION_VALUE}/token": "s3cret"})

    log = apply.apply(deployment, Rotating(), source=source, base_env={})

    restarts = [line for line in log if line.startswith("restart ")]
    # Sorted by value and then by entry key, so two machines are two lines in an
    # order two runs of one deployment agree on.
    assert restarts == [
        f"restart {CLIENT_KEY} for {SESSION_VALUE} on beta at root@10.0.0.11",
        f"restart {SERVER_KEY} for {SESSION_VALUE} on alpha at root@10.0.0.10",
    ], log

    # Every restart is after every activation: a unit started by an activation is
    # already holding this run's bytes, and one that was running is not.
    assert log.index(restarts[0]) > max(log.index(line) for line in log if "activate " in line)


def test_a_run_is_asked_what_it_would_do(tmp_path: Path) -> None:
    """The steps a dry run prints are the steps the same run prints when it acts.

    The one difference is what a machine said, which a dry run never asked for:
    a reported line is indented and every step line is not, so the two logs are
    comparable line by line and are compared that way here.
    """
    deployment = _built(
        tmp_path / "built",
        plan={**PLAN, CLIENT_KEY: {"reads": {"site": {"entry": SERVER_KEY}}}},
        entries={
            CLIENT_KEY: _stated(CLIENT_KEY, "beta", "10.0.0.11"),
            SERVER_KEY: _stated(SERVER_KEY, "alpha", "10.0.0.10"),
        },
        values={SESSION_VALUE: {"delivery": ["alpha", "beta"], "files": TOKEN}},
    )
    source = _source(tmp_path / "values", {f"{SESSION_VALUE}/token": "s3cret"})

    asked = Reporting()
    printed: list[str] = []
    would = apply.apply(
        deployment, asked, source=source, dry_run=True, base_env={}, log=printed.append
    )

    assert asked.commands == []
    assert list(would) == printed
    assert [line for line in would if line.startswith("value ")]
    assert _activated(would) == [SERVER_KEY, CLIENT_KEY]

    taken = Reporting()
    did = apply.apply(deployment, taken, source=source, base_env={})

    assert taken.commands != []
    assert [line for line in did if not line.startswith("  ")] == list(would)
    assert [line for line in did if line.startswith("  ")] == [
        "  unchanged",
        "  unchanged",
        "  started site-server-serve.service",
        "  started site-server-serve.service",
    ]


def test_a_dry_run_hands_no_payload_to_the_channel_it_substitutes(tmp_path: Path) -> None:
    """A dry run of a delivered value dials nothing and prints the real run's lines.

    The bytes are read out of the source and handed to a channel that takes no
    step with them, which is what keeps the two runs comparable line for line:
    a payload is a parameter of a step, not a decision the walk takes.
    """
    deployment = _delivering(tmp_path / "built")
    source = _bytes_source(tmp_path / "values", {f"{SESSION_VALUE}/token": SECRET})

    asked = Reporting()
    would = apply.apply(deployment, asked, source=source, dry_run=True, base_env={})

    assert asked.commands == []

    taken = Reporting()
    did = apply.apply(deployment, taken, source=source, base_env={})

    assert [line for line in did if not line.startswith("  ")] == list(would)
    assert [line for line in would if line.startswith("value ")] == [
        f"value {SESSION_VALUE} token -> root@10.0.0.10:{TOKEN['token']['path']} (root:root 0400)"
    ]


def _leaks(content: bytes) -> dict[str, bytes]:
    """Return the encodings of ``content`` no argument vector may carry."""
    return {
        "the bytes": content,
        "base64": base64.b64encode(content),
        "base32": base64.b32encode(content),
        "hex": content.hex().encode(),
        "a digest": hashlib.sha256(content).hexdigest().encode(),
        "a digest in base64": base64.b64encode(hashlib.sha256(content).digest()),
    }


def test_a_process_table_observed_during_a_value_write(tmp_path: Path) -> None:
    """What a process table shows of a step is the argv, and no argv holds a value.

    The argv is read off the channel rather than sampled out of `/proc`: a write
    lasts a millisecond, and a sampler that passed by missing the window would be
    worse than no test. It is one vector on both hosts, the machine's own command
    line being the element that carries the script.
    """
    deployment = _delivering(tmp_path / "built")
    source = _bytes_source(tmp_path / "values", {f"{SESSION_VALUE}/token": SECRET})
    recorder = Reporting()

    apply.apply(deployment, recorder, source=source, base_env={})

    written = [cmd for cmd in recorder.commands if 'cat > "$tmp"' in cmd[-1]]
    assert len(written) == 1
    assert written[0][-1] == remote.write_script(
        ValueFile(
            name="token",
            path=TOKEN["token"]["path"],
            sealed=TOKEN["token"]["sealed"],
            secrecy="secret",
            owner="root",
            group="root",
            mode="0400",
        )
    )
    for cmd in recorder.commands:
        for word in cmd:
            spoken = word.encode(errors="surrogateescape")
            for what, needle in _leaks(SECRET).items():
                assert needle not in spoken, f"{what} of the value is in {word}"


def test_two_values_of_one_length_run_one_argument_vector(tmp_path: Path) -> None:
    """Two payloads of one length are one argv and one log, which is the property.

    Stronger than the absence of a known needle: the vector is a function of the
    plan, so two deliveries of different bytes to one path are indistinguishable
    from anything the channel was handed.
    """
    deployment = _delivering(tmp_path / "built")
    runs = []
    for name, content in (("one", b"\x00\x01payload-one"), ("two", b"payload-two\xff\xfe")):
        source = _bytes_source(tmp_path / name, {f"{SESSION_VALUE}/token": content})
        recorder = Reporting()
        log = apply.apply(deployment, recorder, source=source, base_env={})
        runs.append((recorder.commands, [line for line in log if not line.startswith("  ")]))

    assert runs[0][0] == runs[1][0]
    assert runs[0][1] == runs[1][1]
    assert any('cat > "$tmp"' in cmd[-1] for cmd in runs[0][0])


def _sealer(root: Path) -> Path:
    """Return a stand-in for the sealing program the command's own wrapper names.

    It is not `age` and does not pretend to be: what these assertions are about
    is where the ciphertext travels and what the argument vectors carry, so the
    program has to be one the run resolves, take the recipient as an argument,
    read the plaintext on its input and answer bytes that are not the plaintext.
    Whether the real tool round-trips is `tests/e2e/delivery.py`'s own guard,
    asked of the resolved tool rather than of an invention.
    """
    program = root / "seal"
    program.parent.mkdir(parents=True, exist_ok=True)
    program.write_text(
        f"#!{sys.executable}\n"
        "import sys\n"
        "sys.stdout.buffer.write(\n"
        "    b'sealed:' + sys.argv[2].encode() + b':'\n"
        "    + bytes(byte ^ 0x5A for byte in sys.stdin.buffer.read())\n"
        ")\n"
    )
    program.chmod(0o755)
    return program


# The entry each machine of the sealing cases runs, and where it answers.
PLACED = {"alpha": (SERVER_KEY, "10.0.0.10"), "beta": (CLIENT_KEY, "10.0.0.11")}


def _sealed_delivery(root: Path, *machines: str) -> manifest.Deployment:
    """One entry per machine, and the session value delivered to sealing ``machines``."""
    return _built(
        root,
        plan=PLAN,
        entries={
            PLACED[machine][0]: _stated(PLACED[machine][0], machine, PLACED[machine][1])
            for machine in machines
        },
        values={SESSION_VALUE: {"delivery": list(machines), "files": TOKEN}},
        machines=_sealing(*machines),
    )


def test_a_machine_that_states_no_recipient_is_delivered_to_as_before(tmp_path: Path) -> None:
    """A machine the record says seals nothing is written to exactly as it was."""
    deployment = _delivering(tmp_path / "built")
    source = _bytes_source(tmp_path / "values", {f"{SESSION_VALUE}/token": SECRET})
    recorder = Reporting()

    log = apply.apply(
        deployment,
        recorder,
        source=source,
        base_env={"PLANNER_AGE": str(_sealer(tmp_path / "tools"))},
    )

    assert _steps(log) == [
        f"value {SESSION_VALUE} token -> root@10.0.0.10:{TOKEN['token']['path']} (root:root 0400)",
        f"copy {SERVER_KEY} {(tmp_path / 'built' / 'artifacts' / 'site-server-alpha')} "
        f"-> root@10.0.0.10",
        f"activate {SERVER_KEY} (flakelet) on root@10.0.0.10",
    ]
    # Nothing about a sealed copy reached the machine either: no unsealer, and
    # no step naming the root a sealed copy would live under.
    spoken = " ".join(" ".join(command) for command in recorder.commands)
    assert remote.SEALED_ROOT not in spoken
    assert remote.UNSEAL_UNIT not in spoken


def test_a_run_installs_the_unsealer_of_every_machine_it_seals_a_value_to(
    tmp_path: Path,
) -> None:
    """Each sealing machine is given its unsealer before the first value written to it."""
    deployment = _sealed_delivery(tmp_path / "built", "alpha", "beta")
    source = _bytes_source(tmp_path / "values", {f"{SESSION_VALUE}/token": SECRET})
    recorder = Reporting()

    log = apply.apply(
        deployment,
        recorder,
        source=source,
        base_env={"PLANNER_AGE": str(_sealer(tmp_path / "tools"))},
    )

    steps = _steps(log)
    for machine, address in (("alpha", "10.0.0.10"), ("beta", "10.0.0.11")):
        artifact = (tmp_path / "built" / "artifacts" / f"machines-{machine}").resolve()
        copied = steps.index(f"unsealer {machine} {artifact} -> root@{address}")
        installed = steps.index(f"unseal {machine} on root@{address}")
        written = [at for at, line in enumerate(steps) if f"@{address}:" in line]
        assert copied < installed < min(written), steps
    assert sorted(_activated(log)) == sorted([SERVER_KEY, CLIENT_KEY])


def test_a_run_that_writes_no_value_installs_no_unsealer(tmp_path: Path) -> None:
    """A run restricted to an entry that reads no value contacts no sealing machine."""
    deployment = _built(
        tmp_path / "built",
        plan=PLAN,
        entries={
            SERVER_KEY: _stated(SERVER_KEY, "alpha", "10.0.0.10"),
            CLIENT_KEY: _stated(CLIENT_KEY, "beta", "10.0.0.11"),
        },
        values={SESSION_VALUE: {"delivery": ["alpha"], "files": TOKEN}},
        machines=_sealing("alpha"),
    )
    source = _bytes_source(tmp_path / "values", {f"{SESSION_VALUE}/token": SECRET})
    recorder = Reporting()

    log = apply.apply(
        deployment,
        recorder,
        source=source,
        only=(CLIENT_KEY,),
        base_env={"PLANNER_AGE": str(_sealer(tmp_path / "tools"))},
    )

    assert [
        line for line in _steps(log) if line.startswith(("unsealer ", "unseal ", "sealed "))
    ] == []
    dialled = " ".join(" ".join(command) for command in recorder.commands)
    assert "10.0.0.10" not in dialled


def test_a_sealed_payload_enters_no_argument_vector(tmp_path: Path) -> None:
    """Two sealed deliveries of one length are one argv, and no vector holds a value.

    The sealed bytes are a value's as much as the plaintext is, so the property
    is asserted over both: the vectors of two runs delivering different bytes to
    one path are equal, which is stronger than the absence of a known needle,
    and no element of either carries an encoding of either payload.
    """
    deployment = _sealed_delivery(tmp_path / "built", "alpha")
    program = _sealer(tmp_path / "tools")
    runs = []
    payloads = (b"\x00\x01payload-one", b"payload-two\xff\xfe")
    for name, content in zip(("one", "two"), payloads, strict=True):
        source = _bytes_source(tmp_path / name, {f"{SESSION_VALUE}/token": content})
        recorder = Reporting()
        log = apply.apply(
            deployment, recorder, source=source, base_env={"PLANNER_AGE": str(program)}
        )
        runs.append((recorder.commands, _steps(log)))

    assert runs[0][0] == runs[1][0]
    assert runs[0][1] == runs[1][1]
    # The sealed copy travelled, on a step of its own and before the plaintext.
    sealed = [at for at, line in enumerate(runs[0][1]) if line.startswith("sealed ")]
    written = [at for at, line in enumerate(runs[0][1]) if line.startswith("value ")]
    assert sealed and written and sealed[0] < written[0], runs[0][1]
    assert TOKEN["token"]["sealed"] in runs[0][1][sealed[0]]
    for commands, _ in runs:
        for command in commands:
            for word in command:
                spoken = word.encode(errors="surrogateescape")
                for content in payloads:
                    for what, needle in _leaks(content).items():
                        assert needle not in spoken, f"{what} of the value is in {word}"


def test_a_value_whose_bytes_did_not_move_restarts_nothing(tmp_path: Path) -> None:
    """A rewritten seal is no reason to restart: the plaintext's answer decides."""
    plan = {**PLAN, "reader:app@alpha": {"reads": {"creds": _reading()}}}
    deployment = _built(
        tmp_path / "built",
        plan=plan,
        entries={"reader:app@alpha": _stated("reader:app@alpha", "alpha", "10.0.0.10")},
        values={SESSION_VALUE: {"delivery": ["alpha"], "files": TOKEN}},
        machines=_sealing("alpha"),
    )
    source = _bytes_source(tmp_path / "values", {f"{SESSION_VALUE}/token": SECRET})
    program = str(_sealer(tmp_path / "tools"))

    first = apply.apply(deployment, Rotating(), source=source, base_env={"PLANNER_AGE": program})
    recorder = Reporting()
    again = apply.apply(deployment, recorder, source=source, base_env={"PLANNER_AGE": program})

    # The bytes moved on the first run, so that one restarts the reader.
    assert [line for line in first if line.startswith("restart ")], first
    # On the second the machine said the plaintext was unchanged, and the seal
    # was rewritten anyway, because two sealings of one file differ.
    assert [line for line in _steps(again) if line.startswith("sealed ")], again
    assert "  unchanged" in again
    assert [line for line in again if line.startswith("restart ")] == []
    assert not [cmd for cmd in recorder.commands if "try-restart" in cmd[-1]]


def test_a_dry_run_of_a_deployment_the_planner_refuses(tmp_path: Path) -> None:
    """Asked what it would do, it refuses with the message it refuses with.

    A dry run is the prefix of a real run, so every refusal made from the plan,
    the record and the value source is made, no step is printed, and the two
    messages are one message rather than two that have to be kept in step.
    """
    table = "slot-reads-nothing  check:client@beta  no provider exports site\n"
    refused = _built(
        tmp_path / "refused",
        plan=PLAN,
        entries={SERVER_KEY: _stated(SERVER_KEY, "alpha", "10.0.0.10")},
        rows=[
            {
                "id": "slot-reads-nothing",
                "subject": CLIENT_KEY,
                "severity": "error",
                "message": "no provider exports site",
                "evidence": "",
                "resolution": "",
            }
        ],
        table=table,
    )
    applicable = _built(
        tmp_path / "applicable",
        plan=PLAN,
        entries={SERVER_KEY: _stated(SERVER_KEY, "alpha", "10.0.0.10")},
        values={SESSION_VALUE: {"delivery": [], "files": TOKEN}},
    )
    recorder = Recorder()
    printed: list[str] = []

    for deployment, only in ((refused, ()), (applicable, ("site:server@gamma",))):
        with pytest.raises(errors.ApplyError) as asked:
            apply.apply(
                deployment,
                recorder,
                only=only,
                dry_run=True,
                base_env={},
                log=printed.append,
            )
        with pytest.raises(errors.ApplyError) as acted:
            apply.apply(deployment, recorder, only=only, base_env={})

        assert str(asked.value) == str(acted.value)

    assert printed == []
    assert recorder.commands == []


def test_a_source_directory_is_not_a_target(tmp_path: Path) -> None:
    """A folder that holds a deployment is refused, not handed to nix as a flake.

    `tests/e2e/wired-pair` is where a reader looks first, and it is neither a
    build nor a flake. Left to nix it is parsed as a registry reference and the
    answer is about commit hashes, so the refusal is made here instead.
    """
    folder = tmp_path / "wired-pair" / "deployment"
    folder.mkdir(parents=True)
    (folder / "default.nix").write_text("{ }\n")

    with pytest.raises(errors.ApplyError) as raised:
        manifest.resolve(str(tmp_path / "wired-pair"))

    message = str(raised.value)
    assert "manifest.json" in message
    assert "flake.nix" in message


def test_the_values_of_a_plan_are_its_vars_entries() -> None:
    """A value's entry is told from a service's by the `vars/` in its key."""
    assert sorted(delivery.vars_entries(PLAN)) == [CA_VALUE, SESSION_VALUE]


def test_an_entry_the_plan_placed_resolves_to_its_key() -> None:
    assert delivery.placed_key(PLAN, SERVER_ENTRY, "alpha") == SERVER_KEY
    assert delivery.machines_placed(PLAN, SERVER_ENTRY) == ["alpha"]


def test_a_delivery_is_addressed_from_the_machine_record() -> None:
    """The address is the registry's, not the entry's own target."""
    assert delivery.address_of(PLAN, SERVER_KEY) == "10.0.0.10"
    assert delivery.address_of(PLAN, CLIENT_KEY) == "10.0.0.11"


def test_a_machine_with_no_address_cannot_be_delivered_to() -> None:
    """A registry that declares no address is refused rather than dialled empty."""
    with pytest.raises(delivery.DeliveryError) as raised:
        delivery.address_of({"machine:bare": {"tags": []}, "svc:only@bare": {}}, "svc:only@bare")
    assert "declares no address" in str(raised.value)


def test_a_throwaway_guest_is_reached_with_no_host_config(tmp_path: Path) -> None:
    """The command runs in a single-uid namespace, where a root-owned config is refused.

    The options are the guest's rather than the command's, so the harness states
    them and the command extends what it is given.
    """
    key = tmp_path / "id_ed25519"
    env = delivery.command_env({"PATH": "/usr/bin"}, key)

    assert env["PATH"] == "/usr/bin"
    opts = env["NIX_SSHOPTS"]
    assert "-F /dev/null" in opts
    assert f"-i {key}" in opts
    assert "UserKnownHostsFile=/dev/null" in opts
    assert "GlobalKnownHostsFile=/dev/null" in opts
    assert "BatchMode=yes" in opts


def test_the_key_a_run_connects_with_is_a_private_copy_of_the_images(tmp_path: Path) -> None:
    """ssh refuses a key file others can read, and a store file is readable by all."""
    source = tmp_path / "store-key"
    source.write_text("PRIVATE KEY BYTES\n")
    source.chmod(0o444)
    run_root = tmp_path / "state"
    run_root.mkdir()

    key = delivery.ssh_key(run_root, source)

    assert key.read_text() == source.read_text()
    assert key.stat().st_mode & 0o777 == 0o600


def test_the_service_name_comes_from_the_artifact(tmp_path: Path) -> None:
    """The name the endpoint registers is the one `meta.json` declares."""
    for directory, name in (("site", "site-server"), ("check", "check-client")):
        (tmp_path / directory).mkdir()
        (tmp_path / directory / "meta.json").write_text(json.dumps({"name": name}))

    assert delivery.service_name(tmp_path / "site") == "site-server"
    assert delivery.service_name(tmp_path / "check") == "check-client"


def _layer(tmp_path: Path, folders: dict[str, list[str]]) -> Path:
    """Write a fake end-to-end layer: one directory per folder, with its files."""
    for folder, files in folders.items():
        directory = tmp_path / folder
        directory.mkdir()
        for name in files:
            (directory / name).write_text("")
    (tmp_path / "delivery.py").write_text("")
    return tmp_path


def test_a_developer_runs_every_end_to_end_test(tmp_path: Path) -> None:
    """With no name, every folder's test file is selected and nothing else."""
    root = _layer(
        tmp_path,
        {
            "wired-pair": ["test_wired_pair.py"],
            "portable-image": ["test_portable_image.py", "x.nix"],
        },
    )

    assert sorted(runner.end_to_end_tests(root)) == ["portable-image", "wired-pair"]
    assert [path.name for path in runner.select_tests(root, None)] == [
        "test_portable_image.py",
        "test_wired_pair.py",
    ]


def test_a_developer_runs_one_end_to_end_test(tmp_path: Path) -> None:
    """One name selects one folder, and an unknown one is refused by name."""
    root = _layer(
        tmp_path,
        {"wired-pair": ["test_wired_pair.py"], "portable-image": ["test_portable_image.py"]},
    )

    assert [path.name for path in runner.select_tests(root, "wired-pair")] == ["test_wired_pair.py"]

    with pytest.raises(runner.RunnerError) as raised:
        runner.select_tests(root, "nonesuch")
    message = str(raised.value)
    assert "nonesuch" in message
    assert "wired-pair" in message
    assert "portable-image" in message


def test_a_run_reads_the_built_layer_rather_than_a_shell_s_checkout() -> None:
    """The artifacts the app names are imported before anything the shell carries.

    `devshells.nix` puts this checkout on `PYTHONPATH` on purpose, so that a
    manual `pytest` reads an edit. A run of the app inherits that value, and the
    checkout shadowed the store copies the app had just built: the run then
    reported on modules it did not build, which reads as a failure of the code
    under test.
    """
    inherited = os.pathsep.join(["/home/someone/nixplan/tests/e2e", "/home/someone/nixplan/cli"])

    path = runner.import_path(Path("/nix/store/aaa-e2e"), "/nix/store/bbb-planner-src", inherited)

    assert path.split(os.pathsep) == [
        "/nix/store/aaa-e2e",
        "/nix/store/bbb-planner-src",
        *inherited.split(os.pathsep),
    ]
    assert runner.import_path(Path("/nix/store/aaa-e2e"), None, "") == "/nix/store/aaa-e2e"


def test_the_host_cannot_provide_what_a_machine_needs() -> None:
    """A device a machine needs and the host has not is named, with the reason.

    The device list is a parameter, so what is asserted is the refusal rather
    than whatever the host running this happens to have. `/dev/null` stands for
    a device that is there. Nothing else about the host is asserted, because
    this file also runs inside a build sandbox.
    """
    reason = "the control channel into each guest is vsock"

    present = runner.host_problems((("/dev/null", reason),))
    assert [line for line in present if "/dev/null" in line] == []

    absent = runner.host_problems((("/dev/nothing-is-here", reason),))
    named = [line for line in absent if "/dev/nothing-is-here" in line]
    assert len(named) == 1
    assert reason in named[0]


ROOT_VALUE = "issuer:vars/root"
TOKEN_VALUE = "issuer:vars/token"
ROOT_NAME = "issuer:root"
TOKEN_NAME = "issuer:token"
ROOT_IDENTITY = "sha256-1111222233334444"
TOKEN_IDENTITY = "sha256-5555666677778888"
GENERATOR = "/nix/store/9dm4x2vqk7z1n5bpr3jlfg8ys6cwh0az-generate-token.drv"

GENERATED_PLAN = {
    ROOT_VALUE: {
        "key": ROOT_IDENTITY,
        "per": "instance",
        "deploy": False,
        "delivery": [],
        "program": GENERATOR,
        "files": {"key": _delivered("/run/vars/issuer/root/key", "secret")},
    },
    TOKEN_VALUE: {
        "key": TOKEN_IDENTITY,
        "per": "instance",
        "deploy": True,
        "delivery": ["alpha", "beta"],
        "reads": [ROOT_VALUE],
        "program": GENERATOR,
        "files": {
            "secret": _delivered("/run/vars/issuer/token/secret", "secret"),
            "fingerprint": _delivered("/run/vars/issuer/token/fingerprint", "public"),
        },
    },
}

CONFIGURATION = {
    "_type": "secrets-configuration",
    "store": {
        ROOT_NAME: {
            "backend": "age",
            "dependencies": [],
            "prompts": {},
            "generate": GENERATOR,
            "files": {"key": {"deploy": False}},
        },
        TOKEN_NAME: {
            "backend": "age",
            "dependencies": [ROOT_NAME],
            "prompts": {},
            "generate": GENERATOR,
            "files": {"secret": {"deploy": True}, "fingerprint": {"deploy": True}},
        },
    },
    "backends": {"prompt": {}, "store": {"age": {}}},
}

NAMES = {ROOT_VALUE: ROOT_NAME, TOKEN_VALUE: TOKEN_NAME}


class Backend:
    """A store backend that answers from a table and records every fetch.

    The real one is a program per command, invoked by exit status. What the
    driver does with a real one is asserted in `tests/e2e/generated-secret`, on
    machines, against bytes a generator minted.
    """

    def __init__(
        self,
        holds: dict[tuple[str, str], str],
        statuses: dict[tuple[str, str], int] | None = None,
    ) -> None:
        self.holds = holds
        self.statuses = statuses or {}
        self.fetched: list[tuple[str, str]] = []

    def status(self, name: str, file: str) -> int:
        if (name, file) in self.statuses:
            return self.statuses[(name, file)]
        return generation.HELD if (name, file) in self.holds else generation.NOT_HELD

    def fetch(self, name: str, file: str) -> str:
        self.fetched.append((name, file))
        return self.holds[(name, file)]


def _values() -> tuple[generation.Value, ...]:
    return generation.values(GENERATED_PLAN, CONFIGURATION, NAMES)


def _everything_held() -> Backend:
    return Backend(
        {
            (ROOT_NAME, "key"): "root-bytes",
            (TOKEN_NAME, "secret"): "secret-bytes",
            (TOKEN_NAME, "fingerprint"): "0f1e2d3c",
        }
    )


def test_an_unreadable_backend_answer_fails_the_run() -> None:
    """`exists` answers 0 or 42. A third status is a backend that failed."""
    values = _values()
    backend = _everything_held()
    backend.statuses[(TOKEN_NAME, "secret")] = 7

    with pytest.raises(generation.GenerationError) as raised:
        generation.state(values, backend)

    message = str(raised.value)
    assert TOKEN_NAME in message
    assert "secret" in message
    assert "7" in message
    assert TOKEN_VALUE in message


def test_a_generator_that_fails_stops_the_run() -> None:
    """A non-zero exit is refused with the value the generator named."""
    failed = subprocess.CompletedProcess(
        args=["nixos-secrets", "generate"],
        returncode=1,
        stdout=f"Generating '{TOKEN_NAME}'\n",
        stderr=f"Error generating '{TOKEN_NAME}': exit 1\n",
    )

    assert generation.failed_value(failed.stdout + failed.stderr) == TOKEN_NAME

    with pytest.raises(generation.GenerationError) as raised:
        generation.require_success(failed, what="generation")
    assert TOKEN_NAME in str(raised.value)

    timed_out = subprocess.CompletedProcess(
        args=["nixos-secrets", "generate"],
        returncode=1,
        stdout="",
        stderr=f"Generator '{ROOT_NAME}' timed out\n",
    )
    with pytest.raises(generation.GenerationError) as raised:
        generation.require_success(timed_out, what="generation")
    assert ROOT_NAME in str(raised.value)


def test_a_generator_that_produced_nothing_stops_the_run() -> None:
    """Success and an empty store is a refusal naming the value and its files."""
    values = _values()
    backend = Backend({(ROOT_NAME, "key"): "root-bytes"})
    built = generation.state(values, backend)

    assert built[TOKEN_VALUE]["secret"] == {"present": False}

    with pytest.raises(generation.GenerationError) as raised:
        generation.require_generated(values, built)

    message = str(raised.value)
    assert TOKEN_NAME in message
    assert "secret" in message
    assert "fingerprint" in message
    assert ROOT_NAME not in message


def test_a_regenerated_dependency_leaves_its_consumer_stale() -> None:
    """The identity compared is the plan key over the declaration, both named."""
    values = _values()
    built = generation.state(values, _everything_held())

    current = generation.identities(values)
    assert current == {ROOT_NAME: ROOT_IDENTITY, TOKEN_NAME: TOKEN_IDENTITY}
    generation.require_provenance(values, built, current)

    stale = dict(current)
    stale[TOKEN_NAME] = "sha256-0000000000000000"
    with pytest.raises(generation.GenerationError) as raised:
        generation.require_provenance(values, built, stale)

    message = str(raised.value)
    assert TOKEN_NAME in message
    assert "sha256-0000000000000000" in message
    assert TOKEN_IDENTITY in message
    assert f"nixos-secrets generate -g {TOKEN_NAME}" in message
    # The dependency was regenerated and agrees, so it is not what is named.
    assert ROOT_NAME not in message.replace(TOKEN_NAME, "")


def test_a_stored_value_of_unknown_provenance_is_refused() -> None:
    """No record is a disagreement, and a value the backend holds none of is not."""
    values = _values()
    built = generation.state(values, _everything_held())

    with pytest.raises(generation.GenerationError) as raised:
        generation.require_provenance(values, built, {})
    assert "a declaration nothing recorded" in str(raised.value)

    ungenerated = generation.state(values, Backend({}))
    assert generation.held(values, ungenerated) == ()
    generation.require_provenance(values, ungenerated, {})


def test_a_guard_compares_a_record_with_the_values_that_wrote_it(tmp_path: Path) -> None:
    """A record the run wrote from the declarations it then compares is not a guard.

    `write_provenance` records the identity of every declaration handed to it,
    so a comparison against it agrees whatever the backend holds. What can
    disagree is a record an earlier run left behind, which is why the folder
    reads the record before it generates anything and writes it afterwards.
    """
    values = _values()
    built = generation.state(values, _everything_held())
    record = tmp_path / generation.PROVENANCE_FILE

    generation.write_provenance(record, values)
    generation.require_provenance(values, built, generation.read_provenance(record))

    earlier = generation.identities(values)
    earlier[TOKEN_NAME] = "sha256-0000000000000000"
    record.write_text(json.dumps(earlier))
    with pytest.raises(generation.GenerationError):
        generation.require_provenance(values, built, generation.read_provenance(record))

    folder = (Path(__file__).parent / "generated-secret" / "test_generated_secret.py").read_text()
    assert folder.index("read_provenance") < folder.index("write_provenance")


def test_the_tool_cannot_be_resolved() -> None:
    """The refusal names the variable and the reference that resolved to nothing."""
    reference = "/nix/store/there-is-no-such-flake-here"

    with pytest.raises(generation.GenerationError) as raised:
        generation.tool(reference)

    message = str(raised.value)
    assert generation.FLAKE_VARIABLE in message
    assert reference in message


def _tool_tree(root: Path, schema: str) -> Path:
    """Write a store-path-shaped tool holding one schema file."""
    into = root / "lib" / "python3.14" / "site-packages" / "nixos_secrets"
    into.mkdir(parents=True)
    (into / "secrets-config.schema.json").write_text(schema)
    return root


def test_the_external_contract_has_changed(tmp_path: Path) -> None:
    """A differing schema fails naming the reading, the revision and the file."""
    moved = generation.contract_refusal(_tool_tree(tmp_path / "moved", '{"title": "Something"}'))

    assert moved is not None
    assert generation.READING in moved
    assert generation.CONTRACT_REVISION in moved
    assert generation.CONTRACT_FILE in moved
    assert generation.CONTRACT_DIGEST in moved


def test_the_external_contract_cannot_be_read(tmp_path: Path) -> None:
    """An unreadable signal is not evidence the contract moved, so it passes."""
    assert generation.contract_refusal(None) is None
    # Resolved to nothing, and resolved to something carrying no contract: the
    # run that needed the tool skips, and this check has nothing to compare.
    assert generation.contract_refusal(tmp_path / "nothing-was-resolved") is None
    (tmp_path / "no-schema").mkdir()
    assert generation.contract_refusal(tmp_path / "no-schema") is None


def _record(root: Path, record: dict[str, Any]) -> Path:
    """Write a deployment record verbatim, for the reading to accept or refuse."""
    root.mkdir(parents=True, exist_ok=True)
    (root / "plan.json").write_text(json.dumps(PLAN))
    (root / "manifest.json").write_text(json.dumps(record))
    return root


def test_a_record_states_a_version_the_command_does_not_implement(tmp_path: Path) -> None:
    """A record of another shape is refused before any entry of it is interpreted."""
    shape = {"storeDir": manifest.store_dir(), "entries": {}, "realisers": REALISERS}
    root = _record(tmp_path, {"version": 1, **shape})
    recorder = Recorder()

    with pytest.raises(errors.ApplyError) as raised:
        apply.apply(manifest.read(root), recorder, base_env={})

    message = str(raised.value)
    assert "version 1" in message
    assert f"version {manifest.VERSION}" in message
    assert recorder.commands == []


def test_a_record_names_a_store_the_command_does_not_run_against(tmp_path: Path) -> None:
    """Artifact paths of another store are paths this command cannot copy."""
    shape = {"version": manifest.VERSION, "entries": {}, "realisers": REALISERS}
    root = _record(tmp_path, {**shape, "storeDir": "/gnu/store"})
    recorder = Recorder()

    with pytest.raises(errors.ApplyError) as raised:
        apply.apply(manifest.read(root), recorder, base_env={})

    message = str(raised.value)
    assert "/gnu/store" in message
    assert manifest.store_dir() in message
    assert recorder.commands == []


def test_a_record_carries_no_table_of_entries(tmp_path: Path) -> None:
    """A misspelled table is a record to refuse, never a deployment placing nothing."""
    shape = {
        "version": manifest.VERSION,
        "storeDir": manifest.store_dir(),
        "values": {},
        "realisers": REALISERS,
        "machines": {},
    }
    misspelled = _record(tmp_path / "misspelled", {**shape, "entires": {}})

    with pytest.raises(errors.ApplyError) as raised:
        manifest.read(misspelled)

    message = str(raised.value)
    assert str(misspelled / manifest.MANIFEST) in message
    assert "entries" in message

    empty = manifest.read(_record(tmp_path / "empty", {**shape, "entries": {}}))
    assert empty.entries == {}


def test_a_record_carries_no_table_of_realisers(tmp_path: Path) -> None:
    """What a realiser realises and what names its holdings are read out of the record."""
    shape = {
        "version": manifest.VERSION,
        "storeDir": manifest.store_dir(),
        "entries": {},
        "machines": {},
    }
    root = _record(tmp_path, shape)

    with pytest.raises(errors.ApplyError) as raised:
        manifest.read(root)

    assert "realisers" in str(raised.value)

    published = manifest.read(_record(tmp_path / "published", {**shape, "realisers": REALISERS}))
    assert {name: record.scopes for name, record in published.realisers.items()} == {
        "flakelet": ("system",),
        "image": ("system", "user"),
    }
    assert published.realisers["flakelet"].text(remote.URL_PREFIX) == URL_PREFIX
    assert published.realisers["image"].number(remote.LENGTH) == DIGEST_LENGTH


def test_a_record_carrying_an_entry_with_no_address_is_read(tmp_path: Path) -> None:
    """A machine that declares no address is a warning, so the absence is carried."""
    stated = _stated(SERVER_KEY, "alpha", "10.0.0.10")
    deployment = _built(tmp_path, plan=PLAN, entries={SERVER_KEY: {**stated, "address": None}})
    recorder = Recorder()

    assert deployment.entries[SERVER_KEY].address is None

    with pytest.raises(errors.ApplyError) as raised:
        apply.apply(deployment, recorder, base_env={})

    message = str(raised.value)
    assert SERVER_KEY in message
    assert "alpha" in message
    assert recorder.commands == []


def test_a_target_that_was_collected_is_named_as_collected(
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    """A path a collector removed is a build that is gone, not a reference that fails."""

    def dialled(*args: object, **kwargs: object) -> NoReturn:
        raise AssertionError("nix was asked to build a path that is not there")

    monkeypatch.setattr(subprocess, "run", dialled)
    collected = f"{manifest.store_dir()}/3k9m2x7vqz1n5bpr4jlfg8ys6cwh0d2a-deployment"

    with pytest.raises(errors.ApplyError) as raised:
        manifest.resolve(collected)

    message = str(raised.value)
    assert collected in message
    assert "collected" in message
    assert "don't know how to build" not in message


def test_a_file_outside_every_values_own_directory_is_left_alone(tmp_path: Path) -> None:
    """Bytes under no value's directory are a claim about no value, so nothing measures them."""
    deployment = _built(
        tmp_path / "built",
        plan=PLAN,
        entries={SERVER_KEY: _stated(SERVER_KEY, "alpha", "10.0.0.10")},
        values={SESSION_VALUE: {"delivery": ["alpha"], "files": TOKEN}},
    )
    source = _source(
        tmp_path / "values",
        {
            f"{SESSION_VALUE}/token": "s3cret",
            "README": "the bytes of this deployment's values",
            ".gitignore": "*\n",
        },
    )
    recorder = Recorder()

    log = apply.apply(deployment, recorder, source=source, base_env={})

    assert [line for line in log if line.startswith("value ")] == [
        f"value {SESSION_VALUE} token -> root@10.0.0.10:/run/vars/issuer/session/token"
        f" (root:root 0400)"
    ]
    assert "README" not in " ".join(" ".join(command) for command in recorder.commands)


def test_two_undeclared_files_are_both_named(tmp_path: Path) -> None:
    """An operator fixing a source wants the list, not the first line of it."""
    deployment = _built(
        tmp_path / "built",
        plan=PLAN,
        entries={SERVER_KEY: _stated(SERVER_KEY, "alpha", "10.0.0.10")},
        values={SESSION_VALUE: {"delivery": ["alpha"], "files": TOKEN}},
    )
    source = _source(
        tmp_path / "values",
        {
            f"{SESSION_VALUE}/token": "s3cret",
            f"{SESSION_VALUE}/toekn": "misspelled",
            f"{SESSION_VALUE}/spare": "unnamed",
        },
    )
    recorder = Recorder()

    with pytest.raises(errors.ApplyError) as raised:
        apply.apply(deployment, recorder, source=source, base_env={})

    message = str(raised.value)
    assert f"{SESSION_VALUE}/toekn" in message
    assert f"{SESSION_VALUE}/spare" in message
    assert recorder.commands == []


RELAY_KEY = "probe:relay@alpha"


def test_an_entry_off_the_cycle_keeps_its_order(tmp_path: Path) -> None:
    """A read into a mutual pair is satisfied, and only the pair's own edge is contradicted."""
    plan = {
        **PLAN,
        CLIENT_KEY: {"reads": {"relay": {"entry": RELAY_KEY}}},
        RELAY_KEY: {"reads": {"site": {"entry": SERVER_KEY}}},
        SERVER_KEY: {"reads": {"relay": {"entry": RELAY_KEY}}},
    }
    deployment = _built(
        tmp_path,
        plan=plan,
        entries={
            CLIENT_KEY: _stated(CLIENT_KEY, "beta", "10.0.0.11"),
            RELAY_KEY: _stated(RELAY_KEY, "alpha", "10.0.0.10"),
            SERVER_KEY: _stated(SERVER_KEY, "alpha", "10.0.0.10"),
        },
    )

    log = apply.apply(deployment, Recorder(), base_env={})

    assert _activated(log) == [RELAY_KEY, SERVER_KEY, CLIENT_KEY]
    against = [line for line in log if line.startswith("ordered against ")]
    assert against == [f"ordered against the read of {SERVER_KEY} by {RELAY_KEY}"]


def _cycles(log: tuple[str, ...]) -> list[str]:
    """Return the cycle lines the log shows, in the order it shows them."""
    return [line for line in log if line.startswith("cycle of ")]


def _against(log: tuple[str, ...]) -> list[str]:
    """Return the contradicted-edge lines the log shows, in the order it shows them."""
    return [line for line in log if line.startswith("ordered against ")]


def test_two_entries_that_read_each_other_are_named_as_one_cycle(tmp_path: Path) -> None:
    """The pair is named as a cycle above the edge the order contradicted, and both are applied."""
    plan = {
        **PLAN,
        SERVER_KEY: {"reads": {"back": {"entry": CLIENT_KEY}}},
        CLIENT_KEY: {"reads": {"site": {"entry": SERVER_KEY}}},
    }
    deployment = _built(
        tmp_path,
        plan=plan,
        entries={
            SERVER_KEY: _stated(SERVER_KEY, "alpha", "10.0.0.10"),
            CLIENT_KEY: _stated(CLIENT_KEY, "beta", "10.0.0.11"),
        },
    )

    log = apply.apply(deployment, Recorder(), base_env={})

    assert _cycles(log) == [f"cycle of {CLIENT_KEY}, {SERVER_KEY}"]
    assert _against(log) == [f"ordered against the read of {SERVER_KEY} by {CLIENT_KEY}"]
    assert log.index(_cycles(log)[0]) < log.index(_against(log)[0])
    assert sorted(_activated(log)) == [CLIENT_KEY, SERVER_KEY]


def test_an_entry_reading_into_a_cycle_is_not_contradicted(tmp_path: Path) -> None:
    """The third entry is named in no cycle, and the read it declared is honoured."""
    plan = {
        **PLAN,
        CLIENT_KEY: {"reads": {"relay": {"entry": RELAY_KEY}}},
        RELAY_KEY: {"reads": {"site": {"entry": SERVER_KEY}}},
        SERVER_KEY: {"reads": {"relay": {"entry": RELAY_KEY}}},
    }
    deployment = _built(
        tmp_path,
        plan=plan,
        entries={
            CLIENT_KEY: _stated(CLIENT_KEY, "beta", "10.0.0.11"),
            RELAY_KEY: _stated(RELAY_KEY, "alpha", "10.0.0.10"),
            SERVER_KEY: _stated(SERVER_KEY, "alpha", "10.0.0.10"),
        },
    )

    log = apply.apply(deployment, Recorder(), base_env={})

    assert _cycles(log) == [f"cycle of {RELAY_KEY}, {SERVER_KEY}"]
    assert CLIENT_KEY not in _cycles(log)[0]
    assert _against(log) == [f"ordered against the read of {SERVER_KEY} by {RELAY_KEY}"]
    activated = _activated(log)
    assert activated.index(RELAY_KEY) < activated.index(CLIENT_KEY)


def test_two_separate_cycles_are_two_reports(tmp_path: Path) -> None:
    """Two disjoint mutual pairs are two cycles, each naming its own two entries."""
    plan = {
        **PLAN,
        SERVER_KEY: {"reads": {"back": {"entry": CLIENT_KEY}}},
        CLIENT_KEY: {"reads": {"site": {"entry": SERVER_KEY}}},
        HUB_KEY: {"reads": {"relay": {"entry": RELAY_KEY}}},
        RELAY_KEY: {"reads": {"hub": {"entry": HUB_KEY}}},
    }
    deployment = _built(
        tmp_path,
        plan=plan,
        entries={
            SERVER_KEY: _stated(SERVER_KEY, "alpha", "10.0.0.10"),
            CLIENT_KEY: _stated(CLIENT_KEY, "beta", "10.0.0.11"),
            HUB_KEY: _stated(HUB_KEY, "alpha", "10.0.0.10"),
            RELAY_KEY: _stated(RELAY_KEY, "alpha", "10.0.0.10"),
        },
    )

    log = apply.apply(deployment, Recorder(), base_env={})

    assert _cycles(log) == [
        f"cycle of {HUB_KEY}, {RELAY_KEY}",
        f"cycle of {CLIENT_KEY}, {SERVER_KEY}",
    ]
    assert _against(log) == [
        f"ordered against the read of {RELAY_KEY} by {HUB_KEY}",
        f"ordered against the read of {SERVER_KEY} by {CLIENT_KEY}",
    ]
    assert sorted(_activated(log)) == sorted([CLIENT_KEY, HUB_KEY, RELAY_KEY, SERVER_KEY])


class Counted(str):
    """A plan key that counts every lookup the walk makes of it."""

    lookups = 0

    def __hash__(self) -> int:
        Counted.lookups += 1
        return str.__hash__(self)


CHAIN = 1000

# Lookups per entry, not seconds: a wall-clock bound in this suite would be flaky
# by construction. The component walk asks 27 per entry of the chain below; the
# frontier rescan it replaced asked 1510, because it looked every remaining entry
# up once per entry applied.
BUDGET = 300


def _chain(size: int, *, mutual: bool = False) -> tuple[dict[str, Any], list[Counted]]:
    """Return a plan whose reads form a chain of ``size`` entries, and those entries."""
    keys = [Counted(f"fleet:node{index:04d}@m{index:04d}") for index in range(size)]
    plan: dict[str, Any] = {
        keys[index]: {"reads": {"up": {"entry": keys[index - 1]}}} for index in range(1, size)
    }
    if mutual:
        plan[keys[0]] = {"reads": {"down": {"entry": keys[1]}}}
    return plan, keys


def _measured(plan: dict[str, Any], keys: list[Counted]) -> tuple[order.WalkResult, int]:
    """Walk ``keys`` and return the result beside the lookups the walk made."""
    Counted.lookups = 0
    walked = order.walk(plan, keys)
    return walked, Counted.lookups


def test_a_large_deployment_is_ordered_without_a_per_entry_rescan() -> None:
    """A thousand-entry chain is ordered at a cost bounded per entry rather than by the fleet."""
    plan, keys = _chain(CHAIN)

    walked, lookups = _measured(plan, keys)

    assert list(walked.order) == keys
    assert walked.broken == ()
    assert lookups < BUDGET * CHAIN


def test_a_large_deployment_carrying_a_cycle_is_ordered_at_the_same_cost() -> None:
    """One mutual pair in the same chain costs the same order and reports its own edge."""
    _, acyclic = _measured(*_chain(CHAIN))
    plan, keys = _chain(CHAIN, mutual=True)

    walked, lookups = _measured(plan, keys)

    assert list(walked.order) == keys
    assert walked.cycles == ((keys[0], keys[1]),)
    assert walked.broken == ((keys[1], keys[0]),)
    assert lookups < 2 * acyclic


def test_no_entry_can_be_ordered(tmp_path: Path, monkeypatch: pytest.MonkeyPatch) -> None:
    """An unorderable state is the command's own refusal, and it dials nothing.

    A condensation is acyclic, so no component computation over a plan reaches
    the position. The fault is injected where a future edge source would sit: a
    mutual pair is handed over as two components, which is a condensation that
    reads itself.
    """
    plan = {
        **PLAN,
        SERVER_KEY: {"reads": {"back": {"entry": CLIENT_KEY}}},
        CLIENT_KEY: {"reads": {"site": {"entry": SERVER_KEY}}},
    }
    deployment = _built(
        tmp_path,
        plan=plan,
        entries={
            SERVER_KEY: _stated(SERVER_KEY, "alpha", "10.0.0.10"),
            CLIENT_KEY: _stated(CLIENT_KEY, "beta", "10.0.0.11"),
        },
    )
    recorder = Recorder()
    monkeypatch.setattr(
        order, "_components", lambda nodes, forward: tuple((node,) for node in nodes)
    )

    with pytest.raises(errors.ApplyError) as raised:
        apply.apply(deployment, recorder, base_env={})

    message = str(raised.value)
    assert SERVER_KEY in message
    assert CLIENT_KEY in message
    assert f"{CLIENT_KEY} reads {SERVER_KEY}" in message
    assert recorder.commands == []


def test_a_restricted_run_activates_a_consumer_without_its_provider(tmp_path: Path) -> None:
    """The read the selection drops is announced before the first dial, and the consumer runs."""
    plan = {**PLAN, CLIENT_KEY: {"reads": {"site": {"entry": SERVER_KEY}}}}
    deployment = _built(
        tmp_path,
        plan=plan,
        entries={
            CLIENT_KEY: _stated(CLIENT_KEY, "beta", "10.0.0.11"),
            SERVER_KEY: _stated(SERVER_KEY, "alpha", "10.0.0.10"),
        },
    )
    recorder = Recorder()

    log = apply.apply(deployment, recorder, only=(CLIENT_KEY,), base_env={})

    assert log[0] == f"not applying {SERVER_KEY}, which {CLIENT_KEY} reads"
    assert _activated(log) == [CLIENT_KEY]
    assert all("10.0.0.10" not in " ".join(command) for command in recorder.commands)


def test_a_full_run_announces_nothing_about_unapplied_providers(tmp_path: Path) -> None:
    """A whole-deployment run reports the edges a cycle contradicted and no other read."""
    plan = {
        **PLAN,
        SERVER_KEY: {"reads": {"back": {"entry": CLIENT_KEY}}},
        CLIENT_KEY: {"reads": {"site": {"entry": SERVER_KEY}}},
    }
    deployment = _built(
        tmp_path,
        plan=plan,
        entries={
            SERVER_KEY: _stated(SERVER_KEY, "alpha", "10.0.0.10"),
            CLIENT_KEY: _stated(CLIENT_KEY, "beta", "10.0.0.11"),
        },
    )

    log = apply.apply(deployment, Recorder(), base_env={})

    assert [line for line in log if line.startswith("not applying ")] == []
    assert _against(log) == [f"ordered against the read of {SERVER_KEY} by {CLIENT_KEY}"]


def test_an_unreachable_machine_is_refused_without_a_prompt(tmp_path: Path) -> None:
    """Silence is bounded and the caller's own value for an option is the one used."""
    deployment = _built(
        tmp_path,
        plan=PLAN,
        entries={SERVER_KEY: _stated(SERVER_KEY, "alpha", "10.0.0.10")},
    )
    recorder = Recorder()

    apply.apply(deployment, recorder, base_env={"NIX_SSHOPTS": "-o ConnectTimeout=1"}, log=print)

    activation = recorder.commands[-1]
    assert "BatchMode=yes" in activation
    assert "ServerAliveInterval=30" in activation
    assert "ServerAliveCountMax=3" in activation
    assert activation.index("ConnectTimeout=1") < activation.index("ConnectTimeout=10")


REFUSED = "No space left on device"


class Failing(Recorder):
    """A recorder whose machine refuses every step whose argv holds ``at``.

    The question of what the machine holds is answered rather than refused: it
    is not a step, it is asked of every machine before the first one, and what
    this recorder is for is a step a machine refuses.
    """

    def __init__(self, at: str) -> None:
        super().__init__()
        self.at = at

    def run(
        self, cmd: list[str], *, env: dict[str, str] | None = None, stdin: bytes | None = None
    ) -> object:
        self._refuse(cmd)
        return super().run(cmd, env=env, stdin=stdin)

    def output(
        self, cmd: list[str], *, env: dict[str, str] | None = None, stdin: bytes | None = None
    ) -> str:
        self._refuse(cmd)
        return super().output(cmd, env=env, stdin=stdin)

    def _refuse(self, cmd: list[str]) -> None:
        if self.at in " ".join(cmd) and not _asked_what_it_holds(cmd):
            raise subprocess.CalledProcessError(1, cmd, output="", stderr=f"{REFUSED}\n")


def test_a_step_that_fails_names_the_machine_and_what_it_said(
    tmp_path: Path,
    capsys: pytest.CaptureFixture[str],
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    """A machine's refusal is the command's own, and no traceback reaches the operator."""
    root = tmp_path / "built"
    _built(root, plan=PLAN, entries={SERVER_KEY: _stated(SERVER_KEY, "alpha", "10.0.0.10")})
    failing = Failing("10.0.0.10")
    monkeypatch.setattr(remote, "Subprocess", lambda: failing)

    assert planner.main(["apply", str(root)]) == 1

    refusal = capsys.readouterr().err
    assert SERVER_KEY in refusal
    assert "10.0.0.10" in refusal
    assert REFUSED in refusal
    assert "Traceback" not in refusal


def _broken(tmp_path: Path) -> tuple[manifest.Deployment, Failing, list[str]]:
    """Apply a two-entry deployment whose second entry's machine refuses the copy."""
    deployment = _built(
        tmp_path,
        plan={**PLAN, CLIENT_KEY: {"reads": {"site": {"entry": SERVER_KEY}}}},
        entries={
            CLIENT_KEY: _stated(CLIENT_KEY, "beta", "10.0.0.11"),
            SERVER_KEY: _stated(SERVER_KEY, "alpha", "10.0.0.10"),
        },
    )
    failing = Failing("10.0.0.11")
    log: list[str] = []

    with pytest.raises(errors.ApplyError):
        apply.apply(deployment, failing, base_env={}, log=log.append)

    return deployment, failing, log


def test_a_step_is_announced_before_it_is_attempted(tmp_path: Path) -> None:
    """The step line of a step that never completed is the run's own last word about it."""
    deployment, _, log = _broken(tmp_path)

    steps = [line for line in log if not line.startswith(("  ", "failed "))]
    assert steps[-1] == f"copy {CLIENT_KEY} {deployment.entries[CLIENT_KEY].path} -> root@10.0.0.11"
    assert log[-1].startswith("failed ")
    assert "10.0.0.11" in log[-1]
    assert REFUSED in log[-1]


def test_the_run_stops_at_the_step_that_broke(tmp_path: Path) -> None:
    """One boundary, not a set of them: nothing after the refused step is attempted."""
    _, failing, log = _broken(tmp_path)

    assert _activated(tuple(log)) == [SERVER_KEY]
    steps = [command for command in failing.commands if not _asked_what_it_holds(command)]
    assert [command[:2] for command in steps] == [["nix", "copy"], ["ssh", "-o"]]
    # Every machine is asked what it holds before the first step, so the only
    # thing addressed to the second machine is that question.
    assert all("10.0.0.11" not in " ".join(command) for command in steps)
    asked = [command for command in failing.commands if _asked_what_it_holds(command)]
    assert [command[-2] for command in asked] == ["root@10.0.0.10", "root@10.0.0.11"]


def test_a_step_the_machine_refuses_is_named_by_the_run_that_took_it(tmp_path: Path) -> None:
    """Every subcommand announces its step first, the rollback path included."""
    deployment = _built(
        tmp_path,
        plan=PLAN,
        entries={SERVER_KEY: _stated(SERVER_KEY, "alpha", "10.0.0.10")},
    )
    printed: list[str] = []

    with pytest.raises(errors.ApplyError) as raised:
        report.rollback(deployment, Failing("10.0.0.10"), SERVER_KEY, log=printed.append)

    assert printed[0] == f"rollback {SERVER_KEY} on root@10.0.0.10"
    assert printed[-1].startswith("failed ")
    assert "10.0.0.10" in str(raised.value)
    assert REFUSED in str(raised.value)
    assert "Traceback" not in str(raised.value)


def _restricted(tmp_path: Path, only: tuple[str, ...]) -> Recorder:
    """Apply a two-machine deployment restricted to ``only`` and return the recorder."""
    deployment = _built(
        tmp_path,
        plan=PLAN,
        entries={
            CLIENT_KEY: _stated(CLIENT_KEY, "beta", "10.0.0.11"),
            SERVER_KEY: _stated(SERVER_KEY, "alpha", "10.0.0.10"),
        },
        values={SESSION_VALUE: {"delivery": ["alpha", "beta"], "files": TOKEN}},
    )
    recorder = Recorder()
    source = _source(tmp_path / "values", {f"{SESSION_VALUE}/token": "s3cret"})

    apply.apply(deployment, recorder, source=source, only=only, base_env={})

    return recorder


def test_a_restricted_run_contacts_only_the_machines_of_the_entries_it_applies(
    tmp_path: Path,
) -> None:
    """A machine that receives a value only because an unselected entry reads it is left alone."""
    recorder = _restricted(tmp_path, (SERVER_KEY,))

    dialled = " ".join(" ".join(command) for command in recorder.commands)
    assert "10.0.0.10" in dialled
    assert "10.0.0.11" not in dialled


def test_a_restriction_that_names_a_value_entry_reaches_its_delivery_set(tmp_path: Path) -> None:
    """A value named directly is written to every machine that receives it, and nothing runs."""
    recorder = _restricted(tmp_path, (SESSION_VALUE,))

    dialled = [" ".join(command) for command in recorder.commands]
    assert len(dialled) == 2
    assert any("10.0.0.10" in command for command in dialled)
    assert any("10.0.0.11" in command for command in dialled)
    assert all("flakelet activate" not in command for command in dialled)


class Answering(Recorder):
    """A recorder whose machine answers ``said`` to the script naming ``asked``.

    The question of what it holds is answered with nothing whatever ``asked``
    names, so a machine asked about one entry does not answer that question
    with an endpoint record of every entry it holds.
    """

    def __init__(self, asked: str, said: str) -> None:
        super().__init__()
        self.asked = asked
        self.said = said

    def output(
        self, cmd: list[str], *, env: dict[str, str] | None = None, stdin: bytes | None = None
    ) -> str:
        answered = super().output(cmd, env=env, stdin=stdin)
        if _asked_what_it_holds(cmd) or self.asked not in " ".join(cmd):
            return answered
        return self.said


def test_an_artifact_the_run_needs_later_is_missing(tmp_path: Path) -> None:
    """An artifact the second machine needs is resolved before the first is dialled."""
    deployment = _built(
        tmp_path,
        plan=PLAN,
        entries={
            CLIENT_KEY: _stated(CLIENT_KEY, "beta", "10.0.0.11"),
            SERVER_KEY: {**_stated(SERVER_KEY, "alpha", "10.0.0.10"), "realiser": "image"},
        },
    )
    artifact = manifest.artifact_of(deployment.entries[SERVER_KEY])
    (artifact / "attachment.json").write_text(json.dumps({}))
    recorder = Recorder()

    with pytest.raises(errors.ApplyError) as raised:
        apply.apply(deployment, recorder, base_env={})

    assert SERVER_KEY in str(raised.value)
    assert "names no image" in str(raised.value)
    assert recorder.commands == []


def test_a_file_inside_the_build_is_malformed(tmp_path: Path) -> None:
    """A file the command reads is refused by name, never as the reader's own error."""
    root = tmp_path / "built"
    _built(root, plan=PLAN, entries={SERVER_KEY: _stated(SERVER_KEY, "alpha", "10.0.0.10")})
    (root / "diagnostics.json").write_text("{not json at all")

    with pytest.raises(errors.ApplyError) as raised:
        manifest.read(root)

    message = str(raised.value)
    assert str(root / "diagnostics.json") in message
    assert "not readable as JSON" in message


def test_a_file_inside_the_build_is_not_text(tmp_path: Path) -> None:
    """Bytes that decode as nothing are the same refusal as bytes that parse as nothing.

    `UnicodeDecodeError` is a `ValueError` and not a `JSONDecodeError`, so a
    reader that names only the latter lets the former out as a traceback.
    """
    root = tmp_path / "built"
    _built(root, plan=PLAN, entries={SERVER_KEY: _stated(SERVER_KEY, "alpha", "10.0.0.10")})

    for name, said in (("diagnostics.json", "not readable as JSON"), ("diagnostics.txt", "text")):
        (root / name).write_bytes(b"\xff\xfe[]")

        with pytest.raises(errors.ApplyError) as raised:
            manifest.read(root)

        assert str(root / name) in str(raised.value)
        assert said in str(raised.value)
        (root / name).unlink()


def test_an_entry_records_a_path_that_names_nothing(tmp_path: Path) -> None:
    """An empty path is not the build root: absence is an omitted key, never a name."""
    root = tmp_path / "built"
    _built(root, plan=PLAN, entries={SERVER_KEY: {**_stated(SERVER_KEY, "alpha", "10.0.0.10")}})
    record = json.loads((root / "manifest.json").read_text())
    record["entries"][SERVER_KEY]["path"] = ""
    (root / "manifest.json").write_text(json.dumps(record))

    with pytest.raises(errors.ApplyError) as raised:
        manifest.read(root)

    assert SERVER_KEY in str(raised.value)
    assert "records path as ''" in str(raised.value)


def _publishes_only(tmp_path: Path) -> manifest.Deployment:
    """A deployment placing one entry that publishes an export and runs nothing."""
    stated = _stated(CLIENT_KEY, "beta", "10.0.0.11")
    del stated["path"]
    return _built(
        tmp_path,
        plan=PLAN,
        entries={
            CLIENT_KEY: {**stated, "units": []},
            SERVER_KEY: _stated(SERVER_KEY, "alpha", "10.0.0.10"),
        },
    )


def test_an_entry_declares_no_unit(tmp_path: Path) -> None:
    """The record of an entry realised into nothing is one every command reads."""
    deployment = _publishes_only(tmp_path)
    recorder = Recorder()

    assert deployment.entries[CLIENT_KEY].path is None
    assert any(CLIENT_KEY in line for line in report.describe(deployment))

    log = apply.apply(deployment, recorder, base_env={})

    # The entry that realises nothing takes no step, and the one beside it is applied.
    assert _activated(log) == [SERVER_KEY]
    assert all("10.0.0.11" not in " ".join(command) for command in recorder.commands)

    answered = report.status(deployment, Recorder())
    assert answered.unasked == ()
    nothing = f"{CLIENT_KEY} flakelet realises nothing"
    assert any(line.startswith(nothing) for line in answered.lines)


def test_a_command_needs_the_artifact_an_entry_does_not_have(tmp_path: Path) -> None:
    """A step that wants the artifact refuses naming that entry and no other.

    The refusal is the command's own and is made before the step is announced,
    so no line presents a local read of the build as a machine's answer.
    """
    deployment = _publishes_only(tmp_path)
    recorder = Recorder()
    printed: list[str] = []

    with pytest.raises(errors.ApplyError) as raised:
        report.rollback(deployment, recorder, CLIENT_KEY, log=printed.append)

    message = str(raised.value)
    assert CLIENT_KEY in message
    assert "declares no unit" in message
    assert SERVER_KEY not in message
    assert recorder.commands == []
    assert printed == []
    assert "10.0.0.11" not in message


def test_an_entry_the_endpoint_recorded_a_failure_for_is_not_reported_as_healthy(
    tmp_path: Path,
) -> None:
    """The line is the endpoint's whole record, so an error it holds is in it."""
    deployment = _built(
        tmp_path,
        plan=PLAN,
        entries={SERVER_KEY: _stated(SERVER_KEY, "alpha", "10.0.0.10")},
    )
    entry = deployment.entries[SERVER_KEY]
    failed = "unit site-server-serve.service failed to start"
    answering = Answering(
        "flakelet status", _endpoint(entry, _ran(entry), generation=2, last_error=failed)
    )

    reported = report.status(deployment, answering, base_env={})

    assert reported.lines == (
        f"{SERVER_KEY} flakelet generation 2 of plan:{SERVER_KEY} runs this build's units, "
        f"last error {failed}",
    )
    assert reported.unasked == ()


class Silent(Recorder):
    """A recorder whose machines exit ``status`` with ``said`` for the machine in ``at``."""

    def __init__(self, at: str, status: int, said: str) -> None:
        super().__init__()
        self.at = at
        self.status = status
        self.said = said

    def output(
        self, cmd: list[str], *, env: dict[str, str] | None = None, stdin: bytes | None = None
    ) -> str:
        answered = super().output(cmd, env=env, stdin=stdin)
        if self.at in " ".join(cmd):
            raise subprocess.CalledProcessError(self.status, cmd, output="", stderr=self.said)
        return answered


def _asked(tmp_path: Path, runner: Recorder, **stated: object) -> report.Report:
    """Ask about a two-machine deployment, with ``stated`` overriding one entry's record."""
    deployment = _built(
        tmp_path,
        plan=PLAN,
        entries={
            CLIENT_KEY: {**_stated(CLIENT_KEY, "beta", "10.0.0.11"), **stated},
            SERVER_KEY: _stated(SERVER_KEY, "alpha", "10.0.0.10"),
        },
    )
    return report.status(deployment, runner, base_env={})


def test_a_machine_with_no_endpoint_is_not_reported_as_absent(tmp_path: Path) -> None:
    """An endpoint that cannot be run is a machine to install, not a deployment to apply."""
    reported = _asked(tmp_path, Silent("10.0.0.11", 127, "flakelet: command not found\n"))

    line = [text for text in reported.lines if text.startswith(CLIENT_KEY)]
    assert line == [f"{CLIENT_KEY} flakelet no endpoint on beta: flakelet: command not found"]
    assert reported.unasked == ("beta",)


def test_a_machine_that_cannot_be_reached_is_reported_as_unreachable(tmp_path: Path) -> None:
    """ssh exits 255 for a machine that answered nothing, and nothing is claimed about it."""
    reported = _asked(tmp_path, Silent("10.0.0.11", 255, "ssh: connect to host: timed out\n"))

    line = [text for text in reported.lines if text.startswith(CLIENT_KEY)]
    assert line == [f"{CLIENT_KEY} flakelet unreachable: beta at 10.0.0.11 answered nothing"]
    assert reported.unasked == ("beta",)


def test_an_entry_whose_machine_records_no_address_is_not_dialled(tmp_path: Path) -> None:
    """A machine with no address is not dialled and is not reported unreachable either."""
    recorder = Recorder()

    reported = _asked(tmp_path, recorder, address=None)

    line = [text for text in reported.lines if text.startswith(CLIENT_KEY)]
    assert line == [f"{CLIENT_KEY} flakelet not dialled: machine beta declares no address"]
    assert all("10.0.0.11" not in " ".join(command) for command in recorder.commands)


def test_one_unreachable_machine_does_not_hide_the_others(tmp_path: Path) -> None:
    """A report is printed as it is known, so one dead machine costs one line."""
    answering = Silent("10.0.0.11", 255, "ssh: connect to host: timed out\n")
    printed: list[str] = []
    deployment = _built(
        tmp_path,
        plan=PLAN,
        entries={
            CLIENT_KEY: _stated(CLIENT_KEY, "beta", "10.0.0.11"),
            SERVER_KEY: _stated(SERVER_KEY, "alpha", "10.0.0.10"),
        },
    )

    reported = report.status(deployment, answering, base_env={}, log=printed.append)

    assert printed == list(reported.lines)
    assert reported.lines[0].startswith(f"{CLIENT_KEY} flakelet unreachable")
    assert reported.lines[1] == f"{SERVER_KEY} flakelet absent"


def test_a_report_that_could_not_ask_every_machine_exits_non_zero(
    tmp_path: Path,
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    """Every machine answering is a zero exit whatever it answered, silence is not."""
    root = tmp_path / "built"
    _built(
        root,
        plan=PLAN,
        entries={
            CLIENT_KEY: _stated(CLIENT_KEY, "beta", "10.0.0.11"),
            SERVER_KEY: _stated(SERVER_KEY, "alpha", "10.0.0.10"),
        },
    )

    monkeypatch.setattr(remote, "Subprocess", lambda: Recorder())
    assert planner.main(["status", str(root)]) == 0

    silent = Silent("10.0.0.11", 255, "ssh: connect to host: timed out\n")
    monkeypatch.setattr(remote, "Subprocess", lambda: silent)
    assert planner.main(["status", str(root)]) == 1


def _ran(entry: manifest.Entry) -> dict[str, str]:
    """The unit files the harness wrote for one entry, as its machine reports them."""
    artifact = manifest.artifact_of(entry)
    return {unit: str((artifact / "units" / unit).readlink()) for unit in entry.units}


def _endpoint(entry: manifest.Entry, units: dict[str, str], **fields: object) -> str:
    """One entry's record, as `flakelet status --json` prints it."""
    return json.dumps(
        [
            {
                "name": entry.key,
                "generation": 1,
                "locked_url": f"plan:{entry.key}",
                "units": units,
                "last_error": None,
                **fields,
            }
        ]
    )


def test_an_endpoint_that_reports_no_identity_is_compared_by_what_it_does_report(
    tmp_path: Path,
) -> None:
    """The endpoint names no identity, so the line answers over the files it does name."""
    deployment = _built(
        tmp_path,
        plan=PLAN,
        entries={SERVER_KEY: _stated(SERVER_KEY, "alpha", "10.0.0.10")},
    )
    entry = deployment.entries[SERVER_KEY]
    ran = _ran(entry)
    older = {unit: f"{path}-of-an-older-build" for unit, path in ran.items()}

    holds = report.status(deployment, Answering("flakelet status", _endpoint(entry, ran)))
    moved = report.status(deployment, Answering("flakelet status", _endpoint(entry, older)))

    said = f"{SERVER_KEY} flakelet generation 1 of plan:{SERVER_KEY}"
    assert holds.lines == (f"{said} runs this build's units",)
    assert moved.lines == (f"{said} runs units this build did not produce",)
    assert (holds.unasked, moved.unasked) == ((), ())


def test_an_endpoint_that_reports_nothing_to_compare_is_not_reported_as_current(
    tmp_path: Path,
) -> None:
    """An answer carrying no unit file is compared with nothing, and says so."""
    deployment = _built(
        tmp_path,
        plan=PLAN,
        entries={SERVER_KEY: _stated(SERVER_KEY, "alpha", "10.0.0.10")},
    )
    entry = deployment.entries[SERVER_KEY]

    reported = report.status(deployment, Answering("flakelet status", _endpoint(entry, {})))

    assert reported.lines == (
        f"{SERVER_KEY} flakelet generation 1 of plan:{SERVER_KEY} reports nothing to compare",
    )
    assert "current" not in reported.lines[0]


class Fleet(Recorder):
    """A recorder answering each machine with the endpoint record ``said`` names."""

    def __init__(self, said: dict[str, str]) -> None:
        super().__init__()
        self.said = said

    def output(
        self, cmd: list[str], *, env: dict[str, str] | None = None, stdin: bytes | None = None
    ) -> str:
        answered = super().output(cmd, env=env, stdin=stdin)
        if _asked_what_it_holds(cmd):
            return answered
        for address, said in self.said.items():
            if address in " ".join(cmd):
                return said
        return answered


def test_a_fleet_part_way_through_an_apply_reports_both_answers(
    tmp_path: Path,
    monkeypatch: pytest.MonkeyPatch,
    capsys: pytest.CaptureFixture[str],
) -> None:
    """One machine applied from this build, one not, and the run still exits zero."""
    root = tmp_path / "built"
    deployment = _built(
        root,
        plan=PLAN,
        entries={
            CLIENT_KEY: _stated(CLIENT_KEY, "beta", "10.0.0.11"),
            SERVER_KEY: _stated(SERVER_KEY, "alpha", "10.0.0.10"),
        },
    )
    applied = deployment.entries[SERVER_KEY]
    behind = deployment.entries[CLIENT_KEY]
    stale = {unit: f"{path}-of-an-older-build" for unit, path in _ran(behind).items()}
    fleet = Fleet(
        {
            "10.0.0.10": _endpoint(applied, _ran(applied)),
            "10.0.0.11": _endpoint(behind, stale),
        }
    )
    monkeypatch.setattr(remote, "Subprocess", lambda: fleet)

    assert planner.main(["status", str(root)]) == 0

    printed = capsys.readouterr().out.splitlines()
    assert printed == [
        f"{CLIENT_KEY} flakelet generation 1 of plan:{CLIENT_KEY} "
        f"runs units this build did not produce",
        f"{SERVER_KEY} flakelet generation 1 of plan:{SERVER_KEY} runs this build's units",
    ]


def test_a_record_publishing_no_identity_is_refused(tmp_path: Path) -> None:
    """A record with no published identity is one the command cannot read."""
    root = tmp_path / "built"
    stated = _stated(SERVER_KEY, "alpha", "10.0.0.10")
    del stated["key"]

    with pytest.raises(errors.ApplyError) as raised:
        _built(root, plan=PLAN, entries={SERVER_KEY: stated})

    message = str(raised.value)
    assert SERVER_KEY in message
    assert "key" in message


def test_the_pinned_endpoints_answer_still_carries_no_identity() -> None:
    """The weaker comparison is a fact about one revision of somebody else's tool.

    It is compared rather than trusted, and an unresolvable source is not
    evidence that it moved: a build sandbox reaches no network, so this skips
    there and answers in a shell.
    """
    source = delivery.endpoint_source()
    if source is None:
        pytest.skip("the locked flakelet source is not resolvable here")

    assert delivery.endpoint_refusal(source) is None, delivery.endpoint_refusal(source)
    assert "settings_hash" not in delivery.ENDPOINT_REPORTS


def test_the_resolved_tool_round_trips_a_native_recipient(tmp_path: Path) -> None:
    """The one behaviour this change rests on, asserted against the tool a run uses.

    Mint a throwaway pair, seal a known string to the printed line, open it with
    the identity file, compare. No version is compared, so a bump that changes
    nothing changes nothing here.
    """
    tool = delivery.sealing_tool()
    if tool is None:
        pytest.skip(delivery.sealing_skip())

    assert delivery.sealing_refusal(tool, tmp_path) is None, delivery.sealing_refusal(
        tool, tmp_path
    )


def test_a_tool_that_cannot_be_resolved_skips_rather_than_passes() -> None:
    """A reference naming nothing answers nothing, and the reason names that reference.

    The round trip above reads that answer and skips on it. An unresolvable
    reference is not evidence that sealing still works, so it may not be read as
    a claim that was satisfied.
    """
    reference = f"{Path(__file__).resolve().parents[2]}#planner-seals-with-nothing"

    assert delivery.sealing_tool(reference) is None
    assert reference in delivery.sealing_skip(reference)
    assert delivery.SEALING in delivery.sealing_skip(reference)


def _row(severity: str) -> dict[str, str]:
    return {
        "id": "slot-unwired",
        "subject": CLIENT_KEY,
        "severity": severity,
        "message": "no wire reaches site",
        "evidence": "",
        "resolution": "",
    }


TABLE = "slot-unwired  check:client@beta  no wire reaches site"


def test_a_build_of_a_deployment_carrying_warnings_prints_them(
    tmp_path: Path,
    capsys: pytest.CaptureFixture[str],
) -> None:
    """A warning is what a deployment holds as much as an entry is."""
    root = tmp_path / "built"
    _built(
        root,
        plan=PLAN,
        entries={SERVER_KEY: _stated(SERVER_KEY, "alpha", "10.0.0.10")},
        values={SESSION_VALUE: {"delivery": ["alpha"], "files": TOKEN}},
        rows=[_row("warning")],
        table=f"{TABLE}\n",
    )

    assert planner.main(["build", str(root)]) == 0

    printed = capsys.readouterr().out
    assert SERVER_KEY in printed
    assert SESSION_VALUE in printed
    assert TABLE in printed


def test_a_build_of_a_deployment_carrying_an_error_prints_the_table_and_refuses(
    tmp_path: Path,
    capsys: pytest.CaptureFixture[str],
) -> None:
    """The planner refused it, so the report is that refusal rather than a second one."""
    root = tmp_path / "built"
    _built(root, plan=PLAN, entries={}, rows=[_row("error")], table=f"{TABLE}\n")

    assert planner.main(["build", str(root)]) == 1

    assert TABLE in capsys.readouterr().out


def _written(script: str, *, umask: int, content: bytes = b"s3cret") -> int:
    """Run one write script under a stated umask, with its bytes on its own input."""
    return subprocess.run(
        ["bash", "-c", f"umask {umask:04o}; {script}"],
        input=content,
        check=False,
        capture_output=True,
    ).returncode


def _own_account() -> tuple[str, str]:
    return pwd.getpwuid(os.getuid()).pw_name, grp.getgrgid(os.getgid()).gr_name


def test_a_mode_widened_on_the_machine(tmp_path: Path) -> None:
    """Ownership and mode are set on every apply, so a machine-side edit does not survive.

    The mode is also read back under two umasks, because the record is the only
    thing that decides it and a login's umask is not part of the deployment.
    """
    owner, group = _own_account()
    modes = []
    for umask in (0o077, 0o000):
        path = tmp_path / f"u{umask:o}" / "token"
        file = ValueFile(
            name="token",
            path=str(path),
            sealed=f"{path}.age",
            secrecy="secret",
            owner=owner,
            group=group,
            mode="0640",
        )
        script = remote.write_script(file)
        assert _written(script, umask=umask) == 0
        assert stat.S_IMODE(path.stat().st_mode) == 0o640
        path.chmod(0o666)

        assert _written(script, umask=umask) == 0

        modes.append(stat.S_IMODE(path.stat().st_mode))
        assert path.read_bytes() == b"s3cret"
    assert modes == [0o640, 0o640]


def test_an_interrupted_write(tmp_path: Path) -> None:
    """A write that stops part way is the old file or none, never a half of the new one."""
    owner, group = _own_account()
    path = tmp_path / "token"
    file = ValueFile(
        name="token",
        path=str(path),
        sealed=f"{path}.age",
        secrecy="secret",
        owner=owner,
        group=group,
        mode="0400",
    )
    assert _written(remote.write_script(file), umask=0o077, content=b"first") == 0
    interrupted = remote.write_script(file).replace("mv -f", "false; mv -f", 1)

    assert _written(interrupted, umask=0o077, content=b"second") != 0

    assert path.read_bytes() == b"first"
    assert sorted(p.name for p in tmp_path.iterdir()) == ["token"]


def test_an_account_the_machine_does_not_have(tmp_path: Path) -> None:
    """A recorded owner the machine lacks is that sentence, not `chown`'s wording."""
    path = tmp_path / "token"
    file = ValueFile(
        name="token",
        path=str(path),
        sealed=f"{path}.age",
        secrecy="secret",
        owner="nosuchaccount",
        group="nosuchaccount",
        mode="0400",
    )
    ran = subprocess.run(
        ["bash", "-c", remote.write_script(file)],
        input="s3cret",
        check=False,
        capture_output=True,
        text=True,
    )

    assert ran.returncode != 0
    assert "no account nosuchaccount:nosuchaccount" in ran.stderr
    assert str(path) in ran.stderr
    assert list(tmp_path.iterdir()) == []


def _file_record(path: Path, *, owner: str, group: str, mode: str = "0400") -> ValueFile:
    """One value file record naming ``path``."""
    return ValueFile(
        name="token",
        path=str(path),
        sealed=f"{path}.age",
        secrecy="secret",
        owner=owner,
        group=group,
        mode=mode,
    )


def test_a_value_write_carries_its_bytes_on_the_steps_input_stream(tmp_path: Path) -> None:
    """The file holds the bytes handed over, and the step still answers one word.

    The payload is not valid text, which is the case a channel encoding what it
    is given corrupts silently. The observation is the file rather than a
    recording of it: what records a step is handed the argv and never the bytes.
    """
    owner, group = _own_account()
    path = tmp_path / "token"
    step = ["bash", "-c", remote.write_script(_file_record(path, owner=owner, group=group))]
    payload = b"\x00\xfe not utf-8 \xff\x80"
    channel = remote.Subprocess()

    answered = channel.output(step, stdin=payload)

    assert path.read_bytes() == payload
    assert answered.split() == ["changed"]
    assert channel.output(step, stdin=payload).split() == ["unchanged"]

    # A machine's own answer is decoded where it is read, so a byte the locale
    # cannot decode is reported rather than raised on inside the decoder.
    with pytest.raises(remote.Refused) as refused:
        channel.output(["bash", "-c", "printf 'refused \\377\\n' >&2; exit 7"], stdin=payload)

    assert refused.value.status == 7
    assert "refused" in refused.value.said
    assert "\ufffd" in refused.value.said


def test_a_write_that_fails_after_its_bytes_have_arrived(tmp_path: Path) -> None:
    """A write refused at the ownership leaves the file that was there and nothing else.

    The run reports the value, the file, the machine and what the machine said,
    and takes no step after it: the recovery is a second apply.
    """
    owner, group = _own_account()
    path = tmp_path / "token"
    held = _file_record(path, owner=owner, group=group)
    assert _written(remote.write_script(held), umask=0o077, content=b"first") == 0
    refused = _file_record(path, owner="nosuchaccount", group="nosuchaccount")

    assert _written(remote.write_script(refused), umask=0o077, content=SECRET) != 0

    assert path.read_bytes() == b"first"
    assert sorted(entry.name for entry in tmp_path.iterdir()) == ["token"]

    deployment = _delivering(tmp_path / "built")
    source = _bytes_source(tmp_path / "values", {f"{SESSION_VALUE}/token": SECRET})
    failing = Failing('cat > "$tmp"')
    printed: list[str] = []
    with pytest.raises(errors.ApplyError) as reported:
        apply.apply(deployment, failing, source=source, base_env={}, log=printed.append)

    message = str(reported.value)
    for named in (SESSION_VALUE, "token", "10.0.0.10", TOKEN["token"]["path"], REFUSED):
        assert named in message
    # The question of what the machine holds is asked before any step, and the
    # write that broke is the first step, so no step is recorded at all.
    assert [cmd for cmd in failing.commands if not _asked_what_it_holds(cmd)] == []
    assert printed[-1].startswith("failed ")


def test_a_repeated_write_finishes_what_a_failed_one_did_not(tmp_path: Path) -> None:
    """The apply after a write that stopped part way writes the file and says so."""
    owner, group = _own_account()
    path = tmp_path / "token"
    file = _file_record(path, owner=owner, group=group, mode="0640")
    script = remote.write_script(file)
    assert _written(script, umask=0o077, content=b"first") == 0
    assert _written(script.replace("mv -f", "false; mv -f", 1), umask=0o077, content=SECRET) != 0

    answered = remote.Subprocess().output(["bash", "-c", script], stdin=SECRET)

    assert answered.split() == ["changed"]
    assert path.read_bytes() == SECRET
    assert stat.S_IMODE(path.stat().st_mode) == 0o640
    assert (path.owner(), path.group()) == (owner, group)
    assert sorted(entry.name for entry in tmp_path.iterdir()) == ["token"]


TOKEN_PATH = "/run/vars/issuer/session/token"
OWNED_PATH = "/run/vars/issuer/session/owned"
TWO_FILES = {
    "token": _delivered(TOKEN_PATH, "secret"),
    "owned": _delivered(OWNED_PATH, "secret", owner="nobody", group="nogroup", mode="0440"),
}


class Holding(Recorder):
    """A machine that answers the values question for the paths it is asked about."""

    def __init__(self, held: set[str]) -> None:
        super().__init__()
        self.held = held

    def output(
        self, cmd: list[str], *, env: dict[str, str] | None = None, stdin: bytes | None = None
    ) -> str:
        answered = super().output(cmd, env=env, stdin=stdin)
        asked = cmd[-1]
        if "present" not in asked:
            return answered
        return "".join(
            f"{path} {'present' if path in self.held else 'absent'}\n"
            for path in (OWNED_PATH, TOKEN_PATH)
            if shlex.quote(path) in asked
        )


def _holding(tmp_path: Path, held: set[str]) -> report.Report:
    """Report on one machine delivered a value of two files, holding ``held`` of them."""
    deployment = _built(
        tmp_path,
        plan=PLAN,
        entries={SERVER_KEY: _stated(SERVER_KEY, "alpha", "10.0.0.10")},
        values={SESSION_VALUE: {"delivery": ["alpha"], "files": TWO_FILES}},
    )
    return report.status(deployment, Holding(held), base_env={})


def test_a_machine_holding_every_file_of_a_value_is_reported_without_a_line(
    tmp_path: Path,
) -> None:
    """A value of more than one file is one question and, when it is all there, no line."""
    reported = _holding(tmp_path, {TOKEN_PATH, OWNED_PATH})

    assert [line for line in reported.lines if line.startswith("value ")] == []
    assert reported.unasked == ()


def test_a_value_one_of_whose_files_is_gone_is_named_once(tmp_path: Path) -> None:
    """The report is about the value and not about its files, so one line names it."""
    reported = _holding(tmp_path, {OWNED_PATH})

    assert [line for line in reported.lines if line.startswith("value ")] == [
        f"value {SESSION_VALUE} missing on alpha"
    ]
    assert reported.unasked == ()


class Unchecked(Holding):
    """A machine holding its values and no unsealer, so its trial answers nothing.

    The question is one login, so the answer is one answer: the presence of
    each delivered path, the marker, and the word a machine with no trial to
    run prints instead of that trial's own lines.
    """

    def output(
        self, cmd: list[str], *, env: dict[str, str] | None = None, stdin: bytes | None = None
    ) -> str:
        answered = super().output(cmd, env=env, stdin=stdin)
        if "present" not in cmd[-1]:
            return answered
        return f"{answered}{remote.SEALS}\n{remote.UNCHECKED}\n"


def test_a_machine_that_holds_no_unsealer_is_not_reported_either_way(tmp_path: Path) -> None:
    """A machine the record says seals and which was never applied to is neither."""
    deployment = _built(
        tmp_path,
        plan=PLAN,
        entries={SERVER_KEY: _stated(SERVER_KEY, "alpha", "10.0.0.10")},
        values={SESSION_VALUE: {"delivery": ["alpha"], "files": TWO_FILES}},
        machines=_sealing("alpha"),
    )
    machine = Unchecked({TOKEN_PATH, OWNED_PATH})

    reported = report.status(deployment, machine, base_env={})

    assert "alpha holds no unsealer, so its sealed copies were not checked" in reported.lines
    assert [line for line in reported.lines if "sealed copy" in line] == []
    # A machine that answered is not a machine that could not be asked.
    assert reported.unasked == ()
    # One question per machine: the trial rides in the login the presence
    # question already cost, because a socket-activated sshd refuses a burst.
    assert len([cmd for cmd in machine.commands if remote.SEALS in cmd[-1]]) == 1


USER_ADDRESS = "10.0.0.10"
ASKED = re.compile(r"printf '%s=%s\\n' (\S+) ok")


def _user_scope(root: Path) -> manifest.Deployment:
    """One image entry and one value on a machine whose registry states `scope = "user"`.

    The scope is stated twice because the plan states it twice: in the machine
    record every reader of a machine asks, and in the target of the entry that
    was planned for it.
    """
    deployment = _built(
        root,
        plan={
            **PLAN,
            "machine:alpha": {"address": USER_ADDRESS, "tags": ["cluster"], "scope": "user"},
            SERVER_KEY: {
                "key": PUBLISHED,
                "target": {"address": USER_ADDRESS, "scope": "user"},
                "reads": {"token": _reading()},
            },
        },
        entries={SERVER_KEY: {**_stated(SERVER_KEY, "alpha", USER_ADDRESS), "realiser": "image"}},
        values={SESSION_VALUE: {"delivery": ["alpha"], "files": TOKEN}},
    )
    artifact = manifest.artifact_of(deployment.entries[SERVER_KEY])
    (artifact / "attachment.json").write_text(json.dumps({"image": f"site-server_{PUBLISHED}.raw"}))
    return deployment


class Provisioned(Recorder):
    """A machine answering the preflight question it was asked, fact by fact.

    The answer is read out of the question rather than written beside it, so a
    requirement the command stops asking is a requirement this stops answering.
    ``failing`` is what the machine says instead of `ok`, by requirement key.
    """

    def __init__(self, failing: dict[str, str] | None = None) -> None:
        super().__init__()
        self.failing = {} if failing is None else failing

    def output(
        self, cmd: list[str], *, env: dict[str, str] | None = None, stdin: bytes | None = None
    ) -> str:
        self.commands.append(cmd)
        asked = cmd[-1]
        if _asked_what_it_holds(cmd):
            return ""
        keys = ASKED.findall(asked)
        if keys:
            return "".join(f"{key}={self.failing.get(key, remote.OK)}\n" for key in keys)
        if 'cat > "$tmp"' in asked:
            return "changed"
        if "flakelet status" in asked:
            return "[]"
        return "attached site-server"


def _steps(log: tuple[str, ...]) -> list[str]:
    """Return the step lines of a log, without what the machines said under them."""
    return [line for line in log if not line.startswith("  ")]


def test_a_user_scope_machine_is_asked_before_anything_is_written(tmp_path: Path) -> None:
    """The question is the first step against the machine, and it asks every fact.

    Provisioning is root's work done once, so each of these is verified: a
    machine that was never provisioned and one that was are told apart here and
    nowhere else.
    """
    deployment = _user_scope(tmp_path / "built")
    source = _source(tmp_path / "values", {f"{SESSION_VALUE}/token": "s3cret"})
    machine = Provisioned()

    log = apply.apply(deployment, machine, source=source, base_env={})

    steps = _steps(log)
    assert steps[0] == f"preflight alpha at root@{USER_ADDRESS}"
    for mutation in ("value ", "copy ", "activate ", "restart "):
        assert [at for at, line in enumerate(steps) if line.startswith(mutation)] > [0], steps
    # By what it asks and not by its position: the question of what the machine
    # holds precedes every step, and prints no step line of its own.
    question = next(cmd[-1] for cmd in machine.commands if ASKED.findall(cmd[-1]))
    assert ASKED.findall(question) == [
        "values-root",
        "sealed-root",
        "staging-root",
        "lingering",
        "user-manager",
        "user-portabled",
        "home-traversable",
        "mountfsd",
        "nsresourced",
        "user-namespaces",
    ]
    for named in (
        remote.VALUES_ROOT,
        remote.SEALED_ROOT,
        remote.STAGING_ROOT,
        remote.MOUNTFSD,
        remote.NSRESOURCED,
        remote.NAMESPACES,
        "Linger",
        "XDG_RUNTIME_DIR",
        '"$HOME"',
    ):
        assert named in question, named
    # One question per machine, for the reason the values question is one.
    assert len([cmd for cmd in machine.commands if ASKED.findall(cmd[-1])]) == 1


def test_a_failed_preflight_fact_is_the_runs_own_refusal(tmp_path: Path) -> None:
    """A fact the machine says it does not hold stops the run there, naming all three."""
    deployment = _user_scope(tmp_path / "built")
    source = _source(tmp_path / "values", {f"{SESSION_VALUE}/token": "s3cret"})
    said = "loginctl reports no lingering for the account"
    machine = Provisioned({"lingering": said})

    with pytest.raises(errors.ApplyError) as raised:
        apply.apply(deployment, machine, source=source, base_env={})

    message = str(raised.value)
    assert "alpha" in message
    assert "lingering" in message
    assert said in message
    assert "Traceback" not in message
    # Nothing after the question was attempted on that machine: what it holds,
    # which every run asks first and no run writes anything for, and this.
    assert [_asked_what_it_holds(cmd) for cmd in machine.commands] == [True, False]


def test_a_system_scope_machine_is_asked_nothing_new(tmp_path: Path) -> None:
    """A machine stating no scope is a system-scope machine, and its steps are what they were."""
    deployment = _delivering(tmp_path / "built")
    source = _source(tmp_path / "values", {f"{SESSION_VALUE}/token": "s3cret"})
    machine = Provisioned()

    log = apply.apply(deployment, machine, source=source, base_env={})

    assert [line for line in _steps(log) if line.startswith("preflight ")] == []
    assert [cmd for cmd in machine.commands if ASKED.findall(cmd[-1])] == []
    assert _steps(log)[0].startswith(f"value {SESSION_VALUE} ")


def test_a_dry_run_records_the_preflight_question(tmp_path: Path) -> None:
    """The question goes through the replaced channel, so it is printed and never asked."""
    deployment = _user_scope(tmp_path / "built")
    source = _source(tmp_path / "values", {f"{SESSION_VALUE}/token": "s3cret"})

    asked = Provisioned()
    would = apply.apply(deployment, asked, source=source, dry_run=True, base_env={})

    assert asked.commands == []
    assert would[0] == f"preflight alpha at root@{USER_ADDRESS}"

    taken = Provisioned()
    did = apply.apply(deployment, taken, source=source, base_env={})

    # A restart is a function of what the machine said a write did, which a dry
    # run never asked, so the steps compared are the ones a plan decides.
    assert [line for line in _steps(did) if not line.startswith("restart ")] == list(would)


def test_a_user_scope_machine_is_addressed_as_the_account(tmp_path: Path) -> None:
    """`--user` is in every step that addresses a manager or a portabled, and nowhere else."""
    deployment = _user_scope(tmp_path / "built")
    source = _source(tmp_path / "values", {f"{SESSION_VALUE}/token": "s3cret"})
    machine = Provisioned()

    apply.apply(deployment, machine, source=source, base_env={})
    report.status(deployment, machine, base_env={})

    scripts = [cmd[-1] for cmd in machine.commands if cmd[0] == "ssh"]
    restarts = [script for script in scripts if "try-restart" in script]
    asked = [script for script in scripts if "is-attached" in script]
    written = [script for script in scripts if 'cat > "$tmp"' in script]
    assert restarts == [f"{remote.BUS}systemctl --user try-restart site-server-serve.service 2>&1"]
    assert asked and all("portablectl --user" in script for script in asked)
    assert all(remote.BUS in script for script in restarts + asked)
    # The account owns what it writes, and chowning a file to the owner it
    # already has is refused by the kernel, so the write states the mode alone.
    assert written and all("chown" not in script for script in written)
    assert all(f"chmod {TOKEN['token']['mode']}" in script for script in written)


def test_a_system_scope_machine_is_addressed_as_root(tmp_path: Path) -> None:
    """The same steps on a machine stating no scope name no account and no bus."""
    deployment = _built(
        tmp_path / "built",
        plan={**PLAN, SERVER_KEY: {"key": PUBLISHED, "reads": {"token": _reading()}}},
        entries={SERVER_KEY: _stated(SERVER_KEY, "alpha", USER_ADDRESS)},
        values={SESSION_VALUE: {"delivery": ["alpha"], "files": TOKEN}},
    )
    source = _source(tmp_path / "values", {f"{SESSION_VALUE}/token": "s3cret"})
    machine = Provisioned()

    apply.apply(deployment, machine, source=source, base_env={})
    report.status(deployment, machine, base_env={})

    scripts = [cmd[-1] for cmd in machine.commands if cmd[0] == "ssh"]
    written = [script for script in scripts if 'cat > "$tmp"' in script]
    assert [script for script in scripts if "--user" in script] == []
    assert [script for script in scripts if "XDG_RUNTIME_DIR" in script] == []
    assert written and all("chown root:root" in script for script in written)


def test_an_entry_states_a_realiser_that_does_not_realise_its_scope(tmp_path: Path) -> None:
    """The record publishes what each realiser realises, and the crossing is made against it."""
    deployment = _built(
        tmp_path / "built",
        plan={
            **PLAN,
            "machine:alpha": {"address": USER_ADDRESS, "tags": ["cluster"], "scope": "user"},
            SERVER_KEY: {"key": PUBLISHED, "target": {"scope": "user"}},
        },
        entries={SERVER_KEY: _stated(SERVER_KEY, "alpha", USER_ADDRESS)},
    )
    recorder = Recorder()

    with pytest.raises(errors.ApplyError) as raised:
        apply.apply(deployment, recorder, base_env={})

    message = str(raised.value)
    assert SERVER_KEY in message
    assert "user scope" in message
    assert "flakelet" in message
    assert recorder.commands == []


GONE_KEY = "sweep:job@alpha"
GONE_NAME = "sweep-job"
GONE_OTHER_KEY = "spare:agent@alpha"
GONE_OTHER_NAME = "spare-agent"


class Holds(Recorder):
    """A machine answering ``said`` to the question of what it holds.

    Every other question is answered with nothing, which is what a machine's
    endpoint says about an entry it holds nothing for, so each case below is
    about the answer under test and no other. ``at`` is the machine that
    answers, where a case has more than one and only one of them holds
    anything.
    """

    def __init__(self, said: str, at: str | None = None) -> None:
        super().__init__()
        self.said = said
        self.at = at

    def output(
        self, cmd: list[str], *, env: dict[str, str] | None = None, stdin: bytes | None = None
    ) -> str:
        answered = super().output(cmd, env=env, stdin=stdin)
        addressed = self.at is None or self.at in " ".join(cmd)
        return self.said if _asked_what_it_holds(cmd) and addressed else answered


def _on_alpha(*keys: str) -> dict[str, dict[str, Any]]:
    """Return those entries, all of them placed on one machine."""
    return {key: _stated(key, "alpha", "10.0.0.10") for key in keys}


def _reported_holdings(
    tmp_path: Path,
    said: str,
    *,
    entries: dict[str, dict[str, Any]] | None = None,
    only: tuple[str, ...] = (),
) -> tuple[report.Report, Holds]:
    """Report on a deployment whose machines answer ``said`` about what they hold."""
    deployment = _built(
        tmp_path, plan=PLAN, entries=_on_alpha(SERVER_KEY) if entries is None else entries
    )
    machine = Holds(said)
    return report.status(deployment, machine, only=only, base_env={}), machine


def _named(reported: report.Report) -> list[str]:
    """Return the holding lines of a report, in the order it printed them."""
    return [line for line in reported.lines if " holds " in line]


def test_one_question_per_machine_carries_every_realiser_the_scopes_admit(
    tmp_path: Path,
) -> None:
    """The question is built from the table, and a realiser whose scopes refuse stays out."""
    system, machine = _reported_holdings(tmp_path, "")
    asked = [cmd[-1] for cmd in machine.commands if _asked_what_it_holds(cmd)]
    assert len(asked) == 1
    assert "flakelet status --json" in asked[0]
    assert "portablectl list --no-legend" in asked[0]
    assert "--user" not in asked[0]
    assert system.unasked == ()

    scoped = Holds("")
    report.status(_user_scope(tmp_path / "user"), scoped, base_env={})

    user = [cmd[-1] for cmd in scoped.commands if _asked_what_it_holds(cmd)]
    assert len(user) == 1
    assert "portablectl --user list --no-legend" in user[0]
    assert remote.BUS in user[0]
    # flakelet publishes system scope alone, so its half reaches no such machine.
    assert "flakelet" not in user[0]


def test_a_machine_without_a_realisers_tool_holds_nothing_of_it(tmp_path: Path) -> None:
    """A missing tool is an answer about the machine, and any other status is unreadable."""
    without, _ = _reported_holdings(
        tmp_path, _holds(("flakelet", 127, "flakelet: command not found"))
    )

    assert _named(without) == []
    assert without.unasked == ()

    with pytest.raises(errors.ApplyError) as raised:
        _reported_holdings(tmp_path / "refused", _holds(("flakelet", 1, "no endpoint socket")))

    message = str(raised.value)
    assert "alpha" in message
    assert "no endpoint socket" in message


def test_a_machine_holding_nothing_unnamed_is_reported_without_such_a_line(
    tmp_path: Path,
) -> None:
    """A machine holding exactly what the build names says nothing more."""
    reported, _ = _reported_holdings(
        tmp_path,
        _holds(("flakelet", 0, _registered(_registration(SERVER_KEY, "site-server")))),
    )

    assert _named(reported) == []
    assert reported.lines == (f"{SERVER_KEY} flakelet absent",)
    assert reported.unasked == ()


def test_an_unnamed_holding_does_not_change_the_exit_status(
    tmp_path: Path,
    monkeypatch: pytest.MonkeyPatch,
    capsys: pytest.CaptureFixture[str],
) -> None:
    """A holding is an answer a machine gave, which costs no exit status."""
    root = tmp_path / "built"
    _built(root, plan=PLAN, entries=_on_alpha(SERVER_KEY))
    machine = Holds(_holds(("flakelet", 0, _registered(_registration(GONE_KEY, GONE_NAME)))))
    monkeypatch.setattr(remote, "Subprocess", lambda: machine)

    assert planner.main(["status", str(root)]) == 0

    printed = capsys.readouterr().out.splitlines()
    assert f"alpha holds {GONE_KEY}, which this build does not name" in printed


def test_a_service_the_machines_own_configuration_declares_is_not_reported(
    tmp_path: Path,
) -> None:
    """An identity carrying nothing the record publishes came from no deployment of ours."""
    declared = {
        **_registration(GONE_KEY, "monitoring"),
        "locked_url": "github:someone/monitoring",
        "origin": "declarative",
    }
    reported, _ = _reported_holdings(
        tmp_path,
        _holds(
            ("flakelet", 0, _registered(_registration(SERVER_KEY, "site-server"), declared)),
        ),
    )

    assert _named(reported) == []
    assert reported.lines == (f"{SERVER_KEY} flakelet absent",)


def test_an_entry_the_selection_excluded_is_not_reported_as_unnamed(tmp_path: Path) -> None:
    """The restriction bounds which machines are asked and not what counts as unnamed."""
    reported, _ = _reported_holdings(
        tmp_path,
        _holds(
            (
                "flakelet",
                0,
                _registered(
                    _registration(SERVER_KEY, "site-server"),
                    _registration(CLIENT_KEY, "check-client"),
                ),
            ),
        ),
        entries=_on_alpha(SERVER_KEY, CLIENT_KEY),
        only=(SERVER_KEY,),
    )

    assert _named(reported) == []
    assert reported.lines == (f"{SERVER_KEY} flakelet absent",)


def test_a_machine_the_build_no_longer_names_is_not_asked(tmp_path: Path) -> None:
    """The plan carries the machine and the build places nothing on it, so nobody dials it."""
    reported, machine = _reported_holdings(
        tmp_path,
        _holds(("flakelet", 0, _registered(_registration(GONE_KEY, GONE_NAME)))),
    )

    dialled = " ".join(" ".join(cmd) for cmd in machine.commands)
    assert "10.0.0.11" not in dialled
    assert [line for line in reported.lines if "beta" in line] == []
    assert reported.unasked == ()


def test_the_question_of_what_a_machine_holds_is_asked_once_per_machine(
    tmp_path: Path,
) -> None:
    """Three entries on one machine are one question, and its answer is read whole."""
    reported, machine = _reported_holdings(
        tmp_path,
        _holds(
            (
                "flakelet",
                0,
                _registered(
                    _registration(GONE_KEY, GONE_NAME),
                    _registration(GONE_OTHER_KEY, GONE_OTHER_NAME),
                ),
            ),
        ),
        entries=_on_alpha(SERVER_KEY, CLIENT_KEY, RELAY_KEY),
    )

    assert len([cmd for cmd in machine.commands if _asked_what_it_holds(cmd)]) == 1
    assert _named(reported) == [
        f"alpha holds {GONE_KEY}, which this build does not name",
        f"alpha holds {GONE_OTHER_KEY}, which this build does not name",
    ]


def test_an_answer_about_what_a_machine_holds_that_the_command_cannot_read_is_a_refusal(
    tmp_path: Path,
) -> None:
    """An answer that is not the endpoint's own is refused, never read as holding nothing."""
    said = "ssh: /bin/sh: no such file"

    with pytest.raises(errors.ApplyError) as raised:
        _reported_holdings(tmp_path, said)

    message = str(raised.value)
    assert "alpha" in message
    assert said in message


def _retiring(
    tmp_path: Path,
    said: str,
    *,
    entries: dict[str, dict[str, Any]] | None = None,
    only: tuple[str, ...] = (),
    retire: bool = True,
) -> tuple[tuple[str, ...], Holds]:
    """Apply a deployment whose alpha answers ``said`` about what it holds."""
    deployment = _built(
        tmp_path, plan=PLAN, entries=_on_alpha(SERVER_KEY) if entries is None else entries
    )
    machine = Holds(said, at="10.0.0.10")
    return apply.apply(deployment, machine, only=only, retire=retire, base_env={}), machine


def _one_holding() -> str:
    """One machine's answer naming one entry of this planner's that no build here names."""
    return _holds(("flakelet", 0, _registered(_registration(GONE_KEY, GONE_NAME))))


def _retirements(machine: Holds) -> list[str]:
    """Return the removal steps a run addressed to a machine, as the machine saw them."""
    return [cmd[-1] for cmd in machine.commands if "flakelet remove" in cmd[-1]]


def test_a_run_asked_what_it_would_do_names_no_holding(tmp_path: Path) -> None:
    """A dry run contacts no machine, so it names no holding: reporting answers that."""
    deployment = _built(tmp_path, plan=PLAN, entries=_on_alpha(SERVER_KEY))
    machine = Holds(_one_holding())

    would = apply.apply(deployment, machine, dry_run=True, retire=True, base_env={})

    assert machine.commands == []
    assert [line for line in would if " holds " in line] == []
    assert _activated(would) == [SERVER_KEY]


def test_a_retirement_asks_the_endpoint_to_remove_the_entry(tmp_path: Path) -> None:
    """The step is the endpoint's own removal verb, and never the one that empties state."""
    log, machine = _retiring(tmp_path / "retired", _one_holding())

    assert _retirements(machine) == [f"flakelet remove {GONE_NAME} 2>&1"]
    assert all("--purge" not in cmd[-1] for cmd in machine.commands)
    assert [line for line in log if line.startswith("retire ")] == [
        f"retire {GONE_KEY} on root@10.0.0.10 (no state deleted)"
    ]
    assert f"alpha holds {GONE_KEY}, which this build does not name" in log

    announced, untouched = _retiring(tmp_path / "announced", _one_holding(), retire=False)

    # A run that was not asked announces the holding and says what it did about it.
    assert _retirements(untouched) == []
    assert [line for line in announced if " holds " in line] == [
        f"alpha holds {GONE_KEY}, which this build does not name; not retired"
    ]
    assert _activated(announced) == [SERVER_KEY]


def test_a_retirement_names_only_what_the_machine_answered_and_the_record_published(
    tmp_path: Path,
) -> None:
    """Every word of the step comes from the answer, the record and the invocation."""
    _, machine = _retiring(tmp_path, _one_holding())

    taken = _retirements(machine)
    assert taken == [f"flakelet remove {GONE_NAME} 2>&1"]
    # The name the endpoint registered, which the machine answered, and not the
    # identity a line carries nor any path of the holding's own artifact: that
    # artifact belongs to a build this run is not applying.
    assert GONE_KEY not in taken[0]
    assert "/nix/store" not in taken[0]
    assert str(tmp_path) not in taken[0]
    assert "detach" not in taken[0]


def test_a_retirement_precedes_every_value_write_and_every_activation_of_the_run(
    tmp_path: Path,
) -> None:
    """A holding owns the host resources the entry replacing a renamed one claims."""
    deployment = _built(
        tmp_path / "built",
        plan=PLAN,
        entries={
            CLIENT_KEY: _stated(CLIENT_KEY, "beta", "10.0.0.11"),
            SERVER_KEY: _stated(SERVER_KEY, "alpha", "10.0.0.10"),
        },
        values={SESSION_VALUE: {"delivery": ["alpha", "beta"], "files": TOKEN}},
    )
    source = _source(tmp_path / "values", {f"{SESSION_VALUE}/token": "s3cret"})
    machine = Holds(_one_holding(), at="10.0.0.10")

    log = apply.apply(deployment, machine, source=source, retire=True, base_env={})

    steps = _steps(log)
    retirement = [at for at, line in enumerate(steps) if line.startswith("retire ")]
    assert len(retirement) == 1
    for mutation in ("value ", "copy ", "activate "):
        put = [at for at, line in enumerate(steps) if line.startswith(mutation)]
        assert put and retirement[0] < min(put), steps


def test_an_entry_left_out_of_a_restricted_run_is_not_retired(tmp_path: Path) -> None:
    """An entry the deployment places is no holding, whichever entries a run applies."""
    log, machine = _retiring(
        tmp_path,
        _holds(
            (
                "flakelet",
                0,
                _registered(
                    _registration(SERVER_KEY, "site-server"),
                    _registration(CLIENT_KEY, "check-client"),
                ),
            ),
        ),
        entries=_on_alpha(SERVER_KEY, CLIENT_KEY),
        only=(SERVER_KEY,),
    )

    assert _retirements(machine) == []
    assert [line for line in log if line.startswith("retire ")] == []
    assert _activated(log) == [SERVER_KEY]


def test_a_restriction_naming_a_holding_the_deployment_does_not_place_is_refused(
    tmp_path: Path,
) -> None:
    """A holding is not addressable as a plan key of this build."""
    deployment = _built(tmp_path, plan=PLAN, entries=_on_alpha(SERVER_KEY))
    machine = Holds(_one_holding())

    with pytest.raises(errors.ApplyError) as raised:
        apply.apply(deployment, machine, only=(GONE_KEY,), retire=True, base_env={})

    message = str(raised.value)
    assert GONE_KEY in message
    assert SERVER_KEY in message
    assert machine.commands == []


def test_a_build_naming_no_entry_on_a_machine_retires_nothing_there(tmp_path: Path) -> None:
    """A build carries an address only for a machine it places an entry on."""
    log, machine = _retiring(tmp_path, _one_holding())

    dialled = " ".join(" ".join(cmd) for cmd in machine.commands)
    assert "10.0.0.11" not in dialled
    assert _retirements(machine) == [f"flakelet remove {GONE_NAME} 2>&1"]
    assert _activated(log) == [SERVER_KEY]


def test_a_machine_that_answers_nothing_is_left_to_fail_at_its_own_step(tmp_path: Path) -> None:
    """ssh's own silence is a machine that is unreachable, not an answer nobody can read.

    A machine whose sshd is down answers the question of what it holds with
    nothing, and a run that refused there would take no step at all, so its last
    line would name no step against that machine and the recovery of a run
    broken between two machines could not be read off it.
    """
    deployment = _built(
        tmp_path,
        plan={**PLAN, CLIENT_KEY: {"reads": {"site": {"entry": SERVER_KEY}}}},
        entries={
            CLIENT_KEY: _stated(CLIENT_KEY, "beta", "10.0.0.11"),
            SERVER_KEY: _stated(SERVER_KEY, "alpha", "10.0.0.10"),
        },
    )
    silent = Silent("10.0.0.11", remote.UNREACHABLE, "ssh: connect to host 10.0.0.11: refused")
    printed: list[str] = []

    with pytest.raises(errors.ApplyError) as raised:
        apply.apply(deployment, silent, base_env={}, log=printed.append)

    # The step line of a step that never completed is the run's last word about
    # it, so the run got as far as the first step against that machine.
    steps = [line for line in printed if not line.startswith(("  ", "failed "))]
    assert steps[-1].startswith(f"activate {CLIENT_KEY} ")
    assert printed[-1].startswith("failed ")
    message = str(raised.value)
    assert "10.0.0.11" in message
    assert "what it holds" not in message


ENROLLMENT_VALUE = "mesh:vars/enrollment"

# The bytes a coordination server admits one machine on. The operator reads
# them out of the value source and hands them over outside the tree, so the
# source is the one place they are, and a run that delivers them nowhere is a
# run no step of which can have spoken them.
CREDENTIAL = b"\x00authkey-7be2c1d40f9a\xff"


def test_no_argv_of_a_run_carries_the_credential(tmp_path: Path) -> None:
    """A credential delivered to nobody is in no vector of a run that delivers.

    The run has a value to write and an entry to activate, so what it recorded
    is a real run's vectors rather than an empty list, and the source it was
    handed holds the credential beside the delivered value. Every encoding a
    step could have reached for is asked of every word of every vector, which
    is the assertion a delivered secret already earns.
    """
    credential = {
        "per": "instance",
        "deploy": False,
        "delivery": [],
        "program": PROGRAM,
        "files": {"preauthkey": _delivered("/run/vars/mesh/enrollment/preauthkey", "secret")},
    }
    deployment = _built(
        tmp_path / "built",
        plan={**PLAN, ENROLLMENT_VALUE: credential},
        entries={SERVER_KEY: _stated(SERVER_KEY, "alpha", "10.0.0.10")},
        values={
            SESSION_VALUE: {"delivery": ["alpha"], "files": TOKEN},
            ENROLLMENT_VALUE: credential,
        },
    )
    source = _bytes_source(
        tmp_path / "values",
        {f"{SESSION_VALUE}/token": SECRET, f"{ENROLLMENT_VALUE}/preauthkey": CREDENTIAL},
    )
    recorder = Reporting()

    log = apply.apply(deployment, recorder, source=source, base_env={})

    steps = _steps(log)
    assert [line for line in steps if line.startswith("value ")]
    assert _activated(log) == [SERVER_KEY]
    # No step named the credential either: a run that wrote it somewhere would
    # have carried its path, whatever the bytes travelled on.
    spoken = [word for command in recorder.commands for word in command]
    assert not [word for word in spoken if "enrollment" in word]
    for word in spoken:
        said = word.encode(errors="surrogateescape")
        for what, needle in _leaks(CREDENTIAL).items():
            assert needle not in said, f"{what} of the credential is in {word}"
