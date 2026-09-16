# planner/diagnostics Specification

## Purpose
Defines evaluation as total: a plan and a table of problems come out together, no check aborts the pass, and every refusal is a record a user interface can draw and a command line can filter. This is the property that lets forty instances with two mistakes render as forty instances with two marks rather than as one error message.

## Requirements

### Requirement: Evaluation returns a plan and a diagnostics table, always both

The library's entry point SHALL return both a plan and a diagnostics table for every input it is given, including inputs carrying authoring mistakes. It SHALL NOT return a plan alone and SHALL NOT return diagnostics alone.

#### Scenario: A deployment with one bad instance

- **WHEN** a deployment declares more than one instance and one of them carries a mistake that produces an error row
- **THEN** the result SHALL contain plan entries for the instances that are correct
- **AND** the diagnostics table SHALL contain the row for the one that is not

#### Scenario: A deployment with no mistakes

- **WHEN** a deployment produces no rows at all
- **THEN** the result SHALL still contain a diagnostics table
- **AND** that table SHALL be empty rather than absent

### Requirement: No evaluation path raises

Forcing the whole result, including every plan entry, every export value and every diagnostic
record, SHALL NOT raise. The library SHALL NOT call any Nix builtin whose failure mode is to raise
in place of returning a value, and SHALL use the type library's verification entry point rather
than its assertion entry point.

A layer above the library MAY raise, and SHALL raise only for a condition an error row already
reported. A refusal about a fact the plan carries SHALL be an error row from the planner. A refusal
about a fact the realisation statement carries SHALL be an error row from the deployment build. A
realiser SHALL refuse only conditions one of those two reported, and its refusal SHALL remain as the
answer a caller reaching the realiser directly receives. A deployment the planner reports as
applicable, realised under a statement the deployment build accepted, SHALL therefore be realised
rather than refused.

#### Scenario: Every authoring mistake at once

- **WHEN** a deployment carries an unwired slot, a secret published as a value, a keyset violation,
  an arity violation and an interface mismatch simultaneously
- **THEN** deeply forcing the result SHALL succeed
- **AND** the diagnostics table SHALL contain one row per mistake

#### Scenario: A realiser refuses a condition no row reports

- **WHEN** a realiser gains a refusal that neither the planner nor the deployment build reports as
  an error row
- **THEN** the test suite SHALL fail
- **AND** the failure SHALL name the refusal and the layer that owes the row

#### Scenario: An applicable deployment is realised without a raise

- **WHEN** every placed entry of a deployment the planner reports as applicable is realised under a
  statement the deployment build accepted
- **THEN** each entry SHALL be read into an artifact
- **AND** no realiser SHALL raise

#### Scenario: A unit value no unit file has a line for

- **WHEN** a unit's environment carries a value containing a line break
- **THEN** the planner SHALL report an error row naming the entry, the unit and the variable
- **AND** the deployment SHALL be reported as inapplicable

#### Scenario: A declared closure root is not a store path

- **WHEN** an implementation declares a closure root that is not a path under the store directory
  the plan records
- **THEN** the planner SHALL report an error row naming the entry and the root
- **AND** the row SHALL name the store directory the plan was read against

#### Scenario: A declared closure root arrives by delivery

- **WHEN** an implementation declares a closure root that the plan also records as a delivered
  reference
- **THEN** the planner SHALL report an error row naming the entry and the root
- **AND** the row SHALL say that the bytes reach the units from the machine rather than from a
  closure

#### Scenario: A raising helper is introduced

- **WHEN** any library source file calls the type library's assertion entry point or a raise builtin
- **THEN** the test suite SHALL fail
- **AND** the failure SHALL name the file and the call

#### Scenario: A module's own code raises a catchable error

- **WHEN** a module under evaluation raises a catchable error inside its receiving half
- **THEN** the planner SHALL record an error row naming that module
- **AND** the rest of the plan SHALL still be produced

#### Scenario: A module's own code raises an uncatchable error

- **WHEN** a module under evaluation fails in a way the interpreter does not let a caller catch
- **THEN** the failure MAY propagate
- **AND** the library SHALL document which failures fall into this class rather than claiming to contain them

### Requirement: A diagnostic record has a fixed shape

Every diagnostic SHALL be a record carrying a stable identifier for its kind, the subject it is about, a severity, a one-line message, the evidence that produced it and the resolution its author is expected to apply. The subject SHALL be a plan key, a file path relative to the deployment root, or an issue identifier.

#### Scenario: Two runs over one input

- **WHEN** the same input is evaluated twice
- **THEN** the diagnostics tables SHALL be equal, including row order
- **AND** the identifiers SHALL be equal

#### Scenario: A row carries its resolution

- **WHEN** any row is produced
- **THEN** it SHALL carry a resolution line describing an edit a person can make
- **AND** the resolution SHALL name the file or the command rather than restating the problem

### Requirement: Severity decides the apply and not the evaluation

A diagnostic SHALL carry exactly one of two severities. An error SHALL block an apply. A warning SHALL NOT block an apply. Neither SHALL stop evaluation, and neither SHALL remove a plan entry that would otherwise exist.

#### Scenario: An error blocks the apply

- **WHEN** the diagnostics table contains at least one error
- **THEN** the result SHALL report that the plan is not applicable
- **AND** the plan SHALL still be readable in full

#### Scenario: A warning does not block the apply

- **WHEN** the diagnostics table contains warnings and no errors
- **THEN** the result SHALL report that the plan is applicable

#### Scenario: A module author cannot set a severity

- **WHEN** a module attempts to declare the severity of a row the planner produces
- **THEN** the declaration SHALL have no effect on that row's severity
- **AND** the planner SHALL emit a warning row naming the attempt

### Requirement: Rows render to the committed text format

The library SHALL render a diagnostics table to the row format the example folders already use, so that a rendered table can be compared against a committed file. Rendering SHALL be a function of the table alone, and SHALL NOT read the deployment again.

