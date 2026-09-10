"""A reader's own machine, a template copied onto it, and the two machines it deploys.

``nix run .#planner-e2e newcomer`` runs this. Every other folder of this layer
proves a property of a deployment; this one proves that somebody who is not this
repository can use it, and it proves that on a machine rather than here. Three
machines boot: a workstation, which is nobody's target and belongs to no plan,
and ``alpha`` and ``beta``, which are the two machines the template deploys to.

Nothing of the walk happens on the host. What the host does is hand the
workstation two store paths - this checkout's tracked content, and the key the
image authorizes - and every step after that is a command the workstation runs:

1. ``nix flake lock --override-input``, which is where the template stops naming
   the published flake and starts naming the copy under test
2. ``nix run path:<source> -- build``, which substitutes what the machine's store
   lacks, evaluates the deployment and builds it in that store
3. ``nix run path:<source> -- apply``, which copies each artifact to the machine
   its entry names and activates it there
4. ``nix run path:<source> -- status``, which asks both machines what they hold

The template is the load-bearing artifact. ``template/flake.nix`` carries the
published input url verbatim, because that is the line a reader outside this
repository writes, and the run never edits it: the override is recorded in the
lock, and `test_the_template_names_the_published_flake` reads the lock rather
than trusting the substitution. Everything else under ``template/`` is a file a
reader writes for themselves, which is why the folder's own
``deployment/default.nix`` imports that copy instead of holding a second one.

This is the one cluster of the layer that is not hermetic (``offline=False``). The
claim is that a machine holding nothing but the template and this repository's
source can obtain what it needs, and a cluster with no upstream would answer that
claim with a local cache. The bytes it goes out for are the command's own
interpreter and the build's inputs, some 340 MB of them; the nixpkgs *source* is
already in the image, because a NixOS system pins its own flake in the registry,
so a locked input whose hash is already valid in the store is never downloaded.
Egress is checked before anything else and the module skips itself without it:
there is nothing here to observe on a machine that cannot fetch, and a green run
would be a lie.

The preparation boots and yields, so the fetch, the build and the apply happen on
every run. Moving any of them into the preparation would cache the evidence and
leave these tests reading a replay.

rookery is imported at run time rather than statically: it is resolved from
``$ROOKERY_FLAKE`` by the runner and is deliberately not an input of this flake,
so the module skips itself when it is absent.
"""

from __future__ import annotations

import json
import os
import shlex
import subprocess
from collections.abc import Iterator
from dataclasses import dataclass
from pathlib import Path
from typing import Any

import pytest

import delivery

snapshot = pytest.importorskip(
    "rookery.snapshot",
    reason='rookery is not importable: run .#planner-e2e, or eval "$(planner-e2e-env)"',
)


def _env_path(variable: str) -> Path:
    """The path a variable names, or skip the module: it needs the built layer."""
    value = os.environ.get(variable)
    if value is None:
        pytest.skip(f"{variable} is unset; run this through .#planner-e2e", allow_module_level=True)
    return Path(value)


FLAKE = _env_path("PLANNER_E2E_FLAKE")
GUEST_IMAGE = _env_path("PLANNER_E2E_GUEST_IMAGE")
CREDENTIAL = _env_path("PLANNER_E2E_SSH_KEY")
KEY = delivery.ssh_key(delivery.state_root(), CREDENTIAL)

WORKSTATION = "workstation"
TARGETS = ("alpha", "beta")
MACHINES = (WORKSTATION, *TARGETS)

ENTRY = "greeter:greet"
UNIT = "greeter-greet-say.service"
GREETING = "/run/hello.greeting"
REALISER = "flakelet"

# Where the workstation keeps the two things it is handed. The template becomes a
# writable directory of its own, because a flake nix locks is a flake nix writes a
# lock into, and a store path is read-only.
CONSUMER = "/root/consumer"

# The same template with one mistake in it, and the mistake: a closure root that
# is not a path under the store the plan is read against.
REFUSED = "/root/refused"
OUTSIDE = "/opt/vendor/greeter"
GUEST_KEY = "/root/id_ed25519"
TEMPLATE = "tests/e2e/newcomer/template"

SUBSTITUTER = "https://cache.nixos.org"

# One nixpkgs fetch, one evaluation of it and one deployment build, on two virtual
# cores. The cap is what distinguishes a slow first run from a wedged one.
PATIENT = 1800.0
BRIEF = 300.0


