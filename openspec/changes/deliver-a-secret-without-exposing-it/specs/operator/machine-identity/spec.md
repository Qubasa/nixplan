<!--
`openspec/specs/` is empty in this repository, so this new capability is written here. It lives in
the machine registry (`lib/resolve.nix:42-48`), in the plan's `machine:<name>` entry
(`lib/plan.nix:774-788`), and in the connection `cli/remote.py` opens.

It reads against `planner/plan-artifact`, which owns what a plan entry records and what an entry key
covers, and against `operator/apply-command` in `apply-deployments-with-an-operator-command`, which
owns the steps a run takes and the refusals it makes before it dials. That capability says an
artifact goes to "the address the plan records for that machine" and says nothing about who answers
there. This capability owns the answer: what a deployment states about the machine it means, what
the command verifies before it writes anything, and which options a run connects with.

`operator/deployment-build` in that same change owns the refusal for a machine record carrying no
address. A record carrying no identity is the same shape and is refused here, by the command rather
than by the build, for the reason given in D2.
-->

## Purpose

Defines the identity of a machine as a fact of the deployment rather than of the shell that launched
a command, so that writing a secret to an address is writing it to a machine the deployment named.
It owns the registry field, its relationship to the keys a plan carries, the verification the
command performs before its first write, and the visibility of the options a run connected with.

## ADDED Requirements

### Requirement: A machine's host identity is a fact of the registry

A machine registry record SHALL be able to state the host identities the machine presents, as a
list, so that a deployment carries one answer about which machine an address means. The plan's entry
for that machine SHALL record the list beside the address, so a consumer of the plan can verify a
connection from the plan alone.

The identity SHALL be optional, as the address already is, because a deployment whose machines are
addressed and identified late is still a deployment worth building.

The identity SHALL NOT participate in any key the plan carries. Rotating a machine's identity SHALL
move no entry key, SHALL change no artifact, and SHALL be visible only in that machine's own entry:
an identity is a fact about reaching a machine, not about what the machine runs.

#### Scenario: A registry states a machine's host identity

- **WHEN** a machine record states the identities the machine presents
- **THEN** the plan's entry for that machine SHALL record them beside its address
- **AND** a record stating none SHALL still produce an entry, with the field recorded as empty
  rather than absent

#### Scenario: Rotating a host identity moves no key

- **WHEN** a machine's stated identities change and nothing else does
- **THEN** every entry key in the plan SHALL be unchanged
- **AND** every artifact built from the deployment SHALL be byte-identical
- **AND** the machine's own entry SHALL be the only entry whose content differs

### Requirement: A secret is not written to a machine whose identity is unverified

The command SHALL verify the identity of every machine it connects to against the identities the
deployment stated for it, and SHALL do so before it writes any byte of a value there. A machine
whose record states no identity SHALL be refused before the first dial, naming the machine and the
field, unless the invocation itself states what to do instead.

A machine that answers with an identity the deployment did not state SHALL be refused for that
machine, naming the machine and the identity it presented, and the run SHALL NOT continue on it. The
refusal SHALL be the command's own, because a build contacts nothing and stays buildable for a
machine no identity has been stated for.

#### Scenario: A machine states no host identity

- **WHEN** the command is asked to apply a deployment placing an entry on a machine whose record
  states no identity, and the invocation states no alternative
- **THEN** it SHALL refuse naming the machine and the field
- **AND** no machine SHALL have been dialled, including the machines that do state one

#### Scenario: A machine answers with another identity

- **WHEN** the machine at a stated address presents an identity the deployment did not state
- **THEN** the command SHALL refuse for that machine, naming the machine and the identity presented
- **AND** no value SHALL have been written there
- **AND** no artifact SHALL have been copied there

### Requirement: The options a run connects with are stated and reported

The options a run connects with SHALL come from the deployment and from the invocation, and SHALL
NOT be inherited from the environment. An option an operator's shell exports SHALL have no effect on
how a run authenticates a machine, so an accommodation made for one deployment cannot lower the
guarantee of another.

The command SHALL report the options it connected with, on every invocation that contacts a machine,
before the first step. An invocation that accepts an unverified machine SHALL say so in that report,
so an operator reading their own output can tell a verified run from an unverified one.

#### Scenario: An inherited option set does not reach the connection

- **WHEN** the environment of the invocation carries connection options that disable host
  verification
- **THEN** the run SHALL verify identities as though the environment carried none
- **AND** a machine whose record states no identity SHALL still be refused

#### Scenario: The report names the options the run used

- **WHEN** a run contacts a machine
- **THEN** its first reported line SHALL name the options it connected with
- **AND** two runs of one deployment with equal invocations SHALL report equal lines

#### Scenario: A throwaway guest's accommodation is named on the command line

- **WHEN** a run is against machines created for that run, whose identities no deployment can state
  in advance
- **THEN** accepting them SHALL be stated in the invocation rather than in the environment
- **AND** the report SHALL name the run as one that accepted an unverified machine
- **AND** an invocation without that statement SHALL be refused
