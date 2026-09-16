## Why

flakelet already rolls a failed activation back. Its activation starts `<name>-health.service` if the
generation carries one and then requires that no unit of the entry is `failed`, and a failure of
either deletes the new generation, switches back to the previous one, records a hold and exits
non-zero (`docs/design.md` "Health checks are units" and the update flow, `docs/reference/service-module.md`
"Activation semantics", at the locked revision). nixplan gives it nothing to start: the unit
vocabulary (`lib/module.nix:83-100`) says when a unit runs - `command`, `oneShot`, `schedule`,
`restart`, `restartSec`, the two condition polarities and the three directory kinds - and never
whether it works. A service whose start job succeeds and whose process then crash-loops is therefore
activated, published as the running generation, and rolled back by nothing, while `apply` exits zero
and the report says the machine runs this build's units.

The gap is one missing fact per unit, not a new mechanism: the probe flakelet wants is an ordinary
oneshot of the generation, which is why it gets `TimeoutStartSec=`, sandboxing, the journal and
`systemctl start` for free, and why it is gc-rooted and rolled back together with the code it probes.

## What Changes

- The unit vocabulary carries **`probe`**, the command that decides whether the unit is serving, and
  **`probeTimeout`**, the bound on how long that command may take. Both are per unit, both enter the
  entry's key as every unit field does, and neither is defaulted: a bound nobody stated would be a
  service manager's default in the record, which this vocabulary refuses.
- An entry carries **at most one** probe. The file flakelet starts is `<name>-health.service`, one
  per entry, so a second probe on a second unit of one entry is a row rather than a file nothing
  starts.
- The derived unit's name is **`<service name>-health.service`**, where the service name is the
  prefix every unit file of the entry already carries. It is derived in `unitFilesOf`
  (`image/read.nix:250-253`), which is the one derivation `flakelet/read.nix`'s `acceptsUnit`
  (`flakelet/read.nix:72-75`), `image/read.nix`'s own name rule and `operator/read.nix`'s per-machine
  unit-file index (`operator/read.nix:121`, `:257`, `:469-508`) all read, so all three see the new
  name by existing.
- The derived unit is rendered once, by the shared reading, as a oneshot ordered after and requiring
  the unit it probes, carrying the probed unit's account, the entry's own host-path binds, the
  probe's command as `ExecStart=` and the bound as `TimeoutStartSec=`, and **no `[Install]`**:
  flakelet starts it by name and an `[Install]` would queue it at every boot instead.
- It inherits the account and nothing that makes it the owner of a resource. In particular it
  declares no `runtimeDirectory`, because a service manager deletes a unit's runtime directory when
  that unit stops and a oneshot that exited would take the probed unit's directory with it.
- `unitDirectives` (`image/read.nix:93-118`) gains both fields, so the image realiser renders them
  rather than failing the build on a vocabulary it does not know.
- **The image realiser carries the probe unit and starts it, and nothing rolls back.** `portablectl`
  attaches and starts an entry's units with no generation to return to (`cli/report.py:30-32`), so
  the probe is in the attachment's unit list, the attach script's `systemctl start` runs it, and a
  failing probe is a failed apply step naming the entry and what the machine printed. The image stays
  attached and running what it holds. This is stated as the realiser's behaviour rather than dressed
  up as a rollback it cannot perform.
- Seven rows from `lib/` and one from `operator/read.nix`, all errors, none a raise: a bound with no
  command, a command with no bound, a bound that spells zero, a probe on a `oneShot` unit, a probe on
  a scheduled unit, two probes in one entry, and a derived probe file a declared unit of the same
  entry already spells. `lib/atoms.nix` gains one exported predicate, `isZeroDuration`, read by the
  third of those the way `restartPolicies` is read by the row about a policy outside its domain.
- No new plan field says whether a unit is healthy, no readiness gate is evaluated by the planner,
  and no plan field decides `[Install]`. The plan records the command and the bound; each realiser
  decides what starting it means.
- No change to `cli/`. `flakelet activate` exits non-zero for a deploy that was rolled back
  (`docs/reference/cli.md`, "Exit status"), `cli/remote.py:421-427` already runs it as one step, and a
  step that fails is already the command's own error naming the entry, the machine and what the
  machine printed.

## Capabilities

### New Capabilities

None. The probe is a field of a vocabulary that exists and a file two realisers already derive names
for.

### Modified Capabilities

- `planner/unit-vocabulary`: the vocabulary carries the probe and its bound, with the rows that read
  them against the shape the unit already declared.
- `realiser/flakelet-artifact`: the artifact carries the derived probe unit, the endpoint's own
  activation gate is what the change exists to feed, and a probe that fails is a rollback.
- `realiser/portable-service-image`: the image carries the derived probe unit and starts it at
  attach, and states that nothing rolls back.
