# Generated values and the tool that produces them

The fourth realiser over one unchanged plan. `secrets/read.nix` reads a plan as a configuration for
the external secret generator - NixOS vars,
[nixpkgs PR #547171](https://github.com/NixOS/nixpkgs/pull/547171), at revision `e6af758` - and
`secrets/backend.nix` renders the one step of that tool's contract a plan is needed for. Nothing
upstream changes, and the planner still neither runs nor reads a generator.

```bash
nix build .#planner-e2e-generated-secret-generation   # the configuration, the names and the plan expression
nix build .#planner-e2e-generated-secret              # that deployment: the plan, the manifest, the artifacts
nix build .#checks.x86_64-linux.planner-tests         # the reading, per case, in tests/unit/secrets.nix
nix run .#planner-e2e generated-secret                # three machines, a real generator, a real backend
```

## Two halves, and what each one knows

This library derives which machine receives which value and why. A generated value is an entry of
its own, its `delivery` list is the machines that receive the bytes, and `deliveryDerivedFrom`
records what put each of them there. The library produces no bytes: `varsState` is an argument, and
until this composition existed every suite and every end-to-end folder filled it in by hand.

The external tool is the other half. It has generator scripts, dependency ordering, prompts,
storage backends and garbage collection, and no machine dimension at all: its unit of work is one
configuration, and its own module text concedes that a backend spanning machines has to scope
`list` itself or the command line deletes the other machines' files.

| this library | nixos-secrets at `e6af758` |
| --- | --- |
| `varsState.<key>.<file> = { present, content }` | `exists`, exit 0 or 42, and `get`, bytes to `$out` |
| `plan.<key>.delivery` and `.files.<f>.path` | `deploy.remote`, given a file list and nothing else |
| a plan | `_type = "secrets-configuration"`, which `--json` consumes without evaluating Nix |

Each row is a fact one side records and the other has no vocabulary for. `secrets/read.nix` reads
the left column into the right one; `secrets/backend.nix` supplies the machine dimension the right
column has no field for.

## The declaration

A generator gains the one field it was missing: the program that produces it.

```nix
vars.token = {
  files."secret" = { secrecy = "secret"; };
  files."fingerprint" = { secrecy = "public"; };
  per = "instance";
  reads = [ "root" ];
  program = derive.drvPath;
};
```

The planner records that store path as a literal string and does nothing else with it. It runs no
program, reads no program and resolves no program, here or anywhere else. A declaration that is not
exactly one store path is a `vars-program-malformed` row saying the same thing from the other side:
the one thing a consumer does with the field is hand it to a tool that resolves store paths.
Omitting the field stays valid and produces no row. The library described values before anything
could produce them, and the reader that needs a program is what refuses.

The external contract wants a derivation, `^/nix/store/.+\.drv$`, so a deployment declares `drvPath`
rather than an output path. That is a string a pure evaluation can produce, which keeps the plan
free of derivations.

The program is **no closure root**, and it is not a mention the closure scan holds against a
declared closure either. A generator runs where the plan is read, on the machine holding the values
and never on one receiving them, and making it a root would send every deployment's generators to
every machine that receives one of their outputs. What the entry carries and how the field
enters the entry's key is in [plan.md](plan.md); how it is written is in
[authoring.md](authoring.md#vars).

## The name projection

A plan key is `<instance>:vars/<generator>` or `<instance>:vars/<generator>@<machine>`, and the
tool's `safe-name` is `^[a-zA-Z0-9:_\.-]+$`: a colon is admitted, `/` and `@` are not. The
projection therefore joins on a colon, `<instance>:<generator>` for a per-instance value and
`<instance>:<generator>:<machine>` for a per-machine one, so two machines' values of one generator
stay two stored values.

Deliberately not a hash of the key. These names are what an operator reads in the tool's own
listing, in a backend's storage layout and in a prompt about deleting something, and a hash makes
each of those unattributable while hiding the collision the projection exists to refuse.

The reading raises rather than returning a row, as the image and flakelet readings do, and every
refusal names both sides:

| Refused | What the refusal names |
| --- | --- |
| two keys projecting onto one name | both keys and the one name, because one would overwrite the other's stored bytes |
| a component carrying `:` | the key, the role of the component and its value: a name joined on that character could not be read back |
| a component outside `[a-zA-Z0-9_.-]+` | the same, plus the characters the tool admits |
| an entry recording no `program` | the entry and the field, because the tool runs one program per stored value |

A file name is not projected, so it keeps the colon the tool admits; the one name it may not carry
is `.nixos-secrets-metadata`, which the tool keeps for its own record. A value's `reads` become the
entry's `dependencies` under the same projection, so the topological order the tool walks is the
order the planner already resolved and checked for cycles.

`collisionsOf` returns the colliding pairs as a value, so what a refusal is about can be read
without catching it.

## The rendered deploy step

The contract hands `deploy.remote` a list of `<name> <file>` pairs on standard input and nothing
else: no machine, no address, no path. `secrets/backend.nix` renders that step from the plan.
Every file of every deployed value becomes one `case` branch, and every machine of that value's
delivery set becomes one `deliver` line inside it, carrying the address that machine's entry records
and the path the plan fixed. A pair no branch names fails the step naming the pair: the
configuration and the script would have been rendered from two different plans. A delivery target
the plan gives no address for is refused while the script is rendered, naming the value and the
machine.

The script carries no bytes. `deliver` fetches each file from the store backend's own `get` program
at run time, into a temporary file, and pipes it over `ssh` into a file written under `umask 077`
and moved into place. `$PLANNER_SECRETS_SSH_OPTS` reaches `ssh` unquoted, and the word splitting is
the point: the contract says a deploy step takes whatever else it needs from the environment, and
reaching a guest whose host key nobody has accepted yet is exactly that.

**The path stays this library's.** The contract carries no path at all: a store entry's file record
is one boolean, `deploy`, and `path` exists only as a NixOS option a backend sets, which a
configuration passed with `--json` never reaches. The rendered step is therefore the only thing that
ever states a path, and the path it states is `/run/vars/<instance>/<generator>/<file>`, the one the
plan fixed. The external side never learns a path and never has to agree about one.

## Provenance

The tool records a uuid per generation and nothing about which declaration a stored value came from.
An interrupted or failed run therefore leaves a dependency new and its consumer derived from the old
one, and the next invocation reports success.

`tests/e2e/generation.py` writes the plan key of each stored value beside the state it read, and
compares before anything is delivered. A disagreement refuses the run, naming the value and both
identities and printing the one command that regenerates it. A stored value with no recorded
identity is a disagreement rather than a match: the tool regenerates conservatively, so a value
stored before the record existed may have come from any declaration.

The identity is the plan key the planner already computes over the declaration, which is why the
plan gains no field for this. Staleness is a fact about bytes on disk, which the library cannot
observe, and a `varsState.<key>.from` row would be the planner restating a claim its caller made.

## The pinned revision and the guard

`secrets/read.nix` is written against one revision of one file:

| Recorded | Value |
| --- | --- |
| revision | `e6af758a5745ac4adef763deb0f1771cec58c461` |
| file | `pkgs/by-name/ni/nixos-secrets/src/nixos_secrets/secrets-config.schema.json` |
| digest | `sha256:44408bcdca7e59af6f9f05e4fe30ef6aa6df004f97e3df68d8e8d2062a4876cf` |

The tool itself is resolved at run time from `$NIXOS_SECRETS_FLAKE`, built with `--refresh`, exactly
as `tests/e2e/runner.py` resolves rookery and for the same reason: a branch reference otherwise
resolves through nix's tarball TTL and a run silently uses whatever was fetched last. It is not a
flake input, because the reference is an unmerged branch of a fork and pinning it in `flake.lock`
would make every consumer of this repository fetch it.

The guard in `tests/e2e/generation.py` digests the schema the resolved tool publishes and compares
it with the recorded one. A difference fails, naming `secrets/read.nix`, the recorded revision and
the upstream file to diff, so a merged and renamed API cannot be silently outlived. A tool that
cannot be resolved at all, or one carrying no schema, does not fail it: an unreadable signal is not
evidence that the contract moved, and the run that needed the tool skips with the reference named.

## What this composition inherits

Each of these is a defect of the external tool at the pinned revision, read in its own review. None
of them is fixed here, and each one is out of reach for a different mechanical reason.

| Upstream defect | Review | Why it is unreachable here |
| --- | --- | --- |
| garbage collection keyed on `networking.hostName`, so two checkouts collide | `r3820900132` | no `collect-garbage` is ever invoked, and one invocation covers the whole cluster rather than one machine at a time |
| `--file` and `--flake` derive different secret paths for one declaration | `r3820972963` | a `--json` configuration has no `networking.hostName` to disagree about, and this reading emits one |
| no rollback, so an interrupted run leaves a derived value stale and reports success | `r3821143332` | the driver compares provenance before delivering and refuses, naming the value |
| bubblewrap needs user namespaces a host may deny, and dies with no message | `r3821015145` | the driver probes the sandbox once and skips the folder naming the missing kernel feature |
| a prompt hangs a run, and a crash can leave terminal echo off | `r3821062507`, `r3821148209` | a store entry's `prompts` is always `{}`, because the library has no prompt vocabulary, and the folder declares a prompt backend that fails on any invocation |

A prompt being asked at all is therefore a defect rather than a value, and it becomes a named
failure instead of a wedged run.

## The end-to-end folder

`tests/e2e/generated-secret/` is three machines - `alpha` at `10.0.0.10`, `beta` at `10.0.0.11` and
`gamma` at `10.0.0.12` - and one instance whose two generators are produced by a real program and
stored by a real backend. `issuer:api` on `alpha` declares `root`, one secret file, and `token`,
which reads `root` and declares a secret file and a public one; `probe:client` on `beta` declares a
read of the secret export, which is what puts `beta` in that value's delivery set; the instance on
`gamma` declares neither a generator nor a read, so `gamma` receives none of it. The projected names
are `issuer:root` and `issuer:token`.

The folder builds its plan twice, and that is a property of the library rather than of the test. A
plan is a function of `varsState`, so a plan carrying generated bytes cannot be a build artifact of
a run that has generated nothing yet. `tests/e2e/generated-secret/deployment/args.nix` is the
deployment on its own - `{ planner, packages, varsState }` in, arguments out - and
`tests/e2e/generated-secret/deployment/default.nix` calls it against a declared state, every file
present and no bytes, so that the unit files and the `SecretsConfiguration` are a function of the
declaration alone. `operator.mkGeneration` writes the second evaluation out beside the
configuration as `plan.nix`, and `tests/e2e/generated-secret/test_generated_secret.py` evaluates
that file at run time against the state the backend actually answered. The second plan is the one
every assertion reads, and what it evaluates is the copy of `args.nix` inside the built farm rather
than the working tree, so the two evaluations are of one text.

At the pinned revision the tool accepts what this reading emits: its own `evaluate --json`
validates the configuration against the schema above, `generate` runs both of the folder's programs
in bubblewrap and stores their output through the `age` backend, and the plan re-evaluated from the
state read back carries the public file's bytes with an empty diagnostics table.

### A deviation from design.md D9

D9 of
[design.md](../openspec/changes/generate-values-with-nixos-secrets/design.md)
says the folder uses the PR's own example `age` backend. It does not: it builds its own, at
`tests/e2e/generated-secret/deployment/backend.py`. The reason is mechanical rather than a judgement about the
example. The configuration has to carry a build-time `.drv` path for every backend program, and the
example backend lives in the NixOS module tree of a branch that is resolved at run time, so no
derivation path of it exists at the time the configuration is written. What the folder proves is the
composition, not the backend.

The hazard D9 records is unreachable either way: the storage path is the run's own state root, so
two runs cannot collide, and nothing invokes `collect-garbage`.
