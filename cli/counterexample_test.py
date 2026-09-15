"""Counterexamples to the invariants the operator's command states about itself.

Each test below pins one sentence `CLAUDE.md` or a module docstring of `cli/` states as a
guarantee, asserts that sentence rather than what the code does today, and therefore fails
today: the comment above each assertion names the source the invariant is read off, and the
docstring says the invariant in one line. Every record is a real `Deployment`, `Entry` or
`Value` and every remote step goes through a local recorder, so a failure is the command's own
decision and never a mock's. A test turns green when the sentence it pins becomes true; none of
them is a pin on a message, so a fix may word its refusal however it likes.
"""

from __future__ import annotations

import json
import os
from pathlib import Path
from typing import Any

import apply
import manifest
import order
import remote
import report
import values
from errors import ApplyError
from manifest import Deployment, Entry, Value, ValueFile

MACHINE = "alpha"
ADDRESS = "alpha.example"
DIGEST = "deadbeefdeadbeef"


class Channel:
    """The remote channel of a run, recording every argv and answering one fixed line."""

    def __init__(self, said: str = "") -> None:
        """Answer ``said`` to every step, and keep the argv and the payload of each.

        Args:
            said: What every machine says to every step.
        """
        self.calls: list[list[str]] = []
        self.payloads: list[bytes | None] = []
        self.said = said

    def run(
        self, cmd: list[str], *, env: dict[str, str] | None = None, stdin: bytes | None = None
    ) -> object:
        """Record one step that reads nothing back."""
        self.calls.append(list(cmd))
        self.payloads.append(stdin)
        return None

    def output(
        self, cmd: list[str], *, env: dict[str, str] | None = None, stdin: bytes | None = None
    ) -> str:
        """Record one step and answer what this channel says."""
        self.calls.append(list(cmd))
        self.payloads.append(stdin)
        return self.said


def flakelet_artifact(root: Path) -> Path:
    """Return a flakelet artifact directory, with the two files the command reads."""
    artifact = root / "flakelet-artifact"
    (artifact / "units").mkdir(parents=True)
    (artifact / "meta.json").write_text(json.dumps({"name": "svc"}))
    (artifact / "units" / "main.service").write_text("[Unit]\n")
    return artifact


def image_artifact(root: Path, image: str) -> Path:
    """Return an image artifact directory whose attachment names ``image``."""
    artifact = root / "image-artifact"
    (artifact / "bin").mkdir(parents=True)
    (artifact / "attachment.json").write_text(json.dumps({"image": image}))
    return artifact


def placed(
    key: str,
    artifact: Path | None,
    *,
    realiser: str = "flakelet",
    address: str | None = ADDRESS,
    digest: str = DIGEST,
) -> Entry:
    """Return one placed entry of a deployment record."""
    return Entry(
        key=key,
        path=artifact,
        realiser=realiser,
        profile=None,
        machine=MACHINE,
        address=address,
        units=("main.service",),
        digest=digest,
    )


def built(
    plan: dict[str, Any],
    entries: dict[str, Entry],
    generated: dict[str, Value] | None = None,
) -> Deployment:
    """Return a built deployment over ``plan``, carrying no diagnostics."""
    return Deployment(
        root=Path("/nonexistent"),
        plan=plan,
        entries=entries,
        values={} if generated is None else generated,
        diagnostics=(),
        table="",
    )


def secret_value(key: str, path: str) -> Value:
    """Return one generated value of a single secret file, delivered to the machine."""
    return Value(
        key=key,
        delivery=(MACHINE,),
        program=None,
        files=(
            ValueFile(
                name="token",
                path=path,
                secrecy="secret",
                owner="root",
                group="root",
                mode="0400",
            ),
        ),
    )


