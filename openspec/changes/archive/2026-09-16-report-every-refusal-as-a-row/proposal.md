## Why

The repository states one rule about refusals in two places, and neither statement holds.
`CLAUDE.md` says of `image/` and `flakelet/` that "Every refusal there is a condition `mkPlan` also
reports as a row", and `image/read.nix:5-8` says "Every refusal here is a condition mkPlan reports
too, so a caller that wants the row already has it". The smallest deployment the documentation shows
is the shortest disproof.

`docs/README.md:52-125` shows one service publishing a greeting and one echoing it. Evaluated as
written, the planner answers `diagnostics = [ ]` and `applicable = true`, and the plan carries
`talker:main@host`, `hearer:main@host` and `machine:host`. Reading either placed entry as an artifact
raises, and no row anywhere says why:

- `hearer:main@host` fails with "entry `hearer:main@host` records no `closure`". Its one unit runs
  `/bin/echo` and names no store path, so the declared closure is the empty list, `pruned`
  (`lib/plan.nix:22`) drops an empty list and an empty attribute set from every entry it emits, and
  `required` (`image/read.nix:118-123`) refuses a field an entry does not record.
- `talker:main@host` fails with "entry `talker:main@host` records no `units`". It computes an export
  and runs nothing, so the same pruning removes its `units`.

A unit that depends on no store path, and a service that publishes a value: two ordinary services,
unbuildable, with an empty table above them.

Above the plan the rule fails for a second reason - the realisation statement is a fact `mkPlan`
never sees, and the reading that does see it checks almost none of it. Each of the following was
observed against `operator/read.nix` over a one-entry plan:

- One typo in a statement key, `realise."svc:onlyy" = { realiser = "image"; profile = "strict"; }`,
  is read as a statement about nothing. The reading answers `realiser = "flakelet"`,
  `profile = null` and no row (`operator/read.nix:70-82`), so a user who asked for a confined image
  receives an unconfined artifact. `tests/unit/operator.nix:236-256` records that outcome as
  intended.
- `profile = "stricT"` passes the reading unexamined, because
  `operator-image-profile-missing` fires only when the profile is `null`
  (`operator/read.nix:135-142`). `image/read.nix:195-199` refuses it later as a bare string, even
  though the row the reading already writes for an absent profile names `imageReader.profileNames`
  in its own resolution text.
- `realise = { default = { realiser = "image"; profile = "strict"; }; "svc:only" = { realiser =
  "image"; }; }` refuses with `operator-image-profile-missing`. `realiser` falls back to the default
  statement and `profile` does not (`operator/read.nix:102-106`).

Two of the reading's classifications are text matches on a key rather than tests of a record.
`isMachineRecord = key: match "machine:.*" key != null` (`operator/read.nix:49`), and `machine` is
not a reserved instance name: an instance called `machine` produces the placed key
`machine:only@host`, and the reading then answers no entries, no values, no rows and
`refused = false`. The build produces a tree with no `entries/`, and an apply of it copies nothing
and reports success. `isValueEntry = key: match ".*:vars/.*" key != null` (`:51`), and a member
called `vars/x` produces `svc:vars/x@host`, which is routed into `readValue` and aborts with
`attribute 'delivery' missing` - a failure `builtins.tryEval` cannot catch, out of a file whose
header calls itself total.

Three more consequences of the same gap:

- flakelet is the default realiser, and it refuses any entry whose unit is shown a host path it
  would have to assemble - a configuration file (`flakelet/read.nix:135-139`). Assembling a
  configuration file is among the most ordinary things a service does, the worked fixture's
  `vault-repo:server@vault` is in that class, and `mkPlan`, the reading and the table are all silent
  before `nix build` throws a string.
- When the reading does refuse, `operator/default.nix:88-92` discards the derivation, so
  `plan.json`, `diagnostics.json` and `diagnostics.txt` are unreachable for the deployments those
  files exist to describe. `docs/operator.md:60-61` promises four answers off `passthru`, and an
  inapplicable deployment reaches none of them.
- The first row producer outside `lib/` writes the six fields of a row by hand three times
  (`operator/read.nix:126-152`), because `lib/default.nix:70-73` exports `render` and `mkTable` and
  not `row`, `error` or `warning`. It therefore skips `util.oneLine`, which
  `lib/diagnostics.nix:44-46` applies to the message, the evidence and the resolution of every row
  the library builds. A user-controlled value carrying a newline breaks the one-row-one-line shape
  that `diagnostics.txt` and every reader of it assume.

## What Changes

- **The layering rule becomes a requirement instead of a comment.** A refusal about a fact the plan
  carries is a row from `mkPlan`. A refusal about a fact the realisation statement carries is a row
  from `operator/read.nix`. A realiser raises only for a condition one of those two already reported
  as an error, so a caller always sees the row first and the raise second. The unit layer holds that
  rule to the source: every refusal condition in `image/read.nix` and `flakelet/read.nix` is
  answered by a named row producer above it.
