## Context

See `proposal.md` - Why. What shapes the approach is that the data already exists and is thrown
away in one place, and that the pure half of the command is already published for import.

`report.status` is one loop of three questions (`cli/report.py:139-168`). The per-entry question
records a line composed at the call site, `f"{entry.key} {entry.realiser} {_answered(entry,
answer)}"` (`:144`); the value question records `value <key> missing on <machine>` out of `_absent`
(`:157-158`, `:266-282`) and the seal lines out of `_seals` (`:159-160`, `:298-337`); the holdings
question records `holding.sentence(machine)` (`:167`). `Report` carries the lines and the machines
that could not be asked (`:81-86`).

Every verdict is computed before it is rendered. `_answered` tells five conditions apart by the
exit status of one ssh (`:364-375`): `UNREALISED` and `UNDIALLED` are the command's own sentinels
(`:77-78`), `remote.UNREACHABLE` is 255 and `remote.MISSING` is `(126, 127)`
(`cli/remote.py:59-60`), a non-zero status from the endpoint itself is absence, and zero is an
answer to read. `_read_status` reads the endpoint's own JSON (`:422-436`): the first registration's
`generation`, its `locked_url`, the unit comparison `_running` makes against `unit_files(entry)`
with its three answers (`:471-486`), and `last_error`. `_read_attachment` reads
`remote.attachment_of` (`:510`, `cli/remote.py:860-890`), projects the identity of the entry's own
image out of the listing with `_held` (`:512`, `:529-548`), compares it against `entry.digest`
(`:517`) and names the configuration paths whose word is not `current` with `_beside`
(`:524-526`). `_seals` reads four words - `remote.OPENS`, `remote.MISSING_COPY` and
`remote.UNCHECKED`, told apart after the `remote.SEALS` marker (`cli/remote.py:128-131`).

Two records already exist as data and are stringified on the way out. `Attachment` carries the
state, the listing and the configuration words (`cli/remote.py:851-858`). `Holding` carries the
realiser, the identity, the removal name and the state, and carries a `sentence` method itself
(`cli/remote.py:920-941`), which both the report (`cli/report.py:167`) and the apply
(`cli/apply.py:205-215`) call.

The consumers are in-process importers, not shell pipelines. `packages.planner-src`
(`cli/flake-module.nix:45`) is published as `PLANNER_CLI_SRC` (`flake-module.nix:201-207`), the
runner puts it on `PYTHONPATH` before any inherited entry (`tests/e2e/runner.py:26-29`, `:355`),
and the harness and a folder's tests already import the modules
(`tests/e2e/test_harness.py:34-44`, `tests/e2e/wired-pair/test_wired_pair.py:87-88`). The command's
own subcommands are exactly `plan build apply status rollback` (`cli/planner.py:100-106`) and the
only JSON any of them prints is `planner plan` (`cli/planner.py:36-38`).

On the build record side, `lib/diagnostics.nix:45-63` requires six fields on every row and
`operator/default.nix:319-329` writes all six into `diagnostics.json`; `cli/manifest.py:664-679`
decodes four into the four-field `Diagnostic` (`cli/manifest.py:123-131`), and
`Deployment.rendered` composes lines out of those decoded rows where the build wrote no table
(`cli/manifest.py:206-210`).

## Goals / Non-Goals

**Goals:**

- One record per question asked, carrying the fields the verdict is made of, returned by the
  library function a program imports.
- Every sentence an operator reads stays byte-identical, produced by one rendering function over
  one record.
- The four answers a report keeps apart become four values of one field, so a consumer reads a
  value and never matches a word.
- `Holding` and `Attachment` escape as records; rendering is the caller's.
- A diagnostics row reaches a program with the six fields the planner produced.

**Non-Goals:**

- A `--json` flag on any subcommand. D3 states why, and the whole reason the pure half is
  published for import is that a second serialisation is not needed.
- Any change to the exit status of any subcommand. `unasked` stays the one thing `planner status`
  exits non-zero on (`cli/planner.py:69-82`).
- Any new question of a machine. The three questions, their scripts and their argv are untouched:
  this change is about what the readings return, not about what is asked.
- Any field no reading computes. The record's field set is derived from `_answered`, `_read_status`,
  `_read_attachment`, `_absent` and `_seals`, and a field nothing produces is not in it.
- A view of the record. `show-a-deployment-in-a-browser` consumes this record and defines no
  machine question of its own; the seam is in `openspec/changes/INTEGRATION.md`.

## Decisions

### D1 - The record is what a question answers, and the sentence is a rendering of it

`report.status` returns records. `Report` carries the records it collected beside the lines it
handed to `log` (`cli/report.py:140`, `:144`) and the machines it could not ask, and each line is
the output of one rendering function over one record. The lines stay in the record set because
they are what `planner status` prints and what `log` receives as the answers are known
(`cli/planner.py:69-82`): a caller that prints is as real a consumer as one that reads fields.

Rejected: **a second pass over the lines.** Parsing `value <key> missing on <machine>` back into a
key and a machine is a second grammar for a sentence whose first grammar is an f-string, and the
two drift the moment a message is reworded. The fields exist before the string does; the string is
the lossy form.

