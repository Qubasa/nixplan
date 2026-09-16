## Context

See `proposal.md` - Why. The shapes that decide the approach are the ones the tree already holds:

- **`builtins.tryEval` is weaker than the guarantee it is used to keep.** It catches a `throw` and a
  failed `assert`, and neither an abort nor a missing attribute
  (`lib/diagnostics.nix:55-58`, `lib/default.nix:5-8`). A type error from `removeAttrs`, `attrNames`
  or `mapAttrs` applied to a non-record is in the uncatchable class: `builtins.tryEval
  (builtins.removeAttrs 5 [ ])` raises rather than answering `{ success = false; }`, and so does
  `builtins.tryEval (builtins.mapAttrs (n: v: v) 5)`. Both were evaluated. A guard is therefore not a
  substitute for a check, and no amount of wrapping fixes an unchecked index.
- **The deployment half already has the reading this change gives the module half.** `declaredField`
  and `declaredRecord` (`lib/resolve.nix:90-159`) take a `subject`, a `file`, a `where` and a shape
  out of `shapes` (`:64-85`), return a fallback, and emit `declaration-field-malformed` or
  `declaration-field-missing`. The comment above them says why: "the unknown-key scans call
  `attrNames` on the record itself, and that ends the evaluation rather than filling a row"
  (`lib/resolve.nix:132-134`). That sentence is true of the module half too, and nothing there acts on
  it.
- **The implementation half is the worked example of recovery.** `implShape` (`lib/resolve.nix:1216`)
  forces only the shape, `implNotAttrs` produces `implementation-malformed` (`:1346-1354`), and
  `unitsRaw` and `closureRaw` each guard one field. The declaration half is applied bare at
  `lib/compose.nix:30-31` and has none of it.
- **A fail-open index is worse than a raise.** `5432 ? fixed` is `false` rather than an error, so
  `util.filterAttrs (_: claim: claim ? fixed)` (`lib/module.nix:355`) drops a malformed claim
  silently, and `port-claim-not-fixed` (`lib/module.nix:344-352`) is the row a naive suppression
  would produce - a sentence about the wrong mistake.
- **A row is the only channel.** `lib/*.nix` carries no `throw`, `abort`, `assert`, `.check ` or
  `korora.check`, and `tests/unit/diagnostics.nix:476-508` scans the source text for them. Every rule
  below is a returned row.

## Goals / Non-Goals

**Goals:**

- No declaration a module or a root can write ends the evaluation. A malformed one is a row naming
  the module file and the site, and every other entry of the deployment is still planned.
- A module that raises while computing its declaration is attributable, as one raising while
  computing its implementation already is.
- A wire and a binding resolve only to a far end that can be type-checked, and a far end that cannot
  leaves the slot undelivered rather than the table unprinted.
- The guarantee is held by probes that plan a malformed declaration, because the text scan cannot see
  an index.

**Non-Goals:**

- No new tolerance. A malformed declaration produces a row and a fallback; it does not produce a
  plan entry built from a guess. A port claim that is not a record claims no port, a slot that is
  not a record declares no slot, and neither is defaulted into existence.
- No `throw` sentinel anywhere. A refusal is a returned value, which is the rule
  `lib/diagnostics.nix` and `lib/resolve.nix:1012-1018` already follow, and a sentinel would put a
  raising call into `lib/`.
- No widening of `mkPlan`'s own argument record. See the open question below.
- No new search and no inference. The check is one predicate per record the reading already reads.

## Decisions

### The check lives in the readings, not at the index sites

`lib/module.nix` gains one record reading beside `keyRow`, taking the `subject`, the module label and
a `where`, and every sub-reading is routed through it before it indexes: `readClaims` for `claims` and
for each port claim, `readSlot`, `readCapability`, `readVars` for each generator and each generated
file, `readPin`, and `read` for the declaration itself. `lib/compose.nix` does the same for the value
the module returns, because it indexes that value at `:47` and `:75` before `lib/resolve.nix:818`
ever hands it to `module.read`.

Alternative rejected: **an `isAttrs` branch inside `util.extraKeys` (`lib/util.nix:117`).** It is one
line and it is wrong three ways. `extraKeys` is handed an allow-list and a set and nothing else, so it
has no subject, no file and no `where`: the most it can return is an empty key list, which converts
the raise into a silent success. That success then reaches `util.filterAttrs (_: claim: claim ? fixed)`
(`lib/module.nix:355`) and the deployment gets `port-claim-not-fixed` - a row naming a mistake the
author did not make. And `extraKeys` is not the only index: `mapAttrs` over `uses`, `attrNames` in
`lib/compose.nix:47` and the bare `capability.interface` at `lib/resolve.nix:1590` each raise on their
own, so the helper's guard would close one of four doors.

