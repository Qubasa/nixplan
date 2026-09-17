<!--
A delta against `openspec/specs/operator/apply-command/spec.md`. Every requirement below is ADDED.
Three of that spec's requirements are load-bearing here and none of them is contradicted, so none is
restated:

- `A value is written at the ownership and mode its record states` (`:460`) and `A re-apply restores
  a value's ownership and mode` (`:498`) are about the plaintext, which this change leaves at the
  same path with the same record and the same discipline.
- `A value write says whether the bytes moved` (`:553`) stays the plaintext's answer. The sealed copy
  is written on every apply and is never compared, because a seal is not reproducible.
- `The command refuses a deployment record it cannot read` (`:249`) already requires a record with no
  table of entries to be refused rather than read as a deployment that places nothing. The
  requirement below is the same rule for the machine table, stated separately because it is a new
  table and not a change to that one.

`retire-an-entry-a-build-no-longer-names` owns the retire step of the walk, and the per-machine
order across the open changes - preflight, retirement, unsealer install, value writes, copy,
activation, value-driven restarts - is written out once in INTEGRATION.md; this change states only
its own step. It takes no decision about the channel a remote step goes through, the order the walk
visits entries in, or what a report says about an entry the build does not name. The preflight
question of a user-scope machine, lingering included, is `run-an-entry-without-root`'s and is cited
as a seam rather than restated.

The conditions:

- `cli/apply.py:209-296` is the walk: refuse, select, check the source, plan the writes, order,
  write every value, then per entry copy and activate, then restart the readers of a value that
  moved. `nix copy` happens once per entry artifact (`cli/apply.py:283-286`); nothing is copied per
  machine.
- `cli/remote.py:326-384` builds the write script from the record alone and the bytes arrive on the
  step's input stream (`cli/apply.py:266-276`, `cli/remote.py:88-111`).
- `cli/manifest.py:180-217` reads the record, `:41-56` is the file record it reads, and `:241-258` is
  where a value's machine address is read off the plan. The recipient is read there too, with a
  reader of this change's own, because a value's machine need run no entry.
- `cli/values.py:151-197` is every refusal about the source, all of them made before the first dial
  (`cli/apply.py:236-238`), which is where the refusal about a missing sealing program belongs too.
-->

## ADDED Requirements

### Requirement: A run installs the unsealer of a machine before it writes that machine's values

Before the first value of a machine is written, a run SHALL put that machine's unsealer on it and
install the unit that runs it: the artifact SHALL be copied with the same store-to-store copy the run
already uses for an entry's artifact, and the unit SHALL be installed into the manager the machine's
scope names - the system manager, or the account's own for a user-scope machine - so that it runs on
the next boot. The step SHALL be idempotent and SHALL say whether it changed anything, the way the
value write and the activation do.

A run SHALL take the step for exactly the machines it writes a value to and whose record says their
values are sealed, so that a restricted run contacts no machine it would not otherwise contact, and a
run that writes no value installs nothing.

A run asked what it would do SHALL print the step and SHALL take it against nothing, exactly as it
prints every other step, because the mode replaces the channel and nothing else.

#### Scenario: A run installs the unsealer of every machine it seals a value to

- **WHEN** a deployment delivering values to two machines that seal is applied
- **THEN** each of those machines SHALL be sent its own unsealer before the first value written to
  it
- **AND** the step SHALL be announced before it is attempted, like every other step

#### Scenario: A run that writes no value installs no unsealer

- **WHEN** a run is restricted to entries that read no value and whose machines receive none
- **THEN** no unsealer SHALL be copied and no unit installed
- **AND** no machine outside the restriction SHALL be contacted

#### Scenario: A machine that already holds the unsealer is reported as unchanged

- **WHEN** a deployment is applied twice with no change between the runs
- **THEN** the second run's install step SHALL report that it changed nothing
- **AND** the unit SHALL still be the one the build published

### Requirement: The sealed copy travels as the step's payload and never as an argument

The bytes a run seals SHALL be sealed where the plaintext already is, in the process that read the
value source, and the sealed bytes SHALL travel to the machine on the step's own input stream. No
argument vector on either host SHALL carry a byte of a value, sealed or plain. The recipient is not
a value: it is one public word, read from the plan's machine record, and it MAY stand in an
argument vector the way a path or an address does.

A step's argument vector SHALL stay a function of the plan, the deployment record and the
invocation's own options, so that two runs over one deployment address the machine identically
however the bytes differ.

The sealed copy SHALL be written on every apply, because two sealings of one file differ and no
comparison of seals is meaningful. Whether a value's bytes moved SHALL remain the plaintext's
answer, and an apply in which no plaintext moved SHALL restart nothing on the strength of a rewritten
seal.

#### Scenario: A sealed payload enters no argument vector

- **WHEN** two values of equal length and different bytes are delivered to one machine
- **THEN** the argument vectors of the two steps SHALL be equal
- **AND** no element of either SHALL hold a byte of a value, sealed or plain

#### Scenario: A value whose bytes did not move restarts nothing

- **WHEN** a deployment is applied twice with the same bytes in the value source
- **THEN** the second run SHALL report the plaintext unchanged
- **AND** SHALL restart no entry, whether or not the sealed copy was rewritten

### Requirement: A run that cannot seal refuses before it dials

Where a deployment's record says a machine's values are sealed and the invocation names no program
that can seal them, the run SHALL refuse before the first machine is contacted, naming the program it
could not find and the machines it would have sealed for. The sealing program SHALL be named by the
command's own wrapper rather than found on the caller's `PATH`, so that what a run seals with is the
build's answer and not the workstation's.

A record carrying no table of the machines a value reaches SHALL be refused as a record the command
cannot read, never read as a deployment whose machines seal nothing, for the reason a record carrying
no table of entries is refused: the difference between the two readings is silent and the wrong one
leaves a fleet that cannot recover.

#### Scenario: A run that must seal and has no sealing program

- **WHEN** a deployment whose record says a machine's values are sealed is applied and the sealing
  program the invocation names is not there
- **THEN** the command SHALL refuse naming the program and the machines
- **AND** no machine SHALL have been dialled

#### Scenario: A record carrying no table of machines

- **WHEN** the command is given a deployment record holding no table of the machines a value
  reaches
- **THEN** it SHALL refuse naming the record and the table
- **AND** SHALL NOT report a run that sealed nothing as successful
