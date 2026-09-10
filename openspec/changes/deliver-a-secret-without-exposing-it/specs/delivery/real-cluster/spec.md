<!--
A delta against `delivery/real-cluster`, which lives in the unarchived `prove-plan-on-real-machines`
change and is already modified by `strip-planner-tests-to-unit-and-e2e`,
`resume-e2e-machines-from-snapshots`, `deliver-secrets-across-machines`,
`generate-values-with-nixos-secrets`, and `apply-deployments-with-an-operator-command`. Nothing
existing changes: this adds the negative the layer has never observed.

"The bytes travel beside the artifacts, never inside them" in `deliver-secrets-across-machines`
already holds a run to searching the plan and every artifact, and
`tests/e2e/secret-delivery/test_secret_delivery.py:279-283` does exactly that plus the file's mode
and owner. What no test reads is the delivery itself: with `cli/remote.py:125-145` the plaintext is
an element of an argument vector on both hosts for the duration of one ssh session, and every
assertion in the layer looks at the state after the session closed. This requirement is about the
window, and about the observation of it not becoming a second copy of the value.

`open-the-repository-to-a-consumer` owns `tests/e2e/newcomer/` and the requirement about a
newcomer's walk. This delta adds no scenario there.
-->

## Purpose

Defines what the machine layer observes about a delivery while it is happening, rather than about
the state it left behind, and how a run establishes the absence of bytes without holding a second
copy of them.

## ADDED Requirements

### Requirement: A delivery in flight is observed to leave the bytes nowhere

While a value is being delivered, its bytes SHALL appear in no process on either host: not in the
arguments of the local process that sends them, and not in the arguments of the remote command that
writes them. They SHALL appear in no record the receiving machine keeps of the session either. The
observation SHALL cover the window in which the delivery happens rather than the state after it
closed, because that window is where an argument vector lives.

The observation SHALL NOT become a copy of the value. A run SHALL compare what it observed against
what the plan implies, by digest, so that the observer holds no needle and a failure names a
mismatch rather than a value. No assertion of this layer SHALL print, store, or search for the bytes
of a delivered value in order to establish their absence.

#### Scenario: No process on either host carries the delivered bytes

- **WHEN** a value is delivered to the machines its entry names
- **THEN** the arguments of every process the operator's host ran for the delivery SHALL be
  reproducible from the plan alone
- **AND** the arguments of every process the receiving machine ran for it SHALL be reproducible the
  same way
- **AND** delivering a different value of the same length SHALL leave both sets unchanged

#### Scenario: The observation names a digest and never the value

- **WHEN** an observation of a delivery fails
- **THEN** the failure SHALL name the digest observed and the digest the plan implied
- **AND** no artifact of the run, no captured output, and no assertion message SHALL hold the bytes
  of the value

#### Scenario: A machine's own log holds no delivered byte

- **WHEN** the receiving machine's record of the delivery session is read after the delivery
- **THEN** it SHALL hold no byte of the value
- **AND** the count of occurrences SHALL be the evidence, rather than any matched text
