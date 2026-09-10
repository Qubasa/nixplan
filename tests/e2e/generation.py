"""The operator side of a generated value: where its bytes come from.

A plan is evaluated against `varsState`: which declared files exist, and what
the public ones hold. Until now every run wrote that by hand, so the delivery
set was derived over bytes nothing generated. This module obtains it instead by
asking a real store backend, once per declared file, and reads the bytes of a
public file only - a secret one travels beside the plan, never inside it.

Three things are refusals rather than surprises, and each names what to change:

1. **The tool is resolved at run time.** ``$NIXOS_SECRETS_FLAKE`` is an unmerged
   branch of a fork, so pinning it as an input of this flake would make every
   consumer fetch it. It is built with ``--refresh`` for the reason
   ``runner.resolve_rookery`` is: a branch reference otherwise resolves through
   nix's tarball TTL and a run silently uses whatever was fetched last.
2. **The contract is pinned.** ``secrets/read.nix`` is written against one
   revision's ``secrets-config.schema.json``. Its digest is recorded here and
   compared against the resolved tool's, so a merged and renamed API fails
   loudly instead of being silently outlived. An unresolvable tool is not
   evidence the contract moved, so that comparison does not fail.
3. **Provenance is compared before anything is delivered.** The tool records no
   provenance of its own, so an interrupted run leaves one value regenerated and
   a value derived from it stale, and the next invocation reports success. The
   identity compared is the plan key the planner already computes over the
   declaration, written beside the state it read.

Nothing here runs a generator itself: the tool does that, in its own sandbox.
"""

from __future__ import annotations

import hashlib
import json
import os
import re
import subprocess
import tempfile
from collections.abc import Iterable, Mapping, Sequence
from dataclasses import dataclass, field
from pathlib import Path
from typing import Any, Protocol

import runner

FLAKE_VARIABLE = "NIXOS_SECRETS_FLAKE"
CONTRACT_REVISION = "e6af758a5745ac4adef763deb0f1771cec58c461"
DEFAULT_FLAKE = f"github:starlitcanopy/nixpkgs/{CONTRACT_REVISION}"
CONTRACT_DIGEST = "sha256:44408bcdca7e59af6f9f05e4fe30ef6aa6df004f97e3df68d8e8d2062a4876cf"
CONTRACT_FILE = "pkgs/by-name/ni/nixos-secrets/src/nixos_secrets/secrets-config.schema.json"
READING = "secrets/read.nix"
# Not spelled with the interpreter-versioned prefix of the tool's site-packages:
# the path scan in `tests/unit/layers.nix` reads raw file text, and a token whose
# first segment is a top-level entry of this repository has to resolve here.
SCHEMA_GLOB = "**/nixos_secrets/secrets-config.schema.json"

# The two statuses the contract's `exists` script may answer with. Anything else
# is a backend that failed rather than a file that is missing.
HELD = 0
NOT_HELD = 42

# Where the identity each stored value was generated from is written. Not the
# tool's own `.nixos-secrets-metadata`: that records a uuid per generation, which
# says two runs differ and nothing about which declaration either came from.
PROVENANCE_FILE = "planner-provenance.json"

SSH_OPTIONS_VARIABLE = "PLANNER_SECRETS_SSH_OPTS"

FAILED_VALUE = re.compile(r"(?:Error generating|Generator) '([^']+)'")
UPDATED = re.compile(r"Successfully updated (\d+) secret")
REGENERATING = re.compile(r"Regenerating '([^']+)'")


class GenerationError(RuntimeError):
    """A generated value this run will not proceed past, named at its cause."""


@dataclass(frozen=True)
class File:
    """One file of a generated value, as the plan and the configuration agree on it."""

    name: str
    secret: bool
    deploy: bool


@dataclass(frozen=True)
class Value:
    """One generated value: its plan key, its projected name and its identity."""

    key: str
    name: str
    identity: str
    files: tuple[File, ...]

    def file(self, name: str) -> File:
        """Return the declared file of that name.

        Raises:
            GenerationError: If the value declares no such file.
        """
        for each in self.files:
            if each.name == name:
                return each
        raise GenerationError(f"{self.key} declares no file {name!r}")


