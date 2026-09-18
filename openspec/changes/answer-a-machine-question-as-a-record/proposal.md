## Why

The command computes a structured verdict about every machine and then destroys it at the
boundary. `report.status` asks three questions per machine - one per entry, one per value, one for
what the machine holds that the build names no entry for - and every answer is reduced to a
sentence before it leaves the function: `Report` carries `lines: tuple[str, ...]` and `unasked` and
nothing else (`cli/report.py:81-86`), and each line is f-stringed at the site that computed the
verdict (`cli/report.py:144`, `:157-160`, `:167`). The verdict itself is real data. `_answered`
tells five conditions apart by an exit status (`cli/report.py:364-375`, against `UNDIALLED` and
`UNREALISED` at `:77-78` and `remote.UNREACHABLE` and `remote.MISSING` at `cli/remote.py:59-60`);
`_read_status` reads a generation, a locked url, a unit comparison and a last error out of the
endpoint's own JSON (`cli/report.py:422-436`, `:471-486`); `_read_attachment` reads an attachment
state, selects the identity of the entry's own image out of the listing, compares it against
`entry.digest` and names the configuration paths that disagree (`cli/report.py:489-521`,
`:524-526`, `:529-548`). Two of those facts are already records inside `remote` - `Attachment`
(`cli/remote.py:851-858`, read by `attachment_of` at `:860-890`) and `Holding`
(`cli/remote.py:920-941`) - and both are stringified back into prose before a caller sees them,
`Holding` by a `sentence` method the record carries itself (`cli/remote.py:938-940`), called from
the report (`cli/report.py:167`) and from the apply (`cli/apply.py:205-215`).

The consumer of that data is not hypothetical. The pure half of the command is published for
import on purpose: `packages.planner-src` (`cli/flake-module.nix:45`) is exported as
`PLANNER_CLI_SRC` (`flake-module.nix:201-207`), the end-to-end runner puts it on `PYTHONPATH`
(`tests/e2e/runner.py:26-29`, `:355`), and the harness and a folder's own tests already
`import report` and `import apply` (`tests/e2e/test_harness.py:34-44`,
`tests/e2e/wired-pair/test_wired_pair.py:87-88`). What every one of those importers gets today is a
tuple of sentences, so every assertion about a verdict is a string comparison against prose
(`tests/e2e/test_harness.py:2338-2341`, `:2487-2488`;
`tests/e2e/portable-image/test_portable_image.py:690`, `:878-881`, `:1058-1059`). A browser view of
the deployment or a tool that decides anything from a report has one option: grep the sentence a
human reads.

The same loss happens once in the build record, in the one path designed for programs rather than
for a reader. `lib/diagnostics.nix:45-63` requires six fields on every row - `id`, `subject`,
`severity`, `message`, `evidence`, `resolution` - and `operator/default.nix:319-329` writes all six
into `diagnostics.json` beside the rendered `diagnostics.txt`. `cli/manifest.py:664-679` decodes
four of them into a `Diagnostic` carrying four fields (`cli/manifest.py:123-131`), dropping
`evidence` and `resolution`: exactly the two an author needs, the one saying what was observed and
the one naming the declaration to edit.

## What Changes

- `report.status` returns one record per question it asked - per entry, per value on a machine, per
  holding - carrying the fields the verdict is made of rather than the sentence it was rendered
  into. The field set is derived from what `_answered`, `_read_status` and `_read_attachment`
  already compute and nothing is invented: the plan key, the machine, the realiser, whether the
  machine answered at all and which of the four non-answers it was, what the machine printed, the
  identity the machine holds and the identity this build published, the unit comparison a flakelet
  endpoint permits, the attachment state the machine's own tool printed, the configuration paths
  whose bytes disagree, and the last error the endpoint recorded.
- The sentences an operator reads stay byte-identical, and that is the compatibility contract.
  Every line becomes the output of one rendering function over one record, so `planner status`
  output does not move and the lines `docs/operator.md:515-519`, `:521-528`, `:541-547`, `:573-578`
  and `:607-609` document stay true. The proof is the end-to-end folders, which already assert
  those strings.
- `Holding` and `Attachment` stop being stringified inside `report` and `apply`. The record escapes
  and the caller renders: `Holding.sentence` (`cli/remote.py:938-940`) moves out of the record into
  the one renderer, and `apply.holding_lines` (`cli/apply.py:205-215`) calls that renderer rather
  than the record's own method, so the one line a report and an apply both print stays one string
  built in one place.
- The four answers a report has to keep apart - an entry the endpoint does not register, a machine
  carrying no endpoint, a machine that answers nothing, and an entry whose machine declares no
  address (`openspec/specs/operator/machine-report/spec.md:41-48`, `:149-166`) - become four
  distinguishable values of one field of the record, plus the fifth condition that is the command's
  own refusal. A consumer reads a value; it never matches a word out of a sentence.
- Exit status is unchanged. `unasked` stays the only thing `planner status` exits non-zero on
  (`cli/planner.py:69-82`), and a record that carries staleness as a field is not a licence to
  change that: staleness is a line and never an exit status, and putting a machine right is the
  applying command's work.
- `cli/manifest.py`'s diagnostics decoding carries all six fields. The fix is in the decode and not
  in a second reader of `diagnostics.json`: `_rows` (`cli/manifest.py:664-679`) is the only decode
  of that file, `Deployment.rendered` already falls back to composing lines out of the decoded rows
  where the build wrote no table (`cli/manifest.py:206-210`), and a second reader would be two
  decodes of one file that can disagree while the first still drops the two fields.

## Capabilities

### New Capabilities

None.

### Modified Capabilities

- `operator/machine-report`: the answer a report gives per entry becomes a record and the line
  becomes a rendering of it; the four answers become four values of one field rather than four
  spellings in prose; absence stays produced by one fact and staleness stays a line and never an
  exit status, now stated over a field. One requirement is added for the record itself, its field
  set and the rendering contract that keeps every documented sentence byte-identical.
- `operator/deployment-build`: the record a build publishes is read by every command with all six
  fields of every diagnostics row, because the row the planner produced carries six and the one
  path designed for programs is the one that was dropping two.

## Impact

- `cli/report.py`: the records `status` returns, the rendering function, and the readings that stop
  f-stringing their verdicts (`:144`, `:157-160`, `:167`, `:364-375`, `:422-436`, `:471-486`,
  `:489-521`, `:524-526`).
- `cli/remote.py`: `Holding.sentence` leaves the record (`:938-940`); `Attachment` and `Holding`
  are what the report's records carry.
- `cli/apply.py`: `holding_lines` renders the record through the one renderer (`:205-215`).
- `cli/manifest.py`: `Diagnostic` carries `evidence` and `resolution` (`:123-131`) and `_rows`
  decodes them (`:664-679`).
- `docs/operator.md`: the documented lines are restated as a rendering of the record, and the
  record's fields are documented beside them.
- `tests/e2e/test_harness.py`: the record's own cases, beside the string assertions that stay as
  the byte-identity proof.
- No file under `lib/**` is touched: no plan field, no row, no registry key and no key input moves,
  so nothing `perf/eval.nix` evaluates changes.
- The seams with the other four changes of this set are in `openspec/changes/INTEGRATION.md`; this
  change owns the record and the two restored diagnostics fields, and every other change of the set
  consumes them rather than defining a second answer.
