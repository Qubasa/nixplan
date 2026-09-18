# Integration orders

Two sets of changes were planned in parallel, each against one set of contracts. A set is
independent in what it owns and not independent in what it touches, so this file records the seams
rather than leaving each change to discover them. One file, one home for a seam: a change states
only its own step and cites this file for the rest.

## The four production changes

`run-an-entry-without-root`, `retire-an-entry-a-build-no-longer-names`,
`unseal-a-value-after-a-reboot` and `probe-a-service-before-it-counts-as-live`. The other open
changes are not part of this set. `name-the-machine-a-run-dials` is parked, on disk and untouched:
the user-scope redesign moved the seal recipient to an age key the registry states, so nothing
consumes `hostKey` any more, and connection pinning is a separate, currently unowned concern -
whether to delete the change or revive it around pinning alone is an open operator decision.
`declare-service-state` was struck - `PARKED.md` beside this file holds its unbuilt half and the
trigger that revives it - `answer-whether-a-machine-is-current` stays open for the
reason `CLAUDE.md` records, `deliver-a-secret-without-exposing-it` stays narrowed for the reason
`CLAUDE.md` records, and `enroll-a-friend-machine` is planned and ordered behind the four - the
closing section names it.

### Order

1. `run-an-entry-without-root` first is the simplest order: `unseal-a-value-after-a-reboot` places
   its unsealer as a user unit on a user-scope machine and `retire-an-entry-a-build-no-longer-names`
   puts `--user` into its argv, and both read `scope` for it.
2. The other three in any order. There is no hard dependency between the four: landing any of the
   others first is landing it system-scope-only, which each states it degrades to - a machine
   stating no scope is a system-scope machine, which is today's behaviour.

### Seams

**The deployment record.** Three changes add to it. `unseal-a-value-after-a-reboot` adds the
machines table and moves the stated version from 1 to 2, because a reader of the previous shape
cannot deliver a value. `retire-an-entry-a-build-no-longer-names` adds the per-realiser `realisers`
table and moves the version too (its D10). `run-an-entry-without-root` adds `scopes` to that same
table - it is one table whichever change introduces it first. Each change's tasks write version
numbers as if it landed first, so whichever lands second or third reads `cli/manifest.py` for the
current number rather than assuming it.

**`operator/apply-command`.** Three changes delta it, each with one step of its own: the preflight
question (`run-an-entry-without-root`), the retirement (`retire-an-entry-a-build-no-longer-names`,
opt-in), and the unsealer install and the sealed value write (`unseal-a-value-after-a-reboot`).
Each delta states only its own step and cites this file for the rest, so the whole on-machine line
is written out here and nowhere else: preflight question, then retirement, then unsealer install,
then value writes, then copy, then activation, then value-driven restarts.

**`planner/machine-platform`.** Two changes MODIFY the registry-keys requirement:
`run-an-entry-without-root` adds `scope` and `unseal-a-value-after-a-reboot` adds `sealRecipient`.
Each delta states its own key only and reads the other as a seam; whichever lands second restates
the requirement text over the amended base rather than over the text both were written against.

**`operator/machine-report`.** Two changes delta it. `unseal-a-value-after-a-reboot` MODIFIES
`A delivered value the machine does not hold is reported`, whose current first scenario says a
reboot loses a value; the retire change only adds. The unseal change therefore owns that sentence.

**The perf gate.** Three of the four touch `lib/`: `run-an-entry-without-root` with the scope atom,
the registry key and the scope-crossing rows, `unseal-a-value-after-a-reboot` with the recipient
grammar, atom and projection, and `probe-a-service-before-it-counts-as-live` with its unit
vocabulary fields. Each is read per machine, per value or per unit of every entry, so each moves
the gated counters and each carries its own baseline-and-check task. They were planned against the
same recorded budgets, so two landing together can pass separately and fail as a pair. Measure
after each, not after all.

