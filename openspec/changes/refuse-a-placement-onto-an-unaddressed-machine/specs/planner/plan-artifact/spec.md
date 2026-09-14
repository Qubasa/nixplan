<!--
A delta against `planner/plan-artifact`, whose base text lives in the unarchived changes
`implement-minimal-typed-edge`, `emit-systemd-portable-service-images`,
`prove-plan-on-real-machines`, `deliver-secrets-across-machines`,
`generate-values-with-nixos-secrets`, `report-every-refusal-as-a-row`,
`identify-interfaces-by-declared-id`, `hold-every-stated-guarantee`,
`cut-a-member-and-wire-its-place` and `refuse-two-entries-claiming-one-host-resource`.
`openspec/specs/` is empty in this repository, so the base text is read from those changes.

This delta exists because the requirement it modifies states the behaviour this change reverses, in
so many words: `prove-plan-on-real-machines/specs/planner/plan-artifact/spec.md:15-17` says a
machine that declares no address "SHALL yield that value without an address field", and its
scenario `A machine with no address` says an implementation reading one "SHALL produce a row naming
the entry and the machine". Both are true today and both are the defect: the row only appears where
the module guarded the read itself, and where it did not the evaluation ends with no table at all.
That file is accountable in `tests/unit/coverage.nix:126`, so the reversal is written here rather
than left as a test quietly rewritten against a standing requirement.

The heading and the three scenario headings are kept, so each keeps the test it names.
`A machine's address is an input to the keys of the entries on it` is untouched: the address is
still in the target and the target is still hashed.
-->

## MODIFIED Requirements

### Requirement: An implementation is handed the machine it was planned for

An implementation SHALL receive the machine a placement was planned for as one value carrying every
fact the planner has about it that a unit may be rendered from: what it is built for, what runs its
units, and the address it is reached at. All three SHALL be present, because a value carrying a
subset of them cannot be read safely: selecting an absent attribute is a failure the planner cannot
catch and cannot report, so an implementation that reads the address of a machine that declares none
would end the whole evaluation rather than earn a row. A machine that declares no address SHALL
therefore have no entry to hand a value to, and the planner SHALL report that machine against the
registry file instead.

An implementation SHALL NOT have to test for the presence of any of the three, and a deployment
SHALL NOT have to restate the address in settings for a service to publish its own endpoint.

#### Scenario: A service publishes its own endpoint

- **WHEN** a service is placed on a machine whose record carries an address, and its
  implementation renders that address into an export or a unit
- **THEN** the value it renders SHALL equal the address the plan records for that machine
- **AND** the deployment SHALL have declared the address exactly once, in the machine registry

#### Scenario: A machine with no address

- **WHEN** a service is placed on a machine whose record declares no address, and its implementation
  reads that address with no test for its presence
- **THEN** the planner SHALL produce the registry's own row naming the machine and the file that
  declares it
- **AND** no entry SHALL be planned for that machine, so nothing forces the implementation
- **AND** the table SHALL carry no row about the module

#### Scenario: The address a consumer reads is the producer's, not its own

- **WHEN** a consuming service reads an endpoint from a wire whose far end is on another machine
- **THEN** the address in the value it reads SHALL be the producing machine's address
