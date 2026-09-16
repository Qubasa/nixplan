## Why

An apply that breaks cannot be read. `cli/apply.py:220-229` calls `record(...)` after each step has
returned, so the last line a broken run prints is the last step that worked, and the step that broke
is named nowhere. Nothing else recovers it: `cli/report.py:148-153` renders an entry's status as
`generation <n> of <locked_url>` and drops every other field the endpoint reported, including
`last_error`, which `tests/e2e/wired-pair/test_wired_pair.py:453` reads off the same record;
`cli/report.py:138-141` calls an image attached only when `portablectl is-attached` printed exactly
`attached`, while `image/default.nix:227-228` attaches and then starts the units, so a machine the
command applied a second ago reports `absent`, and the example at `docs/operator.md:305` cannot be
produced by any successful run.

Reaching the machines is no better. `cli/remote.py:69-73` builds an ssh argv with no `BatchMode`, no
`ConnectTimeout` and no timeout on the subprocess: `planner status` against unrouted addresses
printed nothing and had to be killed at 60 seconds, and an unknown host key makes ssh prompt on a
standard input nobody sees, because `Subprocess.output` captures it. `cli/report.py:77-83` collects
every line and prints after the last machine answered, so one dead machine hides the report of the
live ones - the observed run gave a 28-line traceback, exit 1 and zero report lines. And
`cli/remote.py:175-183` folds every remote failure into the word the command uses for absence
(`2>/dev/null || printf '[]'`), so an endpoint that is not installed, a permission error and a
machine that was never applied to all read alike.

The rest of the walk misreports smaller things in the same direction. `cli/order.py:52-58` breaks a
tie by taking `remaining[0]` when nothing is ready, which need not sit on a cycle: with `a:x@m`
reading `b:y@m` and `b:y@m` and `c:z@m` reading each other, the walk contradicts the read of `b:y@m`
by `a:x@m`, an edge the order `(b, c, a)` satisfies. `cli/apply.py:118-126` with
`cli/values.py:56-63` dials every machine of a value's delivery set even under `--only`, which is
the one flag a half-finished apply has. `cli/values.py:112-121` measures the value source with
`rglob("*")` over the whole directory, so a `README`, a `.gitignore` or an editor backup beside it
ends the run, and only the first extra is named. `cli/manifest.py:157-166` reads neither `version`
nor `storeDir`, both of which `operator/read.nix:231-233` writes, and defaults a missing `entries`
table to empty, so a record from another revision is read as this one and a misspelled key applies
nothing and exits zero. `cli/manifest.py:118-127` builds with `--no-link`, so a store path the
command handed back and a collector removed comes back as `don't know how to build these paths`,
which reads as a broken flake attribute. `cli/report.py:36-46` prints entries and values and neither
half of the diagnostics, although `manifest.read` decoded both.

What an operator hits is one experience: a run stops somewhere in the middle of a cluster, the log
ends on a success line, `status` answers `absent` for entries that are running, and no committed
document says what to do next - `docs/operator.md` has no match for interrupt, partial, resume or
unreachable.

## What Changes

- **A step is announced before it is attempted.** Each step line is printed when the step starts,
  and a step that fails is followed by a line naming it, the machine and what the machine said. The
  log a broken run leaves therefore ends at the boundary rather than one step behind it, and the
  step the operator has to look at is the last line rather than the line after the last.
- **A machine's own failure is a refusal, not a traceback.** A remote command that exits non-zero
  becomes the command's own error naming the entry, the machine and the machine's output.
  `Subprocess` stops letting `CalledProcessError` escape `main`.
- **Silence is bounded, work is not.** The command appends `BatchMode=yes`, a `ConnectTimeout` and a
  server-alive bound to the ssh options of every step, after the options the caller set, because ssh
  takes the first value given for an option and an operator's own choice has to win. No wall-clock
  timeout is put on a step: a copy of a large closure is allowed to take as long as it takes.
- **`status` reports per machine, as each machine answers.** A line is printed when it is known, so
  one unreachable machine costs its own line and hides nothing. A machine that could not be asked is
  reported as unreachable, and the run exits non-zero without turning the other machines' answers
  into a traceback.
