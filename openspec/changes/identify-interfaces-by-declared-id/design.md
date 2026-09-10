## Context

See proposal.md — Why. The mechanics the approach has to fit:

| Fact | Site | Consequence for this change |
| --- | --- | --- |
| an edge exists when two interface values are equal | `lib/resolve.nix:916-917` — `slot.interface == capability.interface` | the one comparison to widen; everything else about a read is downstream of it |
| this library's atoms are built by applying a function to korora | `lib/atoms.nix:10-43` — `korora.typedef "url" (v: …)` | two evaluations of `lib/` produce unequal atoms, so unequal interfaces; measured, not assumed |
| korora memoises by path, not by argument | `import` semantics; measured: two `import "${korora}/types.nix"` are one value, two `import ./lib { … }` are not | sharing an interface today requires sharing one evaluation of `lib/`, which requires `follows` |
| a korora type carries a stable name with its polymorphic metadata | measured: `string`, `attrsOf<string>`, `listOf<int>`, `union<string,int>`; `__name` strips it to `attrsOf` | `type.name` is the comparable projection of a type; `__name` is not, because it collapses `attrsOf<string>` and `attrsOf<int>` |
| an interface's declaring file is found by value | `lib/interface.nix:75-80` — `filter (r: r.value == iface) reg` | the attribution lookup has the same blind spot as the match, and one identity function fixes both |
| the registry is attribution and never validation | `lib/default.nix:74-77`; `implement-minimal-typed-edge` — "SHALL NOT be validated against any registry" | a claim may not become a registration: an interface absent from `interfaces` must stay a perfectly good interface |
| the same fact produced twice is one row | `CLAUDE.md` — "`dedup` keeps the first" | a conflict observable from two sites needs no second mechanism to be reported once |
| a plan records `provides.<cap>.interface` as the interface's name | `fixtures/minimal-typed-edge/plan/backup.json` — `"interface": "ssh-host-identity"` | the plan carries the label and nothing a downstream reader can use as identity |
| a field a declaration does not carry is absent from the record | `docs/authoring.md` — the unit vocabulary rule | a claim-only plan field leaves the golden untouched |
| an interface may own a fold | `hold-declaration-shape-and-fold-set-reads` D1, D4 | a lambda cannot be compared, so identity must say what a fold contributes |
| two consumers wanting two folds get two interfaces | that change's Risks — "a second interface with a different fold is legal" | any identity rule that ignores the fold silently merges those two |

## Goals / Non-Goals

**Goals:**

- Two authors, two evaluations of this library, one wire that resolves.
- A disagreement about what a shared interface is becomes a row naming the disagreement, at the
  earliest point either side is visible.
- One identity function, used by matching, by attribution and by the plan field, so the three cannot
  drift.

**Non-Goals:**

- Making `name` load-bearing. It stays a label, and two interfaces may still share one.
- A registry, a resolver, a lockfile or any list of known interfaces the planner owns.
- Proving that two matched interfaces mean the same thing. A claim is a claim (D3).
- Identity for unit extensions. They are read from the value an author wrote into `extends` and are
  never matched against a far end, so nothing about them is decided across two evaluations.
- Addressing a module by name, or typing a setting. Both need this change first and neither is opened
  here.

## Decisions

### D1 — Identity is an authored claim, not inferred structure

An interface carries `id ? null`. Two interfaces are one interface when both claim one `id` and the
rest of their identity agrees; otherwise the rule is today's value equality.

Alternatives considered:

