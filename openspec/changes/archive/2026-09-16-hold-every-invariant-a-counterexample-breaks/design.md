## Context

See `proposal.md` - Why. What decides the approach is a handful of shapes, each measured rather than
assumed:

- **`builtins.tryEval` is weaker than two of the failures this change meets.** It catches a `throw`
  and a failed `assert` and nothing else (`lib/diagnostics.nix:55-58`). Both formals failures are in
  the uncatchable class, evaluated on nix 2.34.8: `builtins.tryEval (({a}: a) { a = 1; b = 2; })`
  propagates `called with unexpected argument 'b'`, and `builtins.tryEval (({a}: a) { })` propagates
  the missing one. A missing attribute is uncatchable too, which is what `results.<slot>` is for an
  unwired slot. Nix exposes no predicate for a pattern's ellipsis: `builtins.functionArgs` answers
  the formal names and says nothing about `...`, so a pre-flight check of the argument record cannot
  tell `{ settings }` from `{ settings, ... }` without refusing the second.
- **A guard whose subject is re-forced beside it is not a guard.** `implShape`
  (`lib/resolve.nix:1452-1457`) catches the module's raise, and `:1461` reads `if impl == null ||
  implRaised || implNotAttrs`, whose first operand forces the application again, outside the guard.
  `:1564` forces it a third time. The row exists and the evaluation ends anyway, which is the shape
  `keep-a-declaration-from-ending-an-evaluation` set out to remove and did not finish.
- **korora hands out no structure.** `struct` returns `typedef' name verify // { override }`
  (`korora/types.nix:485-489`): a name, a verifier, an override. Two `struct "endpoint"` types over
  different member sets are therefore indistinguishable to anything that cannot hash a function, so
  a deeper fingerprint is not an option that exists.
- **`stated` answers the wrong question.** `fileRecord` (`lib/module.nix:617-629`) records which keys
  the declaration carried and `withoutUnstated` (`lib/plan.nix:120`) prunes the rest from the key
  input. The question a key needs answered is whether the value differs from the default, and those
  two are the same answer only for a declaration that never states one.
- **Two shapes of one relation are read in two places.** `cli/order.py:315-320` reads a resolved
  read's providers from `entry` and from `entries`; `cli/apply.py:207-210` reads them from `values`.
  The order therefore has the edge and the rotation does not, which is the one defect here that
  loses bytes an operator asked for.
- **The digest is taken over the plan's record of an artifact, not over the artifact.** `versionFor`
  (`image/read.nix:556-587`) hashes name, units, closure, store directory, service manager, shown
  host paths and platform. The confinement profile is a statement beside the deployment that the
  builder renders into the unit files, so it changes the bytes and not the digest.
- **Every environment name in the tree is already a POSIX name.** The 14 `env` records under
  `tests/e2e/`, `fixtures/` and `perf/` carry `TOKEN_FILE`, `API_URL`, `PGDATA` and their like, so
  the name grammar this change adds refuses nothing that exists here.

## Goals / Non-Goals

**Goals:**

- Every value a declaration wrote is read for its kind before it is indexed or coerced, and what
  remains uncatchable is stated rather than claimed.
- The diagnostics table is printable whatever one entry's own record does, because the table is what
  explains the mistake that made the record unprintable.
- A plan key, an artifact name and a derived unit file name each name one thing, and a name that
  cannot do that is refused before any key exists.
- A key moves when the artifact moves and not otherwise: stating a default is a no-op, and a
  statement that changes the bytes is in the digest.
- The secrecy lattice and the readability predicate are asked at every site holding the facts, and
  the answer does not depend on which realiser later reads the plan.
- A read that orders an apply is a read that rotates a consumer.
- Each of the 48 red counterexamples is the acceptance criterion for the rule it breaks.

**Non-Goals:**

- No new tolerance anywhere. Every rule here is a row and a fallback that records nothing, never a
  guess: a refused source has no bytes, a refused claim claims nothing, a refused export publishes
  nothing.
- No new identifier where an existing one states the condition, and no identifier per site where one
  condition is spelled once and the row names its site.
- No search, no solver, no inference. Every check is a predicate over a value the reading already
  reads, or one index built from a list the planner already has.
- No deepening of the interface fingerprint, and no change to what a claimed identity is.
- No change to what widens a delivery set. A declared read stays the only thing that does.
- No `throw` sentinel in `lib/`, and no attribute in `results` for a slot the planner refused.

## Decisions

