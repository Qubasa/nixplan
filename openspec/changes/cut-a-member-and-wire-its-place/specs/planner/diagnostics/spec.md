<!--
A delta against `planner/diagnostics`, whose base text lives in the unarchived changes
`implement-minimal-typed-edge`, `deliver-secrets-across-machines`,
`hold-declaration-shape-and-fold-set-reads`, `report-every-refusal-as-a-row`,
`hold-every-stated-guarantee` and `deliver-a-secret-without-exposing-it`. `openspec/specs/` is empty
in this repository, so the base text is read from those changes.

Every requirement below is ADDED, and deliberately. The row contract and the refusals-by-subtraction
rule are unchanged in kind, and restating `Refusals by subtraction name the condition that would
bring the construct back` here would put a second edited copy of that block in a second unarchived
change - the reason `order-a-cycle-by-its-strong-components` gives for the same decision. What
changes is the contents of the table that requirement is read over, which the first requirement below
states.

## ADDED Requirements

### Requirement: The exclusion table no longer carries the member-cuts row

`member cuts` SHALL NOT be a row of the exclusion table, and `members.<name>.enable` and a
member-scoped wire SHALL NOT earn an exclusion row: they are constructs this subset carries. The
remaining rows SHALL be `locality`, `lifecycle`, `placement.pick/strategy/allocation`, `externals`,
the collect family and the runtime plane, and every rule the refusals-by-subtraction requirement
states SHALL continue to hold over them unchanged.

A row leaving the table SHALL leave three places at once: the table the library exports, the
exclusion suite that asserts one refusal per row, and the table published in the worked fixture's
README. The suite SHALL compare its own count against that README, so that the three cannot be
edited apart.

#### Scenario: A deployment cutting a member earns no exclusion row

- **WHEN** a deployment writes `members.<name>.enable = false`
- **THEN** the planner SHALL emit no exclusion row
- **AND** the member SHALL be cut

#### Scenario: A member-scoped wire earns no exclusion row

- **WHEN** a deployment writes a member-scoped wire for a slot a cut opened
- **THEN** the planner SHALL emit no exclusion row
- **AND** the slot SHALL resolve to the capability the wire names

#### Scenario: The table, the suite and the fixture's README agree

- **WHEN** the exclusion table is read as data
- **THEN** its rows SHALL be exactly those the worked fixture's README tables
- **AND** the exclusion suite SHALL assert one refusal per row
- **AND** neither SHALL name `member cuts`

#### Scenario: The six remaining rows are still refused

- **WHEN** a deployment or a module writes a key naming one of the six remaining constructs
- **THEN** the planner SHALL emit that construct's exclusion row naming the trigger
- **AND** SHALL NOT emit an unknown-key row for it

### Requirement: The rows a cut and a single-consumer capability can earn

The rows this construct adds SHALL each name the declaration to edit, the way every other row does:

- A wire the deployment writes for a slot the module binds to a kept member SHALL name the slot, the
  member it is bound to, and the file that wrote the wire; its resolution SHALL name both ways out -
  cut the member, or delete the wire.
- A `placement`, a `settings` namespace or a consuming wire naming a member the instance cut SHALL
  name the member and the cut; its resolution SHALL name both ways out - keep the member, or delete
  the reference.
- A second consumer of a capability declaring `consumers = "one"` SHALL name the capability, its
  providing instance and both consuming slots, and SHALL be produced once for the capability rather
  than once per consumer.

A slot opened by a cut and left unwired SHALL earn the existing unwired-slot row rather than a row of
its own: the condition is identical, and a second identifier for it would make one fault report two
sentences.

#### Scenario: Each new row names a declaration to edit

- **WHEN** each of the three conditions is produced
- **THEN** each row SHALL name the file and the declaration to change
- **AND** each resolution SHALL name both ways out where two exist

#### Scenario: A cut with an unwired slot reports the existing row

- **WHEN** a cut opens a slot the deployment does not wire
- **THEN** the row SHALL be the unwired-slot row
- **AND** no second row SHALL describe the same absence

#### Scenario: Two consumers report one row

- **WHEN** two slots wire one single-consumer capability
- **THEN** the table SHALL carry exactly one row for it
- **AND** the row SHALL name both slots
