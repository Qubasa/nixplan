<!--
A delta against `planner/unit-vocabulary`, whose base text lives in the unarchived changes
`emit-systemd-portable-service-images`, `hold-a-long-running-daemon` and
`open-a-configuration-file-to-its-reader`. `openspec/specs/` is empty in this repository, so the base
text is read from those three.

Every requirement below is ADDED, for the reason `open-a-configuration-file-to-its-reader` gives:
what these read against is held in other unarchived changes, and restating one of those blocks would
put a second edited copy of it in a second unarchived change. Nothing in the base becomes false here;
two of the three make a base sentence true in the direction it already claims.

`A configuration file's source is a store object or the file has no bytes` reads against `A
configuration file names its bytes rather than carrying them`
(`emit-systemd-portable-service-images`), which already calls `source` "a store path holding the
rendered file", and against `A configuration file's disposition states when its bytes exist`
(`hold-a-long-running-daemon`). Nothing checks either sentence: `lib/module.nix:1328` copies the
stated `source` verbatim through `util.pickAttrs`, held to neither kind nor store, so
`/etc/ssl/private/host.key` is bound into a unit as that entry's configuration and a value of another
kind reaches `readFile` in a builder. The same fact is already checked one field over, by `A
generated value may declare the program that produces it` (`planner/secret-delivery`,
`generate-values-with-nixos-secrets`). Counterexample: `tests/unit/counterexamples.nix:863`.

`A host path a unit binds carries nothing a service manager reads as its own` reads against `A
configuration file's host path is held to the grammar a rendered step can carry`
(`planner/diagnostics`, `refuse-a-value-a-unit-file-cannot-carry`), whose two properties - the row
and the grammar's single home in the library - are unchanged. What changes is what the grammar
admits: `util.wordRule` admits `:`, which separates one bind from the next inside `BindReadOnlyPaths=`
so the directive is dropped, and `%`, which systemd expands as a specifier so the bind lands on a
path the artifact has no mount point for. Counterexample: `tests/unit/counterexamples.nix:946`.

`A unit's own name and an environment name are held to the rule their values are` reads against `A
value a unit file cannot carry is a row for every field the file carries` (`planner/diagnostics`,
`refuse-a-value-a-unit-file-cannot-carry`) and `Each unit runs with its own environment`
(`emit-systemd-portable-service-images`). The scan walks every string the record carries, values and
attribute names alike, and the two outermost names are outside it: the unit's own attribute name,
which a realiser turns into a unit file name and renders directives under, and an environment
variable's name, which `image/read.nix` writes as `Environment="<k>=<v>"` escaping the key with
nothing. Either forges a free directive line, and flakelet's restated unit rule does not catch the
first because `builtins.match`'s `.` matches a newline. Counterexamples:
`tests/unit/counterexamples.nix:921` and `:979`, the second of which the realiser delta of this
change answers for the rendering half.
-->

## ADDED Requirements

### Requirement: A configuration file's source is a store object or the file has no bytes

A configuration file's stated source SHALL be read for its kind and held to the store before it is
recorded. A source that is not a string, or that is a string naming a path outside the store, SHALL
be an error row naming the entry, the file's host path and what a source may be.

The file SHALL then have no bytes rather than bytes from somewhere else. The entry SHALL record the
host path, the mode and the ownership the declaration states and no disposition at all, so that a
reader cannot mistake a refused source for a file whose bytes exist, and nothing shows a unit a host
file the deployment never rendered under the name of its own configuration.

This SHALL be the rule `A generated value may declare the program that produces it` already states
for the other store path a declaration writes: the library records a literal string, resolves
nothing and reads nothing, and a value outside that grammar is a row rather than a path a builder
dereferences. One field of a plan SHALL NOT be held to two standards because two layers read it.

The check SHALL be the library's, so every realiser and every plan reader inherits it. The entry
SHALL still be planned and the deployment SHALL NOT be applicable, and every other entry of the
deployment SHALL still be read.

#### Scenario: A configuration file source is read for its kind and held to the store

