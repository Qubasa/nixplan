## Context

See `proposal.md` - Why. Four shapes in the tree decide what the fix can be.

- **The failure is uncatchable by construction.** `diag.guard` is `builtins.tryEval` over a
  `deepSeq` (`lib/diagnostics.nix:58-68`), and the comment above it records the limit: it catches a
  raise and a failed assertion, and "neither an abort nor a missing attribute". A target composed by
  `//` out of the fields that happen to be present (`lib/resolve.nix:436-438`) makes the missing
  attribute the failure mode of a declaration a deployment writes. Note which way round this is: a
  machine declaring neither `system` nor `serviceManager` yields `targetOf == null`
  (`lib/resolve.nix:433-434`), and a module selecting an attribute of null is a type error the guard
  does catch, which is what `module-raised` reports. It is the **partial** target that is fatal, and
  a partial target is what the current code is careful to produce.
- **The tree already has one refusal of this shape.** A machine, instance, member or generator name
  carrying `@`, `:` or `/` is `name-carries-key-separator` and is then filtered out:
  `placeable` (`lib/resolve.nix:212`) drops such a machine from every placement, and `members`
  (`lib/resolve.nix:528`) drops such a member from the member set. The comment at
  `lib/resolve.nix:189-192` states the rule: the check is made "in the reading of each, and before
  any key is built from it", and the thing named is "left out of everything a key is derived from".
  A row plus a drop is therefore not a new device.
- **A row is per machine, not per entry, and it already counts the placements.**
  `machine-target-incomplete` (`lib/resolve.nix:378-398`) is subjected to the registry file, names
  the missing keys, and says how many entries are placed on the machine through `placementsOn`
  (`lib/resolve.nix:400`). That is the row this change widens.
- **The realiser half is already paired.** `image/read.nix:131,136,137` gives `fieldMissing`,
  `targetNoPlatform` and `targetNoServiceManager` the id `machine-target-incomplete`, which
  `tests/unit/diagnostics.nix` crosses against the rows the reading layers produce
  (`:493-495`, `:537-550`). Widening that row keeps every pairing; retiring it would break three.

## Goals / Non-Goals

**Goals:**

- No deployment ends an evaluation because a machine has not been told where it lives. The observed
  failure is `error: attribute 'address' missing` with no table; the required failure is one error
  row naming the machine and the registry file.
- An implementation is handed a total target. `target.address` is readable without a guard, and so
  are `target.system` and `target.serviceManager`.
- The declaration that would have produced the abort is out of every later stratum, not merely
  reported by one.

**Non-Goals:**

- No new row identifier. The condition is the one `machine-target-incomplete` already states; only
  the key list it reads and the drop below it are new.
- No inference of an address. The planner does not read a host file, does not resolve a name and
  does not default to the machine's own attribute key. `address` is a fact the deployment states.
- No change to what is in an entry's key. The address is already a key input through the target
  (`prove-plan-on-real-machines/specs/planner/plan-artifact/spec.md:38-42`), and every machine of
  every fixture and every perf harness already declares one, so no key and no golden moves.
- No change to the point at which the command refuses to dial (`cli/manifest.py:230-251`).

## Decisions

**An address is a required registry field once a placement selects the machine, and the reversal is
argued rather than assumed.** `report-every-refusal-as-a-row` decided the opposite and recorded the
reasoning in two places: its own design (`.../design.md:244-247`) and `CLAUDE.md`, Realisers - "an
address is read by the step that dials a machine and by no step that builds one, so the record
carries the absence and every artifact is built". Every clause of that is still true and it answers
the wrong question. The address is not only dialled with: the target carries it *because* a unit may
be rendered from it (`lib/resolve.nix:421-424`), so it is spent during `mkPlan`, one stratum below
any build and two below any dial. What that trade actually bought was a fleet whose addressed
machines build while one unaddressed machine waits, and what it costs is that the same fleet does
not evaluate at all the moment any module renders the field. A build that cannot happen is a strict
loss against a build that would have been refused.

Alternatives rejected:

- **Record `address = null` unconditionally.** This is the smallest edit and it does not work.
  Interpolating null is `error: cannot coerce null to a string`, which is a raise inside the
  module's own expression, so a module under `diag.guard` earns `module-raised` and a module whose
  value is forced outside one still ends the evaluation. It also pessimises every honest module: the
  field would have to be read as `if target.address == null` where today it is read plainly, and
  `lib/plan.nix`'s `pruned` drops nulls from records, so the plan would look exactly as it does now
  while every module grew a branch. The absence is not the defect; the absence being *reachable by
  a module* is.
- **Keep the warning and add a second warning at plan time.** A row is a value in a table and
  nothing forces the table before the units. A consumer's own flake decides what it forces first,
  and `passthru.entries.<key>` of a deployment forces one entry without forcing the table at all
  (`CLAUDE.md`, Realisers). Two rows about one machine would therefore both be produced, both be
  unread, and the evaluation would still end at the entry. A row cannot prevent an abort; that is
  the whole content of this change.
