# planner/plan-artifact Specification

## Purpose
Defines the deployment plan this library emits: what one entry contains, how its key is derived, what an absent value looks like, and which values are recorded as references rather than as content. The plan is the only thing the two halves of the architecture have to agree on, so its shape is a contract rather than an output format.

## Requirements

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

An export declared `secret` SHALL appear in the plan as a path reference and never as content. An
export declared `public` MAY appear as content. A generated file declared `secret` SHALL appear as a
reference; its public counterpart MAY appear as a value.

A generated file's path SHALL name the instance that owns the generator, the generator and the file,
because a machine may hold values it does not own and two instances of one module would otherwise
name one file. The path SHALL be the same on every machine that receives the value, so that one
delivery of one value has one name.

#### Scenario: A private key in the plan

- **WHEN** a module publishes a generated file declared `secret` as an export
- **THEN** the plan SHALL record the export's path and secrecy and no bytes of the file

#### Scenario: A secret with no reader

- **WHEN** a secret export is declared and no slot reads it
- **THEN** the plan SHALL record it with an empty reader list

#### Scenario: A generated file's path names its instance

- **WHEN** two instances of one module, each declaring a generator called `app`, are placed on one
  machine
- **THEN** the two files' paths SHALL differ by the instance segment
- **AND** each path SHALL be the one recorded on every machine that receives that value

### Requirement: Values are recorded on the plane their use site implies

A value a unit reads through its environment SHALL be recorded in that unit's hashed environment, and additionally in the entry's environment when every unit of the entry agrees on it. A value rendered into a file the service reads at runtime SHALL be recorded as configuration data with the file mode, the units that reload when it changes, and either the store path holding the rendered file or the ordered recipe from which the machine assembles it. A value interpolated into a store path SHALL be part of the entry's closure, and the closure SHALL be the roots the module declared rather than the roots a scan inferred.

The plan SHALL name bytes rather than carry them. A digest SHALL be recorded only over material the plan itself holds: a file assembled from public literals alone SHALL carry a content hash over those literals, a file whose recipe carries any reference SHALL carry a hash over the recipe's fragments and reference paths and no digest over assembled bytes, and a file named by a store path SHALL be identified by that path.

#### Scenario: A file changes and a unit reloads

- **WHEN** the content of a rendered configuration file changes and nothing else does
- **THEN** the entry SHALL record the new file identity and the units the module named for reloading
- **AND** the entry's closure SHALL be unchanged

#### Scenario: An environment value changes

- **WHEN** a value a unit reads from its environment changes
- **THEN** the entry's key SHALL change
- **AND** the entry's closure SHALL be unchanged

#### Scenario: Two units read different values for one variable

- **WHEN** two units of one entry are handed different values for one environment variable
- **THEN** each unit SHALL record its own value
- **AND** the entry's environment SHALL NOT record that variable
- **AND** the planner SHALL emit no row

#### Scenario: A file whose recipe names a secret

- **WHEN** a configuration file's recipe interpolates the path of a value declared secret
- **THEN** the entry SHALL record the recipe with that path as a reference
- **AND** SHALL record a hash over the recipe's fragments and reference paths
- **AND** SHALL record no digest over the file's assembled bytes

#### Scenario: A store path only a configuration file names

- **WHEN** a package is named by a configuration file's recipe and by no command and no environment value
- **THEN** the module SHALL be required to declare it among the entry's closure roots
- **AND** an undeclared mention SHALL be an error row naming the entry, the path and where it was mentioned

### Requirement: The worked deployment reproduces its committed plan

Evaluating the deployment in `fixtures/minimal-typed-edge/deployment/` SHALL produce a plan equal to
the committed fixture for that folder, comparing every field except the prose fields the fixture
carries for a human reader. The fixture SHALL contain an entry for every placement the deployment
produces and for every generated value it declares, with none elided. The fixture SHALL carry real
hash values and real store path strings rather than the shortened placeholders a hand-written file
uses, and each difference between the hand-written file and the produced plan SHALL be recorded.

The generated bytes the planner is told about SHALL be keyed by the entry of the value they belong
to, so that one value has one answer about whether it exists no matter how many machines receive it.

