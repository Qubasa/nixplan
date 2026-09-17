<!--
A delta against `operator/apply-command`, whose current text is
`openspec/specs/operator/apply-command/spec.md`. Every block below is ADDED; no existing
requirement is modified. The channel every remote step goes through is the one `cli/remote.py`
already dials, and the steps stated here are steps of that channel rather than a second one - this
change adds no channel and no connection option. Other open changes delta this capability with
steps of their own; the on-machine order across changes is written out once in
`openspec/changes/INTEGRATION.md`.

Three existing requirements are preconditions and are deliberately not restated. `What the command
does on a machine` says the command uses what is already there, which is what makes a retirement
the endpoint's own verb rather than a script of the command's. `A run that broke is finished by a
second run` is why nothing here says what happens after a retirement a machine refuses: the run
stops at the first step a machine refuses, and a retirement is a step. `The command refuses before
it dials` bounds what a refusal may be made of, and the one refusal added below is not one of
those: what a machine holds cannot be read from the plan, so an answer the command cannot read is
refused where it is read. It is read before anything is written anywhere, which is the property
stated instead.

`A restriction bounds the machines a run contacts` is the block the selection rule below sits
beside, and it is left alone: it already says which machines a restricted run contacts, and what is
added is that the restriction decides nothing about what counts as a holding the build does not
name.

The conditions. `cli/apply.py:243-296` writes every value, then copies and activates each entry,
then restarts the readers of a moved value, and takes no step about anything the plan does not
carry. `image/default.nix:378-385` builds a `bin/detach` into every image artifact that stops the
units, detaches the image and removes the staging directory; no subcommand calls it, and the only
caller in the tree is `tests/e2e/portable-image/test_portable_image.py:380`. Nothing in `cli/` names
`flakelet remove`, and `flakelet reconcile` is not the verb for this: it removes declarative
entries no longer in `config.json`, while `cli/remote.py:420-427` activates through `flakelet
activate`, which registers a manual entry that `reconcile` leaves alone.

`image/default.nix:348-356` is the precedent for a step that detaches an image the machine named
rather than one a build carried: the attach script reads which image the entry currently runs from
out of `systemctl show -P RootImage` and detaches that, with no artifact of that build at hand.
`lib/plan.nix:1404-1418` emits a `machine:<name>` record only for a machine some placement
selected, and `cli/manifest.py:342-361` reads an address only off an entry of the record, which is
what makes the last block a statement of scope rather than a behaviour.
-->

## ADDED Requirements

### Requirement: An apply names what the machines hold that the build does not

Before it writes anything on any machine, an apply SHALL ask every machine of its selection what it
holds and SHALL announce, per machine, every holding that machine runs which the build being applied
names no entry for. The announcement SHALL be in the shape the report's own line has, naming the
machine and the identity or name the machine gave the holding, and SHALL be printed where the run's
other announcements are printed - before the first step it takes.

A realiser SHALL join the question only where the scopes the record publishes for it admit the
machine's scope, and the question SHALL address the account's own daemon on a machine whose scope
is `user`. A record publishing no scopes for a realiser admits every machine, so the question loses
nothing where the fact is not yet published.

Asking every machine before the first write SHALL be the order, so that a run which cannot read a
machine's answer has changed nothing anywhere when it refuses.

An apply SHALL NOT retire a holding it was not asked to retire. Where the run was not asked, the
announcement SHALL say that the holding would be retired and that nothing was removed, and the run
SHALL continue with the entries it applies.

A run asked what it would do rather than to act SHALL name no holding, because naming one requires
asking a machine and such a run contacts none. What a machine currently holds SHALL remain a
question the reporting command answers.

#### Scenario: An apply of a build that dropped an entry announces what the machine still runs

- **WHEN** a deployment that placed two entries on one machine is applied, one entry is deleted from
  it, and the remaining entry is applied from the new build
- **THEN** the run SHALL announce the deleted entry as a holding the build does not name, naming the
  machine
- **AND** the announcement SHALL be printed before the first step the run takes

#### Scenario: An apply that was not asked to retire leaves the holding running

- **WHEN** the run of the previous scenario is taken without being asked to retire
- **THEN** the holding SHALL still be running on the machine afterwards
- **AND** the announcement SHALL say that nothing was removed
- **AND** the entry the build names SHALL have been applied

#### Scenario: A run asked what it would do names no holding

- **WHEN** a deployment is applied in the mode that asks rather than acts, against machines holding
  entries the build does not name
- **THEN** no machine SHALL be contacted
- **AND** the run SHALL name no holding

### Requirement: A retirement is the endpoint's own removal verb

Where a run is asked to retire, it SHALL retire every holding it announced on the machines of its
selection, and each retirement SHALL be the removal verb of the endpoint that holds it: the verb
that stops an entry's units, unlinks them and leaves the entry unregistered. The step SHALL be
addressed by what the machine answered and what the deployment record publishes, and by nothing
else. On a machine whose scope is `user` the step SHALL address the account's own daemon, the way
the question did: the verb does not move, the daemon it is addressed to does.

