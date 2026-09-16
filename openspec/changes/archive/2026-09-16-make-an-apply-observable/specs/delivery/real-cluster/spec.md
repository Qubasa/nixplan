<!--
A delta against `delivery/real-cluster`, which lives in the unarchived `prove-plan-on-real-machines`
change and is already modified by `strip-planner-tests-to-unit-and-e2e`,
`resume-e2e-machines-from-snapshots`, `deliver-secrets-across-machines`,
`generate-values-with-nixos-secrets`, `apply-deployments-with-an-operator-command` and
`open-the-repository-to-a-consumer`. Nothing existing changes.

`apply-deployments-with-an-operator-command` added "A run applies its deployment the way an operator
does", which holds a run to the operator's own steps. What no requirement holds is what those steps
leave when one of them does not complete, and that fact needs machines: a route between two of them
to cut, a real endpoint on each, and a second run over the same build. The pure half of both claims
- the run stops at the failed step, and a repeated step has no effect - is `operator/apply-command`
in this same change under "A run that broke is finished by a second run".
-->

## ADDED Requirements

### Requirement: A run broken between two machines is finished by a second run

Where a run of the operator's command is broken between two machines of a cluster, the machines it
reached SHALL hold what it put there and the machines it did not reach SHALL hold what they held
before. The report of the broken run SHALL name the step that broke and the machine that refused it,
and SHALL name as taken exactly the steps that were taken.

A second run of the same command over the same built deployment and the same value source, once the
machine can be reached again, SHALL leave every machine of the cluster running the deployment: the
entries the first run applied SHALL be undisturbed by the second, and the entries it did not apply
SHALL be applied. No step of the recovery SHALL be an undo of the first run.

#### Scenario: A run broken between two machines names the step that broke

- **WHEN** the route to the second machine of a cluster is cut and the deployment is applied
- **THEN** the run SHALL exit non-zero
- **AND** its last step line SHALL name the step against the machine that could not be reached
- **AND** every entry of the machine it did reach SHALL be running there

#### Scenario: A second run finishes what the broken run left

- **WHEN** the route is restored and the same deployment is applied again from the same build and
  the same value source
- **THEN** the run SHALL complete
- **AND** the entry on the machine the broken run never reached SHALL be running
- **AND** the entry the broken run applied SHALL still be running the generation it applied

#### Scenario: A machine the broken run never reached holds what it held before

- **WHEN** a run is broken before it reaches one machine of a cluster
- **THEN** that machine SHALL hold no artifact and no generated file of the entries the run did not
  reach it with
- **AND** what it held before the run SHALL be unchanged
