# realiser/secrets-configuration Specification

## Purpose
Says what one plan becomes when it is read as a configuration for an external secret generator: one
store entry per generated value, a name projection that either holds or refuses, and the one deploy
script that carries the machine dimension the external contract does not have. The reading realises
nothing beyond the script it renders, and it refuses rather than mangling a name or guessing a
target.

## Requirements

### Requirement: A plan is readable as a generator configuration

The reading SHALL take one plan and produce a configuration the external generator consumes without
evaluating any of this library's Nix: one store entry for each generated value the plan carries,
and nothing for an entry that is not a generated value.

Each store entry SHALL carry the value's declared files, the sibling values it declared reads of as
that entry's dependencies, and the generator the deployment declared. A file the plan records as
undeployed SHALL be marked as not to be deployed, so that a value which exists for other values to
read is generated and stored and sent to no machine.

The reading SHALL NOT invent a field the plan does not record. A configuration key the external
contract requires and the plan cannot answer SHALL be reported as a row naming the entry and the
field, and no store entry for that value SHALL be emitted.

#### Scenario: A generated value becomes one store entry

- **WHEN** a plan carrying a generated value is read
- **THEN** the configuration SHALL hold exactly one store entry for that value
- **AND** that entry SHALL declare exactly the files the value declares
- **AND** an entry of the plan that is not a generated value SHALL contribute none

#### Scenario: A declared read becomes a dependency

- **WHEN** a value declares a read of a sibling value
- **THEN** the sibling SHALL appear as that entry's dependency under the same projected name
- **AND** the order the external tool derives from those dependencies SHALL be an order the plan
  already resolved, so a cycle is refused before the reading rather than during generation

#### Scenario: An undeployed value is generated and sent nowhere

- **WHEN** a value the plan records as undeployed is read
- **THEN** its store entry SHALL exist
- **AND** each of its files SHALL be marked as not to be deployed

#### Scenario: A required field the plan cannot answer is refused

- **WHEN** a value carries no generator for the external tool to run
- **THEN** the reading SHALL report a row naming the entry and the field
- **AND** it SHALL NOT emit an entry with an absent or empty generator
- **AND** it SHALL NOT raise

### Requirement: The name projection holds or the reading refuses

A plan key is structured and the external contract accepts a restricted name, so the reading SHALL
project each key onto a name that contract admits, and the projection SHALL be injective over one
plan. Two values projecting onto one name SHALL be reported as a row naming both plan keys, because
one would otherwise overwrite the other's stored bytes.

A projection SHALL be refused where a component of the key already contains the separator the
projection uses, and where a component contains a character the external contract does not admit.
Neither SHALL be silently substituted or stripped, and each SHALL be a row rather than a raise.

A per-machine value's projected name SHALL name its machine, so that two machines' values of one
generator remain two stored values.

#### Scenario: Two values projecting onto one name are refused

- **WHEN** two plan keys project onto the same external name
- **THEN** the reading SHALL report a row naming both keys and the name they collide on
- **AND** neither entry SHALL appear in the configuration

#### Scenario: A name component carrying the separator is refused

- **WHEN** an instance, generator or machine name contains the character the projection separates on
- **THEN** the reading SHALL report a row naming the component and the character
- **AND** the row SHALL state that the name is what has to change

#### Scenario: A per-machine value keeps its machine in its name

- **WHEN** one generator is declared per machine and placed on two machines
- **THEN** the configuration SHALL hold two store entries
- **AND** each projected name SHALL name its own machine

### Requirement: The deploy script is rendered from the plan

The external contract hands its deploy step a list of files and no target, so the reading SHALL
render that step itself. For each file the rendered step SHALL address exactly the machines the
value's delivery set names, at the addresses the plan records, and SHALL write the file at the path
the plan fixed.

The rendered step SHALL address no machine outside a value's delivery set, and SHALL contain none of
the bytes of any value: it names paths and machines only.

A value whose delivery set names a machine the plan gives no address for SHALL be reported as a row
before any script exists, and no step SHALL be rendered for that value.

An address or a path the rendered step cannot carry as a single shell word SHALL be a row naming the
value, the offending text and what a rendered word admits. The reading SHALL NOT quote its way around
one, and SHALL NOT render a step it cannot render safely.

