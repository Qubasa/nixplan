<!--
A delta against `realiser/portable-service-image`, which lives in the unarchived
`emit-systemd-portable-service-images` change and is already modified by
`declare-service-state` and `deliver-secrets-across-machines`. Only what the reading may show a
unit changes: until now every generated file of an entry became a host path, including a value no
machine receives, and the unit then failed at `226/NAMESPACE` naming neither the value nor the
declaration. The plan field this reads is added in this change's `planner/plan-artifact` delta.
-->

## ADDED Requirements

### Requirement: A path is shown only where bytes arrive at it

The reading SHALL show a host path for a generated file only where the plan records that the file is
deployed. A value no machine receives has no bytes at its path, so mounting it would mount nothing:
the service manager refuses the namespace and the unit fails with neither the value nor the
declaration named.

An entry that owns such a value SHALL still be readable, and every other path it is shown SHALL be
unaffected. The undeployed file's path SHALL remain in the plan, because a site that opens it is a
row the planner reports.

#### Scenario: An undeployed value is shown at no path

- **WHEN** an entry owning both a deployed and an undeployed generated value is read
- **THEN** the entry SHALL be shown the deployed file's path
- **AND** it SHALL be shown no path for the undeployed one
- **AND** the plan SHALL still record the undeployed file's path