#### Scenario: Rendering the folder's own rows

- **WHEN** the minimal-typed-edge deployment is evaluated and its table rendered
- **THEN** the output SHALL contain one row per row in the committed diagnostics file for that deployment
- **AND** each rendered row SHALL carry the same subject, severity and message as the committed one

#### Scenario: Rendering is stable under unrelated change

- **WHEN** a deployment gains an instance that produces no rows
- **THEN** the rendered output SHALL be unchanged

### Requirement: A row originates in the library or in a guarded interface fold

Every diagnostics row SHALL be produced by the planner. A module SHALL have exactly one channel
through which it can refuse something another module supplied: the fold of an interface it declares,
applied under the planner's guard. For such a refusal the module SHALL supply text only, and the
planner SHALL supply the row's identifier, its subject and its severity.

A module SHALL NOT declare the severity of a row. An implementation SHALL NOT carry a field through
which it returns rows: a key an implementation is not defined to return SHALL be reported as an
unknown implementation key, and the report SHALL name the fold as the place a refusal belongs.

#### Scenario: A module declares a severity

- **WHEN** a module's declaration carries a severity
- **THEN** the planner SHALL read and discard it, and SHALL emit a warning row saying so
- **AND** every other row the planner produced for that module SHALL keep the severity the planner
  gave it

#### Scenario: An implementation returns a refusals field

- **WHEN** an implementation returns a field intended to carry refusals
- **THEN** the planner SHALL emit an error row naming that key as one an implementation does not
  return
- **AND** the row SHALL name the interface fold as where a refusal of another module's value belongs

#### Scenario: A fold refuses a provider

- **WHEN** an interface's fold refuses a provider's value and states why
- **THEN** the row SHALL carry the planner's identifier, the consuming entry as its subject and the
  planner's severity
- **AND** the row SHALL carry the fold author's own message

#### Scenario: One bad provider read by two consumers

- **WHEN** two consuming entries read a set containing the same refused provider
- **THEN** the planner SHALL emit one row per consuming entry, each naming its own subject
- **AND** neither row SHALL be dropped as a duplicate of the other

#### Scenario: A module raises outside a fold

- **WHEN** a module's own expression raises a catchable error anywhere other than a fold
- **THEN** the planner SHALL emit the row it already emits for a raising module, naming what was
  being forced
- **AND** the module's own text SHALL NOT become the row's message

### Requirement: One row is one line, whatever it names

The library SHALL export the constructor that builds a row, so that every producer of a row builds
it the same way, and SHALL NOT require a producer outside the library to write the six fields by
hand. Every field of a row a reader is shown - its subject as well as its message, its evidence and
its resolution - SHALL render as one line, whatever a deployment, a module or an interface
interpolated into it, so a rendered table has one line per field of one row and a reader of the
rendered table cannot be shown a row that was never produced.

A line break SHALL mean every character the library counts as one, the carriage return as well as
the newline, and one definition SHALL serve both the scan that asks whether a value carries a line
break and the repair that removes one. A refusal a module states through the one channel it has SHALL
therefore be unable to rewrite the subject, the severity or the message a reader is shown, whatever
text it carries.

#### Scenario: A row is built outside the library

- **WHEN** a layer above the library produces a row
- **THEN** the row SHALL be built by the library's own constructor
- **AND** it SHALL carry the same six fields, in the same shape, as a row the library produced

#### Scenario: A member name carries a line break

- **WHEN** a row names a deployment value that carries a line break
- **THEN** the rendered table SHALL still show one line for that row's message
- **AND** the row SHALL still name the value

#### Scenario: A subject carrying a line break renders one line per row

- **WHEN** a deployment names an instance with a name carrying a line break and the row about it is
  subjected to that instance's plan key
- **THEN** the rendered table SHALL carry one block per row and one line per field of it
- **AND** the row SHALL still name the declaration

#### Scenario: A fold refusal cannot carry a carriage return

- **WHEN** an interface's fold refuses a value with text carrying a carriage return
- **THEN** the row the planner builds from that refusal SHALL carry no line break in any field
- **AND** the rendered table SHALL show no line the planner did not produce

### Requirement: A deployment's own declarations are read the way a module's are

The half of a declaration the deployment writes - an instance, a wire, a placement, a machine, an
exposure - SHALL be read with the same tolerance as the half a module writes. A value of the wrong
type, or an absent key the reading needs, SHALL be a row naming the declaration and the field, and
the rest of the deployment SHALL still be read.

No malformed value a deployment can write SHALL end the evaluation, whether or not any module is
well formed.

#### Scenario: An instance names no module

- **WHEN** an instance is declared with no module
- **THEN** the planner SHALL produce a row naming that instance
- **AND** SHALL still plan every other instance

#### Scenario: A declaration carries the wrong type

- **WHEN** a wire, an exposure, a placement, a machine's tags or a machine's system is declared as
  something other than the shape the reading needs
- **THEN** each SHALL be a row naming the declaration and the field
- **AND** the planner SHALL still produce its table and its plan

### Requirement: An export's atom is checked where the export is used

An export SHALL be checked for the atom that types it wherever the planner uses that atom, not only
where the export is absent or unpublished. An export declaring no atom, or an atom that is not one,
SHALL be a row naming the interface and the export.

The check SHALL be reachable on the path a published export takes, so that the row can fire for a
capability a deployment actually reads.

#### Scenario: A published export declares no atom

- **WHEN** an interface declares an export with no atom and a capability publishes it
- **THEN** the planner SHALL produce a row naming the interface and the export
- **AND** the evaluation SHALL NOT end

#### Scenario: An export's atom is not an atom

- **WHEN** an export's atom is a value of some other kind
- **THEN** the planner SHALL produce a row naming the interface and the export

### Requirement: A refusal cannot break the table it travels to

