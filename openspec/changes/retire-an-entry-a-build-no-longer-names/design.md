## Context

See `proposal.md` - Why. What shapes the approach is what each endpoint already answers and what a
build already publishes.

`cli/report.py:94-135` asks one question per selected entry and one value question per machine.
Nothing asks a machine what else it holds, and `cli/report.py:372-391` matches the machine's image
listing only against the file names the build published for entries it names. `cli/apply.py:243-296`
writes values, copies and activates, and restarts; it takes no step about anything the plan does not
carry.

The two endpoints answer differently, and both differences are load-bearing.

`flakelet status --json` takes zero or more names; with none it answers for every entry the machine
holds. Each answer carries `name`, `origin`, `generation`, `units`, `locked_url` and the rest of
`ServiceStatus` (`tests/e2e/delivery.py:44-64` pins the field set at the locked revision).
`flakelet/read.nix:194` writes `flake_url = "plan:${image.key}"` into the artifact's `meta.json`, so
`locked_url` is `plan:` followed by the plan key of the entry the artifact was built for. The
retirement verb is `remove [--purge] <name>`, documented as: stop, unlink, delete generations and
bookkeeping, delete the exports file, keep and list the state folders, empty them only with
`--purge`. `reconcile` is not that verb: it removes declarative entries no longer in `config.json`,
and `cli/remote.py:420-427` activates through `flakelet activate`, which registers a manual entry
(`origin: "manual"`) that `reconcile` leaves alone.

`portablectl list --no-legend` answers for every portable image in the machine's search paths, with
a name and a state per row, and `cli/remote.py:482-512` already reads both out of the answer the
report asks for. An image's name is `image/read.nix:919`'s `<name>_<version>.raw` with the suffix
stripped, over `image/read.nix:208`'s `<instance>-<service>` and `lib/util.nix:495-496`'s sixteen
hex digits. `portablectl detach` resolves a name in those same search paths, which is where
attaching put a symlink to the image, and `--now` stops the units before it unlinks them
(portablectl(1), added in version 245). Nothing in the listing says which tool attached a row.

`lib/plan.nix:1404-1418` emits a `machine:<name>` record only for a machine some placement selected,
and `cli/manifest.py:342-361` reads an address only off an entry of the record.

## Goals / Non-Goals

**Goals:**

- One question per machine answers what it holds, whichever realisers put things there.
- A holding is attributed to this planner before it is named, and attributed by a fact only the
  realiser that would have put it there owns.
- Retirement is one step of the existing walk, through the existing channel, using the endpoint's
  own removal verb.
- The report and the apply announcement are one sentence shape, so an operator reads one line.

**Non-Goals:**

- Deleting anything a service wrote. No `--purge`, no `rm` of a staging tree, no state directory.
- Retiring from a machine the build no longer names. The build carries no address for one.
- A generated value the build no longer names. A value's directory is derived per value, a machine
  keeps no ledger of the values it holds, the paths are under `/run` and a reboot clears them, and
  deleting bytes is precisely what this change refuses to do. `status` already names a missing value
  of a value the build does name, and a value the build stopped naming stays unmentioned.
- A second listing of what a machine holds for its own sake. This is not `machinectl list` with
  extra steps: only holdings the record explains are named.

## Decisions

### D1 - Attribution is a fact the realiser publishes and the record carries

Each realiser publishes, beside the `nameRule`, `unitRule`, `pathRule` and `recordRule` the reading
already asks it for (`operator/read.nix:180-190`, `:313-323`), what a machine's own answer names the
things it put there by. `operator/read.nix` copies those into `manifest.json` as one table keyed by
realiser, for every realiser the reading is handed. `cli/manifest.py` reads the table;
`cli/remote.py`'s existing per-realiser table (`REALISERS`, `cli/remote.py:533-542`) spends it.

```
"realisers": {
  "flakelet": { "identityPrefix": "plan:" },
  "image":    { "nameSeparator": "_", "digestAlphabet": "0123456789abcdef", "digestLength": 16 }
}
```

The fields differ because the answers differ: flakelet's carries an identity the realiser wrote, so
one prefix decides both attribution and the plan key behind it; an image's carries a file name, so
attribution is the shape of that name and there is no key behind it. There is one switch on the
realiser and it is the one `cli/remote.py` already has. The table is keyed by realiser and is one
table: `run-an-entry-without-root` publishes each realiser's `scopes` beside these fields, and the
question of D2 and the verb of D3 spend it.

Alternatives rejected:

- **A literal in the command.** This is what exists today in a smaller form:
  `tests/e2e/delivery.py:36` keeps its own copy of `plan:` equal to `flakelet/read.nix:194` by
  comment. A rule whose one home is a realiser, restated in the layer that decides what to detach,
  is a widened copy away from retiring something nobody asked to retire.
- **A regular expression in the record.** A nix regex and a python regex are two dialects, so one
  published pattern would be a rule with one spelling and two readings. The published fields are
  data with no dialect.
