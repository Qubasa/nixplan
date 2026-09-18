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
| `signing` | `{ privateKey, certificate }`, the two paths a user-scope image's roothash is signed with, optional and `null` by default. One key per operator rather than per entry, an argument of the build alone: no plan field, no field of the reading, no field of `manifest.json` and no byte of an artifact carries it, so rotating it re-keys nothing. A user-scope image built without it is refused naming the entry and this argument, for the reason [root at provision time](#root-at-provision-time-never-at-deploy-time) states |

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

Beside those, one `machines/<name>` link per machine a delivered value reaches whose registry
record declares a seal recipient, each pointing at that machine's own `planner-unseal-<name>` farm
of `bin/unseal`, `bin/check` and `planner-unseal.service` -
[what a machine does with a value after a reboot](#what-a-machine-does-with-a-value-after-a-reboot)
states what it does and what installs it. A machine is addressed by its own name here, no projection
being needed: a machine name carrying a key separator is refused before any key exists, and machine
names are unique in the registry, so no two of them can claim one link.

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
([design D3](../openspec/changes/archive/2026-09-16-apply-deployments-with-an-operator-command/design.md)):

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
  "version": 3,
  "storeDir": "/nix/store",
  "realisers": {
    "image": { "scopes": [ "system", "user" ] },
    "flakelet": { "scopes": [ "system" ] }
  },
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
          "secrecy": "secret",
          "owner": "root", "group": "root", "mode": "0400",
          "sealed": "/var/lib/planner/sealed/issuer/session/token.age"
        }
      }
    }
  },
  "machines": {
    "alpha": { "sealed": true, "scope": "system", "path": "machines/alpha" },
    "beta": { "sealed": false, "scope": "system" }
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
| `key` | the artifact's own identity digest, which is what the machine's endpoint stores for it as `settings_hash` and what an image's file name carries. The command reads it and compares it against what the machine answers, so a record publishing none for a placed entry is refused. The plan entry key stays in `plan.json`, which travels beside this file: it moves when any fact of the entry moves, including the machine's address, and no byte of the artifact need have changed |

Per value entry:

| Field | What it is |
| --- | --- |
| `delivery` | the machines that receive the value, which may be empty |
| `files` | each declared file by name: the absolute `path` it lands at, its `secrecy`, the `owner`, `group` and `mode` a write sets there, and the `sealed` path a machine that seals keeps its copy at. The sealed path is a function of that file's own `path` and is published for every file, whatever the machines of the delivery set declare, because nothing about a machine enters it. It is derived here rather than read off the plan: nothing in `cli/` imports the library that derives it, and a field on the plan's own file record would re-key every generated value in every deployment for a path that record already carries |
| `program` | the store path of the program that produces those files, as the plan records it. **Absent** where the generator declared none, and it is what tells the command which values it must be handed bytes for |

Per machine a delivered value reaches:

| Field | What it is |
| --- | --- |
| `sealed` | whether that machine's copies of its values are sealed, which is whether its registry record declares a recipient. A machine of a delivery set is in this table either way, so a tool tells a machine that seals from one that does not without reading the plan |
| `scope` | the scope of the service manager the unsealing unit is installed into, `system` or `user`, which is the machine's own scope |
| `path` | the artifact that opens that machine's copies, relative to the build root. Present only where that machine's values are sealed, and absent where they are not |

The machine table is there whether or not it holds a machine, so a deployment that delivers no
value is not read as a record written before the table existed. It does not restate the recipient
the copies are sealed to: the plan's own `machine:<name>` record carries that, and a second copy
here would be a second answer a stale build could disagree with.

`storeDir` is the store the artifacts were built in, and `version` is `3`. A record stating an
earlier version is refused by it rather than read, and no reading of two shapes exists: a reader of
the previous shape would take a record with no machine table for a fleet whose machines seal
nothing, which is the silent failure the table is there to prevent. `realisers` is every
realiser the reading knows, keyed by name, each carrying the `scopes` it realises, which the
realiser publishes rather than the record restating: a tool reads it to know which scope a
realiser's steps on a machine may be addressed to. The reading crosses the same list against each
entry's machine scope, so an entry in this record is an entry whose stated realiser admits the
scope of the machine it is placed on. Nothing here is derived from the plan twice: the plan travels
beside `manifest.json` and stays the single answer for everything else.

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
| `operator-entry-path-not-installable` | the stated realiser binds a store object, and a configuration file the entry is shown states a record a store object does not carry | state the store's own record on that file, or state `image` for that key |
| `operator-entry-service-manager-mismatch` | the entry's machine runs another service manager | place it on a machine the realiser emits for |
| `operator-entry-scope-unsupported` | the entry's machine declares a scope the stated realiser does not publish, flakelet realising the system scope alone | state `image` for that key, or place the entry on a machine whose scope the realiser admits |
| `operator-entry-name-refused` | the stated realiser's endpoint refuses a name the entry derives | rename the instance or the service |
| `operator-entry-access-denied` | a unit needs an access the stated profile denies | state a profile that allows it, or stop needing it |
| `operator-entry-value-unaccounted` | a declared read names a generated value's path this plan delivers to no machine of that entry | inspect the value entry that declares the path and the placements of the reading entry, and replan |

A record carrying `delivery` is a generated value, one carrying `placement` is a service entry, and
one carrying neither is a machine record. Nothing is classified by the text of a key: `machine` is a
legal instance name and `vars/x` a legal member name. A placed entry that declares no unit is
realised into nothing - it is named in `manifest.json` with its machine and no `path`, the key is
omitted rather than stated as `null`, and only a statement naming it is a refusal. A command that
needs an artifact for such an entry refuses naming that entry, and one that does not proceeds.

## Which values an entry is shown

An entry is shown the generated values its own declaration produces and the ones its declared reads
name, deployed, and nothing else. The two halves are one list with one record per path, so a value
two reads of one entry name, or one an entry both generates and reads, is one record and one bind.
Every reading about a shown value asks that one list - the host paths the image carries, the denial
the confinement profile imposes, the reference paths the declared closure is checked against, and
the table the attachment describes. A path a unit is shown is therefore a path the refusals
reasoned about.

The join is by the path a read record already carries. A read records the value's path and its
secrecy and nothing else, which is deliberate: `reads` is in an entry's key input, so a peer's
ownership or mode recorded there would re-key every consumer the moment the value's own record
moved. Who may open the file stays the value entry's answer, looked up by that path while the
entry is read.

A shown path the plan's own value records account for no delivered bytes at - a read naming a value
the plan delivers to another machine, or a path no value record carries at all - is
`operator-entry-value-unaccounted`, and it refuses the deployment naming the entry, the slot and
the path. An undeployed value is a different answer: it is shown at no path, and the planner has
already said so with `slot-reads-undeployed-value`.

The consequence for a running fleet is one-time and visible. A consumer of a peer's value is shown
a host path it was not shown before, so its version digest moves: the first apply after this change
replaces those images and writes one new flakelet generation for each such entry, and the next
reports nothing changed. No value is rewritten by it, the bytes being on those machines already.

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
planner apply    <target> [--dry-run] [--retire] [--values DIR] [--only KEY]... [--ssh-key PATH] [--user USER]
planner status   <target> [--only KEY]... [--ssh-key PATH] [--user USER]
planner rollback <target> --only KEY [--ssh-key PATH] [--user USER]
```

A `<target>` is either a built deployment directory or a flake reference. A directory is read as it
is found; a reference is built once per invocation with `nix build --no-link --print-out-paths`. A
reference that does not build is refused with the build's own output, which is where the rendered
diagnostics table appears. `--user` is `root` by default, `--only` is repeatable, and `--retire` is
a flag.

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
<machine> holds <identity>, which this build does not name
retire <identity> on <user>@<address> (no state deleted)
  <what the endpoint reported about what it kept>
unsealer <machine> <artifact store path> -> <user>@<address>
unseal <machine> on <user>@<address>
  changed
sealed <value key> <file> -> <user>@<address>:<sealed path>
  sealed
value <value key> <file> -> <user>@<address>:<path> (<owner>:<group> <mode>)
  changed
copy <plan key> <artifact store path> -> <user>@<address>
activate <plan key> (<realiser>) on <user>@<address>
  <the endpoint's own report, one indented line each>
restart <plan key> for <value key> on <machine> at <user>@<address>
```

The first line appears only for an edge a cycle forced the walk to contradict. A flakelet entry is
activated by the machine's own endpoint, `flakelet activate <name> <artifact>`; an image entry is
attached by the script the artifact itself carries, `bin/attach`. No entry is skipped for being
present: the machine's own script decides what to do, and the indented lines under an activation are
that decision - `assembled <path>`, `replaced <image>`, `attached <image>`, `started <unit>`,
`reloaded <unit>` or `nothing changed`.

The holds line is the announcement every apply makes, whether or not it was asked to act on it: each
machine of the selection is asked what it holds, and every holding the build being applied names no
entry for is printed with the cycle lines, before the first step. Without `--retire` the line carries
`; not retired`, no step follows it and the run goes on to apply the entries the build does name,
which makes a plain apply the preview of one taken with the flag. A holding is named only where the
deployment record publishes, for the realiser that would have put it there, what a machine's own
answer names that realiser's holdings by, so a service the machine's own configuration declares and
an image another tool attached are neither announced nor retired.

**`apply --retire`** takes the retirement, one `retire` step per announced holding. The step is the
endpoint's own removal verb over the name the machine answered with: `flakelet remove <name>` for a
flakelet entry, which stops it, unlinks its units, drops its registration and keeps and lists its
state folders, never `flakelet remove --purge`, which is the flag that empties them; and
`portablectl detach --now <name>` for an image, `--now` stopping the units before it unlinks them, so
the step needs no unit list of its own and cannot stop the wrong ones. The retirement is asked for
rather than implied because it stops a running service, and a deployment one person edits is applied
by another.

A retirement deletes no state. No state directory, no delivered value, no host path a unit was shown
and no file staged for one is removed, and the step line says so and carries whatever the endpoint
itself reported about what it kept. A deployment declares no account and no state of its own, so
bytes on a machine that outlive an entry are the machine's, and deleting them is an operator's
decision this command does not take.

A retirement also runs no script out of the retired entry's own artifact. That artifact belongs to a
build this run is not applying: the run cannot name its path, and nothing on the machine roots it
against a collection, so a step that needed it would fail exactly where it is needed. The
`bin/detach` an image artifact carries is unaffected by that and stays the artifact's own contract,
which is what an operator runs by hand.

A value write says `changed` or `unchanged` under its own step, which is the machine comparing the
bytes it holds against the ones being written. Neither the bytes nor a digest of them is printed:
what is reported is that the file moved, never what it moved to.

The two `unseal` steps come before the first value written to their machine, and a run takes them
for exactly the machines it writes a value to whose record says their values are sealed: a run that
writes no value installs no unsealer, and a restricted run contacts no machine it would not have
contacted anyway. `unsealer` is the same store-to-store copy an entry's artifact is sent with, and
`unseal` installs the unit into the manager the machine's scope names - the system manager, or the
account's own on a user-scope machine - and answers `changed` or `unchanged`, the way a value write
and an activation do.

A `sealed` step writes the copy the machine opens for itself at the next boot, immediately before
the `value ` step of the same file. The bytes are sealed in the process that read the value source,
where the plaintext already is, and the ciphertext travels on that step's own input stream. No
argument vector on either host carries a byte of a value, sealed or plain; the recipient is not a
value but one public word off the plan's `machine:<name>` record, and it stands in a vector the way
a path or an address does. The `value ` line, the record it reads and its `changed` or `unchanged`
answer are untouched, and the new line is prefixed differently, so a log filtered for `value ` or
`restart ` reads what it read before.

A `sealed` step has no `unchanged` answer, and the absence is the honest one: age draws a fresh
ephemeral key per file, so two sealings of one file differ and a comparison of seals would say
nothing. The copy is rewritten on every apply, whether the bytes moved or not, and whether they
moved stays the plaintext's answer - an apply in which no plaintext moved restarts nothing on the
strength of a rewritten seal.

The program that seals is the one the command's own wrapper names, `PLANNER_AGE`, read off the
module's own attributes the way `PLANNER_CLI` is, so what a run seals with is the build's answer and
not the caller's `PATH`. A run whose record says a machine's values are sealed and whose
`PLANNER_AGE` names no program refuses before the first machine is contacted, naming the program it
could not run and the machines it would have sealed for. A machine whose record says its values are
not sealed is written to as it was before any of this: one step per file, the plaintext, and no
second file.

A `restart` step is the last thing a run does, and only for a value whose bytes moved. Its subject is
the entry that *read* the value, which is where a stale process is: the units of that entry are
restarted if they are running, and a unit an operator stopped stays stopped. The whole entry is
restarted rather than a named unit, because the plan says which entry reads a value and not which of
its units opens the file.

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
`status` is where it is asked. A dry run therefore names no holding and takes no retirement,
`--retire` included: naming one means asking a machine, and a line built out of the plan instead
would be a line no machine said.

**`status`** prints one line per entry, and asks rather than applies. A line is the machine's own
answer:

```
issuer:api@alpha flakelet generation 1 of plan:issuer:api@alpha runs this build's units
probe:client@beta flakelet generation 1 of plan:probe:client@beta runs units this build did not produce
watch:file@alpha image running current
```

Four answers are kept apart, because each one needs something different done about it:

| The line | The `reached` field | What happened |
| --- | --- | --- |
| the generation and the identity the endpoint stores | `answered` | the endpoint answered, and the entry is there |
| `absent` | `absent` | the endpoint answered and holds no entry under that name |
| `no endpoint on <machine>: <what it printed>` | `no-endpoint` | the endpoint could not be run there |
| `unreachable: <machine> at <address> answered nothing` | `unreachable` | the machine answered no connection |

Every one of those lines is the rendering of one record, and the record is what the library
function returns. `report.status` answers one record per question it asked - one per entry, one per
value delivered to a machine, one per holding the build names no entry for - beside the lines and
the machines it could not ask, and `report.lines_of` is the one function every line comes out of,
the applying run's holding line included. A program reads a field; it never matches a word of a
sentence. The entry record carries the plan key, the machine, the realiser and the address, how the
machine was reached, what it printed where an answer carries that, the generation and the locked url
a flakelet endpoint reports, which of the three answers the unit comparison made, the identity the
machine holds beside the one the build published, the word the machine's own tool printed and the
one its listing gave that image, each configuration path whose bytes disagree, and the error the
endpoint recorded. A field the reading did not compute is absent rather than empty, so an
unreachable machine says nothing about an identity. The value record carries the value key, the
machine, whether every declared path is there and the machine's own verdict on the sealed copy; the
holding record carries the holding the machine answered and the machine it was asked of.

Staleness is a field of the record and still never an exit status. A report whose machines all
answered exits zero however stale their answers are - an identity the build did not publish, a
value a machine lost, a holding the build names no entry for - because changing what a machine
holds is `apply`'s work.

`absent` is an endpoint's own answer and nothing else gives it: a machine that was never asked has
said nothing about the deployment, and printing absence on its behalf would tell an operator the
entries were never applied. An entry whose machine declares no address is reported as one the
command will not dial, naming the machine, rather than dialled and reported unreachable. An entry
whose last activation the endpoint recorded as failed carries that error on its line.

An answered line then says whether the machine holds what this build published. Two machines answer
that question with two different facts, so there are two vocabularies and neither borrows the
other's word:

| The clause | What it compared |
| --- | --- |
| `current` | the identity the machine names is the `key` the record published for that entry |
| `holds <identity>, built <identity>` | it names another one: the machine is on an older build, and both are printed |
| `holds this build's image, <path> <word>` | the image matches and a configuration file beside it does not |
| `runs this build's units` | the endpoint names no identity, and the unit files it runs are the artifact's |
| `runs units this build did not produce` | the same comparison, disagreeing |
| `reports nothing to compare` | the endpoint named neither, so nothing was compared |

An image's version digest excludes the bytes of a configuration file on purpose, so identity
equality is evidence about the image and about nothing beside it. The artifact's own `bin/check`
answers the other half - what the machine holds at each path the entry is shown, against what this
build would assemble there - and the word it prints for a path that disagrees is what the line
carries. A file whose bytes are on the machine is `current` and says nothing.

An image names what it holds, because the image's file name carries the digest and
`portablectl list` prints it. A flakelet endpoint stores that digest in the generation it keeps and
reports the unit files instead, which are files of the artifact the build produced, so the
comparison is the narrower one and the words say so. It does not see an edit that moves the
closure, a host path, the service manager or the platform without moving a byte of any unit text -
in that case the machine really does run this build's units, and `current` would be the false
sentence rather than the missing one.

Each line is printed as it is known rather than after the last machine, so one machine's silence
costs one line and hides nobody else's answer. The command exits non-zero when any machine could
not be asked, and zero when every machine answered, whatever the answers were - a stale fleet is a
fleet that answered, and what to do about it is `apply`'s work. An apply that stopped half way is
therefore readable: the entries the run reached say they run this build and the ones it did not
reach say they do not.

After the entry lines come the value lines: one per value a machine is delivered and does not hold,
and three more about the copy a machine would put it back from.

```
value issuer:vars/session missing on beta
value issuer:vars/session sealed copy does not open on beta
value issuer:vars/session has no sealed copy on beta
gamma holds no unsealer, so its sealed copies were not checked
```

Each machine is asked once, about every path delivered to it and every sealed copy of one, and only
whether each path is there and whether each copy opens. What a held file contains is never asked:
reading a secret to report on it is not something this command does, and nothing about the bytes of
a copy, sealed or plain, is printed or transferred either. A value of more than one file is one line
however many of them are gone, because the subject is the value and not its files.

Values live under `/run`, so a reboot empties every one of them, and what happens after that is
what the second and third lines are about. A machine whose record says its values are sealed puts
them back itself before the entries that read them start, so a rebooted machine holding copies it
can open is reported with no missing value at all. A copy that does not open and a value with no
copy are the two conditions under which that will not happen, and an operator reads them before the
reboot that would have proved them: the verdict is the machine's own, its `bin/check` asking
whether each copy opens with the identity file the machine holds, which is the only question a
native seal can be answered about. The fourth line is a machine the record says seals and which has
never been applied to, so it carries no unsealer to ask - its copies were not checked, rather than
reported as opening or as failing to open.

For a machine whose record says its values are not sealed, a reboot is what it always was: the
entry is back - the endpoint brings its units up again - and the value lines are the only thing
that says the machine is not where the deployment left it. A second `apply` writes the values and
restarts their readers. None of these lines changes the exit status, for the reason a stale entry
costs none: a machine that answered is not a machine that could not be asked, and putting a value
back is `apply`'s work.

Beside those four answers a report says a fifth thing, after the value lines and per machine rather
than per entry: every holding the machine runs that this build names no entry for.

```
<machine> holds <identity>, which this build does not name
```

The identity is the machine's own answer and never one the command reconstructed. A flakelet
endpoint reports the identity the artifact registered, which is `plan:` followed by the plan key of
the entry it was built for, so the line names that key. An image names a file instead, composed of
the artifact's own name, a separator and the version digest, and that projection is not invertible:
the line names what `portablectl list` printed and derives no plan key from it, a key reconstructed
from such a name being a key that may not name the entry the machine runs.

A holding is recognised by what the deployment record publishes for the realiser that would have put
it there and by nothing else, so a service the machine's own configuration declares and an image
another tool attached are reported as nothing: not as a holding, not as an entry, and not as an
error. Attribution reaches this command and no further, so a machine two deployments of it were
applied to has each deployment's entries named as holdings the other does not name, and the report
claims nothing more than that. An image of an earlier build of an entry the build still names stays
the `holds <identity>, built <identity>` line above and is not also a holding: one fact earns one
line.

What a machine holds is one question per machine and not one per holding, for the reason every path
delivered to a machine is one question: an endpoint may be reached over a socket-activated login,
and a burst of short logins is answered by the socket's own trigger limit rather than by the
endpoint. An answer the command cannot read as the endpoint's own is the command's own refusal,
naming the machine and what it said, and it costs the exit status the way silence does: a machine
whose answer cannot be read is a machine that was not asked, rather than one holding nothing the
build does not name.

These lines cost no exit status. A report whose machines all answered exits zero however many
holdings it named, for the reason a stale entry and a missing value cost none: a holding is an answer
a machine gave, not a machine that could not be asked, and removing it is `apply --retire`'s work.

`--only` bounds which machines are asked and decides nothing about what counts as unnamed. A machine
no entry of the selection is placed on is not asked, and an entry the deployment places is named as a
holding on no machine, whichever machine it is placed on and whether or not the selection left it
out. A machine the build no longer names carries no address in the build at all, and that limit is
written out with the order `apply` walks.

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

Each file is written outside the store, at the path the value entry records and at the ownership and
mode that entry states. Not `nix copy`: a store object is readable by every process on the machine,
which is the one property a generated secret cannot have.

The write takes all three from the record and decides none of them. The temporary it goes through is
created `0600 root` before its first byte, chowned, chmoded and only then moved into place, so the
bytes are never at the writing login's umask and never readable by anyone the record does not admit;
an interrupted run leaves the previous file or none. Ownership and mode are set again after the
move, on every apply and not only where the bytes changed, so a mode widened on the machine or an
owner changed there is returned to what the deployment states by the next apply. Where the recorded
account does not exist on the machine the step fails naming it, and nothing is left owned by the
login. The directories of a value are `0711`: traversable, so a file the record opens to an account
is reachable by it, and listable by nobody.

The temporary is compared against the file the machine already holds and moved only where they
differ, and the step says `changed` or `unchanged`. The comparison is made on the machine, by the
process that is about to write the bytes, and neither the bytes nor a digest of them is printed: what
is reported is that the file moved, never what it moved to. That answer is what decides the restart
steps at the end of the run.

The bytes travel on the step's own input stream. The argument vector of a write is the path, the
mode and the ownership the plan records, which is what the step line already prints, so a process
table on either host shows a write by the file it writes and never by what it writes there: the
vector the command hands its channel is the vector `execve` publishes, and the machine's own command
line is the element of it carrying the script. Two runs delivering different bytes of one length to
one path therefore run identical vectors.

A machine whose record says its values are sealed receives a second file per value, and it is not a
second plaintext. The copy is sealed to the recipient that machine's registry record declares, at a
path derived from the value's own by replacing `/run/vars` with `/var/lib/planner/sealed` and
appending the extension age publishes for its own files, and it is `0400` under `0700` directories
owned by the account that opens it - root on a system-scope machine, the deploying account on a
user-scope one. The record's `owner`, `group` and `mode` decide the plaintext and nothing beside
it: the copy is ciphertext, its one reader is the step that restores the plaintext, and `0711`
directories here would publish the value file names of every entry on the machine to every account
for no gain.

Nothing in this repository generates those bytes. The directory is where a generator hands them
over, and `apply` cannot tell a minted secret from one an operator wrote by hand.

## What a machine does with a value after a reboot

`/run` is a tmpfs, so a reboot empties every value on a machine. A machine whose registry record
declares a `sealRecipient` puts them back itself, before the entries that read them start, with no
operator and no network. A machine that declares none does not: its recovery is the second `apply`
it always was, and the planner says so at plan time with one
`machine-receives-a-value-unsealed` warning naming the values delivered there.

The build produces one artifact per machine a delivered value reaches whose record declares a
recipient, at `machines/<name>` in the same link farm as the entries. It carries `bin/unseal`,
`bin/check` and `planner-unseal.service`, and the program that opens a seal is in its closure
rather than expected on the machine's `PATH`: nothing in a plan provisions a package, and a
machine's own environment is not a fact the build records. The artifact is a function of the value
file records delivered there and of the machine's scope, and of the recipient not at all, so
rotating one rebuilds nothing. It is no plan entry and no realiser realises it - it belongs to no
instance and to no member - and the layer that already builds `plan.json`, `manifest.json` and both
halves of the diagnostics builds this as well.

The command installs it, in its place in the on-machine line: after the preflight question and the
retirement, before the first value written to that machine. `flakelet activate` is a flakelet-only
route and `portablectl` an image-only one, while the machine's own service manager is what every
placed machine declares, so the unit goes into that manager and the step reports whether the
install changed anything.

`planner-unseal.service` is a oneshot after `local-fs.target`, ordered before every unit of every
entry on that machine whose own record names a value's path - a declared read and an owner's own
file alike, because the recogniser that finds a value's path inside a string decides it rather than
a list somebody maintains. It orders and does not require, so a machine whose copies do not open
still starts its readers and they still fail on the file that is not there. On a system-scope
machine it is a system unit wanted by `multi-user.target`; on a user-scope one it is a user unit
wanted by `default.target`, run as the account that owns the identity file there.

What it does per value, in plan key order: a plaintext already at the path is left alone, so that a
restore can never replace a fresher delivery with an older copy; otherwise the copy is opened with
`/var/lib/planner/age.key` into a temporary created `0600` inside the value's own `0711` parent
chain, owned, chmodded to the record and moved into place, which is the write step's discipline for
the write step's reason. It prints `unsealed <path>` per value it restored, and `nothing to unseal`
where it restored none, and neither line rules out the ones about a copy: a machine holding neither
a plaintext nor a copy of anything names every absent copy and says `nothing to unseal` in the same
run. A copy that is there and does not open is the one condition that costs the exit
status: it is named and skipped, every other value is still restored, and the unit exits non-zero,
so the failure is in the machine's own service manager. Whether such a copy was sealed to a rotated
identity or damaged in place is a question it does not answer: both are copies it cannot open, and
that is what it says. A copy that is not there at all is named and the run still ends zero, because
a value nobody has sealed yet is an apply's work rather than a boot's. `bin/check` asks the same
question with no writes and no exit status of its own, printing one
`<sealed path> opens|absent|unreadable` line per value, and that is what a `status` run reads.

**Minting a machine's identity** is provisioning work, run on the machine once, before the first
apply:

```bash
install -d -m 0700 /var/lib/planner
age-keygen -o /var/lib/planner/age.key
chmod 0400 /var/lib/planner/age.key
```

`age-keygen` prints the public line of the identity it wrote:

```
Public key: age10se97f4u4mgwduyf5yt9xgakejc0qkttes9hwhtnj2n4rupxldts4alvvl
```

That word is what an operator pastes into the machine's registry record as `sealRecipient`, and
`age-keygen -y /var/lib/planner/age.key` prints it again off the file. The `chmod` is a third line
rather than a flag because `age-keygen` writes the file `0600`. Root runs those three lines on a
system-scope machine and the deploying account runs them on a user-scope one, where that account
owns `/var/lib/planner` and the sealed root beneath it: root at provision time, never at deploy
time.

Nothing in this repository ever holds, reads or transports the private half. The registry declares
one public word, the plan records that word on the machine's own record, and the file the seals are
opened with is read by the machine and by nothing else. A rotation is one `age-keygen` there, one
registry edit and one `apply` with the value source: no key moves and no value is regenerated,
because a copy is rewritten on every apply in any case, and between the rotation and that apply the
machine's copies are copies it cannot open, which the report names per value.

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

Every refusal the command can make from the plan, `manifest.json`, the value source and its own
invocation happens before the first machine is contacted: an inapplicable deployment, a `--only`
naming a key the deployment carries as neither an entry nor a value, a missing or unnamed value
file, a machine with no address, a deployment record of a version this command does not implement
or carrying no table of the machines a value reaches, and a record saying a machine's values are
sealed where `PLANNER_AGE` names no program that can seal them - which is refused naming the
program and the machines, because a run that dialled first would write a plaintext it could keep no
copy of. A run that has started is a run whose remaining failures belong to a machine.

A retirement is taken before anything is put in place: after the preflight question a user-scope
machine is asked, which is the head of the on-machine line, and before the first value write, the
first copy and the first activation. A holding the build does not name holds host resources of its
machine - a port, a unit file name, a host path - and the entry that replaces a renamed one claims
the same ones. `entry-port-claimed-twice` and `operator-entry-unit-file-collision` reach inside one
build and cannot see across two, so retire-then-activate is the only order a rename can start in.
Make before break is the other order, and it is the right one where a replacement can run beside
the thing it replaces, which a renamed entry cannot: it contends for exactly the resources its
predecessor holds. It also gets the failure mode backwards, a run that broke half way having
retired nothing and applied half.

Every machine of the selection is asked what it holds before anything is written on any of them, so
a run that cannot read one machine's answer has changed nothing anywhere. A holding is not
addressable as a plan key of the build, and a `--only` naming one is therefore the refusal above for
a key the deployment carries as neither an entry nor a value, made before a machine is contacted.

A machine the build no longer names at all is out of reach, and the limit is stated rather than
worked around: the plan records an address only for a machine some placement selected, so a
deployment whose every entry on one machine was deleted carries no address for that machine
anywhere, and no option, no machine-identity field and no reading of a previous build is invented to
reach it. The order of work follows from that. A machine is emptied while the build still names an
entry on it: drop the entries to retire, keep one, apply with `--retire`, and drop the last entry in
a later build. A machine the build has already stopped naming is emptied on the machine itself, with
the endpoint's own tool - `flakelet remove <name>`, or the `bin/detach` the image artifact carries.

## Root at provision time, never at deploy time

A machine whose registry record declares `scope = "user"` is deployed as an account, and that
account is the whole privilege a run has there. No step of an apply is root, and no step asks for a
privilege the account was not given. What root does on such a machine is provision it, once, before
the first apply, and everything below is that work.

Three roots are what a deployment writes under, and none of them moves with the scope: `/run/vars`,
where every generated value lands, the image staging root `/run/portable-planner`, where an attach
assembles what it installs, and `/var/lib/planner`, where a machine's sealed copies and the
identity file that opens them live. They are the same paths on a user-scope machine as on a
system-scope one, which is why no uid, no account name and no home directory is a field of any
plan: flipping a machine's scope re-keys the entries placed on it and re-keys no value, and a
value's recorded path is the same sentence on every machine of its delivery set.

`/run` is empty after a boot, so making those roots writable by the deploying account belongs in
`tmpfiles.d` rather than in a command somebody has to remember:

```
# /etc/tmpfiles.d/planner-user-scope.conf
d /run/vars              0711 deploy deploy -
d /run/portable-planner  0711 deploy deploy -
```

`0711` is the mode the value directories and the staging tree already carry: traversable, so a file
the record opens to the account is reachable by it, and listable by nobody, so the machine does not
publish the configuration file names of every entry on it. `systemd-tmpfiles --create` applies the
rule without a reboot.

The third root outlives a boot, which is the property it is chosen for, so it is provisioned once
instead of being recreated by a rule: on a user-scope machine `/var/lib/planner` is the deploying
account's, `0700`, and the sealed copies and the identity file under it are the account's too.

```
install -d -m 0700 -o deploy -g deploy /var/lib/planner
```

A value's own directory inside the sealed root is created by the write that puts a copy there, at
`0700` and owned by whoever wrote it, so nothing below that line is provisioning work. Minting the
identity file is, and on a user-scope machine the account mints its own -
[what a machine does with a value after a reboot](#what-a-machine-does-with-a-value-after-a-reboot)
is that step.

The account's own service manager has to be running while nobody is logged in, because a
non-interactive ssh login has no session to start one:

```
loginctl enable-linger deploy
```

A user attach then needs the certificate the image's roothash was signed with. `systemd-mountfsd`
applies its untrusted image policy to every image outside the system trusted directories, so a
user-scope image is signed dm-verity and an unsigned one escalates to an interactive polkit action
that a non-interactive run reads as a hard failure. The public half goes into `/etc/verity.d`, the
operator's own of the three directories systemd validates a signature against:

```
install -D -m 0444 planner-verity.crt /etc/verity.d/planner.crt
```

The private half never leaves the operator. It reaches the build as `signing`, the optional
argument tabled above, and it is in no plan, no artifact and no value source: what the image
carries is the signature over its roothash, which is public. Rotating the key
rebuilds and re-keys nothing, an artifact's version digest being over what the artifact holds. A
lost key is new provisioning, every machine installing the public half of its replacement, and a
leaked key signs images those machines trust, which is the one fact of this walk that is the
operator's to keep and not this repository's to carry.

An apply verifies that work rather than assuming it. On a user-scope machine it asks one question
there first, before it mutates anything: the three roots writable by the account, lingering active,
the account's service manager reachable, the user portabled reachable where an image entry is placed
on that machine, `systemd-mountfsd.socket` and `systemd-nsresourced.socket` live, and unprivileged
user namespaces permitted. A fact the machine cannot confirm is the command's own refusal, naming
the machine, the requirement and what the machine answered, and nothing after it is attempted on
that machine: the plan holds no runtime fact, so a missing prerequisite is no diagnostics row. A
system-scope machine is asked nothing new, and under `--dry-run` the question is recorded rather
than asked, like every other remote step.

Its place is the head of the on-machine line, which
[`INTEGRATION.md`](../openspec/changes/INTEGRATION.md) writes out once: the preflight question, then
the retirement of an entry the build no longer names, then the unsealer install, then the value
writes, then the copy, then the activation, then the value-driven restarts.

The account a run reaches a machine as is the command's own `--user`, the login there, `root` by
default. A user-scope machine is applied by naming the provisioned account, and what the scope
decides is the other half: every manager and portabled step of that machine is addressed with
`--user`, read off the machine's scope in the record and the `scopes` the realiser of that step
publishes.

## How a machine becomes a member

A friend's machine - behind NAT, on an address that moves, never root - is declared like any other
machine, and a mesh is what makes the declaration true. The coordination server the operator runs
is the membership authority: it admits a machine, names it, and expires it. Enrollment is the order
of work around that server, and it adds no registry key, no plan field and no subcommand. After
admission the machine is an ordinary machine of its scope, and no step of an apply or a report
knows that it was enrolled.

1. **Declare the row.** The machine's `address` is its mesh name and its `scope` is `user`. No layer
   below the registry can tell that name from any other address, an `address` being an opaque name
   handed to ssh, and every export built from `target.address` carries the name rather than a
   number the mesh may reassign.
2. **Generate the credential.** The entry that runs the coordination server declares a generator
   minting the join key single-use and with an expiry. Its file record states `secrecy = "secret"`
   and `deploy = false`, so the key is delivered to no machine and arrives only in
   [the directory a generator hands bytes over in](#where-the-bytes-of-a-generated-value-come-from).
3. **Hand it over outside the tree.** The operator reads the key out of the value source and gives
   it to the friend over whatever channel the two of them trust. Its bytes enter no plan field and
   no argv of a run, the discipline every secret value already has: the plan records the value's
   path and its delivery facts, never its bytes.
4. **Verify the node list.** The friend joins with the key and reports success, and the operator
   then reads the server's own node list and expires the node if the answer is not the machine that
   was meant. That check is the admission, and the tree automates no part of it.
5. **Apply.** Everything after admission is the existing walk, dialing a name the mesh resolves:
   the user-scope preflight question first
   ([root at provision time](#root-at-provision-time-never-at-deploy-time)), then the retirement,
   the value writes, the copy, the activation and the report. A machine that never joined is
   refused at its first step, naming the machine and what the dial answered, and nothing after that
   step is attempted there.

The sync is one-way, registry to server
([design D2](../openspec/changes/enroll-a-friend-machine/design.md)). The registry declares which
machines the deployment means and the server admits and expels; the server's database is never a
source the planner reads. A machine's current endpoint, its presence and its last-seen are the
mesh's facts, `mkPlan` sees none of them, and the only gate from the mesh back into evaluation is
an operator-reviewed registry edit. Evaluation stays pure that way, and a join re-keys nothing but
the joined machine's own rows.

Admission is verified rather than automated, because a pre-auth key admits whoever presents it
first: the handover is not the ceremony, the check after it is. Single-use is what makes an
interception visible - the second presenter is refused, and the first is on the node list to
inspect - and a key past its expiry admits nobody. Neither refusal is this tree's to make. The tree
mints a credential the server will refuse twice, and the server is what refuses it.

Expiring a node is how membership ends. A machine whose node the operator expired reads as
unreachable in the report, an answer about reachability and never about retirement, and a report
that could not ask a machine exits non-zero. The expiry is therefore visible without the command
learning anything about the mesh. Retiring an entry is the other question and the other half:
`--retire` is about a holding the build no longer names, and it is asked of a machine that answers.

## When a run breaks

A run stops at the first step a machine refuses. Each step's line is printed before that step is
attempted, so the last step line an interrupted run printed names the step that was running when it
ended, and the failure line after it names that step, the machine and what the machine said. Nothing
after the failed step is attempted: a broken run leaves one boundary rather than a set of them.

What the cluster then holds is a partial application. The machines the walk had already reached hold
the new artifact and run it, and every machine after the break holds what the previous run left. No
single machine is half applied, because each step is one ssh invocation that either completed on
that machine or did not.

Which side of that boundary a machine is on is what `status` now answers. Each line says whether
the machine holds what this build published, so the entries the run reached and the entries it did
not are told apart by reading the report rather than by remembering how far it got. The exit status
is unchanged: a fleet part way through an apply is a fleet that answered.

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
([design D13](../openspec/changes/archive/2026-09-16-apply-deployments-with-an-operator-command/design.md)):

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
