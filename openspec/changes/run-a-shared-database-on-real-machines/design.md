## Context

See proposal.md - Why. The constraints that shape the folder, all of them existing facts:

- **The unit vocabulary is eleven fields** (`lib/module.nix:58-70`): `command`, `env`, `after`,
  `requires`, `user`, `oneShot`, `remainAfterExit`, `schedule`, `timeout`, `stopCommand`,
  `reloadCommand`. There is no `Restart=`, no `ExecStartPre=` and no socket unit. `after`/`requires`
  may name only units the same module declared (`lib/atoms.nix:20`), which is all this folder needs.
- **flakelet refuses a configuration file.** `flakelet/read.nix:125` accepts a host path only where
  `from == path`, and `image/read.nix:217-225` gives every `configData` file `from = staged`. So a
  flakelet entry may show no assembled file at all.
- **A delivered value lands at `0400 root`** (`cli/remote.py:282-284`), and a generated file record
  admits exactly one key, `secrecy` (`lib/module.nix:365`). A non-root reader cannot open one.
- **A port claim must be `fixed`** (`lib/module.nix:329`); `alloc.ports` echoes it
  (`lib/resolve.nix:806-807`).
- **flakelet is `trusted`** (`flakelet/read.nix:50`), so `User=` is rendered
  (`image/read.nix:524`) and no `DynamicUser` is forced. Nothing creates the account.
- **The shared guest image's every property is part of every snapshot cut's key**, and the cache
  never evicts (CLAUDE.md, Machine layer snapshots).

## Goals / Non-Goals

**Goals:**

- Prove the shared-provider shape on machines with no change under `lib/`, `image/`, `flakelet/`,
  `secrets/`, `operator/` or `cli/`, so that the four library changes that follow have a working
  deployment to be measured against.
- Assert the claims that are worth having independently of any of them: one process behind two
  capabilities, a routable read from another machine, per-consumer credentials bounded by the
  delivery set, isolation enforced by the server, and state surviving a restart.
- Keep every accommodation the vocabulary forces visible in the folder's own text, so that a reader
  can tell a design decision from a workaround.

**Non-Goals:**

- No member cuts. `pg-shared`'s consumers in the corpus are cuts of one module
  (`notes/examples/instance-as-group/deployment/instances.nix:139,164`), which is
  `lib/excluded.nix:37-44`. This folder writes two consumer instances of one consumer module that
  declares its slot unconditionally, and `openspec/changes/cut-a-member-and-wire-its-place` is where
  the cut arrives. When it does, the folder's instances change and no plan key does.
- No restart policy, no socket activation, no health check, no co-placement by locality, no firewall
  rule, no port range, no provider-side consumer cardinality. Each is either excluded
  (`lib/excluded.nix`) or absent from the vocabulary, and none is needed for the claims above.
- No external generator. The passwords come from the operator-supplied value source
  (`cli/values.py:73-91` excludes a `program`-bearing value from the required set), so this folder
  does not depend on the draft nixpkgs branch `tests/e2e/generation.py:46-48` pins.
- No `image` realisation of the cluster. A confined image entry may not read a deployed secret
  (`image/read.nix:255-263`), and `trusted` drops the confinement that would be the reason to use
  one.

## Decisions

### The server's knobs are command-line flags, not a configuration file

Every setting the cluster needs is passed as `-c <key>=<value>` on the long-running unit's
`command`, and the host-based authentication file is written into the data directory by the
initialising unit. The data directory is state, not `configData`, so `flakelet/read.nix:125` never
sees an assembled host path.

Alternatives considered:

- **Declare `configData` and realise the cluster as an image.** Rejected: it trades the refusal for
  `image`'s own gaps - no boot persistence (`image/read.nix:505-529` emits no `[Install]`), an
  attach that is skipped on a second apply (`cli/apply.py:308-312`), and the secret denial - so the
  folder would be measuring three broken things at once.
