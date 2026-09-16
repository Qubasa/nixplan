## Purpose

Defines how this repository measures what it costs to evaluate a deployment into a plan, and which of those measurements are allowed to fail a build. The design commits the planner to running on every keystroke in a user interface, and this capability turns that sentence into committed numbers that a change has to answer to.

## ADDED Requirements

### Requirement: Deterministic counters gate and wall clock reports

The harness SHALL gate only on evaluation counters that are equal across repeated runs of one input on one interpreter version. Wall clock and any counter that varies between runs SHALL be reported and SHALL NOT fail a build. The harness SHALL record the interpreter version beside every measurement, and a version change SHALL invalidate the comparison rather than fail it.

#### Scenario: A counter is not reproducible

- **WHEN** a counter the harness gates on differs between two runs of one input
- **THEN** the harness SHALL fail with a message naming that counter
- **AND** SHALL NOT report a budget result derived from it

#### Scenario: Wall clock regresses

- **WHEN** wall clock rises and every gated counter is within budget
- **THEN** the build SHALL pass
- **AND** the report SHALL show the wall clock change

#### Scenario: The interpreter changes

- **WHEN** measurements are compared against budgets recorded under a different interpreter version
- **THEN** the harness SHALL report the comparison as invalid
- **AND** SHALL state which version the budgets were recorded under

### Requirement: Budgets are committed and expressed per plan entry

Budgets SHALL live in a file committed alongside the library. Each budget SHALL be expressed as a cost per plan entry rather than as a total for one fixture, so that a fixture gaining entries does not silently consume headroom. The budget file SHALL name the fixture, the interpreter version and the date each figure was recorded.

#### Scenario: A fixture grows

- **WHEN** a fixture gains plan entries and the cost per entry is unchanged
- **THEN** the build SHALL pass

#### Scenario: Cost per entry rises

- **WHEN** a change raises a gated counter per plan entry above its budget
- **THEN** the build SHALL fail
- **AND** the failure SHALL name the counter, the fixture, the budget and the measured value

#### Scenario: A budget has no recorded provenance

- **WHEN** a budget entry lacks a fixture name, an interpreter version or a date
- **THEN** the harness SHALL fail
- **AND** SHALL name the incomplete entry

### Requirement: The ratchet refuses a stale budget in both directions

When a measurement is materially below its budget, the harness SHALL fail and require the budget to be lowered. The margin that counts as material SHALL be stated in the budget file rather than assumed by the harness. This makes an improvement a deliberate edit rather than accumulated slack.

#### Scenario: An optimisation lands

- **WHEN** a change lowers a gated counter well below its budget
- **THEN** the build SHALL fail with a message giving the new value to write into the budget file
- **AND** the message SHALL be usable as the replacement figure without further arithmetic

#### Scenario: A small improvement

- **WHEN** a measurement falls below its budget by less than the stated margin
- **THEN** the build SHALL pass
- **AND** the report SHALL show the headroom

### Requirement: Growth across fleet sizes is bounded

The harness SHALL measure a synthetic deployment across a range of fleet sizes and SHALL fail when a gated counter grows faster than the bound the budget file states for it. The synthetic deployment SHALL include a set-valued read whose provider is placed on every machine, because that is the resolution whose cost can grow with the square of the fleet.

#### Scenario: A quadratic in set-valued resolution

- **WHEN** a change makes a set-valued read resolve in time proportional to the square of the fleet size
- **THEN** the harness SHALL fail at the largest fleet size before the smallest one exceeds its per-entry budget
- **AND** the failure SHALL name the counter and the two sizes whose ratio broke the bound

#### Scenario: Linear growth passes

- **WHEN** every gated counter grows in proportion to the number of plan entries
- **THEN** the build SHALL pass
- **AND** the report SHALL show the measured ratio at each size

#### Scenario: The synthetic fleet is deterministic

- **WHEN** the synthetic deployment is generated twice at one fleet size
- **THEN** the two deployments SHALL be equal
- **AND** SHALL NOT depend on the current time, the filesystem or any environment variable

### Requirement: A measurement covers the library and nothing else

A measurement SHALL cover evaluating a deployment into a plan and forcing that plan, and SHALL exclude reading the flake, building any derivation and realising any store path. A measurement SHALL NOT require network access and SHALL NOT write to the store.

#### Scenario: A measurement on a clean checkout

- **WHEN** the harness runs on a checkout whose evaluation caches are empty
- **THEN** the gated counters SHALL equal those from a checkout whose caches are warm

#### Scenario: The harness is asked to build

- **WHEN** a fixture references a package
- **THEN** the fixture SHALL supply it as a literal store path string
- **AND** the measurement SHALL NOT realise it
