<!--
A delta against `operator/deployment-build`, whose base text lives in the unarchived changes
`apply-deployments-with-an-operator-command`, `make-an-apply-observable`,
`report-every-refusal-as-a-row`, `hold-every-stated-guarantee` and `hold-a-long-running-daemon`.
`openspec/specs/` is empty in this repository, so the base text is read from those changes.

The requirement below keeps the heading `report-every-refusal-as-a-row` gave it
(`.../specs/operator/deployment-build/spec.md:178-192`) and keeps its scenario heading, so the test
that scenario names keeps its name and changes its assertions. What the requirement loses is its
row: with the address required of the registry, no plan the planner emits carries a placed entry
whose machine record has no address, so a row here would restate a decision the planner made about a
plan the planner cannot produce. What it keeps is everything the reading owes a caller that hands it
a plan of its own: the absence is carried rather than raised on, every artifact is built, and
refusing to dial stays with the command.

`The reading is total over a plan the planner pruned`, `An inapplicable deployment is not built` and
`The manifest is the whole interface to a build` are untouched; the second of them is what the
scenario about an inapplicable deployment below reads.
-->

## MODIFIED Requirements

### Requirement: An address is needed to apply and not to build

An address is read by the step that dials a machine and by no step that builds one, so a machine
record declaring no address SHALL NOT refuse a build and SHALL NOT produce a row of the deployment
build. The planner refuses such a placement before a plan exists, so the condition is reported once,
by the layer that holds the fact, against the file that declares it.

The reading SHALL nevertheless carry the absence rather than raise on it or omit the field, because
a plan and a deployment record may be handed to it by a caller the planner did not produce them
for, and SHALL build every artifact of the deployment. Refusing to apply an entry whose machine
record states no address belongs to the command, under "The command refuses before it dials" in
`operator/apply-command`, and SHALL stay there.

A build of a deployment the registry made inapplicable SHALL still publish the plan and both forms
of the diagnostics and SHALL publish no entry artifact, so that the operator reads the rendered
table naming the machine and the registry file rather than a build they cannot apply.

#### Scenario: A machine of a placed entry declares no address

- **WHEN** the reading is handed a plan whose machine record for a placed entry declares no address
- **THEN** the build SHALL produce every artifact the deployment places
- **AND** the diagnostics table SHALL carry no row about the address
- **AND** the deployment record SHALL carry that entry with its address stated as absent

#### Scenario: A build of a deployment the registry made inapplicable

- **WHEN** a deployment whose registry declares no address for a machine a placement selects is
  built
- **THEN** the build SHALL produce the plan, the machine-readable diagnostics and the rendered
  diagnostics
- **AND** SHALL produce no artifact for any entry of the deployment
- **AND** the rendered table SHALL name the machine and the file that declares it