The channel a module's refusal travels through SHALL accept only a refusal the planner can render,
and SHALL report anything else as a row. A refusal that is not text, or that is empty, SHALL be a row
naming the interface and what it refused, and SHALL NOT end the evaluation or produce a row with no
message.

#### Scenario: A refusal is not text

- **WHEN** a fold refuses a value with something other than text
- **THEN** the planner SHALL produce a row naming the interface and the slot
- **AND** the evaluation SHALL NOT end

#### Scenario: A refusal carries no reason

- **WHEN** a fold refuses a value with nothing
- **THEN** the row SHALL name the interface and the slot
- **AND** SHALL NOT be rendered with an empty message

### Requirement: A row about an interface does not depend on attribution

Attribution SHALL NOT decide whether an interface is checked. Every row an interface can earn - about
its declared identity, about its fold, about its exports - SHALL be reachable for an interface a
deployment did not list, because an interface absent from that list is still an interface.

#### Scenario: An unattributed interface declares a malformed identity

- **WHEN** two modules import an interface whose declared identity is malformed
- **AND** the deployment lists that interface nowhere
- **THEN** the planner SHALL produce the same row it would produce for a listed one

#### Scenario: An unattributed interface declares a fold that is not a function

- **WHEN** an interface a deployment did not list declares a fold that is not a function
- **THEN** the planner SHALL produce a row naming the file that declared it

### Requirement: The exclusion table no longer carries the member-cuts row

`member cuts` SHALL NOT be a row of the exclusion table, and `members.<name>.enable` and a
member-scoped wire SHALL NOT earn an exclusion row: they are constructs this subset carries. The
remaining rows SHALL be `locality`, `lifecycle`, `placement.pick/strategy/allocation`, `externals`,
the collect family and the runtime plane, and every rule the refusals-by-subtraction requirement
states SHALL continue to hold over them unchanged.

A row leaving the table SHALL leave three places at once: the table the library exports, the
exclusion suite that asserts one refusal per row, and the table published in the worked fixture's
README. The suite SHALL compare its own count against that README, so that the three cannot be
edited apart.

#### Scenario: A deployment cutting a member earns no exclusion row

- **WHEN** a deployment writes `members.<name>.enable = false`
- **THEN** the planner SHALL emit no exclusion row
- **AND** the member SHALL be cut

#### Scenario: A member-scoped wire earns no exclusion row

- **WHEN** a deployment writes a member-scoped wire for a slot a cut opened
- **THEN** the planner SHALL emit no exclusion row
- **AND** the slot SHALL resolve to the capability the wire names

#### Scenario: The table, the suite and the fixture's README agree

- **WHEN** the exclusion table is read as data
- **THEN** its rows SHALL be exactly those the worked fixture's README tables
- **AND** the exclusion suite SHALL assert one refusal per row
- **AND** neither SHALL name `member cuts`

#### Scenario: The six remaining rows are still refused

- **WHEN** a deployment or a module writes a key naming one of the six remaining constructs
- **THEN** the planner SHALL emit that construct's exclusion row naming the trigger
- **AND** SHALL NOT emit an unknown-key row for it

### Requirement: The rows a cut and a single-consumer capability can earn

The rows this construct adds SHALL each name the declaration to edit, the way every other row does:

- A wire the deployment writes for a slot the module binds to a kept member SHALL name the slot, the
  member it is bound to, and the file that wrote the wire; its resolution SHALL name both ways out -
  cut the member, or delete the wire.
- A `placement`, a `settings` namespace or a consuming wire naming a member the instance cut SHALL
  name the member and the cut; its resolution SHALL name both ways out - keep the member, or delete
  the reference.
- A second consumer of a capability declaring `consumers = "one"` SHALL name the capability, its
  providing instance and both consuming slots, and SHALL be produced once for the capability rather
  than once per consumer.

A slot opened by a cut and left unwired SHALL earn the existing unwired-slot row rather than a row of
its own: the condition is identical, and a second identifier for it would make one fault report two
sentences.

#### Scenario: Each new row names a declaration to edit

- **WHEN** each of the three conditions is produced
- **THEN** each row SHALL name the file and the declaration to change
- **AND** each resolution SHALL name both ways out where two exist

#### Scenario: A cut with an unwired slot reports the existing row

- **WHEN** a cut opens a slot the deployment does not wire
- **THEN** the row SHALL be the unwired-slot row
- **AND** no second row SHALL describe the same absence

#### Scenario: Two consumers report one row

- **WHEN** two slots wire one single-consumer capability
- **THEN** the table SHALL carry exactly one row for it
- **AND** the row SHALL name both slots

### Requirement: A unit that cannot open a value it reads is an error row

Where an entry declares a read of an export backed by a generated file that will be delivered, and a
unit of that entry runs as an account the file's recorded ownership and mode do not admit, the
planner SHALL emit an error row naming the reading entry, the unit, the account the unit runs as, the
slot, the export and the ownership and mode the file records.

The comparison SHALL be made from the plan alone: the file's `owner`, `group` and `mode`, and the
unit's `user`. A unit that declares no user runs as the machine's privileged account and SHALL NOT
earn the row. A file whose mode admits a reader other than its owner - by group where the unit's
declared groups include the file's, or by the mode's world bits - SHALL NOT earn the row.

The row SHALL be an error, because the outcome it predicts is a unit that cannot start, and its
resolution SHALL name both ways out: deliver the file at an ownership the unit's account admits, or
run the unit as the account the file names.

Producing the row SHALL NOT depend on which realiser reads the entry. A realiser whose confinement
imposes a different account is a second, separate condition reported by the layer that holds the
realisation statement.

#### Scenario: A unit running as an account reads a root-only value

- **WHEN** an entry's unit declares `user` and the entry declares a read of an export backed by a
  file recorded as owned by `root` at mode `0400`
- **THEN** the planner SHALL emit an error row naming the entry, the unit, the account, the slot, the
  export and the file's ownership and mode
- **AND** the deployment SHALL be inapplicable

