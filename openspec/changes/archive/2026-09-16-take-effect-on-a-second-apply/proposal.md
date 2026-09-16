## Why

A second apply is where this tool currently loses. Four ways, three of them silent:

- **An edited configuration file never reaches an attached machine.** The image's version digest
  deliberately excludes configuration bytes (`image/read.nix:302-318`, and `CLAUDE.md` says why: a
  file's content moves the plan key and never enters the image), and the attach script is the only
  thing that assembles those bytes on the host (`image/default.nix:229-246`). `cli/apply.py:308-312`
  then skips the script entirely for an entry the machine already holds attached, printing
  `attached <key> already`. The machine keeps the old bytes and `status` prints `current`.
- **A new build of an attached entry has no path onto the machine.** `holds_attached`
  (`cli/apply.py:154-190`) asks about the *new* image's own path, so a changed build reads as
  detached; the attach script runs bare `portablectl attach` with no detach of the old image, and the
  unit file names carry no version (`image/read.nix:179-180`), so the two collide.
  `tests/e2e/portable-image/` builds a `changed` image that nothing attaches, so the case is
  untested by construction, and `rollback` is refused for image entries outright
  (`cli/report.py:202-206`).
- **`configData.<path>.reload` is declared, validated, recorded - and read by nothing.**
  `lib/module.nix:88-93` reads it, `lib/module.nix:846-849` checks it against the module's own units,
  `image/read.nix:211` carries it into the image record, and no realiser and no command ever issues a
  reload. `docs/plan.md:265` promises the opposite.
- **A rotated secret leaves every consumer holding the old bytes.** `cli/apply.py:295-310` writes the
  value and then activates an unchanged artifact, which is the endpoint's own no-op:
  `tests/e2e/wired-pair/test_wired_pair.py:553-562` asserts the process's `MainPID` does not move.
  Nothing restarts the reader, and nothing says so.

Between them these make the second-most-common operator action - change something and apply - either
a no-op or a collision. The same hole answers the reboot question: values live on tmpfs
(`lib/resolve.nix:949`), so a rebooted machine holds none of them, and no report says which.

## What Changes

- **The artifact's own script becomes the whole decision, and it is idempotent.** It assembles every
  configuration file, replaces an older image of the same entry, attaches if not attached, starts the
  units, and reloads what the plan named - and running it twice over an unchanged deployment changes
  nothing and reports that it changed nothing.
- **The command stops skipping.** `holds_attached` and the `attached … already` line go away: the
  machine-side script owns the question, which is what
  `cli/apply.py:180-183`'s own docstring already says decides it.
- **An older image of an entry is detached before the new one attaches.** The image an entry's units
  currently run from is read from the service manager, which `tests/e2e/portable-image/` already
  proves readable, and an image that is not this artifact's is stopped and detached first.
- **`reload` is honoured.** A configuration file whose assembled bytes changed reloads the units it
  named; a file whose bytes did not change reloads nothing.
- **A changed delivered value restarts its readers.** The write step reports whether the bytes moved,
  and every entry that declared a read of a value whose bytes moved has its units restarted if they
  are running. A value whose bytes did not move restarts nothing.
- **A report names a delivered value the machine does not hold.** That is how a rebooted machine is
  diagnosed, and the recovery is an apply, which already writes every delivered value.

## Capabilities

### Modified Capabilities

- `operator/apply-command`: no entry is skipped for being already present; a value write reports
  whether the bytes moved; readers of a changed value are restarted; the reload a configuration file
  named is issued.
- `realiser/portable-service-image`: the artifact's script is idempotent and complete - assemble,
  replace an older image of the same entry, attach, start, reload - and reports what it did.
- `realiser/flakelet-artifact`: what an activation of an unchanged artifact is, and what the command
  must therefore do for a changed value.
- `operator/machine-report`: a delivered value the machine does not hold is reported, and a machine
  holding configuration bytes older than the build's is not reported as current.

## Impact

- `image/default.nix`: the attach script gains an idempotent shape, a replacement step and a reload
  step, and reports what it did; `detach` is unchanged.
- `image/read.nix`: the record the script is written over gains the per-file information the reload
  step needs (which units, and the bytes to compare against).
- `cli/apply.py`: `holds_attached` deleted; the value write compares before writing; the restart of
  readers after the writes; the reload step's output folded into the step report.
- `cli/remote.py`: the value write reports whether the bytes moved; a restart script for the readers.
- `cli/report.py`: a missing delivered value, and configuration staleness for an image entry.
- `tests/unit/{image,operator}.nix`, `tests/e2e/test_harness.py`,
  `tests/e2e/portable-image/`, `tests/e2e/wired-pair/`, `tests/e2e/secret-delivery/`.
- `docs/operator.md`, `docs/plan.md` (the promise at `:265` becomes true), `CLAUDE.md`.
- Depends on nothing, but reads best after `openspec/changes/hold-a-long-running-daemon`: a
  configuration file whose bytes exist at build time needs no assembly, so the reload step's subject
  is the smaller set of files that genuinely change on the machine.
