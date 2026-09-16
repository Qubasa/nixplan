<!--
A delta against `openspec/specs/planner/machine-platform/spec.md`, which owns what a machine
declares about itself and the form the plan records it in. The base text is there and this file
restates only the blocks that change.

`A machine declares the system it runs and the service manager that runs its units` is MODIFIED
twice, in the same two places the reservation statement touched it: the key list a registry record
may carry, and the paragraph saying which of those facts a machine's key is a function of. The
block below is that requirement copied whole with the identity folded into both.

`A machine states the identity it presents` is ADDED: the field, the grammar it is held to, the
projection it is read in, and what the plan records.

Nothing else moves. `The plan records a reduced elaboration of a platform, never a raw one`, `An
entry records the target it was planned for`, `An implementation is handed a target carrying every
field a module may render` and `A placement onto a machine whose target is incomplete is not
planned` are unchanged and not restated: an identity is not a fact a module renders from, so it is
in no target and no implementation is handed it.

The conditions. `lib/resolve.nix:52-59` lists the six keys a record may carry and none is an
identity, so a deployment cannot state which machine an address means.
`lib/resolve.nix:459-466` reads each key with its shape; `:576-593` is the record the plan keys,
`:599-613` is the target an entry is planned for, and `:617-619` is the third projection, which the
reservation statement already uses and no key reads. `lib/plan.nix:31` is `machineKey` and `:1342`
applies it to `resolved.machines`, which is `:576-593`; every placed entry and every per-placement
generated value depends on that key through its own `dependsOn`, which is why the identity is read
in the third projection and not in the first. `lib/plan.nix:1404-1419` is the `machine:<name>`
record, where `address` is carried unconditionally and the optional group is pruned of nulls.
`lib/util.nix:111-115,129-177` is the one home of the grammars a name, a rendered word, a bound
path and an environment variable name are held to, and `lib/atoms.nix:127-129,134` is where an atom
of this kind is written.

The severity of `machine-host-key-malformed` is an error for the reason `address = 22` is: a value
the reading refused is not the value the declaration wrote, and a line no `known_hosts` file can
carry is a statement about no machine.
-->

## ADDED Requirements

### Requirement: A machine states the identity its host presents

A machine registry record SHALL be able to state the identity its host presents, as one public key
line: the algorithm, the key, and an optional comment. The statement SHALL be optional, as the
address already is, because a deployment whose machines are addressed and identified late is still a
deployment worth building, and because every deployment written before the field existed states
none.

The line SHALL be held to the grammar a single entry of a host-identity file can carry. A value
carrying a line break SHALL be refused, because a file of one entry per line would gain a second
entry naming whatever followed the break. A value carrying any other control character SHALL be
refused for the same reason. A value whose algorithm, key or optional comment is outside that
grammar SHALL be refused. Every refusal SHALL be one error row naming the machine, the field and
what the grammar admits, and SHALL leave the rest of the registry and every entry placed on that
machine read.

A refused line SHALL be recorded nowhere: the plan SHALL carry the machine as one that states no
identity, so that no consumer of the plan is ever handed a line it cannot write into a
host-identity file. A machine whose stated line is refused SHALL therefore earn both the refusal and
every row a machine stating no identity earns, the way a machine whose address is a value of another
kind earns both the malformed declaration and the incomplete target.

The plan SHALL record the stated identity in the machine's own record, beside the address, as an
explicit absence where none was stated or where the statement was refused. A reader SHALL NOT be
able to mistake the field for a plan that does not carry it.

The identity SHALL NOT be one of the facts any key of the plan is a function of, and the requirement
above states that. It SHALL reach a consumer of a build the way the address does and SHALL reach no
placed entry, no generated value and no artifact.

#### Scenario: A machine states the key its host presents

- **WHEN** the registry declares a machine stating the public key line its host presents, and a
  placement selects it
- **THEN** the planner SHALL emit no row about the statement
- **AND** the machine's own plan record SHALL carry that line beside its address

#### Scenario: A machine states no host key

- **WHEN** the registry declares a machine stating no identity
- **THEN** the planner SHALL emit no row about the field
- **AND** the machine's own plan record SHALL carry the field as an explicit absence rather than
  omit it

