# planner/secret-delivery Specification

## Purpose
TBD - created by archiving change deliver-secrets-across-machines. Update Purpose after archive.

## Requirements

### Requirement: A generated value declares how many of it exist

`vars.<generator>.per` SHALL take exactly `"instance"` and `"placement"`. An omitted `per` SHALL
mean `"placement"`. `"instance"` SHALL mean one value for the instance, independent of how many
machines the owning member is placed on; `"placement"` SHALL mean one value per machine it is placed
on. A `per` outside the domain SHALL produce an error row naming the generator, the value written
and the two values it takes.

Two members of one instance SHALL NOT declare the same generator name, because a generator is
addressed by instance and name and the two declarations would be one address for two values. The
second SHALL produce an error row naming the instance, the generator and both members.

#### Scenario: A generator states one value for the instance

- **WHEN** a member placed on three machines declares a generator with `per = "instance"`
- **THEN** the planner SHALL resolve one value for that generator
- **AND** every placement of that member SHALL read the same path for each of its files

#### Scenario: A generator states one value per placement

- **WHEN** a member placed on three machines declares a generator with `per = "placement"`
- **THEN** the planner SHALL resolve one value per placement
- **AND** each placement's value SHALL be identified by that placement's machine

#### Scenario: A cardinality outside the domain

- **WHEN** a generator declares a `per` that is neither `"instance"` nor `"placement"`
- **THEN** the planner SHALL emit an error row naming the generator, the value written and both
  admitted values
- **AND** the rest of the deployment SHALL still be planned

#### Scenario: Two members claim one generator name

- **WHEN** two members of one instance each declare a generator called `app`
- **THEN** the planner SHALL emit an error row naming the instance, the generator name and both
  members
- **AND** the row SHALL be produced once for the instance rather than once per placement

### Requirement: A generated value is delivered to the machines that need it

The planner SHALL record, for each generated value, the set of machines that receive its bytes. That
set SHALL be the machines the owning member is placed on, plus the machine of every entry that
declares a read of an export whose published value is a file of that generator. It SHALL be derived
from nothing else: not from the value, not from the interface, and not from what `impl` interpolates.

The planner SHALL also record, in a stable order, the reason each machine is in the set, naming the
entry and — for a reader — the slot and export it declared.

#### Scenario: The owner receives its own value

- **WHEN** a member declares a generator and no slot anywhere reads an export backed by it
- **THEN** the delivery set SHALL be exactly the machines that member is placed on

#### Scenario: A declared read adds the reader's machine

- **WHEN** a consumer on another machine declares a read of a secret export whose value is a file of
  that generator
- **THEN** the delivery set SHALL contain the consumer's machine as well as the owner's
- **AND** the recorded reason SHALL name the consuming entry, its slot and the export

#### Scenario: An undeclared export delivers to nobody

- **WHEN** a consumer's `uses.<slot>.reads` omits an export whose value is a file of that generator
- **THEN** the consumer's machine SHALL NOT be in that generator's delivery set
- **AND** the export SHALL be absent from the consumer's `results`, so the omission cannot be
  defaulted around

#### Scenario: A machine running neither is not in the set

- **WHEN** a third machine runs a member of neither the owning nor the reading instance
- **THEN** it SHALL NOT appear in the delivery set of either value

### Requirement: A value nobody receives is stated, not implied

`vars.<generator>.deploy` SHALL be a boolean defaulting to `true`, and SHALL decide whether any
machine receives that generator's bytes. `per` and `deploy` SHALL be independent: one value may
exist and no machine receive it.

A `deploy = false` generator's public files SHALL still carry their value in the plan, because a
value the plan holds needs no file on a machine. Anything that would open one of its files on a
machine SHALL be refused: a unit or configuration file of the owning module naming the path, and a
consumer's declared read of a secret export backed by it. Each refusal SHALL name the generator, the
file and the site that opens it.

#### Scenario: A value nobody receives

- **WHEN** a generator declares `deploy = false`
- **THEN** its delivery set SHALL be empty
- **AND** the entry SHALL record that the value exists

#### Scenario: A unit opens a value nobody receives

