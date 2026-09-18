"""The operator's command: nine subcommands over a built deployment.

`plan` and `build` answer what a deployment is and what building it produced.
`apply` puts it on the machines it names, `status` asks those machines what they
hold, and `rollback` returns one entry to its previous generation. `diagnose`
answers the one question that needs no artifact: what the planner said about the
deployment, which is why it is the only subcommand that realises nothing. And
`invite`, `members` and `expel` are the membership acts against the coordination
server the deployment states, which are acts against that server rather than
steps of an apply.

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
import diagnose
import enrollment
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
        dry_run=args.dry_run,
        retire=args.retire,
        log=print,
    )
    if args.dry_run:
        # On stderr, so that the two runs are comparable line by line on stdout.
        print("planner: a dry run, so no machine was contacted", file=sys.stderr)
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
    report.rollback(
        deployment,
        remote.Subprocess(),
        args.only[0],
        ssh_key=Path(args.ssh_key) if args.ssh_key else None,
        user=args.user,
        log=print,
    )
    return 0


def _diagnose(args: argparse.Namespace) -> int:
    answered = diagnose.answer(args.target)
    if args.json:
        print(json.dumps(list(answered.rows), indent=2))
    else:
        for line in answered.rendered.splitlines():
            print(line)
    return 1 if answered.errors else 0


def _invite(args: argparse.Namespace) -> int:
    deployment = manifest.read(manifest.resolve(args.target))
    enrollment.invite(
        deployment,
        remote.Subprocess(),
        source=Path(args.values),
        ssh_key=Path(args.ssh_key) if args.ssh_key else None,
        user=args.user,
        log=print,
    )
    return 0


def _members(args: argparse.Namespace) -> int:
    deployment = manifest.read(manifest.resolve(args.target))
    enrollment.members(
        deployment,
        remote.Subprocess(),
        ssh_key=Path(args.ssh_key) if args.ssh_key else None,
        user=args.user,
        log=print,
    )
    return 0


def _expel(args: argparse.Namespace) -> int:
    deployment = manifest.read(manifest.resolve(args.target))
    enrollment.expel(
        deployment,
        remote.Subprocess(),
        args.node,
        ssh_key=Path(args.ssh_key) if args.ssh_key else None,
        user=args.user,
        log=print,
    )
    return 0


SUBCOMMANDS: dict[str, Subcommand] = {
    "plan": _plan,
    "build": _build,
    "apply": _apply,
    "status": _status,
    "rollback": _rollback,
    "diagnose": _diagnose,
    "invite": _invite,
    "members": _members,
    "expel": _expel,
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
        ("diagnose", "print the diagnostics of a deployment, realising nothing"),
        ("invite", "mint the join credential of the mesh a deployment coordinates"),
        ("members", "print what the coordination server of a deployment admits"),
        ("expel", "end one membership at the coordination server of a deployment"),
    ):
        description = help_text
        if name == "rollback":
            description += ". It takes exactly one --only, the entry to roll back"
        if name == "diagnose":
            description += (
                ". A directory a build produced is read from the two files that build wrote, and "
                "any other target is evaluated once for the two attributes a deployment publishes "
                "the rows and the rendered table under. It exits 1 where a row carries an error"
            )
        if name == "invite":
            description += (
                ". The credential is the generator the deployment declared, run on the machine "
                "the server answers on: its bytes arrive on the step's own output stream, reach "
                "no argument vector and no machine, and are written under --values for the "
                "operator to hand over out of band"
            )
        if name == "members":
            description += (
                ". The server's answer is printed as the server made it, and nothing of it is "
                "read back into the deployment: the server's database is no source the planner "
                "reads"
            )
        if name == "expel":
            description += (
                ". It takes the node identifier the listing printed, and refuses a machine the "
                "registry declares in its place: a node is the server's own fact"
            )
        sub = subcommands.add_parser(
            name,
            help=help_text,
            description=description,
            epilog=EPILOG,
            formatter_class=argparse.RawDescriptionHelpFormatter,
        )
        sub.add_argument("target", help=TARGET)
        if name == "diagnose":
            sub.add_argument(
                "--json",
                action="store_true",
                help=(
                    "print the rows themselves instead of the table, in the order the table put "
                    "them and with every field a row carries"
                ),
            )
        if name == "expel":
            sub.add_argument(
                "node",
                help="the node identifier the listing printed, and never a registry machine name",
            )
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
        if name in ("apply", "status", "rollback", "invite", "members", "expel"):
            sub.add_argument("--ssh-key", metavar="PATH", help="the private key to connect with")
            sub.add_argument(
                "--user", default="root", metavar="USER", help="the login user on each machine"
            )
        if name == "invite":
            sub.add_argument(
                "--values",
                required=True,
                metavar="DIR",
                help=(
                    "the value source the minted bytes are written into, laid out "
                    "<DIR>/<entry-key>/<file>; the same directory an apply reads them from"
                ),
            )
        if name == "apply":
            sub.add_argument(
                "--values",
                metavar="DIR",
                help="a directory of generated bytes, laid out <DIR>/<entry-key>/<file>",
            )
            sub.add_argument(
                "--dry-run",
                action="store_true",
                help=(
                    "make every refusal, print the value writes, copies and activations this "
                    "run would perform in the order it would perform them, and contact no "
                    "machine"
                ),
            )
            sub.add_argument(
                "--retire",
                action="store_true",
                help=(
                    "remove what the machines hold that this build names no entry for, with the "
                    "endpoint's own removal verb and before anything is put in place; it deletes "
                    "no state, and every run announces such a holding whether or not it is given "
                    "this flag"
                ),
            )
    return root


def main(argv: Sequence[str] | None = None) -> int:
    """Run one invocation of the command, over ``argv`` or the process's own.

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
