## Context

See `proposal.md` - Why. What shapes the approach:

- The four production changes land the substrate this change stands on:
  `run-an-entry-without-root` gives the friend machine a scope, a preflight and a realiser;
  `unseal-a-value-after-a-reboot` gives it recovery without the operator;
  `retire-an-entry-a-build-no-longer-names` gives membership an ending on the entry side;
  `probe-a-service-before-it-counts-as-live` tells a started service from a working one. None of
  them makes a machine a member, and this change makes nothing but that.
- The registry reading is closed over its keys and this change keeps it closed: `address` is
  already an opaque name handed to ssh, so a mesh name is an address like any other and no layer
  below the registry can tell the difference. That is the whole trick.
- The vars machinery already covers the credential: a generator on an entry, a secret file
  record, `deploy = false` for a value no machine receives, and the harness recorder that proves
  an argv carries no payload. Nothing new is built for it.
- A design round recorded in `openspec/changes/PARKED.md` explored the decentralized shape -
  membership cards, an offline network key, claim fragments by pull request, a gossip phone book
  - and its red-team found the renewal paradox, clock skew at admission and revocation
  distribution. Every parked construct carries the trigger that revives it.

## Goals / Non-Goals

Goals:

- A friend's machine becomes a member the operator's runs can dial, with one credential handover
  and one verification, and is an ordinary machine ever after.
- The whole path is proven on real machines: join, spent key, apply over the mesh, expiry.

Non-goals:

- The exported self-installing bundle for a machine no run can ever dial stays
  `build-a-bundle-for-a-machine-a-run-cannot-dial`, the named follow-up of
  `run-an-entry-without-root`. This change makes the friend machine dialable instead.
- No decentralized enrollment, no mesh-provider abstraction, no second mesh backend. Parked, with
  triggers.
- No `cli/` subcommand and no library rule. Enrollment is an order of work and its proof.

## Decisions

- **D1. Centralized on purpose.** The coordination server the operator runs is the membership
  authority. It buys NAT traversal, naming, expiry and re-authentication as an existing tool, and
  the price - the server is an availability dependency the operator hosts - is accepted and
  recorded here rather than discovered. The decentralized alternative is parked, not rejected:
  its trigger is an operator requirement that no coordination server exist.
- **D2. The sync is one-way, registry to server.** The registry declares which machines the
  deployment means; the server admits and expels. The server's database is never a source the
  planner reads - a machine's runtime reachability, its current endpoint, its last-seen are the
  mesh's facts and enter no plan. The only gate from the mesh back into evaluation is an
  operator-reviewed registry edit. This keeps `mkPlan` pure and keeps a join from re-keying
  anything but the joined machine's own rows.
- **D3. The credential is single-use and expiring, and the ceremony is verification after the
  fact.** A pre-auth key admits whoever presents it first, so the honest ceremony is not the
  handover but the check: the operator reads the server's node list after the friend reports
  success, and expires the node if the answer surprises. Single-use makes the interception case
  visible - the second presenter is refused and the first is on the list to inspect.
- **D4. The mesh name is the address.** Declaring the friend machine's `address` as its mesh name
  makes every export built from `target.address` carry the name, so nothing binds to a number the
  mesh may reassign. The invariant costs no code; it is a row convention the end-to-end folder
  exercises and `CLAUDE.md` records.
- **D5. The server runs as a leaf module of the folder's own deployment.** The end-to-end hub
  runs headscale as a planned entry, not as guest-image wiring, so the folder proves the operator
  story - the server is itself a service the plan places - and the guest image only gains the
  packages.

## Risks / Trade-offs

- The coordination server is a single point of admission and of naming. Accepted for this
  change's scale; the parked design is the exit when that stops being acceptable.
- A pre-auth key is bearer authority until it is spent or expires. Mitigated by single-use, a
  short expiry, and D3's verification; not eliminated.
- headscale and tailscale enter the guest image, which re-keys every folder's snapshot cut. One
  edit, `rookery snapshot gc --all` after it, and the cost is paid once.