The rendered step SHALL deliver every pair the list holds, including the last one when the list ends
without a line terminator. The external tool joins the list with newlines, so its last line carries
none, and a step that dropped it would store a file and deliver nothing at the path a unit opens.

#### Scenario: The rendered step targets the delivery set

- **WHEN** the deploy step rendered from a plan is read
- **THEN** for each file it SHALL name exactly the machines the value's delivery set names
- **AND** the path it writes SHALL be the path the plan recorded for that file

#### Scenario: The last pair of the file list is delivered

- **WHEN** the rendered step is given a file list whose last line has no terminator
- **THEN** that pair SHALL be delivered like every other

#### Scenario: The rendered step carries no bytes

- **WHEN** the rendered step is searched for the bytes of any value the plan describes
- **THEN** none SHALL be found

#### Scenario: A delivery target with no address is refused

- **WHEN** a value's delivery set names a machine whose plan entry records no address
- **THEN** the reading SHALL report a row naming the value and the machine
- **AND** the row SHALL state that the machine's address is what is missing
- **AND** no step SHALL be rendered for that value

### Requirement: The reading is pinned and fails when the external contract moves

The reading is written against one revision of an external contract that is under review and not
merged. The repository SHALL record which revision, and a check SHALL compare the contract that
revision publishes against the contract the resolved tool carries.

A disagreement SHALL fail the check, naming the file to edit and the revision recorded, so that a
reading written for a superseded contract cannot outlive it silently. Where the comparison cannot be
made at all, the check SHALL NOT fail: an unreadable signal is not evidence that the contract moved.

#### Scenario: The external contract has changed

- **WHEN** the resolved tool publishes a contract differing from the recorded revision's
- **THEN** the check SHALL fail naming the recorded revision and the file that encodes it
- **AND** the message SHALL state what to delete or rewrite

#### Scenario: The external contract cannot be read

- **WHEN** the tool cannot be resolved at all
- **THEN** the check SHALL NOT fail
- **AND** the run depending on the tool SHALL skip itself with a reason instead

### Requirement: The reading of a plan as a configuration is total

Reading a plan as a generator configuration SHALL be total: it SHALL answer with a diagnostics table
beside its result, and SHALL NOT raise for a condition it can report. Every condition the reading
refuses SHALL be a row naming the value entry it is about, and the row SHALL carry a resolution
naming the declaration to change.

Rows the reading produces SHALL be built through the same row constructors the planner's own rows
are, so that one condition renders as one line whatever the deployment interpolated into it, and so
that the severity of a row is the producing layer's to state and never the author's.

A reading asked for its rows SHALL realise nothing: no derivation, no filesystem read, and no
rendered script.

#### Scenario: A plan the reading refuses still answers with a table

- **WHEN** a plan carrying a condition the reading refuses is read for its rows
- **THEN** the reading SHALL answer with a table carrying a row for that condition
- **AND** SHALL NOT raise
- **AND** the row SHALL name the value entry and what has to change

#### Scenario: Every condition of one plan is reported, not the first

- **WHEN** one plan carries two conditions the reading refuses
- **THEN** the table SHALL carry a row for each of them
- **AND** neither row SHALL depend on which condition was read first

### Requirement: The conditions only this reading knows are its own rows

The external contract's requirements are facts no layer above this reading holds, so each SHALL be a
row of this reading rather than a raise or a planner row:

- a value entry recording no program to run, where the contract runs one program per stored value;
- a generated file whose name the contract does not admit, and a file carrying the name the contract
  reserves for its own provenance record;
- two plan keys projecting onto one stored name;
- a recipient machine whose plan record carries no address, where the rendered step has to dial it;
- an address or a path the rendered step cannot carry as a single shell word.

Each row SHALL name both sides of the fact it reports: the value entry and the field, the file and
the grammar, both plan keys and the name they collide on, or the value and the machine.

A row about a recipient machine's address SHALL be an error of this reading even though the same
absence is a warning of a deployment build, because the rendered deploy step is the one artifact that
carries an address and it cannot be rendered without one.

#### Scenario: A value with no program is a row

- **WHEN** a plan carries a generated value whose entry records no program
- **THEN** the reading SHALL report a row naming the entry and the program field
- **AND** the resolution SHALL name declaring a program on the generator, or reading the plan with
  something that needs none

