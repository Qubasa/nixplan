## Context

See `proposal.md` - Why. The constraints that shape the approach:

- The channel is one seam. `cli/remote.py:55-69` declares `Runner` with `run` and `output`, and
  `cli/remote.py:3-5` says why: "a caller that wants to observe the order and the argv substitutes a
  recorder for the runner and nothing else about the command changes". `docs/operator.md:653` states
  the same as a property of the check: the command "is asserted by handing it a recorder in place of
  a process table and reading the argv it produced". Anything the fix hides from the argv it also
  hides from every test in this repository.
- `Runner` has two implementations under `cli/` and eight in the harness. `Subprocess`
  (`cli/remote.py:72-90`) is the operator's and `Nobody` (`cli/apply.py:246-263`) is `--dry-run`'s;
  the eight are `Recorder` (`tests/e2e/test_harness.py:90-102`) and the seven that subclass it. The
  docstring at `cli/remote.py:58-60` also claims the shape is rookery's `Cluster.run`; no folder
  hands a `Cluster` to `apply()` - `tests/e2e/secret-delivery/test_secret_delivery.py:263-266` runs
  the built command *as a process* inside the cluster - so the claim is about a shape and not about
  a live implementer.
- A secret is arbitrary bytes. `cli/apply.py:47` types `Write.content` as `bytes` and
  `cli/apply.py:125` reads it from the value source, while `cli/remote.py:88` runs every step with
  `text=True`. Text mode encodes what it is given and decodes what it gets, strictly, in the
  locale's encoding; a payload cannot go through it and a machine's non-UTF-8 output currently ends
  the run inside the decoder.
- The rendered step is a shell script and its reading is pure. `secrets/backend.nix` renders text;
  `tests/unit/secrets.nix:137-141` renders it in a nix-unit suite, which cannot run it. The lines
  that suite compares exactly (`:453-476`) are `deliver` call sites, not the function body.
- `set -eu` is the rendered step's own (`secrets/backend.nix:86`) and the contract's `get` writes to
  the path named in `out` (`:93`).

## Goals / Non-Goals

**Goals:**

- No byte of a delivered value in any process's argument vector, on either host, and a test that
  fails deterministically if one returns.
- No plaintext left on the host that ran the rendered delivery step, including when it failed.
- Every other guarantee of the write unchanged, and `--dry-run` still a substitution of the channel
  and nothing else.

**Non-Goals:**

- No change to what reaches a machine or at what mode. The written file, its ownership, its parents
  and the word the step reports are the same before and after.
- No new refusal and no diagnostics row. Both defects are in layers that already run after the plan
  is applicable, and neither is a fact a plan records, so `docs/diagnostics.md` gains nothing.
- Not the `0755` staging directory `image/default.nix:191,324` installs.
  `refuse-a-value-a-unit-file-cannot-carry` owns those two lines; naming them here would put two
  changes on one edit.
- No encryption of the channel beyond ssh's, and no attempt to keep the bytes out of the machine's
  page cache or off its disk. The file is written where the plan says, and what happens to it there
  is the machine's.

## Decisions

**The script stays in the argv and only the bytes move to standard input.** `Runner.run` and
`Runner.output` gain a keyword-only `stdin: bytes | None = None`; `Subprocess._completed` passes it
to `subprocess.run(input=…)`; `write_script` drops its `content` parameter and its body's
`printf %s <base64> | base64 -d > "$tmp"` becomes `cat > "$tmp"`. The argv of a write is then the
path, the mode and the ownership - three recorded facts the step line already prints
(`cli/apply.py:339-342`) - and nothing else.

Alternative rejected: send the whole script on standard input too, `ssh … sh -s` with the script and
the bytes as one stream. It hides the path as well, and it costs the property the tree is built on:
the recorder would record an argv that says nothing about which step it is, the harness's own
discriminator (`tests/e2e/test_harness.py:510` keys a value write off the script text) would have
nothing to read, `destination` (`cli/remote.py:191-198`) would still work but no test could assert
what a step does, and `docs/operator.md:653`'s claim about how the command is asserted would stop
being true. It also asks the payload and the script to share one stream, which means a delimiter or
a length prefix in the script - a second encoding of the bytes, in the place the first one was the
defect. The path is not a secret: it is in the plan, in the step line, in the unit file that opens
it and in the image's mount point.

**The channel carries bytes in and text out, decoded once.** With a payload, `text=True` is not
available, so the single `subprocess.run` runs in binary mode and the one place that turns a
machine's output into a string decodes it, replacing what it cannot decode. `printed`
(`cli/remote.py:186-188`) is that place for a refusal and `Subprocess.output` for an answer.

Alternative rejected: two modes in one function, text when there is no payload and binary when there
is. Two code paths for one seam, and the refusal path would print one type or the other depending on
which step failed. Alternative also rejected: decoding the payload into `str` and keeping text mode.
A generated secret is bytes - an age identity, a key, a token with a stray `0x80` - and a channel
that can only carry text is a channel that corrupts some deployments silently.

**The recorder records the argv and never the payload.** `Recorder.run` and `Recorder.output` gain
the keyword and drop it on the floor. That is the whole point: a harness that appended the payload to
a list would be a second copy of the leak, sitting in a test file, and the assertion "no recorded
argv holds the bytes" would be made beside a recorded copy of them. It also makes the assertion
stronger than the one the harness makes today, which is that a particular string is absent: the
property asserted is that two payloads of one length produce equal argvs, which is an equality over
the whole vector rather than a search for one known needle.

