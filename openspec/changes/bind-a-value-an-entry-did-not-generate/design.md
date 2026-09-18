## Context

See `proposal.md` - Why. What shapes the approach is where the relation between a read and a value
already exists, what publishing it would cost, and which layer may raise.

The relation exists three times over and is published once. `mkPlan` holds it per edge as
`edge.entryVarsFiles`, keyed by provider entry key and read name, and spends it on
`slot-reads-value-unreadable-by-user` (`lib/plan.nix:329-361`, the walk at `:360`). The delivery
set is derived from it: the value entry the probe in `proposal.md` produced records
`deliveryDerivedFrom = [ "app:only@one named token in uses.cred.reads", "vault:only@one owns it" ]`.
What reaches the plan is narrower - `readsRecord` (`lib/plan.nix:239-283`) publishes
`values.<read>`, and for a secret export backed by a generated file that is the reference record
`{ path, secrecy }` the export's `read` field carries (`lib/resolve.nix:2077-2083`). The path is a
function of the value's identity alone, `"${util.varsRoot}/${iname}/${gen}/${fname}"`
(`lib/resolve.nix:1685`).

Publishing more than the path is not free. `reads` is in an entry's key input
(`lib/plan.nix:1086-1102`), so a read record carrying a peer's `owner`, `group` and `mode` would
re-key every consumer the moment a peer's `mode` moved, which is the failure the delivery set's own
exclusion from a value's key exists to avoid (`lib/plan.nix:1300-1307`). The path is already in
that key input and adding nothing.

On the reading side, `image/read.nix`'s `read` is handed the whole plan (`:758-770`) and may raise;
its three non-raising entry points - `hostPaths` (`:686-691`), `denials` (`:693-706`) and
`versionFor` (`:713-756`) - are handed one entry and may not. `operator/read.nix` is on `lib/`'s
side, holds the plan, and already builds two tables over it: the per-entry reading
`readEntry { plan, realise }` (`:127-129`) and the per-value reading `readValue` (`:469-483`),
assembled at `:705-717`, with the per-machine reading already taking the value table as an argument
(`:514-520`, called at `:734`). A realiser refusal that mirrors a row of that reading is the
established shape: `imageReader.denials` and `operator-entry-access-denied`
(`image/read.nix:212`, `operator/read.nix:388-399`).

## Goals / Non-Goals

**Goals:**

- A unit is shown every value its entry declared a read of, on the same terms as a value its entry
  generated: one bind, one mount point, one existence guard, one denial comparison.
- One list, asked by every reading that asks about a value: the host paths, the profile denial
  table, the reference paths and the attachment description. A fifth site would be a place to
  forget it.
- A value reached twice is one record, so the rendered unit carries one bind and the image one
  mount point.
- A shown value path no delivered bytes can be accounted for is a refusal naming the entry, the
  slot and the value, and a row above it.
- No plan field, no `lib/` edit, and no edit to `image/default.nix`.

**Non-Goals:**

- Narrowing the denial to the units that name the file. That is task 6.2 of
  `deliver-a-secret-without-exposing-it` and is orthogonal: it changes which units a denial names,
  not which files are compared.
- Widening any delivery set. A read is already what puts a machine in one
  (`lib/plan.nix:165-168`); this change reads that set and never contributes to it.
- Publishing the read-to-value relation in the plan. Stated as a rejection under D1.
- A second proof folder. Stated as a rejection under D6.
- Anything about a machine question or a report. The record `report.status` returns is
  `answer-a-machine-question-as-a-record`'s, behind this change in the order
  `openspec/changes/INTEGRATION.md` states.

## Decisions

### D1 - The join is by the path the read record already carries

The reading builds one index over the plan's value records, keyed by the path each declared file
records, and looks up every value path an entry's reads name. The index is the realiser reading's
own and recognises a record by what it records - `delivery` beside `files` - which is the
`isVarsFile` idiom (`lib/util.nix:499-518`) and never the text of a key, the rule
`operator/read.nix:59-71` states for the same question. A record whose `delivery` is not a list or
whose `files` is not an attrset of records with a string `path` contributes nothing, so the index is
total and a malformed value record surfaces as the refusal of D4 rather than as an evaluation error
inside a reading that may not raise.

Rejected: **publishing the relation as a plan field.** `edge.entryVarsFiles` already exists in
evaluation, and recording it on the read record would be the shortest implementation. It is refused
because `reads` is in the entry's key input (`lib/plan.nix:1086-1102`): a peer's `owner`, `group`
and `mode` in the consumer's read record re-keys the consumer every time the peer's file record
moves, which redelivers and re-attaches bytes that are still correct - the exact reason the delivery
set is kept out of a value's key (`lib/plan.nix:1300-1307`). The path is already in that key input,
so joining on it adds nothing to any key.