Alternative rejected: **a check at each index site.** Eleven `if builtins.isAttrs` expressions, each
with its own row text, and the twelfth site added next year has none. Putting it in the reading means
a caller inherits it: the realisers and `operator/read.nix` read a plan rather than a declaration, so
what they inherit is that a plan exists at all where today there is none.

### One identifier, `declaration-malformed`

The condition is one: a value a module wrote where the reading needs a record. It is spelled once, and
the row's `where` names which site - a port claim, a slot, a capability, a generator, a generated
file, a pin, the declaration - the way `declaration-field-malformed` (`lib/resolve.nix:110-117`)
serves every field of the deployment half and `declaredRecord` (`:150-158`) reuses that same
identifier for a whole record. The name is chosen to sit beside `implementation-malformed`
(`lib/resolve.nix:1349`): `impl` returning a non-record and the declaration being one are the two
halves of one mistake and now read the same.

Alternative rejected: **one identifier per site.** Seven or eleven rows in `docs/diagnostics.md`
differing only in a noun the message already carries, and a reader filtering the table would have to
know all of them to ask "did this module declare something of the wrong shape".

Alternative rejected: **reusing `declaration-field-malformed` for both halves.** The two halves have
different subjects, different files and different resolutions: the deployment half's resolution names
the deployment file and a field of the deployment's own vocabulary, the module half's names the module
file and the module vocabulary. One identifier over both would make the row's resolution a disjunction.

### A guard fixes one case of the three, and a check fixes the other two

Stated explicitly because the temptation is to wrap everything and declare victory:

- **A malformed record is fixed by a check.** `removeAttrs`, `attrNames` and `mapAttrs` on a non-record
  raise a type error, which `tryEval` does not catch. Wrapping `lib/module.nix`'s readings in
  `diag.guard` would change nothing at all.
- **An untyped far end is fixed by a check.** `capability.interface` where the key is absent is a
  missing attribute, also uncatchable. `lib/resolve.nix:1585` and `:1590` need `capability ?
  interface`, not a wrapper.
- **A module that raises while computing its declaration is fixed by a guard**, and only by a guard: the
  expression is the author's own and its failure mode is a `throw`, an `assert` or an interpolation of
  a missing attribute. The first two are caught and become `module-raised`; the third stays in the
  uncatchable class that `lib/default.nix:6-8` documents as propagating, which this change does not
  claim to fix.

The order matters and the task list follows it: the checks land first, so that what the guard is left
holding is the module's own raise rather than a library index the guard cannot catch anyway. A guard
installed first would appear to work while the library's own type errors flew straight through it,
which is the reading a future author would trust.

### The guard goes where the module is applied

`compose.service` is the one site that applies `module { settings = settings.values; }`
(`lib/compose.nix:31`), and compose itself indexes the result at `:47` and `:75`. Guarding at
`lib/resolve.nix:818` instead would leave those two sites in front of the guard. The member record
therefore carries the rows the way it already carries `unknownKeys` and `slotSet`
(`lib/compose.nix:66-67`), and `memberRows` (`lib/resolve.nix:1078-1105`) collects them beside
`member.unknownKeys` at `:1091`.

### A raising declaration degrades into `impl-missing`

The guard's fallback is the empty record. `read` then finds no `impl`
and produces `impl-missing` (`lib/module.nix:1072-1080`) beside `module-raised`. Two rows for one
mistake is correct here and is not a duplicate: the first names what raised, the second names what the
entry consequently has none of, which is what stops the entry from being planned into a unit.

Alternative rejected: **a `declaration-not-computed` identifier.** It would be a third sentence for
one mistake, and `module-raised`'s message already says "its value is recorded as not computed"
(`docs/diagnostics.md:217`).

### The wire's row is about the consumer and does not suppress the provider's

`capability-interface-missing` (`lib/module.nix:315-323`) is the provider's row: its subject is the
module file that declared the capability, and the resolution is to pass the interface value in.
`wire-capability-untyped` is the consumer's: its subject is the consuming entry, it names the
capability and the slot, and the slot is left undelivered - absent from `results`, not `null` and not
`{ }`, which is the rule a refused read already follows.

Alternative rejected: **suppressing the consumer's row when the provider's exists.** `dedup` keys on
(id, subject, message) and the two subjects differ, so nothing deduplicates them by accident. An
operator filtering the table to one entry's key would then see an entry with a slot that never
resolved and no row explaining it. Two entries have a problem.

### The unit half keeps its filters and `implementation-malformed`