- **Wait for configuration files under flakelet.** Rejected as a blocker: it makes this folder
  depend on `openspec/changes/hold-a-long-running-daemon`, and the flag form is what a reader would
  write anyway for a server with six knobs.

### Two units, ordered, and the secret is read by the root one

`units.init` is `oneShot` with `remainAfterExit`, runs as root, and does everything that must happen
once: initialise the data directory if it is empty, write the authentication file, start a private
server long enough to create each database and its owning role, and set each role's password from the
delivered file. `units.postgres` runs as the `postgres` account with `after` and `requires` naming
`init`.

That split is what lets the folder need no change to how a value is delivered: the only reader of a
`0400 root` file is a root unit, and the server never opens one. It is also the honest shape - a
database's schema and roles are applied once, not on every start.

The consumer's unit runs as root and reads its own copy of the password. When
`openspec/changes/open-a-delivered-value-to-its-reader` lands, both readers can become non-root and
the folder gains a scenario rather than changing shape.

### The account is declared in the guest image

`users.users.postgres` with a matching assertion naming this folder, stating that no plan creates an
account and that the addition re-keys every cut.

Alternatives considered:

- **`DynamicUser` plus `StateDirectory` under a confining image profile.** Rejected: `dynamicUser`
  is not in `image/read.nix:66-83`, flakelet is `trusted`, and the secret denial closes the path.
- **Run the server as root.** Rejected: PostgreSQL refuses to start as root, which is a property of
  the payload and not something a deployment may decide.
- **A machine-facts construct so a module can require an account.** That is the `perMachine` gap and
  a far larger change; recording the boundary in an assertion is what this folder can honestly do.

### Two machines, with the near consumer co-located

`alpha` holds the cluster and the consumer of the `eu` database; `beta` holds the consumer of the
`us` database. Two machines rather than three because the stage shape is part of the cut's key and a
third slot buys nothing: co-location and a routable read are both present at two, and the delivery
set already has a machine that is a working consumer excluded from one value.

The stage is this folder's own. Two folders never share one cut (CLAUDE.md), and the preparation body
waits for `multi-user.target` and yields - no delivery, no activation, so the evidence the tests read
is an observation rather than a replay.

### The passwords are minted by the test and written to the value source

The test mints two random values, writes them under `<source>/<value entry key>/<file>` the way
`tests/e2e/secret-delivery/` does, and applies with `planner apply --values`. Each password is
`per = "instance"` on the cluster's member, one generator per database, so the two values are two
keys and the delivery set of each is derived from the reads that name it.

### Every observation is one `key=value` line

The guest's sshd is per-connection socket activated, so a burst of short logins hits the socket's
trigger limit (CLAUDE.md, End-to-end layer). One case is one ssh command whose output is
`key=value` lines, file bytes are compared on the machine and reported as one word, and the phases
are session-scoped in file order.

## Risks / Trade-offs

- **The guest image change makes every folder's next run cold** (five folders, about 2 GiB per
  machine of orphaned cuts). → It is one run, the cost is stated in the assertion, and
  `rookery snapshot gc --all` is the reclaim. There is no cheaper way to give a machine an account.
- **The initialising unit is a shell script of some length, and a script is not the subject under
  test.** → It is kept to the steps the claims need, every step is idempotent, and it is the folder's
  own payload the way `deployment/backend.py` is `tests/e2e/generated-secret/`'s.
- **A database's first start is slow, and a boot-ordering race would read as flakiness.** → The
  consumers wait on the server the way `tests/e2e/wired-pair/` does, with a bounded retry that the
  folder's text explains as cross-machine boot ordering rather than as flake insurance.
- **The folder proves the shape without a restart policy, so a crashed server stays dead.** → That
  is `openspec/changes/hold-a-long-running-daemon`, and this folder's restart scenario restarts the
  unit deliberately rather than asserting recovery from a crash.
- **A reader may take the flag form as the recommended way to configure a server.** → CLAUDE.md
  records why it is there and what removes the reason.
