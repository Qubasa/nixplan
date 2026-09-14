## 1. Record the leak before it is closed

- [ ] 1.1 Record what a run's argv holds today: apply a deployment carrying one delivered value
  through `tests/e2e/test_harness.py`'s `Recorder` and assert that the base64 of the value appears in
  `recorder.commands`. Keep the recording as the before half of task 5.2, and verify it by running
  the assertion against the unpatched tree.
- [ ] 1.2 Record the rendered step's residue: render `secrets/backend.nix` over the worked plan
  (`tests/unit/secrets.nix:137-141` is the call), run the rendered `deliver` body against a fetch
  that answers bytes and an `ssh` on `PATH` that exits non-zero, and record that the file `mktemp`
  made is still there and holds the bytes. Verify by reading the file back.

## 2. The channel

- [ ] 2.1 In `cli/remote.py`, change the protocol: `Runner.run(self, cmd: list[str], *, env:
  dict[str, str] | None = None, stdin: bytes | None = None) -> object` and
  `Runner.output(self, cmd: list[str], *, env: dict[str, str] | None = None, stdin: bytes | None =
  None) -> str`. Reword the docstring at `cli/remote.py:58-60` so the claim about rookery's
  `Cluster.run` is about a step that sends no payload. Verify with `mypy --strict` over `cli/`,
  which `checks.treefmt` runs.
- [ ] 2.2 Change `Subprocess.run`, `Subprocess.output` and `Subprocess._completed(self, cmd: list[str],
  env: dict[str, str] | None, stdin: bytes | None) -> subprocess.CompletedProcess[bytes]` to run one
  `subprocess.run(cmd, env=env, input=stdin, check=True, capture_output=True)` in binary mode, and
  decode at one place: `printed(refused: subprocess.CalledProcessError) -> str` and
  `Subprocess.output` both go through one helper that decodes with `errors="replace"`. Verify with a
  throwaway script that `Subprocess().output(["cat"], env={}, stdin=b"\xff\x00")` answers the two
  bytes back and that a command exiting non-zero with undecodable stderr raises `Refused` rather
  than a `UnicodeDecodeError`.
- [ ] 2.3 Change `write_script(file: ValueFile) -> str`: drop the `content` parameter, replace
  `printf %s <base64> | base64 -d > "$tmp"` (`cli/remote.py:322`) with `cat > "$tmp"`, delete
  `encoded` (`:306`) and the `import base64` at `:27`, and rewrite the docstring sentence at
  `:270-273` that says why the bytes were encoded. Verify the script text no longer contains
  `base64` and that `ruff` reports no unused import (`checks.treefmt`).

## 3. The write

- [ ] 3.1 In `cli/apply.py:344-352`, hand `write.content` to the channel rather than to the script:
  `channel.output(remote.ssh_argv(write.address, remote.write_script(write.file), opts=opts,
  user=user), env=env, stdin=write.content)`. `Write.content` keeps its type. Verify the step line
  (`cli/apply.py:339-342`) is unchanged, by comparing the lines one apply prints against the lines
  recorded before the change.
- [ ] 3.2 Give `Nobody.run` and `Nobody.output` (`cli/apply.py:257-263`) the same keyword, taking no
  step with it, and verify `test_a_run_is_asked_what_it_would_do` still reports the dry run's lines
  as equal to the real run's.
- [ ] 3.3 Verify no other caller of the channel needs the keyword: `cli/report.py:220-222,251-299`
  and `cli/remote.py:111-130` send no payload, so each call is unchanged. Verify with `mypy
  --strict`.

## 4. The rendered step

- [ ] 4.1 In `secrets/backend.nix`, move the temporary into `header` (`:82-103`): create it once
  before the `while` loop and install `trap 'rm -f "$tmp"' EXIT INT TERM HUP` on the line after it.
  Verify the rendered text carries the trap before the first `case` branch.
