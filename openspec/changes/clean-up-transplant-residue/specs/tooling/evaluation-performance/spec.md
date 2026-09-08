<!--
A delta on `tooling/evaluation-performance`, defined in the unarchived
`implement-minimal-typed-edge` change. One requirement changes: a measurement already excludes
building and realising, and now also states what it is a measurement *of*, so that the identity of
a result does not include files no measured evaluation reads. The budget, ratchet and growth
requirements are unaffected and are not restated here.
-->

## MODIFIED Requirements

### Requirement: A measurement covers the library and nothing else

A measurement SHALL cover evaluating a deployment into a plan and forcing that plan, and SHALL
exclude reading the flake, building any derivation and realising any store path. A measurement
SHALL NOT require network access and SHALL NOT write to the store.

A measurement's inputs SHALL be exactly what the measured evaluation reads: the library, the
performance harness and the fixture being planned, each named separately. A file no measured
evaluation reads SHALL NOT be an input, so editing documentation, a specification record or another
test SHALL leave a recorded measurement valid and its result reusable.

#### Scenario: A measurement on a clean checkout

- **WHEN** the harness runs on a checkout whose evaluation caches are empty
- **THEN** the gated counters SHALL equal those from a checkout whose caches are warm

#### Scenario: The harness is asked to build

- **WHEN** a fixture references a package
- **THEN** the fixture SHALL supply it as a literal store path string
- **AND** the measurement SHALL NOT realise it

#### Scenario: A file the measurement does not read is edited

- **WHEN** a file outside the library, the harness and the fixture is edited
- **THEN** the measurement SHALL be unchanged and SHALL NOT be recomputed
- **AND** the harness SHALL name which inputs a measurement has