#### Scenario: A unit running as the account the file names

- **WHEN** the file records that account as its `owner`
- **THEN** the planner SHALL emit no row
- **AND** the plan SHALL record the read

#### Scenario: A unit reading a group-readable value

- **WHEN** the file records a `group` the unit's declared groups include, at a mode with group read
- **THEN** the planner SHALL emit no row

#### Scenario: A privileged unit reads a root-only value

- **WHEN** an entry's unit declares no `user` and reads a root-only value
- **THEN** the planner SHALL emit no row

#### Scenario: One unit of two cannot open the value

- **WHEN** one unit of an entry runs as an account the file does not admit and a second unit of the
  same entry runs privileged
- **THEN** the diagnostics SHALL carry exactly one row, naming the first unit
- **AND** the plan SHALL still record the entry and both units

### Requirement: A host resource two entries of one machine both claim is a row

The planner SHALL report a row when two entries placed on one machine both claim one host resource.
Three claims SHALL be read, and each SHALL be read from what the plan already records or from what
the declaration states, so that no plan field is introduced by this rule:

- a host path a configuration file is written to, which SHALL be an error;
- a port claimed on a protocol and an address that another entry's claim overlaps, which SHALL be an
  error;
- a unit directory name a unit extension application records under `runtimeDirectory`,
  `stateDirectory` or `cacheDirectory`, which SHALL be a warning.

An error SHALL block an apply, because two entries writing one file is two renderings of one file and
two entries claiming one port is a daemon that cannot bind. The directory claim SHALL be a warning,
because two entries sharing one state directory is a handoff a deployment may intend while two
entries sharing one runtime directory loses one of their records at the next restart: the row SHALL
name it and the deployment SHALL still build.

Two port claims of one machine SHALL collide when they claim one number and both their protocols and
their addresses overlap. Two protocols SHALL overlap when they are the same protocol or when either
claim states none. Two addresses SHALL overlap when they are the same address or when either claim
states none, the absence being every address of the machine. Two claims of one number that bind two
different addresses SHALL NOT collide, because two listeners on two addresses of one machine is a
deployment that runs.

Because overlap is not equality, one claim MAY take part in more than one collision, and each
collision SHALL be one row naming its own claimants, its own protocol and its own address. Claims
that state one protocol and one address SHALL be one collision however many claimants they have, so
that a number claimed by three entries is one row and not three.

A row SHALL name both entries, the machine, and the resource they both claim, and its resolution
SHALL name deriving the resource from the entry's own identity. The row SHALL be reported once for
one collision rather than once per claimant, and its subject SHALL be the first of the colliding plan
keys in the plan's own order, so that two evaluations of one deployment render one table byte for
byte.

Reading a unit extension's directory fields by name SHALL NOT name a realiser: the field names are
the ones a realiser's directive table and this rule both read, which is how the library already reads
a unit's declared groups.

#### Scenario: Two entries on one machine write one host path

- **WHEN** two entries placed on one machine each declare a configuration file at the same host path
- **THEN** the planner SHALL emit an error row naming both entries, the machine and the path
- **AND** the row SHALL appear once in the table

#### Scenario: Two entries on one machine claim one port

- **WHEN** two entries placed on one machine each claim the same port number with the same protocol
- **THEN** the planner SHALL emit an error row naming both entries, the machine, the protocol and the
  port

#### Scenario: One claim states a protocol and the other states none

- **WHEN** two entries placed on one machine claim one number and only one of them states a protocol
- **THEN** the planner SHALL emit the error row for that number
- **AND** two entries stating two different protocols of the domain on that number SHALL produce no
  row

#### Scenario: Two claims of one number bind two addresses

- **WHEN** two entries placed on one machine claim one number and one protocol and each states a
  different address
- **THEN** the planner SHALL emit no collision row
- **AND** the deployment SHALL be applicable

#### Scenario: A wildcard claim and a specific claim of one number

- **WHEN** two entries placed on one machine claim one number and one protocol and only one of them
  states an address
- **THEN** the planner SHALL emit an error row naming both entries, the number and the address the
  contention is on

#### Scenario: Two entries on one machine share one unit directory

- **WHEN** two entries placed on one machine each apply a unit extension recording the same runtime
  directory name
- **THEN** the planner SHALL emit a warning row naming both entries, the machine and the directory
- **AND** the table SHALL carry no error on account of it

#### Scenario: One member placed on two machines claims its path on each

- **WHEN** one member is placed on two machines and declares one configuration file
- **THEN** the planner SHALL emit no collision row
- **AND** each entry SHALL record that file

#### Scenario: Two units of one entry share its directory

- **WHEN** two units of one entry apply a unit extension recording the same directory name
- **THEN** the planner SHALL emit no collision row, the claim being the entry's own

#### Scenario: A collision is reported once and names both entries

- **WHEN** three entries placed on one machine all claim one number on one protocol and one address
- **THEN** the table SHALL carry one row for that port
- **AND** the row SHALL name all three plan keys and be subjected to the first of them in the plan's
  order

### Requirement: A declaration a row cannot make safe is left out of every later stratum

Where a declaration's absence would be read by a module's own expression through a path the planner
cannot catch - selecting an attribute that is not there, which is neither a raise nor a failed
assertion and which no guard recovers - the planner SHALL NOT rely on reporting it alone.
It SHALL report it as an error row and SHALL additionally leave the declaration out of everything a
later stratum derives, in the stratum the row is produced in and before any plan key exists, so that
no later evaluation can reach the uncatchable path.

A row SHALL still be produced in every such case, and it SHALL name the declaration to edit rather
than the module that would have read it: the module is correct and the declaration is not.

The rule SHALL apply to a machine a placement selected whose target is incomplete, as it already
applies to a name carrying a separator the plan key grammar splits on. The row SHALL be reported for
the declaration as the deployment wrote it, whether or not anything downstream of the drop survives,
so that a check which removes its own subject does not thereby remove its own row. Where such a drop
leaves a later check with nothing to complain about, that later check SHALL NOT produce a second row
about the same mistake.