- **WHEN** an implementation states a configuration file whose source is a host path outside the
  store, or a value of another kind entirely
- **THEN** the planner SHALL emit one error row naming the entry, the host path and what a source may
  be
- **AND** the file SHALL be recorded with no bytes and no disposition, so no realiser and no plan
  reader is handed the stated value
- **AND** the deployment SHALL NOT be applicable, and every other entry SHALL still be planned

### Requirement: A host path a unit binds carries nothing a service manager reads as its own

A host path a configuration file is written to SHALL be held to what a rendered bind can carry
literally, beside what a rendered shell word can carry. A service manager gives two characters a
meaning of its own inside such a value: the one that separates one bind from the next within a single
directive, and the one that introduces a specifier the manager expands before the bind is made. A
path carrying either is bound somewhere the entry never declared - a directive dropped for a field
count the author did not intend, or a mount at an expanded name - so each SHALL be an error row
naming the entry, the path and what the grammar admits, and the path SHALL NOT be recorded on the
entry.

The grammar SHALL be stated as what every renderer of the path can carry, not as what one of them
can. A recorded host path reaches a rendered shell word, the value of a bind and a plan reader that
resolves it, so a character any one of them reads as its own is a character none of them can be
handed.

The grammar SHALL keep exactly one home. Every realiser and every plan reader SHALL inherit it from
the library rather than state it again, and the reading that renders a delivery step SHALL read it
rather than restate it, so no grammar can admit a character in one rendered script and refuse it in
another. Narrowing it SHALL narrow it for all of them at once.

A refused path SHALL earn one row and not one per renderer that could not carry it, because the fact
is one: the deployment stated a path no renderer accepts.

#### Scenario: A configuration file path is a word a unit file can bind

- **WHEN** an implementation states a configuration file whose host path carries the character a bind
  list separates on, or the character a service manager expands as a specifier
- **THEN** the planner SHALL emit exactly one error row naming the entry, the path and what the
  grammar admits
- **AND** that row SHALL be the one every out-of-grammar host path already earns rather than an
  identifier of its own
- **AND** the path SHALL NOT be recorded on the entry, and the deployment SHALL NOT be applicable

### Requirement: A unit's own name and an environment name are held to the rule their values are

A unit's own name and the name of an environment variable SHALL be held to the rule the strings
inside a unit record are held to, so a line break in either SHALL be an error row. A renderer writes
both into a unit file with no escape of its own, so a line break in either forges a free directive
line, and a unit that carries a directive no module wrote does something no declaration states.

The row SHALL be the one a unit field's value carrying a line break already earns, naming the entry,
the unit and the name at fault, rather than an identifier of its own: one class of defect is one
identifier, and the row names its site. The entry SHALL still be read and the deployment SHALL NOT be
applicable, on the same terms that rule already states for the values it covers.

An environment variable's name SHALL additionally be held to the grammar a service manager can carry
for one, and a name outside it SHALL be an error row naming the entry, the unit and the name, with
neither the name nor its value recorded. The assignment a renderer would write from such a name is a
directive the manager refuses in part, after which the unit starts without the variable, and a unit
running with an environment the deployment did not declare is the silence this row replaces.

One name SHALL earn one row. A name the environment grammar refuses SHALL be reported by that rule
alone, including where the character it carries is a line break, so a reader is not told twice about
one name.

#### Scenario: A unit name carrying a line break is a row

- **WHEN** an implementation declares a unit whose own name contains a line break
- **THEN** the planner SHALL emit one error row naming the entry and that unit
- **AND** the row SHALL be the one a unit field's value carrying a line break already earns
- **AND** the deployment SHALL NOT be applicable, and every other entry SHALL still be planned

#### Scenario: An environment name is held to the environment name grammar

- **WHEN** a unit declares an environment variable whose name is outside the grammar a service
  manager can carry for an environment name
- **THEN** the planner SHALL emit one error row naming the entry, the unit and the name
- **AND** neither the name nor its value SHALL be recorded on the unit, so no renderer writes an
  assignment from it
- **AND** the name SHALL earn no second row about a character that grammar already refused
