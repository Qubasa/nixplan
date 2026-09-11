"""The entry point of ``nix run .#planner-e2e``.

The machine layer is one command. With no argument it runs every end-to-end
test; with the name of one directory under ``tests/e2e/`` it runs
that one alone, and an unknown name is refused naming the ones that exist.
Anything after the name is handed to pytest, so ``planner-e2e wired-pair -k
wire`` still selects by expression.

Three things have to happen before pytest sees a machine, and each of them is a
refusal rather than a surprise:

1. **The host is checked and what is missing is named.** ``/dev/net/tun`` and
   ``/dev/vhost-vsock`` are not sandbox defaults and a stock NixOS host does not
   load ``vhost_vsock`` on its own, so the common failure is a missing device.
   Naming it here means no VM is started and no boot is waited out.
2. **rookery is resolved at run time.** It is private and unpublished, so making
   it a flake input would make every output of this flake - including the checks
   that have nothing to do with clusters - unevaluable for anyone without that
   access (design.md D2). ``$ROOKERY_FLAKE`` is built with the caller's own
   credentials, here, at the moment they run the command.
3. **The interpreters are compared.** rookery reaches pytest through
   ``PYTHONPATH``, which is only meaningful within one minor version, so a
   mismatch stops the run with both versions named rather than importing across
   it (design.md D4).

``$PLANNER_E2E`` is the layer's root and ``$PLANNER_CLI_SRC`` is the command's.
Both go on ``PYTHONPATH`` rather than being copied flat, so a test imports the
shared harness as ``import delivery``, reads a built deployment as
``import manifest``, and reads its own fixture from beside its own file. A
``sys.path`` edit in ``conftest.py`` would not do: pytest loads no conftest above
the ini file's directory, and a run naming one folder collects a path that has
none below it.

``--print-env`` assembles the same environment and prints it as shell ``export``
lines instead of handing over to pytest. That is the tail of what
``planner-e2e-env`` prints for ``eval``, so a manual ``pytest`` runs against the
rookery this runner would have used rather than a second, hand-written assembly
of it.
"""

from __future__ import annotations

import os
import re
import shlex
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path

DEFAULT_ROOKERY_FLAKE = "git+ssh://git@github.com/Qubasa/rookery"

DEVICES: tuple[tuple[str, str], ...] = (
    ("/dev/kvm", "rookery refuses to fall back to TCG emulation, so KVM is required"),
    ("/dev/net/tun", "the cluster LAN is real taps in a network namespace"),
    ("/dev/vhost-vsock", "the control channel into each guest is vsock"),
)
USERNS_LIMIT = Path("/proc/sys/user/max_user_namespaces")

SITE_PACKAGES = re.compile(r"lib/(python3\.\d+)/site-packages$")


class RunnerError(RuntimeError):
    """A prerequisite this runner will not proceed without."""


def banner(title: str, lines: list[str]) -> str:
    """Return a loud, unmissable block naming what has to change."""
    width = max([len(title), *(len(line) for line in lines)]) + 4
    rule = "=" * width
    body = "\n".join(f"  {line}" for line in lines)
    return f"\n{rule}\n  {title}\n{rule}\n{body}\n{rule}\n"


def host_problems(devices: tuple[tuple[str, str], ...] = DEVICES) -> list[str]:
    """Return every host prerequisite that is missing, as printable lines."""
    problems: list[str] = []
    for path, reason in devices:
        try:
            handle = os.open(path, os.O_RDWR | os.O_CLOEXEC)
        except OSError as exc:
            problems.append(f"{path}: {exc.strerror} - {reason}")
        else:
            os.close(handle)
    try:
        limit = int(USERNS_LIMIT.read_text().strip())
    except (OSError, ValueError):
        problems.append(
            f"{USERNS_LIMIT}: unreadable - rookery runs every cluster in an "
            "unprivileged user namespace"
        )
    else:
        if limit <= 0:
            problems.append(
                f"{USERNS_LIMIT} is {limit} - unprivileged user namespaces are "
                "disabled, so no cluster can be created"
            )
    return problems


def host_refusal() -> str | None:
    """Return the banner naming every missing host prerequisite, or ``None``."""
    problems = host_problems()
    if not problems:
        return None
    return banner(
        "THIS HOST CANNOT RUN THE CLUSTER",
        [
            *problems,
            "",
            'On NixOS: boot.kernelModules = [ "tun" "vhost_vsock" ];',
            "and add your user to the 'kvm' group. No VM was started.",
        ],
    )


