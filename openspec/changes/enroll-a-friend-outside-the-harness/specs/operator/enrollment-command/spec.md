<!--
A new capability. `operator/machine-enrollment`, landed with `enroll-a-friend-machine`, owns what
enrollment is: the registry row convention, the credential's nature, the two refusals the
coordination server owns, and how membership ends
(`openspec/changes/enroll-a-friend-machine/specs/operator/machine-enrollment/spec.md:11-92`). This
capability owns only the surface an operator runs against it, so it restates none of that and
MODIFIES it nowhere: the credential stays a generated secret handed over out of band, the server's
database stays a source no plan reads, and admission stays verified rather than automated.

What it deliberately does not decide. The structured record a machine question answers with, and
the two diagnostics fields the manifest restores, belong to
`answer-a-machine-question-as-a-record`; an enrollment verb asks the coordination server and never
asks a machine what it holds, so it defines no machine question and reads none of that record.
`operator/apply-command` keeps the walk, and the enrollment verbs take no step of it. The exported
bundle for a machine no run can dial is named and not designed:
`openspec/changes/INTEGRATION.md:81-84`. The order of this change inside its set, and every seam it
shares with its siblings, is written out once in `openspec/changes/INTEGRATION.md`.

The conditions. `planner`'s subcommands are `plan build apply status rollback`
(`cli/planner.py:100-106`), one subparser each from one table (`:145-151`), and nothing under `cli/`
names enrollment at all. Every membership act of the proof is a shell string a test composes: the
group and the numeric id the server assigned it
(`tests/e2e/friend-enrollment/test_friend_enrollment.py:456-462`), the credential (`:463-469`), the
node list (`:237-245`) and the expiry (`:825-828`). The declared generator has never run: its
program reads two environment names nothing sets
(`tests/e2e/friend-enrollment/deployment/mint.sh:25-32`), because a generator's program is run by
the external secret backend with `out` set (`secrets/read.nix:518-543`,
`tests/e2e/generation.py:562-572`) on a host the server's socket is not on
(`tests/e2e/friend-enrollment/deployment/modules/mesh/hub.nix:144`). The operator's own invocations
cannot read the entry's configuration twice over: the path the entry declares exists inside that
unit's mount namespace alone and the store object it is bound is named by a digest with no suffix,
which the server's loader refuses, so the folder installs a copy by hand
(`tests/e2e/friend-enrollment/test_friend_enrollment.py:192-203`, performed at `:393`). A fact
stated beside the deployment and refused where it names no entry is `realise`
(`operator/read.nix:637-650`, `:690-703`), and a fact published per realiser rather than restated by
a reader is the `scopes` and `holdings` table (`:753-763`).
-->

## Purpose

Defines the verbs an operator runs against a coordination server the deployment places: how a verb
learns which entry that server is and what it reads, where a minted credential's bytes go and where
they may not, what a verb prints, and which refusals belong to the command rather than to a
diagnostics row. It also fixes what the published module that places such a server must make
declarable and what it must refuse to default.

## ADDED Requirements

### Requirement: A verb learns its coordination server from the deployment

The deployment SHALL state which of its entries runs the coordination server, beside the statement
of how each entry is realised, and a verb SHALL read that statement off the built deployment rather
than infer it. A verb SHALL NOT recognise a coordination server by a module's identity, by a
package in a closure, or by the text of a plan key.

A statement naming a key the plan places no entry for SHALL be one error row naming the statement
and the keys it could have named, the way a realisation statement naming no entry already is. A
verb run against a deployment that states no coordination entry SHALL be the command's own refusal
naming the statement to add, and SHALL dial nothing.

The deployment record SHALL publish what a verb needs about that entry - which entry it is, and the
program a verb runs - the way it publishes each realiser's own statements, so that a verb derives
no path and reproduces no rule of a realiser's in the command.

#### Scenario: A verb reads the coordination entry off the built deployment