@dataclass(frozen=True)
class Workstation:
    """The machine the walk runs on, and the source it was handed."""

    vm: Any
    source: str


@dataclass(frozen=True)
class Reported:
    """One line of ``planner build``: an entry, and what was built for it."""

    key: str
    realiser: str
    machine: str
    address: str
    path: str
    units: tuple[str, ...]


def _reported(line: str) -> Reported:
    """Read one line of the build's table.

    Args:
        line: A line as `cli/report.py` renders it: the key, the realiser, the
            machine, its address, the artifact, then the units in brackets.

    Returns:
        The line's fields.
    """
    key, realiser, machine, address, path, units = line.split(" ", 5)
    return Reported(
        key=key,
        realiser=realiser,
        machine=machine,
        address=address,
        path=path,
        units=tuple(units.strip("[]").split()),
    )


def _host(*argv: str, timeout: float = BRIEF) -> str:
    """Run a command on this host and return its stdout.

    Args:
        argv: The command and its arguments.
        timeout: Seconds to allow.

    Returns:
        The command's stdout.

    Raises:
        RuntimeError: If it refused, carrying its own message.
    """
    done = subprocess.run(argv, capture_output=True, text=True, check=False, timeout=timeout)
    if done.returncode != 0:
        raise RuntimeError(f"{shlex.join(argv)} failed:\n{done.stderr.strip()}")
    return done.stdout


def _source_of(flake: Path) -> str:
    """The store path this checkout's tracked content resolves to.

    This is the one thing the host computes: which bytes the workstation is given.
    A `path:` reference to the checkout would copy the ignored trees beside it, and
    a `git+file:` reference would pin `HEAD` and quietly hand over the last commit
    rather than the tree under test.

    Args:
        flake: The checkout.

    Returns:
        The store path of its tracked content.
    """
    return str(json.loads(_host("nix", "flake", "metadata", "--json", str(flake)))["path"])


def test_the_flake_names_its_outputs() -> None:
    """The command that lists a flake's outputs answers for every system claimed.

    The listing walks the three doubles this flake writes out, which is what
    taking the list from an input naming a fourth the package set removed cost:
    the walk died in a release note before it printed one output. The route ends
    at something a reader can type next, so the flake with no attribute named
    runs the command and the command's own help names its subcommands.
    """
    shown = json.loads(_host("nix", "flake", "show", "--json", str(FLAKE)))
    claimed = ["aarch64-darwin", "aarch64-linux", "x86_64-linux"]

    assert sorted(shown["apps"]) == claimed, sorted(shown["apps"])
    assert sorted(shown["packages"]) == claimed, sorted(shown["packages"])
    for system in claimed:
        assert "planner" in shown["apps"][system], shown["apps"][system]
        assert "default" in shown["apps"][system], shown["apps"][system]
        assert "planner" in shown["packages"][system], sorted(shown["packages"][system])

    helped = _host("nix", "run", str(FLAKE), "--", "--help", timeout=PATIENT)
    for subcommand in ("plan", "build", "apply", "status", "rollback"):
        assert f"    {subcommand}" in helped, helped


def test_a_consumer_reads_the_build_off_an_output() -> None:
    """Planning and building are both output names, and neither is a source path.

    Both sit outside the per-system attributes, because the build takes the
    caller's own package set: a consumer on one double building for another reads
    one name rather than one name per double.
    """
    shown = json.loads(_host("nix", "flake", "show", "--json", str(FLAKE)))
    assert "lib" in shown, sorted(shown)
    assert "operator" in shown, sorted(shown)

    library = json.loads(
        _host("nix", "eval", "--json", f"{FLAKE}#lib", "--apply", "builtins.attrNames")
    )
    assert {"interface", "registry", "render", "service", "platform"} <= set(library), library

    build = json.loads(
        _host("nix", "eval", "--json", f"{FLAKE}#operator", "--apply", "builtins.attrNames")
    )
    assert "mkDeployment" in build, build
    assert (
        _host(
            "nix",
            "eval",
            f"{FLAKE}#operator",
            "--apply",
            "built: builtins.isFunction built.mkDeployment",
        ).strip()
        == "true"
    )


