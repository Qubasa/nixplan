## Context

See `proposal.md` for why. What shapes the approach:

- The vocabulary is a flat attrset of atoms read once per unit (`lib/module.nix:83-100`,
  `:922-924`), and its two existing pairs are flat: `restart` with `restartSec`, and each directory
  kind with its own mode (`lib/module.nix:62-81`). A field's row reads the same domain the atom does
  (`lib/atoms.nix:17-22`, `:99-101`).
- A field missing from `unitDirectives` fails the image build on purpose (`image/read.nix:90-93`,
  refusal at `:686-687`), so there is no such thing as a flakelet-only vocabulary field.
- flakelet starts exactly one file after switching and rolls the generation back if it or any unit of
  the entry fails (`docs/design.md` update-flow steps 5 and 6 and "Health checks are units",
  `docs/reference/service-module.md` "Activation semantics", at the locked revision). That file is
  `<name>-health.service`. nixplan renders no `<name>.service` at all - every unit file is
  `${name}-${unit}.service` (`image/read.nix:243`) - so the health file is the only name of the
  entry's namespace that is not already a unit's.
- `portablectl` has no generation to return to (`cli/report.py:30-32`); the attach script starts the
  attachment's unit list under `set -eu` (`image/default.nix:327`, `:362-366`).
- `lib/` never raises, so every new check is a row. A realiser raises only where it cannot render a
  fact the plan recorded, and each refusal carries the identifier of the row that reports the same
  condition first.

## Goals / Non-Goals

**Goals:**

- One fact per unit that a realiser can turn into the file flakelet gates on.
- One derivation of the derived unit's name, read by every check that already asks about a unit file
  name.
- One rendering of the derived unit, identical under both realisers.
- Both realisers coherent: the image carries and starts the probe, and says that nothing rolls back.

**Non-Goals:**

- No health, readiness or liveness state in the plan, and no probe evaluated, ordered or run by the
  planner (see `specs/planner/unit-vocabulary/spec.md`, `A probe is a command and a bound and nothing
  else`).
- No `[Install]` decision moved into the plan.
- No change to `cli/`: `flakelet activate` already exits non-zero for a rolled-back deploy
  (`docs/reference/cli.md`, "Exit status") and `cli/remote.py:421-427` already runs it as one step
  whose failure is the command's own error.
- No second declaration site for a directory, and no `Type=` or `WatchdogSec=` in the vocabulary.
- `declare-service-state` is untouched.

## Decisions

### D1 - The field is a flat pair, `probe` and `probeTimeout`, over existing atoms

`probe = atoms.string`, the command; `probeTimeout = atoms.duration`, the bound. No new atom: the
command is a command like `command`, `stopCommand` and `reloadCommand`, and the bound is a duration
like `timeout` and `restartSec`. `lib/atoms.nix` gains one exported predicate and no type (D5).

Alternatives. A nested record `probe = { command; timeout; }` would need an atom of its own and would
make `unit-field-type-mismatch` name a record where every other field names a value, and the
vocabulary's own reading is one `verify` per top-level key (`lib/module.nix:922-924`), so a record
would either hide its inner mistakes or grow a second reading beside the one that exists. A
`probeCommand`/`probeTimeout` pair was rejected because the tree's pair naming is
`<thing>`/`<thing><Qualifier>` - `restart`/`restartSec`, `stateDirectory`/`stateDirectoryMode` - and
because C2 fixes the field's name as `probe`.

Nothing else earns a place. A repeat interval is a watchdog or a second schedule, and the vocabulary
carries neither `Type=` nor `WatchdogSec=`, which is the same reason the restart domain is four
values and not seven. A failure threshold is a retry policy for a check, which is `restart` on the
service it checks. An account of the probe's own would be a second identity on one unit, and the
derived unit's identity is the probed unit's (D4).

### D2 - The bound is required, and a zero bound is a row