class Store(Protocol):
    """The half of a store backend this module uses: does it hold a file, and what."""

    def status(self, name: str, file: str) -> int:
        """Return the exit status the backend's `exists` script answered with."""
        ...

    def fetch(self, name: str, file: str) -> str:
        """Return the bytes the backend holds for one file."""
        ...


def values(
    plan: Mapping[str, Any],
    configuration: Mapping[str, Any],
    names: Mapping[str, str],
) -> tuple[Value, ...]:
    """Return the generated values of a plan, as the configuration names them.

    Args:
        plan: The plan artifact, as read from its JSON.
        configuration: The `SecretsConfiguration` read from the same plan.
        names: The projected name of each value's plan key, as the reading
            projected it. The projection is the reading's, so nothing here
            reimplements it.

    Returns:
        One value per plan key, in key order.

    Raises:
        GenerationError: If a key names no plan entry, if the configuration
            carries no entry under its projected name, or if the two disagree
            about which files a value declares.
    """
    store = configuration.get("store", {})
    found: list[Value] = []
    for key in sorted(names):
        entry = plan.get(key)
        name = names[key]
        if entry is None:
            raise GenerationError(f"the plan carries no entry {key}, which {name} was read from")
        if name not in store:
            raise GenerationError(f"the configuration carries no store entry {name} for {key}")
        planned = entry.get("files", {})
        configured = store[name].get("files", {})
        if sorted(planned) != sorted(configured):
            raise GenerationError(
                f"{key} declares {sorted(planned)} and {name} declares {sorted(configured)}: "
                "the plan and the configuration were read from two plans"
            )
        found.append(
            Value(
                key=key,
                name=name,
                identity=str(entry["key"]),
                files=tuple(
                    File(
                        name=file,
                        secret=planned[file].get("secrecy") == "secret",
                        deploy=bool(configured[file].get("deploy")),
                    )
                    for file in sorted(planned)
                ),
            )
        )
    return tuple(found)


def state(values: Sequence[Value], store: Store) -> dict[str, Any]:
    """Return the `varsState` a plan is evaluated against, read from a backend.

    A file the backend does not hold is recorded absent rather than present with
    no bytes: the planner renders those two differently and only one of them is a
    value that exists. The bytes of a secret file are never asked for.

    Args:
        values: The generated values of the plan.
        store: The backend to ask.

    Returns:
        The `varsState` argument of `mkPlan`, keyed by plan key.

    Raises:
        GenerationError: If the backend answers with neither of the two statuses
            the contract allows, naming the value, the file and the status.
    """
    built: dict[str, Any] = {}
    for value in values:
        files: dict[str, Any] = {}
        for file in value.files:
            status = store.status(value.name, file.name)
            if status not in (HELD, NOT_HELD):
                raise GenerationError(
                    f"the backend answered {status} about {value.name}/{file.name} of "
                    f"{value.key}, and it answers {HELD} for a file it holds and "
                    f"{NOT_HELD} for one it does not"
                )
            present = status == HELD
            files[file.name] = {"present": present}
            if present and not file.secret:
                files[file.name]["content"] = store.fetch(value.name, file.name)
        built[value.key] = files
    return built


def held(values: Sequence[Value], built: Mapping[str, Any]) -> tuple[Value, ...]:
    """Return the values the state records at least one held file of."""
    return tuple(
        value
        for value in values
        if any(built.get(value.key, {}).get(file.name, {}).get("present") for file in value.files)
    )


def require_generated(values: Sequence[Value], built: Mapping[str, Any]) -> None:
    """Refuse a state that reports a declared file the backend does not hold.

    Args:
        values: The generated values of the plan.
        built: The state read after generation reported success.

    Raises:
        GenerationError: Naming each value and the files it is missing.
    """
    missing = [
        (
            value.name,
            [file.name for file in value.files if not built[value.key][file.name]["present"]],
        )
        for value in values
    ]
    named = [f"{name} is missing {', '.join(files)}" for name, files in missing if files]
    if named:
        raise GenerationError(
            "generation reported success and the backend holds none of these files: "
            + "; ".join(named)
        )