### Totality is narrowed to the values a declaration wrote, and the rest is named

Three classes, and only two of them are the library's:

- **A value of another kind is fixed by a check**, because the failure is a type error or a coercion
  and no wrapper catches either. Twelve readings gain one: the root's `services`, a recipe fragment,
  a settings knob, `impl` itself, an export shaped like a file reference, the interface attribution,
  the four `mkPlan` arguments, `varsState`, and the realisation statement's `realiser`, `profile` and
  a plan's configuration file `mode`.
- **A module that raises inside its own expression is fixed by a guard**, and the guard that exists
  is fixed by reading `implRaised` before anything re-forces its subject. `impl` is recorded only
  where it is a function, so the row `impl-missing` and the value the reading kept can no longer
  disagree.
- **A signature that refuses the argument record, and a module indexing an absent attribute of its
  own, are named.** `impl` taking `...` becomes a stated contract of a module rather than a
  convention, and the documented uncatchable class grows those two sentences.

Alternative rejected: **applying `impl` with only the formals it names.** It would make
`builtins.functionArgs` the contract and silently deny a module the arguments it did not enumerate,
including `target`, which is the one argument whose presence already varies.

Alternative rejected: **binding a refused slot to a `throw` so the read is catchable.** It puts a
raising call in `lib/`, and worse, it makes `results ? <slot>` and `results.<slot> or [ ]` both
succeed, which is the property the absence exists to deny.

### The table survives an entry that cannot be forced

A raise inside one entry's own record currently takes `diagnostics` and `applicable` with it, because
`applicable` forces the whole table and the table is built from every entry's rows. Each entry's row
list is therefore produced under the guard, so the table prints, `applicable` answers, and reading
`plan.<key>` of that one entry is what raises. This is what makes the two uncatchable conditions
survivable rather than fatal: the operator gets the sentence naming the module to edit, and the entry
that cannot be described is the only thing that cannot be read.

### A field enters a key only where its value differs from its default

`withoutUnstated` becomes a comparison against the defaults the record resolved to, for a generated
file's `owner`, `group` and `mode` and for a configuration file's `owner` and `group`. Two properties
hold at once: a declaration that states a default keys as one that states nothing, and a plan written
before the fields existed keys as it did, because both are the same key input. `stated` then records
nothing any key reads, and the note in `CLAUDE.md` that keeps it alive as load-bearing is retired
with it.

Alternative rejected: **normalising in the row and leaving the key input alone.** The key is what
regenerates a secret; a row about it changes nothing.

### The derived unit file namespace belongs to the shared realiser reading

The projection is the realiser's (`nameOf` plus the unit name, `image/read.nix:208,243`), both
realisers spend the same names, and the reading that compares entries against each other already
refuses an artifact name collision (`operator/read.nix:438-455`). The index is therefore built there,
per machine, over the derived file names, and it names both entries and the file.

Alternative rejected: **refusing the ambiguity in the library.** The planner does not know the
separator a realiser picks, so the check would either encode one realiser's projection in `lib/` or
refuse member names a realiser accepts.

Alternative rejected: **mangling the second name.** A name an operator reads in `portablectl list`
would then be one the plan cannot explain.

### The mention scan asks about the machine, not about the deploy flag

`undeployedRows` already walks every mention site of an entry (`lib/plan.nix:477-571`). Its path list
grows from the entry's own undeployed values to every value of the deployment the mentioning machine
does not receive, which makes the existing `deploy = false` case one instance of the general rule: a
value on no machine is not on this one either. The row keeps naming the site, the value and the
declaration to edit.

Cost is the one thing to watch: the path list is per machine rather than per entry, and
`util.mentionsDeep` is a containment walk over the entry's own strings. The budgets are re-measured
as part of the work rather than after it.

Alternative rejected: **making a generated file's `path` a typed reference so that exporting it
widens delivery.** It changes what a delivery set is derived from, and it would grow sets silently
where an author omitted a read - the opposite of the recorded rule that only a declared read widens
one.

### Interface identity stays nominal, and the structural check moves to the wire

A claimed identity is a name and a shape of names, and korora cannot be asked for more. So the claim
is documented as nominal and name-deep, and the value crossing the wire is verified against the
**consuming** interface's own export type. That catches the diamond whatever the two interfaces are
called, including the case no identifier is claimed at all, and it is one verify per delivered read
against a type the consumer already declared.

Alternative rejected: **refusing a claimed `id` on a type whose name is not injective.** Nothing can
compute that: the name is all there is.

