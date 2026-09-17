<!--
A delta against `realiser/flakelet-artifact`, whose current text is
`openspec/specs/realiser/flakelet-artifact/spec.md`. One requirement is added; nothing is
modified.

The shape follows `A name the endpoint cannot accept is refused before bytes exist`: this realiser
publishes what it accepts as a fact the deployment build asks for, the build reports the crossing
as a row, and a raise here is reachable only by a caller that did not ask, printing the sentence
the row states. The row is `operator-entry-scope-unsupported`, stated by
`operator/deployment-build`'s delta of this change; what this file adds is the realiser's own half
of that contract.

The upstream facts. flakelet's core writes its unit files into `/run/systemd/system`
(systemd.rs:13) and keeps its generations and bookkeeping under `/var/lib/flakelet`, both paths an
account does not own and a user manager does not read, and its endpoint addresses the system
manager. A user mode is upstream work, not a rendering decision this realiser can take: rendering
into a user unit directory would produce an artifact the endpoint's own linking never reads.
Declaring the limit is what keeps it honest - a realiser that half-worked in user scope would fail
on the machine, naming neither the entry nor the deployment.
-->

## ADDED Requirements

### Requirement: This realiser states the system scope alone

This realiser SHALL publish `system` as the one scope it can realise, beside the name and unit
rules it already publishes, because its endpoint writes its unit files into `/run/systemd/system`
(systemd.rs:13) and keeps its state under `/var/lib/flakelet`, both of which belong to the system
manager and to root. A user mode is the upstream endpoint's work, and until it exists this
realiser SHALL NOT render for a user-scope target.

An entry whose machine's scope is `user` and whose stated realiser is this one SHALL be refused.
The deployment build SHALL report it as the `operator-entry-scope-unsupported` error row, and a
caller reaching this builder directly SHALL be refused with a sentence carrying that identifier
and naming the upstream facts - the system unit directory the endpoint writes and the state root
it keeps - so the resolution is to state the image realiser or a system-scope machine rather than
to expect a rendering the endpoint would never read.

#### Scenario: The published scopes name the system scope alone

- **WHEN** the deployment reading asks this realiser for the scopes it can realise
- **THEN** the answer SHALL be the system scope and no other
- **AND** it SHALL be published beside the name and unit rules the reading already asks for

#### Scenario: An entry placed in user scope is refused before bytes exist

- **WHEN** an entry on a machine whose scope is `user` is stated to be realised by this realiser
  and a caller reaches the builder directly
- **THEN** the build SHALL fail before any file is produced, carrying
  `operator-entry-scope-unsupported`
- **AND** the sentence SHALL name the entry, the machine's scope and the upstream facts the limit
  rests on