#### Scenario: The golden plan matches

- **WHEN** the worked deployment is evaluated
- **THEN** the produced plan SHALL equal the committed golden plan field for field

#### Scenario: The state of a value is keyed by its entry

- **WHEN** the planner is told which generated files exist
- **THEN** it SHALL read that state under the key of the value's own entry
- **AND** a `per = "instance"` value SHALL have exactly one such record however many machines
  receive it

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

### Requirement: An implementation is handed the machine it was planned for

An implementation SHALL receive the machine a placement was planned for as one value carrying every
fact the planner has about it that a unit may be rendered from: what it is built for, what runs its
units, and the address it is reached at. All three SHALL be present, because a value carrying a
subset of them cannot be read safely: selecting an absent attribute is a failure the planner cannot
catch and cannot report, so an implementation that reads the address of a machine that declares none
would end the whole evaluation rather than earn a row. A machine that declares no address SHALL
therefore have no entry to hand a value to, and the planner SHALL report that machine against the
registry file instead.

An implementation SHALL NOT have to test for the presence of any of the three, and a deployment
SHALL NOT have to restate the address in settings for a service to publish its own endpoint.

#### Scenario: A service publishes its own endpoint

- **WHEN** a service is placed on a machine whose record carries an address, and its
  implementation renders that address into an export or a unit
- **THEN** the value it renders SHALL equal the address the plan records for that machine
- **AND** the deployment SHALL have declared the address exactly once, in the machine registry

#### Scenario: A machine with no address

- **WHEN** a service is placed on a machine whose record declares no address, and its implementation
  reads that address with no test for its presence
- **THEN** the planner SHALL produce the registry's own row naming the machine and the file that
  declares it
- **AND** no entry SHALL be planned for that machine, so nothing forces the implementation
- **AND** the table SHALL carry no row about the module

#### Scenario: The address a consumer reads is the producer's, not its own

- **WHEN** a consuming service reads an endpoint from a wire whose far end is on another machine
- **THEN** the address in the value it reads SHALL be the producing machine's address

### Requirement: A machine's address is an input to the keys of the entries on it

Because a unit may be rendered from a machine's address, the address SHALL be an input to the key
of every entry placed on that machine, so that two renderings of one entry can never share a key.
Changing one machine's address SHALL change the keys of the entries placed on it and no others.

#### Scenario: An address changes

- **WHEN** a machine's address is declared differently and nothing else changes
- **THEN** the keys of the entries placed on that machine SHALL change
- **AND** the keys of entries placed on other machines SHALL be unchanged

#### Scenario: Nothing else changes with it

- **WHEN** a machine's address is declared differently and nothing else changes
- **THEN** the plan SHALL report the same placements, the same allocations and the same wires as
  before

### Requirement: A generated value is an entry of the plan

A plan SHALL carry one entry per generated value, keyed `<instance>:vars/<generator>` for a
`per = "instance"` value and `<instance>:vars/<generator>@<machine>` for a `per = "placement"` one,
so that a reader can tell which cardinality it holds before opening it. Splitting such a key SHALL
be splitting at the last `@`, as for a service entry.

The entry SHALL carry the cardinality, whether any machine receives it, the machines that do, the
reason each one does, the sibling values it reads, the entries it depends on, and one record per
declared file naming that file's path, its secrecy and whether the plan holds its value or a
reference to it. It SHALL carry a key over exactly those inputs, so that two evaluations of one
input produce equal keys and a moved input moves the key. The machine fact SHALL reach a
`per = "placement"` value's key only through `dependsOn`, as it does for a service entry.

#### Scenario: A shared value is one entry

- **WHEN** a member placed on three machines declares a `per = "instance"` generator
- **THEN** the plan SHALL carry exactly one entry for it, keyed without a machine
- **AND** that entry SHALL name all three machines in its delivery set

#### Scenario: A machine-specific value is one entry per machine

- **WHEN** a member placed on three machines declares a `per = "placement"` generator
- **THEN** the plan SHALL carry three entries, each keyed with its machine
- **AND** the three keys SHALL differ only through the machine fact each depends on