- **Pure structural identity** — `name` plus the export shape, no new field. Rejected on two counts.
  It makes `name` load-bearing, contradicting a requirement this repository already shipped ("An
  interface's `name` SHALL be used only in diagnostic output") and the invariant in `CLAUDE.md`. And
  it merges by accident: two authors who both write `name = "http-endpoint"` with one `url` export
  get one interface whether or not either meant the other's, which is a wrong edge rather than a
  refused one. A claim is the smallest construct that makes merging deliberate.
- **A registry of known interfaces** — `mkPlan` given a table of canonical interfaces. Rejected: the
  library validates against no registry by requirement, and a registry would make an interface nobody
  upstreamed second-class, which is the thing the value rule exists to prevent.
- **Content hashing the interface** — hash the shape, use the digest as identity. Rejected: it is
  pure structural identity with a worse row. A digest cannot be read in a diagnostic, and the author
  never wrote it, so nothing tells two authors they disagreed on purpose rather than by accident.

### D2 — An identity is the `id`, the export shape and the fold's name

Identity is `{ id, exports = { <name> = { type = <korora type name>; secrecy = <resolved secrecy>; }; },
fold = <fold name or null> }`. Every leaf is a string or null, so two identities compare across
evaluations by ordinary Nix equality with no function anywhere in the value.

`type.name` rather than `type.__name`: measured, `__name` collapses `attrsOf<string>` and
`attrsOf<int>` to `attrsOf`, so it would call two different exports the same. Secrecy is the resolved
one (`secrecyOf`, defaulting to `public`), so an author who writes the default explicitly and one who
omits it agree.

Alternatives considered:

- **The `id` alone.** Rejected: it removes the version check that is half the value. An author who
  adds an export or changes a type under an unchanged `id` would hand a consumer a shape it was not
  written against, silently.
- **The `id` and the export keyset, without types.** Rejected for the same reason one step in: a
  `url` becoming a `string` is exactly the change a consumer's `impl` breaks on.
- **Excluding the fold.** Rejected: `hold-declaration-shape-and-fold-set-reads` documents "a second
  interface with a different fold is legal" as the escape hatch for two consumers wanting two folds.
  An identity that ignores the fold merges those two interfaces and then has to pick a fold, which
  reintroduces per-consumer fold policy through the back door — the thing that change's D1 rejected.

### D3 — A claim is a claim; each side still verifies with its own value

After a match by claim, nothing else changes hands. A provider's exports are verified against the
provider's own interface and a slot's `reads` are checked against the consumer's own, exactly as they
are for two ends holding one value. Identity decides only whether the edge exists.

This is what keeps the change small and what makes the limitation honest: two korora types sharing
one name are one type for identity however differently they verify. The planner cannot compare two
predicates, so it does not pretend to. The mitigation is that the values themselves are still
verified — by the side that publishes them, against the type that side imported — so a value one
author's type refuses is still a row, on the author whose type refused it.

### D4 — The fold gets a name the way korora gets one, and only a claim requires it

`planner.fold "<name>" (providers: …)` returns `{ name, apply }`. This is `typedef name verify` with
the words changed, which is the shape this repository already reads as "a function plus the only part
of it that can be compared".

Required only where an interface declares an `id`. An unclaimed interface's fold has nothing to be
compared with, so demanding a name there would be churn for no decision. An interface that claims an
`id` and carries an unnamed fold cannot have an identity computed, so its claim is refused and it
falls back to value identity (D6).

Alternative considered: make every fold a named fold and drop the bare form. Rejected — it edits a
construct that has just landed, for interfaces where the name is never read.

### D5 — Both ends must claim, and a lone claim changes nothing

Where one end claims and the other does not, the rule is value equality. A claim is a statement that
this interface is the well-known one; taking one side's word for it would let an author capture a far
end that never agreed to be captured.

The consequence is stated rather than hidden: an author adopting an `id` does not break an existing
in-repository wire, because that wire already matches by value and continues to.

### D6 — A refused claim is disregarded, and the interface falls back to its value

Three things refuse a claim: a malformed `id`, an unnamed fold beside an `id`, and a fold name that
is not a name. Each is an error row, and in each case the interface is then identified by its value.

The alternative — making the interface unusable — was rejected because it turns one authoring mistake
into a cascade of unrelated rows, and because falling back is the behaviour the deployment had before
the claim was written. The plan is already not applicable; what the fallback buys is that the rest of
the table describes the deployment rather than the consequences of one bad string.

### D7 — A conflict is found at two sites and reported once

A conflicting claim is observable from the registry `mkPlan` was given, and at a wire. Both are
checked; `dedup` already keeps the first, so one conflict is one row.

The registry pass matters on its own: it reports two authors disagreeing before anybody wires them,
which is the case a catalogue of third-party services hits first.

Determinism, because the table must render identically twice: the pair is ordered by `subjectOf` and
the row is subjected to the first, naming the second in its evidence.

### D8 — Attribution matches by value first, then by identity

`fileOf` tries value equality, then claimed identity. Value first keeps every existing lookup exactly
as fast and exactly as accurate; the identity pass only ever converts a miss into a hit.

This is what lets a row about an interface built by another evaluation print that interface's own
declaring file, provided the deployment merged that author's `interfaces` map — which is the same
attribution argument the library already has, reaching one step further.

### D9 — An unqualified `id` is a warning, and the trigger for hardening it is recorded

An `id` carrying neither `.` nor `/` is a warning. It works, it identifies, and the row says why it is
a poor idea: the namespace is shared with every author and an unqualified claim collides silently
with a stranger's.

Not an error, because the planner owns no namespace and cannot say what a good one is. The condition
that would make it an error is the first collision between two unrelated authors observed in a real
deployment, at which point the namespace has a fact about it rather than an opinion.

### D10 — The plan records the claim, only where one was made

`provides.<capability>.interface` already carries the interface's name and `declaringFile` its file.
A claimed `id` is added beside them, and is **absent** where no claim was made — the library's own
convention for a field a declaration does not carry. No in-tree interface claims one, so
`fixtures/minimal-typed-edge/plan/backup.json` does not move.

This is the field a downstream reader needs and the name cannot supply: two `http-endpoint`s are
distinguishable in a plan only by something stable, and the plan is the artifact a UI, a catalogue or
an operator's command reads.

The read side is deliberately not extended. A read already names the provider entry it resolved, and
that entry carries the claim, so recording it twice would be a second place for one fact.

## Risks / Trade-offs

- **Two authors claim one `id` for interfaces that agree in shape and disagree in meaning** → the
  claim is deliberate and the `id` is namespaced by convention, with an unqualified one warned about.
  This is the residual cost of any identity that is not a single global registry, and it is stated in
  the spec as something the planner does not prove rather than left to be discovered.
- **A `struct` type collapses to its own name** → measured: `korora.struct "s" { … }.name` is `"s"`,
  so two different structs named `s` are one type for identity. Same class as two `typedef`s sharing
  a name (D3), same mitigation: each side still verifies its own values.
- **An author bumps a type and forgets the `id`** → that is the conflict row, and it is an error. The
  risk is the inverse: an author who bumps the `id` for a compatible change orphans every consumer at
  once, with a mismatch row rather than a conflict row. Nothing here can tell a compatible change from
  an incompatible one, and the spec does not claim to.
- **Attribution by identity could print the wrong file** → only for two interfaces with equal
  identities, which by construction are one interface. A wrong file is then not wrong.
- **A new plan field is a new thing a realiser could grow to depend on** → it is present only where
  claimed, so a realiser reading it unconditionally fails on the first unclaimed interface, loudly,
  in its own build.
- **Roughly twenty new scenarios means twenty named tests** → the coverage cross-walk fails until each
  exists, which is the intended failure mode.

## Migration Plan

Additive in every position; nothing in the tree declares an `id` or a named fold:

1. `id` defaults to null and matching falls back to value equality, so every existing wire resolves by
   the rule it resolves by today.
2. The fold constructor is additive beside the bare form, which stays legal.
3. The plan field is absent where no claim is made, so `fixtures/minimal-typed-edge/plan/backup.json`
   and `plan/diagnostics.txt` stay comparable with `==`.
4. Both new paths are exercised in the unit layer, where two evaluations of the library can be built
   on purpose and an interface can be given a deliberately malformed claim.

Rollback is deleting the `id` argument, the identity function and the fold constructor. Nothing
persists between evaluations, and the only artifact that could record a claim records it just where
one was written.

## Open Questions

- Whether `fixtures/minimal-typed-edge`'s interfaces should eventually claim `id`s. Deferrable and
  deliberately deferred: the fixture's value is as evidence of the value rule, and claiming would move
  the golden for no behaviour this change introduces. The end-to-end folders are the better place for
  the first real claim, because two of them already build one deployment from more than one file.
