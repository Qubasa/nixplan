<!--
A delta against `realiser/flakelet-artifact`, whose base text lives in the unarchived changes
`emit-flakelet-service-artifacts`, `deliver-secrets-across-machines` and
`report-every-refusal-as-a-row`. `openspec/specs/` is empty in this repository, so the base text is
read from those changes.

Every requirement below is ADDED. What the artifact holds, the `[Install]` decision, and the
endpoint's own name and unit rules are unchanged.

The condition: an activation of an artifact the endpoint already holds is the endpoint's own no-op,
which `tests/e2e/wired-pair/test_wired_pair.py:553-562` pins by comparing a unit's main process
identifier. That is correct behaviour for an unchanged artifact and is exactly why a value's bytes
moving cannot be answered by re-activating.
-->

## ADDED Requirements

### Requirement: An unchanged artifact's activation is a no-op, and what that implies is stated

Activating an artifact the machine already holds SHALL leave the entry's processes untouched, and
this realiser SHALL NOT attempt to detect a change in anything outside the artifact. An artifact is
a function of the plan entry; bytes delivered beside it are not part of it, and making an activation
depend on them would make one entry's identity depend on a file no artifact carries.

It SHALL therefore be stated, as a property of this realiser rather than as an omission, that a
change in a delivered value produces no change in the artifact and no change in what an activation
does. The layer that wrote the value is the layer that knows it moved, and it is where the reader's
restart belongs.

#### Scenario: An artifact activated twice

- **WHEN** an unchanged artifact is activated twice
- **THEN** the entry's units SHALL keep the same main processes
- **AND** the endpoint SHALL record no new generation

#### Scenario: A delivered value moves under an unchanged artifact

- **WHEN** a value an entry reads is rewritten with different bytes and the unchanged artifact is
  activated
- **THEN** the activation SHALL change nothing
- **AND** the entry's processes SHALL still hold the previous bytes until something restarts them

### Requirement: A unit's reload is available to the layer that needs it

Where a plan entry records the units a configuration file's `reload` list names, this realiser SHALL
render the units so that reloading one is possible without re-activating the entry: a unit that
declared a reload command SHALL carry the corresponding directive, and a unit that did not SHALL be
restartable.

Nothing in this realiser SHALL issue a reload. It renders units and the endpoint links and starts
them; which unit to reload, and when, is the caller's decision, and stating it here would put a
second activation model beside the endpoint's.

#### Scenario: A unit declaring a reload command

- **WHEN** an entry's unit records a reload command
- **THEN** the rendered unit file SHALL carry the corresponding directive
- **AND** reloading that unit on the machine SHALL not require the artifact to be re-activated

#### Scenario: The realiser issues nothing

- **WHEN** an artifact is activated
- **THEN** the activation SHALL consist of what the endpoint does with the artifact
- **AND** no reload or restart of any unit SHALL be issued by this realiser
