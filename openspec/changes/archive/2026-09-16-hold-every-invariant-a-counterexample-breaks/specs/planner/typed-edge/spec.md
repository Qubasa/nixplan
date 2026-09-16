<!--
A delta against `planner/typed-edge`, whose base text lives in the unarchived changes
`implement-minimal-typed-edge`, `deliver-secrets-across-machines`,
`identify-interfaces-by-declared-id`, `unify-declaration-and-implementation-readings`,
`cut-a-member-and-wire-its-place`, `hold-declaration-shape-and-fold-set-reads`,
`hold-the-consumer-cardinality-a-provider-states` and
`keep-a-declaration-from-ending-an-evaluation`. `openspec/specs/` is empty in this repository, so
the base text is read from those changes.

Both requirements below are ADDED.

The first reads against `An export atom declares a type and a secrecy and nothing else` (the base),
whose fourth scenario puts a failing value's row at the provider, and against `A claim decides only
whether an edge exists` (`identify-interfaces-by-declared-id`), which states that each side keeps
the value its own author imported. Both stand: the provider's own verification at
`lib/resolve.nix:1666` keeps producing `export-type-mismatch` against the provider, and no
comparison of two interfaces is added. What is added is the verification nobody performs today, the
one the consumer's own declared type makes over the value it is handed.
`korora/types.nix:485-489` returns a record type as a name, a verifier and an override, so a whole
record schema is outside a claimed identity and the wire resolves anyway:
`tests/unit/counterexamples.nix:566` wires one provider and one consumer over two member sets under
one claimed identifier and reads the consumer as rendered from a record its own declaration refuses.

The second reads against `An interface is a value and its name is a label`
(`identify-interfaces-by-declared-id`), which states that an interface is validated against no
registry, and against `A row about an interface does not depend on attribution`
(`hold-every-stated-guarantee`, `planner/diagnostics`), which holds the other direction of the same
rule and is unchanged. `lib/interface.nix:394-414` walks every interface a deployment reaches
together with every one the attribution lists, so a listed interface no module imports earns its
rows: `tests/unit/counterexamples.nix:748` plans one applicable deployment twice and watches an
attribution entry it never reads turn it inapplicable.
-->

## ADDED Requirements

### Requirement: A delivered read is verified against the consuming interface's own type

A value a read delivers SHALL be verified against the export type the consuming interface declares,
where the value crosses the wire, and that verification SHALL be the structural check of a typed
edge. A value the consumer's own declaration refuses SHALL leave the slot unfilled - absent from the
consumer's resolved reads rather than present and empty - and SHALL be one error row naming the
consuming entry, the slot and what the consuming interface's type reported.

Identity equality SHALL NOT be taken as a structural check. The verification SHALL be made whether
the two ends matched by value or by a claimed identity, and whether or not either end claims one, so
a provider publishing a value its consumer's declaration refuses SHALL be reported even where the two
ends agree on every name an identity carries.

The verification a provider already makes against its own interface SHALL stand and SHALL keep its
subject: a value failing the provider's own declared type is the provider's row and names no
consumer. The two SHALL be rows about two subjects, and a value one end accepts and the other refuses
SHALL earn only the row of the end that refused it.

What is compared SHALL be a value against a type and never a type against a type: the planner SHALL
still not verify that two matched interfaces agree on anything an identity does not carry. A value
both ends accept SHALL be delivered unchanged, and the verification SHALL change no delivery set, no
plan key and no read the plan records.

#### Scenario: A provider publishes a record the consuming interface refuses

- **WHEN** a provider and a consumer declare interfaces that match, one export is declared as a
  record on both sides, and the provider publishes a record its own declaration accepts and the
  consumer's declaration refuses
- **THEN** the planner SHALL emit an error row naming the consuming entry, the slot and what the
  consuming interface's type reported
- **AND** the slot SHALL be absent from that consumer's resolved reads
- **AND** the table SHALL report the plan as not applicable
- **AND** every other entry of the deployment SHALL still be planned

#### Scenario: A consuming interface accepts the record it is delivered

- **WHEN** a read delivers a value the consuming interface's declared type accepts
- **THEN** the consuming implementation SHALL receive that value unchanged
- **AND** no row SHALL be emitted for the verification
- **AND** the delivery set of any generated value behind that export SHALL be the one the declared
  read produces without it

#### Scenario: A set-valued read verifies each provider against the consuming interface

- **WHEN** a slot reads one interface with set reach over several providers and one of them publishes
  a value the consuming interface's declared type refuses
- **THEN** the planner SHALL emit one error row naming the consuming entry, the slot and the
  contributing provider
- **AND** the slot SHALL be left unfilled rather than delivered as the set the refused provider was
  dropped from
- **AND** every other entry of the deployment SHALL still be planned

### Requirement: Attribution decides what a row says and never which rows exist

The interface attribution a deployment passes SHALL be attribution and never a registry. Every row an
interface can earn - about its claimed identity, about its fold, about its exports - SHALL be reached
from the modules that imported that interface, and an interface the attribution does not name SHALL
earn each of those rows exactly as a named one does.

Attribution SHALL change only what a row says about the file an interface was declared in. Adding or
removing an attribution entry SHALL NOT change whether the plan is applicable, SHALL NOT change any
value the plan records, and SHALL NOT change which conditions the table reports.

An interface the attribution names that no module of the deployment imported SHALL therefore earn no
row at all. Its declarations reach no entry, no wire and no export, so a malformed one SHALL be
neither checked nor reported: naming an interface registers nothing, and a list of names is not a set
of declarations the planner is asked to hold to anything.

#### Scenario: Attribution does not decide applicability

- **WHEN** one applicable deployment is planned twice, the second time with an interface named in its
  attribution that no module of it imports and whose declaration would earn an error row were a
  module to import it
- **THEN** both plans SHALL be applicable
- **AND** both SHALL record the same entries with the same keys and the same values
- **AND** no row SHALL be emitted about the named interface

#### Scenario: Attribution changes only the file a row names

- **WHEN** one deployment is planned twice, once with an imported interface named in its attribution
  and once without
- **THEN** each row either plan carries SHALL be carried by the other for the same condition
- **AND** the two SHALL differ only in how each such row names the declaring file
- **AND** both SHALL report the same plan and the same applicability