#### Scenario: A generated value depends on what it reads

- **WHEN** a `per = "placement"` generator reads a `per = "instance"` sibling
- **THEN** each placement's entry SHALL name the sibling's entry and key in `dependsOn`
- **AND** the sibling's entry SHALL name neither

### Requirement: A published capability records the identity its interface claimed

An entry's record of a capability it provides SHALL carry the identity its interface claimed, beside
the interface's name and declaring file that the record already carries. The field SHALL be absent
where the interface claimed no identity, never null and never the interface's name, so that a reader
cannot mistake an unclaimed interface for one claiming its own label.

A claim SHALL NOT change an entry's key. Two deployments that differ only in whether an interface
claims an identity SHALL produce the same entry keys, because a claim decides which edges exist and
not what any entry was rendered from.

#### Scenario: A claimed interface records its claim

- **WHEN** an entry provides a capability whose interface declares an identity
- **THEN** the plan's record of that capability SHALL carry that identity
- **AND** SHALL still carry the interface's name and its declaring file

#### Scenario: An unclaimed interface records no claim

- **WHEN** an entry provides a capability whose interface declares no identity
- **THEN** the plan's record of that capability SHALL carry no identity field at all
- **AND** the record SHALL otherwise be byte-identical to the one produced before claims existed

#### Scenario: A claim does not re-key an entry

- **WHEN** an interface adopts an identity and nothing else about a deployment changes
- **THEN** every entry key in the plan SHALL be the one it was before

### Requirement: A placed entry records what a realisation reads

A placed entry SHALL record the closure it declares and the units it declares, whether or not either
holds anything. An empty closure SHALL mean the entry depends on no store path, and an empty unit
set SHALL mean the entry runs nothing; an absent field SHALL mean the plan does not know, which is a
condition a realisation may refuse. A reader SHALL NOT have to write a fallback for either field,
and SHALL NOT be able to mistake either field for an absence.

The plan MAY continue to omit a field whose emptiness carries no such claim. An entry that is placed
nowhere SHALL record neither, because it declares no units for any machine and has no closure to
declare.

#### Scenario: A unit names no store path

- **WHEN** a placed entry's only unit runs a command outside the store and names no store path
- **THEN** the entry SHALL record a closure holding no root
- **AND** reading that entry as an artifact SHALL produce one, with no refusal about a field the
  entry does not record

#### Scenario: A placed service runs no unit

- **WHEN** a service is placed on a machine, publishes an export and declares no unit
- **THEN** the entry SHALL record a unit set holding no unit
- **AND** the diagnostics table SHALL carry no row about it

#### Scenario: An entry that is placed nowhere records no unit

- **WHEN** a member's placement selects no machine
- **THEN** the entry the plan carries for it SHALL record neither a closure nor a unit set
- **AND** it SHALL still record its own key, its placement and its settings

### Requirement: A generated value's program is carried and is not fetched by a machine

A generated value's entry SHALL record the program its generator declared, so that a reader of the
plan alone can run it. The record SHALL be the store path as a literal string, and SHALL be
distinguishable from a value that declared none.

The program SHALL NOT be a closure root of any entry, and its presence in an entry SHALL NOT be a
mention the closure scan holds against a declared closure. A closure is what a machine is given, and
a generator runs where the plan is read: on the machine that holds the values, never on the machine
that receives them. Making the program a closure root would send every deployment's generators to
every machine that receives one of their outputs.

#### Scenario: The program is in the entry

- **WHEN** a generator declaring a program is planned
- **THEN** its value's entry SHALL record that path
- **AND** an entry whose generator declared none SHALL record its absence rather than a path

#### Scenario: The program is mentioned without entering a closure

- **WHEN** the plan is scanned for store paths mentioned without being declared as closure roots
- **THEN** a generator's program SHALL produce no row
- **AND** it SHALL appear in no entry's closure

#### Scenario: A machine is given no generator

- **WHEN** every closure of a plan whose generators declare programs is read
- **THEN** none of them SHALL name a generator's program