Recorded against the proposal's own reading of `lib/resolve.nix:1234` and `:1253`, which said those
filters drop a non-record unit and a non-record configuration file silently. They do not. Each filter
selects the records the reading is handed, and `malformed` (`:1278-1284` at the base commit) reports
the complement, so `units.web = 5` already earns `implementation-malformed` naming `unit "web"` and the
entry declares no such unit. Measured at `b7dd7e1`: the table carries
`implementation-malformed :: bad:only@two` and the deployment is still planned.

What did end the evaluation is the container: `units = 5` reaches `util.filterAttrs` and aborts with
`expected a set but found an integer: 5`. That is the fourth abort of this family, found by the
probes, and it is fixed the way the other three are - a kind read before the index, with
`unitsDeclared` and `configDeclared` falling back to `{ }` and `malformed` gaining `the unit set` and
`the configuration data` as sites.

`readUnit` and `readConfigFile` are therefore not routed through `declaredRecord`. They are handed
only records by construction, so the branch would be unreachable, and the row for this half is
`implementation-malformed` - the identifier the spec's fourth scenario asks the declaration half to
read the same as. A second identifier for the same site, reachable from nothing, is worse than the
filter it would replace.

### `binding-malformed` widens rather than gaining a sibling

`bindingOf` (`lib/resolve.nix:1009`) tests `given ? member && given ? capability`. A hand-written
record satisfying both is still not "a capability value off a sibling's handle", which is exactly what
the row's own message and evidence say (`:1050-1051`). Requiring `interface` as well is the same
condition read more completely, so the identifier, the message and the resolution are unchanged and
`docs/diagnostics.md:156` gains one clause rather than a row. `member` and `capability` are also read
for being strings rather than for being present, because the line below indexes `memberKeyOf` with the
first of them and a non-string key is the same uncatchable type error this change is about.

Alternative rejected: **a `binding-untyped` identifier.** It would split one condition in two and
oblige an author to learn which of the two their typo earns.

### The suite plans probes rather than scanning source

The purity scan (`tests/unit/diagnostics.nix:476-508`) matches five call spellings as substrings over
comment-stripped lines. None of `removeAttrs`, `attrNames`, `mapAttrs` or `capability.interface` is a
call whose failure mode a spelling can name, and adding them would refuse the library's own legitimate
indexes into values it just built. The property is therefore held by evaluation: one probe per shape
that plans the malformed declaration, deep-forces the plan and the table, and asserts the row's
identifier and subject. A probe that asserted only that the evaluation completed would pass against a
reading that dropped the declaration silently, which is why each probe's expectation is the row.

## Risks / Trade-offs

- **A deployment that raises today starts producing a plan, and a consumer's build that used to fail
  loudly now fails with a table.** → That is the change. Every condition here is an error row, so the
  deployment is inapplicable and `operator/default.nix` refuses through `planner.render`; what moves
  is that the refusal names the declaration to edit.
- **A golden could move.** → None can. Each new row's condition currently ends the evaluation, so no
  deployment that evaluates can contain one, and `fixtures/minimal-typed-edge`, `perf/fleet.nix` and
  `perf/mesh.nix` all evaluate. The argument is structural rather than an inspection, and the
  fixture's `plan/*` comparison and `diagnostics.txt` comparison are the check.
- **Cost.** → One predicate per record the reading already reads, and one `tryEval` per member for the
  declaration guard. `diag.guard` deep-forces its value, and the declaration is a value the planner
  forces in full anyway, so the added work is the traversal's bookkeeping rather than a second
  traversal. The gate is `nix build .#checks.x86_64-linux.planner-perf` against the nine budgets,
  margin 0.15 and growth bound 1.25 across sizes 4, 16, 64 and 256.
- **A module that fails with an abort or a missing attribute still ends the evaluation.** → Unchanged
  and documented (`lib/default.nix:6-8`). The class is narrowed, not closed: what was three families
  of failure becomes one, and that one is the author's own uncatchable expression rather than the
  library's index into it.
- **Eleven call sites is eleven chances to miss one.** → The probes are what catch a miss, and the
  reading is one function, so a site added later that does not use it is a red test rather than a
  green suite. There is no mechanical proof that every index goes through the reading; the honest
  statement is that the scan cannot provide one and the probes cover the shapes a declaration has.

## Open Questions

- **Is `mkPlan`'s own argument record held to this rule?** `interfaces`, `sources` and `varsState` are
  a caller's records, not a declaration, and a non-record `interfaces` would raise inside
  `interface.fileOf` the way a non-record `provides` raises today. It is left out of this change
  because a row needs a subject and a caller's argument has no plan key and no deployment file to
  name, which is a naming decision this change does not want to take silently. The alternative - a
  fourth surface with rows subjected to an issue identifier - is a separate proposal.