- **WHEN** a unit of the owning module names the path of a file of a `deploy = false` generator
- **THEN** the planner SHALL emit an error row naming the generator, the file and the unit
- **AND** the row SHALL state that the path resolves to nothing at run time

#### Scenario: A consumer reads a value nobody receives

- **WHEN** a slot's `reads` names a secret export whose value is a file of a `deploy = false`
  generator
- **THEN** the planner SHALL emit an error row naming the consuming slot, the export and the
  generator

#### Scenario: A public file of an undeployed generator still travels

- **WHEN** a `deploy = false` generator declares a public file whose bytes the planner was given,
  and the module publishes that file's value as a public export
- **THEN** the export SHALL carry the value
- **AND** no machine SHALL be in that generator's delivery set

### Requirement: A generator may read its siblings within its own cardinality

`vars.<generator>.reads` SHALL name generators of the same module. A generator SHALL be able to read
a sibling of the same or a coarser cardinality: `"placement"` may read `"instance"`, `"instance"`
may read `"instance"`, `"placement"` may read `"placement"`. A `"instance"` generator reading a
`"placement"` one SHALL produce an error row, because the placements hold one value each and the
reader is one value, so the read has no single answer. A `reads` entry naming a generator the module
does not declare SHALL produce an error row listing the generators it does declare.

#### Scenario: A machine-specific value reads a shared one

- **WHEN** a `per = "placement"` generator reads a `per = "instance"` sibling
- **THEN** the planner SHALL accept it
- **AND** each placement's entry SHALL depend on the one shared value's entry

#### Scenario: A shared value reads a machine-specific one

- **WHEN** a `per = "instance"` generator reads a `per = "placement"` sibling
- **THEN** the planner SHALL emit an error row naming both generators and both cardinalities
- **AND** the resolution SHALL state that reversing the direction is the shape that works

#### Scenario: A generator reads a sibling that is not declared

- **WHEN** a generator's `reads` names a generator the module does not declare
- **THEN** the planner SHALL emit an error row naming the generator, the name read and the
  generators the module declares

### Requirement: Delivery moves bytes the plan never holds

A delivered value SHALL be named by the plan and carried by nothing in it: for every secret file, the
plan SHALL hold the path and the delivery set and no content, on the provider's entry, on every
reader's entry and on the value's own entry.

#### Scenario: A delivered secret carries no bytes

- **WHEN** a secret is delivered to two machines and read by a consumer on one of them
- **THEN** the plan SHALL record the path, the delivery set and the reason for each machine
- **AND** the bytes the planner was given SHALL appear in no entry of the plan

### Requirement: A generated value may declare the program that produces it

A generator MAY name the program that produces its files. The declaration SHALL be a store path,
recorded as a literal string, and the planner SHALL neither run it nor read it: naming a program is
a fact about the value, exactly as its cardinality is.

A generator that names no program SHALL remain a well-formed generator, because the library
described values before anything could produce them and a deployment that never runs a generator
stays valid. A reader that needs a program and finds none SHALL refuse by name; the planner SHALL
NOT refuse on its behalf.

A declaration that is not a store path SHALL be an error row naming the generator and the value it
was given, because the one thing a consumer can do with the field is hand it to a tool that
resolves store paths.

#### Scenario: A generator names its program

- **WHEN** a generator declares a store path as its program
- **THEN** the value's entry SHALL record that path
- **AND** the planner SHALL neither realise nor read it

#### Scenario: A generator names no program

- **WHEN** a generator omits the program
- **THEN** it SHALL produce no diagnostic row
- **AND** its entry SHALL record no program, distinguishably from recording an empty one

#### Scenario: A program that is not a store path

- **WHEN** a generator declares a program that is not a store path
- **THEN** the result SHALL contain an error row naming the generator and the declared value
- **AND** the rest of the plan SHALL still be produced

### Requirement: A generated file records the ownership and mode it is delivered at

A generated file's record SHALL carry `owner`, `group` and `mode`, each optional and each defaulting
to what the delivery writes today: `root`, `root` and `0400`. A file declaring none of the three
SHALL be recorded with those values and SHALL be delivered exactly as it is delivered before this
change.

