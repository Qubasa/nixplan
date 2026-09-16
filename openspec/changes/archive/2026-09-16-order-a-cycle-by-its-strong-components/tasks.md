## 1. Record what the current walk does

- [x] 1.1 Run `order.walk` over the mutual fixture the harness already uses and record the order and
  the contradicted edge, so the new walk can be compared against it rather than against a
  description
- [x] 1.2 Build a thousand-entry chain plan in a throwaway script, time `order.walk` on it, and
  record the figure; delete the script and keep the figure in the change
- [x] 1.3 Record the order for a three-entry cycle under the current walk, so the reported-edge
  difference the design states is measured rather than assumed

## 2. The walk becomes a condensation walk

- [x] 2.1 Add the strong-component computation to `cli/order.py` in one pass over the edges, and
  verify against the mutual fixture that both entries land in one component and the third entry does
  not
- [x] 2.2 Walk the condensation in dependency order, breaking ties between independent components by
  the lowest plan key of each, and verify the order for every acyclic case in
  `tests/e2e/test_harness.py` is byte-identical to the recorded one
- [x] 2.3 Order the entries inside a component by plan key and contradict exactly the edges pointing
  backwards in that order, and verify the two-entry mutual case reports the same single edge as
  before
- [x] 2.4 Delete `_eligible` and `_reaches`, and verify no caller outside `cli/order.py` referenced
  either
- [x] 2.5 Return the components the order was broken at beside the order and the contradicted edges,
  and verify the returned record names both entries of the mutual pair

## 3. The refusal and the announcement

- [x] 3.1 Replace the eligibility `next(...)` position with an `ApplyError` naming the entries that
  could not be ordered and the reads between them, and verify by calling the walk with a hand-built
  provider map that violates the invariant that the failure is an `ApplyError`
- [x] 3.2 Report the component above the edge lines in `cli/apply.py`, keeping the existing
  `ordered against the read of` lines, and verify the wired-pair end-to-end assertions still match
- [x] 3.3 Announce a read whose provider the selection excludes, naming consumer and provider, before
  the first dial, and verify with `--only` on the wired-pair deployment that the line appears and the
  consumer is still applied
- [x] 3.4 Verify a full apply announces no unsatisfied read

## 4. Tests

- [x] 4.1 Add the cycle-report scenarios to `tests/e2e/test_harness.py`: a mutual pair named as one
  cycle, an entry reading into a cycle not named in it, and two disjoint cycles reported separately;
  verify each fails against the recorded pre-change behaviour
- [x] 4.2 Add the two scale scenarios with the bounds the design states, and verify the linear
  implementation passes with at least an order of magnitude of headroom
- [x] 4.3 Add the unorderable-state scenario and the two announcement scenarios, and verify each can
  fail by reverting exactly the change it covers
- [x] 4.4 Register every new scenario in `tests/unit/coverage.nix`, and verify
  `nix build .#checks.x86_64-linux.planner-tests` reports no unmapped scenario

## 5. Documents

- [x] 5.1 Document the two report lines in `docs/operator.md` and what an operator does about each,
  and verify `nix build .#checks.x86_64-linux.treefmt` passes
- [x] 5.2 Update `CLAUDE.md`'s statement of the walk so it names the components rather than the
  reachability test, and verify the literal assertions in `tests/unit/layers.nix` still hold
- [x] 5.3 Run the wired-pair end-to-end folder and verify the applied order and the report are
  unchanged for that deployment: `nix run .#planner-e2e -- wired-pair`, 37 passed
