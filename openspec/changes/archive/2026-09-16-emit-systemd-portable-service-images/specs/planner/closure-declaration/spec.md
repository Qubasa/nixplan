## Purpose

Defines how a plan entry's closure comes to exist and where its bytes came from: the roots a module declares, the pin those roots were built from, the store directory the roots are read against, the grammar by which a string is recognised as a store path, and the rows that stop a declaration from drifting away from what the entry actually mentions. The closure is the list a consumer populates a filesystem from, so it is a contract rather than documentation, and a list inference cannot complete must not be inferred.

## ADDED Requirements

### Requirement: An entry's closure roots are declared rather than inferred

A module SHALL declare the store path roots its entry depends on, and the plan SHALL record exactly those roots as the entry's `closure`. The `closure` SHALL be what any consumer populating a filesystem from the entry uses, and no other list SHALL serve that purpose. A scan of the entry's strings SHALL NOT be the source of truth for the `closure`, because a path assembled at runtime, a path arriving through a configuration file's `ref`, and a path a module holds in a shape no scan walks are each invisible to any scanner.

A declared root SHALL be recorded as a literal string and SHALL name a store root rather than a path inside one, so a root declared by way of a file within it SHALL be recorded as the root that contains it.

#### Scenario: A module declares two roots

- **WHEN** a module declares two store path roots for one entry
- **THEN** the entry's `closure` SHALL contain both
- **AND** SHALL contain nothing the module did not declare

#### Scenario: The closure names roots and not paths inside them

- **WHEN** a module declares a root and interpolates a path inside that root into a unit's `command`
- **THEN** the entry's `closure` SHALL contain the root
- **AND** SHALL NOT contain the path inside it
- **AND** the planner SHALL emit no row

#### Scenario: A consumer populates a filesystem from the closure

- **WHEN** a consumer copies every root of an entry's `closure` into a filesystem and resolves every path the entry's units name
- **THEN** every one of those paths SHALL resolve within that filesystem

### Requirement: An entry records the pin its closure was built from

A module SHALL declare the pin its store path roots were built from, as literal strings: a key identifying the pin, and a locked record naming a source, a revision and a content hash. A locked record naming no revision, or no content hash, SHALL be an error row naming the module and the missing field, because a pin that can resolve to different bytes on a later evaluation is the condition this declaration exists to refuse.

A placed entry SHALL record its pin, and that pin SHALL be part of the entry's key.

The planner SHALL NOT resolve pins. It SHALL hold no pin registry, no default pin and no precedence between a module's pin and a deployment's, because sharing one dependency across a tree, protecting a dependency from a consumer's sharing, and deduplicating identical sources are a dependency resolver's obligations and a second resolver could disagree with the first. Two entries whose modules were resolved to one source SHALL record one key, and two resolved to different sources SHALL record different keys, so that whether two services share a dependency is answered by comparing recorded keys and by no other field.

A pin SHALL be recorded and SHALL NOT be verified. The planner reads no lockfile and instantiates nothing, so it SHALL NOT claim that an entry's store paths were in fact produced by the pin the entry names; confirming that is the build plane's obligation.

#### Scenario: A module declares a fully specified pin

- **WHEN** a module declares a pin with a key and a locked record naming a source, a revision and a content hash
- **THEN** the entry SHALL record that pin
- **AND** the planner SHALL emit no row

#### Scenario: A pin names no revision

- **WHEN** a module declares a pin whose locked record has a source and no revision
- **THEN** the planner SHALL emit an error row naming the module and the missing field
- **AND** the plan SHALL still contain the entry

#### Scenario: A pin names no content hash

- **WHEN** a module declares a pin whose locked record has a revision and no content hash
- **THEN** the planner SHALL emit an error row naming the module and the missing field

#### Scenario: Every service resolved to one source

- **WHEN** every member of a deployment was resolved to one shared source
- **THEN** every entry SHALL record one equal pin key
- **AND** the planner SHALL emit no row, because sharing was decided before the plan

#### Scenario: Services resolved to different sources

- **WHEN** two members of one deployment were resolved to different sources
- **THEN** each entry SHALL record its own pin key
- **AND** neither SHALL be re-keyed by a change to the other's pin

#### Scenario: A pin changes and the store paths move

- **WHEN** a member's pin changes and its declared roots move to new store paths
- **THEN** the entry's key SHALL change
- **AND** the entry SHALL record the new pin, so the moved paths are attributable to it

#### Scenario: The planner does not verify a pin

- **WHEN** an entry names a pin and carries store paths that pin did not produce
- **THEN** the planner SHALL record the pin as declared
- **AND** SHALL emit no row claiming the paths were produced by it