def end_to_end_tests(root: Path) -> dict[str, list[Path]]:
    """Return each end-to-end directory's name and the test files it holds."""
    found: dict[str, list[Path]] = {}
    for entry in sorted(root.iterdir()):
        if not entry.is_dir():
            continue
        files = sorted(entry.glob("test_*.py"))
        if files:
            found[entry.name] = files
    return found


def select_tests(root: Path, name: str | None) -> list[Path]:
    """Return the test files to run: every one, or the one ``name`` asks for.

    Raises:
        RunnerError: If ``name`` is no end-to-end test, naming those that are.
    """
    tests = end_to_end_tests(root)
    if name is None:
        return [path for paths in tests.values() for path in paths]
    if name not in tests:
        raise RunnerError(
            banner(
                f"NO END-TO-END TEST NAMED {name!r}",
                ["the end-to-end tests are:", *(f"  {each}" for each in tests)],
            )
        )
    return tests[name]


def resolve_rookery(flake: str) -> Path:
    """Build ``flake#rookery`` with the caller's credentials and return its path.

    ``--refresh`` because a branch reference resolves through nix's tarball TTL:
    without it a run silently uses whatever rookery was last fetched, and a
    rookery from before a nixpkgs bump is a different python minor version, which
    the interpreter check then reports as a mismatch that does not exist.

    Raises:
        RunnerError: If the build fails, with the flake reference named.
    """
    built = subprocess.run(
        [
            "nix",
            "build",
            "--refresh",
            "--no-link",
            "--print-out-paths",
            f"{flake}#rookery",
        ],
        capture_output=True,
        text=True,
        check=False,
    )
    if built.returncode != 0:
        raise RunnerError(
            banner(
                "ROOKERY COULD NOT BE RESOLVED",
                [
                    f"$ROOKERY_FLAKE = {flake}",
                    "",
                    "rookery is private and is resolved at run time with your own",
                    "credentials rather than pinned as an input of this flake.",
                    "Point $ROOKERY_FLAKE at a checkout or a reference you can fetch.",
                    "",
                    *built.stderr.strip().splitlines()[-6:],
                ],
            )
        )
    return Path(built.stdout.strip().splitlines()[-1])


def propagated(store_path: Path) -> list[Path]:
    """Return the store paths one package propagates to its consumers."""
    listing = store_path / "nix-support" / "propagated-build-inputs"
    if not listing.exists():
        return []
    return [Path(entry) for entry in listing.read_text().split()]


def propagated_closure(roots: list[Path]) -> list[Path]:
    """Return ``roots`` and everything they propagate, transitively, in order.

    The walk is transitive because it has to be: ``iproute2``, ``util-linux`` and
    ``openssh`` are propagated as their ``-dev`` outputs, which carry no ``bin``
    and propagate the real output one level down. Taking ``bin`` of the direct
    entries alone loses ``ip``, ``nsenter`` and ``ssh``.
    """
    seen: list[Path] = []
    pending = list(roots)
    while pending:
        current = pending.pop(0)
        if current in seen:
            continue
        seen.append(current)
        pending.extend(propagated(current))
    return seen


def site_packages(rookery: Path) -> Path:
    """Return rookery's ``site-packages`` directory.

    Raises:
        RunnerError: If the package holds none.
    """
    found = sorted((rookery / "lib").glob("python3.*/site-packages"))
    if not found:
        raise RunnerError(f"{rookery} carries no python3.*/site-packages under lib")
    return found[0]


def python_minor(site: Path) -> str:
    """Return the ``python3.X`` a site-packages directory belongs to."""
    match = SITE_PACKAGES.search(str(site))
    if match is None:
        raise RunnerError(f"cannot read a python version out of {site}")
    return match.group(1)


def require_one_interpreter(rookery_python: str) -> None:
    """Refuse to import rookery across a python minor version boundary.

    Raises:
        RunnerError: If this interpreter's minor version is not rookery's, with
            both versions named.
    """
    ours = f"python3.{sys.version_info.minor}"
    if ours != rookery_python:
        raise RunnerError(
            banner(
                "PYTHON VERSION MISMATCH",
                [
                    f"rookery was built for {rookery_python}",
                    f"this runner's pytest environment is {ours}",
                    "",
                    "rookery reaches pytest through PYTHONPATH, which only holds",
                    "within one minor version. Rebuild the runner's environment on",
                    f"{rookery_python} (pytest-env.nix picks the newest one),",
                    "or point $ROOKERY_FLAKE at a rookery built for " + ours + ".",
                ],
            )
        )