#### Scenario: The row outlives the placements it dropped

- **WHEN** every placement a machine was selected by is dropped because its target is incomplete
- **THEN** the table SHALL still carry the error row naming that machine and the registry file
- **AND** the row SHALL state how many entries the deployment placed on it

#### Scenario: One row for one machine however many placements selected it

- **WHEN** three members of two instances are all placed on one machine that declares no address
- **THEN** the table SHALL carry exactly one row about that machine

#### Scenario: The row names the keys the machine did not declare

- **WHEN** a selected machine declares neither an address nor a service manager
- **THEN** the row SHALL name both keys and the registry file
- **AND** its resolution SHALL name the edit to make in that file

#### Scenario: A dropped placement produces no module row

- **WHEN** an implementation that reads its own machine's address is placed on a machine that
  declares none
- **THEN** the table SHALL carry the registry's row and no row about the module
- **AND** deeply forcing the plan and the table SHALL succeed

### Requirement: A resource a machine reserves and an entry claims earns that resource's own row

A host resource a machine states that it already holds and a placed entry on that machine claims
SHALL earn the row that resource's kind already has, with no identifier of its own: the reservation
is a claimant like any other, and a reader learns which claimants collided from the row's text rather
than from two families of identifier. A reserved port a placed entry claims with the same protocol
SHALL therefore be the same error as two entries claiming it, and a reserved host path a placed
entry's configuration file is written to SHALL be the same error as two entries writing it.

The machine SHALL be named in the row by the key its own plan record carries, which is distinct from
every entry key by construction and is a valid row subject. The machine's key SHALL be ordered with
the entry keys by the one rule the collision row already follows - a row is reported once for one
collision and is subjected to the first of the colliding plan keys in the plan's order - so the
machine is the subject exactly when it sorts first, and is a named claimant of the row either way. A
row SHALL only ever name a machine whose record the plan carries, so that its subject addresses
something a reader can find in the plan.

The row's resolution SHALL name both declarations a reader can edit: the claim the entry declares and
the reservation the registry declares. Where the claimants are two entries and no reservation, the
resolution SHALL be the one that requirement already states.

A reservation SHALL earn no row on its own. A reserved resource no placed entry claims is a
statement the deployment agrees with, and a reservation on a machine no placement selects is a
statement about a machine that runs nothing: both SHALL leave the table as it was. The planner SHALL
NOT check a reservation against the machine, so a reserved path that does not exist and a reserved
port nothing listens on are not rows either.

A reservation SHALL collide only where it can be compared. A port SHALL compare by its protocol and
its number together, so a reserved port and a claim of the same number on another protocol are two
resources and no row, which is the rule the entry-to-entry comparison already makes. A reservation
SHALL NOT be compared against a unit directory name a unit extension records, that name being in the
service manager's own namespace rather than a host path the plan states.

#### Scenario: A machine reserves a port an entry claims

- **WHEN** a machine states that it already holds a port with a protocol and an entry placed on that
  machine claims the same port with the same protocol
- **THEN** the planner SHALL emit the error row a port claimed twice earns, naming the machine, the
  entry, the protocol and the port
- **AND** the row SHALL appear once in the table
- **AND** its resolution SHALL name the entry's claim and the machine's reservation

#### Scenario: A machine reserves a port nothing claims

- **WHEN** a machine states that it already holds a port and no entry placed on it claims that port
- **THEN** the planner SHALL emit no collision row
- **AND** the deployment SHALL be applicable

#### Scenario: A machine reserves a path an entry writes

- **WHEN** a machine states that it already holds a host path and an entry placed on that machine
  declares a configuration file at that path
- **THEN** the planner SHALL emit the error row a host path claimed twice earns, naming the machine,
  the entry and the path

#### Scenario: A reservation on a machine no placement selects

- **WHEN** a machine states that it already holds a port and a path, and no placement selects that
  machine
- **THEN** the planner SHALL emit no collision row about it
- **AND** no row of the table SHALL be subjected to that machine

#### Scenario: A reserved port and a claim on another protocol

- **WHEN** a machine states that it already holds a port on one protocol and an entry placed on it
  claims the same number on another protocol
- **THEN** the planner SHALL emit no collision row, the two being two resources

#### Scenario: A machine and two entries claim one port

- **WHEN** a machine states that it already holds a port and two entries placed on it both claim it
  with that protocol
- **THEN** the table SHALL carry one row for that port
- **AND** the row SHALL name the machine and both entries
- **AND** its subject SHALL be the first of those three plan keys in the plan's order

### Requirement: A port claim outside the vocabulary's domains is a row

The planner SHALL report a row for each part of a port claim that falls outside what the vocabulary
admits, and each row SHALL name the claim, the module that wrote it and what the field may take:

- a number that is not a port, which SHALL be an error and SHALL leave the claim unrecorded;
- a protocol outside the named domain, which SHALL be an error and SHALL leave the number recorded
  with no protocol;
- an address that is not an address, which SHALL be an error and SHALL leave the number recorded
  with no address.

A row about a protocol SHALL name every value the domain admits, the way a row about any other
enumerated field of this vocabulary does, so that the refusal states the answer rather than only the
mistake.

The wildcard SHALL NOT be spellable. An address whose text is a wildcard SHALL be refused with a
resolution naming the absence of the field as the way to say it, because two spellings of one
reading is the defect that let a number be claimed twice.

A refused protocol or address SHALL widen the claim rather than narrow it: the claim SHALL then be
compared as though the field had not been stated, so a deployment carrying one of these rows is
never checked less than a deployment carrying none.

#### Scenario: A protocol outside the domain

- **WHEN** a module claims a port with a protocol the domain does not admit
- **THEN** the planner SHALL emit an error row naming the claim, the value and every value the
  domain admits

