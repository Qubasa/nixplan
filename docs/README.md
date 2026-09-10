# The deployment planner

A pure-Nix library that evaluates a deployment into a **plan** and a
**diagnostics table**, and realises nothing: no derivation, no store path that
is not a literal string, no filesystem read, no network.

Two sentences of context. A service declares what it *provides* and what it
*uses* as typed interfaces; a deployment says which instances exist, where they
are placed, and which slot is wired to which capability. The planner resolves
those edges and refuses the ones that do not typecheck — by returning a row,
never by raising.

```
nixplan/
  lib/       the library
  image/     the portable-service-image realiser
  flakelet/  the flakelet service-artifact realiser
  secrets/   the nixos-secrets configuration realiser
  operator/  a whole deployment built: the plan, the manifest, one artifact per entry
  cli/       planner, the operator's command, which builds a deployment and applies it
  tests/     nix-unit suites in unit/, five machine tests and their harness in e2e/
  fixtures/  the worked deployment the unit suites evaluate, with its golden plan
  perf/      two synthetic deployments, measurement harness, committed budgets, checker
  docs/      you are here
```

## Read in this order

| Document | Answers |
| --- | --- |
| this file | what it is, the smallest working example, the shape of the result |
| [authoring.md](authoring.md) | how to write an interface, a leaf module, a root and a deployment |
| [diagnostics.md](diagnostics.md) | the row contract, every row the planner can produce, and rendering |
| [plan.md](plan.md) | what is in the plan artifact and what each field means |
| [tooling.md](tooling.md) | flake attributes, checks, fixture regeneration, the perf gate |
| [flakelet.md](flakelet.md) | the store-backed realiser: what a flakelet service artifact holds, who decides a unit is enabled, and what it refuses |
| [operator.md](operator.md) | building a whole deployment, and the command that puts one on machines |
| [secrets.md](secrets.md) | the realiser that reads a plan as a configuration for the external secret generator: the program a generator declares, the name projection, the rendered deploy step and the pinned contract |
| [cluster.md](cluster.md) | real machines: what a delivery moves, the host it needs, how a consumer's own flake is proved, and how to attach to a live run |

Two realisers read one plan into something a machine runs, and neither adds a field to it. The
image is **store-less** - it carries its own closure and a machine attaches it with `portablectl`,
which is the tier where no store and no daemon exist. The flakelet artifact is **store-backed** -
it carries unit files and metadata only, and the machine runs them out of its own store. Build the
one your target can hold: what this repository builds of each is the end-to-end fixture, `nix build
.#planner-e2e-portable-image` or `nix build .#planner-e2e-wired-pair`. The third reading realises
nothing a machine holds: it turns the same plan into a configuration for the external secret
generator, and `secrets/backend.nix` renders the step that carries a generated file to the machines
the plan says receive it.

The worked example the library is built against is
`fixtures/minimal-typed-edge/`. The field discussions below quote it, and it is
evaluated as committed by `tests/unit/worked.nix`.

## The smallest thing that works

One service, two machines, and a tag that places it on both. This is not a
transcription of an example: it is the deployment
`tests/e2e/newcomer/template/deployment/` holds, `nix build
.#planner-e2e-newcomer` builds it, and the machines of `tests/e2e/newcomer/`
apply it and read back what each unit wrote. An example that stopped building
would fail that build.

The registry it is placed against, `machines.nix`:

```nix
{
  machines = {
    alpha = {
      address = "10.0.0.11";
      tags = [ "greets" ];
      system = "x86_64-linux";
      serviceManager = "systemd";
    };

    beta = {
      address = "10.0.0.12";
      tags = [ "greets" ];
      system = "x86_64-linux";
      serviceManager = "systemd";
    };
  };
}
```

Which instances exist and where they go, `instances.nix`:

```nix
{ hello }:
{
  instances = {
    greeter = {
      module = hello.services.default;
      placement.every.greet = {
        tags = [ "greets" ];
      };
    };
  };
}
```

What the one of them runs, `modules/hello/greet.nix`:

```nix
{ greeter }:

{ settings, ... }:
{
  platforms = [ "x86_64-linux" ];

  # The greeting names the machine the entry was planned for, so the two entries of
  # one instance are two artifacts rather than one copied twice.
  impl =
    { target, ... }:
    {
      closure = [ greeter ];

      units.say = {
        command = "${greeter}/bin/greet";
        env.GREET_WHO = settings.who;
        env.GREET_WHERE = target.address;
        env.GREET_PATH = settings.greetingPath;
      };
    };
}
```

Two more files hold those three together, and a reader copies the directory
rather than this page: `modules/hello/default.nix` is the root that names the one
member, and `default.nix` builds the program the unit runs and hands the whole
thing to `mkDeployment`, which is [operator.md](operator.md)'s subject.

`result.plan` carries `greeter:greet@alpha`, `greeter:greet@beta`,
`machine:alpha` and `machine:beta`; `result.diagnostics` is `[ ]`;
`result.applicable` is `true`; and
`plan."greeter:greet@alpha".units.say.env.GREET_WHERE` is `10.0.0.11`, the
address the registry declares for the machine that entry was planned for. The
two entries of one instance are two artifacts rather than one copied twice,
because each one carries the address it was planned for.

