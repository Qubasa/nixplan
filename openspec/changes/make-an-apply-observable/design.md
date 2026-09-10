# Design

## D1 - What a broken apply leaves, and why the recovery is another apply

A run walks values first, then entries in provider-before-consumer order, one machine at a time
(`cli/apply.py:206-229`). Break it anywhere and the cluster holds a prefix of that walk: some
machines carry the new artifact and run it, some carry the bytes of a value and none of the entries
that read it, and the rest carry what the previous run left. Nothing is half-written on any single
machine, because each step is one ssh invocation that either completed on that machine or did not: a
value file is written under `umask 077` by one script (`cli/remote.py:139-146`), an artifact arrives
through one `nix copy`, and an activation is one call into the endpoint, which owns its own
generation bookkeeping.

Two recoveries are available for that state.

| Recovery | What it needs | Why it loses or wins |
| --- | --- | --- |
| undo the batch | a generation the whole run moves as one, on every machine | no such generation exists. An endpoint counts generations per service, and an image entry has none at all - `cli/report.py:110-114` already refuses to roll one back. Undoing a prefix would also mean detaching images the run attached and deleting value bytes a previous run may have relied on |
| run it again | every step to be repeatable | each step already is, or is made so here. The walk is a function of the plan, so the second run takes the same order, and the steps that already happened cost a comparison each |

The recovery is therefore a second apply, and the property that makes it one is per-step
repeatability:

- **A value write** rewrites the same bytes at the same path with the same mode. The source is the
  operator's directory, checked against the plan before anything is dialled, so a second run writes
  what the first would have written.
- **A copy** is `nix copy` of a closure the machine may already hold; a store path that is valid on
  the target is not sent again.
- **A flakelet activation** is the endpoint's own no-op when the artifact is unchanged. The machine
  layer already asserts it: `test_an_unchanged_entry_is_a_no_op` re-applies one entry and reads back
  the same generation and the same main PID (`tests/e2e/wired-pair/test_wired_pair.py:527-535`).
- **An image attachment** is the exception, and this change fixes it. `bin/attach` runs under `set
  -eu` (`image/default.nix:179-187`) and ends in `portablectl attach … && systemctl start …`
  (`:227-228`); `portablectl` refuses an image it already holds attached, so a second run over an
  attached entry fails on a machine that is in the intended state. The command therefore asks the
  question it already knows how to ask - the status script of `cli/remote.py:180-183` - and reports
  the entry as already attached instead of running the script. The alternative, making the script
  itself idempotent, changes an artifact every image realisation produces and puts the decision in
  the layer that owns confinement rather than in the layer that owns the walk.

A second run needs the same `--values` directory as the first, because the source is checked whole
before anything is dialled. That is a property of the value source and this change keeps it; what it
adds is the documentation of it, which `docs/operator.md` currently lacks.

## D2 - No record of progress on the operator's side

The tempting shape is a file: a run writes each completed step to `~/.local/state/planner/<hash>`
and `--resume` replays what is missing. Three reasons against, in order of weight.

1. **A second answer that can be wrong.** The machines already hold the state, and each endpoint can
be asked what it holds. A file is a claim about the same fact, written by a process that may have
been killed between the step and the write. Where the two disagree, an operator has to work out
which lies, and the file is the one with no evidence behind it. 2. **It does not shorten the
recovery.** A resumed run still checks the value source whole, still reads the plan, and still has
to copy and activate whatever the file does not account for. The steps a resumed run would skip are
the steps that cost a comparison, because of D1. 3. **It is state the command would own.** A path, a
naming scheme keyed by something, an eviction rule, and a second thing to keep in step with a plan
that moved. The command reads a built directory and dials machines; it owns no state today, and this
is not the reason to start.

What replaces it is the two things an operator actually reads: the step log, which under D5 ends at
the step that broke, and `status`, which under D6 answers per entry with what the machine holds. A
narrower second run is `--only`, and D3 is what makes that restriction reach exactly the machines it
names.

## D3 - Where a run stops, and what it exits

`status` and `apply` are asked the same question - what happened on each machine - and answer it
differently on purpose.

