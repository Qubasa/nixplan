"""The operator's command: five subcommands over a built deployment.

`plan` and `build` answer what a deployment is and what building it produced.
`apply` puts it on the machines it names, `status` asks those machines what they
hold, and `rollback` returns one entry to its previous generation.

A target is a built directory or a flake reference, and it is resolved once per
invocation, because a second build of the same reference is a second evaluation
of the same deployment. A refusal reaches the operator as a message on stderr
and a non-zero exit, and the message of an unbuildable deployment is the build's
own output, which carries the rendered diagnostics table.

The command talks to `nix` and `ssh` and reads a built directory. It imports
nothing of the evaluating side: what a deployment is, it learns from
`manifest.json`.
"""

from __future__ import annotations

import argparse
import json
import sys
from collections.abc import Callable, Sequence
from pathlib import Path

import apply
import manifest
import remote
import report
from errors import ApplyError

Subcommand = Callable[[argparse.Namespace], int]


def _plan(args: argparse.Namespace) -> int:
    deployment = manifest.read(manifest.resolve(args.target))
    print(json.dumps(deployment.plan, indent=2, sort_keys=True))
    return 0


def _build(args: argparse.Namespace) -> int:
    root = manifest.resolve(args.target)
    print(root)
    deployment = manifest.read(root)
    for line in report.describe(deployment):
        print(line)
    return 1 if deployment.errors else 0


def _apply(args: argparse.Namespace) -> int:
    deployment = manifest.read(manifest.resolve(args.target))
    apply.apply(
        deployment,
        remote.Subprocess(),
        source=Path(args.values) if args.values else None,
        only=tuple(args.only),
        ssh_key=Path(args.ssh_key) if args.ssh_key else None,
        user=args.user,
        log=print,
    )
    return 0


def _status(args: argparse.Namespace) -> int:
    deployment = manifest.read(manifest.resolve(args.target))
    answered = report.status(
        deployment,
        remote.Subprocess(),
        only=tuple(args.only),
        ssh_key=Path(args.ssh_key) if args.ssh_key else None,
        user=args.user,
        log=print,
    )
    if not answered.unasked:
        return 0
    print(f"planner: {', '.join(answered.unasked)} could not be asked", file=sys.stderr)
    return 1


def _rollback(args: argparse.Namespace) -> int:
    deployment = manifest.read(manifest.resolve(args.target))
    if len(args.only) != 1:
        raise ApplyError("rollback takes exactly one --only, the entry to roll back")
    for line in report.rollback(
        deployment,
        remote.Subprocess(),
        args.only[0],
        ssh_key=Path(args.ssh_key) if args.ssh_key else None,
        user=args.user,
    ):
        print(line)
    return 0


SUBCOMMANDS: dict[str, Subcommand] = {
    "plan": _plan,
    "build": _build,
    "apply": _apply,
    "status": _status,
    "rollback": _rollback,
}


# What the help has to reach on its own, read as somebody's only document: what a
# target may be, what a plan key looks like, every constraint a parser enforces,
# and where the fuller document is.
TARGET = "a built deployment directory, or a flake reference naming an attribute that builds one"

KEY_SHAPE = (
    "A plan key is <instance>:<service>@<machine>, and a generated value's is "
    "<instance>:vars/<generator> or <instance>:vars/<generator>@<machine>. `planner build` "
    "prints one per line, which is where a key is read off rather than guessed."
)

TARGETS = (
    "A target is either a directory a build of the deployment produced, which holds "
    "manifest.json beside plan.json, or a flake reference that names an attribute building "
    "one, like .#my-deployment. The attribute has to be named: a bare directory that is not "
    "a flake is read as a reference to a registry entry rather than as a path."
)

DOCUMENT = (
    "The command in full is docs/operator.md of nixplan: "
    "https://github.com/Qubasa/nixplan/blob/main/docs/operator.md"
)

EPILOG = f"{TARGETS}\n\n{KEY_SHAPE}\n\n{DOCUMENT}"


def parser() -> argparse.ArgumentParser:
    """Return the command's argument parser, with one subparser per subcommand."""
    root = argparse.ArgumentParser(
        prog="planner",
        description="Build a planned deployment and put it on the machines it names.",
        epilog=EPILOG,
        formatter_class=argparse.RawDescriptionHelpFormatter,
    )
    subcommands = root.add_subparsers(dest="command", metavar="<subcommand>", required=True)

    for name, help_text in (
        ("plan", "print the plan of a deployment"),
        ("build", "build a deployment and report what it holds"),
        ("apply", "put a built deployment on the machines it names"),
        ("status", "ask each machine what it holds of a deployment"),
        ("rollback", "return one entry to its previous generation"),
    ):
        description = help_text
        if name == "rollback":
            description += ". It takes exactly one --only, the entry to roll back"
        sub = subcommands.add_parser(
            name,
            help=help_text,
            description=description,
            epilog=EPILOG,
            formatter_class=argparse.RawDescriptionHelpFormatter,
        )
        sub.add_argument("target", help=TARGET)
        if name in ("apply", "status", "rollback"):
            sub.add_argument(
                "--only",
                action="append",
                default=[],
                metavar="KEY",
                required=name == "rollback",
                help=(
                    "the one plan key to roll back; exactly one is required"
                    if name == "rollback"
                    else "restrict the run to this plan key; repeatable"
                ),
            )
            sub.add_argument("--ssh-key", metavar="PATH", help="the private key to connect with")
            sub.add_argument(
                "--user", default="root", metavar="USER", help="the login user on each machine"
            )
        if name == "apply":
            sub.add_argument(
                "--values",
                metavar="DIR",
                help="a directory of generated bytes, laid out <DIR>/<entry-key>/<file>",
            )
    return root


def main(argv: Sequence[str] | None = None) -> int:
    """Run one invocation of the command.

    Args:
        argv: The arguments to parse, the process's own by default.

    Returns:
        The exit status: zero, or one for a refusal reported on stderr.
    """
    args = parser().parse_args(argv)
    try:
        return SUBCOMMANDS[args.command](args)
    except ApplyError as refused:
        print(f"planner: {refused}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