- [ ] 4.2 Change `deliver` (`:91-96`) to truncate the temporary and fetch into it rather than making
  one of its own, keeping the `ssh … < "$tmp"` send and the remote `cat > '$5.new'` exactly as they
  are. Verify against `tests/e2e/generated-secret/deployment/backend.py` that the backend's `get`
  writes to an existing `out` path (the open question in `design.md`); if it does not, spell the
  truncation as an `rm -f` before the fetch instead.
- [ ] 4.3 Verify the `deliver` call sites are byte-equal to the four lines
  `tests/unit/secrets.nix:453-476` compares, so the delivery table of the worked plan does not move.

## 5. The scenarios

- [ ] 5.1 Give every recorder in `tests/e2e/test_harness.py` the new keyword and have none of them
  store the payload: `Recorder` (`:90-102`), `Reporting` (`:500-514`), `Rotating`, `Failing`
  (`:1517-1531`), `Answering`, `Silent`, `Fleet` and `Holding`. Replace `Reporting.output`'s
  `"base64 -d" in cmd[-1]` discriminator (`:510`) with a word of the new script, and change
  `_written` (`:2114-2121`) to pipe the bytes on stdin. Verify the whole file is green:
  `nix build .#checks.x86_64-linux.planner-delivery`.
- [ ] 5.2 Add `test_a_process_table_observed_during_a_value_write` and
  `test_two_values_of_one_length_run_one_argument_vector` to `tests/e2e/test_harness.py`: the first
  asserts no element of any recorded argv holds the value's bytes, their base64 or a digest of them,
  and that the machine's command line is the argv's last element; the second applies one deployment
  twice with two different payloads of one length and asserts the two recorders' `commands` and the
  two step-line lists are equal. Verify the first fails against the tree as it was in task 1.1.
- [ ] 5.3 Add `test_a_value_write_carries_its_bytes_on_the_steps_input_stream`: run
  `remote.Subprocess()` against `["bash", "-c", remote.write_script(file)]` with a payload that is
  not valid UTF-8, and assert the written file holds exactly those bytes, that the answer is the one
  word the step reports, and that a second run over the same bytes answers `unchanged`. Verify it
  fails against the old `write_script`, whose signature takes the content.
- [ ] 5.4 Add `test_a_dry_run_hands_no_payload_to_the_channel_it_substitutes`: a dry run of a
  deployment carrying a delivered value takes no step and prints the real run's lines. Verify beside
  the existing `test_a_run_is_asked_what_it_would_do`, which stays as it is.
- [ ] 5.5 Add `test_a_write_that_fails_after_its_bytes_have_arrived` and
  `test_a_repeated_write_finishes_what_a_failed_one_did_not`: run the write script locally with the
  payload on stdin and the ownership step made to fail, assert the directory holds only the file the
  first write left, that the previous bytes survive, and that a following successful run of the same
  script reports the bytes moved and lands the recorded mode and ownership. Verify both against
  `test_an_interrupted_write` (`:2158-2176`) and `test_an_account_the_machine_does_not_have`
  (`:2179-2200`), which stay green unchanged apart from the piped payload.
- [ ] 5.6 Add `testTheRenderedStepRemovesThePlaintextItFetched` to `tests/unit/secrets.nix`:
  the rendered step carries the trap, the trap names the temporary, it is installed before the first
  fetch, it covers `EXIT INT TERM HUP`, and the script makes exactly one temporary. Verify it fails
  against the unpatched `secrets/backend.nix`.
- [ ] 5.7 Add `test_a_delivery_the_machine_refuses_leaves_no_plaintext` and
  `test_a_completed_delivery_leaves_no_plaintext` to
  `tests/e2e/generated-secret/test_generated_secret.py`: give the deploy invocation
  (`:330-337`, whose env is already a parameter) a `TMPDIR` of the run's own empty directory, and
  assert after it that no file under that directory holds any byte of a delivered value; run the
  rendered step a second time with an `ssh` on `PATH` that refuses and assert the same. Verify both
  fail against the unpatched `secrets/backend.nix` and that the folder still skips cleanly where the
  external tool cannot be resolved.

## 6. Registration and documents