Rejected: **recognising the value by the read record's shape.** A secret read is
`{ path, secrecy }`, and a public export backed by a generated file publishes the whole file record
as its `read` (`lib/resolve.nix:2077-2083`), so a shape test would be two shapes and would drift on
the next export kind. `util.varsPathsDeep` (`lib/util.nix:369-377`) recognises a value path inside
any string by its shape, which is the recogniser `misdeliveredRows` (`lib/plan.nix:635-677`) and
`opensAValue` (`operator/read.nix:498-503`) already ask, and it is asked here of one slot's record
at a time so the answer carries the slot that named it.

### D2 - One union, computed once per entry, read by four readings

`valuesOf` answers `{ generated, unaccounted }` for one entry: `generated` is the entry's own
`generatedOf` walk followed by the read-derived records for paths that walk did not already carry,
and `unaccounted` is the slot-and-path pairs the index could not answer for. The union keeps the
first record for a path, which is the `dedup` discipline `CLAUDE.md` states for rows, so a value
reached by two reads of one provider's two exports, or by a read and the entry's own generator, is
one record - one `BindReadOnlyPaths` line (`image/read.nix:640-642`), one `install -D` mount point
(`image/default.nix:103-109`), one existence guard (`image/default.nix:344-348`) and one denial.

Both halves carry one field set, because every reader of the list may index any field of it and a
half-shaped element is what `required` (`image/read.nix:300-305`) exists to refuse: the file's own
`path`, `secrecy`, `deploy`, `inPlan`, `owner`, `group`, `mode` and `present`, and the provenance a
refusal names - the slot and the value entry's key for a read-derived record, the generator and the
file name for the entry's own, each null on the other half.

The four readings that stop walking `entry.vars` and read the union: `hostPathsOf` (`:562-591`),
`denialsOf` (`:602-635`, already parameterised on `generated`), `referencePaths` (`:809-814`) and
the attachment description's `generated` table (`:1169-1174`). The attachment description gaining
the peer's values is what makes it reviewable in the sense its requirement asks for: a description
naming only half the paths the unit is shown describes a different attachment.

Rejected: **widening `hostPathsOf` alone.** The denial reading and the reference-path reading are
about the same files for the same reason, and three walks of one relation is how the two copies of
`util.admits` came to disagree (`CLAUDE.md:368-371`).

### D3 - The index rides the reading, and the three entry points take the union

`operator/read.nix` builds the index once per reading, between the `{ plan, realise }` layer and the
`key` layer of `readEntry` (`:127-129`), computes the union once per entry beside the denials it
already computes (`:237-244`), and hands `generated` to `hostPaths`, `denials` and `versionFor`
(`:171`, `:241`, `:280-283`). `image/read.nix`'s `read` builds both itself from the plan it already
has (`:758-770`). The three entry points gain one argument each and lose their internal
`generatedOf entry` call.

Rejected: **the entry points taking `plan`.** A `groupBy` over the fleet's value records inside each
of three calls per entry is the whole plan walked three times per entry for one relation, and Nix
memoises a thunk rather than a function call. One index per reading is the shape the per-machine
reading already uses, taking the value table as an argument rather than rebuilding it (`:514-520`,
`:734`).

Rejected: **reusing `operator/read.nix`'s own `values` table** (`:712-717`). Its file records carry
the five fields a delivery interpolates (`fileFields`, `:437-443`) and not `deploy` or `inPlan`,
which are the two conditions the shown-path rule turns on, and `readMachine`'s own filter requires
every field of that list to be a non-empty string (`:529`), which a boolean is not. Growing that
list to serve this reading breaks the reading it was written for.

### D4 - An unaccountable shown value path is a refusal with a row above it

A read record naming a value path the index cannot answer for - no value record carries that path,
or the record that does does not name this entry's machine in its delivery set - is
`operator-entry-value-unaccounted`, an error row of `operator/read.nix` naming the entry, the slot
and the path, and the builder's refusal in `image/read.nix` carries that identifier in its
`accounts` entry (`:183-215`). That is the shape `operator-entry-access-denied` already has
(`image/read.nix:212`, `operator/read.nix:388-399`) and the shape
`operator-entry-extension-field-unrendered` has for a table the reading asks the realiser for.

The row belongs to the reading and not to `mkPlan` because the fact is a cross-record consistency
fact about a plan the reading was handed: inside `mkPlan` it cannot arise, the delivery set being
derived from the reads that would name it. Its neighbours are `operator-plan-record-unclassified`
and `operator-plan-field-missing` (`operator/read.nix:407-419`), which are rows about the same class
of handed-in plan.