What still has to observe the bytes is the write itself, and it does so where they land: the
scenario `A value write carries its bytes on the step's input stream` runs the real `Subprocess`
against `bash -c <write_script>` with a payload that is not valid UTF-8, and reads the file back.
The observation is the file, not a recording.

**The rendered step gets one temporary and a trap.** `header` (`secrets/backend.nix:82-103`) creates
the temporary once, before the loop, and installs `trap 'rm -f "$tmp"' EXIT INT TERM HUP`; `deliver`
truncates it and fetches into it. One file rather than one per delivery bounds what a killed process
can leave to one file, and `mktemp` already creates it `0600`.

Alternative rejected: a trailing `rm` after the ssh. Under `set -eu` a refused send exits the script
before it, which is exactly the case that matters - a machine that refused is the reason an operator
reruns the step - and no trailing command runs on a signal either. Alternative rejected: a `mktemp`
and a `trap`/`trap -` pair per delivery, which is three more lines per call and a window between the
`trap -` and the next `trap` in which nothing covers the file. Alternative rejected: no temporary at
all, `out=/dev/stdout "$get" … | ssh …`: the contract hands the backend a path to write and a
backend that writes-then-renames cannot rename onto `/dev/stdout`, and a pipeline hides `get`'s exit
status from `set -e`, because POSIX `sh` has no `pipefail`. The bytes would then be sent by a step
that could not tell a failed fetch from an empty value.

**The residue is permanence, not permission.** `mktemp` creates `0600`, so the honest claim is that
one plaintext file per delivered file per machine accumulates under `$TMPDIR` until something else
removes it, that a rotation adds another beside the old one, and that they are readable by the
operator's own account, by root, and by whatever reads that host's backups. `docs/secrets.md:120-124`
is edited to say what the step does with the file rather than to describe a window it does not have.

**Both halves of `(a)` are one observation.** The script string is the last element of the local
argv (`cli/remote.py:264`) and the machine's login shell receives that same string as one word of
its own argv, so an argv free of the bytes on the operator's host is an argv free of them on the
machine. The spec states it that way rather than asking for two samples, because sampling `/proc`
during a millisecond-long write passes by missing the window, and a test that passes for the wrong
reason is worse than none. The scenario that runs on a machine is not added for that reason, and
`tests/e2e/secret-delivery`'s existing assertions - the bytes, the mode and the owner on each
machine of the delivery set - already prove the write still works over the new channel.

## Risks / Trade-offs

- **An implementer of `Runner` outside this repository stops satisfying it.** → The keyword has a
  default, so every step that sends no payload calls it exactly as before, and only a runner that is
  *type-checked against* the protocol is affected. The docstring at `cli/remote.py:58-60` is
  reworded to say that `run` is the shape `Cluster.run` has for a step that sends nothing, because
  that is what stays true.
- **`errors="replace"` hides a machine's exact bytes in a refusal.** → Accepted, and it is a strict
  improvement: today a machine printing a non-UTF-8 byte raises inside the decoder, which is neither
  the machine's refusal nor the command's own error. What a refusal is for is naming the step and
  the machine (`cli/remote.py:144-147`), not round-tripping bytes.
- **`cat` on the machine.** → No new assumption: the script already needs `install`, `chown`,
  `chmod`, `cmp`, `mv` and `mkdir`, and it stops needing `base64`, which is one dependency fewer.
- **A caller who forces a pty with `-tt` in `NIX_SSHOPTS`.** → The payload would then go through a
  terminal line discipline. A single `-t` does not force one when stdin is a pipe, `BatchMode=yes`
  is already appended (`cli/remote.py:39-48`), and a caller's options are the caller's: the command
  appends rather than decides (`cli/remote.py:17-22`). Not guarded against, and named here so the
  next reader does not have to rediscover it.
- **The rendered step's reused temporary.** → Answered while implementing: truncation is enough.
  `tests/e2e/generated-secret/deployment/backend.py:106-119` fetches with
  `age --decrypt --identity … --output <out>`, and `age` overwrites an output path that already
  exists, measured directly against a file created by `: >`. The step therefore spells the
  truncation `: > "$tmp"` and needs no `rm -f` before each fetch, and `nix run .#planner-e2e
  generated-secret` runs the real tool through that path. A backend whose `get` refused an existing
  path would want the `rm -f` spelling instead; both satisfy the requirement.
- **Cost.** → None that is measured. Nothing under `lib/` changes, so no plan field, no golden and
  no counter moves; `nix build .#checks.x86_64-linux.planner-perf` is not part of this change's
  verification and the reason is recorded in the task list rather than left to a reader.

## Open Questions

- Whether the value write should also stop echoing its own `changed`/`unchanged` through a shell
  that has the payload on its stdin at the same time. It does not today and nothing suggests it
  should, but the one-word answer and the payload now share one connection, and the step's answer is
  read as a word list (`cli/apply.py:355`). Stated rather than assumed: if a `cat` that reads past
  its input ever consumed the answer, the scenario `A value write carries its bytes on the step's
  input stream` is where it would show.
- Whether `image/default.nix:384-396`'s trailing `rm -f "$part"` wants the same trap. Its reads are
  guarded (`:386`), so the line is reachable in practice, and `bin/check` assembles a configuration
  file rather than a secret. Left alone deliberately; if it is to change, it is a change of its own.
