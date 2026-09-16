## 1. The name the cardinality is read by

- [x] 1.1 In `lib/resolve.nix:1581-1582`, read `providerDeclared` as
  `providerMember.declaration.provides.${capability.capability} or null`, and update the comment above
  it to say that the cardinality is the member's statement while the wire's own field is the root's
  exposed name. Verify with a throwaway deployment evaluated through `nix eval .#lib --apply`: one
  provider member declaring `consumers = "one"`, a root writing `provides.endpoint =
  server.provides.repo`, and two instances wiring `endpoint`. Before the edit the table is empty and
  `applicable` is true; after it the table carries exactly one `capability-consumers-exceeded` row
  subjected to the providing member and `applicable` is false. Delete the probe afterwards and
  confirm nothing was written into the tree. Measured: before, `rows = []` and `applicable = true`;
  after, one error row subjected to `provider:only` reading ``capability `repo` of `provider:only`
  declares `consumers = "one"` and is wired by `authz:only.far`, `hosts:only.far` `` and `applicable
  = false`. The probe was held outside the tree, since a path under it is unreadable in pure
  evaluation mode, and `git status` names no file of it.
- [x] 1.2 Verify the bound path is unmoved. The task said to replace the second wire with a root
  binding and confirm the row unmoved, which is wrong: a binding beside a renamed wire is exactly the
  case the fix repairs, so that deployment's row moves from nothing to one row and is task 2.5. What
  holds the bound path still is a deployment whose *both* consumers are bound members of the
  provider's own root, and that row is byte-identical before and after - identifier
  `capability-consumers-exceeded`, severity `error`, subject `provider:only`, message ``capability
  `repo` of `provider:only` declares `consumers = "one"` and is wired by `provider:also.far`,
  `provider:near.far` ``, `applicable = false`. `capName` and `capability.capability` are one string
  where `isBound` (`lib/resolve.nix:1555`), which is why that side cannot move. The mixed
  binding-and-wire probe measured empty before the edit and one row naming `authz:only.far` and
  `provider:near.far` after it, with the bound slot resolving to the sibling's value on both sides.
- [x] 1.3 Verify nothing else reads `providerDeclared`: `grep` the file and confirm
  `lib/resolve.nix:1853` is its only consumer, so the change has one site. Two mentions in the file,
  the binding at the edited site and the read at `consumers = if providerDeclared == null then
  "many" else providerDeclared.consumers`.

## 2. The regression the tree could not have caught

- [x] 2.1 Give `tests/unit/resolution.nix`'s `taking` helper (`tests/unit/resolution.nix:283-317`) an
  exposure mapping: the provider instance is built with `support.root` rather than `soleRoot`, its
  `provides` is an attrset of exposed name to `{ member = "only"; capability = <declared name>; }`,
  and `exposes` lists the exposed names. Keep `taking caps consumers` meaning what it means today by
  defaulting the mapping to one exposed name per declared capability, name for name, so the four
  existing cardinality tests (`tests/unit/resolution.nix:2266-2421`) keep their deployments. Verify
  those four and `testACapabilityDeclaringAConsumerCountOutsideTheDomain` are green with the helper
  changed and `lib/resolve.nix` unpatched. The parameterised helper is `takingAs`, taking `caps`,
  `consumers` and `exposure`, and `taking = caps: consumers: takingAs { inherit caps consumers; }` is
  the name-for-name shortcut the five keep calling. With the helper changed and `lib/resolve.nix`
  reverted, `nix eval --json .#debug.failuresBySuite.resolution` named only the three new tests
  below, so none of the five moved.
- [x] 2.2 Add `testARootRenamingACapabilityTakenTwice`: one capability declaring `consumers = "one"`,
  exposed under a different name, wired by two instances. Assert the identifier, the `error` severity,
  the subject `provider:only`, that the message names the capability by the name its member declared
  and names both slots, and `applicable = false`. Verify it is red against the unpatched
  `lib/resolve.nix` - the table is empty there - and green after task 1.1.
- [x] 2.3 Add `testARootRenamingACapabilityTakenOnce`: the same renamed exposure wired by one
  instance. Assert an empty row list and that the consumer's read is delivered with the provider's
  exported value, so the fix refuses nothing a single consumer was doing. It asserts the absence of a
  change, so it is green on both sides of task 1.1 by construction; it also pins
  `reads.far.wire.provides` to the exposed name `endpoint`, which is the half the plan records.
- [x] 2.4 Add `testOneCapabilityExposedUnderTwoNames`: one member capability declaring
  `consumers = "one"`, exposed under two names, with one instance wiring each name. Assert exactly one
  `capability-consumers-exceeded` row, its subject, and that the message names both consuming slots,
  which is the assertion that pins the group key to the provider's own capability rather than to the
  exposed name.
- [x] 2.5 Add `testARootBindingAndAWireTakingOneCapability`: a root whose consuming member is bound to
  a sibling's `consumers = "one"` capability and which exposes that capability under another name,
  plus one other instance wiring that name. Assert one row naming the bound slot and the wired slot,
  and that the bound slot still resolves to the sibling's capability. Verify it is red before task 1.1
  and green after.
