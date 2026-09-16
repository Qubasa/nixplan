<!--
A delta against `openspec/specs/operator/deployment-build/spec.md`. Every requirement below is
ADDED. `The manifest is the whole interface to a build` (`:122`) is not restated: it says what the
record states per placed entry, and nothing about it stops being true; the requirement below adds a
second table beside the two the record already carries.

The conditions:

- `operator/read.nix:518-656` is the whole reading, total and row-producing, and
  `operator/default.nix:27-109` is the link farm over it: `plan.json`, `manifest.json`, both halves
  of the diagnostics, and one artifact per realised entry at `entries/<projected key>`. Nothing in
  the farm is addressed by a machine, and `manifest.json` carries `entries` and `values`
  (`operator/read.nix:608-628`) and no machine table.
- A value's machine need run no entry, which is why `cli/manifest.py:241-258` reads the plan's own
  `machine:<name>` record for a value's address rather than an entry's. A per-machine build artifact
  therefore cannot be addressed through the entries table.
- `operator/read.nix:469-508` indexes every unit file name the realisers derive, per machine, and
  `image/read.nix:244-253` derives them as `<instance>-<service>-<unit>.service` off
  `nameOf parts = "${parts.instance}-${parts.service}"` (`image/read.nix:208`). Every such name
  therefore carries at least two hyphens outside its components, which is what keeps a one-hyphen
  machine-scoped unit name outside the namespace an entry can spell. `design.md` D3 records the
  argument and why no row is added for a collision that cannot happen.
- The mention scan this reading orders the unsealer by is the library's own recogniser,
  `util.varsPathsDeep` (`lib/util.nix:341-349`), asked of the records the reading already walks the
  way `imageReader.hostPaths` walks them (`operator/read.nix:163`).
- `hostKey` is read with `machineRecordOf` the way the address is (`operator/read.nix:138-140`), and
  it is `name-the-machine-a-run-dials`'s field (contract C1). A line the atom refused is recorded as
  an absence, so this reading is never handed a malformed one. What it decides is narrower: whether
  the line's type is one the sealing tool accepts.
-->

## ADDED Requirements

### Requirement: A build produces the unsealer of every machine that holds a sealed value

For every machine a delivered value reaches and whose declared host identity can be sealed to, the
build SHALL produce one artifact carrying the program that opens a seal and the boot-time unit that
runs it, addressed by that machine's own name. The artifact SHALL be a function of the value file
records delivered to that machine and of the identity's type, and of nothing else: two builds of one
deployment SHALL produce the same one, and a change to one machine's values SHALL leave every other
machine's artifact unchanged.

A machine no delivered value reaches SHALL have no such artifact, whether or not it runs an entry: it
is the delivery set and never the placement that decides who holds a value.

The program SHALL arrive in the artifact's own closure rather than be expected on the machine's
`PATH`, because nothing in a plan provisions a package and a machine's own environment is not a fact
the build records.

The artifact SHALL NOT be a plan entry and SHALL be realised by no realiser: it belongs to no
instance, has no member, and the statement beside the deployment decides nothing about it. The layer
that builds a deployment SHALL build it, as it already builds the plan, the manifest and the
diagnostics.

#### Scenario: A machine that receives a value has an unsealer

- **WHEN** a deployment delivers a value to a machine whose declared host identity can be sealed to
- **THEN** the build SHALL carry one artifact for that machine, addressed by its name
- **AND** the artifact SHALL carry the unsealing program and the unit that runs it

#### Scenario: A machine that receives no value has none

- **WHEN** a machine runs entries and no delivered value names it in its delivery set
- **THEN** the build SHALL carry no artifact for that machine

#### Scenario: Two builds of one deployment produce one unsealer

- **WHEN** one deployment is built twice
- **THEN** each machine's artifact SHALL be identical between the two builds
- **AND** changing the values delivered to one machine SHALL leave the artifacts of the others
  unchanged