A retirement SHALL NOT run a script out of the retired holding's own artifact. That artifact belongs
to a build this run is not applying, so this run cannot name it, and nothing on the machine keeps it
from being collected; a retirement that needed it would fail exactly where it is needed. The script
an artifact carries for the operator's own use is unaffected by this and remains the artifact's own
contract.

After a retirement the machine SHALL run none of the retired holding's units and its endpoint SHALL
register nothing for it.

#### Scenario: A retirement asks the endpoint to remove the entry

- **WHEN** a run is asked to retire a holding an endpoint registers
- **THEN** the step taken against the machine SHALL be that endpoint's own removal verb for the name
  the machine answered
- **AND** SHALL NOT be the verb that empties what the entry stored

#### Scenario: A retired entry stops running and the endpoint no longer registers it

- **WHEN** a run is asked to retire an entry a machine runs and the build does not name
- **THEN** the machine SHALL run none of that entry's units afterwards
- **AND** the endpoint SHALL register nothing under that entry's name
- **AND** the entries the build does name SHALL be running

#### Scenario: A retired image is detached and its units are gone

- **WHEN** a run is asked to retire an image a machine holds attached for no entry of the build
- **THEN** the image SHALL be detached afterwards
- **AND** the service manager SHALL know none of the units that attachment created
- **AND** the image this build published for an entry it names SHALL be untouched

#### Scenario: A retirement names only what the machine answered and the record published

- **WHEN** a run is asked to retire a holding
- **THEN** every part of the step it takes SHALL come from the machine's answer, the deployment
  record and the invocation's own options
- **AND** SHALL name no path of the retired holding's own artifact

### Requirement: A retirement deletes no state

A retirement SHALL remove what a deployment put in place and SHALL delete nothing a service wrote.
No state directory, no delivered value, no host path a unit was shown and no file staged for one
SHALL be deleted by it, and the announcement of a retirement SHALL say so and SHALL carry whatever
the endpoint itself reported about what it kept.

This SHALL hold whether or not the endpoint offers a way to empty what an entry stored: a
retirement never asks for it. A deployment declares no account and no state of its own, so bytes on
a machine that outlive an entry are the machine's, and deleting them is an operator's decision that
this command does not take.

#### Scenario: A file the retired entry wrote survives its retirement

- **WHEN** an entry that wrote a file on its machine is retired
- **THEN** the file SHALL still be there afterwards
- **AND** the run SHALL report the retirement as taken

#### Scenario: The line of a retirement says what it kept

- **WHEN** a holding is retired
- **THEN** the line naming that step SHALL say that no state was deleted
- **AND** SHALL carry what the endpoint reported about what it kept

### Requirement: A retirement precedes every step that puts something in place

Within one run, every retirement SHALL be taken before the first value is written, before the first
artifact is copied and before the first entry is activated. A holding the build does not name holds
host resources of the machine - a port, a unit file name, a host path - and the entry that replaces
it may claim the same ones; the planner's own collision rows reach inside one build and cannot see
across two, so the only order in which a renamed entry can start is the one that takes the old entry
away first.

#### Scenario: A retirement precedes every value write and every activation of the run

- **WHEN** a run that writes a value and activates two entries is asked to retire a holding
- **THEN** the retirement SHALL be taken before the first value write
- **AND** before every copy and every activation of that run

### Requirement: A restriction never makes an entry a holding the build does not name

A restriction on which entries a run applies SHALL bound which machines the run asks and SHALL
decide nothing about what counts as a holding the build does not name. An entry the deployment
places SHALL NOT be announced or retired on account of a restriction leaving it out, whichever
machine it is placed on.

A restriction naming a holding rather than an entry or a value of the deployment SHALL remain the
refusal the command already makes for a key the deployment does not carry: a holding is not
addressable as a plan key of this build, and a run is restricted to what the build carries.

#### Scenario: An entry left out of a restricted run is not retired

- **WHEN** a run over a machine running two entries of the deployment is restricted to one of them
  and asked to retire
- **THEN** the run SHALL retire nothing
- **AND** SHALL apply the entry it was restricted to

#### Scenario: A restriction naming a holding the deployment does not place is refused

- **WHEN** a run is restricted to the identity of a holding the build does not name
- **THEN** the command SHALL refuse naming that key and the keys the deployment carries
- **AND** SHALL contact no machine

### Requirement: A machine the build does not name is out of reach

A build carries an address only for a machine it places an entry on. A run SHALL therefore announce
and retire only on machines the build still names, SHALL NOT infer an address for any other machine
and SHALL NOT take a machine's address from anywhere but the deployment record.

A machine whose every entry was deleted from the deployment is consequently out of reach of this
command, and that SHALL be stated in the operator's document as the limit it is, together with the
order of work it implies - a machine is emptied while the build still names an entry on it, and a
machine the build has already stopped naming is emptied with the endpoint's own tool. No field,
option or record SHALL be invented to reach it as part of this change.

#### Scenario: A build naming no entry on a machine retires nothing there

- **WHEN** a deployment whose every entry on one machine was deleted is applied and asked to retire
- **THEN** that machine SHALL NOT be contacted
- **AND** the run SHALL apply the entries of the machines it does name