#### Scenario: A refused protocol collides with every protocol

- **WHEN** one entry claims a number with a protocol outside the domain and a second entry on the
  same machine claims the same number with a protocol inside it
- **THEN** the planner SHALL emit the claimed-twice error beside the protocol row

#### Scenario: An address spelled as the wildcard

- **WHEN** a module states an address whose text means every address of the machine
- **THEN** the planner SHALL emit an error row whose resolution names omitting the field
- **AND** the number SHALL still be recorded

#### Scenario: An address outside the address grammar

- **WHEN** a module states an address that is not a string, or is a string the grammar refuses
- **THEN** the planner SHALL emit an error row naming the claim and the grammar
- **AND** the claim SHALL be compared as though it bound every address of the machine

### Requirement: A value a unit file cannot carry is a row for every field the file carries

A unit file is line-oriented, so a line break in a value is a fact the file cannot carry, and the
planner SHALL report one error row for such a value wherever the unit record holds it. The rule
SHALL hold for every string the record carries at any depth - a plain field, an element of a list
field, a value of an attribute-set field, and a field of an extension application - and SHALL NOT be
written against an enumerated list of fields, because a field added to the vocabulary or a field an
extension author declares is then covered by existing rather than by a second edit.

The row SHALL name the entry, the unit and the path of the field the value sits at, so that a reader
who wrote a newline into a command is not told about an environment variable. One identifier SHALL
cover every field, because a reader meeting two identifiers for one class of defect has to learn
which field belongs to which, and a table carrying both would report one mistake twice for a value
that appears in two fields.

A value carrying a space, a quote or a backslash SHALL NOT be a row: those are facts a unit file can
carry, and carrying them is the renderer's work.

A value whose own field type already refuses a line break SHALL be reported by that type and by this
rule nowhere, so that one fact earns one row. A field the planner withheld from the record for any
other reason SHALL likewise earn no row from this rule: the rule is about what a file will be
rendered from, and a withheld value is rendered from nothing.

#### Scenario: A newline in a command is a row

- **WHEN** a unit declares a command whose value contains a line break
- **THEN** the planner SHALL emit one error row naming the entry, the unit and the field
- **AND** the deployment SHALL NOT be applicable
- **AND** the entry SHALL still be read, with the rest of its units recorded

#### Scenario: A newline in an extension value is the same row

- **WHEN** a unit applies an extension whose field value contains a line break, at any depth of that
  value
- **THEN** the planner SHALL emit the same error row, naming the extension and the field
- **AND** the row's identifier SHALL be the one an environment value with a line break earns

#### Scenario: A newline in a user name is reported once by its type

- **WHEN** a unit declares a user name whose value contains a line break
- **THEN** the planner SHALL report the field's own type failure
- **AND** SHALL emit no second row about the line break
- **AND** the value SHALL NOT be recorded

#### Scenario: A value carrying a space and a quote is no row

- **WHEN** a unit declares a command and an environment value each carrying a space, a double quote
  and a backslash
- **THEN** the planner SHALL emit no row about them
- **AND** both values SHALL be recorded as the bytes the module wrote

### Requirement: A configuration file's host path is held to the grammar a rendered step can carry

A host path a configuration file is written to SHALL be held to the grammar of one word a rendered
shell step can carry, and a path outside it SHALL be an error row naming the entry, the path and
what the grammar admits. The check SHALL be made by the library, so that every realiser and every
plan reader inherits it and none of them has to state it again.

The grammar SHALL be the one the other rendered step of this repository already states for the paths
and addresses it renders, and that grammar SHALL have exactly one home: the reading that renders a
delivery step SHALL read it rather than restate it, so that a widened grammar cannot admit a
character in one rendered script and refuse it in another.

A refused path SHALL NOT be recorded on the entry. A path the library has just said no rendered step
can carry is not a fact to hand a reader, and a reader may be handed a plan whose table it did not
read; the file is therefore left out of the record the way a name carrying a key separator is left
out of every key it would have entered. Nothing else about the entry SHALL be withheld: its units,
its closure and its other configuration files SHALL be recorded as they were.

A row SHALL be produced whether the path was written by a deployment or derived inside an
implementation, because both reach the same rendered script.

#### Scenario: A newline in a configuration file path is a row

- **WHEN** an implementation declares a configuration file whose host path contains a line break
- **THEN** the planner SHALL emit an error row naming the entry, the path and what the grammar
  admits
- **AND** the entry SHALL record no configuration file at that path

#### Scenario: A configuration file path carrying a shell metacharacter is a row

- **WHEN** an implementation declares a configuration file whose host path contains a command
  substitution
- **THEN** the planner SHALL emit the error row before anything is built
- **AND** the deployment SHALL NOT be applicable

#### Scenario: A configuration file path carrying a quote is a row

- **WHEN** an implementation declares a configuration file whose host path contains a double quote
- **THEN** the planner SHALL emit the error row
- **AND** the row SHALL name the path in a subject a rendered table can carry

#### Scenario: A refused path is left out of the entry record

- **WHEN** one of an entry's two configuration files is declared at a refused path
- **THEN** the entry SHALL record the other file and its units unchanged
- **AND** the refused path SHALL appear in no field of the plan

#### Scenario: One grammar answers for both rendered steps

- **WHEN** the grammar of a renderable word is widened or narrowed
- **THEN** the path a configuration file is written to and the path a delivery step renders SHALL be
  held to the same admitted characters
- **AND** neither reading SHALL carry a second statement of it

### Requirement: A record the reading indexes into is checked to be a record first

A declaration of the wrong shape SHALL be a diagnostics row and SHALL NOT end the evaluation. Every
value a module or a root writes that the reading indexes into - the declaration itself, a port claim,
a slot, a capability, a generator, a generated file's record, a pin, a unit, a configuration file -
SHALL be checked to be a record before it is indexed, and a value of another kind SHALL be one error
row naming the module file and the site inside it.

