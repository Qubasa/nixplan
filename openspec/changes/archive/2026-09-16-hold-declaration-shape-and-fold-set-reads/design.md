## Context

See proposal.md — Why. The mechanics the approach has to fit:

| Fact | Site | Consequence for this change |
| --- | --- | --- |
| one declaration reading, against resolved settings | `lib/compose.nix:26-27` | a shape comparison needs a *second* reading; nothing else in the library wants one |
| a set-valued read is already keyed by provider entry | `lib/resolve.nix:937-949`, `960-969` — `entryKey = "${target}:${capability.member}@${machine}"`, `values = picked` | a fold needs no new data path: its input is the value the read already builds |
| `interface { name, exports }` is a strict pattern | `lib/interface.nix:47-54` | an author passing `fold` to today's constructor fails at the author's own site, outside any guard, so the constructor must gain the argument |
| an interface value already carries functions | every `exports.<x>.type` is a korora type, and a korora type is an attrset with a `verify` function | adding a lambda changes nothing about interface identity |
| interface identity is value equality | `lib/interface.nix:78` — `filter (r: r.value == iface) reg`; `CLAUDE.md`: "two functions are never equal in Nix" | that equality is already satisfied by pointer identity and nothing else; a `fold` neither improves nor worsens it |
| a refused read is absent from `results` | `docs/authoring.md` — `or [ ]` cannot be written | a refused fold must make the slot **absent**, not empty |
| `subjectOf` yields a relative `.nix` path, or `interface:<name>` | `lib/interface.nix:92-97`, `lib/diagnostics.nix:23-30` | both forms are already valid subjects, so an interface-level row needs no new subject kind |

One decided constraint the change must not break: `unify-declaration-and-implementation-readings`
(implemented) decided that a member's capability set **may** be derived from resolved settings, with
scenarios for a deployment adding a capability and a wire naming it. Any observation of
settings-derived declarations has to leave that alone.

## Goals / Non-Goals

**Goals:**

- One fold per interface, owned by the value the consumer imported, replacing the hand-written fold
  in each consuming `impl`.
- A slot set that varies with settings leaves a row behind instead of nothing.
- One decided answer to "where may a refusal originate", recorded before collect slots need twelve.

**Non-Goals:**

- Opening `collects`, `contributes` or `answers` (`lib/excluded.nix:49-60`). This change supplies the
  fold and the refusal rule those will need and stops there.
- Any plan field, any entry key change, any change to `reach`, secrecy, delivery-set derivation,
  placement or the diagnostics record shape.
- Refusing a settings-derived declaration of any kind. Nothing this change adds makes a plan
  inapplicable that is applicable today, except a fold an author wrote that raises.
- Per-consumer fold policy. One interface, one fold.

## Decisions

### D1 — The fold lives on the interface and is called `fold`

The interface is the only value both ends of a read already share: the provider satisfies its export
keyset, the consumer names it in `uses.<slot>.interface`. A policy for combining many providers is a
fact about that shared type, not about one consumer's file.

Named `fold` rather than ThermOS's `merge` because `merge` is the NixOS module system's option-merge
vocabulary, which this library refuses outright; the operation here is a fold of an entry-keyed set
into one value, and no option is being merged.

Alternatives considered:

- **On the slot** (`uses.<slot>.fold`). Rejected: that is where the duplication already is. Ten
  consumers would still write ten policies, and the interface would still have nothing to say about
  its own set.
- **On the deployment.** Rejected: a deployment names machines and wires. A rule for combining
  exported values is not a placement decision, and putting it there would let two deployments of one
  module disagree about what a consumer reads.
- **A fixed combinator table** (`fold = "union"` selected from planner-supplied folds). Rejected: the
  useful folds are shaped like the consumer's file format — a sorted `authorized_keys`, a comment
  line per provider — and a table would either be a list of everyone's file formats or be useless.
  Inspectability was the one argument for it, and it does not apply: a fold's output never enters the
  plan (D5).

### D2 — The fold's input is the value the read already builds

