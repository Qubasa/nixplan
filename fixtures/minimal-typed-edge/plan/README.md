# The committed plan

`backup.json` is `mkPlan` over this folder, as committed: eight entries, real
hashes, real store path strings, no ellipsis and no invented hash. Every field
in it is a field the planner produced, so it is compared with `==` in evaluation
by `tests/unit/plan.nix` and regenerated with one command:

```bash
nix eval --json .#planner.worked.plan | jq -S . > fixtures/minimal-typed-edge/plan/backup.json
```

Regeneration is never automatic. It is a command a reader runs and a diff a
reviewer reads, which is the point of committing the plan at all.

The notes below were once `note` keys inside the document. They are prose for a
reader, not fields of a plan, and a comparison that had to know which keys were
prose is what `golden.py` existed to be. They live here instead, each under the
attribute path it described.

`diagnostics.txt` is the rendered table for the same evaluation.

## `/`

An export record carries `secrecy` and nothing the interface did not declare: an
export in this folder declares `type` and `secrecy` and nothing else, and `type`
is structural rather than resolved, so it appears as the interface name on the
capability and not per export. The other fields on a record — `plane`, `readBy`,
`rows` — are what the planner resolved about that export, not what its author
wrote. Every sibling plan writes three tags per export because §32.1 declares
three bounds; `../interfaces/exports.nix` narrows the declaration to one, and a
plan that recorded `locality` or `lifecycle` would be recording a field no
interface in this folder wrote.

## `nightly:client@alpha`

This entry and `vault-repo:server@vault` read each other and neither appears in
the other's `dependsOn`. Both values are known at evaluation, so both reads
resolve directly, and the pair is acyclic because a capability's exports are a
function of module and settings and never of a wire.
The corpus's one-daemon-two-networks sketch keeps its own mutual pair
acyclic through the fact register instead, because the values there are
at-most-probed.

## `nightly:client@alpha/provides/identity/exports/privateKey`

Declared and delivered to nobody. No slot in the plan names it, because a
`reads` entry for a secret export is refused outright rather than checked
against a machine boundary. The reference appears in this entry's own env
because the service that made the key is the service that uses it.

## `nightly:client@alpha/reads/repo`

One placement of the wired capability, so the single-valued read is satisfied. A
second placement of `vault-repo:server` would be a row naming this slot and both
placements rather than an attrset this module was not written to index.

## `nightly:client@gamma`

The entry exists and its export is declared, which is the whole difference from
the fold clan-core writes today. There, this machine is absent from a list and
nothing names it. Here the capability is declared by the module, the placement
is decided by the tag, the entry is written, and only the bytes are missing — so
exactly one row is produced and it names this machine.

## `vault-repo:server@vault/configData//srv/borg/.ssh/authorized_keys`

The hash is not computed because one entry of the set it renders has no value.
Two of the three lines are known and the file is not, which is the difference
between this model and a fold that would have written a two-line file and called
it done.

## `vault-repo:server@vault/reads/clients`

Three named entries for three placements of the wired capability, and the third
carries no bytes. The set is named rather than counted, so the absent one is a
row against that entry instead of a shorter list. `reads` is the declared list
from `../modules/borg-repo/server.nix` and `privateKey` is not in it, so no
private half appears anywhere in this entry.