- [x] 2.6 Verify the suite as a whole: `nix eval --json .#debug.failuresBySuite.resolution` is `{}`,
  and `nix eval --json .#debug.suites --apply 'builtins.mapAttrs (_: builtins.attrNames)'` shows the
  four new names and no other addition. The failure report of a green suite is `[]` rather than `{}`,
  and it is `[]` here; against the unpatched library it is
  `["testARootBindingAndAWireTakingOneCapability", "testARootRenamingACapabilityTakenTwice",
  "testOneCapabilityExposedUnderTwoNames"]`, three of the four for the reason recorded in task 2.3.
  The suite holds 57 tests where it held 53, and no other suite's name list moved.

## 3. The goldens that must not move

- [x] 3.1 Verify no golden moves: `nix eval --json .#debug.worked.plan | jq -S .` equals
  `fixtures/minimal-typed-edge/plan/backup.json` as committed, and
  `fixtures/minimal-typed-edge/plan/diagnostics.txt` is byte-equal. Nothing under `fixtures/` declares
  `consumers` and the fixture root re-exposes name for name
  (`fixtures/minimal-typed-edge/modules/borg-repo/default.nix:21`), so a moved golden means the fix
  changed a case it was not supposed to reach. `cmp` of the regenerated plan against `backup.json`
  is silent, `git diff b7dd7e1 -- fixtures/` is empty, and `plan.testTheGoldenPlanMatches` and the
  fixture's rendered table are green in the suite build.
- [x] 3.2 Verify the plan of a renamed deployment is unchanged by the fix: take the probe of task 1.1
  with a single consumer, and confirm the entry keys, `reads.far.wire.provides` (which records the
  exposed name the deployment wrote) and every recorded read are identical before and after the edit.
  No plan field carries a cardinality (`lib/plan.nix:236-241`), so the only difference a renamed
  deployment can show is the table. Identical: keys `authz:only@one`, `machine:one`,
  `provider:only@one`; `wire = { instance = "provider"; provides = "endpoint"; }`; the read
  `delivered`, `entry = "provider:only@one"`, `reach = "one"` and `values.publicKey`.

## 4. Registration and documentation

- [x] 4.1 Move `hold-the-consumer-cardinality-a-provider-states/specs/planner/typed-edge/spec.md` from
  `excused` to `accountable` in `tests/unit/coverage.nix` - the excuse is "an unimplemented change"
  and it expires the moment a task of this change is ticked - and verify
  `testEverySpecificationIsClassified` and the scenario cross-walk are green: each of the eight
  scenario headings must find the test name it derives, the four kept ones resolving to the tests that
  already answer for `cut-a-member-and-wire-its-place`'s copy of the same titles.
- [x] 4.2 Update `docs/tooling.md:87`: the `resolution` suite's recorded figure moves by the four tests
  of task 2, and `coverage.testASuiteGainsATest` compares that figure against the suite. Verify with
  `nix eval --json .#debug.suites.coverage` reporting no failure for it. 53 to 57, and the prose total
  the same check compares moves 507 to 511, which the suite build's own last line confirms.
- [x] 4.3 Extend the `capability-consumers-exceeded` row in `docs/diagnostics.md:203` and the section
  "How many consumers a capability admits" in `docs/authoring.md:820-827` with the rule: the
  cardinality is read by the member's own capability name, so exposing the capability under another
  name, or under two names, changes which name a wire may address and never how many wires may take
  it. No row identifier is added by this change, so every identifier still appears exactly once in
  `docs/diagnostics.md`. Verify `nix build .#checks.x86_64-linux.treefmt` passes, vale included.
- [x] 4.4 Record the rule in `CLAUDE.md` at the `consumers` bullet under "Interfaces, composition,
  reads" (`CLAUDE.md:240-243`), beside the sentence that already says the count is over wires: the
  declared cardinality is read by the member's own capability name, a root's `provides` decides what a
  wire may address and not how many wires may take it, and one capability exposed under two names is
  one capability. Verify the file still lints under `nix build .#checks.x86_64-linux.treefmt`.

## 5. Verification

- [x] 5.1 Run `nix build .#checks.x86_64-linux.planner-tests` and verify every suite is green,
  including `plan`'s golden comparison and the fixture's `diagnostics.txt` byte comparison, and record
  which suites this change moved: `resolution` gains four tests and nothing else gains any. 511 of
  511 successful, and `nix eval --json .#debug.failures` is `[]`.
- [x] 5.2 Run `nix build .#checks.x86_64-linux.planner-perf` and verify the nine budgets hold. The edit
  replaces one attribute selection with another on a value the same expression already forces
  (`lib/resolve.nix:1575-1576`), so the expectation is an unmoved figure; record the measured cost per
  entry for `mesh-64` and `mesh-256` if any gated counter moves at all, since the edge count is what
  those fixtures scale. Every gated figure of this tree is already above its recorded budget before
  this change, so the comparison made was against the same measurement of the base commit through
  `packages.planner-perf-results`: 81 of 81 gated figures fail on both sides and every one of them is
  the same number to four digits, `nrThunks` of `mesh-64` 459.2073 against a budget of 409.2539 and of
  `mesh-256` 438.8284 against 390.8375, `sets.bytes` of `mesh-256` 6041.2172 against 5652.4838. Every
  counter of every one of the nine fixtures is bit-identical between the two measurements, so the only
  lines that differ are the advisory wall-clock and cpuTime ones, and the growth bound against size 4
  is unmoved at three digits.