- **`status` tells four answers apart.** An entry the endpoint does not register is absent; a
  machine carrying no endpoint is reported as such, with what the machine said; a machine that
  cannot be reached is unreachable; and an entry whose activation the endpoint recorded as failed
  reports that failure rather than a healthy generation. The status scripts stop discarding standard
  error and stop turning every failure into the empty list.
- **A status line carries the identity and the error the endpoint records.** The generation, the
  identity the endpoint stores for the artifact and `last_error` for a flakelet entry; the
  attachment word the machine's own tool printed for an image entry, where only `detached` means
  absence.
- **A restriction bounds the machines dialled.** `--only` selects the entries to apply, and the
  machines contacted are the machines of those entries plus the delivery machines of a value entry
  the restriction names directly. `--only site:server@alpha` opens no connection to beta.
- **The order the walk reports as broken is broken.** When no entry is ready, the walk chooses among
  the entries whose every unapplied provider can be reached back from the entry itself, takes the
  lowest such key, and contradicts only the edges into it from that same set. An edge off every
  cycle is never reported and never contradicted.
- **A build prints the rows it holds.** `planner build` prints the rendered diagnostics table beside
  the entries and the values, and exits non-zero when a row is an error. The table is the refusal
  `report-every-refusal-as-a-row` leaves in the tree, printed, rather than a second refusal of the
  command's own.
- **The value source is measured where the deployment declares files.** An undeclared file is one
  that sits under the directory of a value entry the deployment delivers; a file elsewhere under the
  source is not the command's business. Every extra is named, not the first.
- **A record states its shape and the command holds it to it.** `version` and `storeDir` are read: a
  version the command does not implement, and a store other than the one the command runs against,
  are refusals naming both values. A record carrying no `entries` table is refused rather than read
  as a deployment that places nothing.
- **A target that no longer exists is named as collected.** A target under the store directory that
  is absent is refused as a build that was collected, naming the reference to rebuild, rather than
  handed to `nix build` to answer about.
- **A second apply is the documented recovery.** `docs/operator.md` gains what an interrupted run
  leaves, why the recovery is another apply rather than an undo, which steps are unchanged when
  repeated, and how `--only` narrows the second run. The command re-attaches no image the machine
  already holds attached at that path, which is what makes an image entry repeatable.
- **The machine layer proves the recovery.** `tests/e2e/wired-pair/` gains a final phase that breaks
  a run between its two machines, reads the report of the broken run, and finishes the deployment
  with a second apply.

Not in this change, deliberately:

- **`--dry-run`.** D5 belongs to `open-the-repository-to-a-consumer`, which restates "The command
  refuses before it dials" for it. This change restates no requirement that change touches.
- **A progress record on the operator's side.** No journal file, no `--resume`. Design D2 argues it:
  the machines hold the state, and a file that claims to know what they hold is a second answer that
  can be wrong.
- **Concurrency.** A run still walks one machine at a time. Reporting a failure per machine does not
  turn the walk into a scheduler.
- **Health checks and automatic rollback.** Unchanged from
  `apply-deployments-with-an-operator-command`: the command reports what the endpoint reported.
- **Redacting an argv.** C2's leak of a base64 value through a raised `CalledProcessError` is
  `deliver-a-secret-without-exposing-it`. This change converts that failure into the command's own
  error; what the message may carry is that change's requirement.
- **Reconciling an entry's published identity with the plan key.** B11 is
  `report-every-refusal-as-a-row`, under "The identity a build publishes for an entry is the
  identity the machine stores". Status here prints what the endpoint recorded.

## Capabilities

### New Capabilities

- `operator/machine-report` (`cli/report.py`): what asking a machine answers, and the four states a
  report has to tell apart - an entry the endpoint does not register, a machine with no endpoint, a
  machine that cannot be reached, and an entry whose activation the endpoint recorded as failed.

### Modified Capabilities

- `operator/apply-command`: a step is announced before it is attempted and a failed step is named;
  the ordering walk contradicts only an edge on a cycle; a restriction bounds the machines dialled;
  the value source is measured per value entry; a deployment record is refused by version, by store
  and by a missing entry table; a collected build is named as collected; a build prints the
  planner's own table; and a second run finishes a run that broke.
- `operator/deployment-build`: the record a build publishes states the version of its own shape and
  the store its artifacts were built in, so a reader can refuse a record it cannot read.
- `delivery/real-cluster`: a run broken between two machines leaves a state that a second run
  completes, and the report of the broken run names the step that broke.
