<!--
A delta against `realiser/flakelet-artifact`, whose base text lives in the unarchived
`emit-flakelet-service-artifacts` change and is restated or extended by
`deliver-secrets-across-machines`, `report-every-refusal-as-a-row`, `hold-a-long-running-daemon`,
`take-effect-on-a-second-apply` and `open-a-configuration-file-to-its-reader`. `openspec/specs/` is
empty in this repository, so the base text is read from those changes.

The one requirement below is MODIFIED: it is `A name the endpoint cannot accept is refused before
bytes exist`, added by `emit-flakelet-service-artifacts` and last restated by
`report-every-refusal-as-a-row`, restated whole with one statement added about what a restatement of
somebody else's rule owes. Its three scenarios are kept verbatim - each names a situation whose
outcome does not move - and a fourth is added.

Evidence: `flakelet/read.nix:36-48` restates the endpoint's `validate_name` and `validate_units`
from that endpoint's own `manager.rs`, and the unit rule is a pattern whose wildcard matches a line
break, so `main\nConditionPathExists=/nonexistent` satisfies the restatement and is a name the
endpoint itself refuses. The artifact then carries a unit file whose name is two lines, which is a
directive no module wrote. Counterexample: `tests/unit/counterexamples.nix:921`, which asserts the
planner's row for the same declaration; the realiser's half is this requirement.

The row that reports a refused derived name is `operator-entry-name-refused`, which
`operator/deployment-build` already owns and already obtains from the stated realiser, so no delta
against that capability is needed here: what changes is what this realiser's published predicate
answers, not what the row means. The rule that a unit name is held to the rule its values are held
to belongs to `planner/unit-vocabulary` in this same change, and holds one stratum above this one.
-->

## MODIFIED Requirements

### Requirement: A name the endpoint cannot accept is refused before bytes exist

The names an artifact derives - the service name and every unit file name - SHALL satisfy the
endpoint's own naming rules, and the builder SHALL refuse an entry whose derived names do not,
naming the entry, the offending name and the rule it breaks. A refusal SHALL be a raise, as every
refusal on this side is, and it SHALL happen before any file is produced.

This realiser SHALL be the author of both rules, and SHALL publish each as a predicate a caller can
ask before building, so that the deployment build reports the same condition as a row without
restating the rule. A raise here SHALL therefore be reachable only by a caller that did not ask, and
the sentence a raise prints SHALL be the sentence the row states.

Both rules are restatements of rules the endpoint owns, and a restated rule SHALL refuse everything
the rule it restates refuses. A name this realiser admits and the endpoint rejects is a defect of
the restatement and not of the declaration: the refusal then arrives from the endpoint, on a
machine, naming neither the entry nor the deployment, and the artifact has already been built and
delivered.

A restatement SHALL be anchored over the whole name, so that no character the endpoint treats as a
terminator passes as an ordinary one. A rule stated as a pattern SHALL match the name end to end and
its wildcards SHALL admit no line break, because a name carrying one satisfies a rule about a single
line while naming a file whose second line is a directive the plan does not record. Where the two
rules cannot be shown to agree, the restatement SHALL be the narrower of the two.

#### Scenario: An unusable instance name

- **WHEN** an entry's instance or service name contains a character the endpoint's service names may
  not carry
- **THEN** the build SHALL fail naming the entry, the derived name and the rule
- **AND** a caller that reads the deployment build instead SHALL have received a row naming the same
  three

#### Scenario: A unit name outside the service's namespace

- **WHEN** an entry would render a unit file whose name does not begin with the derived service name
- **THEN** the build SHALL fail naming the entry and that unit

#### Scenario: A unit name carrying a line break is refused by the restated rule

- **WHEN** an entry derives a unit file name whose text carries a line break, so that its first line
  alone satisfies the restated rule
- **THEN** the published predicate SHALL answer that the name is unusable and the build SHALL fail
  naming the entry and that name
- **AND** no artifact of that entry SHALL carry a unit file whose name spans two lines
- **AND** the deployment build SHALL have reported the same condition as an error row

#### Scenario: A well-formed entry is not refused

- **WHEN** an entry's instance, service and unit names are all made of characters the endpoint
  accepts
- **THEN** the build SHALL succeed