def identities(values: Sequence[Value]) -> dict[str, str]:
    """Return the identity of each value's declaration, by projected name."""
    return {value.name: value.identity for value in values}


def read_provenance(path: Path) -> dict[str, str]:
    """Return the identities recorded beside the stored values, or nothing."""
    if not path.exists():
        return {}
    recorded = json.loads(path.read_text())
    return {str(name): str(identity) for name, identity in recorded.items()}


def write_provenance(path: Path, values: Sequence[Value]) -> None:
    """Record the identity each stored value was generated from."""
    path.write_text(json.dumps(identities(values), indent=2, sort_keys=True) + "\n")


def require_provenance(
    values: Sequence[Value],
    built: Mapping[str, Any],
    recorded: Mapping[str, str],
) -> None:
    """Refuse a run whose stored values disagree with the declarations they name.

    A stored value with no recorded identity is a disagreement, not a match: the
    tool regenerates conservatively, so a value that was stored before this
    record existed may have been generated from any declaration.

    Args:
        values: The generated values of the plan.
        built: The state read from the backend.
        recorded: The identities recorded beside those stored values.

    Raises:
        GenerationError: Naming the value, both identities and what resolves it.
    """
    stale = [
        (value.name, recorded.get(value.name), value.identity)
        for value in held(values, built)
        if recorded.get(value.name) != value.identity
    ]
    if not stale:
        return
    named = "; ".join(
        f"{name} was generated from {was or 'a declaration nothing recorded'} and the plan "
        f"now declares {now}"
        for name, was, now in stale
    )
    raise GenerationError(
        runner.banner(
            "A STORED VALUE NO LONGER MATCHES ITS DECLARATION",
            [
                named,
                "",
                "The generator regenerates conservatively and records no provenance,",
                "so a value derived from a changed one is stale while reporting success.",
                "Regenerate the value this names:",
                *(f"  nixos-secrets generate -g {name}" for name, _, _ in stale),
            ],
        )
    )


def unresolved(flake: str, stderr: str) -> str:
    """Return the banner naming the reference that resolved to nothing."""
    return runner.banner(
        "NIXOS-SECRETS COULD NOT BE RESOLVED",
        [
            f"${FLAKE_VARIABLE} = {flake}",
            "",
            "The generator is an unmerged branch of a fork, so it is resolved at",
            "run time rather than pinned as an input of this flake. Point",
            f"${FLAKE_VARIABLE} at a checkout or a reference you can fetch.",
            "",
            *stderr.strip().splitlines()[-6:],
        ],
    )


def tool(flake: str | None = None) -> Path:
    """Build `flake#nixos-secrets` and return its path.

    Args:
        flake: The flake reference to resolve. Defaults to `$NIXOS_SECRETS_FLAKE`,
            and to the recorded revision when that is unset.

    Returns:
        The store path of the generator.

    Raises:
        GenerationError: If the build fails or nix is not there to run it, with
            the variable and the reference named.
    """
    reference = flake or os.environ.get(FLAKE_VARIABLE) or DEFAULT_FLAKE
    argv = [
        "nix",
        "build",
        "--refresh",
        "--no-link",
        "--print-out-paths",
        f"{reference}#nixos-secrets",
    ]
    try:
        built = subprocess.run(argv, capture_output=True, text=True, check=False)
    except FileNotFoundError as exc:
        raise GenerationError(unresolved(reference, f"nix is not on PATH: {exc}")) from exc
    if built.returncode != 0:
        raise GenerationError(unresolved(reference, built.stderr))
    return Path(built.stdout.strip().splitlines()[-1])


def schema_of(resolved: Path) -> Path | None:
    """Return the contract the resolved tool publishes, or `None` if it holds none."""
    found = sorted(resolved.glob(SCHEMA_GLOB))
    return found[0] if found else None


def digest_of(path: Path) -> str:
    """Return the `sha256:<hex>` digest of one file."""
    return "sha256:" + hashlib.sha256(path.read_bytes()).hexdigest()