- **WHEN** a verb runs against a built deployment whose record states a coordination entry
- **THEN** the entry it addresses SHALL be the one the record states
- **AND** the machine it dials SHALL be the machine that entry's own record names

#### Scenario: A coordination statement names no placed entry

- **WHEN** a deployment states a coordination entry whose key the plan places no entry for
- **THEN** the reading SHALL produce one error row naming the statement and the keys it could have
  named
- **AND** the row SHALL name the deployment argument the statement is written in

#### Scenario: A deployment states no coordination entry

- **WHEN** an enrollment verb runs against a built deployment whose record states no coordination
  entry
- **THEN** the command SHALL refuse naming the statement to add
- **AND** no machine SHALL have been dialled

### Requirement: The credential a verb mints is the generator the deployment declared

The verb that mints SHALL run the credential value's own declared program - the store path the plan
records for it - on the coordination entry's machine, under the contract a generator's program is
already run under: one program, an output directory the run names, and the files it writes under
it. The verb SHALL NOT mint with an invocation of its own, so that the deployment stays the one
place a credential's expiry, file name and secrecy are declared.

The files the program wrote SHALL be written into the value source at the paths the plan names for
that value's files, and a program that wrote a file set the plan does not name SHALL be the
command's own refusal naming the value and the files. The bytes SHALL travel on a step's stream:
no argument vector of the run SHALL carry the credential in any encoding, and no line the verb
prints SHALL carry a byte of it. What the verb prints SHALL be where the credential now is and the
expiry it was minted under.

#### Scenario: The minted bytes are the declared program's own

- **WHEN** the minting verb runs against a deployment declaring a credential generator
- **THEN** the program it runs on the machine SHALL be the store path the plan records as that
  value's program
- **AND** the command SHALL run no invocation of the coordination server's tool of its own

#### Scenario: A minted credential enters no argument vector

- **WHEN** the minting verb has run and the credential is in the value source
- **THEN** no recorded argument vector of the run SHALL contain the credential in any encoding
- **AND** no line the verb printed SHALL contain a byte of it

#### Scenario: A verb prints where the credential is

- **WHEN** the minting verb succeeds
- **THEN** it SHALL print the path in the value source the bytes were written to and the expiry
  they were minted under
- **AND** the operator SHALL hand the credential over from there, outside this tree

#### Scenario: A mint program wrote files the plan does not name

- **WHEN** the declared program writes a file set that is not the one the plan names for that value
- **THEN** the command SHALL refuse naming the value and the files
- **AND** nothing SHALL have been written into the value source

### Requirement: A verb is one step on the coordination machine and its refusal is the command's own

Each verb SHALL take one step on the coordination entry's machine, over the channel every other
remote step of the command uses, addressed by the scope that machine's record states - the
account's own manager and an explicitly stated runtime directory where the scope is `user`. A verb
SHALL run the program out of the entry's own closure on that machine, and SHALL refuse naming the
entry and the path where the machine does not hold what this build names, rather than reconstruct
the program or copy one.

A machine that refuses a step SHALL be reported as the command's own refusal naming the entry, the
machine and what the machine printed - never a traceback and never the argument vector - and
nothing after the refusal SHALL be attempted. A failed fact of a verb SHALL NOT be a diagnostics
row: the plan holds no runtime fact about a coordination server.

#### Scenario: A verb addresses the machine by its stated scope

- **WHEN** a verb runs against a coordination entry on a machine whose scope is `user`
- **THEN** the step SHALL address the account's own manager and SHALL state the account's runtime
  directory itself
- **AND** a coordination entry on a machine whose scope is `system` SHALL be addressed without
  either

#### Scenario: A machine refusing a verb is named with what it said

- **WHEN** the machine refuses the step a verb takes
- **THEN** the command SHALL refuse naming the entry, the machine and what the machine printed
- **AND** the refusal SHALL carry neither a traceback nor the argument vector of the step

