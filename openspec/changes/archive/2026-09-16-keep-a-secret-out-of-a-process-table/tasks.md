## 1. Record the leak before it is closed

- [x] 1.1 Record what a run's argv holds today: apply a deployment carrying one delivered value
  through `tests/e2e/test_harness.py`'s `Recorder` and assert that the base64 of the value appears in
  `recorder.commands`. Keep the recording as the before half of task 5.2, and verify it by running
  the assertion against the unpatched tree.
  Recorded against `b7dd7e1` extracted to a scratch tree: a payload of `s3cret-payload` put
  `czNjcmV0LXBheWxvYWQ=` into the last element of the recorded ssh argv, as
  `printf %s czNjcmV0LXBheWxvYWQ= | base64 -d > "$tmp"`. The same run's property as task 5.2
  states it - no recorded argv holds the base64 - fails there with
  `assert b'czNjcmV0LXBheWxvYWQ=' not in b'set -eu; umask 077; ...'`.
- [x] 1.2 Record the rendered step's residue: render `secrets/backend.nix` over the worked plan
  (`tests/unit/secrets.nix:137-141` is the call), run the rendered `deliver` body against a fetch
  that answers bytes and an `ssh` on `PATH` that exits non-zero, and record that the file `mktemp`
  made is still there and holds the bytes. Verify by reading the file back.
  Rendered the `b7dd7e1` copy of `backend.nix` over a one-value plan of the shape
  `tests/unit/secrets.nix`'s `synthetic` builds, with `get` a script writing
  `PLAINTEXT-SECRET-BYTES` and an `ssh` on `PATH` exiting 255. The step exited 255 and left
  `$TMPDIR/tmp.1KW6wXhdUU` holding `PLAINTEXT-SECRET-BYTES`. The same run of the patched render
  exits 255 and leaves the directory empty. The plan is a hand-written one rather than the suite's
  `worked.plan`, because the suite's plan is a `let` binding of a nix-unit file and no output
  exposes it; the rendered `deliver` body is a function of neither.

## 2. The channel

- [x] 2.1 In `cli/remote.py`, change the protocol: `Runner.run(self, cmd: list[str], *, env:
  dict[str, str] | None = None, stdin: bytes | None = None) -> object` and
  `Runner.output(self, cmd: list[str], *, env: dict[str, str] | None = None, stdin: bytes | None =
  None) -> str`. Reword the docstring at `cli/remote.py:58-60` so the claim about rookery's
  `Cluster.run` is about a step that sends no payload. Verify with `mypy --strict` over `cli/`,
  which `checks.treefmt` runs.
  `cli/remote.py:54-76`. The docstring now says `run` is the shape `Cluster.run` has for a step that
  sends no payload. `nix build .#checks.x86_64-linux.treefmt` exits 0.
- [x] 2.2 Change `Subprocess.run`, `Subprocess.output` and `Subprocess._completed(self, cmd: list[str],
  env: dict[str, str] | None, stdin: bytes | None) -> subprocess.CompletedProcess[bytes]` to run one
  `subprocess.run(cmd, env=env, input=stdin, check=True, capture_output=True)` in binary mode, and
  decode at one place: `printed(refused: subprocess.CalledProcessError) -> str` and
  `Subprocess.output` both go through one helper that decodes with `errors="replace"`. Verify with a
  throwaway script that `Subprocess().output(["cat"], env=…, stdin=b"\xff\x00")` answers those bytes
  decoded and that a command exiting non-zero with undecodable stderr raises `Refused` rather
  than a `UnicodeDecodeError`.
  `decoded` in `cli/remote.py:199-209` is the one place. The throwaway answered
  `'\ufffd\x00'` for `stdin=b"\xff\x00"` through `cat`, and `sh -c "printf 'bad \377\n' >&2; exit 9"`
  raised `Refused` with status 9 and `said` of `'bad \ufffd'`, no `UnicodeDecodeError`.
  The verification as written asked for "the two bytes back", which this design cannot answer and
  should not: `output` is the text half of a channel that is bytes in and text out, decoded once
  with `errors="replace"`, so `b"\xff"` comes back as the replacement character. The wording above
  is corrected to that, and the byte-for-byte round trip is asserted where the bytes land instead -
  the same throwaway wrote `b"\xff\x00"` through `sh -c 'cat > …'` and read it back unchanged,
  which is what scenario 5.3 holds permanently.
