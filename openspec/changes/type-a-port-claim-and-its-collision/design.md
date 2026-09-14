## Context

See `proposal.md` - Why. The shapes that decide the approach are already in the tree:

- **An enumerated field is an atom over a named domain.** `restartPolicies` and
  `consumerCardinalities` are lists in `lib/atoms.nix:15-28`, each read twice: once by the atom's
  predicate and once by the row that reports a value outside it (`lib/atoms.nix:65-75`). A port
  claim is the one scalar of the module vocabulary with neither.
- **A value that fails its type is dropped, never coerced.** `unit-field-type-mismatch` records
  nothing for the failing field, and `readClaims` already drops a claim with no `fixed`
  (`lib/module.nix:355`). A reading that repaired `"5432"` into `5432` would make the plan a
  function of a guess.
- **The claim record the index reads is the module's own attrset.** `readClaims` returns
  `util.filterAttrs (_: claim: claim ? fixed) ports` (`lib/module.nix:355`), so `proto` reaches
  `lib/plan.nix:706` exactly as the module wrote it. Any validation that does not also normalise
  leaves the index reading around it.
- **`alloc` is an input to the entry key.** `keyInput.alloc = member.alloc.ports`
  (`lib/plan.nix:802`) and `alloc.ports` is `mapAttrs (_: claim: claim.fixed)`
  (`lib/resolve.nix:941-943`). Anything added to what `alloc` records re-keys every entry that
  claims a port; anything read off the declaration at the index site does not.
- **The collision index is two `groupBy` passes over a flat list** (`lib/plan.nix:733-757`), built
  in `entries`, which is the one site that holds every placed entry. The perf gate is cost per plan
  entry with a margin of 0.15 across sizes 4, 16, 64 and 256, and both perf fixtures claim one port
  per entry (`perf/fleet.nix:89-92`, `perf/mesh.nix:101-104`).
- **`lib/` names no realiser and allocates nothing.** A claim is a fact the deployment states, and
  `dynamicPort` records the condition that would change that (`lib/excluded.nix:32-35`).

## Goals / Non-Goals

**Goals:**

- Make the value `entry-port-claimed-twice` compares a value the reading has held to a domain, so
  the row fires on the input it claims to fire on.
- Make the unstated case the safe one: a claim that says less collides with more, never with less.
- Let two listeners on one number and two addresses be a deployment the planner accepts, without
  letting two listeners on one number and one address through.
- Move no entry key, no plan record and no golden byte for a declaration that exists today.

**Non-Goals:**

- No allocation and no search. The planner picks no number and no address.
- No record of the protocol or the address in the plan. What `alloc` carries stays the number.
- No resolution of an address to an interface. The comparison is textual, which is what a pure
  evaluation can do.
- No second check for a port a unit actually binds. The plan records a claim, not an observation of
  a command line, and inferring a listener out of a command string is the mistake
  `closure-path-undeclared` exists to refuse.

## Decisions

### The number is a `port` atom, and a claim whose number is not a port is not recorded

`port` is `isInt v && v >= 1 && v <= 65535`, and a failing claim is `port-claim-not-a-port` and is
absent from `alloc`. The index then compares the integer itself and the `builtins.toJSON` at
`lib/plan.nix:708` is deleted, because the only reason it was there was to make two types of one
number comparable as text, which is precisely the defect: it made them comparable and unequal.

Zero is refused with the rest. A claim of port 0 is the kernel being asked to choose, which is the
`dynamicPort` excluded construct under another spelling, and a plan recording 0 records a number no
two evaluations agree about.

Alternatives rejected:

- **Coerce a digit string.** Rejected: `fixed = "5432"` and `fixed = 5432` would then be one claim,
  but `alloc` would carry a value the module never wrote, and every other typed field of this
  vocabulary drops rather than repairs.
- **Compare `toString` instead of `toJSON`.** Rejected: it closes the string-versus-integer hole and
  leaves the claim untyped, so `fixed = 99999` and `fixed = -1` stay claims and the row says nothing
  about them.

### The protocol stays optional, and an unstated protocol collides with every protocol in the domain

