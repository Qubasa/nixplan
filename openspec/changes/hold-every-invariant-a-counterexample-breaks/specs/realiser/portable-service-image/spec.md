<!--
A delta against `realiser/portable-service-image`, whose base text lives in the unarchived
`emit-systemd-portable-service-images` change and is restated or extended by
`deliver-a-secret-without-exposing-it`, `deliver-secrets-across-machines`,
`report-every-refusal-as-a-row`, `open-a-delivered-value-to-its-reader`,
`generate-values-with-nixos-secrets`, `hold-every-stated-guarantee`, `declare-service-state`,
`hold-a-long-running-daemon`, `take-effect-on-a-second-apply`,
`open-a-configuration-file-to-its-reader` and `refuse-a-value-a-unit-file-cannot-carry`.
`openspec/specs/` is empty in this repository, so the base text is read from those changes.

Both requirements below are ADDED, and each sharpens a sentence the base already carries rather
than replacing the requirement that carries it.

The first reads against `An image carries no bytes the host holds` (`hold-a-long-running-daemon`),
whose closing sentence is "The image's version digest SHALL be taken over what the artifact holds",
and against `Two evaluations of one deployment produce one image`
(`emit-systemd-portable-service-images`). Evidence: `image/read.nix:556-587` takes the digest over
the entry's name, its units, its closure, `storeDir`, the service manager, the shown host paths and
the platform, and `:645` applies it to the key and the entry alone, so the stated confinement
profile is outside it while `:623-696` renders that profile into what the artifact holds. Two
artifacts whose unit files differ therefore publish one digest, carry one image file name, report
`nothing changed` on every apply and read as `current`. Counterexample:
`tests/unit/counterexamples.nix:1014`.

The second reads against `A rendered environment value is one value`, which
`deliver-secrets-across-machines` added, `report-every-refusal-as-a-row` restated and
`refuse-a-value-a-unit-file-cannot-carry` restated again. That requirement is about a value and is
unchanged; what is added is the other half of the same directive. Evidence:
`image/read.nix:790` renders `Environment="<k>=<v>"`, escaping the backslash and the quote of the
value and the name with nothing, so a name carrying the quote character closes the quoting and the
rest of the line is the module's to write; systemd answers `Invalid syntax, ignoring` and starts the
unit without the variable. Counterexample: `tests/unit/counterexamples.nix:979`.

The row that reports a value a unit file cannot carry is `unit-value-newline`, and the rule that a
unit name and an environment name are held to their values' rule belongs to
`planner/unit-vocabulary` in this same change. The requirements below are this realiser's half: what
it renders and what it refuses.
-->

## ADDED Requirements

### Requirement: The version digest an artifact publishes covers every statement its bytes depend on

An artifact's version digest is the identity an endpoint stores and the identity a report compares,
so it SHALL move whenever a statement the artifact was built from changes a byte the artifact
carries, and SHALL NOT move for a statement that changes none. The stated confinement profile is
such a statement: it decides directives the rendered unit files carry, so it SHALL be part of the
digest, beside the entry's name, its units, its closure, the store directory, the service manager,
the host paths it is shown and the platform it is built for.

Two artifacts of one entry whose rendered bytes differ SHALL NOT share a digest, SHALL NOT share an
image file name, and SHALL NOT be reported as one build a machine already holds. A statement a
reader can change and see no consequence is the failure this requirement removes: an apply that
reports nothing changed and a report that says the machine is current, over an entry whose
confinement the operator has just tightened.

Widening the digest re-keys every artifact once, which is one stop, detach and attach per entry on
the first apply after this change and nothing afterwards. That is the intended consequence: a
digest that was wrong for one statement was wrong for every artifact built under it.

#### Scenario: The version digest carries the confinement profile

- **WHEN** one entry is read twice, differing only in the confinement profile stated for it
- **THEN** the two readings SHALL publish two different version digests
- **AND** the two artifacts SHALL carry two different image file names
- **AND** neither reading SHALL report the other's identity as its own

#### Scenario: A tightened profile is a build the machine does not hold

- **WHEN** an operator tightens the confinement stated for an entry and applies the deployment
- **THEN** the machine SHALL be told it holds a build that is not this one
- **AND** the entry's units SHALL be stopped, its previous image detached and this one attached
- **AND** a second apply of the same statement SHALL report that nothing changed

#### Scenario: An entry whose statement did not change keeps its digest

- **WHEN** a deployment is edited so that neither an entry's own record nor the statement beside it
  changes
- **THEN** that entry's version digest SHALL be the digest it published before the edit
- **AND** its artifact SHALL be byte-identical
- **AND** an apply SHALL neither detach nor re-attach it

### Requirement: Every part of a rendered directive is escaped the way every other part is

A rendered directive carries more than one part - a variable's name beside its value - and every
part SHALL be carried through the escape the others are carried through, so that no part can end
the quoting another part sits inside. A name containing the quote character, the backslash or a
character the service manager reads as a separator SHALL read back as exactly the bytes the plan
records, the way the value on the same line already does.

Where the renderer has no escape that carries a part of a directive, the entry SHALL be refused
naming the entry, the unit and the part, and SHALL NOT be rendered into a file whose remaining
directives are the declaration's to choose. A part the renderer drops, truncates or renders into a
line the service manager answers with a syntax complaint SHALL NOT be taken to satisfy this
requirement: a unit that starts without the variable a declaration asked for is the silent failure
this rule exists to remove.

The plan reports such a value as an error row first and this refusal SHALL follow that row rather
than stand alone, the way this realiser's other refusals do. The refusal SHALL remain as the answer
a caller that reached this realiser directly receives, and SHALL carry the identifier of the row
that reports the same condition.

#### Scenario: An environment name is escaped the way its value is

- **WHEN** a unit's environment holds a variable whose name carries the quote character
- **THEN** the planner SHALL report an error row for that name, or the rendered directive SHALL
  escape the name the way it escapes the value on the same line
- **AND** the rendered line SHALL carry no directive the declaration did not write
- **AND** the service manager SHALL read back the name and the value the plan records

#### Scenario: A rendered directive reads back as the name and the value the plan records

- **WHEN** a unit's environment holds a value carrying a space, a quote character and a backslash,
  under a name the name grammar admits
- **THEN** the rendered unit SHALL carry one assignment for that variable
- **AND** that assignment SHALL round-trip to the name and the value the plan records
- **AND** the name SHALL have been carried through the escape the value was carried through

#### Scenario: An environment name the renderer cannot carry is refused

- **WHEN** an entry reaches this realiser with an environment name the renderer has no escape for
- **THEN** the build SHALL fail naming the entry, the unit and the name
- **AND** the refusal SHALL carry the identifier of the row that reports the same condition
- **AND** no unit file of that entry SHALL be produced
