<!--
A delta on `tooling/scenario-suite`, which is defined in the unarchived
`add-scenario-test-harness` change. The whole capability is removed: its subject was a committed
configuration corpus, a serialised artifact a separate Python suite read, and a two-layer rule
policed by prose. `tooling/test-layers` replaces all three, and in it a configuration under test is
a directory belonging to one end-to-end test that a real machine also runs. The change that
introduced this capability stays unarchived as the record of why a committed corpus was worth
having; what it argued for is kept, not dropped.
-->

## REMOVED Requirements

### Requirement: A scenario is a committed configuration directory

**Reason**: The property this requirement protected — a deployment under test that reads like a
deployment an operator would write, discovered rather than listed, never assembled by a test helper
— is kept, but it is no longer a property of a shared corpus. It is a property of each end-to-end
test's own directory.

**Migration**: `tooling/test-layers`, requirement *An end-to-end test carries its own fixture*. Its
scenario *A reader opens an end-to-end directory* carries the same obligation as this
requirement's *A reader inspects what is under test*, with the addition that the registry the
instances are placed against is in that directory too. Discovery survives as discovery of
end-to-end directories rather than of scenario directories.

### Requirement: The asserting half reads a serialised artifact

**Reason**: The split existed because the asserting half was Python and could not evaluate Nix, so
the plan had to be serialised, re-typed and re-read to be asserted. The claims that were asserted
this way are attributes of the value `mkPlan` returns and are now asserted in evaluation, where no
serialisation boundary, no artifact and no loader is needed.

**Migration**: `tooling/nix-unit-suite`, requirement *The suite runs from the flake with one
command*, now carries these claims. There is no artifact to inspect by hand because there is no
artifact; `nix eval` over the plan is the inspection, which is what the scenario *The artifact is
inspected by hand* was reaching for.

### Requirement: A failure names the field that differs

**Reason**: The obligation is unchanged but it is no longer this capability's. A comparison that
reports differing attribute paths rather than two documents is required of the golden comparison,
which is where the only remaining whole-document comparison lives.

**Migration**: `tooling/nix-unit-suite`, requirement *Golden comparisons print a usable difference*,
scenario *A golden fixture drifts* — unchanged by this change and already stating that a failure
names the entry and the field and does not print the whole plan.

### Requirement: Comparison and regeneration share one traversal

**Reason**: The shared traversal existed to hold one rule: which fields participate in a
comparison. That rule existed because the committed fixture carried prose keys the produced plan
does not. The fixture no longer carries them, so every field participates, there is no rule to
share, and regeneration is one documented command over the same value the comparison reads.

**Migration**: `tooling/nix-unit-suite`, requirement *Golden comparisons print a usable difference*,
scenarios *A fixture is regenerated* and *Regeneration is not automatic*, both unchanged. The prose
this requirement's traversal preserved moves beside the fixture as prose.

### Requirement: Each test belongs to exactly one layer

**Reason**: Kept, and strengthened from documented prose into a mechanical check. This requirement
asked the project to document a decidable rule and asked authors to follow it; nothing failed when
they did not, which is how the same behaviour came to be asserted in three places.

**Migration**: `tooling/test-layers`, requirements *A planner test belongs to one of two layers* and
*A behaviour is asserted in one layer only*. The latter's scenario *One behaviour is asserted in
both layers* makes double assertion a check failure naming both files, which is what this
requirement's *A behaviour is already covered* could only advise against.

### Requirement: The specification cross-walk may name a scenario test

**Reason**: There are no longer two suites for the cross-walk to choose between by name, and it no
longer names tests at all. A heading yields its test's name, and the check resolves that name in
whichever layer it exists.

**Migration**: `tooling/nix-unit-suite`, requirement *Every spec scenario maps to a named test*, as
modified by this change — in particular its scenario *A test name is derived from a heading*. The
protection this requirement wanted, that a renamed or deleted test fails the check, is stronger
under a derivation than under a table: `tooling/test-layers`, scenario *A scenario heading is
reworded*.

### Requirement: A scenario whose result cannot be serialised is refused loudly

**Reason**: Nothing is serialised, so nothing can fail to serialise. The underlying hazard — a
module dereferencing a slot whose delivery was refused raises where the planner cannot catch it —
is a planner claim and is asserted where planner claims are asserted, not by a harness reporting
that it could not write a file.

**Migration**: `implement-minimal-typed-edge`, `planner/diagnostics`, whose totality requirements
own that hazard, and `tooling/nix-unit-suite`, requirement *Total evaluation is checked as a
property*. Neither changes.

### Requirement: A scenario no test names is a failure

**Reason**: A fixture can no longer accumulate unread, because a fixture is not a corpus entry that
a suite might or might not name. It is a directory inside the one test that uses it, and removing
that test removes it.

**Migration**: `tooling/test-layers`, requirement *An end-to-end test carries its own fixture*,
scenario *An end-to-end test is deleted*, which states that no fixture is left behind that nothing
reads.