def test_a_set_valued_read_of_a_secret_rotates_its_consumer(tmp_path: Path) -> None:
    """A read that orders an apply is a read that rotates its consumer.

    Args:
        tmp_path: The artifact and the value source of this run.
    """
    artifact = flakelet_artifact(tmp_path)
    path = "/run/vars/issuer/session/token"
    value = secret_value("issuer:vars/session", path)
    # `reach = "all"` records its providers as `entries` keyed by plan key, so a secret export
    # of one of them sits at `entries.<provider>.<export>` rather than at `values.<export>`.
    read = {
        "delivered": True,
        "reach": "all",
        "reads": ["token"],
        "entries": {"issuer:api@alpha": {"token": {"path": path, "secrecy": "secret"}}},
    }
    plan: dict[str, Any] = {
        f"machine:{MACHINE}": {"address": ADDRESS},
        "issuer:api@alpha": {"placement": {}},
        "reader:app@alpha": {"placement": {}, "reads": {"creds": read}},
        "issuer:vars/session": {"delivery": [MACHINE], "files": {"token": {"path": path}}},
    }
    entries = {key: placed(key, artifact) for key in ("issuer:api@alpha", "reader:app@alpha")}
    deployment = built(plan, entries, {"issuer:vars/session": value})
    source = tmp_path / "source"
    (source / value.key).mkdir(parents=True)
    (source / value.key / "token").write_bytes(b"s3cret")

    # CLAUDE.md: "the readers are the entries whose resolved reads name that value on that
    # machine, which is the same index `cli/order.py` builds its edges from".
    assert order.edges(plan, sorted(entries)) == (("issuer:api@alpha", "reader:app@alpha"),)
    lines = apply.apply(deployment, Channel("changed"), source=source, base_env={})
    restarts = [line for line in lines if line.startswith("restart ")]
    assert restarts, f"the value moved and nothing was restarted; steps were {lines}"


def test_an_endpoint_answer_that_is_not_a_status_is_the_commands_own_refusal(
    tmp_path: Path,
) -> None:
    """An endpoint answer that is not its own status is an ApplyError.

    Args:
        tmp_path: The artifact of the entry being asked about.
    """
    artifact = flakelet_artifact(tmp_path)
    deployment = built(
        {f"machine:{MACHINE}": {"address": ADDRESS}}, {"i:a@alpha": placed("i:a@alpha", artifact)}
    )

    for said in ('{"generation": 3, "locked_url": "u", "units": {}}', "7", "3.5"):
        # cli/report.py, `status`: "Raises: ApplyError: ... or an endpoint answered something
        # that is not its own status." cli/planner.py: "A refusal reaches the operator as a
        # message on stderr and a non-zero exit."
        try:
            report.status(deployment, Channel(said), base_env={})
        except ApplyError:
            continue
        except Exception as broke:
            raise AssertionError(f"{said!r} raised {type(broke).__name__}: {broke}") from broke
        raise AssertionError(f"{said!r} was read as the endpoint's own status")


def test_an_image_report_names_the_identity_of_the_entrys_own_image(tmp_path: Path) -> None:
    """An image comparison is identity equality against the entry's own image.

    Args:
        tmp_path: The artifact of the image entry.
    """
    artifact = image_artifact(tmp_path, f"svc_{DIGEST}.raw")
    entry = placed("i:b@alpha", artifact, realiser="image")
    deployment = built({f"machine:{MACHINE}": {"address": ADDRESS}}, {entry.key: entry})
    # `portablectl is-attached` answers about this build's own image, and the listing carries
    # this build's identity beside a leftover attachment of an earlier one.
    said = (
        "running\n"
        "images\n"
        "svc_0000000000000000 raw portable attached\n"
        f"svc_{DIGEST} raw portable running\n"
    )

    line = report.status(deployment, Channel(said), base_env={}).lines[0]
    # CLAUDE.md: "the record's `key` is the artifact's version digest, an image's file name
    # carries it and `portablectl list` prints it, so that half is identity equality".
    assert "0000000000000000" not in line, line
    assert line.endswith("current"), line


def test_an_artifact_path_that_leaves_the_build_is_refused(tmp_path: Path) -> None:
    """A manifest addresses an artifact inside the build and nothing outside it.

    Args:
        tmp_path: The build directory and the directory beside it.
    """
    build = tmp_path / "build"
    build.mkdir()
    (tmp_path / "outside").mkdir()
    (build / "plan.json").write_text("{}")
    # The escape is built rather than written: tests/unit/layers.nix scans every file
    # for a path token that resolves to nothing, and a literal one would be flagged.
    escaping = str(Path(os.pardir) / "outside")
    for stated in (escaping, "/etc"):
        record = {
            "realiser": "flakelet",
            "machine": MACHINE,
            "address": ADDRESS,
            "units": ["main.service"],
            "key": DIGEST,
            "path": stated,
        }
        (build / "manifest.json").write_text(
            json.dumps(
                {
                    "version": manifest.VERSION,
                    "storeDir": manifest.store_dir(),
                    "entries": {"i:a@alpha": record},
                }
            )
        )
        # CLAUDE.md: "`manifest.json` addresses an artifact inside the build ... The path an
        # activation names on the machine has to be the path the copy put there."
        try:
            read = manifest.read(build)
        except ApplyError:
            continue
        raise AssertionError(f"path {stated!r} was accepted as {read.entries['i:a@alpha'].path}")