- [x] 2.3 Change `write_script(file: ValueFile) -> str`: drop the `content` parameter, replace
  `printf %s <base64> | base64 -d > "$tmp"` (`cli/remote.py:322`) with `cat > "$tmp"`, delete
  `encoded` (`:306`) and the `import base64` at `:27`, and rewrite the docstring sentence at
  `:270-273` that says why the bytes were encoded. Verify the script text no longer contains
  `base64` and that `ruff` reports no unused import (`checks.treefmt`).
  `grep base64 cli/remote.py` is empty, and `checks.treefmt` exits 0.

## 3. The write

- [x] 3.1 In `cli/apply.py:344-352`, hand `write.content` to the channel rather than to the script:
  `channel.output(remote.ssh_argv(write.address, remote.write_script(write.file), opts=opts,
  user=user), env=env, stdin=write.content)`. `Write.content` keeps its type. Verify the step line
  (`cli/apply.py:339-342`) is unchanged, by comparing the lines one apply prints against the lines
  recorded before the change.
  `cli/apply.py:352-361`. One deployment applied through `Reporting` on the `b7dd7e1` tree and on
  this one printed identical lines apart from the run's own scratch directory in the `copy` line:
  `value issuer:vars/session token -> root@10.0.0.10:/run/vars/issuer/session/token (root:root
  0400)` / `  unchanged` / `activate …`.
- [x] 3.2 Give `Nobody.run` and `Nobody.output` (`cli/apply.py:257-263`) the same keyword, taking no
  step with it, and verify `test_a_run_is_asked_what_it_would_do` still reports the dry run's lines
  as equal to the real run's.
  `cli/apply.py:261-271`. That scenario is among the 89 that pass in `planner-delivery`, beside the
  new `test_a_dry_run_hands_no_payload_to_the_channel_it_substitutes` of task 5.4.
- [x] 3.3 Verify no other caller of the channel needs the keyword: `cli/report.py:220-222,251-299`
  and `cli/remote.py:111-130` send no payload, so each call is unchanged. Verify with `mypy
  --strict`.
  No file under `cli/` other than `apply.py` and `remote.py` is touched by this change, and
  `checks.treefmt`, which runs `mypy --strict` over `cli/`, exits 0.

## 4. The rendered step

- [x] 4.1 In `secrets/backend.nix`, move the temporary into `header` (`:82-103`): create it once
  before the `while` loop and install `trap 'rm -f "$tmp"' EXIT INT TERM HUP` on the line after it.
  Verify the rendered text carries the trap before the first `case` branch.
  `secrets/backend.nix:94-95`. The rendered text puts `tmp=$(mktemp)` and the trap above
  `deliver() {`, which is itself above the `while`/`case`.
- [x] 4.2 Change `deliver` (`:91-96`) to truncate the temporary and fetch into it rather than making
  one of its own, keeping the `ssh … < "$tmp"` send and the remote `cat > '$5.new'` exactly as they
  are. Verify against `tests/e2e/generated-secret/deployment/backend.py` that the backend's `get`
  writes to an existing `out` path (the open question in `design.md`); if it does not, spell the
  truncation as an `rm -f` before the fetch instead.
  `: > "$tmp"` is the truncation. The open question is answered yes: that backend's `decrypt`
  (`backend.py:106-119`) runs `age --decrypt --identity … --output <out>`, and `age` overwrites an
  existing output path - measured directly, `age --output` onto a file created by `: >` wrote the
  plaintext and exited 0. The `rm -f` spelling is therefore not needed, and task 7.4 runs the real
  tool through this path.
- [x] 4.3 Verify the `deliver` call sites are byte-equal to the four lines
  `tests/unit/secrets.nix:453-476` compares, so the delivery table of the worked plan does not move.
  `testTheRenderedStepTargetsTheDeliverySet` is unedited and green in `planner-tests`.

