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
  operator/  a whole deployment built: the plan, the manifest, one artifact per entry
  cli/       planner, the operator's command, which builds a deployment and applies it
  tests/     nix-unit suites in unit/, three machine tests and their harness in e2e/
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
| [cluster.md](cluster.md) | two real machines: what a delivery moves, the host it needs, and how to attach to a live run |

Two realisers read one plan and neither adds a field to it. The image is **store-less** - it
carries its own closure and a machine attaches it with `portablectl`, which is the tier where no
store and no daemon exist. The flakelet artifact is **store-backed** - it carries unit files and
metadata only, and the machine runs them out of its own store. Build the one your target can
hold: what this repository builds of each is the end-to-end fixture, `nix build
.#planner-e2e-portable-image` or `nix build .#planner-e2e-wired-pair`.

The worked example the library is built against is
`fixtures/minimal-typed-edge/`. Everything below quotes it, and it is
evaluated as committed by `tests/unit/worked.nix`.

## The smallest thing that works

```nix
let
  planner = import ../lib {
    korora = import "${korora}/types.nix";
    systems = nixpkgs.lib.systems;
  };

  # An interface is a value. Importing it is what identifies it; `name` is only
  # a label for diagnostic output.
  greeting = planner.interface {
    name = "greeting";
    exports.text = {
      type = planner.korora.string;
    };
  };

  # A leaf module: what it uses, what it provides, and what it runs.
  speaker = { settings, ... }: {
    provides.line.interface = greeting;
    impl = _: {
      provides.line.exports.text = "hello ${settings.who}";
    };
  };

  listener = _: {
    uses.line = {
      interface = greeting;
      reads = [ "text" ];
    };
    impl = { results, ... }: {
      units.say.command = "/bin/echo ${results.line.text}";
    };
  };

  # A root composes members and decides which of their capabilities the
  # deployment may wire to.
  speakerRoot = { service, ... }: rec {
    services.main = service "main" {
      module = speaker;
      defaults.who = "world";
    };
    provides.line = services.main.provides.line;
  };

  listenerRoot = { service, ... }: {
    services.main = service "main" { module = listener; };
  };

  result = planner.mkPlan {
    machines.host = {
      address = "host.example";
      tags = [ ];
      system = "x86_64-linux";
      serviceManager = "systemd";
    };

    instances.talker = {
      module = speakerRoot;
      placement.every.main.machines = [ "host" ];
      exposes = [ "line" ];
    };

    instances.hearer = {
      module = listenerRoot;
      placement.every.main.machines = [ "host" ];
      wire.line = {
        instance = "talker";
        provides = "line";
      };
    };
  };
in
result
```

`result.plan` carries `talker:main@host`, `hearer:main@host` and
`machine:host`; `result.diagnostics` is `[ ]`; `result.applicable` is `true`;
and `plan."hearer:main@host".units.say.command` is `/bin/echo hello world`.

Now break it. Misspell the wire's instance as `talkr` and the resolution still
produces one error row and `applicable = false`:

```
deployment/instances.nix wires `line` of instance `hearer` to instance `talkr`,
which the deployment does not declare
```

Delete the wire entirely and it is `slot-unwired` instead. Either way the read
delivers nothing, and **`results` in the consumer's `impl` does not contain the
slot at all** — not `null`, not an empty set, absent. The row is produced
either way; the module above interpolates `results.line.text` regardless, so
forcing the entry that reads the missing value raises a missing attribute,
which propagates — see
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
| `interface { name, exports }` | declare an interface |
| `unitExtension { backend, name, fields }` | declare the typed fields one service manager has and the portable unit vocabulary does not. Identified by the value, so two extensions may share a `name`; a unit applies one as `extends = [ { extension = <the value>; values = { … }; } ]` |
| `korora` | korora's types plus this library's atoms and both constructors — the value an interfaces file takes as its argument |
| `atoms` | `korora` without the constructors: korora's own types plus the atoms this library owns (`url`, `secretRef`, `unitRef`, `duration`, `schedule`, `userName`) |
| `platform` | the projection a plan's `target.system` is: `record { system, microarchitecture }`, the name lists it is built from (`scalarNames`, `parsedNames`, `gccNames`, `abiExcluded`, `fieldNames`) and nixpkgs' own `elaborate` and `functionNames` |
| `service`, `mkRoot` | composition, for a caller building roots outside a deployment: `mkRoot <root> <settingsOf>` applies the root to `{ service = service <settingsOf>; }`, and `settingsOf { name, defaults, fixed }` returns `{ values, sources, rows }` |
| `render`, `mkTable` | render a diagnostics table to text; build one from rows |
| `registry`, `fileOf`, `label`, `atomRows`, `exportNames`, `secrecyOf` | the attribution helpers row text is written with: index a caller's `interfaces` by value, find an interface's declaring file, print `` `name` (file) ``, check one interface's atoms, list its exports, read an atom's `secrecy` |
| `excluded` | the exclusion table as data: construct -> the trigger that would bring it back |
| `util` | the list and attrset helpers the library runs on |

## What it deliberately does not do

This subset carries no `locality`, no `lifecycle`, no `placement.pick`, no
member cuts, no externals, no collect family and no
runtime plane. Writing any of them is an **error row naming the condition that
would bring the construct back**, not a silent drop — see
[diagnostics.md](diagnostics.md#refusals-by-subtraction) and
`lib/excluded.nix`.