def test_a_delivered_read_in_neither_shape_is_refused(tmp_path: Path) -> None:
    """A delivered read recorded in neither shape is a refusal, never zero edges.

    Args:
        tmp_path: The artifact both entries are built into.
    """
    artifact = flakelet_artifact(tmp_path)
    provider, consumer = "store:db@alpha", "app:web@alpha"
    # A resolved read that is not a record at all: recorded in neither the `entry` shape nor
    # the `entries` one, and never reached by the `delivered` gate that refuses the others.
    plan: dict[str, Any] = {
        f"machine:{MACHINE}": {"address": ADDRESS},
        consumer: {"placement": {}, "reads": {"db": provider}},
        provider: {"placement": {}},
    }
    entries = {key: placed(key, artifact) for key in (provider, consumer)}

    # CLAUDE.md: "A delivered read recorded in neither shape is the command's own refusal
    # naming the consumer and the slot, because an unrecognised shape that contributes zero
    # edges is what let that stand."
    try:
        walked = order.walk(plan, sorted(entries))
    except ApplyError:
        return
    assert walked.order.index(provider) < walked.order.index(consumer), walked.order


def test_absence_is_an_endpoints_own_answer_and_nothing_else(tmp_path: Path) -> None:
    """Absence is the endpoint registering no entry, and nothing else gives it.

    Args:
        tmp_path: The artifact of the entry being asked about.
    """
    artifact = flakelet_artifact(tmp_path)
    deployment = built(
        {f"machine:{MACHINE}": {"address": ADDRESS}}, {"i:a@alpha": placed("i:a@alpha", artifact)}
    )

    assert report.status(deployment, Channel("[]"), base_env={}).lines[0].endswith("absent")
    for said in ("null", "0", "false", "{}"):
        # CLAUDE.md: "Absence is an endpoint's own answer and nothing else's." An answer that
        # registers nothing is not an answer that the deployment was never applied.
        try:
            line = report.status(deployment, Channel(said), base_env={}).lines[0]
        except ApplyError:
            continue
        assert not line.endswith("absent"), f"{said!r} was reported as {line!r}"


def test_a_refusal_names_the_machine_and_not_an_ssh_option() -> None:
    """A refusal names the machine an argv addresses, and no other word of it."""
    # An ordinary operator option whose value carries an `@`, appended to by the command.
    opts = remote.ssh_opts(None, inherited="-o Ciphers=aes256-gcm@openssh.com")
    argv = remote.ssh_argv(ADDRESS, "true", opts=opts)

    # cli/remote.py, `destination`: "Return the machine an argv addresses, which is all of it a
    # refusal names."
    assert remote.destination(argv) == f"root@{ADDRESS}"


def test_every_undeclared_file_inside_a_values_directory_is_named(tmp_path: Path) -> None:
    """Every undeclared file inside a value entry's own directory is named.

    Args:
        tmp_path: The value source and the directory its subdirectory links to.
    """
    key = "issuer:vars/session"
    value = secret_value(key, "/run/vars/issuer/session/token")
    deployment = built({}, {}, {key: value})
    source = tmp_path / "source"
    (source / key).mkdir(parents=True)
    (source / key / "token").write_bytes(b"s3cret")
    linked = tmp_path / "linked"
    linked.mkdir()
    (linked / "stray").write_bytes(b"x")
    (source / key / "sub").symlink_to(linked, target_is_directory=True)
    assert (source / key / "sub" / "stray").read_bytes() == b"x"

    # CLAUDE.md: "The value source is measured under the directories of the value entries the
    # deployment delivers ... every undeclared file inside one is named rather than the first
    # of them."
    try:
        values.check(deployment, source, [key])
    except ApplyError as refused:
        assert "sub/stray" in str(refused), refused
        return
    raise AssertionError("a file inside the value's own directory claimed nothing")