## 5. The scenarios

- [x] 5.1 Give every recorder in `tests/e2e/test_harness.py` the new keyword and have none of them
  store the payload: `Recorder` (`:90-102`), `Reporting` (`:500-514`), `Rotating`, `Failing`
  (`:1517-1531`), `Answering`, `Silent`, `Fleet` and `Holding`. Replace `Reporting.output`'s
  `"base64 -d" in cmd[-1]` discriminator (`:510`) with a word of the new script, and change
  `_written` (`:2114-2121`) to pipe the bytes on stdin. Verify the whole file is green:
  `nix build .#checks.x86_64-linux.planner-delivery`.
  All ten `run`/`output` definitions in the file carry `stdin: bytes | None = None` and none
  records it; the discriminator is now `'cat > "$tmp"' in cmd[-1]`. The check exits 0 with
  89 passed, 1 skipped, the skip being the locked flakelet source that is unresolvable here.
- [x] 5.2 Add `test_a_process_table_observed_during_a_value_write` and
  `test_two_values_of_one_length_run_one_argument_vector` to `tests/e2e/test_harness.py`: the first
  asserts no element of any recorded argv holds the value's bytes, their base64 or a digest of them,
  and that the machine's command line is the argv's last element; the second applies one deployment
  twice with two different payloads of one length and asserts the two recorders' `commands` and the
  two step-line lists are equal. Verify the first fails against the tree as it was in task 1.1.
  Both present (`test_harness.py:692` and `:725`). `_leaks` covers the bytes, base64, base32, hex,
  a sha256 digest and that digest in base64. Verified failing on `b7dd7e1` - see task 1.1.
- [x] 5.3 Add `test_a_value_write_carries_its_bytes_on_the_steps_input_stream`: run
  `remote.Subprocess()` against `["bash", "-c", remote.write_script(file)]` with a payload that is
  not valid UTF-8, and assert the written file holds exactly those bytes, that the answer is the one
  word the step reports, and that a second run over the same bytes answers `unchanged`. Verify it
  fails against the old `write_script`, whose signature takes the content.
  `test_harness.py:2354`. The payload is `b"\x00\xfe not utf-8 \xff\x80"`, the answers are
  `changed` then `unchanged`, and the tail of it asserts a refusal whose stderr is undecodable is
  reported rather than raised on. Against `b7dd7e1`'s `cli/remote.py` the same call answers
  `TypeError: write_script() missing 1 required positional argument: 'content'`.
- [x] 5.4 Add `test_a_dry_run_hands_no_payload_to_the_channel_it_substitutes`: a dry run of a
  deployment carrying a delivered value takes no step and prints the real run's lines. Verify beside
  the existing `test_a_run_is_asked_what_it_would_do`, which stays as it is.
  `test_harness.py:656`, green beside the untouched `test_a_run_is_asked_what_it_would_do`.
- [x] 5.5 Add `test_a_write_that_fails_after_its_bytes_have_arrived` and
  `test_a_repeated_write_finishes_what_a_failed_one_did_not`: run the write script locally with the
  payload on stdin and the ownership step made to fail, assert the directory holds only the file the
  first write left, that the previous bytes survive, and that a following successful run of the same
  script reports the bytes moved and lands the recorded mode and ownership. Verify both against
  `test_an_interrupted_write` (`:2158-2176`) and `test_an_account_the_machine_does_not_have`
  (`:2179-2200`), which stay green unchanged apart from the piped payload.
  `test_harness.py:2383` and `:2414`. The two older scenarios are unchanged apart from the payload
  moving to `input=`, and all four pass in `planner-delivery`.
- [x] 5.6 Add `testTheRenderedStepRemovesThePlaintextItFetched` to `tests/unit/secrets.nix`:
  the rendered step carries the trap, the trap names the temporary, it is installed before the first
  fetch, it covers `EXIT INT TERM HUP`, and the script makes exactly one temporary. Verify it fails
  against the unpatched `secrets/backend.nix`.
  `tests/unit/secrets.nix:521`. Read against the `b7dd7e1` render, its fields answer
  `trap = [ ]` against an expected one-element list and
  `eachFetchTruncatesTheOneTemporary = false`, and `theTrapIsBeforeTheFirstFetch` compares a `null`
  index against an integer, so the scenario fails there three ways. Verified by reading the
  rendered text, a pure evaluation being unable to run a shell.