`owner` and `group` SHALL be account names rather than numeric identifiers, for the reason
`lib/atoms.nix` already gives for a unit's `user`: an identifier is the machine's answer and a name
is what a deployment can state portably. `mode` SHALL be a file mode, and a value that is not one -
a decimal integer, a three-digit string, a mode with bits outside the permission set - SHALL be an
error row naming the generator, the file and the form a mode takes.

The record SHALL be part of the value entry's key input: two values differing only in the mode they
are delivered at are two values, because the bytes on a machine differ in a way a reader can
observe.

A file's record SHALL be readable from the plan by every layer that delivers or reads one, so that no
layer has to restate the default.

#### Scenario: A file that declares nothing

- **WHEN** a generator declares a file with a `secrecy` and no ownership and no mode
- **THEN** the plan SHALL record that file as owned by `root`, grouped `root`, at mode `0400`
- **AND** the value entry's key SHALL be what it was before the record carried the three fields

#### Scenario: A file readable by an account

- **WHEN** a generator declares a file with `owner`, `group` and `mode`
- **THEN** the plan SHALL record all three on that file
- **AND** the value entry's key SHALL differ from the same value declaring the defaults

#### Scenario: A mode that is not a mode

- **WHEN** a generator declares a file whose `mode` is a decimal integer or a malformed string
- **THEN** the planner SHALL emit an error row naming the generator, the file and the form a mode
  takes
- **AND** the plan SHALL NOT record the failing value

#### Scenario: Two values differing only in mode

- **WHEN** one deployment declares a file at `0400` and another declares the same file at `0440`
- **THEN** the two value entries SHALL carry different keys
- **AND** each entry's recorded mode SHALL be its own

### Requirement: The record travels with the value to every machine that receives it

The ownership and mode a file records SHALL reach every machine in the value's delivery set, and
SHALL be the same on each: one value has one answer about who may read it, however many machines
receive it, the way it already has one answer about whether it exists.

A layer that writes a value SHALL take the ownership and mode from the record rather than from a
literal of its own, so that the deployment's statement and the bytes on every machine cannot
disagree.

#### Scenario: One value on two machines

- **WHEN** a value is delivered to two machines
- **THEN** the file SHALL carry the recorded owner, group and mode on both
- **AND** neither machine SHALL hold it at a mode the record does not state

### Requirement: A secret export is backed by a secret file

An export's declared secrecy and the secrecy of the generated file backing it SHALL be compared, and
an export declared secret backed by a file that is public SHALL be an error row naming the export,
the capability it is published under and the file. A file that declares no secrecy is public, so the
row SHALL be earned by an omission exactly as it is by a written declaration: a lattice that reported
only the written case would make the cheapest mistake the silent one.

Such an export SHALL publish nothing. It SHALL carry no content, no record holding content and
nothing derived from either, so a consumer wired to it reads an absent slot rather than the bytes,
the way every other refused read leaves its slot absent.

Where two declarations disagree about one value's secrecy, the plan SHALL carry that value at the
stricter of the two. The bytes SHALL NOT enter the plan on the strength of the weaker declaration:
the file SHALL be recorded as a path and no content, at every site of the owning entry as well as at
the export, so that a unit environment, a configuration file recipe and every key input that named
the content hold none of it. A content hash over a leaked secret is the leak in another form.

The comparison SHALL be made from the declarations and never from the bytes a generator has produced
so far, so a deployment whose value does not exist yet earns the same row as one whose value does,
and the row does not appear and disappear with the state the plan was evaluated against.

#### Scenario: A secret export may not be backed by a public file

- **WHEN** a module publishes a generated file that declares no secrecy as an export whose atom
  declares that export secret
- **THEN** the planner SHALL emit one error row naming the export and the file
- **AND** the export SHALL carry no value, and the file's bytes SHALL appear in no entry of the plan,
  in no unit's environment and in no entry's key
- **AND** the deployment SHALL NOT be applicable, and every other entry SHALL still be planned

### Requirement: An entry's own units are held to the readability comparison

