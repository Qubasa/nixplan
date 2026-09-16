## Context

See `proposal.md` - Why. The constraints that shape the approach are the ones the tree already
holds:

- `lib/` never raises and every check is a returned row (`CLAUDE.md`, Purity and totality). A
  collision is therefore a row, never a `throw`, and the plan is still produced.
- Rows are produced per entry today. `entryRows`, `unreadableRows` and `closureRows` are all built
  inside `placedEntry` (`lib/plan.nix:636-739`), which sees one entry. The only site holding every
  placed entry at once is `entries` (`lib/plan.nix:877-964`), whose `rows` is
  `concatLists (map (e: e.rows) serviceEntries)`.
- `pruned` drops an empty attrset from a record (`lib/plan.nix`), so `configData` and `alloc` are
  absent from the plan value of an entry that declares none. Any index built from the plan value has
  to read them defensively; an index built from the pre-pruned record does not.
- The perf gate is cost per plan entry with a margin of 0.15 and a growth bound of 1.25 across sizes
  4, 16, 64 and 256 (`CLAUDE.md`, Perf harness). A pairwise comparison of entries would be quadratic
  in the entries of one machine, and `perf/fleet.nix` at 256 puts one agent and one hub on the same
  machine while `perf/mesh.nix` puts 257 entries in one deployment.
- `lib/` names no realiser. It already reads one unit extension field by name -
  `supplementaryGroups` (`lib/plan.nix:325-343`) - with the comment that says why that is not naming
  a realiser: the key is the one a realiser's directive table and the rule both read.

## Goals / Non-Goals

**Goals:**

- A collision between two entries of one machine is visible from the plan alone, before anything is
  dialled, and it names both entries and the resource.
- The check costs the entries, not their square.
- A module can derive a per-entry name from what it is handed, without its composing root passing
  its own name down through settings.

**Non-Goals:**

- No allocation. The planner does not choose a port, a path or a directory, and no `paths.state`-style
  helper is published. A second instance's port stays a fact the deployment states; the alternative is
  the `dynamicPort` excluded construct (`lib/excluded.nix:32-35`), which needs a persisted allocation
  table.
- No new plan field, no new module vocabulary key, no new declaration. The three claims are read off
  `configData`, `claims.ports` and the extension applications a unit already records.
- No detection of a resource the plan cannot see. A data directory that exists only inside a command
  string (`tests/e2e/shared-postgres/deployment/modules/postgresql/databases.nix:122-128`) is not
  checkable, and inferring paths out of command strings is the same mistake `closure-path-undeclared`
  exists to refuse: inference over an entry's strings cannot be complete. When
  `openspec/changes/declare-service-state` lands, its declared folders join this index by being
  records rather than strings.

## Decisions

**The index is built in `entries`, from claims each `placedEntry` returns.** `placedEntry` gains a
fourth field beside `name`, `rows` and `value`: `claims = { machine, paths, ports, directories }`,
taken from the records it already computed (`configData.record`, `member.alloc.ports`,
`placement.units`). `entries` groups the claims by machine with `builtins.groupBy`, then groups each
machine's claims by resource, and emits one row per resource claimed by more than one entry. Two
levels of `groupBy` over a flat list is linear in claims; the alternative, comparing each entry
against the others, is quadratic and would be measured by `perf/fleet.nix` at 256.

Alternative rejected: computing the index in `lib/resolve.nix` beside placement. Placement is an
earlier stratum than units and configuration files, and a path is a fact of the implementation half;
`unreadableRows` is already in `lib/plan.nix` for exactly that reason (`lib/plan.nix:355-357`).

**A claim is keyed by machine and by resource, and an entry claims each resource once.** The same
member placed on two machines produces two claims under two machines, so it never collides with
itself; two units of one entry recording one directory produce one claim, because the claimant is the
entry. Deduplication of a claim within an entry happens before the collision test, not after.

**The port claim carries the protocol.** `claims.ports.<name>` records `proto` and `count`
(`lib/module.nix:115-119`), and a TCP listener and a UDP listener on one number are not a collision.
`count` is recorded but not expanded: a claim of `count = 2` still has one `fixed` number in this
subset, so the claim compared is `<proto>/<fixed>`. When the allocation table lands, a range is what
this index compares.

**The directory row is a warning; the path and port rows are errors.** Two writers of one file and
two listeners on one port are contradictions - neither declaration can be honoured. A shared
directory is destructive for `runtimeDirectory`, which the service manager deletes when its unit
restarts, and plausible for `stateDirectory`, which two entries of one instance may share as a spool.
A warning names it and the build proceeds, which is the rule the tree already states: a warning that
stopped a build would be an error (`CLAUDE.md`, The operator's command).

Alternative considered: three errors. Rejected because it refuses a deployment the library can
express and a reader may intend, and because the destructive case is the one the row makes visible
either way.

**The row is one row for one collision, subjected to the first plan key in order.** This is the rule
`operator-entry-name-collision` already follows (`operator/read.nix:425-441`): the keys are sorted,
the row names all of them, and the subject is the first. `dedup` keeps the first of two identical
rows, so building the row once from the sorted claimant list is what makes the table deterministic
rather than relying on deduplication.

**`member` is added to `implArgs`, not a whole entry record.** `lib/resolve.nix:1199-1206` already
hands `instance`, `machine`, `settings`, `alloc`, `vars`, `results` and `target`. The missing half of
the entry's identity is the member name, and `mname` is in scope at that site. Handing a composed
`entryKey` instead was rejected: a key is `<instance>:<member>@<machine>` and contains the two
separators a name may not carry, so a module interpolating it into a path would produce a path with
`:` and `@` in it; handing the parts lets the module choose its own separator. No key input changes -
`keyInput` already carries `instance` and `service` (`lib/plan.nix:660-677`) - so the golden plan does
not move.

**The rows fire nowhere in the existing fixtures, and that is checked rather than assumed.**
`fixtures/minimal-typed-edge` places one `borg-repo` server per machine with one port claim and one
`configData` path; `perf/fleet.nix` places one hub, and its agents claim no port and write no
configuration file; `perf/mesh.nix` claims `8443` on `m0` once. The golden plan and the golden
diagnostics table therefore stay byte-equal, which the existing `testTheGoldenPlanMatches` and the
fixture's `diagnostics.txt` comparison assert for free.

## Risks / Trade-offs

- **A deployment that works today starts failing.** → Only where two entries of one machine write one
  file or claim one port, which is a deployment whose second apply overwrites the first entry's file
  or whose daemon cannot bind. The row's resolution names deriving the resource from `instance` and
  `member`, which the same change makes possible.
- **A shared `stateDirectory` produces a warning nobody can silence.** → Accepted: the warning does
  not block, and the alternative is a per-entry opt-out field, which is a new vocabulary key for a
  case no deployment in the tree has.
- **Reading extension fields by name couples `lib/` to a spelling a backend chose.** → The spelling is
  already read in `lib/plan.nix:325-343` for `supplementaryGroups`, with the reasoning recorded; the
  three directory fields are in `image/read.nix:82-84`'s directive table under the same names. A
  backend that names a directory something else records no claim and earns no row, which is the
  fail-open direction.
- **Cost.** → Two `groupBy` passes over one flat claim list. The gate is `nix build
  .#checks.x86_64-linux.planner-perf`; the budgets are per plan entry, so a linear pass moves the
  constant and not the growth bound, and the margin is 0.15.

## Migration Plan

Not applicable: no artifact format, no stored state and no consumer interface changes. A deployment
that earns a new error row stops building and the row says what to change; reverting the change
restores the previous silence.
