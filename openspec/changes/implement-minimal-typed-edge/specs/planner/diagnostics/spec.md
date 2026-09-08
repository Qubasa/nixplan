## Purpose

Defines evaluation as total: a plan and a table of problems come out together, no check aborts the pass, and every refusal is a record a user interface can draw and a command line can filter. This is the property that lets forty instances with two mistakes render as forty instances with two marks rather than as one error message.

## ADDED Requirements

### Requirement: Evaluation returns a plan and a diagnostics table, always both

The library's entry point SHALL return both a plan and a diagnostics table for every input it is given, including inputs carrying authoring mistakes. It SHALL NOT return a plan alone and SHALL NOT return diagnostics alone.

#### Scenario: A deployment with one bad instance

- **WHEN** a deployment declares more than one instance and one of them carries a mistake that produces an error row
- **THEN** the result SHALL contain plan entries for the instances that are correct
- **AND** the diagnostics table SHALL contain the row for the one that is not

#### Scenario: A deployment with no mistakes

- **WHEN** a deployment produces no rows at all
- **THEN** the result SHALL still contain a diagnostics table
- **AND** that table SHALL be empty rather than absent

### Requirement: No evaluation path raises

Forcing the whole result, including every plan entry, every export value and every diagnostic record, SHALL NOT raise. The library SHALL NOT call any Nix builtin whose failure mode is to raise in place of returning a value, and SHALL use the type library's verification entry point rather than its assertion entry point.

#### Scenario: Every authoring mistake at once

- **WHEN** a deployment carries an unwired slot, a secret read, a keyset violation, an arity violation and an interface mismatch simultaneously
- **THEN** deeply forcing the result SHALL succeed
- **AND** the diagnostics table SHALL contain one row per mistake

#### Scenario: A raising helper is introduced

- **WHEN** any library source file calls the type library's assertion entry point or a raise builtin
- **THEN** the test suite SHALL fail
- **AND** the failure SHALL name the file and the call

#### Scenario: A module's own code raises a catchable error

- **WHEN** a module under evaluation raises a catchable error inside its receiving half
- **THEN** the planner SHALL record an error row naming that module
- **AND** the rest of the plan SHALL still be produced

#### Scenario: A module's own code raises an uncatchable error

- **WHEN** a module under evaluation fails in a way the interpreter does not let a caller catch
- **THEN** the failure MAY propagate
- **AND** the library SHALL document which failures fall into this class rather than claiming to contain them

### Requirement: A diagnostic record has a fixed shape

Every diagnostic SHALL be a record carrying a stable identifier for its kind, the subject it is about, a severity, a one-line message, the evidence that produced it and the resolution its author is expected to apply. The subject SHALL be a plan key, a file path relative to the deployment root, or an issue identifier.

#### Scenario: Two runs over one input

- **WHEN** the same input is evaluated twice
- **THEN** the diagnostics tables SHALL be equal, including row order
- **AND** the identifiers SHALL be equal

#### Scenario: A row carries its resolution

- **WHEN** any row is produced
- **THEN** it SHALL carry a resolution line describing an edit a person can make
- **AND** the resolution SHALL name the file or the command rather than restating the problem

### Requirement: Severity decides the apply and not the evaluation

A diagnostic SHALL carry exactly one of two severities. An error SHALL block an apply. A warning SHALL NOT block an apply. Neither SHALL stop evaluation, and neither SHALL remove a plan entry that would otherwise exist.

#### Scenario: An error blocks the apply

- **WHEN** the diagnostics table contains at least one error
- **THEN** the result SHALL report that the plan is not applicable
- **AND** the plan SHALL still be readable in full

#### Scenario: A warning does not block the apply

- **WHEN** the diagnostics table contains warnings and no errors
- **THEN** the result SHALL report that the plan is applicable

#### Scenario: A module author cannot set a severity

- **WHEN** a module attempts to declare the severity of a row the planner produces
- **THEN** the declaration SHALL have no effect on that row's severity
- **AND** the planner SHALL emit a warning row naming the attempt

### Requirement: Rows render to the committed text format

The library SHALL render a diagnostics table to the row format the example folders already use, so that a rendered table can be compared against a committed file. Rendering SHALL be a function of the table alone, and SHALL NOT read the deployment again.

#### Scenario: Rendering the folder's own rows

- **WHEN** the minimal-typed-edge deployment is evaluated and its table rendered
- **THEN** the output SHALL contain one row per row in the committed diagnostics file for that deployment
- **AND** each rendered row SHALL carry the same subject, severity and message as the committed one

#### Scenario: Rendering is stable under unrelated change

- **WHEN** a deployment gains an instance that produces no rows
- **THEN** the rendered output SHALL be unchanged
