<!--
A delta against `openspec/specs/delivery/generated-values/spec.md`. Every requirement below is
ADDED. That spec says where the bytes of a generated value come from and what a run refuses before
it delivers; these say what a delivery leaves on the machine and what the machine does with it
without an operator. Nothing in it is contradicted: the bytes still originate outside the plan, the
public-only read rule is untouched, and the provenance refusal is untouched.

The conditions:

- `cli/remote.py:326-384` is the only step that writes a value for the command: the bytes arrive on
  the step's input stream, the script is a function of the record, the file is created `0600` at a
  temporary, owned, chmodded and moved, and the step prints `changed` or `unchanged`. The parent
  chain is `0711` (`cli/remote.py:371-377`), for the reason the invariant index gives: a file the
  record opens to an account is unreachable behind a directory only root may traverse.
- `secrets/backend.nix:82-88` is the other writer, the `deploy.remote` step rendered for the
  external generator. Its remote half is one `ssh` command whose `'$4'` to `'$7'` are re-parsed on
  the machine and held by `util.wordRule` (`lib/util.nix:129-167`) alone, and its words are the ones
  `secrets/read.nix:280-324` states, so a word this change adds to the step is checked by the rows
  that already read that table (`secrets-rendered-word-refused`, `secrets/read.nix:212-228`).
- `tests/e2e/secret-delivery/test_secret_delivery.py:670-711` is the reboot phase: it reboots the
  reader's machine, asserts the token's path is gone, asserts the report names it, applies again and
  starts the unit by hand. It is last because `/run` is what a reboot empties, and nothing is
  restored between phases (`tests/e2e/secret-delivery/test_secret_delivery.py:12-31`). That test's
  claim is inverted by this change.
- The sealing tool is `age`. Its usage block and its "SSH keys" section state that a recipient may
  be an SSH public key (`ssh-ed25519 AAAA...`, `ssh-rsa AAAA...`), that `-R` takes a file of
  recipients and `-i` an identity file, and that `ssh-agent` is not supported, which is why the
  unseal reads the host key file directly and therefore runs as root. `design.md` D1 records the
  version constraint and what the guard is.
-->

## ADDED Requirements

### Requirement: A delivery leaves a copy the machine can open by itself

Every layer that writes a generated value's file on a machine SHALL additionally write a copy of
that file at the file's persistent path, sealed so that only the machine it was written to can open
it. The seal SHALL be made to the identity the machine's registry record declares, and SHALL be made
where the bytes already are rather than on the machine, so that a machine that cannot open its own
seal is a machine the delivery reached and not a machine the delivery depended on.

The write of the plaintext SHALL be unchanged: the same path, the same ownership and mode from the
value's record, the same `0711` directory chain, the same temporary-and-move discipline, and the
same answer about whether the bytes moved. The sealed copy SHALL be written before the plaintext, so
that a run interrupted between the two leaves a machine whose sealed copy is this delivery's and
never one whose sealed copy is older than the plaintext beside it.

The sealed copy SHALL be readable by the privileged account alone, whatever the value's record says
about its plaintext: it is ciphertext, and the only reader is the unsealing step, which must read the
machine's private host key and therefore runs privileged. Its directories SHALL be traversable and
listable by nobody else, because no account reaches a file inside them.

The sealed copy SHALL be written on every delivery rather than only where the bytes moved, because a
seal is not reproducible: two sealings of one file differ, so no comparison of seals says anything,
and the answer about whether the bytes moved SHALL be taken from the plaintext as it is today.

A machine whose registry record declares no identity the seal can be made to SHALL be delivered to
exactly as it is before this change: the plaintext and nothing else.

#### Scenario: A delivery writes a sealed copy beside the value

- **WHEN** a value is delivered to a machine whose record declares an identity that can be sealed to
- **THEN** the machine SHALL hold the plaintext at the value's path with the record's ownership and
  mode
- **AND** the machine SHALL hold a sealed copy at that file's persistent path

#### Scenario: A sealed copy is readable by the privileged account alone

- **WHEN** a machine holds a sealed copy of a value whose record opens the plaintext to an
  unprivileged account
- **THEN** the sealed copy SHALL be owned by the privileged account and readable by no other
- **AND** the directory holding it SHALL be readable by no other

#### Scenario: A machine with no sealable identity is delivered to as before

- **WHEN** a value is delivered to a machine whose record declares no identity the seal can be made
  to