#### Scenario: A host key carrying a line break

- **WHEN** a machine states an identity whose line carries a line break, whatever else it carries
- **THEN** the planner SHALL emit one error row naming the machine, the field and what the grammar
  admits
- **AND** the machine's plan record SHALL carry the field as an explicit absence
- **AND** every other machine of the registry and every entry placed on this one SHALL still be
  read

#### Scenario: A host key outside the grammar an identity line carries

- **WHEN** a machine states an identity that is a value of another kind, or a line whose algorithm,
  key or comment the grammar refuses
- **THEN** the planner SHALL emit one error row naming the machine, the field and what the grammar
  admits
- **AND** the plan SHALL contain the machine's record and the entries placed on it

#### Scenario: Rotating a host key moves no key of the plan

- **WHEN** a machine's stated identity is added, changed or removed and nothing else changes
- **THEN** the machine's key SHALL be the key it had
- **AND** every entry placed on that machine SHALL keep its key
- **AND** every generated value delivered to that machine SHALL keep its key
- **AND** the machine's own record SHALL be the only record of the plan whose content differs

## MODIFIED Requirements

### Requirement: A machine declares the system it runs and the service manager that runs its units

The machine registry SHALL read `address`, `tags`, `system`, `serviceManager`, an optional
microarchitecture, an optional statement of the host resources the machine already holds and an
optional statement of the identity its host presents, and SHALL refuse any other key with an error
row naming the registry file. A selected machine that
declares no `system`, or no `serviceManager`, SHALL produce an error row naming the machine and the
registry file, because a placement on it has no derivable target. The plan SHALL still be emitted in
that case, containing the machine's entry and every entry placed on it, so that a deployment
mid-migration is diagnosable rather than unevaluable.

A machine's key SHALL be a function of the facts the plan records about the machine - what a consumer
dials, what a placement selects on, what a target is elaborated from - so that changing a machine's
architecture re-keys every entry placed on it. Neither a statement of what the machine already holds
nor the identity its host presents SHALL be one of those facts, and neither SHALL enter that key,
nor the key of any entry or generated value
placed on the machine: neither says anything about what is built for the machine, and re-keying an
entry on
account of either would ask for a redelivery, and a generated value for a regeneration, of bytes that
are still correct.

#### Scenario: A machine that reserves a port keys as it did

- **WHEN** a machine's declaration gains a statement of the resources it already holds and nothing
  else changes
- **THEN** the machine's key SHALL be the key it had
- **AND** every entry placed on that machine SHALL keep its key
- **AND** every generated value delivered to that machine SHALL keep its key

#### Scenario: A fully declared machine

- **WHEN** the registry declares a machine with an `address`, a `tags` entry, a `system` and a
  `serviceManager`
- **THEN** the planner SHALL emit no registry row
- **AND** the machine's plan entry SHALL record all four values

#### Scenario: A machine omits its address

- **WHEN** the registry declares a machine with no `address` and a placement selects it
- **THEN** the planner SHALL emit one error row naming the machine, the address as the key it did
  not declare, and the registry file
- **AND** the plan SHALL contain the machine's own record and no entry placed on it

#### Scenario: A machine omits its system

- **WHEN** the registry declares a machine with no `system` and a placement selects it
- **THEN** the planner SHALL emit an error row naming the machine and the registry file
- **AND** the plan SHALL contain the machine's own record and no entry placed on it

#### Scenario: A machine omits its service manager

- **WHEN** the registry declares a machine with no `serviceManager` and a placement selects it
- **THEN** the planner SHALL emit an error row naming the machine and the registry file
- **AND** the plan SHALL contain the machine's own record and no entry placed on it

#### Scenario: A machine declares an address that is not a name

- **WHEN** the registry declares an `address` as a value of some other kind and a placement selects
  that machine
- **THEN** the planner SHALL emit the row about the malformed declaration and the row about the
  incomplete target
- **AND** no entry SHALL be planned for that machine

#### Scenario: A machine changes architecture

- **WHEN** a machine's declared `system` changes and nothing else does
- **THEN** the machine's key SHALL change
- **AND** every entry placed on that machine SHALL be re-keyed