A value the plan records as undeployed is not this refusal. It is shown at no path, by the condition
the requirement already states, and the operator's row for it is
`slot-reads-undeployed-value` (`lib/resolve.nix:2516-2525`).

Rejected: **an account with no row** (`id = null` with a `because`, the shape
`unitFieldUnrendered` uses at `image/read.nix:200-203`). That shape is for a defect of the builder's
own table, which no deployment can produce. This condition is reachable from a plan a caller hands
in, so `tests/unit/diagnostics.nix` is right to demand a row above it.

### D5 - The digest is already right, and it moves

`versionFor` takes the digest over `hostPathsOf` (`image/read.nix:733-747`), and the requirement
already names "the host paths it is shown" among the statements it covers
(`openspec/specs/realiser/portable-service-image/spec.md:767-774`). Widening the set therefore
widens the digest with no edit to the digest and no change to that requirement's rule. The answer is
stated rather than left implicit: a consumer that declares a read of a peer's value publishes a
digest it did not publish before, so the first apply after this change stops, detaches and
re-attaches exactly those entries and nothing afterwards - which is the cost that requirement
already records for a widening (`spec.md:782-784`).

### D6 - The proof is a phase of `tests/e2e/portable-image/`, not a folder

A cross-entry value read needs one machine: the owner's placement puts the value on the reader's
machine, and the folder already runs one booted machine (`test_portable_image.py:298`). The stage's
key is the guest image, the machine names and the disk figure (`tests/e2e/delivery.py:877-942`, the
figure declared part of the key at `:919-923`); a deployment edit moves none of them, so the phase
resumes the cut the folder already warms. The folder also already owns every `portablectl` claim
and states its confined entry `strict`, so the denial half of the rule is observable there against
enforcement rather than against a description.

A folder of its own would pay a full cut to take, warm and store, and could not reuse the report
module: `tests/unit/layers.nix:1036-1039` refuses a folder whose text names a sibling folder and
`:1041-1044` refuses a byte-equal copy of a sibling's file, so the module would have to be rewritten
to differ. Growing the shared guest image is the other way to pay, and re-keys every other folder's
cut.

The flakelet half needs no folder at all: `tests/e2e/shared-postgres/` already reads a peer's value
(`deployment/modules/app/client.nix:17-22,49`) under the flakelet realiser
(`test_shared_postgres.py:533`), so it observes the rule's other realiser by existing, with no edit.

## Risks / Trade-offs

- **A flakelet entry that reads a peer's value gains a mount namespace it did not have.** `bindsOf`
  is the shared reading's and flakelet's wrapper renders it (`tests/unit/flakelet.nix:708`), so
  three consumer entries of `shared-postgres` gain one `BindReadOnlyPaths` line each. → The line is
  the same self-bind those units already carry for their own values (`tests/unit/image.nix:3090`),
  flakelet's `pathRule` is written for a delivered file arriving before activation
  (`flakelet/read.nix:128-135`), and the apply writes values before any entry is activated. A task
  runs that folder and records the one-time new generation.
- **A value the run has not written turns a failed open into a failed start.** A bind of an absent
  path is `226/NAMESPACE` rather than the program's own `ENOENT`. → That is the better failure: the
  service manager names the path, and `image/default.nix:344-348` already refuses the attach before
  it writes anything when a shown generated path is not on the machine yet.
- **Every consumer of a peer's value is re-keyed once at the artifact level.** The digest moves, so
  the first apply replaces those images. → Bounded to one apply, and the requirement that owns the
  digest already records this as the intended consequence of a widening (`spec.md:782-784`).
- **The index is one more pass over the plan per reading.** → One pass, not one per entry, and the
  reading is outside the perf gate: `perf/eval.nix:34` evaluates `planner.mkPlan` and nothing of
  `operator/` or `image/`.
- **A public export backed by a generated file publishes the whole file record as its read**
  (`lib/resolve.nix:2077-2083`), so the path scan finds it there too. → That is correct and
  deliberate: a public delivered file is a file the unit opens at a host path, and the old walk
  dropped it for the same reason it dropped a secret one.

## Migration Plan

Nothing migrates in the plan: no field is added, no key input changes, and
`fixtures/minimal-typed-edge/plan/backup.json` is expected byte-identical, its one consumer reading
`url` and `quota` rather than a value. What moves is at the artifact level, once: every entry that
declares a read of a peer's deployed generated value publishes a new version digest, so the first
apply after this change stops, detaches and re-attaches those images and writes new flakelet
generations for the flakelet ones. A second apply reports that nothing changed. No machine state is
deleted and no value is rewritten, the values being on the machines already.
