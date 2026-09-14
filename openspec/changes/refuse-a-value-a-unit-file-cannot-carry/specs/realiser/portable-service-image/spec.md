<!--
A delta against `realiser/portable-service-image`, whose base text lives in the unarchived
`emit-systemd-portable-service-images` change and is restated or extended by
`deliver-a-secret-without-exposing-it`, `deliver-secrets-across-machines`,
`report-every-refusal-as-a-row`, `open-a-delivered-value-to-its-reader`,
`generate-values-with-nixos-secrets`, `hold-every-stated-guarantee`, `declare-service-state`,
`hold-a-long-running-daemon` and `take-effect-on-a-second-apply`. `openspec/specs/` is empty in this
repository, so the base text is read from those changes.

Three requirements are ADDED and one is MODIFIED. `A rendered environment value is one value` is the
requirement `deliver-secrets-across-machines` added and `report-every-refusal-as-a-row` restated;
this delta restates it once more, because the rule it carries is not about an environment value and
the row it now follows is the generalised one of this change's `planner/diagnostics` delta.

The row that reports a refused name is `operator-entry-name-refused`, which
`operator/deployment-build` already owns for the other realiser and whose text already says "the
service name or a unit file name the entry derives". No delta against that capability is needed: the
change there is which realiser the reading asks for its rules, not what the row means.

`A staged file carries its declared mode before it carries bytes` (`hold-every-stated-guarantee`) is
about a file's own mode and is untouched; the directory requirement below is the other half and adds
no statement about a file.
-->

## MODIFIED Requirements

### Requirement: A rendered environment value is one value

A rendered `Environment=` assignment SHALL carry the whole value the plan records, whatever
characters it contains, or the entry SHALL be refused. A value containing a space, a double quote
or a backslash SHALL be rendered so that the service manager reads back exactly the bytes the plan
holds.

A value containing a line break SHALL be refused, and the refusal SHALL hold for every value this
realiser interpolates into a unit file and not for an environment value alone: a command, a stop or
reload command, a user, a unit reference, a schedule, a duration, a restart policy and every field
of every extension application reach the same line-oriented file. The refusal SHALL name the entry,
the unit and the field the value sits at.

A line break in a unit value is a fact the plan carries, so the planner SHALL report it as an error
row first and this refusal SHALL follow that row rather than stand alone. The refusal here SHALL
remain for a caller that reached the builder directly, and SHALL carry the identifier of that row.

#### Scenario: An environment value carries a space

- **WHEN** a unit's environment holds a value containing a space, a double quote and a backslash
- **THEN** the rendered unit SHALL carry one assignment per variable
- **AND** each assignment SHALL round-trip to the value the plan records

#### Scenario: An environment value carries a newline

- **WHEN** a unit's environment holds a value containing a newline
- **THEN** the build SHALL fail naming the entry, the unit and the variable
- **AND** the same bytes on one line SHALL build

#### Scenario: A command carries a newline

- **WHEN** a unit's command holds a value containing a newline
- **THEN** the build SHALL fail naming the entry, the unit and the field
- **AND** the rendered unit SHALL NOT be produced with a second directive line the module wrote

## ADDED Requirements

### Requirement: A unit file name this realiser derives is held to a rule it states itself

This realiser derives a service name and a unit file name from the entry's own identity, and both
SHALL be held to a rule this realiser states as the sentence its refusal prints, so that the rule and
the message cannot drift apart. A derived name outside the rule SHALL be a refusal naming the entry
and the name, and that refusal SHALL carry the identifier of the row that reports the same condition,
the way the other realiser's name rule already does.

The rule SHALL be the realiser's own and SHALL NOT be stated by the library: which realiser realises
an entry is a fact beside the deployment and no plan field carries it, so a rule in the library would
refuse a name the stated realiser accepts.

A reading that is handed a realisation statement SHALL ask the stated realiser for that rule rather
than testing which realiser it is, so that a realiser publishing the rule is asked by existing, and
SHALL report the refused name as an error row before anything is built. A name outside the rule SHALL
NOT be left to be refused by the build system that happens to receive it: such a refusal names
neither the entry nor the declaration.

#### Scenario: A unit name outside the rule is refused naming the entry

- **WHEN** an entry's identity derives a unit file name carrying a character the rule does not admit
- **THEN** the realiser SHALL refuse naming the entry, the derived name and the rule
- **AND** the deployment build SHALL report an error row for it and build no artifact of that entry

#### Scenario: The name refusal is preceded by its row

- **WHEN** the refusals this realiser can make are crossed against the rows the producing layers
  build
- **THEN** the name refusal SHALL name a row identifier a producing layer produces
- **AND** the row and the refusal SHALL state one rule, asked of the realiser rather than restated

#### Scenario: A name the rule admits builds

- **WHEN** an entry's identity derives a service name and unit file names the rule admits
- **THEN** the realiser SHALL refuse nothing on their account
- **AND** the rendered unit file names SHALL be the ones the entry recorded

### Requirement: A value a generated script interpolates is escaped, grammar or no grammar

Every value this realiser interpolates into a generated shell script SHALL be escaped as one word,
whether or not a grammar elsewhere already constrains that value. This SHALL hold for a value in a
message as well as for a value in an argument: a message is not a place to rely on a grammar,
because a grammar and an escape fail independently and the escape is what holds when a new field
reaches a script before its rule does.

A list of derived names a script hands to a command SHALL be escaped word by word rather than joined
into one string, so that a name carrying a shell metacharacter is a word the command refuses rather
than a pattern the shell expands.

This requirement is a property of the rendered script and SHALL NOT be satisfied by a row: a plan the
library refused is a plan this realiser is never handed, and a caller reaching the realiser directly
is exactly the caller the escape protects.

#### Scenario: Every path a generated script names is escaped

- **WHEN** an entry's scripts are rendered for an entry whose configuration file paths are ordinary
- **THEN** every occurrence of a path in those scripts SHALL be escaped, in messages as well as in
  arguments
- **AND** no occurrence SHALL be a bare interpolation inside a quoted string

#### Scenario: A unit list is escaped word by word

- **WHEN** the attach script stops, starts or detaches the units of an entry
- **THEN** each unit file name SHALL appear as its own escaped word
- **AND** the list SHALL NOT be rendered as one unquoted string

### Requirement: The staging directory is traversable and not listable

A directory this realiser's attach script creates to hold what the host shows an image SHALL be
created traversable by any account and listable by none, which is the mode the two writers of a
delivered value already create their directories at. A unit reads a staged file by its full path, so
traversal is the only access any account needs, and the file's own declared mode still decides its
bytes.

The directory SHALL be created at that mode before it holds a file, and no later step SHALL widen it.
A listable directory would publish the configuration file names of every entry on the machine to any
account, which is a fact about the deployment that no declaration asked to be published.

#### Scenario: The staging directory is traversable and not listable

- **WHEN** the attach script creates the directory it stages configuration files in
- **THEN** the directory SHALL be traversable by any account and listable by none
- **AND** each staged file SHALL still carry its own declared mode

#### Scenario: A staged file is readable through a directory nobody may list

- **WHEN** a unit reads a staged configuration file whose declared mode admits its account
- **THEN** the read SHALL succeed
- **AND** listing the staging directory as that account SHALL be refused