#### Scenario: A file name outside the contract's grammar is a row

- **WHEN** a generated value declares a file whose name the external contract does not admit
- **THEN** the reading SHALL report a row naming the file, the value and the characters the contract
  admits

#### Scenario: The contract's reserved provenance name is a row

- **WHEN** a generated value declares a file carrying the name the contract keeps for its own
  provenance record
- **THEN** the reading SHALL report a row naming the file and the value
- **AND** the row SHALL state that the file is what has to be renamed

#### Scenario: A recipient machine with no address is an error row

- **WHEN** a deployed value's delivery set names a machine whose plan record carries no address
- **THEN** the reading SHALL report an error row naming the value and the machine
- **AND** a deployment build of the same plan SHALL still report that absence as a warning and build
  every artifact

#### Scenario: An address the rendered step cannot carry is a row

- **WHEN** a machine of a delivery set records an address the rendered step cannot carry as one
  shell word
- **THEN** the reading SHALL report a row naming the machine, the address and the characters a
  rendered word admits

### Requirement: A generation build carries the table it was refused by

A build that reads a plan as a generator configuration SHALL produce the diagnostics it produced in
both a machine-readable and a rendered form, beside the configuration, the name mapping and the
expression it writes. Both SHALL be present whether or not the table holds a row.

A table carrying an error SHALL refuse the build with the rendered table, and the refusal SHALL be
that table rather than a message from the reading. A table carrying warnings and no error SHALL
build, because a warning that stopped a build would be an error.

The refusal SHALL cover the rows of the plan and the rows of the reading alike, so that an operator
reading one table sees every reason the generation was refused.

#### Scenario: A refused generation names every reason in one table

- **WHEN** a generation build is refused
- **THEN** the refusal SHALL be the rendered table of the plan's rows and the reading's rows together
- **AND** SHALL NOT be a message naming one condition

#### Scenario: A generation build carries both halves of its table

- **WHEN** a generation build succeeds
- **THEN** its result SHALL carry the diagnostics in a machine-readable form and in a rendered form
- **AND** both SHALL be present when the table is empty

#### Scenario: A warning does not refuse a generation

- **WHEN** the table of a generation build carries warnings and no error
- **THEN** the build SHALL produce the configuration, the name mapping and the expression
- **AND** the warnings SHALL be readable in both halves of its table

### Requirement: The rendered step leaves no plaintext on the host that ran it

The rendered delivery step fetches each file's decrypted bytes onto the host that runs it, because
the external contract hands its backend a path to write rather than a stream. That file SHALL be
removed before the step ends, on every path out of it: a delivery that completed, a delivery a
machine refused, a fetch that failed, and an interrupt.

The removal SHALL be installed before the first fetch and SHALL NOT be a command after the send. The
step runs under `set -eu`, so a refused send exits the step and a command written after it is never
reached; a removal that only runs on the successful path is what leaves the bytes behind exactly
when something went wrong.

At no point SHALL the plaintext of more than one file exist on that host, so a step delivering a
hundred files leaves neither a hundred files behind nor a hundred beside each other while it runs.
What does exist SHALL be readable by nothing the account running the step is not.

A signal no process can trap SHALL be the one case this cannot cover, and what survives it SHALL be
one file rather than one per delivery.

#### Scenario: The rendered step removes the plaintext it fetched

- **WHEN** the step rendered from a plan carrying delivered values is read for what it does with the
  file it fetches into
- **THEN** the removal SHALL be installed before the first fetch and SHALL cover a normal exit, the
  exit a refused send causes, and an interrupt
- **AND** the plaintext of at most one file SHALL be able to exist at a time

#### Scenario: A delivery the machine refuses leaves no plaintext

- **WHEN** the rendered step is run against a send that refuses, with the fetch answering bytes
- **THEN** the step SHALL exit non-zero
- **AND** no file holding any byte of any value SHALL remain in the directory its temporaries were
  made in

#### Scenario: A completed delivery leaves no plaintext

- **WHEN** the rendered step delivers every pair of a file list it was given and exits zero
- **THEN** no file holding any byte of any delivered value SHALL remain in the directory its
  temporaries were made in
