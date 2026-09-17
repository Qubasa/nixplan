## Why

The project's end state (`CLAUDE.md`, "Deployment scope") hands a third party a self-installing
package whose services reach the operator's fleet over a mesh - and no change owns how that
machine becomes a member. Today a machine enters the registry only when the operator can already
dial it: `address` is a name the operator's own network resolves, provisioning is by hand, and a
friend's laptop - behind NAT, on a dynamic address, never root - has no path from "declared in the
registry" to "a run can dial it". The four production changes land the substrate (user scope,
retirement, sealed values, probes) and none of them makes a machine a member.

This change is deliberately the centralized version. A coordination server the operator runs
(headscale) is the membership authority: it answers NAT traversal, naming, expiry and
re-authentication with a tool that already exists, where the decentralized alternative -
membership cards signed by an offline network key, claim fragments by pull request - re-derives
all four and adds a renewal ceremony with no owner. That alternative is recorded, with the trigger
that revives it, in `openspec/changes/PARKED.md`; this proposal spends no further sentence on it.

## What Changes

- **A friend machine is an ordinary registry row.** Its `address` is its mesh name, its scope is
  `user`, and enrollment adds no registry key and no plan field. Everything after admission -
  preflight, value writes, copy, activation, report - is the existing walk dialing a name the mesh
  resolves.
- **The join credential is a generated secret value.** The hub entry running the coordination
  server declares a generator minting a single-use, expiring pre-auth key, `secrecy = "secret"`,
  delivered to no machine (`deploy = false`): the operator reads it out of the value source and
  hands it to the friend outside the tree. Its bytes appear in no plan field and no argv of a run
  - the existing discipline for every secret.
- **Admission is verified, not automated.** The tree automates nothing about approval: the friend
  joins with the key, and the operator's check is the server's own node list. A spent or expired
  key admits nobody - the server refuses it - and expiring a node is how membership ends: the
  machine then reads as unreachable in the report, which already exits non-zero for a machine that
  answers nothing.
- **Exports bind to names.** Because the friend machine's `address` is its mesh name, a URL export
  built from `target.address` carries the name, and whatever answers the name is the mesh's
  business. No library change: the invariant falls out of the row convention.
- Ordered behind all four production changes: the walk that dials the friend machine places a
  user-scope entry on it, so it consumes `run-an-entry-without-root`'s substrate and proves it end
  to end over a real mesh.

## Capabilities

### New Capabilities

- `operator/machine-enrollment`: the registry row convention, the generated join credential and
  its handling discipline, the single-use and expiry refusals, and the report's reading of a
  machine the server expired.

### Modified Capabilities

- none. The registry keys, the walk, the report and the realisers are read as they stand; the
  change adds an order of work and its proof, not a mechanism.

## Impact

- `tests/e2e/guest.nix`: headscale and tailscale in the guest image - a re-key of every folder's
  cut, so `rookery snapshot gc --all` follows the edit.
- A new end-to-end folder `tests/e2e/friend-enrollment/`: a hub running the coordination server as
  a leaf module of the folder's own deployment, a friend machine declared by mesh name at user
  scope, and phases for the join, the spent key, the apply over the mesh and the expired node.
- `docs/operator.md`: the enrollment order of work. `docs/cluster.md`: the guest image note.
- `tests/unit/coverage.nix`: this change's one delta spec, `excused` until it lands.
- `CLAUDE.md`, `openspec/changes/INTEGRATION.md`, `openspec/changes/PARKED.md`.
- `lib/`, `cli/`, the realisers: untouched. The perf gate is not in play.