### Requirement: Every file record says whether bytes arrive at its path

Every generated file the plan records SHALL say whether any machine receives it, on the record of
the file itself and not only on the value's own entry. A realiser reads one entry, and whether bytes
arrive at a path is what decides whether that path may be shown to a unit at all.

The path SHALL be recorded either way. A value nobody receives still has the path it would be read
at, which is what lets a site that opens it be reported as a row rather than silently accepted.

#### Scenario: A file record carries its delivery

- **WHEN** an entry holding a generated file is read
- **THEN** the file's record SHALL state whether it is deployed
- **AND** the record SHALL carry the path whether it is deployed or not

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

### Requirement: One identity of a member is spelled one way

A member SHALL have one identity, and every reading of that member SHALL use it. Where a member's
declaration offers two spellings - the key it is declared under and a name it carries - the planner
SHALL either hold them to be equal or report the difference as a row naming both, and SHALL NOT read
one where the other was recorded.

#### Scenario: A member is declared under a key other than its own name

- **WHEN** a member is declared under one attribute name and carries another
- **THEN** the planner SHALL produce a row naming both spellings
- **AND** the evaluation SHALL NOT end

### Requirement: A field a reader must not mistake for an absence is always recorded

An entry SHALL record every field a reader has to distinguish from an absence, whether or not that
field carries anything. Where a plan omits a field because its value was empty, no reader SHALL be
required to tell that omission apart from a field the entry never had.

The file record of a value entry SHALL be such a field: a value entry SHALL record its files whether
or not the generator declared any.

#### Scenario: A generator declares no files

- **WHEN** a generator declares no files
- **THEN** its value entry SHALL still record a file set, empty
- **AND** a reader SHALL NOT have to treat the field's absence as a shape of its own

#### Scenario: An entry records an empty collection a reader depends on

- **WHEN** an entry's field is a collection that a documented reader indexes
- **THEN** the plan SHALL record it empty rather than omit it

### Requirement: A cut member produces no entry, and no entry that remains moves

A member an instance cut SHALL contribute nothing to the plan: no placed entry, no unplaced entry, no
generated value entry, and no name in any other entry's `dependsOn`. The absence SHALL be an absence
of records rather than a record marked absent.

Every entry the instance still produces SHALL carry the key it carries when nothing is cut, provided
nothing else about it changed. A deployment that cuts a member SHALL therefore redeliver nothing but
what the cut itself changed: the entries whose reads moved from a sibling's capability to a wired
one.

No field of the plan SHALL record that a composition was cut, or which members an instance kept. A
reader holding the plan SHALL be unable to tell an operator's cut from a module that never published
the member, because the two produce the same entries - which is what makes a cut an authoring
decision rather than a plan field.

#### Scenario: The entries of a kept member are unchanged by a cut

- **WHEN** one instance keeps every member and a second cuts a member no kept member's binding named
- **THEN** every entry the second instance produces SHALL carry the key the first instance's
  corresponding entry carries
- **AND** the plan SHALL carry no entry for the cut member

#### Scenario: A cut member's generated value is not recorded

- **WHEN** a cut member declares a generator
- **THEN** the plan SHALL carry no value entry for it
- **AND** no entry SHALL name it in `dependsOn`

#### Scenario: The plan does not say what was cut

- **WHEN** two deployments produce the same entries, one by cutting a member and one by naming a
  module that never published it
- **THEN** the two plans SHALL be equal
- **AND** no field SHALL distinguish them

#### Scenario: A consumer whose read moved to a wired provider

- **WHEN** an instance cuts the member a slot was bound to and wires the slot to another instance's
  capability
- **THEN** the consuming entry's key SHALL differ from the uncut instance's corresponding entry
- **AND** the difference SHALL be the resolved read, which the key input already carries
- **AND** no other entry of that instance SHALL move

### Requirement: An implementation is handed the member it belongs to

A module's implementation SHALL be handed the name of the member it is, beside the instance it
belongs to and the machine it was planned for. The pair SHALL be the same pair the entry's plan key
is built from, so that a name derived from it is unique among the entries of one machine by
construction rather than by convention.