- [x] 5.7 Add `test_a_delivery_the_machine_refuses_leaves_no_plaintext` and
  `test_a_completed_delivery_leaves_no_plaintext` to
  `tests/e2e/generated-secret/test_generated_secret.py`: give the deploy invocation
  (`:330-337`, whose env is already a parameter) a `TMPDIR` of the run's own empty directory, and
  assert after it that no file under that directory holds any byte of a delivered value; run the
  rendered step a second time with an `ssh` on `PATH` that refuses and assert the same. Verify both
  fail against the unpatched `secrets/backend.nix` and that the folder still skips cleanly where the
  external tool cannot be resolved.
  `test_generated_secret.py:567` and `:583`. The refusing send is the operator's own `ssh` against
  an address that resolves for nobody, with `BatchMode` and `ConnectTimeout=5`, rather than a
  program standing in for one. Both verified red against `b7dd7e1`'s `secrets/backend.nix`
  restored into this tree for one run: `2 failed, 7 passed`, each failure naming the temporary that
  held the delivered token in plaintext (`deploy-tmp/tmp.JYXrJrFSzg` and `refused/tmp.bECqKxBumK`,
  both holding `fb208959b9a6ef5e3e2c0d9f13615f389f9ead1695cc9945239807f926051e0b`). The tree was
  restored immediately after. The skip path was not exercised: the external tool resolved here, so
  every run of the folder was a real one.

## 6. Registration and documents

- [x] 6.1 Move `keep-a-secret-out-of-a-process-table/specs/operator/apply-command/spec.md` and
  `.../specs/realiser/secrets-configuration/spec.md` from `excused` to `accountable` in
  `tests/unit/coverage.nix` - the excuse says "an unimplemented change" and expires the moment a
  task here is ticked - and verify every heading finds its derived test:
  `nix eval --json .#debug.failuresBySuite.coverage` is `[]`.
  Moved (`tests/unit/coverage.nix:208-209`), and that evaluation answers `[]`. Nine scenario
  headings, nine derived tests: six under pytest in `tests/e2e/test_harness.py`, two under pytest
  in `tests/e2e/generated-secret/test_generated_secret.py`, one nix-unit attribute in
  `tests/unit/secrets.nix`.
- [x] 6.2 Update `docs/tooling.md`: the `secrets` suite row (`:99`) from 21 to 22 and the total
  (`:112-113`) from 507 to 508. The pytest scenarios move neither figure, both being counts of
  nix-unit test attributes. Verify `coverage.testASuiteGainsATest` is green.
  Both moved, and the coverage suite reports no failure. One figure beyond the task moved too:
  the prose count of `planner-delivery` at `:140,146` went from 84 to 90, which is what the check
  now runs (89 passed plus the one flakelet skip). Nothing compares that number mechanically, and
  leaving it at 84 would have made the document wrong about the check the same change grew.
- [x] 6.3 Update `docs/operator.md`: beside the paragraph on what the write decides (`:509-527`), say
  that the bytes travel on the step's input stream and that the argv of a write is a function of the
  plan, so a process table on either host shows the path and never the bytes. Verify
  `nix build .#checks.x86_64-linux.treefmt` passes, vale included.
  `docs/operator.md:529-534`, and the check exits 0.
- [x] 6.4 Update `docs/secrets.md:120-124`: replace the claim about a window with what the step does
  with the file it fetched - one temporary, removed under a trap on every exit path, `set -eu` being
  why a trailing removal is not the fix. Verify `checks.treefmt`.
  `docs/secrets.md:120-132`, and the check exits 0.
