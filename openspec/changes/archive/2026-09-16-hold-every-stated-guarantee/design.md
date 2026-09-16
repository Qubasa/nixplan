## Context

See proposal.md - Why. Two facts shape everything below.

The first is that each finding is a *silent* failure. Not one of them produces a wrong answer
loudly: the order walk returns an order and an empty `broken`, the reading dies with a Nix trace
instead of a table, the delivery set names a machine that does not exist, the check is green. So the
repair for each is not only the missing case but the tolerance that hid it - a reader that took one
shape of a record and shrugged at the other, a bare attribute read that assumed a field the producer
prunes, a comparison that could not distinguish what it claimed to prove.

The second is that these findings arrived from six independent reviews of a tree that five agents had
just merged into. Three of them are disagreements *between* layers that each satisfy their own rule:
`lib/plan.nix` records `entries`, `cli/order.py` reads `entry`; `lib/plan.nix` prunes `files`,
`operator/read.nix` reads it; `operator/read.nix` writes `artifact = null`,
`cli/manifest.py` refuses it. Each pair was written against a spec neither side violated. That is
what the specs in this change state once, on the record itself, rather than twice on each side.

## Goals / Non-Goals

**Goals:**

- Every finding is reproduced before it is repaired, by a check that is red first.
- Each repair closes the tolerance as well as the case, so the next instance of the same class fails
  rather than passing quietly.
- The two sides of every cross-layer record agree because one statement governs both.

**Non-Goals:**

- No new capability, no new field a deployment can declare, and no change to what a deployment means.
- Not the pending changes' subjects: the command's argv, per-generator `mode`/`owner` and host
  verification stay with `deliver-a-secret-without-exposing-it`; `StateDirectory` stays with
  `declare-service-state`.
- Not the twenty-two false documentation claims one by one as an end in itself - they are corrected,
  but the design question is which of them a suite can hold, and prose that no suite can hold stays
  prose.
- Not archiving or spec-syncing the planning record. `openspec/specs/` is empty and nineteen complete
  changes are unarchived; that is a separate decision.

## Decisions

**D1. An unrecognised resolved read is a refusal, not zero edges.** `cli/order.py` will read both
shapes the plan records - the single `entry` and the per-provider `entries` - but the defect was not
the missing branch, it was that an unknown shape contributed nothing and said nothing. So the walk
gains a third branch: a resolved, delivered read whose shape it does not recognise is an
`ApplyError` naming the consumer and the slot. Alternative considered and rejected: normalising the
plan so every read records `entry` as a list. That flattens the per-provider keying `entries` carries
and moves a plan field for the benefit of one consumer, and it would leave the same silent tolerance
in place for the next field.

**D2. The pruning asymmetry is fixed on the producing side, and the reading is made total anyway.**
`lib/plan.nix` already keeps `delivery` unpruned for exactly this reason, three lines from the
`files` that is pruned, so `files` joins it: a value entry records its file set empty. That alone
would fix the observed abort. The reading is still made total, because the guarantee `CLAUDE.md`
states about `operator/read.nix` is not "it happens to read fields that exist" but "every refusal it
makes is a row". Both sides, deliberately: the plan stops omitting a field a reader indexes, and the
reader stops assuming fields. Alternative rejected: `entry.files or { }` at the call site - it
converts an abort into a silently empty file set, which is the tolerance of D1 again.

**D3. A name is refused by the characters the key grammar uses, not by an allowlist.** The key
structure spends `@`, `:` and `/`; a machine, instance, member or generator name carrying one of them
is a row. An allowlist (say `[a-z][0-9a-z-]*`) would be the stricter rule and would also refuse names
this tree's own fixtures and any existing deployment legitimately use. The check lands in the reading
of machines, instances and members - before any key is built - so that the row exists before any
derived fact, and no delivery set is ever computed from an ambiguous key.

**D4. The attribute key is a member's identity; the second spelling goes away.** `lib/resolve.nix`
indexes `members.${member.name}` while `lib/compose.nix` sets `name` from the argument the author
passed `service`, so a member declared under one attribute and named another aborts. Of the two
spellings the attribute key is identity, because placement and keys are structural everywhere else in
this library. So `service`'s name argument stops feeding identity - it is either removed or kept
strictly as row text, whichever the callers allow - and `resolve` reads the attribute key. A row
reports the disagreement for any declaration that still carries both. Alternative rejected: making
`member.name` authoritative, which would let a member's identity be renamed without moving its
placement.

