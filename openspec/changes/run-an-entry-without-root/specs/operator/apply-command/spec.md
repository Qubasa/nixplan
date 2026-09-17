<!--
A delta against `operator/apply-command`, whose current text is
`openspec/specs/operator/apply-command/spec.md`. One requirement is added; nothing is modified.

The block below adds one step to the walk and takes no decision another change owns.
`retire-an-entry-a-build-no-longer-names` owns the retirement, its announcement and its flag;
`unseal-a-value-after-a-reboot` owns the unsealer install; the order of the steps on a machine is
the shared seam - preflight, then retirement, then unsealer install, then value writes, copy,
activation and the value-driven restarts - and `openspec/changes/INTEGRATION.md` is the one place
the whole line is written out. What is stated here is only that the preflight question precedes
every mutation of this command's on the machine, whichever of those steps a run takes.

Why the refusal is the command's own and not a diagnostics row: `The command refuses before it
dials` bounds what a plan-side refusal may be made of, and a runtime fact of a machine is not one
of those - the plan holds no fact about what a machine currently permits, so the answer is read
where it is asked, which is the same division the holdings question of the retire change states.

The conditions. `cli/apply.py:216` connects as root by default and every step assumes the login
can write anywhere; on a user-scope machine the login is the account, and the facts a user-scope
run rests on - the fixed roots writable (`lib/util.nix:334`, `image/read.nix:296`), lingering, the
user manager, the user portabled, `systemd-mountfsd.socket` and `systemd-nsresourced.socket`,
unprivileged user namespaces - are provisioned once as root and verified per run rather than
assumed. `cli/apply.py:182-207` is the channel a dry run replaces: the walk is the walk either
way, so the question goes through the replaced channel like every remote step, is recorded rather
than asked, and the two runs stay comparable line by line.
-->

## ADDED Requirements

### Requirement: A run verifies a user-scope machine before it writes

Before any mutation on a machine whose scope is `user`, a run SHALL ask that machine one preflight
question verifying the facts the run rests on: the values root, the sealed root and the image
staging root writable by the account; lingering active for the account; the user manager
reachable; the user portabled reachable where an image entry is placed on the machine;
`systemd-mountfsd.socket` and `systemd-nsresourced.socket` live; and unprivileged user namespaces
permitted. The question SHALL precede every mutation the run makes on that machine - the
retirement step, every value write, every copy and every activation - and SHALL add one step to
the walk while deciding nothing any of those steps owns.

A failed fact SHALL be the command's own refusal, not a diagnostics row - the plan holds no
runtime fact - naming the machine, the requirement and what the machine answered, and nothing
after it SHALL be attempted on that machine. A machine whose scope is `system` SHALL be asked
nothing new.

The facts SHALL be verified rather than assumed provisioned: provisioning is root's work done once
per machine, and the preflight is what tells a provisioned machine from one that was not. The
question SHALL remain a list of questions a local installer could ask, so a future realisation
that runs the walk on the machine itself can ask the same list.

Under the mode that asks rather than acts, the question SHALL go through the replaced channel like
every remote step, so it is recorded rather than asked and the walk stays comparable line by line
with a real run's.

#### Scenario: A user-scope machine is asked before anything is written

- **WHEN** a run applies entries to a machine whose scope is `user`
- **THEN** the preflight question SHALL be the first step taken against that machine
- **AND** it SHALL precede the retirement step, every value write, every copy and every activation
  of that run on that machine

#### Scenario: A failed preflight fact is the run's own refusal

- **WHEN** a user-scope machine answers that one verified fact does not hold
- **THEN** the run SHALL refuse naming the machine, the requirement and what the machine answered
- **AND** nothing after the question SHALL be attempted on that machine

#### Scenario: A system-scope machine is asked nothing new

- **WHEN** a run applies entries to a machine whose scope is `system`
- **THEN** no preflight question SHALL be asked of it
- **AND** the run's steps on that machine SHALL be the steps it took before this change

#### Scenario: A dry run records the preflight question

- **WHEN** an applicable deployment placing entries on a user-scope machine is applied in the mode
  that asks rather than acts
- **THEN** the preflight question SHALL go through the replaced channel and SHALL be printed where
  a real run prints it
- **AND** no machine SHALL have been dialled
