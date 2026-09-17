<!--
A delta against `openspec/specs/planner/secret-delivery/spec.md`. Every requirement below is ADDED:
nothing this change does contradicts a requirement of that spec, because the library keeps deriving
exactly the paths, delivery sets and records it derives today and gains one derivation and one
warning beside them.

The conditions:

- `lib/util.nix:334` is `varsRoot = "/run/vars"`, the one home of the root a value lands under, and
  `lib/resolve.nix:1591` spends it as `"${util.varsRoot}/${iname}/${gen}/${fname}"`. `/run` is a
  tmpfs, so a reboot empties it. There is no second path.
- `lib/util.nix:341-349` is the other consumer of that root: `varsPathsIn` recognises a generated
  value's path inside any string by its shape, root plus three components of
  `[^/[:space:]"]+`, and `varsPathsDeep` walks a record with it. It is what
  `vars-path-off-delivery-set` (`lib/plan.nix:672`) and `vars-not-deployed-opened` are built on. A
  sealed copy placed under `varsRoot` would be matched by it, and a mention of the sealed path would
  start earning those rows, so the second root is stated beside the first and outside its reach.
  That is the first requirement below.
- `lib/plan.nix:114-127` is `fileRecord` and `lib/plan.nix:148` is
  `fileKeyInput = withoutDefaults ownershipDefaults (fileRecord file)`: the whole file record enters
  the value entry's key input except ownership fields sitting at their defaults. A `sealed` field
  added to that record would therefore re-key every generated value in every deployment. The value
  entry's own key input is `lib/plan.nix:1275-1283`. `varsState` is keyed by the value's entry
  (`lib/plan.nix:1296-1323`), not by machine. That is the second requirement.
- The identity the seal is made to is the machine's declared `sealRecipient`, this change's own
  registry key (the machine-platform delta beside this one): read in the third projection of the
  machine reading beside `reserves` (`lib/resolve.nix:617-619`), out of `machineRecords`
  (`lib/resolve.nix:576-593`) and out of `targetOf` (`:599-613`), recorded on the `machine:<name>`
  plan record beside `address` (`lib/plan.nix:1404-1419`) and therefore outside `machineKey`
  (`lib/plan.nix:31`, applied at `:1342`). The second requirement's rotation scenario is what pins
  that: a rotated recipient must move no key.
- The warning of the third requirement is produced where the delivery set is built, because the
  delivery set is the fact it is about: the machines the owning member is placed on plus the machine
  of every entry that declares a read of the value.
-->

## ADDED Requirements

### Requirement: A delivered value has a persistent path derived beside its runtime path

For every generated file the planner records a path for, the library SHALL derive a second path, at
which a copy of that file may be kept across a reboot. The persistent path SHALL be a function of
the runtime path and of nothing else: no deployment SHALL state it, no declaration SHALL influence
it, and two evaluations of one deployment SHALL derive the same one.

The root of the persistent path and the root of the runtime path SHALL be stated in one place, so
that a reader sees both and a change to either is made once. The persistent root SHALL lie outside
the runtime root, because the runtime root is also read by the scan that recognises a generated
value's path inside an arbitrary string: a persistent path the scan matched would be reported as a
mention of a value, and the rows about a path named off a value's delivery set or on an undeployed
value would begin to fire on a copy no module named.

The persistent root SHALL be a location a service manager does not clear across a reboot, and the
library SHALL state that requirement rather than leave it to a realiser or to the command.

#### Scenario: A persistent path is derived from the value's own path

- **WHEN** the planner records a generated file's runtime path
- **THEN** the library SHALL answer one persistent path for it, derived from that runtime path
- **AND** two evaluations of the same deployment SHALL answer the same path

#### Scenario: A persistent path is not a value path to the scan that recognises one

- **WHEN** the path recogniser is given a string carrying a persistent path
- **THEN** it SHALL recognise no generated value path in it
- **AND** a unit or configuration file naming a persistent path SHALL earn neither the row for a
  path named off a value's delivery set nor the row for opening an undeployed value

### Requirement: Keeping a value across a reboot moves no key the plan derives

A value that is additionally kept at a persistent path SHALL be the same value. The persistent path
and the fact that a copy is kept SHALL enter no plan record, no entry's key input and no value
entry's key. The recipient a copy is kept for SHALL be recorded once, on the machine's own plan
record, outside every key, the way the address is - and as an explicit absence where none is
declared, so that a reader can tell a machine that seals nothing from a record written before the
field existed.

A value's delivery set SHALL be what the owner's placements and the declared reads make it, as it is
today: keeping a copy on a machine SHALL add no machine to it and remove none from it.

The answer about whether a value exists SHALL remain one answer per value entry rather than one per
machine, so that a machine holding an openable copy and a machine holding none are not two states of
one value.

Where the recipient a copy is kept for is rotated, no key SHALL move: not the value entry's, not the
key of any entry placed on that machine. A value kept for a new recipient is the same value, and
re-keying it would ask for a regeneration of bytes that are still correct and a redelivery of every
entry on the machine.

#### Scenario: A plan is unchanged by the derivation of a persistent path

- **WHEN** a deployment that delivers values is planned
- **THEN** no record of the plan SHALL carry a persistent path or a marker that a copy is kept
- **AND** every entry key and every value entry key SHALL be what it is before this change

#### Scenario: A rotated identity re-keys nothing

- **WHEN** a machine's stated seal recipient is replaced and the deployment is planned again
- **THEN** the key of every value entry delivered to that machine SHALL be unchanged
- **AND** the key of every entry placed on that machine SHALL be unchanged

### Requirement: A delivery-set machine stating no recipient is a warning

Where a generated value's delivery set names a machine whose registry record states no seal
recipient, the planner SHALL produce a warning row with the machine as its subject, naming the
values delivered there - one row per machine, however many values reach it, because the same fact
produced twice is one row. The row SHALL be produced where the delivery set is built, because the
delivery set is the fact it is about.

The row SHALL be a warning and not an error: the deployment is realisable and the delivery works;
what the machine lacks is only the ability to recover its values by itself, which is a property no
deployment had before this change.

#### Scenario: A machine in a delivery set states no recipient

- **WHEN** a value's delivery set names a machine whose registry record states no seal recipient
- **THEN** the planner SHALL produce one warning row whose subject is that machine, naming the
  value
- **AND** the deployment SHALL remain applicable

#### Scenario: One machine with two values earns one row

- **WHEN** two values are delivered to one machine stating no recipient
- **THEN** the table SHALL carry exactly one such row for that machine
- **AND** the row SHALL name both values