`readsAt` (`lib/resolve.nix:919-949`) already produces, per placement, `entryKey` and `values = picked`,
where `picked` holds exactly the exports the slot's `reads` names. The `reach = "all"` branch collects
those into an attrset keyed by `entryKey`. A declared fold is applied to **that** attrset and its
result becomes the slot's value.

This is why three requirements of the spec need no new mechanism: a fold cannot see an unread export,
cannot see a secret export (a slot may not name one), and cannot widen a delivery set (derived from
`varsFiles`, which comes from `slot.reads`, upstream of the fold). Each is inherited rather than
restated in code.

### D3 — The fold is applied under `diag.guard`, and a refused fold leaves the slot absent

`diag.guard` (`lib/diagnostics.nix:55-82`) is the existing mechanism for forcing a value a module
author wrote: `tryEval (deepSeq …)`, a row on failure, a fallback on success. The fold is applied
inside it with the consuming entry as subject.

On failure the read is marked undelivered, which already means the slot is **absent** from `results`
rather than present and empty. An `impl` that reads it then fails with a missing attribute, which
propagates on purpose — the documented behaviour for a refused read, and the reason `or [ ]` cannot
be written to paper over one.

No raising call is added to `lib/`, so the source scan in `tests/unit/diagnostics.nix` stays green:
the fold's raise happens in the author's interface file, and the library only forces it.

### D4 — The constructor gains `fold ? null`; nothing else about interface identity changes

`interface { name, exports }` is strict, so `fold` has to be an accepted argument or every author who
writes one gets a Nix error at their own call site rather than a row. The constructor becomes
`{ name, exports, fold ? null }` and returns `fold` alongside what it returns today.

`module.isInterface` (`lib/module.nix:148`) tests `name` and `exports` only and needs no change. A
`fold` that is not a function is a row against `subjectOf` (D9), not a Nix error.

### D5 — No plan field, and the golden does not move

Considered and rejected: `reads.<slot>.folded = true | false`, so a plan reader could tell what the
consumer saw.

Rejected because a fold changes no fact about the far end. The read record already names every
provider entry that contributed and every export the slot read; the consumer's own output — units,
`configData` identity — is already in the plan. A field would move
`fixtures/minimal-typed-edge/plan/backup.json` for a fact no realiser reads and no delivery depends
on.

Stated honestly as a limit: a plan alone does not say whether a fold ran. The diagnostics table and
the interface file do, and the fold is a function of the interface, which is pinned by the same
sources the module is.

### D6 — The slot-set observation is a warning, covers `uses` only, and names the exclusion trigger

This is the conflict resolution with `unify-declaration-and-implementation-readings`. That change
decided a settings-derived **capability** set is intended and correct, motivated by a real defect (a
deployment could not add a database). The symmetric argument applies to a settings-derived **slot**
set: an operator choosing whether a service talks to an offsite repository is the same kind of
choice. So the row records; it does not refuse.

What the row is for is the asymmetry between the two: an added capability shows up in the plan as
`provides`, while a removed slot shows up nowhere at all — no wire is required for it, `slot-unwired`
never fires, and no entry field mentions it. The row is the only trace.

It names `excluded.constructs.enable.trigger` verbatim, because that trigger is "a module publishing
a composition whose coherent cuts an operator wants", and a module deriving its slot set from a knob
is exactly a module publishing a cut. The row therefore doubles as the accumulating evidence for
un-excluding member cuts.

Scope is the `uses` keyset alone. A `provides` keyset is blessed by the prior change; a value inside a
slot, a claim, a generator or an export is ordinary (`fixtures/minimal-typed-edge/modules/borg-repo/server.nix:14-18`
derives a port claim's `fixed` from `settings.port`, which is the fixture's own documented reason for
that knob being fixed). Only the set of slot names is compared.

### D7 — The second reading is conditional and its rows are dropped

The comparison needs the declaration read under the member's own `defaults`. Two properties keep that
cheap and quiet:

- **Conditional.** `settings.sources` already records, per knob, whether the value came from
  `defaults`, the deployment or `fixed` (`lib/compose.nix:55-107`). If no knob's source is the
  deployment, the two readings are the same value by construction and the second read is not taken.
  Cost is bounded by the number of members a deployment actually configured.
