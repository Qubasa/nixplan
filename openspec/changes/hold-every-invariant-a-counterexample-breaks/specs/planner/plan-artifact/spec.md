<!--
A delta against `planner/plan-artifact`, whose base text lives in the unarchived changes
`implement-minimal-typed-edge`, `emit-systemd-portable-service-images`, `prove-plan-on-real-machines`,
`declare-service-state`, `deliver-a-secret-without-exposing-it`, `deliver-secrets-across-machines`,
`generate-values-with-nixos-secrets`, `identify-interfaces-by-declared-id`,
`report-every-refusal-as-a-row`, `cut-a-member-and-wire-its-place`, `hold-every-stated-guarantee`,
`refuse-two-entries-claiming-one-host-resource` and `open-a-configuration-file-to-its-reader`.
`openspec/specs/` is empty in this repository, so the base text is read from those changes.

The first requirement is ADDED and reads against `A plan is flat, keyed and free of expressions`
(`implement-minimal-typed-edge`), which states what a placed service's key is and leaves one keyspace
holding three families. The second is `A name entering a key is held to the grammar the key can
carry` from `hold-every-stated-guarantee`, restated whole under `## MODIFIED Requirements`. The third
is ADDED and narrows `An entry's key is a hash of everything that affects it`
(`implement-minimal-typed-edge`) the way `A delivered file states what it lands as`
(`deliver-a-secret-without-exposing-it`) and `A configuration file states the account that may read
it` (`open-a-configuration-file-to-its-reader`) each narrowed it, both of which state the rule as
"only the fields a declaration actually stated"; that is the sentence the third requirement replaces.
The fourth is ADDED beside `A host resource two entries of one machine both claim is a row`
(`refuse-two-entries-claiming-one-host-resource`, restated by
`type-a-port-claim-and-its-collision`), which it does not change: that rule is about two entries and
this one is about one entry's own paths.

Evidence. `lib/plan.nix:1253` merges machine records, generated value entries and service entries
with `//`, so the deployment of `tests/unit/counterexamples.nix:321` - an instance named `machine`
with a member named after a declared machine - replaces that machine's record with a service entry,
and `app:only@one`'s `dependsOn` still names `machine:one@<hash>`, a key that is no longer a machine.
Classification by what a record holds rather than by the text of its key is an existing rule of the
tree (`CLAUDE.md`, Realisers; `operator-plan-record-unclassified`) and stays: `machine` is a legal
instance name and `vars/x` a legal member name, so a prefix match answers wrongly for a deployment
the planner accepts, which is why the collision is refused where the keyspace is built rather than
inferred downstream. `lib/util.nix:84`'s denylist admits the empty string, so the member of
`tests/unit/counterexamples.nix:191` is planned as `app:@one`, and `operator/read.nix`'s `parseKey`
wants a character in each of its three groups: the record is in no artifact, in no secrets
projection and in no row. `lib/plan.nix:120-122` and `:464` prune a field from a key by whether the
declaration carried it rather than by whether its value differs from the default it resolved to, so
the two byte-identical records of `tests/unit/counterexamples.nix:259` and `:291` key differently -
which regenerates a secret in the first case, `tests/e2e/generation.py` reading the moved key as a
disagreement, and rebuilds, stops, detaches and re-attaches an image in the second. The claim index
compares host paths for equality only, so the two nested paths of
`tests/unit/counterexamples.nix:890` earn no row and `applicable` is true: the image builder then
stops at `install: cannot create directory ...: Not a directory` and the flakelet builder at
`mkdir: cannot create directory 'files/etc/app'`, each naming a store path and no declaration.
-->

## ADDED Requirements

### Requirement: A plan key names one record

A plan holds three families of record under one keyspace - a machine's own record, a generated
value's entry and a placed service's entry - so a key SHALL name exactly one record. Where two
records claim one key the planner SHALL emit an error row naming both claimants and the key they
share, and SHALL report the deployment as inapplicable.

Neither record SHALL silently replace the other, and no fact a reader derives from a key SHALL be
left naming a record of a family it was not derived from: a placed entry's provenance edge onto the
machine it runs on SHALL name a machine record, and a key a record of another family claimed SHALL
NOT be what that edge resolves to. A deployment whose names are legal SHALL be unaffected, because
every family's key text is text a deployment may legitimately declare: the families SHALL keep being
told apart by what a record holds rather than by the text of its key, and the collision SHALL be
refused where the keyspace is built rather than guessed at by a reader matching prefixes.

#### Scenario: A plan key names one record

- **WHEN** an instance is named after the keyspace machine records live in and one of its members is
  named after a machine the deployment declares
- **THEN** the planner SHALL emit an error row naming both claimants of that key
- **AND** the deployment SHALL be reported as inapplicable
- **AND** the machine's own record SHALL still be the record that key names, and every placed
  entry's provenance edge onto it SHALL still name a machine

#### Scenario: Two claimants of one plan key are both named

- **WHEN** two records of different families claim one key
- **THEN** the row SHALL name both claimants and the key
- **AND** the row SHALL appear once in the table however many readings observe the collision

### Requirement: A field enters a key only where its value differs from its default

An entry's key SHALL be a digest of the facts that decide what the entry is, and a field SHALL be an
input to it only where the value the field resolved to differs from the value it would have resolved
to unstated. Whether a declaration wrote the field SHALL NOT be what decides: stating a field's own
default states nothing, so a record byte-identical to the record the same deployment produces with
that statement removed SHALL carry the same key.