`proto` is not required. An omitted protocol is read as every protocol of the domain, so a claim
that says less collides with more. The domain is `protocols = [ "tcp" "udp" ]`, published as
`domains.protocol` beside `domains.restartPolicy`; a value outside it is
`port-claim-protocol-unknown`, and the refused claim is then read as though it stated no protocol.

Alternative rejected: **make `proto` required.** It is the stricter-looking option and the weaker
one. Required means a new error row for a declaration that is not wrong, it means editing every
claim in this tree and every claim outside it for no behaviour change, and it buys nothing the wide
reading does not already buy: the question the index has to answer is "could these two listeners
contend", and "the author did not say" answers yes. The wide reading also fails in the safe
direction if the domain later grows, whereas a required field plus a narrow domain refuses an
`sctp` listener outright. What is lost is a nudge towards stating the protocol, and a warning would
be the way to buy that back if it is ever wanted; it is not in this change, because a warning nobody
can silence on every existing claim is noise.

Two values rather than four is the same subset argument `restartPolicy` makes. `sctp` and `dccp`
need a kernel module and appear in no unit of this tree; the domain is named in the row, so the
refusal teaches rather than surprising, and widening it later is additive and re-keys nothing.

### `count` is removed rather than expanded

`count` records nothing, expands into nothing, and protects nothing: `{ fixed = 8000; count = 4; }`
is guarded on 8000 and unguarded on 8001 to 8003, which is worse than no field, because the
declaration reads as though the range were claimed.

Expanding it means `alloc` records the range, and `alloc` is in `keyInput` (`lib/plan.nix:802`), so
every entry that writes the word re-keys - a redelivery of twelve claim sites for a number the plan
never carried. It also makes a claim a range everywhere downstream: the index compares intervals
rather than values, the row has to name which member of the range collided, and `alloc.ports.<name>`
stops being a number a module can interpolate into a command line, which is the only thing any
module in this tree does with it. That is an allocation-table-shaped change, and the allocation
table is an excluded construct with a recorded trigger (`lib/excluded.nix:32-35`).

Removing it is one word per site. A module that keeps writing it earns `declaration-unknown-key`
(`lib/module.nix:164-191`), which is an error naming the key and listing what a claim reads, so an
out-of-tree module is told exactly what to delete. No shim, no deprecated spelling, no silent
acceptance: the twelve sites are enumerated in `tasks.md` and in the proposal's Impact.

Alternative rejected: **keep it, unread, and document it as reserved.** Rejected on the same ground
the tree refuses an unknown key at all - a field that reads as a guarantee and provides none is
worse than its absence, and `docs/authoring.md:142` currently publishes it as vocabulary.

### A claim may state the address it binds, and the absence is the wildcard

`address` joins `proto` and `fixed`. An absent address is the wildcard, so every declaration that
exists keeps its meaning and no plan record moves. Two claims of one machine and one number collide
when their protocols overlap **and** their addresses overlap, where two addresses overlap if either
is the wildcard or the two are the same string.

The comparison is per claim rather than by hash group, because overlap is not equality: a wildcard
claim and a specific claim collide while two specific claims do not, so a single grouping key cannot
express it. The index keeps its first pass - group by machine, then by number, which is linear - and
compares inside a group. Claims of identical protocol and address spelling stay one bucket, so three
entries claiming one number still produce one row naming all three; distinct spellings inside one
group are then compared pairwise. A group has more than one member only where two entries of one
machine already claim one number, and ports per machine are few: in every fixture and both perf
inputs every group is a single claim and the pairwise step does no work at all.

A claim may take part in more than one collision - a wildcard claim against two specific ones is two
rows, one per address - and each row names its own claimants and its own address, because each has
its own resolution.

**This costs no re-key.** The address is read at the index site off the normalised claim, the way
`proto` is read at `lib/plan.nix:706` today; `alloc.ports.<name>` stays the number alone, so
`keyInput.alloc` is unchanged and an entry that adopts the field keys as it did. An address a
deployment actually varies still re-keys the entry, because the module reads it out of `settings` to
write the claim and `keyInput.settings` is `member.settings.values` (`lib/plan.nix:801`).