- **THEN** the steps taken against that machine SHALL be the steps taken before this change
- **AND** no sealed copy SHALL be written to it

### Requirement: A machine restores its own values without an operator

A machine that holds sealed copies SHALL restore the plaintext of each of them before the entries
that read them start, using a key only it holds, with no operator action and no network. Restoring
SHALL write each plaintext at the value's own path with the ownership and mode the value's record
states, and SHALL leave a plaintext that is already there untouched, so that a restore can never
replace a fresher delivery with an older seal.

A sealed copy the machine cannot open SHALL leave that value's plaintext absent and SHALL be named:
the restoring step SHALL report the value it could not open and SHALL still restore every value it
could. The machine SHALL then be exactly where it is before this change, with the entries that read
the value failing on a file that is not there and the report naming it, and the recovery SHALL be a
second apply.

The restoring step SHALL NOT distinguish a copy sealed to a rotated identity from a copy whose bytes
were damaged: both are copies it cannot open, and it SHALL say that rather than claim to know which.

#### Scenario: A machine that rebooted holds its values again

- **WHEN** a machine holding sealed copies of every value delivered to it is rebooted
- **THEN** every one of those values SHALL be at its own path again once the machine has booted,
  with the ownership and mode its record states
- **AND** no command SHALL have been run against that machine between the reboot and the
  observation

#### Scenario: A reader started after a reboot reads the delivered bytes

- **WHEN** an entry that declares a read of a value is started on a machine that has rebooted and
  restored its own values
- **THEN** the unit SHALL start
- **AND** the bytes it reads SHALL be the bytes the last delivery wrote

#### Scenario: A copy the machine cannot open leaves the value absent and names it

- **WHEN** a machine's sealed copy of one value is replaced by one it cannot open and the plaintext
  of that value is cleared
- **THEN** restoring SHALL report that value as one it could not open
- **AND** that value's path SHALL hold nothing, and every other value of that machine SHALL be
  restored

### Requirement: The delivery the external generator performs seals what it writes

The step rendered for the external generator's deploy hook SHALL write the sealed copy beside the
plaintext for every machine of a delivery set whose identity the caller names a recipient for, and
SHALL write the plaintext alone for a machine it names none for. It SHALL carry no byte of a value
and no recipient of its own: the recipient and the sealing program SHALL reach it as the caller's
arguments, the way the store backend's own retrieval program already does, because the plan holds
neither and the external contract carries neither.

Every word the step gains SHALL be held to the grammar one word of a rendered shell step can carry,
by the same table the step is rendered from and the rows are derived from, so that a path the
rendered step cannot carry is a row before it is a script.

#### Scenario: The rendered step writes a sealed copy for a machine that seals

- **WHEN** the deploy step is rendered for a plan whose delivery set names a machine the caller
  gives a recipient for
- **THEN** the step SHALL write that machine's sealed copy at the file's persistent path and the
  plaintext at the file's own path
- **AND** the rendered text SHALL carry no byte of any value

#### Scenario: A machine the caller names no recipient for is delivered without a seal

- **WHEN** the deploy step is rendered for a plan whose delivery set names a machine the caller
  gives no recipient for
- **THEN** the step SHALL write that machine's plaintext and no sealed copy
- **AND** the step SHALL still be rendered for every other machine of the set

### Requirement: The sealing tool is held to the behaviour this design depends on

The behaviour this change depends on - that the tool seals to an SSH public key given as a
recipient and opens the result with the corresponding private key file - SHALL be asserted against
the resolved tool rather than assumed, and the assertion SHALL fail naming the design decision when
the resolved tool stops behaving that way, because the tool's own documentation describes the
feature as a convenience and the project's key types as the only ones accepted.

Where the tool cannot be resolved the assertion SHALL skip and SHALL state what named nothing, and
SHALL NOT pass: an unreadable signal is not evidence that the behaviour still holds.

#### Scenario: The resolved tool seals to an ssh recipient and opens it with the ssh identity

- **WHEN** the resolved tool is given an `ssh-ed25519` public key as a recipient and the matching
  private key as an identity
- **THEN** the bytes it opens SHALL be the bytes it sealed
- **AND** a recipient of a type the design does not admit SHALL be refused by the tool rather than
  sealed silently

#### Scenario: A tool that cannot be resolved skips rather than passes

- **WHEN** the reference naming the sealing tool resolves to nothing
- **THEN** the assertion SHALL skip naming that reference
- **AND** no claim about sealing SHALL be reported as satisfied