`status` reads. One machine's silence says nothing about another's answer, so a report prints each
line as it is known, a machine that could not be reached gets a line naming it unreachable, and the
command exits non-zero when any machine could not be asked. Buffering, which is what
`cli/report.py:77-83` does today, converts one dead machine into an empty report of a live cluster.

`apply` writes, and it stops at the first step that fails. The alternative - carry on with the
entries that do not depend on the failed one - was considered and loses:

- the ordering guarantee becomes conditional. "A provider is activated before its consumer" is the
  requirement; after a provider's failure, a consumer applied anyway starts against a provider that
  is not there, and the walk would have to model which failures are upstream of which entries;
- an operator watching a run wants one boundary. A run that continues has a set of boundaries, and
  the recovery of D1 becomes "apply again except for these";
- the narrower run is already expressible. `--only` names the entries to retry, and under D6 it
  contacts only their machines.

Exit status follows from both: a run that dialled and did not complete exits non-zero, and prints
the failing step as its last line rather than raising. `cli/planner.py:150-153` catches `ApplyError`
only, so the piece of work is at the runner: `Subprocess.run` and `Subprocess.output`
(`cli/remote.py:51-58`) raise `CalledProcessError`, which escapes as a traceback and, for a value
write, carries the argv. Both become the command's own error naming the entry, the machine and what
the machine printed.

## D4 - The rule for breaking a cycle, stated so a test can hold it

Two instances wiring each other is a legal deployment and its activation graph has no first element,
so the walk breaks a cycle rather than refusing (that decision belongs to
`apply-deployments-with-an-operator-command`, design D6, and stands). What is wrong today is the
choice of edge: with nothing ready, `cli/order.py:52-58` takes `remaining[0]` and contradicts every
unapplied read of that key, whether or not any of them lies on a cycle.

Read the remaining entries as a graph whose edges are the reads the plan resolved, provider to
consumer. When no entry is ready, every remaining entry has an unapplied provider, so the graph has
at least one cycle. Call an entry **eligible** when every one of its unapplied providers can be
reached from that entry itself by following those edges forward. The rule is:

1. take the eligible entries; 2. choose the lowest by plan key sort order; 3. contradict exactly the
edges into it from its own unapplied providers, and report each; 4. continue the walk.

Every contradicted edge lies on a cycle, by the definition of eligible: the provider is reachable
from the consumer, so provider and consumer sit on one cycle. An eligible entry exists whenever
nothing is ready, because a graph in which every node has an incoming edge holds a cycle, and every
node of a cycle whose members have no other unapplied provider is eligible; taking a strongly
connected component with no incoming edge from another remaining component yields one. Determinism
comes from step 2 and from sorting the reported edges by provider.

On the case that produced this rule - `a:x@m` reads `b:y@m`, and `b:y@m` and `c:z@m` read each other
- `a:x@m` is not eligible, because it cannot reach `b:y@m` forward; `b:y@m` and `c:z@m` are. The
  walk takes `b:y@m`, reports the read of `b:y@m` by `c:z@m` as the edge it ordered against, and
  then finds `c:z@m` and `a:x@m` ready in turn: the order is `(b, c, a)` and one edge is
  contradicted, where the current walk contradicts the read of `b:y@m` by `a:x@m` and satisfies
  neither ordering claim.

Two alternatives were weighed. Refusing a cycle refuses a deployment the library accepts, which is
already settled. Contradicting every edge of the component at once (rather than only those into the
chosen entry) reports edges the resulting order satisfies, and a report an operator cannot trust is
worse than a shorter one.

## D5 - A line before the step, not after it

`record(...)` after the step is what makes a broken run unreadable, and the fix has a cost worth
naming: a line printed before the step is a claim about an attempt, not about a result. A reader of
the log has to know which it is.

The shape chosen: the announcement is the step line the command already prints, emitted before the
step runs; a step that fails is followed by a failure line naming the same step, the machine and
what the machine said; a step that succeeds and had something to report keeps printing the machine's
output indented under it, as today. The last line of a broken run is therefore the failure, and the
last step line before it is the step that broke. The returned tuple - what the machine layer reads -
holds the same lines in the same order, so a test reads the boundary the operator reads.

