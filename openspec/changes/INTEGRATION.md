# Integration order of the four production changes

The four changes in production were planned in parallel against one set of contracts. They are
independent in what they own and not independent in what they touch, so this file records the seams
rather than leaving each change to discover them.

`run-an-entry-without-root`, `retire-an-entry-a-build-no-longer-names`,
`unseal-a-value-after-a-reboot` and `probe-a-service-before-it-counts-as-live`. The other open
changes are not part of this set. `name-the-machine-a-run-dials` is parked, on disk and untouched:
the user-scope redesign moved the seal recipient to an age key the registry states, so nothing
consumes `hostKey` any more, and connection pinning is a separate, currently unowned concern -
whether to delete the change or revive it around pinning alone is an open operator decision.
`declare-service-state` is untouched, `answer-whether-a-machine-is-current` stays open for the
reason `CLAUDE.md` records, `deliver-a-secret-without-exposing-it` stays narrowed for the reason
`CLAUDE.md` records, and `enroll-a-friend-machine` is planned and ordered behind the four - the
closing section names it.

## Order

1. `run-an-entry-without-root` first is the simplest order: `unseal-a-value-after-a-reboot` places
   its unsealer as a user unit on a user-scope machine and `retire-an-entry-a-build-no-longer-names`
   puts `--user` into its argv, and both read `scope` for it.
2. The other three in any order. There is no hard dependency between the four: landing any of the
   others first is landing it system-scope-only, which each states it degrades to - a machine
   stating no scope is a system-scope machine, which is today's behaviour.

## Seams

**The deployment record.** Three changes add to it. `unseal-a-value-after-a-reboot` adds the
machines table and moves the stated version from 1 to 2, because a reader of the previous shape
cannot deliver a value. `retire-an-entry-a-build-no-longer-names` adds the per-realiser `realisers`
table and moves the version too (its D10). `run-an-entry-without-root` adds `scopes` to that same
table - it is one table whichever change introduces it first. Each change's tasks write version
numbers as if it landed first, so whichever lands second or third reads `cli/manifest.py` for the
current number rather than assuming it.

**`operator/apply-command`.** Three changes delta it, each with one step of its own: the preflight
question (`run-an-entry-without-root`), the retirement (`retire-an-entry-a-build-no-longer-names`,
opt-in), and the unsealer install and the sealed value write (`unseal-a-value-after-a-reboot`).
Each delta states only its own step and cites this file for the rest, so the whole on-machine line
is written out here and nowhere else: preflight question, then retirement, then unsealer install,
then value writes, then copy, then activation, then value-driven restarts.

**`planner/machine-platform`.** Two changes MODIFY the registry-keys requirement:
`run-an-entry-without-root` adds `scope` and `unseal-a-value-after-a-reboot` adds `sealRecipient`.
Each delta states its own key only and reads the other as a seam; whichever lands second restates
the requirement text over the amended base rather than over the text both were written against.

**`operator/machine-report`.** Two changes delta it. `unseal-a-value-after-a-reboot` MODIFIES
`A delivered value the machine does not hold is reported`, whose current first scenario says a
reboot loses a value; the retire change only adds. The unseal change therefore owns that sentence.

**The perf gate.** Three of the four touch `lib/`: `run-an-entry-without-root` with the scope atom,
the registry key and the scope-crossing rows, `unseal-a-value-after-a-reboot` with the recipient
grammar, atom and projection, and `probe-a-service-before-it-counts-as-live` with its unit
vocabulary fields. Each is read per machine, per value or per unit of every entry, so each moves
the gated counters and each carries its own baseline-and-check task. They were planned against the
same recorded budgets, so two landing together can pass separately and fail as a pair. Measure
after each, not after all.

**`tests/unit/coverage.nix`.** Every delta spec of the four is registered in `excused` with the
planning artifacts, so the tree is green before any implementation starts. Each change's own tasks
file moves its paths from `excused` to `accountable` in one edit that also ticks every box, because
`changeHasLanded` treats the first `- [x]` at the start of a line as the change having started
landing and `staleExcuses` then fails for an excuse that outlived it. One flip-edit per change, and
every box of all four stays unchecked until its own.

## What this set does not close

A service's mutable state has no declaration site: that is `declare-service-state`, 26 tasks, none
done, and it is the reason nothing here can snapshot before an irreversible activation or know what
to back up. No change here creates an account, opens a port, issues a certificate or routes a
request. `rollback` still has no meaning for an entry realised as a portable-service image, which is
one of the reasons flakelet is the stated target. A machine nobody can dial is named and not
designed: `build-a-bundle-for-a-machine-a-run-cannot-dial`, a named non-goal of
`run-an-entry-without-root`'s proposal, would realise an unmanaged registry machine as one exported
self-installing bundle - artifacts, sealed values, the unsealer, and an installer that is the
one-machine apply walk run locally - and the four changes keep it reachable rather than build it:
attach scripts take no decision from the operator, sealed values need no live channel, and the
preflight stays a list of questions a local installer could ask.

How a machine becomes a member is `enroll-a-friend-machine`, planned and ordered behind all four:
its folder dials a friend machine by its mesh name and places a user-scope entry on it, so it
consumes `run-an-entry-without-root`'s substrate, and the designs it deliberately does not build -
decentralized enrollment, the mesh-provider interface, the phone book, sealed values on gossip -
are parked with their triggers in `PARKED.md` beside this file.
