<!--
A delta against `realiser/flakelet-artifact`, whose base text lives in the unarchived changes
`emit-flakelet-service-artifacts`, `deliver-secrets-across-machines` and
`report-every-refusal-as-a-row`. `openspec/specs/` is empty in this repository, so the base text is
read from those changes.

Every requirement below is ADDED. What the artifact holds, who decides a unit is enabled, and the
name and unit rules the endpoint imposes are unchanged. What this delta changes is which host paths
the reading accepts: the rule stays "this realiser runs no step on the machine that could assemble
bytes", and the set it refuses narrows to the files whose bytes genuinely do not exist yet.

The condition: `flakelet/read.nix:125` accepts a host path only where `from == p.path`, and
`image/read.nix:221` gives every configuration file `from = f.staged`, so every `configData` file is
refused at `flakelet/read.nix:162` whatever its disposition.
-->

## ADDED Requirements

### Requirement: A host path whose bytes exist before activation is accepted

This realiser SHALL accept a host path whose bytes exist before the entry is activated, and SHALL
refuse one whose bytes would have to be assembled on the machine. It still runs no step on the
machine, so the rule is unchanged; what it is applied to is the file's disposition rather than the
file's kind.

A configuration file recorded as a `source` store path SHALL be accepted. A configuration file
recorded as a `render` list of nothing but `text` items SHALL be accepted, and the bytes SHALL be
assembled into the artifact at build time so that the path shown to the unit is a path the machine
holds once the artifact's closure has been copied. A generated file SHALL continue to be accepted,
because its bytes arrive by delivery before activation.

A configuration file whose `render` list carries a `ref` SHALL be refused, naming the entry, the host
path, and the reference whose bytes exist only on the machine. The refusal SHALL state that rule
rather than stating that the file is a configuration file, so that an author can tell which of their
files this realiser can carry.

#### Scenario: A configuration file copied from a store path

- **WHEN** an entry records a configuration file as a `source` store path
- **THEN** the reading SHALL accept the entry
- **AND** the rendered unit SHALL bind that store path at the declared host path
- **AND** the store path SHALL be reachable from the artifact, so copying the artifact copies the
  bytes

#### Scenario: A configuration file assembled from literals

- **WHEN** an entry records a configuration file whose `render` list holds `text` items only
- **THEN** the artifact SHALL carry the assembled file
- **AND** the reading SHALL accept the entry
- **AND** the rendered unit SHALL bind the artifact's own path at the declared host path

#### Scenario: A configuration file referencing a delivered path

- **WHEN** an entry records a configuration file whose `render` list carries a `ref`
- **THEN** the reading SHALL refuse naming the entry, the host path and the reference
- **AND** the refusal SHALL state that the bytes do not exist until the referenced path is written
- **AND** the planner SHALL have reported the same condition as a row

#### Scenario: A delivered generated file is still accepted

- **WHEN** an entry is shown the host path of a generated file its plan records as deployed
- **THEN** the reading SHALL accept the entry
- **AND** the acceptance SHALL rest on the bytes arriving before activation rather than on the file's
  kind

### Requirement: The artifact carries what it assembled and nothing else new

Where this realiser assembles a configuration file at build time, the artifact SHALL carry that file
beside the metadata and the unit files it already carries, and SHALL carry no other new content. An
artifact for an entry that records no such file SHALL be byte-identical to what this realiser
produced before the rule changed.

#### Scenario: An entry with no configuration file is unchanged

- **WHEN** an entry records no configuration file
- **THEN** the artifact SHALL hold exactly the metadata and the unit files
- **AND** its content SHALL be identical to what this realiser produced before this change
