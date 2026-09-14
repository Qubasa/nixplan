## 1. The name the cardinality is read by

- [ ] 1.1 In `lib/resolve.nix:1581-1582`, read `providerDeclared` as
  `providerMember.declaration.provides.${capability.capability} or null`, and update the comment above
  it to say that the cardinality is the member's statement while the wire's own field is the root's
  exposed name. Verify with a throwaway deployment evaluated through `nix eval .#lib --apply`: one
  provider member declaring `consumers = "one"`, a root writing `provides.endpoint =
  server.provides.repo`, and two instances wiring `endpoint`. Before the edit the table is empty and
  `applicable` is true; after it the table carries exactly one `capability-consumers-exceeded` row
  subjected to the providing member and `applicable` is false. Delete the probe afterwards and
  confirm nothing was written into the tree.
- [ ] 1.2 Verify the bound path is unmoved: in the same probe, replace the second wire with a root
  binding of a sibling member's slot to that capability, and confirm the row, its subject and its
  message are what they were before the edit. `capName` and `capability.capability` are one string
  where `isBound` (`lib/resolve.nix:1555`), so this is a check that the edit changed nothing there.
- [ ] 1.3 Verify nothing else reads `providerDeclared`: `grep` the file and confirm
  `lib/resolve.nix:1853` is its only consumer, so the change has one site.

## 2. The regression the tree could not have caught

- [ ] 2.1 Give `tests/unit/resolution.nix`'s `taking` helper (`tests/unit/resolution.nix:283-317`) an
  exposure mapping: the provider instance is built with `support.root` rather than `soleRoot`, its
  `provides` is an attrset of exposed name to `{ member = "only"; capability = <declared name>; }`,
  and `exposes` lists the exposed names. Keep `taking caps consumers` meaning what it means today by
  defaulting the mapping to one exposed name per declared capability, name for name, so the four
  existing cardinality tests (`tests/unit/resolution.nix:2266-2421`) keep their deployments. Verify
  those four and `testACapabilityDeclaringAConsumerCountOutsideTheDomain` are green with the helper
  changed and `lib/resolve.nix` unpatched.
- [ ] 2.2 Add `testARootRenamingACapabilityTakenTwice`: one capability declaring `consumers = "one"`,
  exposed under a different name, wired by two instances. Assert the identifier, the `error` severity,
  the subject `provider:only`, that the message names the capability by the name its member declared
  and names both slots, and `applicable = false`. Verify it is red against the unpatched
  `lib/resolve.nix` - the table is empty there - and green after task 1.1.
- [ ] 2.3 Add `testARootRenamingACapabilityTakenOnce`: the same renamed exposure wired by one
  instance. Assert an empty row list and that the consumer's read is delivered with the provider's
  exported value, so the fix refuses nothing a single consumer was doing.
- [ ] 2.4 Add `testOneCapabilityExposedUnderTwoNames`: one member capability declaring
  `consumers = "one"`, exposed under two names, with one instance wiring each name. Assert exactly one
  `capability-consumers-exceeded` row, its subject, and that the message names both consuming slots,
  which is the assertion that pins the group key to the provider's own capability rather than to the
  exposed name.
- [ ] 2.5 Add `testARootBindingAndAWireTakingOneCapability`: a root whose consuming member is bound to
  a sibling's `consumers = "one"` capability and which exposes that capability under another name,
  plus one other instance wiring that name. Assert one row naming the bound slot and the wired slot,
  and that the bound slot still resolves to the sibling's capability. Verify it is red before task 1.1
  and green after.
- [ ] 2.6 Verify the suite as a whole: `nix eval --json .#debug.failuresBySuite.resolution` is `{}`,
  and `nix eval --json .#debug.suites --apply 'builtins.mapAttrs (_: builtins.attrNames)'` shows the
  four new names and no other addition.

## 3. The goldens that must not move

- [ ] 3.1 Verify no golden moves: `nix eval --json .#debug.worked.plan | jq -S .` equals
  `fixtures/minimal-typed-edge/plan/backup.json` as committed, and
  `fixtures/minimal-typed-edge/plan/diagnostics.txt` is byte-equal. Nothing under `fixtures/` declares
  `consumers` and the fixture root re-exposes name for name
  (`fixtures/minimal-typed-edge/modules/borg-repo/default.nix:21`), so a moved golden means the fix
  changed a case it was not supposed to reach.
- [ ] 3.2 Verify the plan of a renamed deployment is unchanged by the fix: take the probe of task 1.1
  with a single consumer, and confirm the entry keys, `reads.far.wire.provides` (which records the
  exposed name the deployment wrote) and every recorded read are identical before and after the edit.
  No plan field carries a cardinality (`lib/plan.nix:236-241`), so the only difference a renamed
  deployment can show is the table.

## 4. Registration and documentation

- [ ] 4.1 Move `hold-the-consumer-cardinality-a-provider-states/specs/planner/typed-edge/spec.md` from
  `excused` to `accountable` in `tests/unit/coverage.nix` - the excuse is "an unimplemented change"
  and it expires the moment a task of this change is ticked - and verify
  `testEverySpecificationIsClassified` and the scenario cross-walk are green: each of the eight
  scenario headings must find the test name it derives, the four kept ones resolving to the tests that
  already answer for `cut-a-member-and-wire-its-place`'s copy of the same titles.
- [ ] 4.2 Update `docs/tooling.md:87`: the `resolution` suite's recorded figure moves by the four tests
  of task 2, and `coverage.testASuiteGainsATest` compares that figure against the suite. Verify with
  `nix eval --json .#debug.suites.coverage` reporting no failure for it.
- [ ] 4.3 Extend the `capability-consumers-exceeded` row in `docs/diagnostics.md:203` and the section
  "How many consumers a capability admits" in `docs/authoring.md:820-827` with the rule: the
  cardinality is read by the member's own capability name, so exposing the capability under another
  name, or under two names, changes which name a wire may address and never how many wires may take
  it. No row identifier is added by this change, so every identifier still appears exactly once in
  `docs/diagnostics.md`. Verify `nix build .#checks.x86_64-linux.treefmt` passes, vale included.
- [ ] 4.4 Record the rule in `CLAUDE.md` at the `consumers` bullet under "Interfaces, composition,
  reads" (`CLAUDE.md:240-243`), beside the sentence that already says the count is over wires: the
  declared cardinality is read by the member's own capability name, a root's `provides` decides what a
  wire may address and not how many wires may take it, and one capability exposed under two names is
  one capability. Verify the file still lints under `nix build .#checks.x86_64-linux.treefmt`.

## 5. Verification

- [ ] 5.1 Run `nix build .#checks.x86_64-linux.planner-tests` and verify every suite is green,
  including `plan`'s golden comparison and the fixture's `diagnostics.txt` byte comparison, and record
  which suites this change moved: `resolution` gains four tests and nothing else gains any.
- [ ] 5.2 Run `nix build .#checks.x86_64-linux.planner-perf` and verify the nine budgets hold. The edit
  replaces one attribute selection with another on a value the same expression already forces
  (`lib/resolve.nix:1575-1576`), so the expectation is an unmoved figure; record the measured cost per
  entry for `mesh-64` and `mesh-256` if any gated counter moves at all, since the edge count is what
  those fixtures scale.