### Requirement: The unsealing unit runs before the units that open a value

The boot-time unit SHALL be ordered before every unit of every entry on that machine that names a
value's path, and the set of those units SHALL be read off what each entry's own record names rather
than restated: the recogniser the library already uses to find a value's path inside an arbitrary
string is what decides which entries open one, so an entry that reads a value through a declared
read and an entry that names its own generator's file are covered by one rule.

The unit's own name SHALL lie outside the namespace of unit file names a realiser can derive for an
entry, and the reading SHALL keep both, so that installing it on a machine can never replace an
entry's unit file. The disjointness SHALL be a property of the derivations rather than a row about a
collision, because a row nobody can earn is a row nobody can test.

#### Scenario: The unit is ordered before an entry that reads a value

- **WHEN** a machine holds a sealed value and runs an entry whose record names that value's path
- **THEN** the unit SHALL be ordered before every unit file that entry derives
- **AND** an entry on that machine whose record names no value's path SHALL NOT be named in the
  ordering

#### Scenario: No entry can derive the unsealing unit's file name

- **WHEN** the unit file names a realiser derives for any instance, member and unit name are
  compared with the machine-scoped unit's name
- **THEN** no derivable name SHALL equal it

### Requirement: A host identity the seal cannot be made to is a row and not a refusal

Where a machine a delivered value reaches declares a host identity of a type the sealing tool cannot
use, the reading SHALL produce a warning row naming the machine, the type it declared and the types
that can be sealed to, and the build SHALL still happen: that machine SHALL be delivered to exactly
as it is before this change and SHALL have no unsealer. The condition is a warning because the
deployment is realisable and the delivery works; what is lost is only the machine's ability to
recover by itself.

The form of the declared identity SHALL remain the registry reading's question and the type SHALL be
this reading's: the layer that seals is the layer that knows what it can seal to, and a second copy
of the type list beside the library would be a second answer.

Where a machine a delivered value reaches declares no host identity at all, this reading SHALL
produce no row of its own, because the registry reading already reports that machine as one a run
cannot authenticate, and the same fact produced twice is one row.

#### Scenario: A machine declares an identity of a type the seal cannot use

- **WHEN** a machine a value is delivered to declares a host identity whose type the sealing tool
  does not accept
- **THEN** the reading SHALL produce one warning row naming the machine, that type and the accepted
  types
- **AND** the deployment SHALL still be buildable and that machine SHALL have no unsealer

#### Scenario: A machine that declares no identity earns no second row

- **WHEN** a machine a value is delivered to declares no host identity
- **THEN** this reading SHALL produce no row about it
- **AND** that machine SHALL have no unsealer

### Requirement: The deployment record states which machines hold a sealed value

The deployment record SHALL carry a table of the machines a delivered value reaches, one record per
machine, stating whether that machine's values are sealed and, where they are, the artifact that
opens them. The table SHALL be present whether or not it holds anything, so that a reader cannot
mistake a deployment that delivers nothing for a record written before the table existed.

The record SHALL NOT restate the identity the seal is made to: the plan's own machine record carries
it, and a second copy in the build record would be a second answer a stale build could disagree
with.

The record SHALL state the version of its own shape, and the shape this table belongs to SHALL be a
new version rather than an optional addition to the old one, because a reader of the previous shape
would read a record with no table as a deployment whose machines seal nothing, which is exactly the
silent failure the table exists to prevent.

#### Scenario: The record names the machines a value reaches

- **WHEN** a deployment delivering values to two of three machines is built
- **THEN** the record's machine table SHALL carry exactly those two machines
- **AND** each record SHALL say whether that machine's values are sealed

#### Scenario: A deployment that delivers nothing carries the table anyway

- **WHEN** a deployment that delivers no value is built
- **THEN** the record SHALL carry the machine table with no entries
- **AND** SHALL NOT omit it