- [ ] 6.1 Move `keep-a-secret-out-of-a-process-table/specs/operator/apply-command/spec.md` and
  `.../specs/realiser/secrets-configuration/spec.md` from `excused` to `accountable` in
  `tests/unit/coverage.nix` - the excuse says "an unimplemented change" and expires the moment a
  task here is ticked - and verify every heading finds its derived test:
  `nix eval --json .#debug.failuresBySuite.coverage` is `[]`.
- [ ] 6.2 Update `docs/tooling.md`: the `secrets` suite row (`:99`) from 21 to 22 and the total
  (`:112-113`) from 507 to 508. The pytest scenarios move neither figure, both being counts of
  nix-unit test attributes. Verify `coverage.testASuiteGainsATest` is green.
- [ ] 6.3 Update `docs/operator.md`: beside the paragraph on what the write decides (`:509-527`), say
  that the bytes travel on the step's input stream and that the argv of a write is a function of the
  plan, so a process table on either host shows the path and never the bytes. Verify
  `nix build .#checks.x86_64-linux.treefmt` passes, vale included.
- [ ] 6.4 Update `docs/secrets.md:120-124`: replace the claim about a window with what the step does
  with the file it fetched - one temporary, removed under a trap on every exit path, `set -eu` being
  why a trailing removal is not the fix. Verify `checks.treefmt`.
- [ ] 6.5 Record both rules in `CLAUDE.md`: under "The operator's command", beside the existing
  sentence about a value write never printing the bytes, that the bytes travel on the step's input
  stream and enter no argv on either host, and that the recorder records the argv and never the
  payload; under "Realisers", beside the secrets reading's bullet, that the rendered step keeps one
  temporary and removes it under a trap because `set -eu` makes a trailing removal unreachable.
  Verify `checks.treefmt`.
- [ ] 6.6 `docs/diagnostics.md` is not edited, and the task list says so rather than leaving a reader
  to check: this change produces no diagnostics row and no refusal identifier, both defects being in
  layers that run after a plan is applicable. Verify the document is byte-equal and that
  `diagnostics.testTheLibraryGainsARow` and
  `diagnostics.testADocumentTabulatesARowTheTreeCannotProduce` report the identifier sets they
  reported before.

## 7. Verification

- [ ] 7.1 `nix build .#checks.x86_64-linux.planner-delivery` - the harness, including the six new
  scenarios and every recorder that gained the keyword.
- [ ] 7.2 `nix build .#checks.x86_64-linux.planner-tests` - the nix-unit suites, including
  `secrets` with its new scenario and `coverage` with the two spec files moved into `accountable`.
  The golden plan and `fixtures/minimal-typed-edge/plan/diagnostics.txt` must be byte-equal: nothing
  under `lib/` changed, so nothing regenerates. Should one move,
  `nix eval --json .#debug.worked.plan | jq -S .` is the regeneration and the reason belongs in this
  task before it is run.
- [ ] 7.3 `nix build .#checks.x86_64-linux.treefmt` - `mypy --strict` and `ruff` govern `cli/`
  (`ruff.toml`'s `src`, `treefmt.nix`'s `programs.mypy.directories`), and vale governs every
  document edited in group 6.
- [ ] 7.4 `nix run .#planner-e2e generated-secret` - the rendered step, run for real against the
  external tool, with the two new scenarios reading its temporary directory.
- [ ] 7.5 `nix run .#planner-e2e secret-delivery` - a value delivered over the new channel to three
  machines: the bytes, the mode and the owner on each machine of the delivery set, the rotation, and
  the reboot phase, none of which changes.
- [ ] 7.6 `nix build .#checks.x86_64-linux.planner-perf` is deliberately not part of this change.
  No file under `lib/` is edited, the perf harness evaluates no file of `cli/` and renders no
  delivery step, so the nine budgets are measured over an unchanged evaluation. Verify by confirming
  the change touches only `cli/`, `secrets/backend.nix`, `tests/`, `docs/` and `CLAUDE.md`.