def test_one_published_name_answers_two_different_things() -> None:
    """The name the root advertises answers with the program, whoever asks.

    `nix build` reads the packages and then the flake's own top-level attributes,
    so a development attrset published as `planner` answered it with `found a
    set` while `nix run` answered with the command. The name is the program's.
    """
    built = Path(
        _host(
            "nix",
            "build",
            "--no-link",
            "--print-out-paths",
            f"{FLAKE}#planner",
            timeout=PATIENT,
        )
        .strip()
        .splitlines()[-1]
    )
    assert (built / "bin" / "planner").is_file(), built

    shown = json.loads(_host("nix", "flake", "show", "--json", str(FLAKE)))
    assert "planner" not in shown, sorted(shown)


def test_the_test_results_are_reachable_under_a_name_of_their_own() -> None:
    """The suites, their failures and the worked plan are read off one name.

    That name is nobody else's: no application and no package answers for it, so
    the command and the development values cannot be confused for each other.
    """
    failures = json.loads(
        _host("nix", "eval", "--json", f"{FLAKE}#debug.failures", timeout=PATIENT)
    )
    assert failures == [], failures

    suites = json.loads(
        _host(
            "nix",
            "eval",
            "--json",
            f"{FLAKE}#debug.suites",
            "--apply",
            "builtins.attrNames",
            timeout=PATIENT,
        )
    )
    assert "plan" in suites, suites

    entries = json.loads(
        _host(
            "nix",
            "eval",
            "--json",
            f"{FLAKE}#debug.worked.plan",
            "--apply",
            "builtins.attrNames",
            timeout=PATIENT,
        )
    )
    assert entries, entries

    shown = json.loads(_host("nix", "flake", "show", "--json", str(FLAKE)))
    assert "debug" in shown, sorted(shown)
    for system in sorted(shown["apps"]):
        assert "debug" not in shown["apps"][system], shown["apps"][system]
        assert "debug" not in shown["packages"][system], sorted(shown["packages"][system])


def _planner(work: Workstation, *argv: str, timeout: float = PATIENT) -> str:
    """Run the operator's command on the workstation and return its stdout.

    The command arrives the way a reader gets it, out of the flake it was handed:
    ``nix run`` resolves the app, builds the wrapper on the machine and runs it.
    ``NIX_SSHOPTS`` carries the posture of a throwaway guest, whose host key
    nothing has seen before and whose only credential is the one file beside it.

    Args:
        work: The machine to run on, and the source that carries the command.
        argv: The command's own arguments.
        timeout: Seconds to allow.

    Returns:
        The command's stdout.
    """
    options = delivery.guest_ssh_options(Path(GUEST_KEY))
    command = shlex.join(["nix", "run", f"path:{work.source}", "--", *argv])
    out: str = work.vm.ssh_succeed(f"NIX_SSHOPTS={shlex.quote(options)} {command}", timeout=timeout)
    return out


@delivery.cluster_stage(
    snapshot,
    image=GUEST_IMAGE,
    names=MACHINES,
    key=KEY,
    memory_mib=4096,
    offline=False,
)
def booted(cluster: Any) -> Iterator[Any]:
    """The stage this run starts from: three machines, up and usable.

    On a cache hit this body does not run at all, so nothing here may be a fact a
    test reads. It waits, and yields. The memory is the workstation's: one
    evaluation of nixpkgs needs more than the 2 GiB the other folders boot with,
    and the shape is one number for every slot.
    """
    delivery.await_ready(cluster.cluster)
    yield cluster


@pytest.fixture(scope="session")
def workstation(booted: Any) -> Workstation:
    """The workstation, holding the template, the source and the credential.

    Skips the whole walk when the cluster has no egress: the claim under test is
    that a machine fetches its own inputs, and a machine that cannot reach the
    substituter can only be observed failing to.
    """
    cluster = booted.cluster
    vm = cluster.vm(WORKSTATION)
    reachable = vm.ssh(f"nix store info --store {SUBSTITUTER}", timeout=BRIEF)
    if reachable.returncode != 0:
        pytest.skip(
            f"{WORKSTATION} cannot reach {SUBSTITUTER}, so this folder has nothing to "
            f"observe: the cluster needs egress, and this host gave it none "
            f"({reachable.stderr.strip()[:200]})"
        )

    source = _source_of(FLAKE)
    cluster.run(
        [
            "nix",
            "copy",
            "--to",
            f"ssh://root@{vm.ip}",
            "--no-check-sigs",
            source,
            str(CREDENTIAL),
        ],
        env=delivery.command_env(dict(os.environ), KEY),
        timeout=BRIEF,
    )
    vm.ssh_succeed(
        f"cp -r {source}/{TEMPLATE} {CONSUMER} && chmod -R u+w {CONSUMER} && "
        f"install -m 600 {CREDENTIAL} {GUEST_KEY}",
        timeout=BRIEF,
    )
    work = Workstation(vm=vm, source=source)
    vm.ssh_succeed(
        f"cd {CONSUMER} && nix flake lock --override-input nixplan path:{source}",
        timeout=PATIENT,
    )
    return work


