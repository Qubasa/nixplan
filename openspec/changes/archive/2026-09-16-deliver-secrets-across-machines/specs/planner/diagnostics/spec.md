<!--
A delta against `planner/diagnostics`, which lives in the unarchived `implement-minimal-typed-edge`
change. One scenario changes: reading a secret export is no longer a mistake, so the deployment that
carries five simultaneous mistakes carries a different fifth one. Publishing a secret as a value
takes its place, because that is the mistake the read used to stand in for - a secret in the plan as
content rather than as a path.
-->

## MODIFIED Requirements

### Requirement: No evaluation path raises

Forcing the whole result, including every plan entry, every export value and every diagnostic
record, SHALL NOT raise. The library SHALL NOT call any Nix builtin whose failure mode is to raise
in place of returning a value, and SHALL use the type library's verification entry point rather than
its assertion entry point.

#### Scenario: Every authoring mistake at once

- **WHEN** a deployment carries an unwired slot, a secret published as a value, a keyset violation,
  an arity violation and an interface mismatch simultaneously
- **THEN** deeply forcing the result SHALL succeed
- **AND** the diagnostics table SHALL contain one row per mistake

#### Scenario: A raising helper is introduced

- **WHEN** any library source file calls the type library's assertion entry point or a raise builtin
- **THEN** the test suite SHALL fail
- **AND** the failure SHALL name the file and the call

#### Scenario: A module's own code raises a catchable error

- **WHEN** a module under evaluation raises a catchable error inside its receiving half
- **THEN** the planner SHALL record an error row naming that module
- **AND** the rest of the plan SHALL still be produced

#### Scenario: A module's own code raises an uncatchable error

- **WHEN** a module under evaluation fails in a way the interpreter does not let a caller catch
- **THEN** the failure MAY propagate
- **AND** the library SHALL document which failures fall into this class rather than claiming to contain them
