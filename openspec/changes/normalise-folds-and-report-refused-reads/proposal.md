## Why

Two findings measured against the fold `hold-declaration-shape-and-fold-set-reads` landed, on throwaway
deployments run through `nix eval .#lib --apply` and deleted after. Neither needs a library change.
Both are about what a fold is for, and one of them is a promise the spec makes and the implementation
does not keep.

**A refused fold is reportable only where the consuming implementation does not force the slot.**
`hold-declaration-shape-and-fold-set-reads/specs/planner/interface-fold/spec.md:78` states that a
raising fold still produces "the plan ... for every other entry". Measured with two consumers of one
provider-keyed set, each reading `results.keys` the ordinary way, a fold that returns
`{ refused = "..."; }` and a fold that raises both end the evaluation instead:

```
error: attribute 'keys' missing
  env.RENDERED = ... results.keys
  ... while evaluating the attribute 'applicable' at lib/default.nix:116
```

The chain is decided behaviour at every link: a refused read is absent from `results`
(`lib/resolve.nix:1000-1006`, design D3), a missing attribute is what `builtins.tryEval` does not
catch, and `applicable` forces the whole table (`lib/default.nix:111-116`), so no row renders for any
entry. The same deployment with `if results ? keys then ... else "<undelivered>"` in both consumers
produces exactly what the requirement promises: two `interface-fold-refused` rows carrying the fold's
own message, subjects `authz:node` and `hosts:node`, `reads.keys.delivered = false` on both, and
`applicable = false`. A raising fold in the same shape gives two `interface-fold-raised` rows and an
empty message list, which is `tryEval` behaving as documented.

That condition appears in no spec, no document and no test. Its class already has a precedent:
`tests/unit/coverage.nix:286-290` omits "A module's own code raises an uncatchable error" because a
test of the propagation would abort the suite rather than fail it.

**The published fold example renders bytes, which is what makes one fold per interface look like a
limit.** `docs/authoring.md:72-79` shows `sshHostIdentity`'s fold concatenating `authorized_keys`
lines, and `docs/authoring.md:185-188` tells an author the consumer then "walks nothing". Copy that
and the first consumer wanting a different file format has to declare a second interface for a
formatting difference. A fold that normalises instead - validate, refuse, order, keep each provider's
entry key, return records - serves any number of consumers, each rendering its own bytes in `impl`.
ThermOS is the outside evidence: every `contract.merge` under its `modules/contracts/` returns data
(`units.nix` deep merge, `etc.nix` conflict detection, `packages.nix` concatenation) and every byte is
rendered in a builder or in a middleware module, never in a merge. Measured here with one normalising
fold and two consumers of it: `authorizedKeys` is `"# ids:node@p1\nssh-ed25519 ...\n# ids:node@p2\n..."`,
`knownHosts` is `"ids:node@p1=ssh-ed25519 ...,ids:node@p2=..."`, the plan is applicable, and
`reads.keys.entries` still names both providers.

## What Changes

- **The raising-and-refusing requirement gains its condition.** A fold's row is produced for every
  entry whose implementation does not force the absent slot; a consumer that reads the slot the
  ordinary way fails with a missing attribute, and then no table is produced for any entry. The
  requirement keeps its three current scenarios and gains the guarded and unguarded cases as scenarios
  of their own.
- **One fold serves every consumer, and that becomes a stated requirement.** Two consumers reading one
  interface with set reach receive one folded value, and a consumer's own `reads` still decides what
  entered its fold input, so two consumers naming different reads fold two different projections under
  one policy. Nothing in the tree records this today: every fold scenario has exactly one consumer.
- **The documented fold is a normalising fold.** `docs/authoring.md`'s example returns records keyed
  by provider entry and refuses by returned value; the rendering moves into the consumer's `impl`,
  where the file format belongs. The prose stating a consumer "walks nothing" is replaced by the rule
  it should have carried: a second interface is for a different policy, never for a different format.
- **The refusal sections state when a refusal reports.** `docs/authoring.md`'s "When a read is refused"
  and "Where a refusal lives", and the two fold rows in `docs/diagnostics.md`, name the condition and
  the consequence of an unguarded read.
- **No library change, no plan field, no golden move, no budget re-measurement.** The behaviour is
  already what the implementation does; what changes is the spec, the documents and the tests that
  hold them. `fixtures/minimal-typed-edge` keeps its hand-written fold, for the reason recorded at
  `hold-declaration-shape-and-fold-set-reads/design.md:219-222`: the fixture's value is evidence of
  the unfolded shape.

## Capabilities

### New Capabilities

None. Both requirements belong to `planner/interface-fold`, which
`hold-declaration-shape-and-fold-set-reads` introduced and this change corrects and extends.

### Modified Capabilities

- `planner/interface-fold`: the malformed-or-raising requirement is restated with the condition under
  which a refusal is reportable, and one requirement is added for the many-consumer case that decides
  what a fold should return.

No `planner/diagnostics` change: the refusal channel and the id, subject and severity split stay
exactly as decided. No `planner/plan-artifact` change: no entry field moves. No `tooling/*` change: a
new spec file, its `accountable` entry and its per-scenario tests are what `tooling/nix-unit-suite`
already requires of any addition.

## Impact

- **`openspec/changes/normalise-folds-and-report-refused-reads/specs/planner/interface-fold/spec.md`**:
  one modified requirement with five scenarios, one added requirement with two.
- **`tests/unit/coverage.nix`**: the spec path joins `accountable`; the unguarded-read scenario joins
  `omitted` with the reason its class already carries.
- **`tests/unit/resolution.nix`**: three tests beside the existing fold tests - a guarded consumer
  still reporting a refusal, two consumers of one fold receiving one value, and two consumers whose
  different `reads` fold different projections.
- **`docs/authoring.md`**: the fold example, the table row about what a fold returns, the
  second-interface rule, and the two refusal sections.
- **`docs/diagnostics.md`**: the `interface-fold-raised` and `interface-fold-refused` rows.
- **`CLAUDE.md`**: one invariant under "Interfaces, composition, reads".
- **Not in scope**: changing the behaviour. A poisoned value that raises with the row's text on access
  was considered and rejected in design; `collects` and `contributes` stay excluded
  (`lib/excluded.nix:49-60`), which is where a per-consumer transformation belongs.
