<!--
A delta against `planner/secret-delivery`, whose base text lives in the unarchived changes
`deliver-secrets-across-machines`, `generate-values-with-nixos-secrets` and
`open-a-delivered-value-to-its-reader`. `openspec/specs/` is empty in this repository, so the base
text is read from those three.

Every requirement below is ADDED, for the reason `open-a-configuration-file-to-its-reader` gives for
the same decision: the blocks these read against are held in other unarchived changes, and restating
one would put a second edited copy of it in a second unarchived change. Nothing in the base becomes
false here. Each requirement below says which base sentence it makes true.

`A secret export is backed by a secret file` reads against `Secret values appear as references and
public values as content` (`planner/plan-artifact`, added by `deliver-secrets-across-machines` and
restated by `deliver-a-secret-without-exposing-it`), `Delivery moves bytes the plan never holds`, and
`An export atom declares a type and a secrecy and nothing else` (`planner/typed-edge`,
`implement-minimal-typed-edge`). Those three state the lattice per declaration and never across the
pair: nothing compares an export atom's own secrecy against the secrecy of the generated file backing
it, and `lib/resolve.nix:1428` hands a module the content of any file not declared secret, so an
interface calling the value secret publishes the bytes in the plan, in a unit's environment and in
the entry's content hash with `applicable = true`. Counterexample:
`tests/unit/counterexamples.nix:517`.

`An entry's own units are held to the readability comparison` reads against `A generated file records
the ownership and mode it is delivered at` and `The record travels with the value to every machine
that receives it` (both `open-a-delivered-value-to-its-reader`), and against the three rows that
already ask the comparison: `A unit that cannot open a value it reads is an error row`
(`planner/diagnostics`, `open-a-delivered-value-to-its-reader`), `A unit that cannot open a
configuration file its entry shows it is a row` (`planner/plan-artifact`,
`open-a-configuration-file-to-its-reader`) and `A deployed value is denied to a unit only where its
record cannot admit that unit's reader` (`realiser/portable-service-image`,
`open-a-delivered-value-to-its-reader`). `util.admits` is asked of a consumer's declared reads and of
a configuration file an entry is shown, and never of the entry's own generated value, so the
identical impossibility is deployment-fatal over a configuration file, a denial under one realiser's
confinement profile over an own value, and silence everywhere else. Counterexample:
`tests/unit/counterexamples.nix:639`.

`A value's path is named only on a machine that receives it` reads against `A generated value is
delivered to the machines that need it` and `A value nobody receives is stated, not implied` (both
`deliver-secrets-across-machines`). The second states the refusal for the case where no machine
receives the value; `undeployedRows` (`lib/plan.nix:530-571`) implements exactly that, scanning an
entry's mention sites with the predicate `!file.deploy`, so a value that is deployed and delivered
elsewhere - reached through a public export carrying the file's `path` rather than through a read of
the reference - is bound on a machine that does not hold it and the unit fails at `226/NAMESPACE`
naming neither the value nor the declaration. The base sentence stays true as the instance where the
delivery set is empty. Counterexample: `tests/unit/counterexamples.nix:676`.
-->

## ADDED Requirements

### Requirement: A secret export is backed by a secret file

An export's declared secrecy and the secrecy of the generated file backing it SHALL be compared, and
an export declared secret backed by a file that is public SHALL be an error row naming the export,
the capability it is published under and the file. A file that declares no secrecy is public, so the
row SHALL be earned by an omission exactly as it is by a written declaration: a lattice that reported
only the written case would make the cheapest mistake the silent one.

Such an export SHALL publish nothing. It SHALL carry no content, no record holding content and
nothing derived from either, so a consumer wired to it reads an absent slot rather than the bytes,
the way every other refused read leaves its slot absent.

Where two declarations disagree about one value's secrecy, the plan SHALL carry that value at the
stricter of the two. The bytes SHALL NOT enter the plan on the strength of the weaker declaration:
the file SHALL be recorded as a path and no content, at every site of the owning entry as well as at
the export, so that a unit environment, a configuration file recipe and every key input that named
the content hold none of it. A content hash over a leaked secret is the leak in another form.

The comparison SHALL be made from the declarations and never from the bytes a generator has produced
so far, so a deployment whose value does not exist yet earns the same row as one whose value does,
and the row does not appear and disappear with the state the plan was evaluated against.

#### Scenario: A secret export may not be backed by a public file

- **WHEN** a module publishes a generated file that declares no secrecy as an export whose atom
  declares that export secret
