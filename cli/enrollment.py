"""The three verbs an operator runs against a coordination server a deployment
places: mint a join credential, read what the server admits, end one membership.

Each is one step on the machine of the entry the deployment states as its
coordination server, over the channel every other remote step uses and addressed
by the scope that machine's record states. Which entry that is, the command
learns from the record the build wrote and from nothing else: a coordination
server is not recognised by a module's identity, by a package in a closure or by
the text of a plan key.

Where the credential's bytes go is the whole discipline of this file. The verb
that mints runs the generator the deployment declared - the store path the plan
records for that value - on the machine the server answers on, reads the files
it wrote off the step's own output stream, and writes them into the value
source. No argument vector of the run carries the bytes in any encoding, no line
the verb prints carries one, and the handover stays the operator's own act
outside this tree.

None of these verbs writes anything into the deployment, the registry or the
plan. A node is the coordination server's own fact, and the only gate from a
mesh back into evaluation is an operator-reviewed declaration edit.
"""

from __future__ import annotations

import os
from collections.abc import Callable, Mapping, Sequence
from pathlib import Path

import apply
import manifest
import remote
from errors import ApplyError
from manifest import Coordination, Deployment, Entry

# What a deployment writes beside its realisation statement, named here because
# every refusal about its absence names it.
STATEMENT = "coordinate"

# The mode a minted file is written at in the value source. A credential is
# bearer authority until it is spent, and what the plan says about a file's
# ownership is about the machine that receives it - this one is received by
# nobody.
SECRET_MODE = 0o600
PUBLIC_MODE = 0o644
PUBLIC = "public"


def statement(deployment: Deployment) -> Coordination:
    """Return what the deployment stated about its coordination server.

    Raises:
        ApplyError: If it stated none. The refusal names the statement to add
            and nothing is dialled: the plan holds no runtime fact about a
            coordination server, so this is the command's own refusal and no
            diagnostics row.
    """
    stated = deployment.coordination
    if stated is None:
        raise ApplyError(
            f"{deployment.root} states no coordination entry, so there is no server to ask: "
            f"state `{STATEMENT}` beside `realise` in the deployment, naming the plan key of the "
            f"entry that runs it and the generated value that is its join credential"
        )
    return stated


def entry_of(deployment: Deployment, stated: Coordination) -> Entry:
    """Return the placed entry the statement names.

    Raises:
        ApplyError: If the record names an entry this build places none of,
            which is a record read beside a plan it does not belong to.
    """
    entry = deployment.entries.get(stated.entry)
    if entry is None:
        raise ApplyError(
            f"the {manifest.COORDINATION} record names {stated.entry}, and this build places "
            f"{', '.join(sorted(deployment.entries)) or 'no entry at all'}"
        )
    return entry


def invite(
    deployment: Deployment,
    runner: remote.Runner,
    *,
    source: Path,
    ssh_key: Path | None = None,
    user: str = "root",
    base_env: Mapping[str, str] | None = None,
    log: Callable[[str], None] = remote.ignore,
) -> tuple[str, ...]:
    """Mint the credential the deployment declared, where the server answers.

    Args:
        deployment: The built deployment.
        runner: The channel every remote step of the command runs through.
        source: The value source the minted files are written into, laid out
            the way every other generated value is: `<source>/<key>/<file>`.
        ssh_key: The private key the step connects with.
        user: The login the step is taken as.
        base_env: The environment the run reads its channel out of.
        log: Where each line goes as it happens.

    Returns:
        The lines the verb printed, in the order it printed them. What it prints
        is where the bytes now are and the expiry they were minted under, and no
        byte of the key.

    Raises:
        ApplyError: If the deployment states no coordination entry, if the value
            the statement names records no program, if the machine does not hold
            the program this build names, or if the program wrote a file set the
            plan does not name - in which case nothing is written into the value
            source.
    """
    stated = statement(deployment)
    apply.refuse_inapplicable(deployment)
    entry = entry_of(deployment, stated)
    value = _credential(deployment, stated)
    named = tuple(file.name for file in value.files)
    program = value.program or ""

    address = manifest.address_of(entry)
    opts, env = remote.channel(dict(os.environ if base_env is None else base_env), ssh_key)
    script = remote.mint_script(
        program, stated.configuration, named, scope=manifest.entry_scope(deployment, entry)
    )
    lines, record = remote.recording(log)
    # The step's own answer carries the bytes, so it is read and never echoed:
    # every other step of the command prints what the machine said underneath
    # the step line, and this is the one whose answer is a secret.
    answered = _taken(
        runner,
        f"invite {value.key} on {entry.machine} at {user}@{address}",
        address,
        remote.ssh_argv(address, script, opts=opts, user=user),
        env=env,
        record=record,
        entry=entry,
        program=program,
    )
    got, wrote = remote.minted(answered, named)
    if tuple(sorted(got)) != tuple(sorted(named)) or wrote != tuple(sorted(named)):
        raise ApplyError(
            f"{value.key}: the program wrote {', '.join(wrote) or 'nothing'}, and the plan names "
            f"{', '.join(sorted(named))}, so nothing was written into {source}"
        )

    for file in value.files:
        written = source / value.key / file.name
        written.parent.mkdir(parents=True, exist_ok=True)
        written.write_bytes(got[file.name])
        written.chmod(PUBLIC_MODE if file.secrecy == PUBLIC else SECRET_MODE)
        record(f"minted {value.key} {file.name} -> {written}")
    # What a credential was minted under is a fact the operator is told. A file
    # the plan calls secret is named and never read back into a line.
    for file in value.files:
        if file.secrecy == PUBLIC:
            record(f"{file.name} {got[file.name].decode(errors='replace').strip()}")
    for file in value.files:
        if file.secrecy != PUBLIC:
            record(f"hand {source / value.key / file.name} over from there, outside this tree")
    return tuple(lines)