The check SHALL be a check and not a recovery. The library's recovery channel reports that something
raised and cannot catch an index into a value of the wrong kind, so a reading that indexes first and
recovers afterwards SHALL NOT be taken to satisfy this requirement.

A malformed value SHALL contribute nothing to the plan: a port claim that is not a record claims no
port, a slot that is not a record declares no slot, a capability that is not a record publishes
nothing, and none of the three SHALL be defaulted into existence. A malformed value SHALL NOT be
dropped silently either, and SHALL NOT earn a row about some other condition that its absence would
have produced.

One identifier SHALL serve the whole family a declaration writes, because the condition is one, and
the row SHALL name which site it is about rather than leaving that to the identifier. The half an
implementation writes - a unit, a configuration file and the two records holding them - SHALL keep the
identifier it already earns for a value of the wrong kind, which is the row the fourth scenario below
holds the declaration half to, and SHALL name its site the same way.

#### Scenario: A port claim is not a record

- **WHEN** a module declares a port claim as a number
- **THEN** the planner SHALL emit one error row naming the module file and that claim
- **AND** the entry SHALL claim no port
- **AND** every other entry of the deployment SHALL still be planned

#### Scenario: A slot is not a record

- **WHEN** a module declares a slot of `uses` as something other than a record
- **THEN** the planner SHALL emit one error row naming the module file and that slot
- **AND** the member SHALL declare no such slot, so no wire for it is resolved
- **AND** every other entry of the deployment SHALL still be planned

#### Scenario: A capability is not a record

- **WHEN** a module declares a capability of `provides` as something other than a record
- **THEN** the planner SHALL emit one error row naming the module file and that capability
- **AND** the capability SHALL publish nothing and be addressable by no wire
- **AND** every other entry of the deployment SHALL still be planned

#### Scenario: A module returns something other than a record

- **WHEN** a module's declaration is a value of some other kind entirely
- **THEN** the planner SHALL emit one error row naming the module file
- **AND** the row SHALL be the row an implementation returning a value of the wrong kind already
  earns for the other half of the same module
- **AND** every other entry of the deployment SHALL still be planned

### Requirement: A module's own expression is forced under the planner's recovery

A module's declaration SHALL be forced under the same recovery its implementation already gets. A
module that raises a catchable error while computing its declaration SHALL be one `module-raised` row
naming the member, and the rest of the deployment SHALL still be read.

The recovery SHALL record the declaration as the empty record, so the entry degrades through the
existing `impl-missing` row rather than through an identifier invented for this case. Two rows for
one mistake is the intended table: the first names what raised and the second names what the entry
consequently declares none of.

A failure the interpreter does not let a caller catch SHALL still propagate, and the library SHALL
keep documenting that class rather than claiming to contain it.

#### Scenario: A module raises while computing its declaration

- **WHEN** a module raises a catchable error while computing its declaration, before any
  implementation of it is applied
- **THEN** the planner SHALL emit the `module-raised` row naming the member and what was being forced
- **AND** the table SHALL also carry `impl-missing` for that member
- **AND** every other entry of the deployment SHALL still be planned

### Requirement: Every value a declaration wrote is read for its kind

Every value a declaration wrote SHALL be read for its kind before the reading indexes into it,
coerces it, applies it or hashes it, and a value of another kind SHALL be one error row naming the
declaration and the site rather than the end of the evaluation. The rule SHALL cover the whole
surface a deployment, a root and a module write, not the record family a reading indexes into:

- a composing root's member container, which every reading below it indexes;
- a fragment of the recipe a rendered configuration file is assembled from, which the planner
  concatenates into bytes;
- a settings knob, whose resolved value reaches an entry's key as serialised text, so a knob of
  another kind ends the evaluation at the key rather than at the declaration it was written in;
- an implementation, which SHALL be recorded as none where it is not a function, so that the row a
  member with no implementation already earns is the whole answer and nothing applies the value;
- an implementation whose raise the planner's recovery already caught, which SHALL be forced once:
  no later reading of the same entry SHALL force it again outside the recovery that caught it,
  whatever order the readings are written in, and the row the recovery produced SHALL reach the
  table;
- an export carrying the marker of a generated file reference and not the rest of that record's
  fields;
- every value the planner's own entry point is handed - the machine registry, the instance table,
  the interface attribution and the store directory - and the answer a caller gives about which
  generated values exist.

A check SHALL be a check and not a recovery: the recovery channel reports that something raised and
catches neither an index into a value of the wrong kind nor a coercion of one, so a reading that
indexes first and recovers afterwards SHALL NOT be taken to satisfy this requirement.

A malformed value SHALL contribute nothing and SHALL NOT be defaulted into existence, and the
evaluation SHALL answer for the rest of the deployment: deeply forcing the plan, every entry's key
and the table SHALL succeed for every one of these declarations, and a table that is empty while a
key raises SHALL NOT be a result a caller can be handed.

#### Scenario: A root returns services of another kind

- **WHEN** a composing root returns its member container as a value of some other kind
- **THEN** the planner SHALL emit one error row naming that root
- **AND** deeply forcing the plan and the table SHALL succeed
- **AND** every other instance of the deployment SHALL still be planned

#### Scenario: A settings knob holds a function

- **WHEN** a deployment sets a knob of a placed member to a value no key can be derived from
- **THEN** the planner SHALL emit one error row naming the instance, the member and the knob
- **AND** the value SHALL NOT reach the entry's key
- **AND** forcing every key of the plan SHALL succeed and the deployment SHALL be reported as
  inapplicable

#### Scenario: An implementation that is not a function is recorded as none

- **WHEN** a module declares an implementation that is not a function
- **THEN** the planner SHALL record no implementation for that member and SHALL emit the row a
  member with none already earns
- **AND** nothing SHALL apply the declared value
- **AND** deeply forcing the result SHALL succeed

#### Scenario: A guarded implementation is forced once