Now break it. Give the greeter a closure root that is not a path under the store
the plan is read against, and the plan is still produced, with one error row per
placed entry and `applicable = false`:

```
  ! greeter:greet@alpha  greeter:greet@alpha declares the closure root `/opt/vendor/greeter`, which is not a path under the store directory `/nix/store` the plan is read against
      severity: error
      evidence: a closure root is a literal path under the store the plan is read against, and a consumer populates a filesystem from those roots
      resolution: declare a path under `/nix/store` in `closure`, or plan the deployment against the store `/opt/vendor/greeter` belongs to
```

That is the mutation `tests/e2e/newcomer/` builds on a machine: a deployment the
planner refuses builds its plan and both halves of its table, and no artifact.

This example has no wire: one service that reads nothing is the smallest thing
that works. Where a read is refused, **`results` in the consuming `impl` does
not contain the slot at all** — not `null`, not an empty set, absent. The row is
produced either way, and a module that interpolates the missing value raises a
missing attribute, which propagates — see
[authoring.md](authoring.md#when-a-read-is-refused). That is the trade: `or [ ]`
cannot be written, so it cannot silently succeed.

## `mkPlan`

```nix
planner.mkPlan {
  instances = { };     # required: the deployment
  machines = { };      # required: the machine registry
  interfaces = { };    # optional: declaring file -> interfaces, for row text
  varsState = { };     # optional: which generated files exist, and their bytes
  sources = { };       # optional: the file each row names
  storeDir = builtins.storeDir;  # optional: the store an entry's paths are read against
}
```

returns

```nix
{
  plan = { };          # entry key -> entry, flat, free of expressions
  diagnostics = [ ];   # rows, ordered by id then subject then message
  applicable = true;   # false when any row is an error
}
```

`interfaces`, `sources` and `varsState` change what rows *say*, never what the
planner accepts:

- **`interfaces`** maps a declaring file to the interfaces declared in it, so a
  row can print `` `ssh-host-identity` (interfaces/default.nix) ``. It is
  attribution, not a registry — an interface absent from it is still a perfectly
  good interface, and two interfaces sharing a `name` are told apart by this.
- **`sources`** is `{ deployment, machines, modules.<instance>,
  leaves.<instance>.<member> }`, each a path *relative to the deployment root*.
  Absolute paths are refused (a row would otherwise differ between checkouts).
- **`varsState`** is `<machine>.<generator>.<file> = { present, content }`. A
  file the state does not name has no bytes yet, and reading it produces a
  `set-entry-absent` row rather than a `null` a consumer could default against.

`storeDir` is the one optional argument that changes what the planner *sees*:
it is the store directory an entry's declared closure roots and mentioned paths
are recognised against, and the one a consumer populates. It defaults to
`builtins.storeDir`, so a machine whose store lives elsewhere is planned under
its own rather than under a literal written in the library.

## What the library exports

| Attribute | Use |
| --- | --- |
| `mkPlan` | the entry point above |
| `interface { name, exports, fold ? null }` | declare an interface. A `fold` is the interface's own policy for the set a `reach = "all"` read collects: one function of that set, keyed by provider entry key, whose result is what the consuming `impl` receives |
| `unitExtension { backend, name, fields }` | declare the typed fields one service manager has and the portable unit vocabulary does not. Identified by the value, so two extensions may share a `name`; a unit applies one as `extends = [ { extension = <the value>; values = { … }; } ]` |
| `korora` | korora's types plus this library's atoms and both constructors — the value an interfaces file takes as its argument |
| `atoms` | `korora` without the constructors: korora's own types plus the atoms this library owns (`url`, `secretRef`, `unitRef`, `duration`, `schedule`, `userName`) |
| `platform` | the projection a plan's `target.system` is: `record { system, microarchitecture }`, the name lists it is built from (`scalarNames`, `parsedNames`, `gccNames`, `abiExcluded`, `fieldNames`) and nixpkgs' own `elaborate` and `functionNames` |
| `service`, `mkRoot` | composition, for a caller building roots outside a deployment: `mkRoot <root> <settingsOf>` applies the root to `{ service = service <settingsOf>; }`, and `settingsOf { name, defaults, fixed }` returns `{ values, sources, rows }`. A member record also carries `slotSet`, the slot names of the two readings a `slot-set-settings-derived` row is built from, or `null` when the deployment configured nothing |
| `render`, `mkTable` | render a diagnostics table to text; build one from rows |
| `registry`, `fileOf`, `label`, `atomRows`, `exportNames`, `secrecyOf`, `foldOf` | the attribution helpers row text is written with: index a caller's `interfaces` by value, find an interface's declaring file, print `` `name` (file) ``, check one interface's atoms, list its exports, read an atom's `secrecy`, read an interface's `fold` |
| `excluded` | the exclusion table as data: construct -> the trigger that would bring it back |
| `util` | the list and attrset helpers the library runs on |

## What it deliberately does not do

This subset carries no `locality`, no `lifecycle`, no `placement.pick`, no
member cuts, no externals, no collect family and no
runtime plane. Writing any of them is an **error row naming the condition that
would bring the construct back**, not a silent drop — see
[diagnostics.md](diagnostics.md#refusals-by-subtraction) and
`lib/excluded.nix`.
