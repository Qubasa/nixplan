## Purpose

Says where the bytes of a generated value come from before a plan is evaluated: the state the
planner is handed is read out of a real store backend rather than written by a test, the operator
reads the bytes of a public file only, and a run whose stored values disagree with the declaration
they were generated from refuses instead of reporting success.

## ADDED Requirements

### Requirement: The state a plan is evaluated against is read from a backend

The state the planner is handed SHALL be obtained by asking a store backend which of a plan's
declared files it holds, once per declared file, and SHALL record for each one whether it is
present. It SHALL NOT be written by the test that asserts against the resulting plan.

A file the backend does not hold SHALL be recorded as absent rather than as present with no bytes,
because the planner renders those two differently and only one of them is a value that exists.

A backend answer that is neither "held" nor "not held" SHALL fail the run naming the value, the
file and the answer, rather than being read as either.

#### Scenario: A held file becomes a present value

- **WHEN** the backend holds every file a value declares
- **THEN** the state handed to the planner SHALL record each of them present
- **AND** the plan SHALL carry that value with its files rather than an absence marker

#### Scenario: An ungenerated value is absent, not empty

- **WHEN** the backend holds no file of a declared value
- **THEN** the state SHALL record the value's files absent
- **AND** the plan SHALL carry the absence the planner produces for an ungenerated value

#### Scenario: An unreadable backend answer fails the run

- **WHEN** the backend's existence check answers with neither of the two statuses it may answer with
- **THEN** the run SHALL fail naming the value, the file and the status
- **AND** the state SHALL NOT record the file either way

### Requirement: The operator reads the bytes of a public file only

The bytes of a file whose declaration makes it secret SHALL NOT be read by the process that builds
the plan, and SHALL NOT appear in the state that process hands the planner. Only a file whose
declaration makes it public SHALL have its bytes read, because a public value travels inside the
plan and a secret one travels beside it.

#### Scenario: A public file's bytes reach the plan

- **WHEN** a value declares a public file the backend holds
- **THEN** its bytes SHALL be read and recorded in the state
- **AND** the plan SHALL carry them

#### Scenario: A secret file's bytes are never fetched

- **WHEN** a value declares a secret file the backend holds
- **THEN** the retrieval the backend offers SHALL NOT be invoked for it
- **AND** neither the state nor the plan SHALL carry its bytes

### Requirement: A failed generation is not a delivery

Generation SHALL be invoked before the delivery that depends on it, and a generation that fails
SHALL fail the run naming the value that failed. A value whose files the backend does not hold after
generation reported success SHALL fail the run naming the value and the files, rather than being
delivered as an absence.

#### Scenario: A generator that fails stops the run

- **WHEN** a generator exits non-zero
- **THEN** the run SHALL fail naming that value
- **AND** no delivery SHALL be attempted for it

#### Scenario: A generator that produced nothing stops the run

- **WHEN** generation reports success and the backend holds none of the declared files
- **THEN** the run SHALL fail naming the value and the missing files

### Requirement: A stored value that no longer matches its declaration is refused

The external tool regenerates conservatively and records no provenance, so an interrupted or failed
run leaves one value regenerated and a value derived from it stale, and the next invocation reports
success. The run SHALL therefore record, beside each stored value, the identity the plan gives the
declaration that value was generated from, and SHALL compare the two before delivering anything.

A disagreement SHALL refuse the run, naming the value and both identities. A stored value with no
recorded identity SHALL be treated as a disagreement, not as a match. The refusal SHALL name the
action that resolves it.

#### Scenario: A regenerated dependency leaves its consumer stale

- **WHEN** a value's declaration changes, it is regenerated, and a value that reads it is not
- **THEN** the next run SHALL refuse before delivering, naming the consuming value
- **AND** SHALL name both the identity recorded for the stored value and the identity the plan gives
  its declaration now

#### Scenario: A stored value of unknown provenance is refused

- **WHEN** a value the backend holds carries no recorded identity
- **THEN** the run SHALL refuse naming that value
- **AND** SHALL NOT treat the absence of a record as agreement

#### Scenario: An unchanged declaration is not regenerated

- **WHEN** every stored value's recorded identity agrees with the plan
- **THEN** the run SHALL proceed
- **AND** no value SHALL be regenerated

### Requirement: An unavailable generator is a skip, never a pass

Where the external tool cannot be resolved, the run SHALL skip itself and SHALL state the reason,
naming the variable or reference that named nothing. It SHALL NOT pass by asserting against state a
test wrote, because a passing run whose subject was absent is indistinguishable from a run that
proved something.

#### Scenario: The tool cannot be resolved

- **WHEN** the reference naming the external tool resolves to nothing
- **THEN** the run SHALL skip
- **AND** the skip reason SHALL name the reference
- **AND** no assertion about a generated value SHALL be reported as satisfied