`probeTimeout` is recordable only beside a `probe` and a `probe` only beside a `probeTimeout`. The
second direction is stricter than `restart`/`restartSec` on purpose: a policy with no delay is a
complete statement, while an unbounded probe is bounded by the service manager's own default
(upstream's sugar writes `TimeoutStartSec=1min`), and a default this vocabulary does not record is
the one thing a unit field may never be. Making the bound optional would force a realiser to invent
one, which is what `image/`'s and `flakelet/`'s refusals exist to prevent.

A bound spelling zero is refused because `TimeoutStartSec=0` is systemd's spelling of *no* bound: the
value that looks tightest is the absence of the property the field was added for. The duration type
admits `0`, `0s`, and any concatenation whose components are all zero (`lib/atoms.nix:80-82`), so the
check is over the spelling and not over the literal, and it lives in `lib/atoms.nix` as an exported
`isZeroDuration` beside `isWildcardAddress`, which is the same shape of decision - a spelling refused
as a shape rather than as a list of literals - and beside the domains the rows already read. The atom
itself keeps admitting zero: `timeout` and `restartSec` may legitimately state it, and narrowing the
type would re-key plans that state it today.

### D3 - One probe per entry, and the derived name is `<service name>-health.service`

flakelet's step 5 starts one file per entry. Deriving `<name>-<unit>-health.service` instead would
produce a file the endpoint never starts, so the change would render a probe nothing runs and gate
nothing - the whole point of the change. An entry is also activated and rolled back as one
(`docs/design.md`, "All units of one entry form one generation"), so whether the entry is serving is
one question. Hence: the field is per unit, because the probe needs the probed unit's identity and
ordering, and two units of one entry declaring one is `unit-probe-declared-twice` with neither
statement recorded, in the idiom of `unit-directory-declared-twice`.

The name is derived in `unitFilesOf` (`image/read.nix:250-253`), which is the one function
`flakelet/read.nix`'s `acceptsUnit` (`flakelet/read.nix:72-75`), `image/read.nix`'s own unit rule
(`:268-269`) and `operator/read.nix` (`:121`, `:257`, `:469-508`) all read. Consequences, all by
existing:

- flakelet's rule matches `name(-<word>)?(@<word>)?\.(service|socket|target|timer|path)`, so
  `<name>-health.service` is accepted whenever the service name itself is.
- the image's rule matches `name-<word>\.(service|timer)`, so it is accepted there too.
- the per-machine unit-file index sees the derived name, so two entries on one machine deriving one
  probe file is `operator-entry-unit-file-collision` with no edit to that check.
- the deployment record's `units` list grows, which is what `cli/manifest.py:288` and the report's
  unit-file comparison read, and what `apply`'s value-write restart step names. A completed oneshot
  is inactive, and `systemctl try-restart` skips an inactive unit, so the probe is not re-run by a
  value that moved.
- `unit-value-newline` (`lib/module.nix:1042-1043`), `closure-path-undeclared` and
  `vars-path-off-delivery-set` (`lib/plan.nix:566-573`, `:682-710`, `:635-677`) all walk the unit
  record at any depth, so the probe is scanned without a scan naming it.

One case the existing index answers badly: a declared unit named `health` derives the same file as the
entry's probe. That is one entry claiming one name twice, and the existing row's sentence is about
two entries ("entries X, X all derive ..."), so `operator/read.nix` gains
`operator-entry-probe-unit-file-taken`, naming the entry, the declared unit and the file. It belongs
there because the unit-file namespace's owner is the reading that derives the names, and `lib/` cannot
know a realiser's derivation.

### D4 - The derived unit inherits the account and nothing that owns a resource

It carries `Type=oneshot`, `After=` and `Requires=` the probed unit's file, `ExecStart=` the probe,
`TimeoutStartSec=` the bound, the probed unit's `User=` if it declared one, the entry's host-path
binds, and no `[Install]`.

`Requires=` beside `After=` is what makes starting the probe on a machine whose service is not active
fail rather than succeed, which is the gate. Upstream inherits the account for the same reason the
common probe cases need it - a `0660` socket, a read-only self-test - and nixplan's readability
question is then unchanged: `util.admits` was asked about the probed unit's account, and the probe
runs as the same account, so no new denial and no new `slot-reads-value-unreadable-by-user` case
exists.

It declares **no** directory of any kind. A `RuntimeDirectory=` on a unit that exits is deleted when
it exits, so a probe declaring the probed unit's runtime directory would delete the directory the
service is using - the destructive case `entry-unit-directory-shared` is a warning about. A state or
cache directory needs no declaration to be *read* by a static account, and the vocabulary has no
`DynamicUser`, so nothing forces the declaration that upstream's sugar needs. The derived unit
therefore adds no claimant to the index `lib/plan.nix:815-820` builds, and `entry-unit-directory-shared`
keeps meaning what it means: two declarations, not one declaration and one derivation.

A probe that needs another account, or a directory of its own, is out of this vocabulary. That is the
"black-box probe" upstream says is the one to spell out, and spelling it out here would be a second
identity on one unit.

### D5 - The rendering has one home and neither realiser wraps it

`image/read.nix`'s `renderedUnitsBy` (`:897-915`) renders the probe unit itself, beside the per-unit
and per-timer files, using a `renderProbe` of the shared reading rather than a third entry in the
`renderers` record. Reason: the only thing the two realisers differ about for a unit file is the
install section (`flakelet/read.nix:99-102`, `:129-134`), and for the probe they agree - it carries
none. flakelet starts it by name, and an install section would additionally queue it at every boot
and after `flakelet boot`; the image renders no install section for anything. One text, rendered
once, is therefore also the strongest available statement that the two realisers cannot drift about
the file that decides an activation.

`attachment.units` (`image/read.nix:932-935`) derives the unit list a second time, for the attach
script. It gains the probe file from the same helper `unitFilesOf` uses, so the two lists stay one
list in practice; the alternative - letting the attachment derive its own - is how two derivations of
one name start disagreeing.

`unitDirectives` gains `probe = "ExecStart"` and `probeTimeout = "TimeoutStartSec"`. They are the
directives the fields really become, in the derived unit's file rather than in the probed unit's, and
that is closer to the table's contract than `extends = null` is. The probed unit's own file carries
neither.

### D6 - The image starts the probe and rolls nothing back, and says so

The probe file is in the attachment's unit list, so `systemctl start` at attach time starts it, and a
failing probe fails the attach step under `set -eu`: the command's error names the entry, the machine
and what the machine printed. Nothing rolls back - there is no generation, detaching would leave the
machine running nothing, and asking this realiser for a rollback is already a refusal naming the entry
and its realiser. The recovery is a second apply of a corrected build.

Alternatives rejected. Rendering the probe into the image and *not* starting it would make the field a
comment under one realiser while the directive table claims it renders it. Making the image realiser
refuse a probed entry would make a portable image reject a deployment the vocabulary accepts, and
which realiser realises an entry is a statement beside the deployment, so one entry can legitimately
be both. Teaching the attach script to detach on a failed probe would invent the rollback
`cli/report.py:30-32` says an image cannot have.

### D7 - Realiser refusals, each accounted to a row

A realiser raises only where it cannot honestly render a recorded fact. Four conditions qualify, all
reachable only from a hand-written plan, because the planner records none of them:

| refusal | account |
| --- | --- |
| a unit records `probe` and no `probeTimeout` | `unit-probe-without-timeout` |
| a unit records `probeTimeout` and no `probe` | `unit-probe-timeout-without-probe` |
| a unit records a `probeTimeout` spelling zero | `unit-probe-timeout-unbounded` |
| two units of one entry record a `probe` | `unit-probe-declared-twice` |

The first three would each make the renderer write a bound the plan does not state, or drop a field
the plan does state. The fourth is ambiguity: one file, two candidate commands. A probe on a
`oneShot` or scheduled unit is *not* a refusal - it renders fine, it is one row of the planner's
table, and a refusal for every row would make the realisers a second table.

`tests/unit/diagnostics.nix` reads the realiser sources it is handed and fails an account naming a
row nobody produces, so all four identifiers must be produced by `lib/module.nix` - which they are,
being the rows of D2 and D3.

### D8 - Perf: gate the probe rows behind one question

Two more vocabulary keys are two more membership tests and, where declared, two more `verify` calls
per unit of every entry; seven rows computed per unit would be worse. The probe rows are therefore
computed behind one `unit ? probe || unit ? probeTimeout` gate per unit, and the cross-unit
`unit-probe-declared-twice` count behind the same question asked once per entry, in the idiom of
`util.anyLineBreak` gating `util.stringsDeep`. `unitFilesOf` gains one `any` over the unit names per
entry.

The gate is two-sided with a 0.15 margin, so a regression is a task to fix and never a re-recorded
budget. If the measured cost still moves the counters, the next lever is computing the gate once
beside the existing per-unit fold rather than as a second traversal - not a wider budget.

### D9 - Where a failing probe is proved

`tests/e2e/wired-pair/` is the flakelet folder: it already builds `default` and `changed`, asserts
generation 2 and asserts a rollback. A third build whose probe fails is the smallest addition that
proves the gate, and its phases go **last** in file order, because a rolled-back activation records a
hold keyed on the artifact and every phase after it would be applying against a held entry. The
folder's phases are session-scoped and order-dependent and nothing is restored between them, so last
is the only safe position.

The image half is proved in `tests/e2e/portable-image/`, which owns every image assertion, also as
the folder's last phases, against a build of its own whose probe fails.

`tests/e2e/shared-postgres/` is the nearest existing shape - it asserts recovery from a killed main
process - and it is deliberately left alone: its claim is the service manager's `restart`, which is
the other half of the pair and already proved.

## Risks / Trade-offs

- [A probe is per unit but an entry may carry only one] → The row names both units and says why; the
  alternative is a file the endpoint never starts. If a later change gives an entry a main unit, the
  one-per-entry rule is the thing to revisit, not the field's shape.
- [flakelet's hold makes a failed probe sticky: a corrected build clears it by changing the artifact,
  but re-applying the same artifact does not] → Out of scope here, and visible: the apply exits
  non-zero and reports what the endpoint printed. Worth a sentence in `CLAUDE.md` under the
  realisers so the next reader does not diagnose it as a nixplan bug.
- [The derived unit runs inside the portable image under a confining profile, so a probe needing an
  access the profile denies fails at run time] → It is shown the entry's own binds and runs as the
  entry's account, so it is denied exactly what the probed unit is denied, and that comparison is
  already a build-time refusal (`imageReader.denials`). A probe naming a path the entry is not shown
  is the ordinary case of the same rule.
- [Two more fields cost thunks per unit on every entry, probed or not] → D8, plus a measured before
  and after in `tasks.md`.
- [`lib/atoms.nix` is edited by `name-the-machine-a-run-dials` too, which adds `sshPublicKey`] →
  Different construct, same file. Whichever lands second rebases one attribute; nothing here reads
  that atom and nothing there reads `isZeroDuration`.