### D2 - The field set is derived from the readings and nothing is invented

Three record shapes, one per question.

The per-entry answer carries: the plan key, the machine and the realiser, which the line already
names (`cli/report.py:144`); how the machine was reached, one of the five values `_answered` tells
apart (`:364-375`); what the machine printed, which the no-endpoint answer already carries
(`:372`); whether the endpoint answered and registered nothing, which is absence (`:426-427`) or,
for an image, a listing holding no image of this entry whose word is the detached one (`:513-514`);
the identity the machine holds, which is the image identity `_held` projects out of the listed name
(`:512`, `:529-548`) or the generation and the locked url a flakelet endpoint reports (`:432-433`);
the identity this build published, which is `entry.digest` for an image (`:517`) and the artifact's
own unit files for flakelet (`:484`); the unit comparison's three answers (`:482-486`); the
attachment state the machine's own tool printed (`:514`, `:520-521`); the configuration paths whose
word is not `current` (`:524-526`, out of `remote.Attachment.configuration`,
`cli/remote.py:857`, `:875-879`); and the last error the endpoint recorded (`:435`).

The per-value answer carries the value key, the machine, whether every declared path is present
(`:266-282`) and the machine's own verdict on the sealed copy - it opens, there is no copy, it does
not open, or the copies were not checked because the machine holds no unsealer (`:319-337`, over
`remote.OPENS`, `remote.MISSING_COPY` and `remote.UNCHECKED` at `cli/remote.py:128-131`).

The per-holding answer is `remote.Holding` as it already is (`cli/remote.py:920-941`) plus the
machine it was asked of, which is the only thing `sentence` took as an argument (`:938-940`).

Rejected: **a flat mapping of strings.** A dict keyed by field name makes every consumer guess
which keys a question produced, and the five ways an entry can fail to be answered each leave a
different subset of the fields meaningful. Three frozen dataclasses say which fields exist for
which question, which is the same discipline `manifest.py` already applies to a build record.

Rejected: **inventing a currency verdict field.** A single `current` boolean would be a fifth
reading of facts three layers already state, and it would have to lie for a flakelet endpoint,
which publishes no identity of the artifact it activated (`cli/report.py:471-481`). The record
carries the two identities and the comparison the endpoint permits; the word is the renderer's.

### D3 - The record is returned by the library function, not printed by a `--json` flag

`report.status` returns the records to its caller. No subcommand grows a flag and no subcommand
grows an output format.

Rejected: **`planner status --json`.** The consumers are in-process importers: the pure half of the
command is published as `packages.planner-src` (`cli/flake-module.nix:45`) and exported as
`PLANNER_CLI_SRC` (`flake-module.nix:201-207`) precisely so it can be imported, the runner puts it
on `PYTHONPATH` ahead of any inherited entry (`tests/e2e/runner.py:26-29`, `:355`), and the
harness and a folder's own tests already import `report` and `apply`
(`tests/e2e/test_harness.py:34-44`, `tests/e2e/wired-pair/test_wired_pair.py:87-88`). A flag would
be a second serialisation of the same record, reached only through a subprocess, and the only JSON
a subcommand prints today is `planner plan` (`cli/planner.py:36-38`) - a file the build already
wrote, not a shape this command invents. A second shape nobody imports is a second shape nobody
tests: it would need its own field names, its own version and its own cases, and the record it
serialises would still be the thing under test. The subcommand set stays exactly
`plan build apply status rollback` (`cli/planner.py:100-106`).

### D4 - Byte-identical sentences are the compatibility contract, and the folders are the proof

Every line the command prints is the output of one rendering function over one record, and the
bytes do not move. The evidence is already committed: the flakelet verdict
(`tests/e2e/wired-pair/test_wired_pair.py:703-706`, `:747-749`,
`tests/e2e/newcomer/test_newcomer.py:681-684`, `tests/e2e/test_harness.py:2487-2488`), the last
error (`tests/e2e/test_harness.py:2338-2341`), the four non-answers
(`tests/e2e/test_harness.py:2390`, `:2422`,
`tests/e2e/friend-enrollment/test_friend_enrollment.py:862-866`), the image verdicts
(`tests/e2e/portable-image/test_portable_image.py:690`, `:878-881`, `:1058-1059`) and the holding
line (`tests/e2e/test_harness.py:3312`, `:3391-3392`, `:3464`,
`tests/e2e/wired-pair/test_wired_pair.py:965-966`,
`tests/e2e/portable-image/test_portable_image.py:1446`). Those assertions are not rewritten by
this change: they are what makes it provable, and `docs/operator.md:515-519`, `:521-528`,
`:541-547`, `:573-578` and `:607-609` stay true without an edit to a documented line.

Rejected: **improving a sentence while the record lands.** A reworded line is a separate decision
an operator has to be told about, and folding it into this change would destroy the one property
that makes the change safe to land: that nothing an operator reads moves.

### D5 - `Holding.sentence` leaves the record

