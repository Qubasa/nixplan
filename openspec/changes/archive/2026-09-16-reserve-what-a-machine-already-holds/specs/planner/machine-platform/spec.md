<!--
A delta against `planner/machine-platform`, whose base text lives in the unarchived change
`emit-systemd-portable-service-images`. `openspec/specs/` is empty in this repository, so the base
text is read from there.

One requirement is MODIFIED: the registry reads a sixth key, and the sentence about a machine's key
being a function of the values it declares has to say which values, because the sixth is deliberately
outside it. Only the scenario that changes is restated; the four the base requirement carries about a
fully declared machine, a missing `system`, a missing `serviceManager` and a changed architecture are
unchanged and still hold.

The requirement about the reservation itself is ADDED. What a reservation collides with is
`planner/diagnostics`, not this capability: here it is the field, its shape, its optionality and its
absence from every key.
-->

## MODIFIED Requirements

### Requirement: A machine declares the system it runs and the service manager that runs its units

The machine registry SHALL read `address`, `tags`, `system`, `serviceManager`, an optional
microarchitecture and an optional statement of the host resources the machine already holds, and
SHALL refuse any other key with an error row naming the registry file. A selected machine that
declares no `system`, or no `serviceManager`, SHALL produce an error row naming the machine and the
registry file, because a placement on it has no derivable target. The plan SHALL still be emitted in
that case, containing the machine's entry and every entry placed on it, so that a deployment
mid-migration is diagnosable rather than unevaluable.

A machine's key SHALL be a function of the facts the plan records about the machine - what a consumer
dials, what a placement selects on, what a target is elaborated from - so that changing a machine's
architecture re-keys every entry placed on it. A statement of what the machine already holds SHALL
NOT be one of those facts and SHALL NOT enter that key, nor the key of any entry or generated value
placed on the machine: it says nothing about what is built for the machine, and re-keying an entry on
account of it would ask for a redelivery, and a generated value for a regeneration, of bytes that are
still correct.

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

## ADDED Requirements

### Requirement: A machine declares the host resources it already holds

A machine SHALL be able to state the host resources it already holds outside the deployment: at
minimum the ports it listens on, each with its protocol, and the host paths it owns. The statement
SHALL be optional, and its absence SHALL mean that nothing is stated and nothing is checked, so that
a registry written before the field existed keeps producing the plan and the table it produced. A
machine stating an empty set of resources SHALL produce exactly what a machine stating none produces:
a machine that holds nothing and a machine that says nothing are checked alike, and because no plan
field records the statement no reader can tell the two apart.

A stated resource SHALL be read with the tolerance the deployment's own half is read with: a value of
the wrong kind SHALL be a row naming the machine and the registry file, and the rest of the
deployment SHALL still be read. A port SHALL be stated as a protocol and a number, read the way a
module's own port claim is read, so that there is one protocol domain and not two.

The statement SHALL be a declaration and never a probe. The planner SHALL NOT read the machine, open
a connection to it, or infer a reservation from anything it did not declare, so that a plan is a
function of the deployment's text and of nothing about the host the evaluation runs on. A reservation
the planner discovered for itself SHALL remain out of scope until the excluded lifecycle construct
lands, that being the construct for a value that is not knowable at evaluation.

No realiser SHALL read the statement. It SHALL open no port, render no socket unit, create no file
and appear in no artifact: the plan records it nowhere, and what it changes is only which diagnostics
the planner produces.

#### Scenario: A machine reserves a port and a host path

- **WHEN** a machine declares that it already holds a port with a protocol and a host path, and no
  placed entry claims either
- **THEN** the planner SHALL emit no row about the machine's declaration
- **AND** the plan SHALL record the machine, the entries placed on it and the reservation nowhere

#### Scenario: A machine states no reservation

- **WHEN** a registry declares machines and none of them states the resources it holds
- **THEN** the plan SHALL be the plan that registry produced before the field existed, field for
  field
- **AND** the diagnostics table SHALL be unchanged

#### Scenario: A reservation of the wrong shape

- **WHEN** a machine states the resources it holds as a value of the wrong kind
- **THEN** the planner SHALL emit an error row naming the machine, the field and the kind the reading
  needs
- **AND** every other machine of the registry and every entry placed on this one SHALL still be read

#### Scenario: A reservation is a declaration and not a probe

- **WHEN** two otherwise identical deployments reserve two different host paths, one that exists on
  the evaluating host and one that does not
- **THEN** both SHALL produce the same rows about the reservation, namely none
- **AND** neither evaluation SHALL depend on anything outside the deployment's own declarations
