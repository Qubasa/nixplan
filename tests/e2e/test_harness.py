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
can be asserted honestly.
"""

from __future__ import annotations

import json
from pathlib import Path
from typing import Any

import pytest

import apply
import delivery
import errors
import manifest
import runner

SERVER_ENTRY = "site:server"
SERVER_KEY = "site:server@alpha"
CLIENT_KEY = "check:client@beta"

SESSION_VALUE = "issuer:vars/session"
CA_VALUE = "issuer:vars/ca"

TOKEN = {"token": {"path": "/run/vars/issuer/session/token", "secrecy": "secret"}}

PLAN = {
    "machine:alpha": {"address": "10.0.0.10", "tags": ["cluster"]},
    "machine:beta": {"address": "10.0.0.11", "tags": ["cluster"]},
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
        "files": {"ca.pub": {"path": "/run/vars/issuer/ca/ca.pub", "secrecy": "public"}},
    },
}


class Recorder:
    """A runner that records the argv it was handed instead of running it."""

    def __init__(self) -> None:
        self.commands: list[list[str]] = []

    def run(self, cmd: list[str], *, env: dict[str, str] | None = None) -> object:
        self.commands.append(cmd)
        return env

    def output(self, cmd: list[str], *, env: dict[str, str] | None = None) -> str:
        self.commands.append(cmd)
        return ""


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
        "key": "sha256-3333333333333333",
    }


def _built(
    root: Path,
    *,
    plan: dict[str, Any],
    entries: dict[str, dict[str, Any]],
    values: dict[str, dict[str, Any]] | None = None,
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
        rows: The diagnostics rows.
        table: The rendered diagnostics table.

    Returns:
        The deployment, read back from what was written.
    """
    root.mkdir(parents=True, exist_ok=True)
    (root / "plan.json").write_text(json.dumps(plan))
    (root / "manifest.json").write_text(
        json.dumps(
            {
                "version": 1,
                "storeDir": "/nix/store",
                "entries": entries,
                "values": values or {},
            }
        )
    )
    (root / "diagnostics.json").write_text(json.dumps(rows or []))
    (root / "diagnostics.txt").write_text(table)
    # A symlink to a directory beside the build, because that is what a build is:
    # a farm of links into the store, and what the command copies and activates
    # is what a link resolves to.
    for key, stated in entries.items():
        artifact = root / "artifacts" / Path(stated["path"]).name
        artifact.mkdir(parents=True)
        instance, service = key.split("@")[0].split(":")
        (artifact / "meta.json").write_text(json.dumps({"name": f"{instance}-{service}"}))
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

    copy, activation = recorder.commands
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