**D5. The deployment half gets one guarded reading, not seven checks.** The seven confirmed raising
sites are all the same shape: a field read bare where the module half routes the same read through a
check that rows. The repair is one typed accessor used by all seven - a field read with its expected
shape, its subject and its row - rather than seven bespoke conditionals, so the eighth site added
later inherits the behaviour instead of repeating the bug. The atom check (`lib/resolve.nix:798`) and
the refusal channel's coercion (`:1012`) move inside the same mechanism: `verify` is called where the
export is used, under the guard, and a `refused` that is not text is a row rather than a coercion.

**D6. Interface rows are reached from the modules, not from the attribution list.** `registryRows`
walks `interfaces`, which `CLAUDE.md` calls attribution and never a registry, so every
`interface-id-*` and fold row is unreachable for an unlisted interface. The walk becomes the set of
interfaces the deployment actually reaches - the slots' interfaces, the capabilities' interfaces and
their folds - deduplicated by the identity the interface itself declares. Attribution keeps its one
job: supplying the file a row names.

**D7. The staged file is created with its mode, not chmod-ed after its bytes.** `install -m <mode>`
(or an equivalent create-with-mode) replaces `: > file` in `image/default.nix`'s `assemble`, so the
mode is a property of the file's existence rather than a later step, and a script that dies mid-append
leaves a file no wider than declared. A global `umask` in the preamble was considered and rejected: it
would make the mode depend on a script-level default rather than on the declaration, and every file's
declared mode is its own.

**D8. A missing measurement is a failure of the perf gate, and the comparison count is reported.**
`perf/check.py` knows the fixtures it gates from `budgets.json`; a result file it does not find is a
finding naming the fixture, and the summary line reports comparisons made against comparisons
covered. This is the same class as D1 - a gate that compared nine of eighty-one figures and printed
`0 failures`.

**D9. A check proves its property by observing it, not by re-asserting the implementation.** Three
named checks are rewritten rather than deleted, because each names a property worth holding:
context-freedom of a recorded `program` is observed with `builtins.hasContext` on the recorded value
(Nix equality ignores context, which is why the old form was a tautology); stability across
evaluations is observed with the suite's existing `support.anotherEvaluation`, not by applying one
pure function twice; and the e2e provenance guard is built from the *declaration* rather than from the
values the run just read, so a stored value from an earlier declaration disagrees. The checks that
name no property worth holding - the implementation-echo expectations - are deleted, per the
repository's own standard.

**D10. Documents are corrected, but only the enumerable claims gain a suite.** Row identifiers,
recorded counts and the classification of a specification are sets the tree can enumerate, so they
become cross-checks in `tests/unit/layers.nix` and `tests/unit/coverage.nix`. A claim about meaning -
"the bytes themselves are carried by no entry" - is corrected in prose and left there; inventing a
mechanical check for prose would produce a check of the kind D9 deletes.

## Risks / Trade-offs

- **A new row on a name grammar refuses a deployment that plans today** → the grammar refuses only
  the three characters the key structure uses, and the fixtures are checked first; a deployment using
  one of them was already producing keys that parse as other keys.
- **D4 changes a public authoring surface** (`service`'s name argument) → the callers in this tree
  are enumerable and are migrated in the same change, with a row for any declaration that still
  carries two spellings. Clean cutover, no compatibility shim.
- **Nine new rows and one new always-present field move the recorded perf cost** → the budgets are
  re-recorded once, at the end, from the sandboxed measurement, with the margin and growth bound
  untouched; the golden plan is regenerated by command. Doing it per phase would re-record nine times
  and hide which phase moved what.
- **D6 widens which interfaces earn rows, so a deployment that planned silently may now carry
  warnings** → that is the intent, and no warning stops a build; the fixtures show whether any row is
  a false positive before the change lands.
- **The reading becoming total (D2) could mask a producer bug it used to abort on** → the reading
  produces a row naming the entry and the field, and a row is a test subject, so the condition is
  asserted rather than merely tolerated.

## Open Questions

None that would change the specs, the approach or the task breakdown.
