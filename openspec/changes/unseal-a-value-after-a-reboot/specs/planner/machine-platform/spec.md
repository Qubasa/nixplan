<!--
A delta against `openspec/specs/planner/machine-platform/spec.md`. One requirement is MODIFIED: the
registry-keys requirement, because its live text has the registry refuse any key it does not name,
and this change adds one, `sealRecipient`. The block below is the full requirement copied from the
live spec and amended; the amendments are the key in the read list, the paragraph about how it is
read, and the last two scenarios.

The seam: `run-an-entry-without-root` amends the same requirement with `scope`. Each change's delta
states its own key only and reads the other as a seam - whichever lands second restates the
requirement text over the amended base. INTEGRATION.md records this.

The conditions:

- The precedent for a registry fact no key consumes is the reservation: `machineReservations` is the
  third projection of the machine reading (`lib/resolve.nix:617-619`), outside `machineRecords`
  (`:576-593`) and outside `targetOf` (`:599-613`), because `machineKey` hashes the record every
  placed entry and per-placement value depends on. `sealRecipient` is read in the same projection
  for the same reason: rotating a recipient must not re-key entries or values.
- The recipient sits in no target, so a malformed line drops no placement - unlike a malformed
  `address`, whose absence makes the target incomplete. The row is `machine-seal-recipient-malformed`
  and the value is left out of every projection.
- The grammar has one home, `ageRecipientRule` beside `wordRule` in `lib/util.nix`, and the atom
  `ageRecipient` in `lib/atoms.nix` reads it, the way `restartPolicy` reads `restartPolicies`
  (`lib/atoms.nix:17-101`).
- The plan's `machine:<name>` record (`lib/plan.nix:1404-1419`) carries the recipient as an explicit
  absence beside `address`, kept the way a placed entry's `closure` and `units` are kept, because an
  absent field means the plan does not know.
-->

## MODIFIED Requirements

### Requirement: A machine declares the system it runs and the service manager that runs its units

The machine registry SHALL read `address`, `tags`, `system`, `serviceManager`, an optional
microarchitecture, an optional statement of the host resources the machine already holds and an
optional `sealRecipient`, and SHALL refuse any other key with an error row naming the registry
file. A selected machine that declares no `system`, or no `serviceManager`, SHALL produce an error
row naming the machine and the registry file, because a placement on it has no derivable target. The
plan SHALL still be emitted in that case, containing the machine's entry and every entry placed on
it, so that a deployment mid-migration is diagnosable rather than unevaluable.

`sealRecipient` SHALL be one age native X25519 recipient: `age1` followed by 58 characters of the
bech32 alphabet, one word, no spaces, its grammar stated once in the library and read by the atom
and the row alike. A line the grammar refuses SHALL be a `machine-seal-recipient-malformed` error
row naming the machine and the registry file, and the value SHALL be left out of every projection.
The recipient SHALL sit in no target, so refusing it SHALL drop no placement. The key SHALL be read
in a projection no key consumes, and the plan's machine record SHALL carry it as an explicit
absence beside the address, so that a reader can tell a machine that declares no recipient from a
record written before the field existed.

A machine's key SHALL be a function of the facts the plan records about the machine - what a consumer
dials, what a placement selects on, what a target is elaborated from - so that changing a machine's
architecture re-keys every entry placed on it. A statement of what the machine already holds, and
the recipient a delivery seals to, SHALL NOT be among those facts and SHALL NOT enter that key, nor
the key of any entry or generated value placed on the machine: neither says anything about what is
built for the machine, and re-keying an entry on account of either would ask for a redelivery, and a
generated value for a regeneration, of bytes that are still correct.

#### Scenario: A machine that reserves a port keys as it did

- **WHEN** a machine's declaration gains a statement of the resources it already holds and nothing
  else changes
- **THEN** the machine's key SHALL be the key it had
- **AND** every entry placed on that machine SHALL keep its key
- **AND** every generated value delivered to that machine SHALL keep its key

#### Scenario: A fully declared machine

- **WHEN** the registry declares a machine with an `address`, a `tags` entry, a `system` and a
  `serviceManager`
- **THEN** the planner SHALL emit no registry row
- **AND** the machine's plan entry SHALL record all four values

#### Scenario: A machine omits its address

- **WHEN** the registry declares a machine with no `address` and a placement selects it
- **THEN** the planner SHALL emit one error row naming the machine, the address as the key it did
  not declare, and the registry file
- **AND** the plan SHALL contain the machine's own record and no entry placed on it

#### Scenario: A machine omits its system

- **WHEN** the registry declares a machine with no `system` and a placement selects it
- **THEN** the planner SHALL emit an error row naming the machine and the registry file
- **AND** the plan SHALL contain the machine's own record and no entry placed on it

#### Scenario: A machine omits its service manager

- **WHEN** the registry declares a machine with no `serviceManager` and a placement selects it
- **THEN** the planner SHALL emit an error row naming the machine and the registry file
- **AND** the plan SHALL contain the machine's own record and no entry placed on it

#### Scenario: A machine declares an address that is not a name

- **WHEN** the registry declares an `address` as a value of some other kind and a placement selects
  that machine
- **THEN** the planner SHALL emit the row about the malformed declaration and the row about the
  incomplete target
- **AND** no entry SHALL be planned for that machine

#### Scenario: A machine changes architecture

- **WHEN** a machine's declared `system` changes and nothing else does
- **THEN** the machine's key SHALL change
- **AND** every entry placed on that machine SHALL be re-keyed

#### Scenario: A machine states a seal recipient and keys as it did

- **WHEN** a machine's declaration gains a `sealRecipient` and nothing else changes
- **THEN** the machine's key SHALL be the key it had
- **AND** every entry placed on that machine and every generated value delivered to it SHALL keep
  its key
- **AND** the machine's plan record SHALL carry the recipient

#### Scenario: A seal recipient the grammar refuses

- **WHEN** the registry declares a `sealRecipient` that is not one age native recipient
- **THEN** the planner SHALL emit a `machine-seal-recipient-malformed` error row naming the machine
  and the registry file
- **AND** the value SHALL appear in no projection, and every entry placed on that machine SHALL
  still be planned
