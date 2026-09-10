<!--
A delta against `planner/plan-artifact`, which lives in the unarchived `implement-minimal-typed-edge`
change and is already modified by `emit-systemd-portable-service-images`,
`prove-plan-on-real-machines` and `deliver-secrets-across-machines`. Nothing existing changes. What
is added is where a generated value's program lands in the entry, and why the scan that holds every
other store path in the plan to a declared closure must not hold that one.
-->

## ADDED Requirements

### Requirement: A generated value's program is carried and is not fetched by a machine

A generated value's entry SHALL record the program its generator declared, so that a reader of the
plan alone can run it. The record SHALL be the store path as a literal string, and SHALL be
distinguishable from a value that declared none.

The program SHALL NOT be a closure root of any entry, and its presence in an entry SHALL NOT be a
mention the closure scan holds against a declared closure. A closure is what a machine is given, and
a generator runs where the plan is read: on the machine that holds the values, never on the machine
that receives them. Making the program a closure root would send every deployment's generators to
every machine that receives one of their outputs.

#### Scenario: The program is in the entry

- **WHEN** a generator declaring a program is planned
- **THEN** its value's entry SHALL record that path
- **AND** an entry whose generator declared none SHALL record its absence rather than a path

#### Scenario: The program is mentioned without entering a closure

- **WHEN** the plan is scanned for store paths mentioned without being declared as closure roots
- **THEN** a generator's program SHALL produce no row
- **AND** it SHALL appear in no entry's closure

#### Scenario: A machine is given no generator

- **WHEN** every closure of a plan whose generators declare programs is read
- **THEN** none of them SHALL name a generator's program

### Requirement: Every file record says whether bytes arrive at its path

Every generated file the plan records SHALL say whether any machine receives it, on the record of
the file itself and not only on the value's own entry. A realiser reads one entry, and whether bytes
arrive at a path is what decides whether that path may be shown to a unit at all.

The path SHALL be recorded either way. A value nobody receives still has the path it would be read
at, which is what lets a site that opens it be reported as a row rather than silently accepted.

#### Scenario: A file record carries its delivery

- **WHEN** an entry holding a generated file is read
- **THEN** the file's record SHALL state whether it is deployed
- **AND** the record SHALL carry the path whether it is deployed or not
