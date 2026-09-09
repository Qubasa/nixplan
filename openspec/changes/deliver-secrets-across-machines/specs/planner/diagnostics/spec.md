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