**`tests/unit/coverage.nix`.** Every delta spec of the four is registered in `excused` with the
planning artifacts, so the tree is green before any implementation starts. Each change's own tasks
file moves its paths from `excused` to `accountable` in one edit that also ticks every box, because
`changeHasLanded` treats the first `- [x]` at the start of a line as the change having started
landing and `staleExcuses` then fails for an excuse that outlived it. One flip-edit per change, and
every box of all four stays unchecked until its own.

### What this set does not close

A service's mutable state has no declaration site of its own beyond a unit's declared directories,
which is why nothing here can snapshot before an irreversible activation or say what to back up.
That is parked rather than planned: `declare-service-state` was struck once `directoryKinds` made
its premise false, and "Declared state beyond a unit's own directories" in `PARKED.md` carries what
is genuinely unbuilt. No change here creates an account, opens a port, issues a certificate or
routes a request. `rollback` still has no meaning for an entry realised as a portable-service
image, which is
one of the reasons flakelet is the stated target. A machine nobody can dial is named and not
designed: `build-a-bundle-for-a-machine-a-run-cannot-dial`, a named non-goal of
`run-an-entry-without-root`'s proposal, would realise an unmanaged registry machine as one exported
self-installing bundle - artifacts, sealed values, the unsealer, and an installer that is the
one-machine apply walk run locally - and the four changes keep it reachable rather than build it:
attach scripts take no decision from the operator, sealed values need no live channel, and the
preflight stays a list of questions a local installer could ask.

How a machine becomes a member is `enroll-a-friend-machine`, planned and ordered behind all four:
its folder dials a friend machine by its mesh name and places a user-scope entry on it, so it
consumes `run-an-entry-without-root`'s substrate, and the designs it deliberately does not build -
decentralized enrollment, the mesh-provider interface, the phone book, sealed values on gossip -
are parked with their triggers in `PARKED.md` beside this file.

## The five demo changes

`bind-a-value-an-entry-did-not-generate`, `answer-a-machine-question-as-a-record`,
`show-a-deployment-in-a-browser`, `author-a-deployment-from-outside` and
`enroll-a-friend-outside-the-harness`. They exist because the tree can deploy and cannot yet be
shown deploying: the invite flow of `enroll-a-friend-machine` is an order of work a person types
into a test harness, no program renders a plan, and the authoring loop the diagnostics were built
for has no entry point that costs less than a build. This set is product surface over machinery
that landed, and none of it is a redesign of that machinery.

The three changes that carry no ticked box and are not in this set - `account-for-every-
counterexample`, `hold-the-attach-script-to-its-own-discipline` and `hold-the-index-to-the-tree` -
are test and index hygiene, touch no command, no vocabulary and no plan field, and are deferrable
whole. `hold-the-index-to-the-tree` gains five more open changes to read a status word off, which
is a widening of its subject and not a conflict. `deliver-a-secret-without-exposing-it` narrows
once more: `bind-a-value-an-entry-did-not-generate` supersedes its tasks 6.1 and 6.3, the way
`name-the-machine-a-run-dials` superseded its sections 3 and 5.

### Order

1. `bind-a-value-an-entry-did-not-generate` first. It is the only correctness defect in the set,
   and the demonstration's own shape - an entry on a friend's machine opening a secret the
   operator's machine generated - is exactly the shape that trips it. Landing it later means
   demonstrating a failure whose message names neither the value nor the declaration.
2. `answer-a-machine-question-as-a-record` second. Two of the remaining three read either the
   record it returns or the decode it repairs, and reading the sentences instead is a parser
   nobody wants to delete afterwards.
3. The other three in any order. Nothing among them depends on another.

### Seams

**The machine answer.** `answer-a-machine-question-as-a-record` owns the record a question about a
machine answers with, and `show-a-deployment-in-a-browser` is its only other consumer. The view
defines no machine question of its own and adds no remote script: a fact the report does not answer
is a seam recorded here rather than a decision the view takes. This is why the order above is fixed
and not free.

