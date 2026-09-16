<!--
A delta against `planner/secret-delivery`, which lives in the unarchived
`deliver-secrets-across-machines` change. Nothing existing changes. What is added is the one thing a
generated value cannot say today: which program produces its bytes. Every field of `vars.<gen>` is
about how many values exist, whether any machine receives them, and what they read; none of them
names a generator, so a plan cannot be handed to anything that would run one.
-->

## ADDED Requirements

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