- **AND** the bytes on each recipient machine SHALL be the bytes the backend answered

### Requirement: Every value the rendered step carries as a word is checked by the reading first

This reading has two halves: the half that answers a diagnostics table raises nothing, and the half
that renders the delivery step refuses with the sentence a row of that table states. Every value the
rendered step carries as a single shell word - the address it dials, the path it writes, that path's
parent directory, the mode it sets and the ownership it sets - SHALL be checked by the half that
answers the table, so that the refusal a builder makes is the second time an operator hears the
fact and never the first.

A refusal the rendering half makes SHALL always have a row above it. A word only the rendering half
examines SHALL NOT exist: such a word turns a declaration an operator can correct into a build that
stops with no table, naming a rendered fragment rather than the value, the field and the machine.

Each row SHALL name both sides of the fact it reports - the value entry, the field the word came
from, the offending text and what a rendered word admits - and SHALL be an error, because the
rendered step is the one artifact of a generation that carries these words and it cannot be rendered
without them.

The words the two halves hold SHALL be crossed against each other rather than listed twice, so that
a word a future field adds to the rendered step is checked by existing rather than by somebody
remembering this rule.

#### Scenario: An ownership the render refuses is a row first

- **WHEN** a plan carries a delivered generated file whose stated owner or group the rendered step
  cannot carry as one shell word
- **THEN** the reading SHALL report an error row naming the value, the field and the offending text
- **AND** the reading asked for its rows SHALL NOT raise
- **AND** a caller that renders the step instead SHALL be refused with the sentence that row states

#### Scenario: Every value the rendered step escapes is crossed against the reading

- **WHEN** the words the rendered step carries are crossed against the values the table-answering
  half checks
- **THEN** every word the step carries SHALL be one the table-answering half checks
- **AND** a word checked by the rendering half alone SHALL fail that crossing naming the field
- **AND** a check of the table-answering half that no rendered word corresponds to SHALL fail it too

#### Scenario: An ownership the reading admits renders

- **WHEN** a delivered file states an owner and a group the rendered word rule admits
- **THEN** the reading SHALL report no row on their account
- **AND** the rendered step SHALL carry both as single words
- **AND** the step SHALL set that ownership on the file it writes

### Requirement: Every generated value the plan carries is projected or refused by name

This reading SHALL classify a plan record by what that record holds and never by the text of the key
it sits at: a record carrying a delivery set, a file set and a generator to run is a generated
value, and a record carrying a placement or nothing of either is not. An instance may legitimately
be called after a machine and a member after the prefix a generated value's key carries, so a
classification made by matching key text answers wrongly for a plan the planner calls applicable.

Every generated value the plan carries SHALL therefore be either projected onto a name the external
contract admits or refused by a row naming it. A value that is in no store entry, in no collision
comparison, in no row and in no delivery the external tool performs SHALL NOT be possible: the plan
holds bytes a unit opens at a path, and a value the reading cannot see is a unit left to open a file
nothing writes, with no sentence anywhere naming the declaration.

Where a key's components cannot be recovered - because a component is empty, or carries the
separator the projection uses, or carries a character the contract does not admit - the refusal
SHALL name the value by its plan key, which the plan always carries, rather than by the projection
that failed.

#### Scenario: The secrets reading sees every generated value the plan carries

- **WHEN** a plan carries a generated value whose instance or member name is empty
- **THEN** the reading SHALL either project that value onto a name the contract admits or report a
  row naming it by its plan key
- **AND** the count of values the reading sees plus the values it refuses SHALL be the count of
  generated values the plan carries
- **AND** no value of the plan SHALL reach the external tool's delivery without having been seen

#### Scenario: A value entry is recognised by the delivery it records

- **WHEN** a plan carries a generated value whose key text resembles no generated value's key
- **THEN** the reading SHALL recognise it from the fields its record holds
- **AND** it SHALL contribute one store entry, or one row naming what the record cannot answer

#### Scenario: A service entry whose key names a generator contributes no store entry

- **WHEN** a plan carries a placed service entry whose member name resembles a generated value's key
- **THEN** the reading SHALL contribute no store entry for it
- **AND** SHALL report no row about it
- **AND** SHALL render no delivery step naming it