The name handed SHALL be the member's identity in its composing root - the attribute key the root
declared it under - and never a second spelling carried inside the member, so that a name a module
derives is the name every plan key, settings namespace and diagnostics subject already uses. A member
name that could make the pair ambiguous is refused before any key exists, so a module SHALL be able
to interpolate what it is handed without escaping it.

Adding the argument SHALL move no entry key and no plan record: the instance and the member are
already inputs to every entry's key, so a module that ignores the new argument SHALL plan exactly as
it did.

#### Scenario: An implementation derives a name from its own entry

- **WHEN** a placed member's implementation reads the instance and the member it was handed
- **THEN** both SHALL equal the instance and the member its plan key is built from

#### Scenario: Two members of one instance derive two names

- **WHEN** one root composes two members of one leaf module and both are placed on one machine
- **THEN** each implementation SHALL be handed its own member name
- **AND** a path each derives from it SHALL differ between the two entries

#### Scenario: The member handed is the attribute key of the member

- **WHEN** a member is composed under one attribute key and carries a different name inside itself
- **THEN** the implementation SHALL be handed the attribute key
- **AND** the disagreement SHALL remain the row it already is

#### Scenario: A module that ignores the argument plans as it did

- **WHEN** a deployment whose modules read neither the instance nor the member is planned
- **THEN** every entry key SHALL be the key it was before the argument existed

### Requirement: A port claim is a port number, a protocol and the address it binds

A port claim SHALL declare a number, MAY declare the protocol it listens on, and MAY declare the
address it binds. It SHALL declare nothing else, and a key outside those three SHALL be refused as
an unknown key the way every other unread key of a declaration is, so that a word that reads as a
guarantee cannot be carried without one.

The number SHALL be a port: an integer of 1 to 65535. A value that is not SHALL be a row and the
claim SHALL NOT be recorded, so that no later reading compares a value the vocabulary refused and
none repairs one. A number written as text SHALL NOT be read as the number it spells.

The protocol, where stated, SHALL be one of a named domain the row that refuses a value outside it
quotes. Where it is not stated, the claim SHALL be read as claiming the number on every protocol of
that domain, so that a claim which says less is compared against more rather than against nothing.

The address, where stated, SHALL be the single address the listener binds. Where it is not stated,
the claim SHALL be read as binding every address of its machine. The absence SHALL be the only
spelling of that reading, so a claim cannot state the wildcard twice over.

A protocol or an address the vocabulary refuses SHALL leave the number recorded and SHALL be read as
though the field had not been stated, because a refusal must not make the planner compare less than
it did.

#### Scenario: A port number written as a string

- **WHEN** a module claims a port whose number is the text of a number rather than a number
- **THEN** the planner SHALL emit an error row naming the claim and what a port is
- **AND** the entry SHALL record no allocation for that claim
- **AND** no second claim of the same number on the same machine SHALL be reported as colliding with
  it, there being no claim to collide with

#### Scenario: A port number outside the range

- **WHEN** a module claims a port whose number is zero, negative or above 65535
- **THEN** the planner SHALL emit an error row naming the claim and the range
- **AND** the entry SHALL record no allocation for that claim

#### Scenario: A port claim declaring count

- **WHEN** a module writes a port claim carrying a key the claim vocabulary does not read
- **THEN** the planner SHALL emit an error row naming the key and listing the keys a claim declares
- **AND** the deployment SHALL be inapplicable

#### Scenario: A claim whose protocol is refused keeps its number

- **WHEN** a module claims a port with a protocol outside the domain
- **THEN** the entry SHALL still record the number
- **AND** the recorded claim SHALL carry no protocol

### Requirement: An entry records a port claim's number and nothing else

An entry SHALL record the number of each claim it makes and SHALL record neither the protocol nor
the address. The protocol and the address SHALL be read from the declaration where the planner
compares claims, and SHALL NOT be inputs to the entry's key, so that a claim that adopts an address
moves no key, no record and no golden byte of a deployment that already plans.

An address a deployment varies SHALL still re-key the entries it varies, because the value reaches
the claim through the member's resolved settings and those are already an input to the key. The
planner SHALL NOT hand the address back to the implementation: a module that states one stated it
out of what it was already handed.