- **THEN** the planner SHALL emit one error row naming the export and the file
- **AND** the export SHALL carry no value, and the file's bytes SHALL appear in no entry of the plan,
  in no unit's environment and in no entry's key
- **AND** the deployment SHALL NOT be applicable, and every other entry SHALL still be planned

### Requirement: An entry's own units are held to the readability comparison

The readability comparison SHALL be asked wherever the plan holds the facts it needs, which are a
file's recorded owner, group and mode beside the account and the groups a unit declares. An entry's
own generated value SHALL be one of those sites: a unit that names a file of its own entry's
generator and runs as an account the file's record does not admit SHALL be an error row naming the
entry, the unit, the account, the value, the file and the record the file states, which is what a
consumer's declared read of another entry's value already earns.

The answer SHALL NOT depend on which realiser reads the plan. A unit that cannot open a file the plan
told it to read cannot start under any realiser, so the row SHALL be produced by the layer that holds
the plan, and a confinement profile imposing an account SHALL remain a second condition about that
imposed account rather than the only report of this one. A deployment realised by a layer that
confines nothing SHALL earn the same row as one realised by a layer that does.

The comparison SHALL be one rule asked at each site rather than one copy per site, and the sites
SHALL agree about a unit that declares no account: where nothing imposes one it runs privileged, so
it admits any file and earns no row, and a unit that spells the privileged account out SHALL answer
the same way as one that declares none.

A record that admits the unit SHALL earn no row: by its owner where the unit runs as that account, by
its group where the unit declares that group, and by the mode's world bits for any account. The row
SHALL be per unit and per file, so an entry whose second unit runs privileged keeps that unit, and
the entry SHALL still be planned with the value's path recorded.

#### Scenario: A unit that cannot open its own value is a row

- **WHEN** an entry's unit declares an account and names a file of that entry's own generator whose
  record admits its owner alone
- **THEN** the planner SHALL emit an error row naming the entry, the unit, the account, the file and
  the record
- **AND** the row SHALL be produced whatever realiser the deployment states, and whether or not any
  confinement profile is involved
- **AND** the deployment SHALL NOT be applicable

#### Scenario: A value a unit's declared group admits is no row

- **WHEN** an entry's unit declares an account and a group, and names a file of that entry's own
  generator whose record grants that group read
- **THEN** the planner SHALL emit no row about readability
- **AND** the entry SHALL record the unit and the file's path as it does for a file nobody questioned
- **AND** the value's delivery set SHALL be what the owner's placements and the declared reads make
  it

### Requirement: A value's path is named only on a machine that receives it

An entry SHALL name a generated value's path only on a machine that receives the value. Where a unit
or a configuration file of a placed entry names the path of a file whose value's delivery set does
not contain that entry's machine, the planner SHALL emit an error row naming the entry, its machine,
the value, the file and the site that names the path. The path resolves to nothing there, and what
the machine reports when the unit fails to start names neither the value nor the declaration, which
is the whole reason the row exists.

The question SHALL be whether the machine receives the value, not whether the value is deployed at
all. A value no machine receives is the instance of that rule where the delivery set is empty, so
every machine is outside it and the refusal already stated for that case follows from this one rather
than standing beside it. A value that is deployed and delivered elsewhere SHALL be refused on the
same terms, however the path reached the naming entry: through the value's own record, through a read
of a reference, or through a public export carrying the path as an ordinary string.

The rule SHALL NOT widen the delivery set. A declared read of an export backed by a file SHALL remain
the only thing that puts a reader's machine in the set, and naming a path SHALL never put a machine
in it: an entry that names a path it was not delivered is told to declare the read or to stop naming
the path, and the set stays what the owner's placements and the declared reads make it. A rule that
delivered on a mention would make a routable secret bounded by nobody.

An entry on a machine the set contains SHALL earn no row, and the entry SHALL still be planned with
every path it named either way: the row, an inapplicable deployment and a realiser's own refusal are
what stop the bytes.

#### Scenario: Naming a value path on a machine outside the delivery set is a row

- **WHEN** an entry placed on one machine names in a unit the path of a generated value whose
  delivery set holds another machine only, having reached that path through a public export rather
  than through a read of the reference
- **THEN** the planner SHALL emit an error row naming the entry, its machine, the value and the file
- **AND** the value's delivery set SHALL be unchanged, holding the owner's machine alone
- **AND** the deployment SHALL NOT be applicable