**The six-field row.** `cli/manifest.py` decodes a diagnostics row into four fields while
`lib/diagnostics.nix` requires six of every row, so the one path designed for programs drops the
two an author most needs. `answer-a-machine-question-as-a-record` owns that repair.
`author-a-deployment-from-outside` and `show-a-deployment-in-a-browser` both consume it and neither
restores it a second time.

**A new top-level directory.** Two changes add one: the view, and the published modules of
`enroll-a-friend-outside-the-harness`. `classOf` in `tests/unit/layers.nix` is one table gaining two
rows, and `tooling/repository-shape`'s requirement that every top-level entry has a stated purpose
is deltaed twice. Whichever lands second restates that requirement over the amended base rather
than over the text both were written against, which is the rule the production set already states
for `planner/machine-platform`.

**`tooling/consumer-surface`.** Three changes delta it - the view, the authoring surface and the
two published modules - and each states only the name it publishes. Same rule as above for whichever
lands second and third.

**`delivery/real-cluster`.** Two changes delta it: the cross-entry proof of
`bind-a-value-an-entry-did-not-generate` and the rewrite of the enrollment folder around the verbs.

**The guest image.** `enroll-a-friend-outside-the-harness` is the only change of this set permitted
to edit `tests/e2e/guest.nix`, which it does by making that file a consumer of the published
provisioning module rather than a second copy of it. An edit there re-keys every folder's cut, so
`rookery snapshot gc --all` runs before anything else or a folder resumes a cut whose frozen RAM
names a system generation the new disk does not carry.

**The perf gate.** Four of the five edit no `lib/**` and each carries a task 1.1 recording that and
naming what it edits instead. The fifth does: `author-a-deployment-from-outside` publishes the
authoring vocabulary as data out of a new `lib/vocabulary.nix` projecting the tables `lib/atoms.nix`
and `lib/module.nix` already hold, and touches `lib/default.nix`, `lib/module.nix` and
`lib/resolve.nix` for the key lists it exports. All of it is outside `mkPlan` and outside the right
side of the `korora // { … }` update in `lib/atoms.nix`, which is the one place a new top-level key
costs a copy per plan, so that change carries the `bash perf/measure.sh` baseline and expects every
counter byte-identical rather than merely inside the 0.15 margin. **That prediction was measured
false and the budget was re-recorded.** Publishing an attribute allocates its slot: the
whole-evaluation delta is nrThunks +1, values.number +1, sets.bytes +96 and envs.bytes +16,
constant at every fixture and every size, with nrFunctionCalls, nrPrimOpCalls, list.elements and
`nrOpUpdateValuesCopied` unmoved - the exports are additive rather than an update, which is the
half of the prediction that held. Forty-five of the eighty-one gated figures moved, the largest by
0.056% per entry, and a figure over budget by any amount fails, so the recording is the only way
past it and the slot is the cheapest implementation of a published value. `perf/budgets.json`'s
`note` carries the measurement, the figure and that reading.

**`tests/unit/coverage.nix`.** Every delta spec of the five is registered in `excused` with the
planning artifacts, so the tree is green before any implementation starts. Each change's tasks file
moves its own paths to `accountable` in the one edit that also ticks every box, and every box of all
five stays unchecked until its own.

### What this set does not close

The browser view reads and never writes: an apply is a long-running walk whose recovery is running
it again, and a job model with an identity, a lifecycle and a cancellation is not designed here.
A machine no run can dial is still named and not built -
`build-a-bundle-for-a-machine-a-run-cannot-dial`, above. A friend's arbitrary laptop is still out
of reach: a user-scope entry needs the user portabled, `systemd-mountfsd`, `systemd-nsresourced`,
unprivileged user namespaces, a polkit rule and a verity certificate, which is a machine an
operator configures rather than one that merely exists, and `enroll-a-friend-outside-the-harness`
states that limit rather than papering over it. More than about ten friend machines is still slot
pools and ticket policies, parked in `PARKED.md` with its trigger. And the mesh is still one
backend: the mesh-provider interface stays parked until a second one is deployed.
