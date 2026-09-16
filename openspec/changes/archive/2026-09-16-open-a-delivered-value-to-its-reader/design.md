## Context

See proposal.md - Why. The shapes involved:

- **The file record is read against a one-key allow-list** (`lib/module.nix:358-367`), and the row it
  produces for anything else is `keyRow`. Widening it is three entries plus two atoms.
- **The record travels already.** `lib/resolve.nix:940-951` builds each file's record - `deploy`,
  `secrecy`, `path`, `content` - and `lib/plan.nix:682-768` puts every value entry's `files` in the
  plan and in `keyInput`. Three more fields ride the same path.
- **Two writers exist, not one.** `cli/remote.py:265-285` writes an operator-supplied value, and
  `secrets/backend.nix:93` renders the `deploy.remote` step that writes a generated one. Both carry a
  literal `chmod 0400`, and both must read the record instead.
- **The denial is computed from data, in one function.** `denialsOf` (`image/read.nix:234-262`) is
  handed `denies`, `units` and `generated`, and both a raising caller and a row-producing caller ask
  it (`:288-297`, mirrored by `operator/read.nix`). Narrowing the condition there narrows the row and
  the refusal together, which is the property `tests/unit/diagnostics.nix` crosses.

## Goals / Non-Goals

**Goals:**

- Let a service read its own credential without being restructured around root.
- Make confinement and secrets compose, by making the denial a fact about permission rather than
  about secrecy.
- Diagnose the mismatch at plan time, from data the plan already holds, rather than at run time as
  an `EACCES` in a journal.
- Change nothing for a deployment that declares none of the three fields, down to the value entry's
  key and the delivered bytes' mode.

**Non-Goals:**

- No numeric uids or gids. An identifier is the machine's answer; a name is what a deployment can
  state portably, which is the reason `lib/atoms.nix` already gives for a unit's `user`.
- No account creation. Nothing in a plan creates an account and this change does not start; a
  recorded owner the machine does not have is a refusal naming it, which is the boundary
  `tests/e2e/guest.nix` records for `tests/e2e/shared-postgres/`.
- No `neededFor` and no `restartUnits`. The first is about boot ordering, which this tree does not
  model; the second is
  `openspec/changes/take-effect-on-a-second-apply`.
- No change to where a value lives. `/run/vars/<instance>/<generator>/<file>`
  (`lib/resolve.nix:949`) stays, and what a machine holds after a reboot is
  `openspec/changes/take-effect-on-a-second-apply`.
- No credential-loading mechanism. See the decision below.

## Decisions

### A group plus a supplementary group, not a credential directory

The systemd answer to "a confined service must read a root-owned secret" is `LoadCredential=`, which
reads the file as root and exposes it to the service under `$CREDENTIALS_DIRECTORY`. It is rejected
here for one reason: it changes the path. A module interpolates `results.<slot>.<export>.path`, and
the plan records one path per file; a realiser that relocated the bytes would make the path the plan
records wrong for exactly the entries this change exists to serve, and the alternative - a second
path field that only one realiser fills - is a plan field that says which realiser read the entry,
which this tree deliberately does not have.

A static group plus `SupplementaryGroups=` keeps one path and one record. The two statements the
deployment makes - the file's `group`, the unit's groups - are compared in `denialsOf`, which is one
place, at build time.

Alternatives considered:

- **An ACL on the delivered file.** Rejected: it is a second permission model beside the mode, and
  the write would have to know which accounts exist on the machine.
- **Widening the mode to world-readable.** Rejected: it is what the denial exists to prevent, and a
  deployment can already say it explicitly if it means it.
- **`trusted` plus a static user, as today.** Rejected as the answer, kept as a legal choice: it
  works and it drops `PrivateUsers` for the whole entry, which is a trade a deployment should make
  deliberately rather than because the tool left no other path.

### The defaults are what is written today

`root`, `root`, `0400`. So an unwidened record produces the same key, the same plan, the same script
and the same bytes on the machine, and the two "unchanged" scenarios are byte comparisons against a
recorded pre-change artifact rather than assertions about intent.

### The record enters the value's key

Two values delivered at two modes differ in something a reader can observe on the machine, so they
are two values. This follows the rule already stated for `program`, `per`, `deploy` and `files`, and
it is the opposite of `delivery`, which is deliberately outside the key because adding a consumer
does not change the bytes.

### The planner's row is realiser-independent, and the operator's is not

The planner compares the unit's declared `user` against the record. It cannot know that a confining
profile will impose a transient account, because the profile is stated beside the deployment and not
in the plan. So there are two conditions and two reporting layers, which is the split the tree
already uses: `lib/` reports what the plan states, `operator/read.nix` reports what the realisation
statement adds.

### Both writers read the record

`cli/remote.py`'s script and `secrets/backend.nix`'s rendered step both create the file at the
recorded mode before the first byte and then set owner and group, in that order, so no window exists
in which the bytes are present at a wider mode. `image/default.nix:169` already does exactly this
for a configuration file (`install -m 0600 /dev/null` before the first append), and the reason is
recorded in `CLAUDE.md`; this is the same recipe for a value.

The owner is set after the mode rather than before, because a file created as root at `0400` and then
chowned is never readable by the target account earlier than intended, while the reverse order
briefly hands the account a file at the writing umask.

## Risks / Trade-offs

- **A recorded owner that does not exist on a machine fails an apply mid-run.** → It is the command's
  own refusal naming the value, the machine and the account, printed after the step line, and the
  recovery is a second apply once the account exists. The alternative - creating accounts - is a
  machine-level power this tool does not take.
- **A group-readable secret is a wider secret.** → It is a statement the deployment now has to make
  explicitly, and the planner's row is what makes the previous silent alternative - a unit that
  cannot start - visible. A deployment that says nothing still gets `0400 root`.
- **`SupplementaryGroups=` is a seventeenth directive, and the table is meant to stay small.** → It
  is the one directive the denial rule needs to be satisfiable, and it is introduced together with
  the rule that reads it rather than as a general widening.
- **The planner's row can be wrong in one direction**: a unit whose account is a member of the
  file's group on the machine, without the unit declaring it, is refused although it would work. →
  That is deliberate. The plan cannot read a machine's group database, and a deployment that depends
  on one is a deployment whose correctness is not in the plan.
- **Every value entry's key input grows, so a deployment that adopts a mode re-keys its values.** →
  Adopting a mode is a change to the bytes on a machine; the value that was delivered at `0400` was a
  different delivered artifact. Regeneration is not implied: the bytes are the same and only the
  record moved, which is why the change is worth stating in `docs/secrets.md` beside the rotation
  rules.
