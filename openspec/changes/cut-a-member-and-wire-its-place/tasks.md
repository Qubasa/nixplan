## 1. Record what exists

- [ ] 1.1 List this change's three spec files under `excused` in `tests/unit/coverage.nix` with the
  reason the tree uses for an unimplemented change, and verify
  `nix build .#checks.x86_64-linux.planner-tests` reports no unclassified specification
- [ ] 1.2 Record the golden plan of `fixtures/minimal-typed-edge/` and the plan keys of every
  end-to-end folder, so "no key that remains moves" is a comparison rather than a claim
- [ ] 1.3 Record the current refusals: a `members.<n>.enable` deployment and a `wire.<member>.<slot>`
  deployment, each with the row it earns, and the exclusion row count
  `tests/unit/exclusions.nix` compares against the fixture README

## 2. A root binds a member's slot

- [ ] 2.1 Add `wire` to `serviceKeys` in `lib/compose.nix` and carry the bindings on the member
  handle, and verify a root writing an unknown key still earns its row
- [ ] 2.2 Resolve a bound slot in `lib/resolve.nix` from the capability record's own `member` and
  `capability` fields, and verify a two-member root needs no deployment wire and produces the read
- [ ] 2.3 Verify a binding is subject to every check a wire is: the interface-mismatch row, the
  placement-count row for `reach = "one"`, the no-placement row for `reach = "all"`, and the
  export-level rows
- [ ] 2.4 Verify a binding earns no `slot-unwired` row, and that an instance-level wire still fills a
  slot no binding fills
- [ ] 2.5 Verify the fixture's golden plan recorded in 1.2 is unchanged, since no fixture root
  writes a binding

## 3. A deployment cuts a member

- [ ] 3.1 Add `members` to `instanceKeys` in `lib/resolve.nix`, read `members.<name>.enable` before
  placement, settings namespaces and generators, and verify a cut member produces no entry, no value
  entry and no name in any `dependsOn`
- [ ] 3.2 Verify an instance writing no `members` block produces exactly the plan it produces today,
  against 1.2
- [ ] 3.3 Add the rows for naming a cut member in `placement`, in `settings` and as a wire's
  consumer, reusing the keyset comparison `namespaceRows` already makes, and verify each names the
  member and the cut
- [ ] 3.4 Verify a mistyped member name in a `members` block earns the row for a member the module
  does not publish rather than silently cutting nothing

## 4. The binding-versus-address rule

- [ ] 4.1 Discard a binding whose target member the deployment cut, and verify the slot is then
  unwired and earns the existing `slot-unwired` row subjected to the referring member's entry
- [ ] 4.2 Read `wire.<member>.<slot>` as an address: delete the exclusion row at
  `lib/resolve.nix:1436-1444`, resolve the named instance and capability, and verify the slot
  resolves and the planner emits no row
- [ ] 4.3 Add the row for a member-scoped wire naming a slot whose binding points at a kept member,
  and verify the binding still resolves the slot
- [ ] 4.4 Verify the one-module-two-instances case: one instance keeping every member and one cutting
  a member and wiring its place both resolve, from identical module source
- [ ] 4.5 Verify that only the consuming entry's key moves in the cut instance, against 1.2

## 5. A capability taken once

- [ ] 5.1 Add `consumers` to `capabilityKeys` in `lib/module.nix` with its domain, and verify a value
  outside the domain earns a row
- [ ] 5.2 Add the deployment-wide fold counting wires per capability, subject the row to the
  providing capability, and verify two consumers of one single-consumer capability produce exactly
  one row naming both
- [ ] 5.3 Verify two consumers taking two single-consumer capabilities of one instance produce no
  row, and that a capability declaring nothing admits any number
- [ ] 5.4 Verify a single consumer placed on two machines produces no row

## 6. The exclusion table

- [ ] 6.1 Remove `enable` and `memberWire` and the `member cuts` row from `lib/excluded.nix`, and
  verify `excluded.rows` holds the remaining six
- [ ] 6.2 Update `tests/unit/exclusions.nix` and the table in `fixtures/minimal-typed-edge/README.md`
  together, and verify the suite's row count matches the README
- [ ] 6.3 Verify a deployment writing `members.<n>.enable` no longer earns an exclusion row, against
  the refusals recorded in 1.3

## 7. Tests

- [ ] 7.1 Add the binding scenarios to `tests/unit/compose.nix` and `tests/unit/typed-edge.nix`, and
  verify each fails against the pre-change tree
- [ ] 7.2 Add the cut scenarios to `tests/unit/resolve.nix` and `tests/unit/plan.nix`, including the
  two plans that must be equal and the one key that must move
- [ ] 7.3 Add the row scenarios to `tests/unit/diagnostics.nix`, including that a cut with an unwired
  slot reports the existing row and no second one
- [ ] 7.4 Add the single-consumer scenarios
- [ ] 7.5 Register every new scenario in `tests/unit/coverage.nix`, move this change's spec files to
  `accountable`, and verify the suite reports no unmapped scenario

## 8. On machines, and documents

- [ ] 8.1 Rewrite `tests/e2e/shared-postgres/`'s consumer as one module composing a consumer and its
  own private database, bound inside the root, and make the folder's two consumer instances two cuts
  of it wired to the shared cluster
- [ ] 8.2 Verify every plan key of that folder is unchanged except the two consuming entries, against
  a record taken before the rewrite
- [ ] 8.3 Add the third instance the corpus's claim needs: one instance of the same module keeping
  its private database, and verify it runs its own and reads no shared capability
- [ ] 8.4 Run `nix run .#planner-e2e -- shared-postgres` and verify every assertion of the folder
  still holds
- [ ] 8.5 Update `docs/authoring.md` (bindings, cuts, member-scoped wires, `consumers`),
  `docs/diagnostics.md` (the new rows and the removed exclusion row), `docs/plan.md` (a cut is an
  absence and no field), and verify `nix build .#checks.x86_64-linux.treefmt` passes
- [ ] 8.6 Update `CLAUDE.md`: a binding is a value off a member handle, the three cases of the
  binding-versus-address rule, `consumers` counts wires and not placements, and the exclusion table
  is one row shorter; remove the statement that member cuts are excluded
- [ ] 8.7 Update `notes/examples/instance-as-group/README.md`'s first line in the source repository
  if that corpus is still the reference, or record in `CLAUDE.md` that the shape it sketches now
  exists in `tests/e2e/shared-postgres/`