The address is also not handed back through `implArgs`. A module that states an address already has
the value in scope - it wrote the claim from its own settings - so handing it back would be the
planner restating its caller's input, and it would put a second copy of the value in a place a
module could read instead of the one it wrote.

### The address is typed too, which is a third new identifier

An untyped `address` would re-import the defect this change exists to close on a field the change
itself adds. `bindAddress` admits a non-empty string of `[0-9A-Za-z:._%-]` and refuses the wildcard
spellings `0.0.0.0`, `::`, `[::]` and `*`, because the wildcard is the absence of the field and two
spellings of one thing is exactly what `toJSON` gave the number. A value outside it is
`port-claim-address-malformed`, whose resolution names both halves: write the address, or omit the
field for the wildcard.

### A refused number drops the claim; a refused protocol or address does not

The three refusals do not have one consequence, because the failure directions are not the same. A
number that is not a port leaves nothing to record, so the claim is dropped, which is what
`port-claim-not-fixed` already does. A protocol or an address that is refused leaves a perfectly
good number, and dropping the claim there would remove it from the collision index - a refusal that
makes the library check less than it did. So the number is recorded and the refused field is read as
unstated, which is the widest reading and the one that still reports a contention.

### Merging with `reserve-what-a-machine-already-holds`

That change lands on its own branch and this one does not contain it. It factors a shared
`portResource proto number` out of `portsOf` in `lib/plan.nix` and adds a `reservedBy` claimant, so
a machine's existing listener contends with a declared claim. This change deletes `portResource`:
the string it built is the defect, and what `portsOf` returns here is the normalised record the
reading produced.

The merge is therefore not a textual one. A reservation has to become a claim record of the same
shape - a number, a protocol and an address, each already held to its domain, with `null` for an
unstated field - and enter the same `(machine, number)` group as a claimant that is the machine
rather than an entry. Nothing else of the overlap step moves: a reservation stating no protocol
contends with every protocol the way an unstated claim does, and a reservation naming an address
contends only with the claims whose address overlaps it.

## Risks / Trade-offs

- **A deployment that plans today stops planning.** → Only where a claim writes `count`, a number
  that is not a port, or a protocol outside two values. The first is twelve enumerated sites in this
  tree and one deleted word outside it; the second and third are declarations whose current
  behaviour is a listener nothing guards.
- **Typing the number changes what a settings knob may carry.** → A deployment writing
  `settings.port = "5432"` is refused where it used to plan. That is the intent: the claim it
  produced collided with nothing. Settings themselves stay untyped (`lib/compose.nix:108`); the
  claim is where the value becomes a port.
- **Address comparison is textual, so `127.0.0.1` and `localhost` do not collide.** → Accepted and
  recorded. Resolving a name is a machine's answer, not a plan's, and the same rule already governs
  `userName` and `groupName` (`lib/atoms.nix:82-92`). The wildcard case, which is the one that
  actually contends with everything, is exact.
- **Two specific addresses that are the same interface written two ways plan cleanly and fail on the
  machine.** → The fail-open direction, chosen deliberately: the alternative refuses a fleet running
  two databases on one host, which is the case this half of the change exists for.
- **The index gains a pairwise step.** → Inside one machine and one number only, where the healthy
  group size is one. The gate is `nix build .#checks.x86_64-linux.planner-perf`, and the budgets are
  per plan entry, so a constant-factor step inside a singleton group moves neither the cost nor the
  growth bound beyond the 0.15 margin.
- **An out-of-tree module using `count` gets an error rather than a warning.** → A warning would
  leave the field readable as a guarantee for another release. Clean cutover is the tree's rule and
  the row names the key to delete.

## Open questions

- Whether `alloc` should eventually record the protocol and the address beside the number. It would
  let a realiser or an operator's report see what an entry claims, and it would re-key every entry
  with a claim. Deferred deliberately: nothing reads it today, and the re-key has to be paid by a
  change that has a reader to show for it.
- Whether the domain should grow to `sctp`. Left at two until a deployment declares one; widening is
  additive and moves no key.
