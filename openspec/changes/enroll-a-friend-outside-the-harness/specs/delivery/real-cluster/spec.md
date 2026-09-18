<!--
A delta against `delivery/real-cluster`, whose current text is
`openspec/specs/delivery/real-cluster/spec.md`. One requirement is modified - `A run applies its
deployment the way an operator does`, copied whole from `:328-342` and extended - and nothing is
added. The requirement already draws the line this change moves: the harness contributes no
realisation and no delivery step of its own, and what it MAY contribute is what only a test needs.
A membership act was outside that line only because no command took it.

What it deliberately does not decide. What the verbs are is `operator/enrollment-command`, and what
a provisioning declaration carries is `operator/machine-provisioning`, both new capabilities of
this change. What enrollment is stays `operator/machine-enrollment`, landed: the phases this
requirement now holds to a command are the phases that capability already requires
(`openspec/changes/enroll-a-friend-machine/specs/operator/machine-enrollment/spec.md:20-92`).
Nothing here touches the delivery, wire, redelivery, reboot, image, value or stateful-service
requirements of this capability. Two changes of this set delta it - the cross-entry proof of
`bind-a-value-an-entry-did-not-generate` and this rewrite of the enrollment folder - which
`openspec/changes/INTEGRATION.md:149-150` records, and this change is the only one of the set
permitted to edit the guest image, for the reason and with the consequence `:152-156` states.

The conditions. Every membership act of the folder that proves enrollment is a shell string the
test composes: the group and the numeric id the server assigned it
(`tests/e2e/friend-enrollment/test_friend_enrollment.py:456-462`), the credential (`:463-469`), the
node list (`:237-245`), the expiry (`:825-828`), and one `install` of the server's own
configuration under a host path of the test's own (`:192-203`, performed at `:393`) - the folder's
own header states that these are `headscale` invocations over ssh that no unit of the deployment
performs (`:15-18`). The hub it places is a module of the folder
(`tests/e2e/friend-enrollment/deployment/modules/mesh/hub.nix`) that states the cluster's own
choices as the module's text: plain transport (`:68`), a listener on every interface (`:72`),
unverified relay clients (`:97-102`), empty relay maps (`:103-104`) and an empty admission policy
(`:127-132`). And the machines it runs on are provisioned by a test machine
(`tests/e2e/guest.nix:319-392`) while the command that verifies those facts creates none of them
(`cli/remote.py:670-729`). The things that genuinely only a test needs stay: the throwaway
presenter that spends a spent key (`test_friend_enrollment.py:248-263`) and the operator's own
userspace membership and its dialing path (`tests/e2e/delivery.py:574-611`, `:614-696`).
-->

## MODIFIED Requirements

### Requirement: A run applies its deployment the way an operator does

The artifacts a run delivers SHALL be built by the same code an operator's build runs, and the steps
that put them on a machine SHALL be the operator's own command. The harness SHALL contribute no
realisation of a plan and no delivery step of its own: what it MAY contribute is what only a test
needs - the machines, the credential a throwaway guest is reached with, the bytes a value source
stands in for, and the reading of the plan its assertions make.

An act against a coordination server SHALL be a step of the operator's command too. A folder SHALL
hold no invocation of a coordination server's own verbs: minting the credential that admits a
machine, reading back what the server admits and ending a membership SHALL each be a verb the
command runs, and a folder SHALL install no copy of a server's configuration at a host path of its
own. What stays the folder's is a presenter no operator has - a second node brought up to spend a
spent credential - and the membership of the host the run is made from, which is a test's own
process rather than a machine of the deployment.

A folder SHALL NOT hold a module a consumer outside this repository would need. Where this
repository publishes a module for placing a service a folder places, the folder SHALL compose that
module, receiving it the way it receives the deployment build, and the choices that folder's own
cluster makes SHALL be declarations of that folder's deployment rather than lines of a module's
text. The machines a folder runs on SHALL be provisioned by the declaration this repository
publishes for provisioning a machine, so that the machines under test and a reader's own machine
are one text.

#### Scenario: The artifacts were built by the operator's command

- **WHEN** a folder's deployment is put on its machines
- **THEN** each artifact delivered SHALL be the one the operator's build produced for that plan key,
  taken from the manifest that build wrote
- **AND** the copy, the value write and the activation SHALL each be a step of the operator's command
- **AND** the folder SHALL hold no code that realises a plan or delivers an artifact

#### Scenario: A membership act is a verb of the command

- **WHEN** a folder mints a join credential, reads what the coordination server admits, or ends a
  membership
- **THEN** each SHALL be a verb of the operator's command run against the built deployment
- **AND** the folder SHALL hold no invocation of the coordination server's own verbs and no copy of
  its configuration installed at a host path

#### Scenario: A folder composes the published module it would otherwise hold

- **WHEN** a folder places a service this repository publishes a module for
- **THEN** it SHALL compose that module, received as an argument the way the deployment build is
- **AND** the choices its own cluster makes SHALL be stated in its own deployment

#### Scenario: The machines a folder runs on are provisioned by the published declaration

- **WHEN** the image a folder's machines boot is read for a fact a run verifies before it writes
- **THEN** that fact SHALL come from the declaration this repository publishes for provisioning a
  machine
- **AND** the image SHALL state only what a test machine needs beyond it
