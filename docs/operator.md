# Building a deployment, and putting it on machines

The library answers what a deployment is: `lib/` turns a declaration into a plan and a diagnostics
table, and realises nothing. The two realisers answer what one entry of that plan is on disk:
`image/` builds a portable-service image, `flakelet/` builds a service artifact the endpoint
registers. Neither builds a deployment, and neither copies anything anywhere.

Two directories close that distance, and this page is both of them:

- `operator/` builds a whole deployment. One function over a declaration and a statement of how each
  entry is realised, returning the plan, the interface a tool reads, and one artifact per placed
  entry.
- `cli/` is `planner`, the command an operator runs. It builds a deployment, writes the bytes of
  each generated value, copies each artifact to the machine the plan placed it on, activates it
  there, reports what each machine holds, and returns one entry to its previous generation.

## What a deployment build is

`operator/default.nix` exports one function:

```nix
operator.mkDeployment {
  inherit pkgs planner;

  args = {
    # exactly the argument mkPlan takes: instances, machines, and the
    # optional interfaces, sources, varsState and storeDir beside them
  };

  realise = {
    default.realiser = "flakelet";
    "watch:file" = {
      realiser = "image";
      profile = "strict";
    };
  };
}
```

| Argument | What it is |
| --- | --- |
| `pkgs` | the package set the artifacts are built with |
| `planner` | the library value, `nixplan.lib`, or `nixplan.mkLib { ... }` for a caller's own platform definitions |
| `args` | the deployment, exactly as [`README.md`](README.md#mkplan) documents it for `mkPlan` |
| `realise` | how each entry is realised, optional, `{ default.realiser = "flakelet"; }` by default |

The result is a link farm:

```
/nix/store/gvxcr0z2ms4ayqrlpi3602fb54mcq0kj-planner-deployment/
  plan.json                     the plan artifact
  manifest.json                 the interface below
  diagnostics.json              the rows
  diagnostics.txt               the same rows, rendered
  entries/idle-job-gamma        -> /nix/store/xq3...-flakelet-idle-job
  entries/issuer-api-alpha      -> /nix/store/xym...-flakelet-issuer-api
  entries/probe-client-beta     -> /nix/store/zsh...-flakelet-probe-client
```

A Nix caller reads the same four answers off `passthru` without a build: `plan`, `manifest`,
`diagnostics` and `entries`, the last being the derivation of each placed entry keyed by plan key.

Something has to supply `pkgs`, `planner` and `operator` itself. The five end-to-end folders here
are the worked examples, and each is a function of exactly those three. Shortened, with the folder's
own `interfaces/default.nix`, `instances.nix` and `machines.nix` imported beside it as `interfaces`,
`deployment` and `registry`:

```nix
{
  pkgs,
  planner,
  operator,
}:
{
  default = operator.mkDeployment {
    inherit pkgs planner;

    args = {
      inherit (deployment) instances;
      inherit (registry) machines;

      interfaces = {
        "interfaces/default.nix" = interfaces;
      };
    };
  };
}
```

That file is `tests/e2e/secret-delivery/deployment/default.nix`. `flake-module.nix` imports the
`operator/` directory, hands each folder `pkgs`, `planner` and `operator`, and exposes the result as
a package, so the complete file builds:

```bash
nix build .#planner-e2e-secret-delivery --no-link --print-out-paths
nix build .#planner-e2e-wired-pair          # one folder, two builds of one source
nix build .#planner-e2e-wired-pair-changed  # the second of them
```

## Getting all three from outside this repository

`planner` and `operator` are flake outputs of this repository, and neither is system-specific:
`lib` is the library, `operator` is the one attribute above, and both take the caller's own `pkgs`.
`mkLib` is beside them for a consumer whose own package set should elaborate the platform records
as well, which [`tooling.md`](tooling.md#what-this-flake-publishes) tables. The choice decides
every entry key: a platform record is a field of every placed entry and the key is a digest over
it, so `lib` keys a plan against the nixpkgs this flake pins and `mkLib { systems = ...; }` keys
the same deployment against the caller's. One of the two is the answer, never both at once. A
consumer therefore adds one input and wires three arguments.

The flake that does it is committed rather than described: `tests/e2e/newcomer/template/flake.nix`,
shown byte for byte by the root [README](../README.md#using-it-from-your-own-flake), which is the
one document the end-to-end path scan does not read and can therefore hold a file that imports a
sibling of its own. `tests/unit/layers.nix` compares the two texts, so an output renamed here moves
that document with it. Then:

```bash
nix build .                                          # the link farm above
nix run github:Qubasa/nixplan -- apply result        # or any built deployment directory
```

Nothing else is needed and no other output is an interface: a path inside this flake's source is
not one, and neither is anything under `tests/`. `tests/e2e/newcomer/` is that consumer flake run
as a test - a machine holding nothing but its template and this checkout's source locks the one
against the other, builds the deployment in its own store and applies it to the two machines the
template names. [`cluster.md`](cluster.md) describes the walk.

## The artifact name a plan key projects onto

A plan key is `<instance>:<service>@<machine>`. The artifact built for it is addressed by that key
with `:` and `@` replaced by `-`, under `entries/`:

```
issuer:api@alpha   ->  entries/issuer-api-alpha
watch:file@alpha   ->  entries/watch-file-alpha
```

The key is not the directory name, and the caller does not choose the name either
([design D3](../openspec/changes/apply-deployments-with-an-operator-command/design.md)):

| Approach | Why not |
| --- | --- |
| the key as the directory name | `@` and `:` are the two characters the key grammar splits on, so every consumer of the build would quote them |
| a name the caller chooses | that is the local convention each folder had, and a local convention cannot be generic |
| a projection plus a recorded mapping | one rule, and `manifest.json` carries the mapping as data |

The tool never reconstructs a name from a key. It reads the mapping, which is why the projection is
allowed to be the plain rule above. That rule is not injective: `a:b@c` and `a-b@c` both project
onto `a-b-c`, and a member name may carry a hyphen of its own. Two keys projecting onto one name is
therefore `operator-entry-name-collision`, an error row naming both keys, rather than one directory
silently overwriting the other.

## What `manifest.json` states

`manifest.json` is the whole interface between the evaluating side and a tool. A consumer applies a
build by reading `plan.json` and `manifest.json`, and evaluates no Nix.

```json
{
  "version": 1,
  "storeDir": "/nix/store",
  "entries": {
    "issuer:api@alpha": {
      "path": "entries/issuer-api-alpha",
      "realiser": "flakelet",
      "profile": null,
      "machine": "alpha",
      "address": "10.0.0.10",
      "units": [ "issuer-api-serve.service" ],
      "key": "sha256-<sixteen hex digits>"
    }
  },
  "values": {
    "issuer:vars/session": {
      "delivery": [ "alpha", "beta" ],
      "files": {
        "token": {
          "path": "/run/vars/issuer/session/token",
          "secrecy": "secret"
        }
      }
    }
  }
}
```

Per placed entry:

| Field | What it is |
| --- | --- |
| `path` | the artifact, relative to the build root, and `null` for an entry the reading realises into nothing. A consumer resolves it: the build is a farm of symlinks, and the path an activation names on the machine has to be the path the copy put there |
| `realiser` | `flakelet` or `image`, as the statement said |
| `profile` | the confinement profile of an image entry, `null` for a flakelet one |
| `machine` | the machine the plan placed the entry on |
| `address` | the address that machine's registry record declares, and `null` where it declares none. An address is read by the step that dials a machine and by no step that builds one, so the absence is recorded rather than the field omitted, and the build produces every artifact |
| `units` | the unit file names the entry declares, sorted, with the timer of a scheduled unit beside its service |
| `key` | the artifact's own identity digest, which is what the machine's endpoint stores for it as `settings_hash`. A report can therefore compare what a machine holds against what a build holds. The plan entry key stays in `plan.json`, which travels beside this file: it moves when any fact of the entry moves, including the machine's address, and no byte of the artifact need have changed |

Per value entry:

| Field | What it is |
| --- | --- |
| `delivery` | the machines that receive the value, which may be empty |
| `files` | each declared file by name, with the absolute `path` it lands at and its `secrecy` |
| `program` | the store path of the program that produces those files, as the plan records it. **Absent** where the generator declared none, and it is what tells the command which values it must be handed bytes for |

`storeDir` is the store the artifacts were built in, and `version` is `1`. Nothing here is derived
from the plan twice: the plan travels beside `manifest.json` and stays the single answer for
everything else.

## The realisation statement

Nothing in a plan entry says which realiser an entry wants, and nothing should: the same entry can
legitimately be either, which is what `tests/e2e/portable-image/` and `tests/e2e/wired-pair/`
demonstrate between them. `realise` states it instead, and `operator/read.nix` reads a statement by
plan key, then by the `<instance>:<service>` prefix of one, then by `default`:

```nix
realise = {
  default.realiser = "flakelet";
  "watch:file" = {
    realiser = "image";
    profile = "strict";
  };
  "issuer:api@alpha" = {
    realiser = "flakelet";
  };
};
```

Every field is resolved down those same three steps, so an entry naming its own realiser and no
profile takes the profile of the `default` statement, and no reader has to know which fields
inherit.

`flakelet` is the default because it is the realiser that needs no further fact: `flakelet.artifact`
takes the plan and the key and nothing else. A statement that names an entry and no realiser still
takes the default one, because what such a statement carries is the fact the default cannot. An
image needs a confinement profile, which no plan field records, so an `image` statement carrying no
`profile` is refused rather than defaulted. A realiser name nothing implements is refused naming the
two that exist.

The reading answers the whole statement, and it answers the statement crossed with the entry it is
about. Each of these is a row it produces, and every realiser refusal below one of them is
therefore reached only by a caller that never asked the reading:

| Row | What it means | The fix |
| --- | --- | --- |
| `operator-entry-name-collision` | two plan keys project onto one artifact name | rename one of the instances, services or machines |
| `operator-realiser-unknown` | the statement names a realiser other than `flakelet` or `image` | state one of those two for that key |
| `operator-image-profile-missing` | an `image` statement carries no `profile` | add one: `default`, `nonetwork`, `strict` or `trusted` |
| `operator-image-profile-unknown` | the profile stated is not one of those four | state one that exists |
| `operator-statement-names-nothing` | a statement key names neither a plan key nor a prefix of one | fix the key, or delete the statement |
| `operator-statement-not-a-record` | a statement is a bare value rather than a record | write `{ realiser = <realiser>; }` |
| `operator-plan-record-unclassified` | a plan record is none of the three shapes the reading knows | teach the reading the shape, or stop emitting the record |
| `operator-entry-realises-nothing` | the statement names an entry that declares no unit | remove it from `realise`, or declare a unit |
| `operator-entry-path-not-assembled` | the stated realiser runs no step that could assemble a host path the entry is shown | state `image`, or stop declaring the configuration file |
| `operator-entry-service-manager-mismatch` | the entry's machine runs another service manager | place it on a machine the realiser emits for |
| `operator-entry-name-refused` | the stated realiser's endpoint refuses a name the entry derives | rename the instance or the service |
| `operator-entry-access-denied` | a unit needs an access the stated profile denies | state a profile that allows it, or stop needing it |
| `operator-entry-machine-no-address` (warning) | the entry's machine record declares no address | declare an `address` before applying that entry |

A record carrying `delivery` is a generated value, one carrying `placement` is a service entry, and
one carrying neither is a machine record. Nothing is classified by the text of a key: `machine` is a
legal instance name and `vars/x` a legal member name. A placed entry that declares no unit is
realised into nothing - it is named in `manifest.json` with its machine and a `null` artifact, and
only a statement naming it is a refusal.

## Why the build layer raises

`lib/` never raises. Every check it makes is a diagnostics row, and one malformed declaration
becomes a row while the rest of the deployment is still read. The realisers raise, for a fact an
entry does not record. `operator/` raises for a third reason: a deployment the planner itself
called inapplicable.

`mkPlan` already answers `applicable`, and `render` already prints the table. `operator/read.nix`
adds its own rows to that table, and `operator/default.nix` realises no entry of a deployment whose
table carries an error. The build itself still runs: the tree holds `plan.json`,
`diagnostics.json` and `diagnostics.txt` whatever the table says, because a table nobody can read
is of no use to the deployment it describes. What it holds no artifact of is any entry of an
inapplicable deployment, and a caller asking for one through `passthru.entries.<key>` is refused
with the rendered table. Applicability is read from the rows: the tree carries no marker of its
own. A table carrying warnings and no error builds every entry the reading realises: a warning that
stopped a build would be an error.

```bash
built=$(nix build .#planner-e2e-wired-pair --no-link --print-out-paths)
jq -r '.[] | "\(.severity) \(.id) \(.subject)"' "$built/diagnostics.json"
```

The split inside the directory is the realisers' own. `operator/read.nix` is the whole reading -
which entries are placed, which realiser and profile each is stated to use, the name each key
projects onto, what `manifest.json` says, and every refusal - and it is a pure function of the plan
and the statement. `operator/default.nix` is derivations over that answer. The evaluating layer has
no `pkgs`, so `tests/unit/operator.nix` can assert the reading and can never assert a built
artifact. The bytes are what [`cluster.md`](cluster.md) is for.

## The command

```
planner plan     <target>
planner build    <target>
planner apply    <target> [--dry-run] [--values DIR] [--only KEY]... [--ssh-key PATH] [--user USER]
planner status   <target> [--only KEY]... [--ssh-key PATH] [--user USER]
planner rollback <target> --only KEY [--ssh-key PATH] [--user USER]
```

A `<target>` is either a built deployment directory or a flake reference. A directory is read as it
is found; a reference is built once per invocation with `nix build --no-link --print-out-paths`. A
reference that does not build is refused with the build's own output, which is where the rendered
diagnostics table appears. `--user` is `root` by default, and `--only` is repeatable.

A folder of *sources* is neither, and naming one is refused here rather than by nix: a deployment
directory is not a flake, so `nix` would read `tests/e2e/wired-pair` as a registry reference and
answer about commit hashes. Name the flake attribute that builds the folder
(`.#planner-e2e-wired-pair`) or the directory a build wrote.

Build the command, or run it out of the flake:

```bash
nix run .#planner -- --help                             # the five subcommands
nix build .#planner                                     # result/bin/planner
nix run .#planner -- build .#planner-e2e-secret-delivery
```

**`plan`** prints the deployment's plan as sorted JSON, which is the same document
[`plan.md`](plan.md) describes.

**`build`** prints the store path of the build, then a line per placed entry and a line per value
entry. This is the observed output of the third command above:

```
/nix/store/gvxcr0z2ms4ayqrlpi3602fb54mcq0kj-planner-deployment
idle:job@gamma flakelet gamma 10.0.0.12 /nix/store/xq3...-flakelet-idle-job [idle-job-mark.service]
issuer:api@alpha flakelet alpha 10.0.0.10 /nix/store/xym...-flakelet-issuer-api [issuer-api-serve.service]
probe:client@beta flakelet beta 10.0.0.11 /nix/store/zsh...-flakelet-probe-client [probe-client-fetch.service]
issuer:vars/ca delivered to [] files [ca.pub]
issuer:vars/session delivered to [alpha beta] files [token]
```

An entry line is the plan key, the realiser, the machine, the address, the artifact and the unit
files. The artifact column is the resolved store path, which is the path the copy puts on the
machine and the path the activation names there. `issuer:vars/ca` is delivered to no machine because
its generator is not deployed, and the line says so rather than leaving the value out.

After those lines comes the diagnostics table the build wrote, rendered as the planner renders it.
A build whose rows are all warnings prints them and exits zero; a build whose rows carry an error
prints the table and exits non-zero, because that refusal is the planner's own rather than a second
one the command invents.

**`apply`** prints one line per step, in the order the steps happened:

```
ordered against the read of <provider> by <consumer>
value <value key> <file> -> <user>@<address>:<path>
copy <plan key> <artifact store path> -> <user>@<address>
activate <plan key> (<realiser>) on <user>@<address>
  <the endpoint's own report, one indented line each>
```

The first line appears only for an edge a cycle forced the walk to contradict. A flakelet entry is
activated by the machine's own endpoint, `flakelet activate <name> <artifact>`; an image entry is
attached by the script the artifact itself carries, `bin/attach`.

**`apply --dry-run`** asks what a run would do. It makes every refusal a real run makes - the
planner's own table, a restriction naming an entry the plan does not carry, a value source that is
short of a declared file or carries a file nobody declared - and then prints the value writes, the
copies and the activations it would perform, in the order it would perform them, and contacts no
machine. What it does not print is the only thing missing: the indented lines are a machine's own
report, and asking for one is a dial. This is the observed output of a dry run of the deployment
`tests/e2e/newcomer/` builds, whose two machines this host cannot reach:

```
copy greeter:greet@alpha /nix/store/ld5...-flakelet-greeter-greet -> root@10.0.0.11
activate greeter:greet@alpha (flakelet) on root@10.0.0.11
copy greeter:greet@beta /nix/store/izw...-flakelet-greeter-greet -> root@10.0.0.12
activate greeter:greet@beta (flakelet) on root@10.0.0.12
```

The note that nothing was contacted goes to stderr, so the two runs stay comparable line by line on
stdout: `diff <(planner apply --dry-run <target>) <(planner apply <target>)` is the machine's own
reports and nothing else. What a machine currently holds is not a question a dry run answers, and
`status` is where it is asked.

**`status`** prints one line per entry, and asks rather than applies. A line is the machine's own
answer:

```
issuer:api@alpha flakelet generation 1 of path:/nix/store/6y1...-source?narHash=sha256-Xy0...
probe:client@beta flakelet generation 1 of path:/nix/store/6y1...-source?narHash=sha256-Zq4...
watch:file@alpha image running
```

Four answers are kept apart, because each one needs something different done about it:

| The line | What happened |
| --- | --- |
| the generation and the identity the endpoint stores | the endpoint answered, and the entry is there |
| `absent` | the endpoint answered and holds no entry under that name |
| `no endpoint on <machine>: <what it printed>` | the endpoint could not be run there |
| `unreachable: <machine> at <address> answered nothing` | the machine answered no connection |

`absent` is an endpoint's own answer and nothing else gives it: a machine that was never asked has
said nothing about the deployment, and printing absence on its behalf would tell an operator the
entries were never applied. An entry whose machine declares no address is reported as one the
command will not dial, naming the machine, rather than dialled and reported unreachable. An entry
whose last activation the endpoint recorded as failed carries that error on its line.

Each line is printed as it is known rather than after the last machine, so one machine's silence
costs one line and hides nobody else's answer. The command exits non-zero when any machine could
not be asked, and zero when every machine answered, whatever the answers were.

**`rollback`** takes exactly one `--only`, prints `rollback <key> on <user>@<address>` and then the
endpoint's own report. An image entry carries no generation to return to, so rolling one back is
refused naming the entry and its realiser.

**Where each subcommand runs.** `build` needs `nix` and runs anywhere. `apply`, `status` and
`rollback` reach machines over ssh, so they have to run where the deployment's addresses resolve.
That is one boundary rather than two commands: the machine layer here builds in the test process and
applies inside the cluster's network namespace, which [`cluster.md`](cluster.md) describes.

## Where the bytes of a generated value come from

A generated value's bytes are never in the plan and never in an artifact. A path in a plan is
deliverable; bytes in a plan are a leak. `apply --values <dir>` therefore reads them from a
directory the operator names:

```
values/
  issuer:vars/session/token
  nightly:vars/hostKey@beta/ssh_host_ed25519_key
```

The layout is `<dir>/<entry-key>/<file>`. An entry key carries a `/` of its own, so
`values/issuer:vars/session/token` is a real nested path and the directory is walked rather than
split. The required set is the declared files of every value entry whose delivery set is non-empty
**and which records no `program`**: bytes are needed for a file that will be written, a value
delivered to no machine is written nowhere, and a value naming a generator is produced and
delivered by the external tool rather than read from here. A source holding one of that tool's
files is refused naming the program.

The source is checked against the plan before anything is dialled. A file the plan declares that
the source does not hold is refused naming the entry and the file. A file a delivered value's own
directory holds that the value does not declare is refused, and every such file is named rather
than the first of them. A file under no delivered value's directory, a `README` or a `.gitignore`
beside them, is a claim about no value and is measured by nothing. What the source holds is
measured against the whole deployment even under `--only`, so a source that is right for a
deployment stays right for a restricted run of it.

Each file is written over ssh under `umask 077` and left at mode 0400, outside the store, at the
path the value entry records. Not `nix copy`: a store object is readable by every process on the
machine, which is the one property a generated secret cannot have.

Nothing in this repository generates those bytes. The directory is where a generator hands them
over, and `apply` cannot tell a minted secret from one an operator wrote by hand.

## The order `apply` walks

Both orderings come out of the plan, and the caller states neither.

1. **Values before units.** A unit whose environment names `/run/vars/<instance>/<generator>/<file>`
   reads it as soon as it is activated, so every value write happens before any activation.
2. **Provider before consumer.** `plan.<consumer>.reads.<slot>.entry` names the provider's own plan
   key, so the edges are already in the artifact. `dependsOn` is not that relation: a consumer's
   `dependsOn` carries `machine:<name>@<hash>`, which is key provenance rather than order. A slot
   the planner refused is absent from `reads`, so an absence is never an edge.

Per entry the artifact is copied first and activated second. An activation that had to resolve
anything would be activating something other than what was built.

Ties break by plan key sort order, so one deployment always walks one way. Two instances wiring each
other is a legal deployment - a capability's exports are a function of module and settings, never of
a wire - but its activation graph genuinely has no first element. The walk is over the strong
components of that graph: a component no entry outside it reads into is applied first, a component
of one entry is an entry with an order, and a component of more than one is a cycle. Its entries are
applied in plan key order, and the edges of that component pointing backwards in that order are the
ones the order contradicts. Every edge the command prints therefore lies on a cycle, and an entry
that merely reads into one keeps its order. Refusing would refuse a deployment the library considers
correct, and silence would leave a one-off startup failure unexplainable.

A broken cycle prints two kinds of line, before the first machine is dialled:

- `cycle of <key>, <key>` names every entry of the component the order was broken at. This is the
  line that tells a cycle from a provider an earlier decision left behind.
- `ordered against the read of <provider> by <consumer>`, one per contradicted edge, names the read
  the order could not honour. The consumer is activated before that provider, so its first fetch can
  fail once and the service manager restarts it when the provider comes up.

Neither line asks the operator for an action on a deployment whose cycle is intended: two services
that need each other are applied in a fixed order and settle. What the cycle line answers is whether
the cycle was intended at all, because the entries it names are the declarations to read.

A restricted run prints a third: `not applying <provider>, which <consumer> reads` names a read
whose provider the `--only` selection excludes. That read is no ordering constraint, an entry the run
does not apply being an entry that cannot be applied first, and the consumer is applied anyway,
against whatever its provider's machine already holds. A run of the whole deployment prints none of
these.

Every refusal the command can make from the plan, `manifest.json` and the value source happens
before the first machine is contacted: an inapplicable deployment, a `--only` naming a key the
deployment carries as neither an entry nor a value, a missing or unnamed value file, a machine with
no address. A run that has started is a run whose remaining failures belong to a machine.

## When a run breaks

A run stops at the first step a machine refuses. Each step's line is printed before that step is
attempted, so the last step line an interrupted run printed names the step that was running when it
ended, and the failure line after it names that step, the machine and what the machine said. Nothing
after the failed step is attempted: a broken run leaves one boundary rather than a set of them.

What the cluster then holds is a partial application. The machines the walk had already reached hold
the new artifact and run it, and every machine after the break holds what the previous run left. No
single machine is half applied, because each step is one ssh invocation that either completed on
that machine or did not.

The recovery is another `apply` of the same build and the same `--values` directory, not an undo and
not a resume of a recorded prefix. Undoing needs a generation that moves a whole run as one, and no
such generation exists: an endpoint counts generations per service, and an image entry has none at
all. A resume needs a record of what the run had done, and the command keeps none of its own - the
machines hold the state, and `status` asks them. A second run costs a comparison per step that
already happened:

- a value write rewrites the same bytes at the same path with the same mode;
- a copy is `nix copy` of a closure the machine may already hold, and a store path already valid on
  the target is not sent again;
- a flakelet activation of an unchanged artifact is the endpoint's own no-op, and the generation
  does not move;
- an image attachment is asked about first, and an image the machine already holds attached is
  reported as already attached instead of attached a second time.

A narrower second run is `--only`, which bounds the machines contacted as well as the entries
applied: the machines of the entries it names, plus the delivery set of a value entry it names
directly, and no others. A machine that receives a value only because some unselected entry reads it
is not dialled at all.

## Reaching a machine

The command bounds silence and does not bound work. It appends these to the `NIX_SSHOPTS` its caller
set, and `nix copy` inherits the same string:

```
-o BatchMode=yes -o ConnectTimeout=10 -o ServerAliveInterval=30 -o ServerAliveCountMax=3
```

`BatchMode` asks nothing of a terminal nobody is watching, `ConnectTimeout` gives up on a machine
that does not answer a connection, and the server-alive pair ends a connection that has stopped
carrying bytes. A step that keeps making progress is never interrupted by the command: a first
`nix copy` onto a fresh machine legitimately runs for minutes, and every wall-clock bound on a step
breaks a real deployment on a slow link. They are appended rather than prepended because ssh uses
the first value it is given for an option, so an operator who states `ConnectTimeout` in
`NIX_SSHOPTS` keeps their own.

A step the machine refuses is reported as the command's own refusal, naming the entry, the machine
and what the machine printed. The argv is no part of that message: a value write carries the bytes
of a secret.

## Two directories, one role

`operator/` and `cli/` are one role and two kinds of thing
([design D13](../openspec/changes/apply-deployments-with-an-operator-command/design.md)):

| | `operator/` | `cli/` |
| --- | --- | --- |
| language | Nix | Python |
| what it is | an evaluation | a program |
| who reads it | `mkDeployment` callers, and `tests/unit/operator.nix` | an operator, and `tests/e2e/` |
| closure | the artifacts it builds | an interpreter, `nix` and `openssh` |
| checked by | `nix-unit` | `mypy --strict`, `ruff` and pytest |

Merging them would put a Python file under a directory the unit layer imports, and put a store
reference to an interpreter in the closure of the value `tests/unit/operator.nix` evaluates. It
would also make the two checks one: the reading is asserted by evaluating it, and the command is
asserted by handing it a recorder in place of a process table and reading the argv it produced.

Nothing in `cli/` imports anything under `operator/`, `lib/` or `tests/`. Its inputs are a built
directory, a flake reference and a value source, and what a deployment is it learns from
`manifest.json`. That is what keeps the command replaceable: another tool that reads those two
documents applies the same build.

The command's flake wiring is `cli/flake-module.nix`, imported by `flake.nix` beside the root
module and `devshells.nix`. It owns `packages.planner`, `apps.planner` and
`packages.planner-src`, the source root the harness imports the command's pure half from. The
root module reads `PLANNER_CLI` and `PLANNER_CLI_SRC` off those two package attributes rather than
constructing either, so a rename cannot leave the app and the test environment disagreeing.
