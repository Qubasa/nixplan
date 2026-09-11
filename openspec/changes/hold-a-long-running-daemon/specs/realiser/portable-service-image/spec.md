<!--
A delta against `realiser/portable-service-image`, whose base text lives in the unarchived changes
`emit-systemd-portable-service-images`, `deliver-secrets-across-machines`,
`report-every-refusal-as-a-row`, `generate-values-with-nixos-secrets`, `declare-service-state`,
`deliver-a-secret-without-exposing-it` and `hold-every-stated-guarantee`. `openspec/specs/` is empty
in this repository, so the base text is read from those changes.

Every requirement below is ADDED. The rendering requirements those changes state - one `.service`
per unit, a `.timer` for a scheduled one, the empty mount point at every shown host path, the
profile denial table - are unchanged. What this delta adds is two directives and the rule that a
configuration file whose bytes are already a store path is shown from that path rather than from the
staging directory.

The conditions: `image/read.nix:484-529` renders no `Restart=`; `image/read.nix:217-225` gives every
configuration file `from = f.staged` whatever its disposition, and `image/default.nix:169` stages
every one of them.
-->

## ADDED Requirements

### Requirement: A restart policy a unit declared is rendered, and one it did not is absent

Where a unit records `restart`, the rendered unit file SHALL carry the service manager's own restart
directive with the policy the plan recorded, and where it records `restartSec`, the rendered file
SHALL carry the delay directive. A unit that recorded neither SHALL produce a unit file carrying
neither, so that a unit asking for nothing keeps the service manager's default rather than being
pinned to this realiser's opinion of one.

The mapping SHALL be stated in the same table the extension directives are stated in, so that a
field the plan can carry and this realiser cannot render fails the build the way an unknown extension
field does rather than being silently dropped.

#### Scenario: A unit that is restarted on failure

- **WHEN** an entry's unit records `restart = "on-failure"` and a `restartSec`
- **THEN** the rendered unit file SHALL carry both directives with those values
- **AND** the image's version digest SHALL differ from the same entry's digest without them

#### Scenario: A unit that declared no policy

- **WHEN** an entry's unit records neither `restart` nor `restartSec`
- **THEN** the rendered unit file SHALL carry neither directive
- **AND** the rendered bytes SHALL be unchanged from what this realiser produced before the fields
  existed

### Requirement: A configuration file whose bytes are a store path is shown from that path

A configuration file recorded as a `source` store path SHALL be shown to the entry from that store
path, and a configuration file recorded as a `render` list of nothing but `text` items SHALL be
assembled at build time into a store path and shown from that. Neither SHALL be staged on the
machine, and neither SHALL be assembled by the attach step.

A configuration file whose `render` list carries a `ref` SHALL continue to be staged and assembled
on the machine, because its bytes name a path the machine holds. The assembly of such a file SHALL
keep the guarantees it already has: the file is created at its declared mode before its first byte is
written, and the mode SHALL NOT depend on the attaching login's umask.

The image SHALL still carry an empty file at every host path it is shown, whatever the source of the
bytes, because the image root is read-only and a missing mount point is a unit that cannot start.

#### Scenario: A file copied from a store path is not staged

- **WHEN** an entry records a configuration file as a `source` store path
- **THEN** the entry SHALL be shown that store path as the source of the bind
- **AND** the attach step SHALL assemble nothing for that file
- **AND** the store path SHALL be part of the entry's closure

#### Scenario: A file assembled from literals is assembled at build time

- **WHEN** an entry records a configuration file whose `render` list holds `text` items only
- **THEN** the realiser SHALL assemble those literals into a store path at build time
- **AND** the entry SHALL be shown that path
- **AND** the attach step SHALL assemble nothing for that file

#### Scenario: A file referencing a delivered path is still assembled on the machine

- **WHEN** an entry records a configuration file whose `render` list carries a `ref`
- **THEN** the attach step SHALL assemble it on the machine at its declared mode
- **AND** the file SHALL never exist at a mode wider than the declared one
- **AND** the image SHALL carry an empty file at the host path it is shown

### Requirement: An extension field this realiser cannot render is refused with the row that reports it

Where an entry records an extension field this realiser has no rendering for, the refusal SHALL name
the entry, the unit, the field and the backend, and SHALL carry the identifier of the diagnostic row
that reports the same condition. No refusal of this reading SHALL account for itself as having no row
above it while a deployment the planner calls applicable can reach it.

#### Scenario: A field the directive table does not carry

- **WHEN** an entry's unit records an extension field this realiser's directive table does not carry
- **THEN** the realiser SHALL refuse naming the entry, the unit, the field and the backend
- **AND** the refusal SHALL carry the identifier of the row that reports the condition
- **AND** no deployment the planner calls applicable SHALL reach that refusal without the row having
  been produced