def contract_refusal(resolved: Path | None) -> str | None:
    """Return the banner naming a moved contract, or `None`.

    An unreadable signal is not evidence that the contract moved, so a tool that
    could not be resolved and a tool carrying no schema both answer `None`. The
    run that needed the tool skips instead.

    Args:
        resolved: The store path of the generator, or `None`.

    Returns:
        The refusal to print and fail on, or `None`.
    """
    if resolved is None:
        return None
    schema = schema_of(resolved)
    if schema is None:
        return None
    found = digest_of(schema)
    if found == CONTRACT_DIGEST:
        return None
    return runner.banner(
        "THE EXTERNAL SECRET CONTRACT HAS MOVED",
        [
            f"recorded: {CONTRACT_DIGEST}",
            f"resolved: {found}",
            "",
            f"{READING} is written against revision {CONTRACT_REVISION} of",
            f"{CONTRACT_FILE}",
            "",
            f"Diff that file against the recorded revision, rewrite {READING} and",
            "tests/e2e/generation.py's recorded digest, or delete this composition",
            "if the contract it names is gone.",
        ],
    )


def sandbox_problem() -> str | None:
    """Return why the generator's sandbox cannot run here, or `None`.

    The tool runs every generator inside bubblewrap, which needs unprivileged
    user namespaces. Where the kernel denies them the tool dies with no useful
    message, so this probes once and names the feature.
    """
    limit = Path("/proc/sys/user/max_user_namespaces")
    try:
        probe = subprocess.run(
            ["bwrap", "--ro-bind", "/", "/", "true"],
            capture_output=True,
            text=True,
            check=False,
            timeout=10,
        )
    except FileNotFoundError:
        return "bubblewrap is not on PATH, and the generator sandboxes every generator with it"
    except subprocess.TimeoutExpired:
        return "bubblewrap did not answer a trivial invocation within ten seconds"
    if probe.returncode == 0:
        return None
    named = f"{limit} reads {limit.read_text().strip()}" if limit.exists() else f"{limit} is absent"
    return (
        "bubblewrap cannot create a user namespace here, and the generator sandboxes "
        f"every generator with it: {named}. Last line: {probe.stderr.strip().splitlines()[-1:]}"
    )


def generate_argv(
    resolved: Path,
    configuration: Path,
    *,
    forced: Iterable[str] = (),
    timeout: float = 60.0,
) -> list[str]:
    """Return the generation an operator runs, as argv.

    `--json` because the configuration is a plan read into the contract's own
    object: there is no NixOS configuration to evaluate and no `networking.
    hostName` for two invocations to disagree about.
    """
    argv = [
        str(resolved / "bin" / "nixos-secrets"),
        "generate",
        "--json",
        str(configuration),
        "--verbose",
        "--timeout",
        str(timeout),
    ]
    for name in forced:
        argv += ["--generate", name]
    return argv


def deploy_argv(resolved: Path, configuration: Path) -> list[str]:
    """Return the deployment an operator runs, as argv.

    The contract's deploy step is handed a file list and no target, so the step
    itself is rendered from the plan by `secrets/backend.nix`. This invocation is
    what hands it that list.
    """
    return [
        str(resolved / "bin" / "nixos-secrets"),
        "deploy",
        "--json",
        str(configuration),
        "--verbose",
    ]


def failed_value(text: str) -> str | None:
    """Return the value the generator named as having failed, if it named one."""
    found = FAILED_VALUE.search(text)
    return found.group(1) if found else None


def updated(text: str) -> int:
    """Return how many values the generator reported updating.

    Raises:
        GenerationError: If the output carries no such report.
    """
    found = UPDATED.search(text)
    if found is None:
        raise GenerationError(f"the generator reported no update count: {text.strip()[-200:]}")
    return int(found.group(1))


def regenerated(text: str) -> tuple[str, ...]:
    """Return the values the generator reported regenerating, in the order it did."""
    return tuple(REGENERATING.findall(text))