### A fold refuses with a marker rather than with a key its own result can carry

The refusal channel becomes a marker a successful fold cannot imitate, produced by the same
constructor a fold is already spelled with. Everything else about a refusal is unchanged: the fold
supplies the sentence, the planner supplies the identifier, the subject is the consuming entry, and
the severity is the planner's.

### The rows that already exist are reused, and each new condition is spelled once

New identifiers are added only where no existing sentence covers the condition: a plan key claimed
twice, a unit file name claimed twice, a secret export backed by a public file, an entry naming a
value its machine does not receive, a configuration file source that is not a store object, two shown
paths that nest, and the `mkPlan` argument family. Everything else widens a row that exists - the
name grammar's refusal, the host path grammar's, the line-break scan's, the readability family's -
because an operator filtering a table should not have to learn a second identifier for a condition
they already know.

The `mkPlan` argument family answers the open question
`keep-a-declaration-from-ending-an-evaluation` left recorded: a caller's argument has no plan key and
no deployment file, so its rows are subjected to an issue identifier, which is the third subject kind
the diagnostics discipline already admits.

### The order of the work is the order of the dependencies

Checks before guards, names before keys, keys before digests, library before realisers before the
command:

1. The kind checks, so that what the guards are left holding is a module's own raise rather than a
   library index no guard catches.
2. The guards and the guarded row list, so a table exists for everything below to assert against.
3. The name and key rules, because the realiser and secrets projections read what they produce.
4. The secrecy and readability sites, and the widened mention scan.
5. The realisers, whose digests and grammars depend on the plan being settled.
6. The command, which reads the finished plan and the finished manifest.
7. The documents, the budgets and the coverage registration.

### The counterexamples are the acceptance criteria, and two of them are rewritten

47 of the 49 turn green as written. The two asserting that the formals conditions produce a row
(`anImplementationWithStrictFormalsIsARow`, `anUnwiredSlotStillLeavesATableToPrint`) assert a claim
this change withdraws, so each is rewritten to the narrowed one: the table prints and `applicable`
answers, while reading that entry's own record raises. A probe answering `"ok"` stays in place as the
regression pin. Each condition that is a row after the change also gains an assertion in the suite
that owns its family, because a probe proves the evaluation completed and only a suite test can
assert which row it produced.

## Risks / Trade-offs

- **Every image re-keys once.** → One stop, detach and attach per entry on the next apply, and the
  report says `holds <x>, built <y>` until it happens. The alternative is a digest that cannot tell
  two artifacts apart, which is the defect.
- **A deployment that states an ownership default re-keys its values once and regenerates them.** →
  One-time, visible in the provenance driver as a plan key change rather than as a silent
  regeneration, and after it a no-op edit stays a no-op. Nothing in this repository states one, so no
  golden and no fixture moves.
- **The wire verify can make a currently applicable deployment inapplicable.** → That is the point: the
  value the consumer receives is one its own declaration refuses. The row names the consumer, the slot
  and what the type said, so the fix is local.
- **Evaluation cost grows in two places.** → The widened mention scan and one verify per delivered
  read. Both are gated by `nix build .#checks.x86_64-linux.planner-perf` against the nine budgets,
  margin 0.15 and growth bound 1.25 across sizes 4, 16, 64 and 256, and the budgets are re-measured
  in the same change rather than relaxed.
- **Twelve kind checks are twelve chances to miss a thirteenth site.** → The probes catch a miss by
  ending a check rather than a suite, and the honest statement is the one the tree already records:
  there is no mechanical proof, because the source scan cannot see an index.
- **Two uncatchable conditions remain.** → Narrowed and named, not closed. What changes is that the
  table survives them, so an operator reads a sentence instead of a stack of nix frames.
- **The command's refusals grow, and a machine that used to be reported is now a refusal.** → Each of
  the five is a case where the command printed a verdict it had not measured, which is worse than an
  exit code.

## Open Questions

- **Does `stated` have a second reader?** It is recorded for the key input and the key input is the
  only consumer this change can find. It is deleted on that basis; if a reader turns up during the
  work, the field stays and the comparison is applied where it is read instead.
- **Should the two formals conditions be refused at the deployment's edge instead?** A root could be
  required to declare that its module's `impl` is variadic, which turns an uncatchable raise into a
  declaration a reading can check. It is left out because it adds a field to every module for a
  mistake a stated contract and one sentence in the documents already cover.