The rejected alternative is a pair of lines per step, one before and one after. It doubles a log
whose whole purpose is to be read at a glance, and the "after" line carries nothing the next
announcement does not already imply.

## D6 - What a report tells apart, and what the fourth answer costs

Today `flakelet status --json <name> 2>/dev/null || printf '[]'` (`cli/remote.py:175-179`) turns
four situations into one word. Absence, a machine with no endpoint on its `PATH`, a permission error
and a stopped daemon all print `absent`, which is the one word an operator reads as "the deployment
is not there yet".

The four have to be told apart because they need four different actions: apply, install the
endpoint, fix the login, start the daemon. The script therefore keeps its standard error, the
command reads the exit status, and the report distinguishes:

| What happened | What the machine gives | The line |
| --- | --- | --- |
| the endpoint answers with no entry under that name | exit 0, `[]` | absent |
| the endpoint answers | exit 0, one record | the generation, the identity it stores, and `last_error` when it holds one |
| the endpoint is not there, or refuses | non-zero, output on standard error | no endpoint, with what the machine said |
| the machine does not answer at all | ssh fails | unreachable |

The cost is real and is the reason this is a decision rather than a correction: a fresh machine, one
that has been booted and never applied to, currently answers `absent` for every entry, and after
this change it answers with what the machine said about the endpoint. A first-run walk therefore
sees a page of refusals where it used to see a tidy column, and `status` exits non-zero there.

The choice is that this is the honest answer. `absent` is a claim about the deployment - the machine
was asked and had no such entry - and only an endpoint can make it. A machine that cannot be asked
has said nothing about the deployment, and printing a claim on its behalf is what made D1 of the
review reproducible: an operator who applies, sees the run break, and asks `status` is told the
entries were never applied. An image entry keeps a separate reading for the same reason: `attached`
is one of four words `portablectl is-attached` prints (`attached`, `attached-runtime`, `running`,
`running-runtime`), the current comparison against the literal `attached` reports every other word
as absence, and `image/default.nix:227-228` starts the units immediately after attaching, so the
word a healthy machine gives is one the command calls absent. Only `detached` is absence.

## D7 - Bounding silence rather than bounding work

A missing `ConnectTimeout` and a missing `BatchMode` are one defect with two faces: the command
waits forever on a machine that does not answer, and prompts on a captured standard input for a host
key. A wall-clock timeout on the whole step looks like the fix and is not: `nix copy` of a first
closure onto a fresh machine legitimately runs for minutes, and every candidate value for such a
timeout breaks a real deployment on a slow link.

What is bounded is silence instead: `BatchMode=yes` (never ask a question nobody can answer),
`ConnectTimeout` (a machine that does not complete a connection is unreachable), and a server-alive
bound (a connection that stops carrying bytes ends rather than hanging). A step that keeps making
progress is never interrupted by the command.

These are appended to the options the caller set rather than prepended, and the order is
load-bearing: ssh uses the first value obtained for each option, so options added after the caller's
lose to the caller's. An operator who sets `ConnectTimeout` in `NIX_SSHOPTS` keeps it, and the
command's values are defaults in the only sense that matters. Host-key policy stays out of this
change; it belongs to `deliver-a-secret-without-exposing-it`, which owns C3.

## D8 - Measuring the value source where the deployment declares files

`values.check` refuses a source holding a path no delivered value declares, and measures with
`rglob("*")` over the whole directory (`cli/values.py:112-121`). The check earns its place - bytes
under a key no value entry carries are a misspelled entry key, and the operator believes those bytes
were delivered - but the measurement is wrong twice: it counts files that were never a claim
about a value, and it names one extra out of any number.

The layout is `<dir>/<entry-key>/<file>`, so the claim a file makes is made by living under the
directory of a value entry. The measurement becomes: for each value entry the deployment delivers,
the files under that entry's own directory; anything under the source that is not under one of those
directories is not measured. A `README`, a `.gitignore` and an editor backup beside the entry
directories are therefore not extras, while `issuer:vars/session/toekn` still is, which is the case
the check exists for. Every extra is named, sorted, because an operator fixing a source wants the
list rather than the first line of it.