#### Scenario: The entry records the number alone

- **WHEN** an entry claims a port stating both a protocol and an address
- **THEN** the entry's allocation record SHALL carry the number
- **AND** it SHALL carry no protocol and no address

#### Scenario: A claim that states an address keys as it did

- **WHEN** a claim that stated no address is given one that its machine already answers on
- **THEN** the entry's key SHALL be the key it was before the address existed

#### Scenario: An address a deployment moves re-keys through settings

- **WHEN** a deployment changes the setting a module builds its claimed address from
- **THEN** the entry's key SHALL change
- **AND** the entries that read nothing from that member SHALL keep their keys

### Requirement: A configuration file states the account that may read it

A configuration file's record SHALL state the account and the group that may read it beside the
mode it already states, in the same words a generated value's file record states them. Both SHALL
be recorded on every configuration file, whether the declaration stated them or not, so that a
reader cannot mistake an unstated field for a record that does not say. Where a declaration states
neither, the record SHALL state the account and the group the plan defaults to, which SHALL be the
superuser's.

Only the fields a declaration actually stated SHALL be inputs to the entry's key. An entry whose
declarations state no ownership SHALL therefore carry the key it carried before a configuration
file's record could state one, and an entry that states an ownership SHALL carry a different key,
because it asks for a different file on the machine.

An owner or a group whose value fails its type SHALL be an error row naming the module, the file
and the type, and the failing value SHALL NOT be recorded: the defaulted record is what the plan
carries and what a realiser installs.

#### Scenario: A configuration file stating an owner and a group

- **WHEN** a module declares a configuration file stating an owner and a group beside its mode
- **THEN** the entry's record of that file SHALL state all three
- **AND** the entry's key SHALL differ from the key of the same deployment with the ownership
  omitted

#### Scenario: A configuration file stating no ownership

- **WHEN** a module declares a configuration file stating only a mode, a reload list and a recipe
- **THEN** the record SHALL state the superuser as both the owner and the group
- **AND** the record SHALL state them as fields rather than omitting them

#### Scenario: Only the ownership stated enters the key

- **WHEN** a deployment whose configuration files state no ownership is planned
- **THEN** every entry's key SHALL be the key that deployment had before the record could carry an
  ownership
- **AND** adding a group to one file SHALL move that entry's key and no other entry's key

#### Scenario: An ownership that fails its type

- **WHEN** a module declares a configuration file whose owner is not an account name
- **THEN** the planner SHALL emit an error row naming the module, the file and the type
- **AND** the record SHALL state the defaulted owner rather than the failing value

### Requirement: A unit that cannot open a configuration file its entry shows it is a row

A configuration file's record SHALL be read against the account each unit of its own entry runs as,
and a unit that could not open the file SHALL be an error row naming the unit, the account, the
file and the record it is shown at. The comparison SHALL be the one the planner already makes for a
delivered value a consumer declared a read of: the owner bit admits the account that owns the file,
the group bit admits an account whose unit declares that group, and the world bit admits any
account.

The row SHALL be reported whether or not any confinement profile is involved, because a service
whose units run under no profile is still a service whose units fail to start. A unit declaring no
account SHALL earn no row, the account it runs as then being the superuser's.

#### Scenario: A unit that cannot open its own configuration file

- **WHEN** an entry declares a configuration file the superuser alone may read and a unit of that
  entry runs as another account
- **THEN** the planner SHALL emit an error row naming the unit, the account, the file and its record
- **AND** the resolution SHALL name both stating an ownership the unit admits and running the unit
  as the account the file names

#### Scenario: A unit admitted by the file's group

- **WHEN** an entry declares a configuration file readable by its group and a unit of that entry
  declares that group
- **THEN** the planner SHALL emit no row for that file
- **AND** the record SHALL state the group the unit was admitted by

#### Scenario: A unit that declares no account

- **WHEN** an entry declares a configuration file the superuser alone may read and its units
  declare no account
- **THEN** the planner SHALL emit no row for that file

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