- **flakelet's `origin` field.** `manual` distinguishes an entry registered by `activate` or
  `deploy` from a declarative one, and a human `flakelet deploy` is manual too.
- **A ledger on the machine.** `/run/portable-planner/<name>` (`image/read.nix:296`) is nixplan's
  own per-entry directory, and reading it would attribute perfectly - except that it is under `/run`
  while `portablectl attach` is persistent, so after a reboot an image is still attached and its
  staging directory is gone. A registry that undercounts exactly after a reboot is worse than a name
  rule.

### D2 - One question per machine, sectioned per realiser, each half tolerant of a missing tool

The holdings question is one script per machine, built from the published table: per realiser, a
marker line `holdings <realiser> <status>` and then that realiser's own answer. One question per
machine rather than one per realiser or one per holding, because a machine's sshd may be
socket-activated and a burst of short logins is answered by the socket's own trigger limit - the
same reason `cli/remote.py:400-417` asks about every value of a machine in one question and
`cli/remote.py:449-470` folds three questions into one.

The question is scope-aware. A realiser's half joins the script only where the `scopes` the record
publishes for it admit the machine's scope, and on a machine whose scope is `user` the image half
asks `portablectl --user list --no-legend`, addressing the account's own daemon rather than the
system's. A record publishing no `scopes` for a realiser admits every machine and a machine stating
no scope is a system-scope one, so the question degrades to the shape above where either fact is
unstated.

How each `<status>` reads:

- `0` - the answer is read for holdings.
- `126` or `127` - the realiser's tool is not on that machine, so it holds nothing of that realiser.
  No line, no refusal: a machine with no `portablectl` has no attached portable image.
- anything else - the command cannot read the answer, which is the refusal the report already makes
  for an endpoint answer that is not a status, naming the machine and what it said.
- ssh itself failing is the machine being unreachable, which its entry lines already say; the machine
  joins the set the report could not ask and no holding is claimed for it.

### D3 - The retirement verb, per realiser

- flakelet: `flakelet remove <name>`, never `--purge`. `remove` is exactly the shape wanted - it
  stops, unlinks, deletes its own bookkeeping, and keeps and lists the state folders - and its
  listing of what it kept is what the step line echoes.
- image: `portablectl detach --now <name>`, the name being what the listing printed, with `--user`
  where the machine's scope is `user` - the flag the question carried, because an attachment of the
  account's own daemon is invisible to the system's and a detach addressed to the wrong one resolves
  nothing. `--now` stops the units before the unlink, so the step needs no separate unit list and
  cannot stop the wrong ones.

Neither is `bin/detach`. The artifact of a holding this build does not name is not in this build, so
the run cannot name its path; nothing on the machine roots it, so nix can have collected it; and
`image/default.nix:348-356` is the precedent that the right shape is a step over what the machine
answered - the attach script already detaches an image it read out of `systemctl show -P RootImage`
with no artifact of that build at hand. `bin/detach` stays: it is the artifact's own contract, it is
what an operator runs by hand on a machine the build no longer names (see D8), and
`tests/e2e/portable-image/test_portable_image.py:1311-1333` asserts what it does.

`bin/detach` also removes the staging tree, which the retirement does not (D5). That is the one
behavioural difference between them and it is deliberate, not an omission: the artifact's script
owns the machine's state for its own entry and was built knowing every path of it, while a
retirement knows only a name the machine gave it.

### D4 - Retirement is opt-in, by a flag, and every apply announces

`apply` gains `--retire`, a flag. Every apply asks and announces; only a run given the flag retires.

Alternatives rejected:

- **Implicit on every apply.** Retirement is destructive in the one way that matters - it stops a
  running service - and a deployment edited by one person is applied by another.
- **`--retire KEY`, repeatable.** A holding is not a plan key of this build: for an image it is a
  file name the build's own projection cannot invert, so a key-taking option would need a second
  grammar, a second set of refusals and a second document section. `--only` is the option that takes
  keys and it already refuses a key the deployment does not carry. The announcement a plain apply
  prints is the preview, so the operator's two steps are "apply, read the line, apply with the flag".
- **A `retire` subcommand.** It would need its own selection, its own order and its own document
  section, and `README.md`'s five documented commands are asserted literally in
  `tests/unit/layers.nix`. A step of the walk belongs in the walk.
- **A confirmation prompt.** `cli/remote.py`'s `BatchMode` exists so that nothing in this command
  waits for a human; a prompt would be the first.

### D5 - A retirement deletes no state, and says so

No `--purge`, no removal of a staging tree, no delivered value deleted, no host path touched. A
deployment creates no account and declares no state of its own, so bytes that outlive an entry are
the machine's. The step line says that no state was deleted and carries what the endpoint reported
about what it kept, which is the whole answer to "where did my data go".

The cost is bytes left behind: an image's staged configuration files stay under
`/run/portable-planner/<name>` until the next reboot, at the `0711` directories the attach script
made. That is the same treatment a delivered value gets from every other step of this command, and
the alternative - a retirement that deletes a rendered file - is a destructive act about a path the
command derived rather than read.

