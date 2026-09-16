# Integration order of the four production changes

The four changes that make the tree operable with flakelet as the stated realiser were planned in
parallel against one set of contracts. They are independent in what they own and not independent in
what they touch, so this file records the seams rather than leaving each change to discover them.

`retire-an-entry-a-build-no-longer-names`, `name-the-machine-a-run-dials`,
`unseal-a-value-after-a-reboot` and `probe-a-service-before-it-counts-as-live`. The three other open
changes are not part of this set: `declare-service-state` is untouched,
`answer-whether-a-machine-is-current` stays open for the reason `CLAUDE.md` records, and
`deliver-a-secret-without-exposing-it` is narrowed by the second change below.

## Order

1. `name-the-machine-a-run-dials`, first, because it introduces `hostKey` and
   `unseal-a-value-after-a-reboot` consumes it as the seal recipient. Nothing else depends on it.
2. `unseal-a-value-after-a-reboot`, second, and it bumps the deployment record's version. See the
   seam below.
3. `retire-an-entry-a-build-no-longer-names` and `probe-a-service-before-it-counts-as-live`, in
   either order or together. Neither depends on the other and neither depends on 1 or 2.

## Seams

**The deployment record.** Two changes add to it and only one bumps its version.
`unseal-a-value-after-a-reboot` adds a machines table and states that the shape carrying it is a new
version, because a reader of the previous shape cannot deliver a value.
`retire-an-entry-a-build-no-longer-names` adds a per-realiser fact about what a machine's answer
names a holding by, which an old reader ignores. Landing in the order above means the retire change
adds its field to the version the unseal change wrote. Landing them in the other order means the
retire field lands in version 1 and the unseal change carries it forward. Either is correct; what is
not correct is both changes bumping the version to 2, so whichever lands second reads
`cli/manifest.py` for the current number rather than assuming it.

**`operator/apply-command`.** Three changes delta it: the retire step and its announcement, the
channel and the options it connects with, and the unsealer install step. Each is an ADDED
requirement except `name-the-machine-a-run-dials`, which MODIFIES `The command refuses before it
dials` and `What the command does on a machine` - so a change landing after it restates neither of
those two and reads the amended text as its base.

**`operator/machine-report`.** Two changes delta it. `unseal-a-value-after-a-reboot` MODIFIES
`A delivered value the machine does not hold is reported`, whose current first scenario says a
reboot loses a value; the retire change only adds. The unseal change therefore owns that sentence.

**`tests/unit/coverage.nix`.** All fourteen delta specs are already registered in `excused`, and the
registration is committed with the planning artifacts, so the tree is green before any
implementation starts. Each change's own tasks file moves its paths from `excused` to `accountable`
in one edit that also ticks every box, because `changeHasLanded` treats the first `- [x]` at the
start of a line as the change having started landing and `staleExcuses` then fails for an excuse
that outlived it. Every box of all four stays unchecked until that one edit.

**The perf gate.** Three of the four add to `lib/`: a registry key and an atom, a sealed path, and
two unit vocabulary fields. Each is read per machine, per value or per unit of every entry, so all
three move the gated counters and each carries its own baseline-and-check task. They were planned
against the same recorded budgets, so two landing together can pass separately and fail as a pair.
Measure after each, not after both.

## What this set does not close

A service's mutable state has no declaration site: that is `declare-service-state`, 26 tasks, none
done, and it is the reason nothing here can snapshot before an irreversible activation or know what
to back up. No change here creates an account, opens a port, issues a certificate or routes a
request. `rollback` still has no meaning for an entry realised as a portable-service image, which is
one of the reasons flakelet is the stated target.
