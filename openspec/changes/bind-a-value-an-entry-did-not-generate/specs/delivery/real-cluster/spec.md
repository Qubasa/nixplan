<!--
A delta against `delivery/real-cluster`, whose current text is
`openspec/specs/delivery/real-cluster/spec.md`. One requirement is added; nothing is modified.

What this delta deliberately does not decide. It states no rule about which paths a reading shows -
that is the `realiser/portable-service-image` delta of this change, and the two are written so this
one observes what that one decides. It states nothing about the flakelet realiser's own artifact:
`tests/e2e/shared-postgres/` already reads a peer's value
(`tests/e2e/shared-postgres/deployment/modules/app/client.nix:17-22,49`) under that realiser
(`tests/e2e/shared-postgres/test_shared_postgres.py:533`), so the rule's other half is observed
there with no edit and needs no requirement of its own. It states nothing about what a report
answers: `answer-a-machine-question-as-a-record` owns the record a machine question returns, and
`openspec/changes/INTEGRATION.md` records the order.

Which folder, and why not a new one. A cross-entry value read needs one machine, because the owner's
placement puts the value on the reader's machine; `tests/e2e/portable-image/` already runs one
booted machine (`tests/e2e/portable-image/test_portable_image.py:298`) and already owns every
`portablectl` claim. A folder's cut is keyed by the guest image, the machine names and the stage's
disk figure (`tests/e2e/delivery.py:877-942`, the figure declared part of the key at `:919-923`), so
a deployment edit moves no key and the phase resumes the cut the folder already warms. A folder of
its own would pay a full cut and could not reuse the report module:
`tests/unit/layers.nix:1036-1039` refuses a folder whose text names a sibling folder and
`:1041-1044` refuses a byte-equal copy of a sibling's file.

The conditions. That folder's only delivered secret is the entry's own generator - `vars.upstream`
in `tests/e2e/portable-image/deployment/modules/report/watch.nix:14-22`, named at `:75`, recorded as
`SECRET_VALUE = "watch:vars/upstream"` in `test_portable_image.py:77` - and its one cross-entry read
carries a configuration file's path rather than a value
(`tests/e2e/portable-image/deployment/modules/mirror/copy.nix:9-13` against `watch.nix:66-68`), so
no machine in this repository has ever been asked whether an image-realised consumer can open a
value a different entry generated. The proof has to be the unit opening the file on the machine and
not the plan recording it: `imageReader.hostPaths` answering `[ ]` for such a consumer is exactly
what a description-level assertion would not catch, the bytes being on the machine either way.
-->

## ADDED Requirements

### Requirement: An image-realised consumer opens a value another entry generated

The end-to-end layer SHALL apply a deployment in which one entry generates a value, a second entry
realised as a portable-service image declares a read of the export backed by that value, and both
are placed on one machine. The proof SHALL be the consuming unit opening the file on the machine and
SHALL NOT be the plan or the artifact recording it: the bytes reach the machine whether or not the
image is shown the path, so a description-level assertion cannot tell a working bind from a missing
one.

The statement that shows the value SHALL be read off the artifact the realiser built, not
constructed by the harness, and the file the unit opens SHALL be compared inside that unit's own
view of the filesystem, because the whole failure this requirement observes is a path that exists on
the host and not inside the unit.

One value SHALL be one file on the machine however many entries read it: the delivery writes the
path the value's own entry records, and the owner and the reader are shown the same path.

#### Scenario: The consumer's unit opens the peer's value on the machine

- **WHEN** the deployment has been applied and the consuming entry's units are running
- **THEN** the consuming unit SHALL have read the value's bytes from the path the plan records
- **AND** what it read SHALL equal what the generator produced
- **AND** the observation SHALL be made on the machine rather than against the plan

#### Scenario: The bind comes from the artifact's own unit file

- **WHEN** the consuming entry's rendered unit file is read out of the delivered artifact
- **THEN** it SHALL carry one statement showing the value's path to the unit
- **AND** the image SHALL carry a mount point at that path
- **AND** the harness SHALL have constructed neither

#### Scenario: One file on the machine serves both entries

- **WHEN** the machine is asked for the value's path after the apply
- **THEN** exactly one file SHALL be there
- **AND** both the owning entry's unit and the consuming entry's unit SHALL have opened that one
  file
- **AND** the record it carries SHALL be the record the value's own entry states
