"""The harness's own code: the delivery driver's pure functions and the runner.

This file asserts nothing about the planner. It is beside the harness because
the harness is code too, and its pure half - which machine a key names, which
address a delivery dials, what the copy runs in, which end-to-end tests exist -
is a function of its arguments and needs no machine.

What the driver does to a booted machine is asserted in the folders beside this
one, on real machines, which is the only place it can be asserted honestly.
"""

from __future__ import annotations

import json
from pathlib import Path

import pytest

import delivery
import runner

SERVER_ENTRY = "site:server"
SERVER_KEY = "site:server@alpha"
CLIENT_KEY = "check:client@beta"

# A plan is a document. These are the four records the functions below read,
# written out rather than built, so this file names no artifact.
PLAN = {
    "machine:alpha": {"address": "10.0.0.10", "tags": ["cluster"]},
    "machine:beta": {"address": "10.0.0.11", "tags": ["cluster"]},
    SERVER_KEY: {"key": "sha256-1111111111111111"},
    CLIENT_KEY: {"key": "sha256-2222222222222222"},
}


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


def test_the_delivery_environment_carries_the_key_and_no_host_file() -> None:
    """The copy runs in a single-uid namespace, where a root-owned config is refused."""
    env = delivery.delivery_env({"PATH": "/usr/bin"}, "/tmp/id_ed25519")
    assert env["PATH"] == "/usr/bin"
    assert "-F /dev/null" in env["NIX_SSHOPTS"]
    assert "-i /tmp/id_ed25519" in env["NIX_SSHOPTS"]
    assert "UserKnownHostsFile=/dev/null" in env["NIX_SSHOPTS"]
    assert "GlobalKnownHostsFile=/dev/null" in env["NIX_SSHOPTS"]


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
