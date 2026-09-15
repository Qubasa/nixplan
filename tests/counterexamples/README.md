# Counterexamples

`probes.nix` holds one attribute per verified break of an invariant this tree states about
itself: a deployment that ends the evaluation where a diagnostics row is owed. Each attribute
quotes the claim it breaks and evaluates to `"ok"` once the claim holds.

It is not a suite under `tests/unit/`. A nix-unit `expr` that raises uncatchably - a call of a
non-function, a missing attribute, `toJSON` of a function - aborts the whole run instead of
failing one test, so these are evaluated one process each.

Run one by hand, with the arguments the check passes:

    nix eval --apply 'p: p.anUnwiredSlotStillLeavesATableToPrint' -f tests/counterexamples/probes.nix

An attribute answering `"ok"` means the defect is fixed; keep the probe as the regression pin.
