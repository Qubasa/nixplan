<!--
`openspec/specs/` is empty: `planner/plan-artifact` exists only in the unarchived
`implement-minimal-typed-edge` change, so this delta is written against that change's text, the
same way `unify-declaration-and-implementation-readings` writes against `planner/typed-edge`.
-->

## MODIFIED Requirements

### Requirement: Values are recorded on the plane their use site implies

A value a unit reads through its environment SHALL be recorded in that unit's hashed environment, and additionally in the entry's environment when every unit of the entry agrees on it. A value rendered into a file the service reads at runtime SHALL be recorded as configuration data with the file mode, the units that reload when it changes, and either the store path holding the rendered file or the ordered recipe from which the machine assembles it. A value interpolated into a store path SHALL be part of the entry's closure, and the closure SHALL be the roots the module declared rather than the roots a scan inferred.

The plan SHALL name bytes rather than carry them. A digest SHALL be recorded only over material the plan itself holds: a file assembled from public literals alone SHALL carry a content hash over those literals, a file whose recipe carries any reference SHALL carry a hash over the recipe's fragments and reference paths and no digest over assembled bytes, and a file named by a store path SHALL be identified by that path.

#### Scenario: A file changes and a unit reloads

- **WHEN** the content of a rendered configuration file changes and nothing else does
- **THEN** the entry SHALL record the new file identity and the units the module named for reloading
- **AND** the entry's closure SHALL be unchanged

#### Scenario: An environment value changes

- **WHEN** a value a unit reads from its environment changes
- **THEN** the entry's key SHALL change
- **AND** the entry's closure SHALL be unchanged

#### Scenario: Two units read different values for one variable

- **WHEN** two units of one entry are handed different values for one environment variable
- **THEN** each unit SHALL record its own value
- **AND** the entry's environment SHALL NOT record that variable
- **AND** the planner SHALL emit no row

#### Scenario: A file whose recipe names a secret

- **WHEN** a configuration file's recipe interpolates the path of a value declared secret
- **THEN** the entry SHALL record the recipe with that path as a reference
- **AND** SHALL record a hash over the recipe's fragments and reference paths
- **AND** SHALL record no digest over the file's assembled bytes

#### Scenario: A store path only a configuration file names

- **WHEN** a package is named by a configuration file's recipe and by no command and no environment value
- **THEN** the module SHALL be required to declare it among the entry's closure roots
- **AND** an undeclared mention SHALL be an error row naming the entry, the path and where it was mentioned