def require_success(result: subprocess.CompletedProcess[str], *, what: str) -> str:
    """Return the generator's output, or refuse the run naming the value that failed.

    Args:
        result: The finished invocation.
        what: What was being run, for the message.

    Returns:
        The output, both streams, in the order the tool wrote them.

    Raises:
        GenerationError: If the invocation failed, naming the value where the
            output named one.
    """
    output = (result.stdout or "") + (result.stderr or "")
    if result.returncode == 0:
        return output
    value = failed_value(output)
    named = f"{what} failed for {value}" if value else f"{what} failed and named no value"
    raise GenerationError(f"{named} [exit {result.returncode}]:\n{output.strip()[-2000:]}")


def realise(drv: str) -> Path:
    """Return the output the tool would realise for one derivation path.

    Raises:
        GenerationError: If the derivation cannot be realised.
    """
    built = subprocess.run(
        ["nix-store", "--realise", drv], capture_output=True, text=True, check=False
    )
    if built.returncode != 0:
        raise GenerationError(f"{drv} could not be realised:\n{built.stderr.strip()}")
    return Path(built.stdout.strip().splitlines()[-1])


@dataclass
class BackendStore:
    """A configuration's store backend, invoked the way the contract says to.

    `exists` answers by exit status and `get` writes to `$out`, so both are run
    exactly as the tool runs them. Every fetch is recorded, which is what makes
    "a secret file's bytes are never fetched" an observation.
    """

    exists: Path
    get: Path
    env: Mapping[str, str] = field(default_factory=dict)
    fetched: list[tuple[str, str]] = field(default_factory=list)

    def status(self, name: str, file: str) -> int:
        environment = {**os.environ, **self.env}
        answer = subprocess.run(
            [str(self.exists), name, file],
            capture_output=True,
            text=True,
            check=False,
            env=environment,
        )
        return answer.returncode

    def fetch(self, name: str, file: str) -> str:
        self.fetched.append((name, file))
        with tempfile.TemporaryDirectory() as into:
            out = Path(into) / file
            environment = {**os.environ, **self.env, "out": str(out)}
            got = subprocess.run(
                [str(self.get), name, file],
                capture_output=True,
                text=True,
                check=False,
                env=environment,
            )
            if got.returncode != 0:
                raise GenerationError(
                    f"the backend could not fetch {name}/{file}:\n{got.stderr.strip()}"
                )
            return out.read_text()


def backend_store(
    configuration: Mapping[str, Any],
    *,
    name: str,
    env: Mapping[str, str] | None = None,
) -> BackendStore:
    """Return the store backend of a configuration, with its programs realised.

    Args:
        configuration: The `SecretsConfiguration`.
        name: The store backend to read.
        env: What to add to the environment each program runs under.

    Returns:
        The backend, ready to be asked.

    Raises:
        GenerationError: If the configuration declares no such backend, or that
            backend offers no `get`.
    """
    backends = configuration.get("backends", {}).get("store", {})
    if name not in backends:
        raise GenerationError(f"the configuration declares no store backend {name!r}")
    declared = backends[name]
    if not declared.get("get"):
        raise GenerationError(
            f"store backend {name!r} offers no `get`, so no public file is readable"
        )
    return BackendStore(
        exists=realise(declared["exists"]),
        get=realise(declared["get"]),
        env=dict(env or {}),
    )


def plan_of(expression: Path, state_file: Path) -> dict[str, Any]:
    """Evaluate one deployment into a plan against the state read from a backend.

    The plan is a function of the state, so it cannot be a build artifact of a
    run that has not generated anything yet: the artifact carries the expression
    and this evaluates it.

    Args:
        expression: A nix file taking `{ varsStateFile }` and returning a plan.
        state_file: The state, as JSON.

    Returns:
        The plan.

    Raises:
        GenerationError: If the evaluation fails.
    """
    argv = [
        "nix",
        "eval",
        "--json",
        "--file",
        str(expression),
        "--apply",
        f'plan: plan {{ varsStateFile = "{state_file}"; }}',
    ]
    evaluated = subprocess.run(argv, capture_output=True, text=True, check=False)
    if evaluated.returncode != 0:
        raise GenerationError(
            f"{expression} could not be evaluated against {state_file}:\n{evaluated.stderr.strip()}"
        )
    decoded: dict[str, Any] = json.loads(evaluated.stdout)
    return decoded