### Requirement: A store path the entry mentions and does not declare is a row

Any store path appearing in any string the entry carries — a unit's fields, a unit's `env`, a unit extension's `values`, a configuration file's `text` fragments and `ref` paths, a generated file's path, and an export's value — and absent from the entry's declared roots SHALL produce `closure-path-undeclared`, an error row naming the entry, the store path, and where in the entry the path was mentioned. The plan SHALL still contain the entry, so an operator sees what was asked for alongside the refusal.

A declared root that no string of the entry mentions SHALL produce a warning row rather than an error, naming the entry and the root, because such a root is either dead weight or a path assembled at runtime that is worth having written down.

#### Scenario: A package in a command is not declared

- **WHEN** a store path is interpolated into a unit's `command` and is not among the entry's declared roots
- **THEN** the planner SHALL emit a `closure-path-undeclared` error row naming the entry, the path and the unit field that mentioned it
- **AND** the plan SHALL still contain the entry

#### Scenario: A package named only by a configuration file is not declared

- **WHEN** a store path appears only in a configuration file's `text` fragment or `ref` path and is not among the entry's declared roots
- **THEN** the planner SHALL emit a `closure-path-undeclared` error row naming the entry, the path and the configuration file
- **AND** the plan SHALL still contain the entry

#### Scenario: A package named only by an export value is not declared

- **WHEN** a store path appears only in an export's value and is not among the entry's declared roots
- **THEN** the planner SHALL emit a `closure-path-undeclared` error row naming the entry, the path and the export
- **AND** the plan SHALL still contain the entry

#### Scenario: A declared root nothing mentions

- **WHEN** an entry declares a root and no string the entry carries mentions it
- **THEN** the planner SHALL emit a warning row naming the entry and that root
- **AND** the entry's `closure` SHALL still contain the root

#### Scenario: A consistent entry

- **WHEN** every store path the entry mentions is a declared root and every declared root is mentioned
- **THEN** the planner SHALL emit no row for that entry

### Requirement: The store directory is an input to plan evaluation

The store directory SHALL be `storeDir`, an argument to `mkPlan`, defaulting to `builtins.storeDir` — the evaluating Nix's own configured store directory — rather than to a literal path written in the library's source. Recognition of a store path SHALL be performed against that directory, and any consumer populating a filesystem from an entry's `closure` SHALL read the same directory, so a machine whose store lives elsewhere is planned and populated under its own store rather than under a hardcoded one.

#### Scenario: The default store directory

- **WHEN** a plan is evaluated without `storeDir`
- **THEN** the store directory SHALL be the evaluating Nix's configured store directory
- **AND** paths under that directory SHALL be recognised as store paths

#### Scenario: A deployment planned against a relocated store

- **WHEN** a plan is evaluated with `storeDir` set to a directory other than the default
- **THEN** a path under the given directory SHALL be recognised as a store path
- **AND** a path under the default directory SHALL NOT be recognised as a store path for that plan

#### Scenario: An absolute path outside the store directory

- **WHEN** a unit field carries an absolute path that is not under the store directory
- **THEN** that path SHALL NOT be recognised as a store path
- **AND** the planner SHALL emit no row for it

### Requirement: A store path is recognised by Nix's store path grammar

A store path SHALL be recognised as the store directory, followed by a 32-character hash drawn from the base-32 alphabet `0123456789abcdfghijklmnpqrsvwxyz`, followed by a hyphen and a name. The alphabet SHALL exclude `e`, `o`, `t` and `u`, so a run of 32 name characters SHALL NOT be recognised as a hash.

Recognition SHALL be exact in both directions: a string that is a store path SHALL always be recognised as one, and a string that is not SHALL never be. Every store path in a string SHALL be recognised, not only the first.

#### Scenario: A genuine store path is recognised

- **WHEN** a string under the store directory carries a 32-character base-32 hash, a hyphen and a name
- **THEN** it SHALL be recognised as a store path

#### Scenario: A 32-character run outside the alphabet is not a hash

- **WHEN** a string under the store directory carries 32 characters containing `e`, `o`, `t` or `u` where a hash would sit
- **THEN** it SHALL NOT be recognised as a store path
- **AND** the planner SHALL emit no `closure-path-undeclared` row for it

#### Scenario: A short hash is not a store path

- **WHEN** a string under the store directory carries a 31-character base-32 run, a hyphen and a name
- **THEN** it SHALL NOT be recognised as a store path

#### Scenario: Two store paths in one string

- **WHEN** one string interpolates two distinct store paths
- **THEN** both SHALL be recognised
- **AND** each undeclared one SHALL produce its own `closure-path-undeclared` row