#### Scenario: A verb refuses a program the machine does not hold

- **WHEN** a verb runs against a machine that does not hold the program path this build names
- **THEN** the command SHALL refuse naming the entry and the path
- **AND** it SHALL name applying the deployment as what puts it there

### Requirement: A listing is the server's own answer and an expulsion takes what it printed

The verb that lists SHALL print what the coordination server answered, and SHALL read no fact of
that answer into anything the planner evaluates. A listing MAY be printed verbatim because the
server masks a credential in its own listings to a leading fragment, and a verb SHALL NOT print an
unmasked credential from any answer.

The verb that ends a membership SHALL take the identifier the listing printed, and not a machine of
the registry: a node is the server's own fact and the registry's name for a machine is not the
server's name for a node. No verb SHALL write anything into the deployment, the registry or the
plan, so that the only gate from the mesh back into evaluation stays an operator-reviewed
declaration edit.

#### Scenario: A listing is printed as the server answered

- **WHEN** the listing verb runs against a coordination server that admits machines
- **THEN** it SHALL print the server's own answer
- **AND** any credential in that answer SHALL be the masked fragment the server printed

#### Scenario: An expulsion names the node the listing printed

- **WHEN** the expelling verb is given an identifier the listing printed
- **THEN** the step SHALL end that node's membership at the server
- **AND** a verb SHALL NOT accept a registry machine name in place of that identifier

#### Scenario: A verb writes nothing into the deployment

- **WHEN** any enrollment verb has run
- **THEN** no file of the deployment, the registry or the plan SHALL have changed
- **AND** a later plan of the same deployment SHALL be the plan it was before the verb ran

### Requirement: A published module places a coordination server without a folder to copy

A module that places a coordination server SHALL be published by this repository, so that a
deployment composes it rather than copying a module out of an end-to-end folder, which no
deployment outside that folder can name. A fact the module refuses to default SHALL be an argument
of the module itself, so that a composing root omitting it fails before a plan exists rather than
receiving a chosen value: the url a client is configured with SHALL be such an argument, and so
SHALL the admission policy, because the transport and who is admitted are not choices a published
module may make on a consumer's behalf.

Every other choice a cluster makes SHALL be declarable as a setting of the instance, and the
module's own default SHALL be a value it can defend outside a cluster: the listener, the relay's
client verification and its relay maps, the metrics listener, the address prefixes, the node expiry
and the name-service statements.

The module SHALL render two objects from one derivation of the facts it derived: the configuration
the serving unit reads, declared as a file whose bytes the plan holds, and the object an
administrative invocation reads, whose name SHALL carry the extension the server's own loader
requires. Neither SHALL be a copy installed on a host path by anything but the realiser, and no
deployment declaration SHALL carry a host path: every path the module needs SHALL be derived inside
it from the identity of its own entry.

#### Scenario: A fact the module refuses to default is an argument

- **WHEN** a deployment composes the published module without stating the client url or the
  admission policy
- **THEN** the evaluation SHALL fail naming the argument the module requires
- **AND** the module SHALL NOT resolve either to a value of its own

#### Scenario: The cluster's choices are declarations of its deployment

- **WHEN** the end-to-end folder places a coordination server with plain transport, unverified
  relay clients, empty relay maps and an empty admission policy
- **THEN** each of those SHALL be stated in that folder's own deployment
- **AND** the module's default for each SHALL be the value it can defend outside a cluster

#### Scenario: An administrative invocation reads an object the loader accepts

- **WHEN** a verb runs the administrative program of an entry the published module placed
- **THEN** the object it reads SHALL be named so that the server's own loader accepts it
- **AND** no step of the run SHALL install a copy of it at a host path

#### Scenario: The serving unit reads the configuration the plan holds

- **WHEN** an entry the published module placed is planned
- **THEN** the configuration its unit reads SHALL be a declared file whose bytes the plan holds
- **AND** the socket the administrative object names SHALL be the socket that configuration states