The alternative of dropping the extra check entirely was weighed and loses: it converts a misspelled
file name from a refusal into a silent non-delivery, and the failure then appears as a unit that
cannot start on a machine, one dial later.

## D9 - Which side states the shape, and which side refuses it

`operator/read.nix:231-233` already writes `version = 1` and `storeDir` into the record, and
`cli/manifest.py:157-166` reads neither. Two ways to close that, and they are not symmetrical:

- **the build states, the reader refuses.** The record declares the shape it was written in and the
  store its artifact paths live in; a reader that does not implement that version says so, naming
  both versions, and a reader running against another store says so, naming both stores.
- **the reader tolerates.** Read what is recognised and ignore the rest. That is the current
  behaviour by omission, and its failure mode is the one the review found: a record from another
  revision is read as this one, and a misspelled `entries` key becomes a deployment that places
  nothing while the run exits zero having done nothing.

The first, and the split is worth stating because the two halves land in different capabilities. The
declaration is `operator/deployment-build`: a record that does not state its own version cannot be
refused by version, so the requirement there gains it. The refusal is `operator/apply-command`: the
command is the reader, and a reader is where a version check belongs. A missing `entries` table is
part of the same decision - an absent table is not an empty table, and only the reader can tell an
operator which it got.

An absent `address` is deliberately not in that set. `report-every-refusal-as-a-row` moves
`operator-entry-machine-no-address` to a warning, so a record may carry a placed entry whose machine
declares no address; the reading has to carry that absence rather than refuse it, and the refusal
stays where it already is, at the point of dialling.

## D10 - A collected build is named, and no root is taken

`manifest.resolve` builds with `--no-link --print-out-paths` (`cli/manifest.py:118-127`), so nothing
roots the result. A path a collector removed comes back through `nix build` as `don't know how to
build these paths`, which reads as a broken flake attribute rather than as a build that is gone.

Registering a garbage-collection root would prevent one of those two, and it was rejected: a root
that outlives the invocation is state the command would have to name, place and reclaim (D2), and a
root that does not outlive the invocation protects a window nothing is known to fail in - a
collection racing a running apply removes a path the machine already received or is about to receive
from a copy that holds its own lock.

What the command does instead is recognise the condition it cannot prevent. A target that names a
path under the store directory and does not exist is refused as a build that was collected, naming
the path and telling the operator to build the reference again. That message is reachable from the
one thing the command has - the target string - and it costs one existence check before the build is
attempted.

## D11 - Which layer each new fact is proved at

Three homes, and the rule is the one the repository already uses.

| Fact | Home | Why |
| --- | --- | --- |
| the ordering walk, the value-source measurement, the record refusals, the step log's order, the ssh options | `tests/e2e/test_harness.py` | the command's pure half. A recorder in place of a process table observes argv and order with no machine, which is what task 3.4 of `apply-deployments-with-an-operator-command` established |
| the record states its version and its store | `tests/unit/operator.nix` | a fact about the reading, and the evaluating layer has no `pkgs` |
| an apply broken between two machines, and the second apply that finishes it | `tests/e2e/wired-pair/` | two machines, a real endpoint, a real route to cut |

The machine-layer phase goes to `wired-pair` rather than to the `tests/e2e/newcomer/` folder that
`open-the-repository-to-a-consumer` adds, for one reason: a run has to break *between* two machines,
and the newcomer folder deploys one machine and one service on purpose. It runs last in the folder's
ordered session and restores the route it cut, in the idiom
`test_cutting_the_wires_far_end_is_visible` already uses
(`tests/e2e/wired-pair/test_wired_pair.py:510-524`).

The break is deterministic rather than raced: the route to the second machine is cut before the run
starts, so the run reaches the first machine and fails on the second. A test that cut the wire from
another thread while the apply walked would be asserting the same two facts with a timing dependence
between them.