- [x] 6.5 Record both rules in `CLAUDE.md`: under "The operator's command", beside the existing
  sentence about a value write never printing the bytes, that the bytes travel on the step's input
  stream and enter no argv on either host, and that the recorder records the argv and never the
  payload; under "Realisers", beside the secrets reading's bullet, that the rendered step keeps one
  temporary and removes it under a trap because `set -eu` makes a trailing removal unreachable.
  Verify `checks.treefmt`.
  `CLAUDE.md:419-423` under Realisers and `:537-544` under The operator's command. The check exits
  0, and `CLAUDE.md` is one of the documents vale reads.
- [x] 6.6 `docs/diagnostics.md` is not edited, and the task list says so rather than leaving a reader
  to check: this change produces no diagnostics row and no refusal identifier, both defects being in
  layers that run after a plan is applicable. Verify the document is byte-equal and that
  `diagnostics.testTheLibraryGainsARow` and
  `diagnostics.testADocumentTabulatesARowTheTreeCannotProduce` report the identifier sets they
  reported before.
  `git diff b7dd7e1..HEAD --name-only` does not name it, and
  `nix eval --json .#debug.failuresBySuite.diagnostics` is `[]`, so both of those attributes agree
  with the tree's identifier sets.

## 7. Verification

- [x] 7.1 `nix build .#checks.x86_64-linux.planner-delivery` - the harness, including the six new
  scenarios and every recorder that gained the keyword.
  Exit 0. `89 passed, 1 skipped in 0.56s`; the skip is the locked flakelet source, unresolvable
  here and unrelated.
- [x] 7.2 `nix build .#checks.x86_64-linux.planner-tests` - the nix-unit suites, including
  `secrets` with its new scenario and `coverage` with the two spec files moved into `accountable`.
  The golden plan and `fixtures/minimal-typed-edge/plan/diagnostics.txt` must be byte-equal: nothing
  under `lib/` changed, so nothing regenerates. Should one move,
  `nix eval --json .#debug.worked.plan | jq -S .` is the regeneration and the reason belongs in this
  task before it is run.
  Exit 0. No golden moved: `fixtures/` is not in the change's file list, so no regeneration was run
  and none was needed.
- [x] 7.3 `nix build .#checks.x86_64-linux.treefmt` - `mypy --strict` and `ruff` govern `cli/`
  (`ruff.toml`'s `src`, `treefmt.nix`'s `programs.mypy.directories`), and vale governs every
  document edited in group 6.
  Exit 0. Two runs in between answered the `INTERNAL ERROR` mypy 2.1.0 makes intermittently in the
  sandbox over the `e2e-folders` root, which `CLAUDE.md` already records; the same arguments and
  the same config file outside the sandbox answer `Success: no issues found in 13 source files`,
  and the next build of the same derivation exits 0.
- [x] 7.4 `nix run .#planner-e2e generated-secret` - the rendered step, run for real against the
  external tool, with the two new scenarios reading its temporary directory.
  `9 passed in 27.74s`. The external tool resolved, so nothing skipped and the rendered step ran
  against the real `age` store backend.
- [x] 7.5 `nix run .#planner-e2e secret-delivery` - a value delivered over the new channel to three
  machines: the bytes, the mode and the owner on each machine of the delivery set, the rotation, and
  the reboot phase, none of which changes.
  `19 passed in 97.88s`.
- [x] 7.6 `nix build .#checks.x86_64-linux.planner-perf` is deliberately not part of this change.
  No file under `lib/` is edited, the perf harness evaluates no file of `cli/` and renders no
  delivery step, so the nine budgets are measured over an unchanged evaluation. Verify by confirming
  the change touches only `cli/`, `secrets/backend.nix`, `tests/`, `docs/` and `CLAUDE.md`.
  `git diff b7dd7e1..HEAD --name-only` is exactly `CLAUDE.md`, `cli/apply.py`, `cli/remote.py`,
  `docs/operator.md`, `docs/secrets.md`, `docs/tooling.md`, `secrets/backend.nix`,
  `tests/e2e/generated-secret/test_generated_secret.py`, `tests/e2e/test_harness.py`,
  `tests/unit/coverage.nix` and `tests/unit/secrets.nix`, plus this task list. The perf check was
  not run.