### D6 - Retirement is the first thing a run does on a machine

The walk becomes: ask every machine of the selection what it holds; announce cycles, contradicted
edges, unsatisfied reads and holdings; retire; write values; copy and activate per entry; restart the
readers of a moved value.

Asking every machine before the first write means a run that cannot read one machine's answer has
changed nothing anywhere.

Retiring before the writes and activations, rather than after, because a holding owns host resources
of the machine - a port, a unit file name, a host path - and the entry that replaces a renamed one
claims the same ones. `entry-port-claimed-twice` and `operator-entry-unit-file-collision` reach
inside one build and cannot see across two, so the only order in which a rename can start is
retire-then-activate.

Rejected: **retire last**, the make-before-break order. It is the right order when the replacement
can run beside the thing it replaces, and a renamed entry cannot: it contends for exactly the
resources its predecessor holds. It also gets the failure mode backwards - a run that broke half way
would have retired nothing and applied half, and the operator's second run would re-announce the
same holdings; retiring first means the destructive step either happened or stopped the run before
anything else changed.

### D7 - The mode that asks rather than acts names no holding

`--dry-run` replaces the channel and nothing else (`cli/apply.py:181-206`), so the holdings question
answers nothing and the run names no holding. This is stated rather than worked around: what a
machine currently holds is not a question a dry run answers, `status` is, and fabricating a holding
line from the plan would print a line no machine said. The two runs stay comparable line by line
because the holding lines are absent rather than invented.

### D8 - A machine the build no longer names is out of reach, and the document says so

A build carries an address only for a machine it places an entry on, so a machine whose every entry
was deleted is unreachable from the new build. The command invents nothing for it: no `--address`
option, no machine-identity field, no reading of the previous build.

`docs/operator.md` states the order of work instead: empty a machine while the build still names an
entry on it, and empty a machine the build has already stopped naming with the endpoint's own tool -
`flakelet remove <name>`, or the `bin/detach` the image artifact carries. A future change may want
an option that names an address; it is not this one, and the spec says so rather than leaving a
reader to discover a silent gap.

### D9 - What the lines say

- report: `<machine> holds <identity>, which this build does not name`
- apply, announcing: the same sentence with `; not retired` appended
- apply, retiring: `retire <identity> on <user>@<address> (no state deleted)`, with what the
  endpoint printed echoed under it by the step machinery that already echoes
  (`cli/remote.py:177-201`)

`<identity>` is the plan key for a flakelet holding and the image name the machine listed for an
image one. The report's exit status does not move: a holding is an answer a machine gave, which is
the rule `A delivered value the machine does not hold` and the staleness rule already follow.

### D10 - The record's stated version moves

`manifest.json` gains the table, and `VERSION` goes from 1 to 2 in `operator/read.nix:609` and
`cli/manifest.py:36`. A new command reading an older record would find no table, publish no rule,
attribute no holding and report none - a false negative that reads as "nothing to retire". The
version field exists to refuse a record the command cannot read, and this is one. No dual support and
no default: replace, do not deprecate.

## Risks / Trade-offs

- **A portable image some other tool attached, whose name happens to end in an underscore and
  sixteen hex digits, is attributed to this planner and retired.** → The shape is narrow, the
  announcement names it on every apply before any run carries the flag, and the flag is never
  implicit. A stronger attribution would need a fact the listing does not carry.
- **Two deployments of this planner applied to one machine name each other's entries as holdings the
  build does not name.** → Attribution reaches this planner, not this deployment, and the spec says
  so. Retirement is opt-in for exactly this reason, and an operator who runs two deployments against
  one machine reads two announcements. Narrowing it would need a per-deployment identity on the
  machine, which is a field this change is not allowed to invent and would not want to.
- **An image whose file was collected on the machine cannot be resolved by name, so `detach` may
  refuse.** → It is the machine's own refusal naming the holding, printed under the step line the
  run already printed, and the run stops there as it does for any refused step. The recovery is the
  operator's own tool. Guessing a path instead would be inventing one.
- **`flakelet remove` deletes the entry's exports file.** → That is what retirement is. An entry of
  this build that read those exports would have been an entry the plan wired, and the plan does not
  wire an entry it does not carry.
- **One more question per machine on every apply and every report.** → One question per machine, not
  one per holding, and an apply already takes at least two steps per machine.
- **The holdings question is a dial, so the announcement is not available to a run that dials
  nothing.** → D7. Stated in the spec as behaviour rather than left as a surprise.
- **Nothing in `lib/` changes, but the perf gate is two-sided.** → The published table is
  `operator/read.nix`'s and the realisers', which are outside `mkPlan`, so no thunk is added per plan
  entry. The gate is still run at both ends, per the baseline task.

## Migration Plan

One cutover, no compatibility path. The record's version moves with the table (D10), so a build and
a command of different generations refuse each other by the mechanism that already exists for that.
Nothing on any machine has to be migrated: the change adds a question and a step and alters no
artifact a machine already holds. An operator on the old command against a new build gets the version
refusal, which names both versions.