- **Rows dropped.** The baseline reading exists to measure a shape, not to be reported. It is forced
  under `diag.guard` and its rows are discarded; a module that raises on its own bare defaults
  produces no shape row and no second `module-raised` — the raise it produces against resolved
  settings is already reported once.

Alternative considered: compare against the *fixed* values only, or against an empty settings set.
Rejected — a module reading a knob that has no default would raise, so the baseline has to be the
member's own declared defaults, which is the one settings value a module is written against.

### D8 — The fold is the only refusal channel; `impl` gains nothing

`impl` does **not** gain a `refusals` key. With the fold in place, an interface fold is the only place
a module meets values another module produced, so a second channel would be a second way for a row to
exist — the thing `lib/diagnostics.nix:1-3` opens by refusing.

A module writing `refusals` already gets `implementation-unknown-key` from `module.implKeys`
(`lib/resolve.nix:714-722`). This change only makes that row's resolution name the fold, so an author
who reaches for the wrong channel is told the right one.

Deferred, not rejected: author-supplied text with planner-supplied id, subject and severity, returned
from `impl`. The condition that would bring it back is a refusal a fold cannot express because it
depends on the consuming machine rather than on the provider's values.

### D9 — An interface-level row is subjected by `subjectOf`

`interface.subjectOf reg iface` returns the interface's declaring file when `mkPlan` was given the
`interfaces` argument, and `interface:<name>` when it was not. Both are already valid subjects
(`lib/diagnostics.nix:23-30`): the first as a relative `.nix` path, the second as a plan-key-shaped
string. So the malformed-fold row and the unapplied-fold row need no new subject kind, and an
interface nobody attributed still produces a row that renders.

## Risks / Trade-offs

- **A consumer's data shape now depends on a file the consumer did not write** → the fold is on the
  interface the consumer *did* import, and the consumer's own `reads` still decides what enters it.
  A fold cannot add a key to the input.
- **Two consumers may want different folds of one interface** → not supported by design. The escape
  hatch costs one file: an interface is identified by the value an author imported and is validated
  against no registry, so a second interface with a different fold is legal and needs no
  registration.
- **A second module application per configured member is a measurable evaluation cost** → bounded by
  D7, then measured. `perf/budgets.json` is re-pinned from the ratchet failure message in whichever
  direction the nine counters actually move, with interpreter version and date, as the prior change
  did rather than assuming a direction.
- **The unapplied-fold warning could be noise for a shared interface library** → it is a warning, it
  names the interface, and the case it fires on is a fold no deployment exercises, which is also the
  case where its behaviour is untested.
- **Twenty-one new scenarios means twenty-one named tests** → the coverage cross-walk fails loudly
  until each exists; that is the intended failure mode, not a risk to manage.
- **A fold that silently drops providers is legal** → a fold returns a value and the planner cannot
  know what it should have contained. Mitigated only by the plan's read record still naming every
  provider entry, so a dropped provider is visible beside the consumer's output.

## Migration Plan

Additive in every position. No existing module, interface, deployment, fixture or golden changes:

1. The constructor's `fold` defaults to `null`, and a read of an interface without one keeps today's
   entry-keyed set. Every in-tree interface is unaffected.
2. `fixtures/minimal-typed-edge` keeps its hand-written fold
   (`modules/borg-repo/server.nix:40-52`), so `plan/backup.json` and `plan/diagnostics.txt` are
   untouched and stay comparable with `==`.
3. The fold path is exercised in the unit layer, where an interface can be declared with a fold and a
   raising fold can be declared on purpose.
4. The slot-set row is new behaviour with no existing subject: no in-tree module derives its `uses`
   from settings, so no fixture or perf plan gains a row. Verified by evaluating the worked
   diagnostics before and after.

Rollback is deleting the `fold` argument and the comparison; nothing persists between evaluations and
no artifact records either.

## Open Questions

- Whether `fixtures/minimal-typed-edge`'s `borgRepository`-side `sshHostIdentity` should eventually
  adopt a fold instead of the hand-written map in `server.nix:45-49`. Deferrable: it changes no spec
  and no task here, and it moves the golden only if the rendered bytes differ. The fixture's value as
  evidence of the *unfolded* shape is itself an argument for leaving it.
