## MODIFIED Requirements

### Requirement: An interface is a value and its name is a label

An interface SHALL be identified by the value an author imported, or by an identity that author
claimed with a declared `id`, never by a name resolved at composition time, and SHALL NOT be validated
against any registry of known interfaces. An interface's `name` SHALL be used only in diagnostic
output. Two interfaces declared in different files MAY carry the same `name`.

Where either end of an edge declares no `id`, the two SHALL be one interface only when they are one
value. Where both ends declare an `id`, the two SHALL be one interface when the whole of the identity
those claims carry is equal, and their values SHALL NOT be compared. A claim SHALL NOT make an
interface known to the planner, required to appear in any list the planner owns, or valid for having
been claimed.

#### Scenario: Two interfaces share a name

- **WHEN** two distinct interface values carry the same `name`, neither declares an `id`, and a slot on
  one is wired to a capability declaring the other
- **THEN** the planner SHALL emit an error row
- **AND** the row SHALL render the declaring file of each interface beside its name, so the two are
  distinguishable in output

#### Scenario: Two interfaces share a name and one identity

- **WHEN** two distinct interface values carry the same `name` and declare one `id` with one identity,
  and a slot on one is wired to a capability declaring the other
- **THEN** the planner SHALL resolve the edge
- **AND** SHALL NOT emit a mismatch row for it

#### Scenario: An interface nobody upstreamed

- **WHEN** a module declares an interface that no other module or library file references
- **THEN** the planner SHALL accept it
- **AND** SHALL NOT require it to appear in any list the planner owns
- **AND** SHALL accept it whether or not it declares an `id`

#### Scenario: A misspelled capability reference

- **WHEN** a module re-exports a capability under a name its member does not provide
- **THEN** the failure SHALL occur while evaluating that module file
- **AND** SHALL NOT be deferred to wire resolution

#### Scenario: A refused edge names the rule that refused it

- **WHEN** a slot's interface and the capability's interface are not one interface
- **THEN** the row SHALL state whether they were compared as values or as claims
- **AND** the resolution SHALL name the fix that applies to the rule that was used