- **Hand `impl` an address that is a `throw`, so the existing guard catches it.** It would work
  mechanically and it costs the invariant that pays for everything else here. `throw`, `abort`,
  `assert`, `.check ` and `korora.check` may not appear in `lib/*.nix`, and
  `tests/unit/diagnostics.nix` scans the source text for them, dropping only lines whose first
  non-space character is `#`. The scan is substring matching, so it has no notion of an exemption: a
  carve-out is either a hole in the scan or a second list of blessed call sites, and a purity
  invariant with an exemption list is one nobody can read off the file any more. It also lies to the
  module: the value handed over would claim to be a string and detonate on use, which is the failure
  mode `lib/` exists to convert into rows.

**The drop is a clause on `placeable`, and the selection is read twice.** `placements` for a member
is `uniqueStrings (filter placeable (named ++ concatLists (map tagged tags)))`
(`lib/resolve.nix:865`), so extending `placeable` (`:212`) drops the machine from tag selection and
from an explicit machine list in one edit, at the site the key-separator refusal already uses. That
alone would eat its own row: `incompleteMachines` is computed over `selectedMachines`
(`lib/resolve.nix:393-398`, `:363`), which comes from `placementsByMachine`
(`:346-361`), which is built from the members' post-filter `placements`. A machine dropped from
every placement would therefore be selected by none and earn no row. The selection is consequently
read in two forms: what the selector matched, which is what `machine-target-incomplete`,
`placementsOn` and `member-not-placed` (`lib/resolve.nix:900-911`) are computed over, and what
survived the drop, which is what `lib/plan.nix` plans. `member-not-placed` keeps the requested form
deliberately: it means "the selector matched nothing", and a member whose machines were all dropped
gets one row about the registry rather than two rows contradicting each other about whose fault it
is.

Implemented with one refinement this argument did not foresee: the predicate the tag index is built
with cannot be the one that drops. `machinesByTag` (`lib/resolve.nix:286-296`) filters the registry
through `placeable` before grouping, so a completeness clause there would take the machine out of
`tagged` and out of the requested form too, which is the eaten row above by another route. The
predicate is therefore split: `selectable` is registry membership plus the name grammar and is what
the tag index and the requested form use, and `placeable` is `selectable` plus completeness and is
the one clause both a named and a tagged machine are dropped by.

**The unplaced reading of a member is produced only where the selector matched nothing.** A member
whose every placement was dropped has `placements == [ ]`, and the member's rows were
`memberRows ++ (if placements == [ ] then unplaced.rows else [ ])` (`lib/resolve.nix:1123`). That
condition had to move to the requested form as well, and for a reason this design found only by
running its own acceptance case: the unplaced reading hands `impl` no `target` at all
(`lib/resolve.nix:1214-1222`), so reading a module there that renders `target.address` ends the
evaluation with `function 'impl' called without required argument 'target'` - a third failure
`builtins.tryEval` does not catch, measured rather than assumed. Reading the module in a context the
deployment never wrote would therefore turn the registry's mistake straight back into the
uncatchable failure this change exists to remove. `lib/plan.nix` still emits the unplaced entry off
`placements`, so the plan shows what was asked for; what is not produced is the row set of an entry
that does not exist. A member the deployment placed nowhere is unaffected: its requested form is
empty too.

**A machine the deployment selected keeps its `machine:<name>` record even when no entry survives.**
`usedMachines` is the selected set (`lib/resolve.nix:1990`, `lib/plan.nix:1076-1093`), and reading
it off the requested form keeps the promise `emit-systemd-portable-service-images` made for the
`system` case: the plan is still emitted and still contains the machine's entry, so the registry
half of a deployment mid-migration is readable. What the promise loses is its second clause, "and
every entry placed on it", and the MODIFIED requirement says so. A member all of whose placements
were dropped falls to the unplaced branch (`lib/plan.nix:1045-1055`), whose record carries the
selector the deployment wrote, so the plan still shows what was asked for.

**A machine no placement selects declares whatever it likes.** This is the answer the brief asks for
and it follows from the defect rather than from taste: the abort is reachable only through an
implementation, an implementation exists only for a placed entry, and no target is derived for a
machine nothing is placed on. It is also the rule already in force for the other two target keys
(`incompleteMachines` folds over `selectedMachines`, `lib/resolve.nix:397`) and it is documented as
such: "A machine nobody is placed on may declare neither and produces no row"
(`docs/authoring.md:739-740`). Keeping it is what makes the cost below survivable: a registry may
list a machine that is not yet provisioned, and the deployment stays applicable until something is
placed on it.

**The completeness test moves from the declaration key to the field value.** `incompleteMachines`
asks `machines.${name} ? ${k}` (`lib/resolve.nix:396`) while `targetOf` uses
`machineFields.${machine}.<field>.value` (`:428-431`), and a value of the wrong kind falls back to
the null fallback with a `declaration-field-malformed` row (`:102-106`). A registry writing
`system = 64` therefore passes the presence test and yields a target with no `system`, which is the
same abort with a different first row. Testing the value closes both mouths with one predicate, and
the reader gets two rows about one declaration - one about the type, one about the target - which is
the accumulating behaviour the diagnostics applicative is for.

