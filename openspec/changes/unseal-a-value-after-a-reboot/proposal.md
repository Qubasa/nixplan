## Why

A value lives under `/run` (`lib/util.nix:334`, spent at `lib/resolve.nix:1591`), so a reboot empties
every one of them. The endpoint brings the entries back, their units fail on a file that is not
there, and the only thing that says so is `planner status` printing `value <key> missing on
<machine>` (`cli/report.py:134`). Recovery is a second `apply` from the operator's workstation, which
means a machine cannot come back from a power cut without a human and a network path to it. The last
phase of `tests/e2e/secret-delivery/test_secret_delivery.py:670-711` is that behaviour, asserted
deliberately.

The registry can name one public line per machine: an age recipient, minted on the machine at
provision time, whose private half never leaves it. Sealing each delivered value to that declared
recipient at delivery time lets the machine put its own values back before the entries that read
them start, with no operator, no network and no new secret store.

## What Changes

- The machine registry gains one key, `sealRecipient`: one age native X25519 recipient, `age1`
  followed by 58 characters of the bech32 alphabet, one word. The grammar is `ageRecipientRule`
  beside `wordRule` in `lib/util.nix`, the atom `ageRecipient` in `lib/atoms.nix` reads it, a line
  the grammar refuses is `machine-seal-recipient-malformed` (error) and the value is left out of
  every projection. The key is read in the third projection of the machine reading, beside
  `reserves`, so declaring or rotating a recipient re-keys nothing.
- The library derives a second path for every generated file it already derives a path for: a
  persistent one under a root of its own, beside `util.varsRoot` and outside the reach of the
  recogniser built on it. Nothing about it enters a key input or `varsState`.
- A delivery writes each value's file twice: the plaintext at its `/run` path exactly as today, and
  a copy sealed to the receiving machine's declared `sealRecipient` at the persistent path. Both
  writers do it: the command's own step (`cli/remote.py:326-384`) and the step `secrets/backend.nix`
  renders for the external generator, which carries the recipient as an ordinary rendered word.
- A machine in a value's delivery set stating no recipient is `machine-receives-a-value-unsealed`, a
  warning row, subject `machine:<name>`, naming the values - one row per machine, produced where the
  delivery set is. That machine is delivered to exactly as it is today: plaintext only, no unsealer,
  no recovery.
- The deployment build produces one unsealer per machine that receives a sealed value: the program
  that opens a seal with the machine's own identity file, and a boot-time unit ordered before every
  unit on that machine that opens a value - a system oneshot on a system-scope machine and a user
  unit on a user-scope one. The apply copies it and installs its unit before it writes a value.
- `planner status` gains two lines: a machine holding a sealed copy it cannot open, and a machine
  that seals and holds no sealed copy. Neither changes the exit status.
- **BREAKING** `manifest.json` gains a required table of the machines a value reaches and its
  `version` becomes 2. A record of the previous shape is refused by its version, as a record the
  command does not implement. There is no dual reading and no compatibility path.
- **BREAKING** The last phase of `tests/e2e/secret-delivery/` asserts the opposite of what it
  asserts today: a machine that rebooted holds its values again. The report scenario that a reboot
  used to produce is produced by clearing both copies instead.

This change owns its own registry key and depends on no other open change. The identity file the
unseal reads is minted at provision time by a documented `age-keygen` one-liner whose printed public
line is what the operator pastes into the registry; nothing in this repository ever holds or
transports the private half.

## Capabilities

### New Capabilities

None. Every fact this change adds belongs to a capability that already exists.

### Modified Capabilities

- `planner/machine-platform`: the registry reads `sealRecipient`, in a projection no key consumes,
  and refuses a line the grammar refuses. `run-an-entry-without-root` amends the same registry-keys
  requirement with `scope`; each delta states its own key only, and whichever lands second restates
  the requirement text over the amended base.
- `planner/secret-delivery`: a delivered value has a persistent path derived beside its runtime
  path, sealing moves no key, no delivery set and no state answer, and a delivery-set machine
  stating no recipient is a warning.
- `delivery/generated-values`: what a delivery leaves on a machine, that a machine restores its own
  values after a reboot, that the external generator's rendered step seals too, and the guard on the
  tool the seal depends on.
- `operator/deployment-build`: the per-machine unsealer, the unit's scope, and the machines table of
  the deployment record.
- `operator/apply-command`: the unsealer install step, the sealed write, and the refusals a run
  makes before it dials when it cannot seal.
- `operator/machine-report`: the two seal lines, and the re-statement of the value-absence scenario
  a reboot no longer produces.

## Impact

- `lib/util.nix`: `ageRecipientRule` beside `wordRule`, and `sealedRoot` and `sealedPathOf` beside
  `varsRoot` and `varsPathsIn`.
- `lib/atoms.nix`: the `ageRecipient` atom, reading the grammar the way `restartPolicy` reads
  `restartPolicies`.
- `lib/resolve.nix`: `sealRecipient` in the third projection of the machine reading, beside
  `reserves`, and `machine-seal-recipient-malformed`.
- `lib/plan.nix`: the `machine:<name>` record carries the recipient as an explicit absence beside
  `address`, and `machine-receives-a-value-unsealed` is produced where the delivery set is.
- `operator/read.nix`: the per-machine unsealer record, the recipient published the way the address
  is, the ordering list read off each entry's own mention sites, the machines table of the manifest,
  the version.
- `operator/default.nix`: the unsealer derivation per machine, in the same link farm as the entries.
- `secrets/read.nix`: the recipient as a per-machine rendered word and two file-scope rendered words
  for the sealed path and its parent; `secrets/backend.nix`: the sealing half of the rendered deploy
  step and the sealing program as its one new caller argument.
- `cli/remote.py`, `cli/apply.py`, `cli/manifest.py`, `cli/report.py`, `cli/values.py`,
  `cli/flake-module.nix`: the seal payload, the install step, the machines table, the recipient
  reader off the plan's machine record, the report lines, the sealing program the wrapper names.
- New runtime dependency on `age`, twice: on the operator's workstation, named by the command's own
  wrapper, and on every machine that receives a sealed value, arriving in the closure the apply
  copies rather than from the machine's own `PATH`.
- `tests/e2e/secret-delivery/`: a committed throwaway identity, `sealRecipient` on its machines, a
  provisioning phase, new phases and a rewritten last one. No guest image edit and no snapshot cut
  moves.
- `docs/operator.md` (including the provision-time one-liner) and `CLAUDE.md`.
- `fixtures/minimal-typed-edge/`: the golden plan and `plan/diagnostics.txt` are regenerated - the
  machine records gain the explicit absence and the worked deployment's delivery-set machines earn
  the warning - while the fixture's declarations do not change.
