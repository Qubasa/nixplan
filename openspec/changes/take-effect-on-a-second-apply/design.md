## Context

See proposal.md - Why. The shapes that decide the approach:

- **The attach script is already almost the right thing.** `image/default.nix:229-246` is guards,
  the not-computed refusal, the reference checks, `install -d` of the staging directory, one
  `assemble` per computed file, `portablectl attach`, `systemctl start`. Only two steps are missing
  and one is misplaced: no replacement of an older image, no reload, and the attach is unconditional.
- **`assemble` is already atomic and mode-safe** (`:152-189`): `install -m 0600 /dev/null` into a
  `.assembling` file, append, then `install -m <mode>` into place. Comparing before installing is one
  more line in the same function.
- **The machine can already be asked which image an entry runs from.**
  `tests/e2e/portable-image/test_portable_image.py:400-410` reads `systemctl show -P RootImage` and
  compares it against the artifact's `.raw`. That is the fact the replacement step needs, and it is
  already proven readable on a machine.
- **`holds_attached` is the only reason the script is skipped** (`cli/apply.py:154-190,308-312`), and
  its own docstring says the artifact's script is what decides. Making the script idempotent removes
  the question.
- **The endpoint's no-op for an unchanged artifact is correct** and is pinned by
  `tests/e2e/wired-pair/test_wired_pair.py:553-562`. Nothing about a delivered value can be answered
  there.

## Goals / Non-Goals

**Goals:**

- Make "change something and apply" work for the four things that can change: an artifact's identity,
  a configuration file's bytes, a delivered value's bytes, and a machine that lost its values.
- Keep every one of those decisions where the fact lives: the script owns the machine's state for
  one entry, the command owns what it wrote, the report owns what it asked.
- Make an unchanged apply provably a no-op, at the level of unit main processes rather than of
  command output.

**Non-Goals:**

- No rollback for an image entry. `cli/report.py:202-206` refuses it because an image carries no
  generation, and replacing an image is not the same thing as keeping the previous one to return to.
- No persistence of values across a reboot. They stay under `/run` deliberately: a secret that
  survives a power cut is a different security property, and the answer here is that the report says
  which are missing and an apply puts them back.
- No per-unit narrowing of a value's readers. A changed value restarts the units of the entries that
  read it; a `restartUnits`-style list per value is a vocabulary question, and clan's own field
  (`generic-generator.nix:193`) is the precedent to copy if the coarseness bites.
- No new plan field. Everything the new steps read - the `reload` list, the assembled bytes' hash,
  the resolved reads - is already recorded.

## Decisions

### The script becomes idempotent and the command stops deciding

One owner for "make this machine match this artifact", and it is the artifact's own script, because
it is the only thing that knows what the entry consists of. The command runs it and reports its
lines. `holds_attached` is deleted rather than fixed: any check the command makes is a second,
weaker copy of the script's own.

The script's steps are ordered so that a failure leaves the machine in a state a rerun can finish:
assemble before attach, because a half-assembled file under an attached image is a unit that starts
against wrong bytes; replace before attach, because two images rendering one unit name collide;
reload last, because reloading a unit that is not yet started is meaningless.

Alternatives considered:

- **Keep the skip and add a marker file recording what was assembled.** Rejected: it is state on the
  machine that only this tool writes and nothing verifies, and the machine already holds the
  answer - the bytes at the declared path.
- **Give the artifact a second script for assembly and keep `attach` as is.** Rejected: the command
  would then have to know which of two scripts to run when, which is the decision being moved out of
  it.

### An older image is found through the service manager, not through a name

`systemctl show -P RootImage` on the entry's first unit answers "which image is this entry running
from" exactly, including after a rebuild whose unit names are identical. The script compares it with
its own `.raw` path: equal means attached and current, empty means nothing attached, anything else
means an older image to stop and detach.

Alternatives considered:

- **Version the unit file names.** Rejected: the names are what `flakelet` validates and what a
  report reads, and a version in them would make every unit name move with every rebuild, including
  for the realiser that has generations of its own.
- **`portablectl list` and a name-prefix match.** Rejected: the output is a table this tree already
  had to write a fallback parser for (`cli/remote.py`'s `attachment_of`, whose fallback branch has no
  test because no real `portablectl` prints one), and `RootImage` is one word.

### A configuration file's change is detected by comparing bytes, not by a digest in a record

`assemble` already writes to a temporary at the declared mode. It hashes that temporary and the
existing file, installs only if they differ, and prints the path when it did. The comparison is on
the machine, where both halves exist, and no new plan field is needed. A `ref`-bearing recipe
interpolates delivered bytes, so its assembled result changes exactly when those bytes do, which is
the same signal the reload needs.

### A changed value's readers are restarted by the command, from the resolved reads

The write step compares the bytes on the machine before writing - by hash, never by printing them -
and reports `changed` or `unchanged`. After every write, the command restarts the units of every
entry whose resolved reads name a changed value, using the service manager's "restart if running" so
that a stopped unit stays stopped. The edge source is `cli/order.py`'s `edges`, the same one the
activation order uses, so a read that orders an apply is a read that rotates a consumer.

Restarting the whole entry rather than a named unit is deliberate coarseness: the plan says which
entry reads the value and does not say which of its units opens the file. Naming the unit is a
vocabulary addition, and the coarse answer is correct - a unit that did not read the value is
restarted needlessly, never wrongly.

### The report gains one line and one word

A missing delivered value is a line, printed as it is known, exit status unchanged - staleness is
never an exit status. Whether a *held* value is current is deliberately not asked: answering it means
reading a secret to report on it.

For configuration bytes the report compares what the machine holds at the declared path against what
the build would assemble, and prints a different word than `current` when they differ. The
alternative - stating that the comparison covers the artifact only - is written into the requirement
as the permitted weaker answer, because it is honest and cheap, and the stronger one is what this
change implements.

## Risks / Trade-offs

- **A restart on rotation can take a service down that a stale secret would not have.** → It is what
  an operator rotating a credential is asking for, it is reported as its own step naming the value,
  and a stopped unit is not started. A deployment that wants no restart can rotate outside an apply.
- **The coarse restart replaces processes that did not read the value.** → Correct but wasteful; the
  precise version needs a vocabulary field, and the requirement states the coarse rule so a later
  change narrows it without contradicting this one.
- **Comparing a value's bytes on the machine means hashing a secret there.** → The hash is computed
  by the same step that is about to write the bytes, in a process that already holds them, and
  neither the hash nor the bytes are printed. The alternative - always restarting every reader -
  makes every apply a fleet-wide restart.
- **Deleting `holds_attached` makes every apply run the machine-side script**, which is slower than
  a skip. → It is one ssh round trip per entry, which every apply already pays for the copy, and the
  skip it replaces is the bug.
- **`RootImage` is systemd's spelling**, so the replacement step is service-manager-specific. → So is
  everything in this realiser: it renders systemd units and calls `portablectl`. The flakelet
  realiser has generations and needs none of this.
- **A machine an operator edited by hand is silently corrected.** → That is what applying a
  deployment means, and the step reports what it changed.