The method moves out of `remote.Holding` (`cli/remote.py:938-940`) into the rendering function, and
both callers - the report (`cli/report.py:167`) and `apply.holding_lines`
(`cli/apply.py:205-215`) - render through it. The line a report and an apply both print stays one
string built in one place, which is why the apply's `; not retired` suffix is still an append onto
that one string (`cli/apply.py:212-215`) rather than a second composition.

Rejected: **keeping the method and adding a renderer beside it.** Two ways to turn one record into
one sentence is the thing this change is deleting, one layer down.

### D6 - The four answers are four values of a field, not four spellings

`openspec/specs/operator/machine-report/spec.md:41-48` and `:149-166` keep four answers apart - an
entry the endpoint does not register, a machine carrying no endpoint, a machine that answers
nothing, and an entry whose machine declares no address - plus the fifth condition that is the
command's own refusal. Each becomes a value of one closed field, and absence stays produced by one
fact: an endpoint that answered and registered no entry. A consumer distinguishing them reads the
field.

Rejected: **letting a consumer match the prose.** `absent`, `unreachable:` and `no endpoint on` are
prose an operator reads; a consumer keying on them makes every message a compatibility surface,
which is exactly the trap `report.py`'s own docstring names - printing absence for a machine nobody
asked tells an operator the deployment was never applied (`cli/report.py:4-18`).

### D7 - Staleness is a field and still never an exit status

The record carries the identity the machine holds beside the identity the build published, so
staleness is readable as data for the first time. It changes no exit status: `planner status` exits
non-zero for `unasked` and for nothing else (`cli/planner.py:69-82`), a report whose machines all
answered exits zero however stale their answers are, and the same holds for a missing value and for
a holding the build does not name. The requirement states it over the record so that a consumer
reading a staleness field is not reading a licence.

### D8 - The diagnostics decode carries six fields, and there is no second reader

`Diagnostic` gains `evidence` and `resolution` (`cli/manifest.py:123-131`) and `_rows` decodes them
(`cli/manifest.py:664-679`). `_rows` is the only decode of `diagnostics.json`, and every reader of
a build's rows goes through it, `Deployment.rendered` included (`cli/manifest.py:206-210`). A row
the planner produced always has all six, because `lib/diagnostics.nix:45-63` requires them of every
producer and `operator/default.nix:319-329` writes the reading's rows out whole.

Rejected: **a second reader of `diagnostics.json` for the two fields.** Two decodes of one file
diverge - a field defaulted in one and required in the other, a row shape one refuses and the other
accepts - and the reader every command already uses would still be the lossy one, so an author
reaching for `evidence` would have to know which of two readers to import. The decode is where the
fields are lost, so it is where they are restored.

### D9 - This change is second in the set and the seam is written once

`bind-a-value-an-entry-did-not-generate` lands first; this change lands second; the browser view,
the authoring command and the enrollment change follow in any order and consume what this one owns.
This change owns the structured record `report.status` returns and the two diagnostics fields
`cli/manifest.py` restores, and nothing downstream defines a second machine answer.
`openspec/changes/INTEGRATION.md` is the one place the order and the rest of the seams are written
out.

## Risks / Trade-offs

- **A record with five conditions has fields that are meaningful for some of them only.** An
  unreachable machine says nothing about an identity, and a consumer reading the identity field of
  such a record would read an absence as a fact. → The reached field is read first by construction:
  the identity fields are absent rather than empty on a record whose machine did not answer, which
  is the same discipline the plan already applies - an absent field means the reading does not know
  (`CLAUDE.md`, under "Interfaces, composition, reads").
- **A rendering function is a single point every line passes through.** A mistake there moves every
  sentence at once rather than one. → That is what the folders assert, string for string, across
  five of them (D4), and the byte-identity task runs them before the change is called done.
- **The record is the command's own python and not a published artifact, so an importer is coupled
  to a dataclass.** → Deliberate: the alternative is a serialisation format with its own version,
  which D3 rejects. The coupling is the one the harness and two folders already have
  (`tests/e2e/test_harness.py:34-44`, `tests/e2e/wired-pair/test_wired_pair.py:87-88`).
- **Two more fields on `Diagnostic` reach every reader of a build's rows.** → Both are required of
  every row by the producer (`lib/diagnostics.nix:45-63`), so no reader can meet a row that lacks
  them, and the decode defaults them the way it defaults the four it already reads
  (`cli/manifest.py:670-676`).
- **Staleness becomes readable, which is the fact an operator most wants to act on
  automatically.** → The requirement states that it is a line and never an exit status over the
  record itself, so the temptation is refused in the specification and not left to a reader of the
  field.

## Migration Plan

Nothing migrates and nothing re-keys. No plan field, no registry key, no row, no artifact and no
key input changes, so every fixture, every golden and every recorded perf counter is untouched -
which is why this change records no perf baseline and says so as a task rather than inventing one.
`Report` gains the records beside `lines` and `unasked`, so `planner status`, `planner apply` and
every caller that prints keep working unchanged, and the string assertions in the five end-to-end
folders pass without an edit. The diagnostics decode gains two fields on a dataclass no consumer
outside this repository holds. The one observable change for a program is that there is now
something to read; the one observable change for an operator is none.
