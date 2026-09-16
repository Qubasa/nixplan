## Purpose

Defines the deployment plan this library emits: what one entry contains, how its key is derived, what an absent value looks like, and which values are recorded as references rather than as content. The plan is the only thing the two halves of the architecture have to agree on, so its shape is a contract rather than an output format.

## ADDED Requirements

### Requirement: A plan is flat, keyed and free of expressions

A plan SHALL be an attribute set whose keys are strings and whose values contain only strings, numbers, booleans, lists and attribute sets. It SHALL contain no functions, no derivations and no store paths that are not literal strings. A placed service's key SHALL be its instance name, its service name and its machine name. A service with no units SHALL carry an entry with no machine.

#### Scenario: The plan serialises

- **WHEN** any plan this library produces is converted to JSON
- **THEN** the conversion SHALL succeed
- **AND** reading it back SHALL yield an equal value

#### Scenario: A service placed twice

- **WHEN** one service of one instance is placed on two machines
- **THEN** the plan SHALL contain two entries whose keys differ only in the machine

#### Scenario: An entry names a dependency

- **WHEN** an entry depends on another
- **THEN** the dependency SHALL be written as a key that appears elsewhere in the same plan
- **AND** SHALL carry the depended-on entry's own key hash

### Requirement: An entry's key is a hash of everything that affects it

An entry SHALL carry a key derived from its instance and service, the store paths it names, the resolved values it was handed, the keys of the entries it depends on, and the machine it runs on. Two evaluations of one input SHALL produce equal keys. A change to any hashed input SHALL change the key.

#### Scenario: An unrelated edit changes nothing

- **WHEN** a setting is changed on one service and a second service reads nothing from it
- **THEN** the second service's key SHALL be unchanged

#### Scenario: A read value changes the reader's key

- **WHEN** a provider's exported value changes and a consumer reads it into a unit's environment
- **THEN** the consumer's key SHALL change

#### Scenario: A set-valued read is in the reader's key

- **WHEN** the membership of a set-valued read changes because a machine gained or lost a tag
- **THEN** the reading entry's key SHALL change
- **AND** the planner SHALL emit a warning row stating that the entry is re-keyed by a change to another machine

### Requirement: An absent value is recorded rather than dropped

When a declared export has no bytes yet, the plan SHALL carry the entry, SHALL record the export with a null value and an explicit marker that its bytes are absent, and SHALL name the row the absence produced. Any artifact derived from a set containing an absent value SHALL be recorded as not computed rather than computed from the values that are present.

#### Scenario: A generator has not run

- **WHEN** a placement's generated file does not exist and another service reads its public half
- **THEN** the reading entry SHALL carry a named entry for that placement with a null value and an absent marker
- **AND** the entry SHALL name the diagnostic row that absence produced

#### Scenario: A rendered file over an incomplete set

- **WHEN** a file is rendered from a set-valued read and one entry of the set has no value
- **THEN** the plan SHALL record the file's content as not computed
- **AND** SHALL NOT record a hash computed over the entries that do have values

### Requirement: Secret values appear as references and public values as content

An export declared `secret` SHALL appear in the plan as a path reference and never as content. An export declared `public` MAY appear as content. A generated file declared `secret` SHALL appear as a reference; its public counterpart MAY appear as a value.

#### Scenario: A private key in the plan

- **WHEN** a service generates a keypair and uses the private half in its own unit
- **THEN** the plan SHALL carry the private half as a path
- **AND** the bytes SHALL NOT appear anywhere in the plan

#### Scenario: A secret with no reader

- **WHEN** a secret export is declared and no slot reads it
- **THEN** the plan SHALL record it with an empty reader list

### Requirement: Values are recorded on the plane their use site implies

A value a unit reads through its environment SHALL be recorded in the entry's hashed environment. A value rendered into a file the service reads at runtime SHALL be recorded as configuration data with a content hash and the units that reload when it changes. A value interpolated into a store path SHALL be part of the entry's closure.

#### Scenario: A file changes and a unit reloads

- **WHEN** the content of a rendered configuration file changes and nothing else does
- **THEN** the entry SHALL record the new content hash and the units to reload
- **AND** the entry's closure SHALL be unchanged

#### Scenario: An environment value changes

- **WHEN** a value a unit reads from its environment changes
- **THEN** the entry's key SHALL change
- **AND** the entry's closure SHALL be unchanged

### Requirement: The worked deployment reproduces its committed plan

Evaluating the deployment in `fixtures/minimal-typed-edge/deployment/` SHALL produce a plan equal to the committed fixture for that folder, comparing every field except the prose fields the fixture carries for a human reader. The fixture SHALL contain an entry for every placement the deployment produces, with none elided. The fixture SHALL carry real hash values and real store path strings rather than the shortened placeholders a hand-written file uses, and each difference between the hand-written file and the first generated one SHALL be recorded with the reason it was accepted.

#### Scenario: The golden plan matches

- **WHEN** the worked deployment is evaluated
- **THEN** the plan SHALL equal the committed fixture after prose fields are removed from both
- **AND** a mismatch SHALL report which keys and fields differ

#### Scenario: A placeholder survives into the fixture

- **WHEN** the fixture carries a shortened store path or an invented hash
- **THEN** the suite SHALL fail naming that field
- **AND** the fixture SHALL NOT be accepted as the comparison target

#### Scenario: The folder's rows are produced

- **WHEN** the worked deployment is evaluated
- **THEN** the diagnostics table SHALL contain the error row for the placement whose bytes are absent and the warning row about the re-keyed entry
- **AND** it SHALL contain no other rows

#### Scenario: The fixture elides nothing

- **WHEN** the fixture is read
- **THEN** it SHALL contain one entry per placement the deployment produces
- **AND** SHALL NOT reference an entry it does not itself contain
