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
import subprocess
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

SERVER_ENTRY = "site:server"
SERVER_KEY = "site:server@alpha"
CLIENT_KEY = "check:client@beta"

SESSION_VALUE = "issuer:vars/session"
CA_VALUE = "issuer:vars/ca"

TOKEN = {"token": {"path": "/run/vars/issuer/session/token", "secrecy": "secret"}}
PROGRAM = "/nix/store/3k9m2x7vqz1n5bpr4jlfg8ys6cwh0d2a-mint-token.drv"

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
        if "path" not in stated:
            continue
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
    """A recorder that answers an activation the way the endpoint answers one."""

    def output(self, cmd: list[str], *, env: dict[str, str] | None = None) -> str:
        self.commands.append(cmd)
        return "started site-server-serve.service"


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
        "  started site-server-serve.service"
    ] * 2


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
        "files": {"key": {"path": "/run/vars/issuer/root/key", "secrecy": "secret"}},
    },
    TOKEN_VALUE: {
        "key": TOKEN_IDENTITY,
        "per": "instance",
        "deploy": True,
        "delivery": ["alpha", "beta"],
        "reads": [ROOT_VALUE],
        "program": GENERATOR,
        "files": {
            "secret": {"path": "/run/vars/issuer/token/secret", "secrecy": "secret"},
            "fingerprint": {"path": "/run/vars/issuer/token/fingerprint", "secrecy": "public"},
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
    root = _record(tmp_path, {"version": 2, "storeDir": manifest.store_dir(), "entries": {}})
    recorder = Recorder()

    with pytest.raises(errors.ApplyError) as raised:
        apply.apply(manifest.read(root), recorder, base_env={})

    message = str(raised.value)
    assert "version 2" in message
    assert f"version {manifest.VERSION}" in message
    assert recorder.commands == []


def test_a_record_names_a_store_the_command_does_not_run_against(tmp_path: Path) -> None:
    """Artifact paths of another store are paths this command cannot copy."""
    root = _record(tmp_path, {"version": 1, "storeDir": "/gnu/store", "entries": {}})
    recorder = Recorder()

    with pytest.raises(errors.ApplyError) as raised:
        apply.apply(manifest.read(root), recorder, base_env={})

    message = str(raised.value)
    assert "/gnu/store" in message
    assert manifest.store_dir() in message
    assert recorder.commands == []


def test_a_record_carries_no_table_of_entries(tmp_path: Path) -> None:
    """A misspelled table is a record to refuse, never a deployment placing nothing."""
    shape = {"version": 1, "storeDir": manifest.store_dir(), "values": {}}
    misspelled = _record(tmp_path / "misspelled", {**shape, "entires": {}})

    with pytest.raises(errors.ApplyError) as raised:
        manifest.read(misspelled)

    message = str(raised.value)
    assert str(misspelled / manifest.MANIFEST) in message
    assert "entries" in message

    empty = manifest.read(_record(tmp_path / "empty", {**shape, "entries": {}}))
    assert empty.entries == {}


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

    _, activation = recorder.commands
    assert "BatchMode=yes" in activation
    assert "ServerAliveInterval=30" in activation
    assert "ServerAliveCountMax=3" in activation
    assert activation.index("ConnectTimeout=1") < activation.index("ConnectTimeout=10")


REFUSED = "No space left on device"


class Failing(Recorder):
    """A recorder whose machine refuses every step whose argv holds ``at``."""

    def __init__(self, at: str) -> None:
        super().__init__()
        self.at = at

    def run(self, cmd: list[str], *, env: dict[str, str] | None = None) -> object:
        self._refuse(cmd)
        return super().run(cmd, env=env)

    def output(self, cmd: list[str], *, env: dict[str, str] | None = None) -> str:
        self._refuse(cmd)
        return super().output(cmd, env=env)

    def _refuse(self, cmd: list[str]) -> None:
        if self.at in " ".join(cmd):
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
    assert [command[:2] for command in failing.commands] == [["nix", "copy"], ["ssh", "-o"]]
    assert all("10.0.0.11" not in " ".join(command) for command in failing.commands)


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
    """A recorder whose machine answers ``said`` to the script naming ``asked``."""

    def __init__(self, asked: str, said: str) -> None:
        super().__init__()
        self.asked = asked
        self.said = said

    def output(self, cmd: list[str], *, env: dict[str, str] | None = None) -> str:
        answered = super().output(cmd, env=env)
        return self.said if self.asked in " ".join(cmd) else answered


def test_an_image_the_machine_already_holds_attached_is_not_attached_twice(
    tmp_path: Path,
) -> None:
    """`portablectl` refuses an image it holds, so a second run asks before it attaches."""
    deployment = _built(
        tmp_path,
        plan={**PLAN, CLIENT_KEY: {"reads": {"site": {"entry": SERVER_KEY}}}},
        entries={
            CLIENT_KEY: _stated(CLIENT_KEY, "beta", "10.0.0.11"),
            SERVER_KEY: {**_stated(SERVER_KEY, "alpha", "10.0.0.10"), "realiser": "image"},
        },
    )
    image = manifest.artifact_of(deployment.entries[SERVER_KEY])
    (image / "attachment.json").write_text(json.dumps({"image": "site-server.raw"}))
    recorder = Answering("portablectl is-attached", "running\n")

    log = apply.apply(deployment, recorder, base_env={})

    dialled = [" ".join(command) for command in recorder.commands]
    assert all(f"{image}/bin/attach" not in command for command in dialled)
    assert f"attached {SERVER_KEY} already on root@10.0.0.10" in log
    assert _activated(log) == [CLIENT_KEY]


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
    """A step that wants the artifact refuses naming that entry and no other."""
    deployment = _publishes_only(tmp_path)
    recorder = Recorder()

    with pytest.raises(errors.ApplyError) as raised:
        report.rollback(deployment, recorder, CLIENT_KEY)

    message = str(raised.value)
    assert CLIENT_KEY in message
    assert "declares no unit" in message
    assert SERVER_KEY not in message
    assert recorder.commands == []


HELD = json.dumps(
    [
        {
            "generation": 2,
            "locked_url": "path:/nix/store/1x8k?narHash=sha256-4444",
            "last_error": "unit site-server-serve.service failed to start",
        }
    ]
)


def test_an_entry_the_endpoint_recorded_a_failure_for_is_not_reported_as_healthy(
    tmp_path: Path,
) -> None:
    """The line is the endpoint's whole record, so an error it holds is in it."""
    deployment = _built(
        tmp_path,
        plan=PLAN,
        entries={SERVER_KEY: _stated(SERVER_KEY, "alpha", "10.0.0.10")},
    )
    answering = Answering("flakelet status", HELD)

    reported = report.status(deployment, answering, base_env={})

    assert reported.lines == (
        f"{SERVER_KEY} flakelet generation 2 of path:/nix/store/1x8k?narHash=sha256-4444, "
        f"last error unit site-server-serve.service failed to start",
    )
    assert reported.unasked == ()


class Silent(Recorder):
    """A recorder whose machines exit ``status`` with ``said`` for the machine in ``at``."""

    def __init__(self, at: str, status: int, said: str) -> None:
        super().__init__()
        self.at = at
        self.status = status
        self.said = said

    def output(self, cmd: list[str], *, env: dict[str, str] | None = None) -> str:
        answered = super().output(cmd, env=env)
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