def cluster_environment(rookery: Path, base_env: dict[str, str]) -> dict[str, str]:
    """Return the environment the suite runs under: rookery's binaries and library."""
    site = site_packages(rookery)
    require_one_interpreter(python_minor(site))

    packages = propagated_closure([rookery])
    bins = [str(path / "bin") for path in packages if (path / "bin").is_dir()]

    env = dict(base_env)
    env["PATH"] = os.pathsep.join([*bins, env.get("PATH", "")]).rstrip(os.pathsep)
    env["PYTHONPATH"] = os.pathsep.join(
        [str(site), *(entry for entry in [env.get("PYTHONPATH", "")] if entry)]
    )
    env["PYTHONUNBUFFERED"] = "1"
    return env


def import_path(root: Path, cli_source: str | None, inherited: str) -> str:
    """Return the import path a run reads its own modules from.

    The artifacts the app names come first. A shell that already carries this
    checkout on ``PYTHONPATH`` - which `devshells.nix` does on purpose, so that
    a manual `pytest` reads an edit - would otherwise shadow the built copies,
    and a run would report on files it did not build.

    Args:
        root: The built end-to-end layer, which is ``$PLANNER_E2E``.
        cli_source: The built command source, where the app named one.
        inherited: The import path the run was handed.

    Returns:
        One ``PYTHONPATH`` value, the run's own roots before the inherited one.
    """
    roots = [str(root), *(value for value in [cli_source] if value)]
    return os.pathsep.join([*roots, *(entry for entry in [inherited] if entry)])


def print_env() -> int:
    """Print the exports a manual ``pytest`` run needs, on stdout, for ``eval``.

    A missing device is a warning here rather than a refusal: the environment is
    still the right one, the banner has already named what to load, and the boot
    is what fails. An unresolvable rookery or a mismatched interpreter is a
    refusal, because either makes the environment wrong.
    """
    refusal = host_refusal()
    if refusal is not None:
        print(refusal, file=sys.stderr)

    flake = os.environ.get("ROOKERY_FLAKE", DEFAULT_ROOKERY_FLAKE)
    try:
        rookery = resolve_rookery(flake)
        env = cluster_environment(rookery, dict(os.environ))
    except RunnerError as exc:
        print(exc, file=sys.stderr)
        return 1

    for name in ("PATH", "PYTHONPATH", "PYTHONUNBUFFERED"):
        print(f"export {name}={shlex.quote(env[name])}")
    print(f"rookery: {rookery}", file=sys.stderr)
    return 0


def main(argv: list[str]) -> int:
    """Check the host, resolve rookery, and hand over to pytest."""
    if argv and argv[0] == "--print-env":
        return print_env()

    root = Path(os.environ["PLANNER_E2E"])
    name = argv[0] if argv and not argv[0].startswith("-") else None
    rest = argv[1:] if name is not None else argv

    try:
        selected = select_tests(root, name)
    except RunnerError as exc:
        print(exc, file=sys.stderr)
        return 1

    refusal = host_refusal()
    if refusal is not None:
        print(refusal, file=sys.stderr)
        return 1

    flake = os.environ.get("ROOKERY_FLAKE", DEFAULT_ROOKERY_FLAKE)

    try:
        rookery = resolve_rookery(flake)
        env = cluster_environment(rookery, dict(os.environ))
    except RunnerError as exc:
        print(exc, file=sys.stderr)
        return 1

    env["PYTHONPATH"] = import_path(root, os.environ.get("PLANNER_CLI_SRC"), env["PYTHONPATH"])

    # Keep this prefix short. The virtiofs socket path built underneath it hits the
    # 108 byte AF_UNIX limit, and virtiofsd then dies during startup with no clear
    # error.
    state = Path(tempfile.mkdtemp(prefix="pc-"))
    env["PLANNER_E2E_STATE"] = str(state)
    print(f"rookery: {rookery}", file=sys.stderr)

    pytest_argv = [
        sys.executable,
        "-m",
        "pytest",
        "-q",
        "-rs",
        "--no-header",
        "-p",
        "no:cacheprovider",
        *(str(path) for path in selected),
        *rest,
    ]
    code = subprocess.run(pytest_argv, env=env, check=False).returncode
    if code == 0:
        shutil.rmtree(state, ignore_errors=True)
    else:
        print(f"cluster state kept for inspection: {state}", file=sys.stderr)
    return code


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))