- **WHEN** a module's implementation raises a catchable error and a later reading of the same entry
  asks that entry for its exports
- **THEN** the table SHALL carry the row the recovery produced
- **AND** no reading SHALL force the implementation outside that recovery
- **AND** deeply forcing the result SHALL succeed

#### Scenario: The planner is handed an argument of another kind

- **WHEN** the machine registry, the instance table, the interface attribution, the store directory
  or the answer about which generated values exist is a value of another kind
- **THEN** each SHALL be one error row naming the argument
- **AND** the planner SHALL still return both a plan and a table

### Requirement: The class the interpreter does not let a caller catch is named rather than claimed

Totality SHALL be claimed for every value a declaration wrote and SHALL NOT be claimed wider than
that. Exactly two conditions SHALL be stated as outside it, each because the interpreter offers a
caller no way to catch it:

- a module's own function signature refusing the argument record the planner hands it, the planner
  having no way to widen a signature it did not write and no way to catch the refusal;
- a module selecting an attribute of its own expression that is absent, which is neither a raise nor
  a failed assertion.

Each SHALL be documented as a failure that propagates, naming the kind of declaration that causes it
and the edit that removes it, rather than covered by a claim the library cannot keep. A module's
implementation SHALL accordingly carry a stated contract of accepting the arguments it does not name,
so that the argument record may gain a field without a module that ignores it ending an evaluation,
and that contract SHALL be part of what a module author is told rather than a convention a reader
discovers from a failure.

#### Scenario: An implementation accepts the arguments it does not name

- **WHEN** a module's implementation names some of the arguments it is handed and accepts the rest
- **THEN** the planner SHALL apply it whatever else the argument record carries
- **AND** a field added to that record later SHALL leave the module planning as it did

#### Scenario: A closed signature is named rather than contained

- **WHEN** a module's implementation names its arguments closed, or selects an absent attribute of
  its own expression
- **THEN** the failure MAY propagate
- **AND** the library's stated totality SHALL name that condition as outside it, with the contract a
  module is held to, rather than claiming to contain it

### Requirement: The table and the verdict survive an entry whose record raises

The diagnostics table and the applicability verdict SHALL be answerable for every input, including
an input one of whose plan records cannot be forced. Neither SHALL be computed by forcing a plan
record: the verdict SHALL be a function of the rows alone, and a row SHALL be reachable without the
entry it is about being forced. A deployment carrying a condition outside the stated totality SHALL
therefore still render the table that explains it, and the failure SHALL be confined to the plan
record holding the value it is about, so that a reader is told which declaration to edit rather than
handed a plan and a table that both end.

#### Scenario: A table is printable where one plan record raises

- **WHEN** one entry's plan record cannot be forced because a module read a value the planner cannot
  make safe
- **THEN** the table and the verdict SHALL still be answerable and SHALL render
- **AND** the table SHALL carry the row naming the declaration that caused it
- **AND** every other entry's record SHALL still be readable

#### Scenario: An unwired slot read by its own module leaves a table to print

- **WHEN** a module reads a slot nobody wired, so forcing that entry's own record ends in a failure
  the planner cannot catch
- **THEN** the table SHALL carry the row about the unwired slot
- **AND** the verdict SHALL report the deployment as inapplicable
- **AND** both SHALL be answerable without that entry's record being forced

### Requirement: A row's subject is the identity the plan already uses

A row's subject SHALL be a plan key the planner built, a path relative to the deployment root, or an
issue identifier, and the rule that accepts one SHALL be stated over those three rather than over the
characters they happen to contain. It SHALL NOT be an allowlist of characters narrower than the
grammar the names entering a key are held to: that grammar refuses the separators a key's own
structure uses and admits every other character, so a name the key grammar admits, the key the
planner built from it and a row subjected to that key are all legal, and a subject rule refusing the
key would turn a table carrying warnings and no error into a refusal to apply. A subject the rule
does refuse SHALL be reported as such, and the reporting SHALL NOT itself be an error that decides
applicability for a deployment whose own rows are warnings.

No repair of a subject SHALL turn two rows about two declarations into one row. Where a subject is
repaired, the repair SHALL NOT be what deduplication compares: two facts SHALL remain two rows even
where their repaired subjects agree, and a reader SHALL be told about the second declaration.

#### Scenario: A name the key grammar admits is not refused by the subject rule

- **WHEN** a deployment names an instance with a character the key grammar admits and earns one
  warning row and no error
- **THEN** the subject rule SHALL accept the plan key the planner built from that name
- **AND** the table SHALL carry that warning row and no row about the subject
- **AND** the deployment SHALL be reported as applicable

#### Scenario: Two module files sharing a basename keep two rows

- **WHEN** two members declared in two files whose names agree in their last component each earn the
  same kind of row
- **THEN** the table SHALL carry one row per member
- **AND** each row SHALL name the file its member was declared in
- **AND** neither row SHALL be dropped as a duplicate of the other

### Requirement: A row's severity is a closed domain

A row SHALL carry one of exactly the two severities the capability states, and the domain SHALL be
closed where a row is built rather than where a row is read. A value outside it SHALL be reported as
such, naming the producer and the value it carried, and SHALL NOT travel in the table as a severity
of its own.

A reading SHALL NOT be the thing that decides what an off-domain severity means: the fact that a row
carries a severity nobody declared SHALL NOT be inferable only by a reader comparing the value
against a spelling it knows, and such a row SHALL neither decide applicability by accident nor be
counted as a warning because it is not the error spelling. An off-domain severity SHALL NOT be a way
for a producer to put text a reader trusts into the table either: the row SHALL still render as one
line per field.

#### Scenario: A row severity is held to the stated domain

- **WHEN** a row is built with a severity outside the two the capability states
- **THEN** the planner SHALL report that value as such, naming the producer
- **AND** the row SHALL NOT be counted as a warning on the grounds that it is not the error spelling
- **AND** the rendered table SHALL carry one line per field of that row
