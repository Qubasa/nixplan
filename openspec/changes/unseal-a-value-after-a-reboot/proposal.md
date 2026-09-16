## Why

A value lives under `/run` (`lib/util.nix:334`, spent at `lib/resolve.nix:1591`), so a reboot empties
every one of them. The endpoint brings the entries back, their units fail on a file that is not
there, and the only thing that says so is `planner status` printing `value <key> missing on
<machine>` (`cli/report.py:134`). Recovery is a second `apply` from the operator's workstation, which
means a machine cannot come back from a power cut without a human and a network path to it. The last
phase of `tests/e2e/secret-delivery/test_secret_delivery.py:670-711` is that behaviour, asserted
deliberately.

A machine already holds a private key nobody else has: its own sshd host key. Sealing each delivered
value to the machine's host identity at delivery time lets the machine put its own values back
before the entries that read them start, with no operator, no network and no new secret store.

## What Changes

- The library derives a second path for every generated file it already derives a path for: a
  persistent one under a root of its own, beside `util.varsRoot` and outside the reach of the
  recogniser built on it. Nothing about it enters a plan record, a key input or `varsState`.
- A delivery writes each value's file twice: the plaintext at its `/run` path exactly as today, and
  a copy sealed to the receiving machine's declared `hostKey` at the persistent path. Both writers
  do it: the command's own step (`cli/remote.py:326-384`) and the step `secrets/backend.nix` renders
  for the external generator.
- The deployment build produces one unsealer per machine that receives a sealed value: the program
  that opens a seal, and a boot-time oneshot ordered before every unit on that machine that opens a
  value. The apply copies it and installs its unit before it writes a value.
- `planner status` gains two lines: a machine holding a sealed copy it cannot open, and a machine
  that seals and holds no sealed copy. Neither changes the exit status.
- A machine whose declared host key is of a type the sealing tool cannot use earns a warning row,
  `operator-machine-host-key-unsealable`, and is delivered to exactly as it is today: plaintext
  only, no unsealer, no recovery.
- **BREAKING** `manifest.json` gains a required table of the machines a value reaches and its
  `version` becomes 2. A record of the previous shape is refused by its version, as a record the
  command does not implement. There is no dual reading and no compatibility path.
- **BREAKING** The last phase of `tests/e2e/secret-delivery/` asserts the opposite of what it
  asserts today: a machine that rebooted holds its values again. The report scenario that a reboot
  used to produce is produced by clearing both copies instead.

This change consumes `hostKey` from `name-the-machine-a-run-dials` (contract C1) and introduces no
machine-identity field of its own. It is ordered after that change.

## Capabilities

### New Capabilities

None. Every fact this change adds belongs to a capability that already exists.

### Modified Capabilities

- `planner/secret-delivery`: a delivered value has a persistent path derived beside its runtime
  path, and sealing moves no key, no delivery set and no state answer.
- `delivery/generated-values`: what a delivery leaves on a machine, that a machine restores its own
  values after a reboot, that the external generator's rendered step seals too, and the guard on the
  tool the seal depends on.
- `operator/deployment-build`: the per-machine unsealer, the row for a host key that cannot be
  sealed to, and the machines table of the deployment record.
- `operator/apply-command`: the unsealer install step, the sealed write, and the refusals a run
  makes before it dials when it cannot seal.
- `operator/machine-report`: the two seal lines, and the re-statement of the value-absence scenario
  a reboot no longer produces.

## Impact

- `lib/util.nix`: `sealedRoot` and `sealedPathOf`, beside `varsRoot` and `varsPathsIn`. No new
  per-entry work in `lib/`, so no plan field, no atom, no registry key and no vocabulary field.
- `operator/read.nix`: the per-machine unsealer record, the usable-host-key question, the ordering
  list read off each entry's own mention sites, the machines table of the manifest, the version.
- `operator/default.nix`: the unsealer derivation per machine, in the same link farm as the entries.
- `secrets/read.nix`: two rendered words for the sealed path and its parent; `secrets/backend.nix`:
  the sealing half of the rendered deploy step and its two new caller arguments.
- `cli/remote.py`, `cli/apply.py`, `cli/manifest.py`, `cli/report.py`, `cli/values.py`,
  `cli/flake-module.nix`: the seal payload, the install step, the machines table, the report lines,
  the sealing program the wrapper names.
- New runtime dependency on `age`, twice: on the operator's workstation, named by the command's own
  wrapper, and on every machine that receives a sealed value, arriving in the closure the apply
  copies rather than from the machine's own `PATH`.
- `tests/e2e/secret-delivery/`: `hostKey` on its machines, a new phase and a rewritten last one.
  The guest image's static host key is `name-the-machine-a-run-dials`'s edit, not this change's.
- `docs/operator.md` and `CLAUDE.md`.
- `fixtures/minimal-typed-edge/` is untouched: its declarations do not change and this change adds
  no plan field, so the golden plan is not regenerated.