**`operator-entry-machine-no-address` is removed rather than kept as a hand-written-plan case.** The
tree's own division of labour decides this: "A fact the plan carries is a row from `mkPlan`. A fact
the realisation statement carries is a row from `operator/read.nix`" (`CLAUDE.md`, Purity and
totality). After this change a missing address is a fact `mkPlan` holds and refuses, and the
deployment build neither dials nor renders an address, so its row would restate a decision made one
stratum up about a plan that stratum cannot emit. The row is also nobody's pair: no realiser account
names it, unlike `secrets-delivery-machine-no-address`, which stays because
`secrets/read.nix`'s `store`, `configuration` and `deliveriesOf` refuse with it and the cross-walk
requires a row above each refusal. Two things must not move with it: the deployment record keeps
`address` as an explicit absence, which `hold-every-stated-guarantee`'s totality requirement needs,
and `cli/manifest.py:230-251` keeps refusing at the point of dialling, because `manifest.json` is an
interface a hand-written record can arrive through. The removal is mechanically guarded in both
directions: `tests/unit/diagnostics.nix`'s `testADocumentTabulatesARowTheTreeCannotProduce`
(`:2053-2064`) fails if the row stays in `docs/diagnostics.md`, and `testTheLibraryGainsARow`
(`:2042-2051`) fails if it leaves the document while any source still writes it.

**Comparable alternative considered and rejected: keep the warning, documented as reachable only for
a hand-written plan.** It costs nothing to keep and it leaves the reader two rows for one condition
with no deployment able to produce one of them, which is precisely the state
`testADocumentTabulatesARowTheTreeCannotProduce` exists to prevent from happening by accident. A row
retained on the strength of a plan nobody in this repository writes is a row whose next reader
cannot tell whether it is load-bearing.

## Risks / Trade-offs

- **The stated cost: a fleet with one not-yet-provisioned machine becomes inapplicable rather than
  partially buildable.** Where a placement selects that machine, its error row makes the whole
  deployment inapplicable, so no entry of any machine is realised - `operator/read.nix` refuses the
  deployment, not the entry. That is a real regression against `report-every-refusal-as-a-row`'s
  intent, and it is narrower than it looks: a machine nothing is placed on costs nothing, and a
  `tags` selection that reaches the new machine is the case that breaks. A `planner build` of such a
  deployment still writes `plan.json`, `diagnostics.json` and `diagnostics.txt` and builds no entry
  artifact (`CLAUDE.md`, Realisers), so the operator gets the rendered table naming the machine and
  the file to edit rather than a build they cannot use. **Judged acceptable**, on two grounds: the
  alternative state of the world is not "a partial build" but "a deployment that may not evaluate",
  and the edit the row asks for is one line in the registry - the same line the operator would have
  had to write before the first apply anyway. What would not be acceptable is refusing a registry
  entry for a machine nobody uses yet, and that case is explicitly kept working.
- **Three recorded expectations are reversed, and they are rewritten rather than re-pinned.**
  `resolution.testAMachineWithNoAddress` (`tests/unit/resolution.nix:811-861`) pins the guard
  pattern `if target ? address then ... else throw`, which is exactly the vocabulary this change
  deletes; `platform.testAMachineOmitsItsSystem` and `.testAMachineOmitsItsServiceManager`
  (`tests/unit/platform.nix:98-150`) assert that `svc:only@host` is planned with a partial target;
  `operator.testAMachineOfAPlacedEntryDeclaresNoAddress` (`tests/unit/operator.nix:1357-1383`)
  asserts the warning. Each is rewritten against the new contract under the scenario heading that
  names it, and the plan-artifact delta is what makes the first of those a specification change
  rather than a deleted test.
- **Evaluation cost.** Reading the selection twice keeps one extra string list per placed member and
  the completeness predicate now reads three field values instead of testing three keys. Both are
  linear in placements, which is what the gate measures per plan entry, so
  `nix build .#checks.x86_64-linux.planner-perf` is in the verification group: the budgets are
  per-entry with a margin of 0.15 and a growth bound of 1.25 across sizes 4, 16, 64 and 256.
- **A module may still render a field the target does not carry.** `microarchitecture` is optional
  and lives inside the platform record rather than in `machineTargetKeys`, so
  `target.system.gcc.arch` remains a missing attribute on a machine that declares none. That is not
  this change's hole to close: `gcc` is a projection of an elaboration and a module reading a
  codegen field is inside nixpkgs' own vocabulary, where the absence is the answer. Recorded as the
  open question rather than decided: if a module is ever seen to read it, the fix is the same shape
  as this one, applied to the projection.

## Migration Plan

A deployment whose registry declares an address for every machine a placement selects is unaffected,
which is every deployment, fixture, perf harness and end-to-end folder in this repository. A
deployment that does not gets one error row naming the machine, the missing keys and the registry
file, and the edit is that line. There is no shim, no dual spelling and no deprecation: the field is
required from the commit that lands this, and reverting the change restores the previous silence.
