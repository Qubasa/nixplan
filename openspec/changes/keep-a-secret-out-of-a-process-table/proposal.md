## Why

Two paths deliver a generated value, and both of them put its plaintext somewhere the deployment
never admitted it.

**The bytes of a delivered value are in an argument vector, on both hosts.** `cli/remote.py:306`
base64-encodes the content and `cli/remote.py:322` embeds the result as a literal of the script
string: `printf %s {shlex.quote(encoded)} | base64 -d > "$tmp"`. That script is the last element of
the ssh argv (`cli/remote.py:264`), and `cli/remote.py:84-90` runs the argv through
`subprocess.run(cmd, …)` with no shell, so it is a real `execve` argument vector. It is called for
exactly this at `cli/apply.py:344-352`, over the `Write.content` bytes `cli/apply.py:125` read out
of the value source. On a stock Linux workstation `/proc/<pid>/cmdline` is world-readable, so every
unprivileged local account, every process-accounting or eBPF collector and every audit log sees
every secret of every apply; on the far side sshd hands the script to the login shell as one word of
*its* argv, so the same bytes are in the machine's process table for the length of the write.

The rule is already the repository's, and it is held on one path only. `cli/remote.py:144-147` says
of a refusal that "the argv is no part of the message: a value write carries the bytes of a secret",
which `CLAUDE.md` restates as "never a traceback and never the argv". `docs/operator.md:509-511`
argues that a store object is the one property a generated secret cannot have. And the requirement
this violates is written down: `deliver-a-secret-without-exposing-it`'s "The bytes of a generated
value come from outside the plan" already says the bytes "SHALL reach a machine as the input of the
remote command that writes them, and SHALL NOT appear in the argument vector of any process on
either host". Task 4.5 of that change, which would have written the test, is unticked. So this is a
defect against a stated requirement rather than a new policy, and what is missing beside the fix is
an observable property a test can fail on.

The correct shape exists in this tree, for this job. `secrets/backend.nix:95` sends the bytes on
standard input and the remote command is `cat > '$5.new'`. `cli/remote.py:270-273`'s own docstring
names the seam that caused the leak: "The bytes travel base64-encoded because a runner runs an argv
rather than a shell."

**The rendered delivery step leaves every secret's plaintext on the operator's host, permanently.**
`secrets/backend.nix:91-96`: `deliver()` makes a temporary with `mktemp`, has the store backend's
own `get` write the decrypted bytes into it, pipes it over ssh, and never removes it. There is no
`rm` between the ssh at `:95` and the closing brace at `:96`, and `header` (`:82-103`) installs no
trap. `set -eu` at `:86` is why a trailing removal would not have been enough either: a refused ssh
exits the function and the script, so the line after it is not reached. Every other site in this
tree that makes a temporary gets rid of it - `cli/remote.py:320` under a trap,
`tests/e2e/shared-postgres/deployment/init.sh:12` under a trap, `image/default.nix:384-396` with a
trailing removal its own guard keeps reachable.

`docs/secrets.md:120-124` describes this step as leaving "no window in which the bytes sit wider
than the deployment stated", and accounts only for the far side. The host-side residue is not a
window: `mktemp` creates the file `0600`, so the mode is not the defect - permanence is. One
plaintext file accumulates per file per recipient machine, a rotation adds a new one beside the old
one, and they sit in `$TMPDIR` until something else removes them, which in this tree is nothing.

## What Changes

- **A value write carries its bytes on the step's input stream.** `Runner` gains an optional payload
  that `Subprocess` hands to `subprocess.run(input=…)`; the argv keeps the script, which is built
  from the plan alone, and the script reads the bytes with `cat` instead of decoding a literal.
  `write_script` loses its `content` argument, `cli/remote.py` loses its `base64` import, and the
  argv of a write becomes a function of the path, the mode and the owner the plan records - all
  three of which the step line already prints (`cli/apply.py:339-342`).
- **The channel carries bytes in and text out.** A secret is arbitrary bytes, so the payload cannot
  go through `text=True`; the one `subprocess.run` runs in binary mode and what a machine said is
  decoded at one place, replacing undecodable bytes rather than raising on them.
- **The observable property is stated and tested.** No element of any argv a run hands its channel
  holds a byte of a value, an encoding of one or a digest of one; two runs delivering different
  bytes of one length run identical argvs. The recorder the harness substitutes for a process table
  records the argv and never the payload: a harness that recorded the secret would have moved the
  leak rather than closed it.
- **None of the write's other guarantees move.** The `0600` temporary created before the first byte,
  ownership then mode then the atomic replace under a trap, the one word (`changed` or `unchanged`)
  the step reports, the `0711` parents, and `--dry-run` remaining a substitution of the channel and
  nothing else.
- **The rendered delivery step removes its plaintext on every exit path.** One temporary for the
  whole script, created before the first fetch, removed by a trap that covers a normal exit, the
  `set -eu` exit a refused ssh causes, and an interrupt.
- **Nothing else.** No plan field, no diagnostics row, no new refusal, no change under `lib/`. The
  `0755` staging directory of `image/default.nix:191,324` is not this change: it belongs to
  `refuse-a-value-a-unit-file-cannot-carry`, and the two must not both edit those lines.

## Capabilities

### New Capabilities

<!-- none: both halves belong to capabilities that exist -->

### Modified Capabilities

- `operator/apply-command`: the argument vector of every step is a function of the plan, a value
  write carries its bytes on the step's input stream, and the guarantees the write already made are
  unchanged by the new channel.
- `realiser/secrets-configuration`: the rendered delivery step leaves no plaintext on the host that
  ran it, including where it fails part way, and holds that under `set -eu`.

## Impact

- `cli/remote.py`: `Runner.run` and `Runner.output` gain a keyword-only `stdin: bytes | None = None`;
  `Subprocess.run`, `Subprocess.output` and `Subprocess._completed` pass it to `subprocess.run`;
  `printed` decodes what a machine said; `write_script(file)` drops `content`; `import base64` goes.
- `cli/apply.py`: the value write hands `write.content` to the channel rather than to
  `write_script`; `Nobody.run` and `Nobody.output` accept the payload and take no step with it.
- `secrets/backend.nix`: `header` creates the temporary and installs the trap; `deliver` truncates
  and fetches into it. The `deliver` call sites are unchanged, so the lines
  `tests/unit/secrets.nix:453-476` compares exactly stay equal.
- `tests/e2e/test_harness.py`: every recorder gains the keyword and none of them stores the payload;
  `Reporting.output` stops recognising a value write by `base64 -d` (`:510`); `_written`
  (`:2114-2121`) pipes the bytes it used to find in the script; six new scenarios.
- `tests/unit/secrets.nix`: one scenario over the rendered step's own text.
- `tests/e2e/generated-secret/`: two scenarios that run the rendered step, one to completion and one
  against an ssh that refuses, and read what is left in the directory its temporaries were made in.
- `tests/unit/coverage.nix`: this change's two spec files from `excused` to `accountable`.
- `docs/operator.md` (the channel, beside the paragraph on what the write decides),
  `docs/secrets.md` (what the step does with the file it fetched), `docs/tooling.md` (the `secrets`
  suite figure and the total), `CLAUDE.md` (both rules).
- `docs/diagnostics.md` is untouched: this change produces no row and no refusal identifier.
- Nothing under `lib/`, so no plan field, no golden and no counter moves: `fixtures/minimal-typed-edge/plan/*`
  is byte-equal and the nine perf budgets are measured over an untouched evaluation.
