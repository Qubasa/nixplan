## Why

A delivered value is readable by root and by nobody else, and the deployment cannot say otherwise. A
generated file's record admits exactly one key - `lib/module.nix:365` is `allowed = [ "secrecy" ]` -
and the write is unconditionally `chmod 0400` as root (`cli/remote.py:282-284`). Two consequences,
both reached by the first service that is not a demo:

- **A service that runs as an account cannot read its own credential.** Under flakelet, confinement
  is `trusted` (`flakelet/read.nix:50`), so `User=` is rendered (`image/read.nix:524`) and the unit
  starts and then fails with `EACCES` on a file the plan told it to read. Nothing diagnoses it: the
  planner holds the unit's `user` and the file's mode and never compares them.
- **A confined image entry may not read a deployed secret at all.** `image/read.nix:246-262` denies
  "a host file only root may read" for **every** unit of the entry whenever the profile denies it,
  which is `default`, `nonetwork` and `strict` (`:45-57`). The only profile left is `trusted`, which
  drops `DynamicUser` and `PrivateUsers` wholesale. So confinement and secrets are mutually
  exclusive, and the denial is not a fact about the file - it is a fact about the file's mode, which
  the deployment is not allowed to state.

The workaround this repository uses is to route every secret through a root-run unit. That works and
it is what `tests/e2e/shared-postgres/` does, and it means a user's own service has to be
restructured around a permission the deployment could simply have declared. clan has `owner`,
`group`, `mode`, `neededFor` and `restartUnits` on a generated file
(`~/Projects/clan-core/modules/clan/export-modules/generic-generator.nix:149,158,171,175`); three of
those five are enough here.

## What Changes

- **A generated file record gains `owner`, `group` and `mode`**, defaulting to `root`, `root` and
  `0400` - which is what is written today, so every existing deployment is unchanged.
- **The write honours them**, still through one script that creates the parent directory under a
  restrictive umask and never leaves the file at a wider mode than the declared one, not even for the
  length of the write.
- **A re-apply restores them.** A value whose bytes are unchanged still has its owner, group and mode
  set, so a hand-edit on the machine does not survive an apply.
- **A unit that cannot open a value it reads is a row.** `slot-reads-value-unreadable-by-user` names
  the consuming entry, the unit, the unit's user, the slot, the export and the file's record: the
  planner holds both halves and compares them.
- **The image profile denial narrows from a fact about secrecy to a fact about permission.** A
  deployed secret is denied to a unit only where the file's record cannot admit that unit's reader.
  A confining profile runs a unit under a transient account, so a file the unit's own declared
  supplementary group owns is readable and is not denied.
- **`supplementaryGroups` joins the systemd extension directive table**, which is what lets a unit
  under a transient account read a file owned by a static group.

## Capabilities

### Modified Capabilities

- `planner/secret-delivery`: a generated file's record carries the ownership and mode it is delivered
  at; the defaults are what is written today; the record is part of the value's key.
- `planner/diagnostics`: a consuming unit whose user cannot open a value it declared a read of is an
  error row naming both halves.
- `operator/apply-command`: the value write honours the recorded ownership and mode, restores them on
  a re-apply, and never widens a file even transiently.
- `realiser/portable-service-image`: the denial of a deployed secret is read from the file's record
  and the unit's readers rather than from the file's secrecy alone; `supplementaryGroups` is
  renderable.

## Impact

- `lib/module.nix`: the generated-file record's allow-list, three fields with types, and the
  `slot-reads-value-unreadable-by-user` row.
- `lib/atoms.nix`: a `fileMode` atom, so `0400` and `0640` are typed and `640` is a row.
- `lib/resolve.nix`, `lib/plan.nix`: the record travels into each value entry's file record and into
  its key input, because two values delivered at two modes are two values.
- `cli/remote.py`, `cli/apply.py`: `write_script` takes the record; the ownership and mode are set on
  every apply, not only when the bytes moved.
- `image/read.nix`: `denialsOf` reads the record; `systemdDirectives` gains `supplementaryGroups`.
- `operator/read.nix`: `operator-entry-access-denied`'s condition narrows with the denial it mirrors.
- `secrets/backend.nix`: the rendered `deploy.remote` step writes at the recorded ownership and mode
  rather than at a literal `chmod 0400`.
- `tests/unit/{module,vars,plan,image,operator,diagnostics,secrets}.nix`, `docs/authoring.md`,
  `docs/secrets.md`, `docs/plan.md`, `docs/diagnostics.md`, `docs/operator.md`, `CLAUDE.md`.
- `tests/e2e/shared-postgres/`: the server reads its own password instead of having a root unit set
  it, and the consumer runs as an account. That is the deployment this change is measured on.
