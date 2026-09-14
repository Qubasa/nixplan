<!--
A delta against `planner/plan-artifact`, whose base text lives in the unarchived changes
`implement-minimal-typed-edge`, `prove-plan-on-real-machines`, `emit-systemd-portable-service-images`,
`deliver-secrets-across-machines`, `deliver-a-secret-without-exposing-it`,
`generate-values-with-nixos-secrets`, `identify-interfaces-by-declared-id`,
`report-every-refusal-as-a-row`, `declare-service-state`, `cut-a-member-and-wire-its-place`,
`hold-every-stated-guarantee` and `refuse-two-entries-claiming-one-host-resource`.
`openspec/specs/` is empty in this repository, so the base text is read from those changes.

Both requirements below are ADDED. `An entry's key is a hash of everything that affects it`
(`implement-minimal-typed-edge`) is unchanged and is what the second requirement holds the claim to:
the claim gains a field and the key input does not, which is a statement about the key rather than a
change to it.
-->

## ADDED Requirements

### Requirement: A port claim is a port number, a protocol and the address it binds

A port claim SHALL declare a number, MAY declare the protocol it listens on, and MAY declare the
address it binds. It SHALL declare nothing else, and a key outside those three SHALL be refused as
an unknown key the way every other unread key of a declaration is, so that a word that reads as a
guarantee cannot be carried without one.

The number SHALL be a port: an integer of 1 to 65535. A value that is not SHALL be a row and the
claim SHALL NOT be recorded, so that no later reading compares a value the vocabulary refused and
none repairs one. A number written as text SHALL NOT be read as the number it spells.

The protocol, where stated, SHALL be one of a named domain the row that refuses a value outside it
quotes. Where it is not stated, the claim SHALL be read as claiming the number on every protocol of
that domain, so that a claim which says less is compared against more rather than against nothing.

The address, where stated, SHALL be the single address the listener binds. Where it is not stated,
the claim SHALL be read as binding every address of its machine. The absence SHALL be the only
spelling of that reading, so a claim cannot state the wildcard twice over.

A protocol or an address the vocabulary refuses SHALL leave the number recorded and SHALL be read as
though the field had not been stated, because a refusal must not make the planner compare less than
it did.

#### Scenario: A port number written as a string

- **WHEN** a module claims a port whose number is the text of a number rather than a number
- **THEN** the planner SHALL emit an error row naming the claim and what a port is
- **AND** the entry SHALL record no allocation for that claim
- **AND** no second claim of the same number on the same machine SHALL be reported as colliding with
  it, there being no claim to collide with

#### Scenario: A port number outside the range

- **WHEN** a module claims a port whose number is zero, negative or above 65535
- **THEN** the planner SHALL emit an error row naming the claim and the range
- **AND** the entry SHALL record no allocation for that claim

#### Scenario: A port claim declaring count

- **WHEN** a module writes a port claim carrying a key the claim vocabulary does not read
- **THEN** the planner SHALL emit an error row naming the key and listing the keys a claim declares
- **AND** the deployment SHALL be inapplicable

#### Scenario: A claim whose protocol is refused keeps its number

- **WHEN** a module claims a port with a protocol outside the domain
- **THEN** the entry SHALL still record the number
- **AND** the recorded claim SHALL carry no protocol

### Requirement: An entry records a port claim's number and nothing else

An entry SHALL record the number of each claim it makes and SHALL record neither the protocol nor
the address. The protocol and the address SHALL be read from the declaration where the planner
compares claims, and SHALL NOT be inputs to the entry's key, so that a claim that adopts an address
moves no key, no record and no golden byte of a deployment that already plans.

An address a deployment varies SHALL still re-key the entries it varies, because the value reaches
the claim through the member's resolved settings and those are already an input to the key. The
planner SHALL NOT hand the address back to the implementation: a module that states one stated it
out of what it was already handed.

#### Scenario: The entry records the number alone

- **WHEN** an entry claims a port stating both a protocol and an address
- **THEN** the entry's allocation record SHALL carry the number
- **AND** it SHALL carry no protocol and no address

#### Scenario: A claim that states an address keys as it did

- **WHEN** a claim that stated no address is given one that its machine already answers on
- **THEN** the entry's key SHALL be the key it was before the address existed

#### Scenario: An address a deployment moves re-keys through settings

- **WHEN** a deployment changes the setting a module builds its claimed address from
- **THEN** the entry's key SHALL change
- **AND** the entries that read nothing from that member SHALL keep their keys