- **A placed entry records `closure` and `units` whether or not either holds anything.** The pruning
  keeps applying to the fields a reader may treat as optional, and stops applying to the two a
  realisation reads. This is the rule `CLAUDE.md` already states for `delivery` and
  `deliveryDerivedFrom`: a reader must not be able to mistake either field for an absence. The
  golden plan of `fixtures/minimal-typed-edge` gains the fields the pruning was removing.
- **A placed entry that declares no unit is realised into nothing, and refused only when a statement
  names it.** The service that publishes a value and runs nothing has no artifact to build, so the
  build reads it, records it, and produces no artifact for it. A statement naming such an entry with
  a realiser is a refusal, because the statement asks for something that cannot exist.
- **The reading classifies a plan record by its shape.** A record carrying `delivery` is a generated
  value, a record carrying `placement` is a service entry, and a record carrying neither is a
  machine record. No classification reads the text of a key for anything but the instance, the
  service and the machine of a placed entry, which the key grammar defines. A record matching none
  of the three shapes is an error row naming the key, never a silent omission.
- **The reading answers the whole realisation statement.** A statement key naming no entry of the
  plan, a statement that is not a record, a profile outside the four the image realiser implements,
  and a field the entry-level statement omits and the default statement carries: each is answered,
  the last by inheritance and the first three by a row.
- **The reading crosses the statement against the entry it is about.** A configuration file under a
  realiser with no assemble step, a confinement profile that denies what one of the entry's units
  needs, and a realiser that emits for a service manager the entry's machine does not run are all
  rows from the reading, before any realiser is called. The reading asks each realiser what it
  accepts through the pure predicates the realisers already export, so one rule lives in one place.
- **A build of an inapplicable deployment produces its plan and both halves of its diagnostics.**
  `mkDeployment` stops discarding the derivation. The tree always holds `plan.json`,
  `diagnostics.json` and `diagnostics.txt`; it holds `entries/<projected>` for the entries that were
  realised and no artifact of an entry of an inapplicable deployment; and applicability is read from
  the rows rather than from the shape of the tree.
- **An address is a fact an apply needs and a build does not.** `operator-entry-machine-no-address`
  becomes a warning, the deployment record carries the absence, and refusing to dial stays with the
  command, where "The command refuses before it dials" in `operator/apply-command` already puts it.
- **The identity a build publishes for an entry is the identity the machine stores.** The per-entry
  identity in `manifest.json` becomes the artifact version digest the endpoint records as
  `settings_hash`, so a report can compare what a machine holds against what a build holds. The plan
  entry digest stays in the plan, which travels beside the record.
- **`row`, `error` and `warning` are exported from the library.** Every row producer builds a row
  with the constructor that applies `util.oneLine`, so one row is one line whatever a user
  interpolated into it, and the six fields are written out in one place.

Not in this change, deliberately:

- **The other half of the documented example.** That no committed document shows a downstream flake,
  and that `operator` is not a flake output, are `open-the-repository-to-a-consumer`'s (A1, A7). This
  change makes the example buildable; that change makes it reachable.
- **What a row may print.** A row that interpolates a value and leaks its bytes (C7) is
  `deliver-a-secret-without-exposing-it`'s. This change decides which layer builds a row and that a
  row stays one line, not what its message is allowed to name.
- **The secret and confinement gaps below the profile check.** That flakelet hardcodes the one
  profile denying nothing (C6), and that an image carries no mount point for another instance's
  generated file (C9), are `deliver-a-secret-without-exposing-it`'s. The row this change adds for a
  denied access reads against whatever that change decides the denial covers.
- **Everything the command does after it dials.** Partial applies, resume, dry runs and status
  reporting (D1 to D13) are `make-an-apply-observable`'s.
- **Cycle detection, and any new refusal about a wire.** `CLAUDE.md` records that two instances
  wiring each other is not a cycle. Nothing here changes which conditions are refusals, other than
  the statement-level ones named above; it changes which layer reports them.

## Capabilities

### New Capabilities

None. The rule this change writes down is about which existing layer answers a question, so it lands
as deltas on the five capabilities that already own the layers: the planner's table, the plan
record, the deployment build and the two realisers.

### Modified Capabilities

- `planner/diagnostics`: the layering rule - which layer reports which kind of fact, and the
  precondition a realiser's raise now has. Plus the row constructor: a row built outside the library
  is built by the library's own function, so one row is one line.
- `planner/plan-artifact`: a placed entry records the fields a realisation reads, present and empty
  rather than absent.
- `operator/deployment-build`: the reading owns every refusal about the realisation statement and
  every refusal about the statement crossed with the entry; it classifies a record by shape; an
  inapplicable deployment still produces its plan and its table; an address is needed to apply and
  not to build; and the identity a build publishes is the identity a machine stores.
- `realiser/flakelet-artifact`: the two refusals this realiser owns are narrowed to conditions the
  deployment build already reported, and the raise remains as a guard for a caller that reached the
  realiser directly.
- `realiser/portable-service-image`: the header claim of `image/read.nix` restated as what will be
  true, and the environment-value refusal narrowed to a condition the planner reported.