def members(
    deployment: Deployment,
    runner: remote.Runner,
    *,
    ssh_key: Path | None = None,
    user: str = "root",
    base_env: Mapping[str, str] | None = None,
    log: Callable[[str], None] = remote.ignore,
) -> tuple[str, ...]:
    """Print what the coordination server admits, as the server answered it.

    The answer is printed as it came back: the server masks a credential it
    minted to its leading fragment, so a listing carries no bearer authority,
    and nothing of it is read into anything the planner evaluates.

    Returns:
        The lines the verb printed.

    Raises:
        ApplyError: If the deployment states no coordination entry, or the
            machine refused the step.
    """
    return _asked(
        deployment,
        runner,
        ("list",),
        ssh_key=ssh_key,
        user=user,
        base_env=base_env,
        log=log,
    )


def expel(
    deployment: Deployment,
    runner: remote.Runner,
    identifier: str,
    *,
    ssh_key: Path | None = None,
    user: str = "root",
    base_env: Mapping[str, str] | None = None,
    log: Callable[[str], None] = remote.ignore,
) -> tuple[str, ...]:
    """End one membership at the coordination server, by the identifier it printed.

    Args:
        identifier: The node identifier the listing printed. A machine of the
            registry is refused in its place: a node is the server's own fact,
            and the registry's name for a machine is not the server's name for
            a node.

    Returns:
        The lines the verb printed.

    Raises:
        ApplyError: If the deployment states no coordination entry, if the
            identifier is a machine the registry declares, or if the machine
            refused the step.
    """
    machines = {
        key.removeprefix(manifest.MACHINE_PREFIX)
        for key in deployment.plan
        if key.startswith(manifest.MACHINE_PREFIX)
    }
    if identifier in machines:
        raise ApplyError(
            f"{identifier} is a machine this registry declares, and an expulsion takes the node "
            f"identifier the listing printed: a node is the coordination server's own fact, and "
            f"the registry's name for a machine is not the server's name for a node"
        )
    return _asked(
        deployment,
        runner,
        ("expel", identifier),
        ssh_key=ssh_key,
        user=user,
        base_env=base_env,
        log=log,
    )


def _credential(deployment: Deployment, stated: Coordination) -> manifest.Value:
    """Return the generated value the statement names as the join credential.

    Raises:
        ApplyError: If the build carries no such value, if it records no
            program - the credential a verb mints is the generator the
            deployment declared and never an invocation of the command's own -
            or if it names no file for the minting to write.
    """
    value = deployment.values.get(stated.credential)
    if value is None:
        raise ApplyError(
            f"the {manifest.COORDINATION} record names {stated.credential} as the join "
            f"credential, and this build carries the generated values "
            f"{', '.join(sorted(deployment.values)) or 'none at all'}"
        )
    if not value.program:
        raise ApplyError(
            f"{value.key} records no program, and the credential a verb mints is the generator "
            f"the deployment declared rather than an invocation of the command's own"
        )
    if not value.files:
        raise ApplyError(f"{value.key} names no file, so a minting has nothing to write")
    return value


def _asked(
    deployment: Deployment,
    runner: remote.Runner,
    argv: Sequence[str],
    *,
    ssh_key: Path | None,
    user: str,
    base_env: Mapping[str, str] | None,
    log: Callable[[str], None],
) -> tuple[str, ...]:
    """Take one verb's step on the coordination machine and echo what it said."""
    stated = statement(deployment)
    apply.refuse_inapplicable(deployment)
    entry = entry_of(deployment, stated)
    address = manifest.address_of(entry)
    opts, env = remote.channel(dict(os.environ if base_env is None else base_env), ssh_key)
    script = remote.coordination_script(
        stated.program,
        stated.configuration,
        argv,
        scope=manifest.entry_scope(deployment, entry),
    )
    lines, record = remote.recording(log)
    answered = _taken(
        runner,
        f"{argv[0]} {stated.entry} on {entry.machine} at {user}@{address}",
        address,
        remote.ssh_argv(address, script, opts=opts, user=user),
        env=env,
        record=record,
        entry=entry,
        program=stated.program,
    )
    for line in answered.splitlines():
        record(f"  {line}")
    return tuple(lines)


def _taken(
    runner: remote.Runner,
    step: str,
    address: str,
    argv: list[str],
    *,
    env: dict[str, str],
    record: Callable[[str], None],
    entry: Entry,
    program: str,
) -> str:
    """Announce one verb's step, take it, and return what the machine said.

    The step goes through the one context every remote step of the command is
    taken in, so it is announced before it is attempted and a machine that
    refuses is named with what it printed. What the machine said is returned
    rather than echoed under the step line: one caller here reads a secret out
    of it.

    Raises:
        ApplyError: If the machine refused. A machine that does not hold the
            program this build names is refused in its own words naming the
            entry and the path, because that program arrives with the entry's
            own closure and an apply is what puts it there.
    """
    with remote.taking(step, address, record):
        answered = _answer(runner, argv, env=env, entry=entry, program=program)
    return answered


def _answer(
    runner: remote.Runner,
    argv: list[str],
    *,
    env: dict[str, str],
    entry: Entry,
    program: str,
) -> str:
    """Return what the machine said, naming a machine that holds no such program."""
    try:
        return runner.output(argv, env=env)
    except remote.Refused as refused:
        if refused.status not in remote.MISSING:
            raise
        raise ApplyError(
            f"{entry.machine} does not hold {program}, which this build names for {entry.key}: "
            f"apply the deployment, which is what copies the entry's own closure onto that "
            f"machine"
        ) from refused