The rule SHALL hold for both records whose ownership a declaration may state - a generated value's
file and an entry's configuration file - because a key that moves is not a formatting difference in
either case. A generated value's key is its identity to whatever produced its bytes, so a key that
moves for a statement changing no byte asks for bytes that are still correct to be produced again. An
entry's key decides the identity of what a realiser builds from it, so a key that moves asks for a
rebuild and for a running unit to be stopped, detached and attached again.

A plan written before a field existed SHALL still key as it did: a deployment stating none of these
fields SHALL carry the keys it carried before the record could state them. A declaration stating a
value that differs from the default SHALL move the key, because it asks for a different file, and
SHALL move the key of no other entry.

#### Scenario: Stating a generated file default does not rekey the value

- **WHEN** a generator declares a file stating the ownership and the mode a file that states none
  resolves to
- **THEN** the value entry's record SHALL equal the record of the same deployment with those
  statements removed
- **AND** the value's key SHALL be the same key
- **AND** nothing SHALL be asked to produce that value's bytes again

#### Scenario: Stating a configuration file ownership default does not rekey the entry

- **WHEN** a module declares a configuration file stating the owner and the group a file that states
  neither resolves to
- **THEN** the entry's record SHALL equal the record of the same deployment with those statements
  removed
- **AND** the entry's key SHALL be the same key
- **AND** no realiser SHALL be asked to build, stop, detach and attach the entry again on account of
  the statement

#### Scenario: A stated value that differs from the default moves the key

- **WHEN** a declaration states an ownership or a mode differing from the value it would resolve to
  unstated
- **THEN** that record's key SHALL differ from the key of the same deployment with the statement
  removed
- **AND** no other entry's key SHALL move

### Requirement: Two shown host paths of one entry may not nest

The host paths one entry is shown SHALL be paths that can all exist at once. Two paths where one is
a parent directory of the other cannot: one declaration asks for a file where the other asks for the
directory holding it. The planner SHALL emit an error row naming both declarations and the two paths,
and SHALL report the deployment as inapplicable.

The comparison SHALL be over the structure of the paths and not over their text being equal, two
nested paths being the contradiction two equal paths are, observed one directory up. The refusal
SHALL be the planner's, so that the deployment does not reach a builder: a builder meets the
contradiction while creating a store object and can name a store path and no declaration, which is
the failure this row exists to replace.

A path that merely shares a prefix with another SHALL be no row, a sibling and a longer name
beginning with another's text both being paths that can exist at once.

#### Scenario: Two shown host paths of one entry may not nest

- **WHEN** one entry is shown two host paths and one of them is a parent directory of the other
- **THEN** the planner SHALL emit an error row naming both declarations and the two paths
- **AND** the deployment SHALL be reported as inapplicable
- **AND** no realiser SHALL be asked to build that entry

#### Scenario: A shown host path sharing a prefix with another is not nested

- **WHEN** one entry is shown two host paths in one directory, one of whose names begins with the
  other's
- **THEN** the planner SHALL emit no row about either path
- **AND** the entry SHALL be shown both paths

## MODIFIED Requirements

### Requirement: A name entering a key is held to the grammar the key can carry

A plan key is structured text, and a reader recovers an entry's parts by taking that structure
apart. Every name a key is built from - a machine, an instance, a member, a generator - SHALL
therefore be held to a grammar that excludes the characters the key's own structure uses, and SHALL
additionally exclude the names no key built from them can be recovered from or rendered: the empty
name, and a name carrying a line break or another control character. A name outside the grammar SHALL
be a row naming the declaration and the name.

The grammar SHALL remain a statement of what a name may not be rather than a list of what it may: an
allowlist refuses names existing deployments legitimately use, so the three additions SHALL be stated
as three more things a name may not be, and SHALL earn the row a name outside the grammar already
earns rather than an identifier per character class.

A plan SHALL NOT be produced in which a key parses as a different key, and no fact derived from a key
- a delivery set above all - SHALL be allowed to name something the deployment never declared.

The rule SHALL leave no placed entry unaccounted for in either direction. Every entry the planner
places SHALL either be read by the readings the plan exists for - realised into what the realisation
statement asks of it, and projected into what an external generator's contract asks of it - or be
named by a row of the reading that could not read it, with that entry's own key as the row's subject.
A placed entry absent from both SHALL NOT be something a caller is handed, because a reading that
silently drops a record asks an external tool for bytes a unit opens and publishes no artifact the
entry's units can run from.

#### Scenario: A machine name carries the key separator

- **WHEN** a machine is named with a character the key's structure uses
- **THEN** the planner SHALL produce a row naming that machine
- **AND** SHALL NOT record a delivery set derived from a key that name made ambiguous

#### Scenario: An instance or member name carries the key separator

- **WHEN** an instance or a member is named with a character the key's structure uses
- **THEN** the planner SHALL produce a row naming that declaration

#### Scenario: A well-formed name is unaffected

- **WHEN** every name a deployment declares is within the grammar
- **THEN** the planner SHALL produce no row about a name
- **AND** every key SHALL take apart into exactly the parts it was built from

#### Scenario: An empty name is refused by the key grammar

- **WHEN** an instance, a member, a machine or a generator is named with the empty string, or with a
  name carrying a line break or another control character
- **THEN** the planner SHALL produce a row naming that declaration and the name
- **AND** the row SHALL be the one a name outside the key grammar already earns
- **AND** every other entry of the deployment SHALL still be planned

#### Scenario: Every placed entry is read or named

- **WHEN** a deployment places an entry whose instance or member name the key grammar refuses
- **THEN** every placed entry of the plan SHALL either be read by the realisation reading and the
  external projection or be named by a row whose subject is that entry's key
- **AND** no placed entry SHALL be absent from both