@pytest.fixture(scope="session")
def built(workstation: Workstation) -> tuple[str, dict[str, Reported]]:
    """What the workstation built, and the table the command reported for it."""
    lines = _planner(workstation, "build", CONSUMER).splitlines()
    assert lines, "planner build reported nothing"
    return lines[0], {row.key: row for row in map(_reported, lines[1:])}


@pytest.fixture(scope="session")
def applied(workstation: Workstation, built: tuple[str, dict[str, Reported]]) -> tuple[str, ...]:
    """The steps of the one apply this walk runs, as the command reported them."""
    assert built[1], "there was nothing to apply"
    return tuple(_planner(workstation, "apply", CONSUMER).splitlines())


def test_the_template_names_the_published_flake(workstation: Workstation) -> None:
    """The template a reader copies names the published flake, and the run swaps it.

    Read off the lock the workstation wrote, because the substitution has to be
    visible somewhere a reader can check: the input is still `github:`, the
    resolution is the tree under test, and the second input is one the machine
    fetched for itself.
    """
    locked = json.loads(workstation.vm.ssh_succeed(f"cat {CONSUMER}/flake.lock", timeout=BRIEF))
    nodes = locked["nodes"]

    assert nodes["nixplan"]["original"] == {
        "type": "github",
        "owner": "Qubasa",
        "repo": "nixplan",
    }, nodes["nixplan"]
    assert nodes["nixplan"]["locked"]["type"] == "path", nodes["nixplan"]["locked"]
    assert nodes["nixplan"]["locked"]["path"] == workstation.source, nodes["nixplan"]["locked"]

    assert nodes["nixpkgs"]["locked"]["type"] == "github", nodes["nixpkgs"]["locked"]


def test_a_consumer_is_asked_for_an_input_only_this_flake_pins(workstation: Workstation) -> None:
    """A reader declares this repository and a package set, and nothing further.

    korora is what the documented call used to ask for: a source pin with no
    flake of its own, whose revision has to be the one the library was built
    against or the types compare unequal. The published library arrives applied
    to it, so it reaches the lock as an input of this repository and never as one
    a reader was asked to name.
    """
    locked = json.loads(workstation.vm.ssh_succeed(f"cat {CONSUMER}/flake.lock", timeout=BRIEF))
    nodes = locked["nodes"]
    asked = nodes["root"]["inputs"]

    assert sorted(asked) == ["nixpkgs", "nixplan"], sorted(asked)
    assert asked["nixpkgs"] == ["nixplan", "nixpkgs"], asked["nixpkgs"]
    assert "korora" in nodes["nixplan"]["inputs"], nodes["nixplan"]["inputs"]


def test_the_machine_builds_the_deployment_it_was_handed(
    booted: Any, workstation: Workstation, built: tuple[str, dict[str, Reported]]
) -> None:
    """A machine given the template and the source builds the deployment itself.

    The two entries of one instance are two artifacts, not one copied twice: the
    greeting each unit writes names the address its entry was planned for, so a
    build that collapsed them would be reporting one store path here.
    """
    root, entries = built
    assert sorted(entries) == [f"{ENTRY}@{name}" for name in TARGETS], sorted(entries)

    for name in TARGETS:
        entry = entries[f"{ENTRY}@{name}"]
        assert entry.realiser == REALISER, entry
        assert entry.machine == name, entry
        assert entry.address == booted.cluster.ip_of(name), entry
        assert entry.units == (UNIT,), entry

    first, second = (entries[f"{ENTRY}@{name}"].path for name in TARGETS)
    assert first != second, first

    held = workstation.vm.ssh_succeed(
        f"nix-store --check-validity {root} && echo held", timeout=BRIEF
    )
    assert held.strip() == "held", held