The readability comparison SHALL be asked wherever the plan holds the facts it needs, which are a
file's recorded owner, group and mode beside the account and the groups a unit declares. An entry's
own generated value SHALL be one of those sites: a unit that names a file of its own entry's
generator and runs as an account the file's record does not admit SHALL be an error row naming the
entry, the unit, the account, the value, the file and the record the file states, which is what a
consumer's declared read of another entry's value already earns.

The answer SHALL NOT depend on which realiser reads the plan. A unit that cannot open a file the plan
told it to read cannot start under any realiser, so the row SHALL be produced by the layer that holds
the plan, and a confinement profile imposing an account SHALL remain a second condition about that
imposed account rather than the only report of this one. A deployment realised by a layer that
confines nothing SHALL earn the same row as one realised by a layer that does.

The comparison SHALL be one rule asked at each site rather than one copy per site, and the sites
SHALL agree about a unit that declares no account: where nothing imposes one it runs privileged, so
it admits any file and earns no row, and a unit that spells the privileged account out SHALL answer
the same way as one that declares none.

A record that admits the unit SHALL earn no row: by its owner where the unit runs as that account, by
its group where the unit declares that group, and by the mode's world bits for any account. The row
SHALL be per unit and per file, so an entry whose second unit runs privileged keeps that unit, and
the entry SHALL still be planned with the value's path recorded.

#### Scenario: A unit that cannot open its own value is a row

- **WHEN** an entry's unit declares an account and names a file of that entry's own generator whose
  record admits its owner alone
- **THEN** the planner SHALL emit an error row naming the entry, the unit, the account, the file and
  the record
- **AND** the row SHALL be produced whatever realiser the deployment states, and whether or not any
  confinement profile is involved
- **AND** the deployment SHALL NOT be applicable

#### Scenario: A value a unit's declared group admits is no row

- **WHEN** an entry's unit declares an account and a group, and names a file of that entry's own
  generator whose record grants that group read
- **THEN** the planner SHALL emit no row about readability
- **AND** the entry SHALL record the unit and the file's path as it does for a file nobody questioned
- **AND** the value's delivery set SHALL be what the owner's placements and the declared reads make
  it

### Requirement: A value's path is named only on a machine that receives it

An entry SHALL name a generated value's path only on a machine that receives the value. Where a unit
or a configuration file of a placed entry names the path of a file whose value's delivery set does
not contain that entry's machine, the planner SHALL emit an error row naming the entry, its machine,
the value, the file and the site that names the path. The path resolves to nothing there, and what
the machine reports when the unit fails to start names neither the value nor the declaration, which
is the whole reason the row exists.

The question SHALL be whether the machine receives the value, not whether the value is deployed at
all. A value no machine receives is the instance of that rule where the delivery set is empty, so
every machine is outside it and the refusal already stated for that case follows from this one rather
than standing beside it. A value that is deployed and delivered elsewhere SHALL be refused on the
same terms, however the path reached the naming entry: through the value's own record, through a read
of a reference, or through a public export carrying the path as an ordinary string.

The rule SHALL NOT widen the delivery set. A declared read of an export backed by a file SHALL remain
the only thing that puts a reader's machine in the set, and naming a path SHALL never put a machine
in it: an entry that names a path it was not delivered is told to declare the read or to stop naming
the path, and the set stays what the owner's placements and the declared reads make it. A rule that
delivered on a mention would make a routable secret bounded by nobody.

An entry on a machine the set contains SHALL earn no row, and the entry SHALL still be planned with
every path it named either way: the row, an inapplicable deployment and a realiser's own refusal are
what stop the bytes.

#### Scenario: Naming a value path on a machine outside the delivery set is a row

- **WHEN** an entry placed on one machine names in a unit the path of a generated value whose
  delivery set holds another machine only, having reached that path through a public export rather
  than through a read of the reference
- **THEN** the planner SHALL emit an error row naming the entry, its machine, the value and the file
- **AND** the value's delivery set SHALL be unchanged, holding the owner's machine alone
- **AND** the deployment SHALL NOT be applicable
