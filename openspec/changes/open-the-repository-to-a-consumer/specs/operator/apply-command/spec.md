<!--
A delta against `operator/apply-command`, whose requirements live in the unarchived
`apply-deployments-with-an-operator-command` change. Only *The command refuses before it dials*
changes, and it is restated below as it will read.

The command already makes every refusal it can from the plan, the deployment record and the value
source before the first machine is contacted. What a first-time operator wants is that prefix on its
own: run every one of those refusals, print the steps the walk would take, and contact nothing.
`make-an-apply-observable`, which lands after this change, adds refusals of its own to this
capability under a requirement of its own and leaves this one alone.
-->

## MODIFIED Requirements

### Requirement: The command refuses before it dials

Every refusal the command can make from the plan and the deployment record alone SHALL happen before
the first machine is contacted, and SHALL name the entry, the field and the value at fault. A
deployment the planner reports as inapplicable SHALL NOT be applied, and an entry the caller names
that the plan does not carry SHALL be refused naming the entries that exist.

An apply SHALL be askable for what it would do without doing it. Asked that way, the command SHALL
make every refusal above, SHALL print the steps it would take in the order it would take them, and
SHALL contact no machine. The steps it prints SHALL be the steps a real run prints, so the two are
comparable line by line. It SHALL be a mode of applying rather than a separate subcommand, and SHALL
honour the same restriction, value source and connection options a real run is given.

Asking what a run would do SHALL NOT report what a machine currently holds. That is a question for
the machine, and answering it is a dial.

#### Scenario: A deployment the planner refuses is not applied

- **WHEN** the command is asked to apply a deployment whose diagnostics carry an error
- **THEN** it SHALL refuse with the rendered diagnostics table
- **AND** no machine SHALL have been dialled

#### Scenario: An entry named on the command line is not in the plan

- **WHEN** the caller restricts the command to an entry the plan does not carry
- **THEN** it SHALL refuse naming the entry given and the entries the plan carries
- **AND** no machine SHALL have been dialled

#### Scenario: A run is asked what it would do

- **WHEN** an applicable deployment is applied in the mode that asks rather than acts
- **THEN** the command SHALL print the value writes, the copies and the activations it would
  perform, in the order it would perform them
- **AND** those lines SHALL be the lines the same run without that mode prints
- **AND** no machine SHALL have been dialled

#### Scenario: A dry run of a deployment the planner refuses

- **WHEN** the mode that asks rather than acts is given a deployment, a restriction or a value
  source the command would refuse
- **THEN** it SHALL refuse exactly as a real run refuses, with the same message
- **AND** SHALL print no step