def test_one_apply_reaches_both_machines(
    booted: Any, built: tuple[str, dict[str, Reported]], applied: tuple[str, ...]
) -> None:
    """One command run on the workstation, and both machines run what it built."""
    _, entries = built

    for name in TARGETS:
        entry = entries[f"{ENTRY}@{name}"]
        assert f"copy {entry.key} {entry.path} -> root@{entry.address}" in applied, applied
        assert f"activate {entry.key} ({REALISER}) on root@{entry.address}" in applied, applied

        vm = booted.cluster.vm(name)
        assert vm.ssh_succeed(f"systemctl is-active {UNIT}", timeout=BRIEF).strip() == "active"
        greeted = vm.ssh_succeed(f"cat {GREETING}", timeout=BRIEF).strip()
        assert greeted == f"hello world from {entry.address}", greeted


def test_the_machine_that_built_it_runs_none_of_it(
    workstation: Workstation, applied: tuple[str, ...]
) -> None:
    """The workstation deployed the plan and is not in it, so it runs nothing.

    A machine that built a deployment holds every artifact of it in its store, and
    that is not a deployment: the unit exists where an entry placed it, which here
    is the two machines the registry names and never the one that did the placing.
    """
    assert applied, applied
    vm = workstation.vm
    assert vm.ssh(f"systemctl is-active {UNIT}", timeout=BRIEF).returncode != 0
    assert vm.ssh(f"test -e {GREETING}", timeout=BRIEF).returncode != 0


def test_the_workstation_asks_both_machines_what_they_hold(
    workstation: Workstation, applied: tuple[str, ...]
) -> None:
    """The last step of the walk answers from the machines, not from the build."""
    assert applied, applied
    reported = _planner(workstation, "status", CONSUMER, timeout=BRIEF).splitlines()

    for name in TARGETS:
        key = f"{ENTRY}@{name}"
        expected = f"{key} {REALISER} generation 1 of {delivery.locked_url(key)}"
        assert expected in reported, reported


@pytest.fixture(scope="session")
def refused(workstation: Workstation) -> str:
    """A copy of the consumer whose deployment carries one error row, built.

    The mutation is a closure root outside the store directory, which the planner
    reports and no realiser is reached for. The build is a real ``nix build`` on
    the machine, because the claim is about what the derivation produces.
    """
    vm = workstation.vm
    vm.ssh_succeed(
        f"rm -rf {REFUSED} && cp -r {CONSUMER} {REFUSED} && chmod -R u+w {REFUSED} && "
        f"sed -i 's|closure = \\[ greeter \\];|closure = [ greeter \"{OUTSIDE}\" ];|' "
        f"{REFUSED}/deployment/modules/hello/greet.nix",
        timeout=BRIEF,
    )
    built: str = vm.ssh_succeed(
        f"cd {REFUSED} && nix build --no-link --print-out-paths .#default",
        timeout=PATIENT,
    )
    return built.strip().splitlines()[-1]


def test_both_halves_of_the_table_are_reachable_for_a_refused_deployment(
    workstation: Workstation, refused: str
) -> None:
    """An inapplicable deployment builds its plan and both halves of its table.

    A tool reads the rows out of `diagnostics.json`, a person reads
    `diagnostics.txt`, and neither exists if the build raises instead. No entry
    is realised, and nothing in the tree says so other than the rows themselves.
    """
    vm = workstation.vm
    held = sorted(vm.ssh_succeed(f"ls {refused}", timeout=BRIEF).split())
    assert held == ["diagnostics.json", "diagnostics.txt", "manifest.json", "plan.json"], held

    rows = json.loads(vm.ssh_succeed(f"cat {refused}/diagnostics.json", timeout=BRIEF))
    errors = [row for row in rows if row["severity"] == "error"]
    assert {row["id"] for row in errors} == {"closure-root-outside-store"}, rows
    assert [row["subject"] for row in errors] == [f"{ENTRY}@{name}" for name in TARGETS], errors
    assert OUTSIDE in errors[0]["message"], errors

    rendered = vm.ssh_succeed(f"cat {refused}/diagnostics.txt", timeout=BRIEF)
    assert errors[0]["message"] in rendered, rendered

    plan = json.loads(vm.ssh_succeed(f"cat {refused}/plan.json", timeout=BRIEF))
    assert [key for key in plan if key.startswith(ENTRY)] == [
        f"{ENTRY}@{name}" for name in TARGETS
    ], sorted(plan)

    assert vm.ssh(f"test -e {refused}/entries", timeout=BRIEF).returncode != 0
