# Authoring

Four things get written, in this order: an **interface**, a **leaf module**, a
**root**, and a **deployment**. Each has exactly one job, and the split is the
point — the module declares what it needs, the deployment says where the far
end is, and neither can express the other's decision.

Every example below is from `fixtures/minimal-typed-edge/`, which the
suite evaluates as committed. Two constructs that folder does not write — a
unit extension and a `pin` — are quoted from `tests/unit/support.nix`,
`tests/unit/units.nix` and `tests/unit/closure.nix` instead, and named as
such where they appear.

## 1. Interfaces

An interface is a value you import. It is identified by that value, validated
against no registry, and its `name` is a label for diagnostic output only. Two
interfaces in two files may carry the same `name` — wiring one to the other is
an `interface-mismatch` row that prints both declaring files.

```nix
# interfaces/default.nix
{ korora }:
{
  sshHostIdentity = korora.interface {
    name = "ssh-host-identity";
    exports = {
      publicKey = {
        type = korora.string;
        secrecy = "public";
      };
      privateKey = {
        type = korora.secretRef;
        secrecy = "secret";
      };
    };
  };
}
```

The `korora` argument is `planner.korora`: korora's own types, the atom types
this library owns, and the two constructors — `interface` and `unitExtension`.

**An export atom declares `type` and may declare `secrecy`, and nothing else.**
`secrecy` defaults to `"public"` and takes `"public"` or `"secret"`. Any other
key is refused — `locality` and `lifecycle` by name, with the condition that
would bring each back (`export-atom-excluded-key`); anything else as a
misspelling (`export-atom-unknown-key`).

Atom types beyond korora's own. The first two are what an export atom binds to
in practice; the last four are the types the unit vocabulary is declared
against, and an interface or an extension field may bind to any of them:

| Type | Verifies |
| --- | --- |
| `url` | a string of the form `<scheme>://<non-space>`, e.g. `ssh://borg@host:22/srv` |
| `secretRef` | a value carrying `path` and `secrecy = "secret"` and deliberately no `content`: the vars file record the planner hands a module, so an interface can declare a secret without an atom that could hold its bytes |
| `unitRef` | the name of a unit; the reader additionally refuses a name the referring module did not declare itself |
| `duration` | a span of time: counts with units (`30s`, `5min`, `1h30min`) or a bare count of seconds |
| `schedule` | a named interval (`daily`, `weekly`) or a calendar expression with an optional weekday and date (`Mon 03:00`) |
| `userName` | the account a unit runs as: the POSIX-portable name, never a uid, because the identity a name resolves to is the machine's answer and not the plan's |

**An interface may also declare a `fold`.** A fold is one function of the set a
set-valued read collects, and it is the interface's own policy for the set:
validate it, refuse it, and hand every consumer one normal shape:

```nix
# interfaces/default.nix, continued
sshHostIdentity = korora.interface {
  name = "ssh-host-identity";
  exports = { publicKey = { type = korora.string; }; };
  fold =
    set:
    let
      entries = builtins.attrNames set;
      blank = builtins.filter (entry: set.${entry}.publicKey == "") entries;
    in
    if blank != [ ] then
      {
        refused = "no host key published by ${builtins.concatStringsSep ", " blank}";
      }
    else
      map (entry: {
        inherit entry;
        inherit (set.${entry}) publicKey;
      }) entries;
};
```

| Fact | Consequence |
| --- | --- |
| the fold applies to `reach = "all"` only | a single-valued read hands `results.<slot>` the read values directly, and the fold is not applied |
| its input is keyed by provider plan entry key | `issuer:api@alpha`, the same keys the plan's `reads.<slot>.entries` names |
| its input carries the slot's `reads` and nothing else | a fold cannot observe an export the slot did not name, cannot name a secret export a slot may not name, and cannot widen a delivery set |
| the planner forces it under a guard | a fold that raises is `interface-fold-raised` and the slot is then **absent** from `results`, the same as any refused read |
| a fold that is not a function | `interface-fold-not-a-function` against the interface's declaring file, rather than an error at the read |
| a fold no set-valued read applies | `interface-fold-unapplied`, a warning: a policy nobody applies is a policy nobody is held to |

An interface that declares no fold delivers the set unchanged, keyed by
provider entry, which is what every interface in `fixtures/minimal-typed-edge/`
does.

## 2. Leaf modules

A leaf module is a function of `{ settings, ... }` returning a declaration. It
declares eight keys at most; anything else is a row.

| Key | Shape |
| --- | --- |
| `platforms` | list of system strings |
| `claims.ports.<name>` | `{ proto, count, fixed }` — `fixed` is required, the planner allocates nothing |
| `vars.<generator>` | `{ files.<file> = { secrecy }, per ? "placement", deploy ? true, reads ? [ ], program ? <store path> }` — below |
| `uses.<slot>` | `{ interface, reach ? "one", reads ? <every export> }` |
| `provides.<capability>` | `{ interface }` |
| `pin` | `{ key, locked }` — the lock entry of the sources this module's packages came from, below |
| `impl` | a function, below |
| `severity` | read and discarded, with a warning — a module does not decide the severity of a planner row |

```nix
# modules/borg-push/client.nix
{ borgbackup, openssh, sshHostIdentity, borgRepository }:

{ settings, ... }:
{
  platforms = [ "x86_64-linux" "aarch64-linux" ];

  vars.hostKey = {
    files."ssh_host_ed25519_key" = { secrecy = "secret"; };
    files."ssh_host_ed25519_key.pub" = { secrecy = "public"; };
  };

  uses.repo = {
    interface = borgRepository;
    reach = "one";
    reads = [ "url" "quota" ];
  };

  provides.identity = { interface = sshHostIdentity; };

  impl = { vars, results, ... }: {
    closure = [ borgbackup openssh ];

    provides.identity.exports = {
      publicKey = vars.hostKey."ssh_host_ed25519_key.pub".content;
      privateKey = vars.hostKey."ssh_host_ed25519_key";
    };

    units.borgPush = {
      command = "${borgbackup}/bin/borg create --stats ${results.repo.url}::{now} ${settings.path}";
      env = {
        BORG_RSH = "${openssh}/bin/ssh -i ${vars.hostKey."ssh_host_ed25519_key".path}";
        BORG_QUOTA_GIB = toString results.repo.quota;
      };
    };
  };
}
```

### `reach`

`reach = "one"` (the default) means the wired capability must have **exactly
one** placement; `results.<slot>` is then the read values directly. Two
placements is `reach-one-placement-count`, naming the slot and both machines.

`reach = "all"` means every placement, and `results.<slot>` is **keyed by
machine even at one placement** — a one-element set does not collapse into a
value:

```nix
uses.clients = {
  interface = sshHostIdentity;
  reach = "all";
  reads = [ "publicKey" ];
};

impl = { results, ... }: {
  configData."/srv/borg/.ssh/authorized_keys" = {
    mode = "0600";
    reload = [ "borgRepo" ];
    render = [
      {
        text = builtins.concatStringsSep "\n" (
          builtins.attrValues (
            builtins.mapAttrs (machine: c: "# ${machine}\n${c.publicKey}") results.clients
          )
        );
      }
    ];
  };
};
```

The fold above is hand-written in the consuming module, which is what an
interface declaring no `fold` leaves each consumer to do. When the interface
declares one, `results.clients` is already the folded value and the consumer
walks nothing.

`reach = "local"` is refused: `local` derives from a locality this subset does
not declare.

### `reads`

Omitted, it is every export of the interface. Naming an export the interface
does not declare is `slot-reads-unknown-export` with the declared list as
evidence.

Naming a `secret` export is what **delivers** it: the reader's machine joins
that value's delivery set, and the reason is recorded on the value's entry. An
export left out of `reads` is absent from `results.<slot>` rather than null, so
an omission cannot be defaulted around, and the machine does not receive the
bytes. A service may also use its own secret through its own unit without a
slot, which is what `BORG_RSH` above does.

### `vars`

A generator is a name for one or more files whose bytes something outside the
planner produces. The planner names them, never reads them, and decides which
machines receive them.

| Key | Means |
| --- | --- |
| `files.<file>.secrecy` | `"secret"` — the plan carries the path — or `"public"`, where it may carry the bytes |
| `per` | `"placement"` (the default) is one value per machine the owner is placed on; `"instance"` is one value for the instance however many machines run it |
| `deploy` | `false` means no machine receives the bytes. One value still exists, so a public file's value still travels in the plan, and anything that would open one of its files on a machine is refused |
| `reads` | sibling generators of the same module. A `"placement"` generator may read an `"instance"` one; the reverse is `vars-reads-arity`, because the placements hold one value each and the reader is one value |
| `program` | the store path of the program that produces the files, recorded as a literal string and neither run nor read here. A declaration that is not exactly one store path is `vars-program-malformed`; omitting the key is valid, and the reader that needs a program is what refuses |

A file's path is `/run/vars/<instance>/<generator>/<file>`, the same on every
machine that receives it: one delivery of one value has one name. Two members of
one instance declaring the same generator name is `vars-generator-claimed-twice`
— a generator is addressed by instance and name, so the two declarations would
be one address for two values.

A deployment writes `<package>.drvPath` rather than an output path: the
external generator this library reads a plan for wants a derivation, and a
`drvPath` is a string a pure evaluation can produce — see
[secrets.md](secrets.md).

### `pin`

`pin` is the lock entry of the sources this module's packages were built from:

```nix
# tests/unit/closure.nix
pin = {
  key = "/nixpkgs";
  locked = {
    type = "github";
    owner = "NixOS";
    repo = "nixpkgs";
    rev = "a1b2c3d4e5f60718293a4b5c6d7e8f9012345678";
    narHash = "sha256-aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa=";
  };
};
```

**Its value arrives through the module's lexical closure the way its packages
do, and is not written by hand.** A leaf module takes `borgbackup` and
`openssh` as function arguments; whatever resolved those sources is what hands
the module the `pin` beside them. The planner **records it and verifies
nothing**: no fetch, no lockfile read, no hash checked. It is a fact about the
deployment the same way a machine's address is.

The requirement is on the resolver, and it is two string fields and no tool:
`rev` and `narHash`. A `locked` record missing either is `pin-underspecified`,
because a pin that can resolve to different bytes on a later evaluation is the
condition per-service pinning exists to refuse. `key` is the string the
resolver assigned, and key equality is the whole of what says two entries share
a dependency. Any resolver that can produce those two fields will do — the
planner names none and can be given another.

`locked` carries `type`, `owner`, `repo`, `rev` and `narHash` and nothing else,
every field a literal string. A key outside `{ key, locked }`, a missing `key`,
a missing `locked` or a field that is not a string is `pin-malformed`.

### The `impl` argument

```nix
impl = { instance, machine, target, settings, vars, alloc, results }: { … };
```

| Field | Is |
| --- | --- |
| `instance` | the instance name this placement belongs to |
| `machine` | the machine name, or `null` at a member no placement selected |
| `target` | `{ system, serviceManager, address }` — the reduced platform record of the machine's system, the service manager that runs its units, and the address it is reached at. Each field is present only where the registry declared it. **Absent** at a member no placement selected |
| `settings` | resolved settings: defaults, then the deployment, then `fixed` |
| `vars.<gen>.<file>` | `{ present, secrecy, path, content }` — `content` is `null` for a secret or an ungenerated file |
| `alloc.ports.<claim>` | the fixed port the claim declared |
| `results.<slot>` | **only the slots that delivered** (see below) |

Those seven and nothing else. `target` is **absent** rather than null where
there is no placement to have a target, so an `impl` that destructures
`{ target, ... }` or reads `args.target` unconditionally raises at an unplaced
member — and that raise propagates for the same reason a refused read's does
(below). Read it under `machine != null`, or write the module so only a placed
member forces the value. A machine that declares neither `system` nor
`serviceManager` has no target either, and that case is
`machine-target-incomplete` on the registry.

A machine that declares no `address` yields a target **without that field**, so
a module publishing its own endpoint is refused rather than handed an empty
string. Read it under `target ? address` where a deployment may leave it out:
an unguarded `target.address` on such a machine is a missing attribute, which
propagates.

`address` is in the target rather than beside it because a unit may be rendered
from it and a target is what an entry's key hashes. Changing one machine's
address therefore re-keys **every** entry placed on it, including entries that
never read it: `impl` is a function, so the planner cannot know which ones
dereferenced the field, and a key that does not cover what the entry was
rendered from is the worse failure.

and it returns any of:

```nix
{
  units.<name> = { … };                    # the unit vocabulary, below
  configData."<path>" = { … };             # a file record, below
  closure = [ <store path root> … ];       # declared, below
  provides.<capability>.exports = { … };   # keyset must equal the interface's
}
```

Those four keys and nothing else: anything else is
`implementation-unknown-key`, and a return value that is not an attribute set
is `implementation-malformed`.

A provider's export keyset **equals** its interface's keyset. An omission is
`provider-export-missing`, an extra is `provider-export-extra`, and a value
failing its atom's type is `export-type-mismatch`. No superset satisfies a
narrower slot.

### The unit vocabulary

A unit is a record of typed fields. A field the unit does not declare is
**absent** from the record rather than written as a null or as a service
manager's default, so a binding can tell "not asked for" from "asked for and
empty".

| Field | Type | Is |
| --- | --- | --- |
| `command` | string | what runs |
| `env` | attrs of string | **this unit's** environment |
| `after` | list of `unitRef` | ordering, against units this module declared |
| `requires` | list of `unitRef` | a hard dependency, same restriction |
| `user` | `userName` | the account it runs as: the POSIX-portable name and never a uid |
| `oneShot` | bool | it runs to completion rather than staying up |
| `remainAfterExit` | bool | it counts as active after exiting |
| `schedule` | `schedule` | a named interval (`daily`) or a calendar expression (`Mon 03:00`) |
| `timeout` | `duration` | `30s`, `5min`, or a bare count of seconds |
| `stopCommand` | string | what stops it |
| `reloadCommand` | string | what reloads it |
| `extends` | list | typed extensions, below |

**Each unit carries its own `env`.** Two units of one service needing different
values for one variable is the ordinary case for a portable service, so it is
two records and no row. The entry's own `env` is the intersection — the
variables every unit of the entry agrees on, and nothing else — so a variable
one unit sets belongs on that unit.

A field whose value fails its type is `unit-field-type-mismatch` and is not
recorded. A name in `after` or `requires` that this module did not declare is
`unit-reference-unknown`: a unit reference is producible only by the module
that declared the unit it names, so no module can order itself against a unit a
stranger may rename. A key outside the vocabulary — a service manager's raw
stanza, for instance — is `implementation-unknown-key`.

### Unit extensions

A field one service manager has and the portable vocabulary does not is a typed
extension, declared beside the interfaces and imported like one:

```nix
# tests/unit/support.nix, where `korora` is that file's `k = planner.korora`
systemdService = planner.unitExtension {
  backend = "systemd";
  name = "systemd-service";
  fields = {
    protectSystem = {
      type = korora.enum "protect-system" [ "no" "yes" "full" "strict" ];
    };
    stateDirectory = { type = korora.string; };
  };
};
```

`backend` names the service manager whose fields it adds and is the only field
a check reads. `name` is a label, so two extensions in two files may carry one
`name` and stay distinct values: like an interface, an extension is
**identified by the value** and never by a name resolved at composition time.

A unit applies one by value, and asks the target before it does:

```nix
# tests/unit/units.nix
impl =
  { target, ... }:
  {
    units.web = {
      command = "/bin/web";
      env.PORT = "8080";
    }
    // (
      if target.serviceManager == "systemd" then
        {
          extends = [
            {
              extension = systemdService;
              values.protectSystem = "strict";
            }
          ];
        }
      else
        { }
    );
  };
```

`values` is a **subset** of `fields` rather than an equal keyset, because a
hardening extension exists to set two of thirty knobs, which is the opposite of
a capability's exports. Assigning a key the extension does not declare is
`unit-extension-unknown-field`; a value failing its field's type is
`unit-extension-type-mismatch`; an `extends` entry whose `extension` is not a
`planner.unitExtension` value is `unit-extension-missing`; an `extends` that is
not a list is `unit-extends-malformed`.

Applying an extension whose `backend` is not the target's `serviceManager` is
`unit-extension-backend-mismatch`, and **the fields are still recorded under
their own backend**. The plan writes them at `units.<name>.extends.<backend>`
either way, so a binding for that backend meets the fields it cannot render and
refuses knowingly instead of dropping them. That is what the conditional above
buys: the same module on a launchd machine writes the portable fields, no
`extends`, and no row.

### Configuration files

A configuration file names its bytes and never carries them.

| Key | Shape |
| --- | --- |
| `mode` | required, a string of octal digits — the mode a file is shown to a service with is a fact of the deployment and not of whoever wrote the bytes |
| `reload` | the units **this module declared** that this file is for; a file that names no unit reloads none |
| `source` | the store path holding the rendered file |
| `render` | the ordered recipe the machine concatenates |

**Exactly one of `source` and `render`.** Neither or both is
`config-file-disposition`. A missing or non-string `mode` is
`config-file-mode-missing`, a `reload` that is not a list is
`config-file-reload-malformed`, and a `reload` entry naming a unit this module
did not declare is `unit-reference-unknown`.

A recipe's items are `{ text = <public literal>; }` or `{ ref = <path>; }`,
exactly one of the two per item; anything else is `config-file-render-item`.
Which of the two a recipe holds is what decides the file's identity in the
plan:

| The file declares | The plan records | Because |
| --- | --- | --- |
| `source` | the path itself, and no digest | the bytes are already identified by a store path |
| `render` of literals only | the recipe and a `contentHash` over the concatenated fragments | the plan holds every byte it hashes |
| `render` carrying any `ref` | the recipe and a `structureHash` over the fragments and the reference paths — **no digest over the assembled bytes** | those bytes live at that path and the plan never reads them |

Write `render` when the content is computed at evaluation and exists in no
store path — the `authorized_keys` file above is a set-valued read rendered —
and `ref` when a fragment is a file on the machine, a secret's path being the
case that makes a digest over assembled bytes impossible in the first place.

### The declared closure

`closure` is the list of store path roots the entry depends on, **declared by
the implementation** rather than inferred from it:

```nix
# modules/borg-push/client.nix
closure = [
  borgbackup
  openssh
];
```

It is the list a consumer populates a filesystem from, and inference over an
entry's own strings cannot be complete, so the planner's scan is a **verifier
and not a source**. It reads the store root out of every string the entry
holds — the path inside the root is not part of it — and compares the roots to
the declaration:

- A root the entry mentions and the declaration does not name is
  `closure-path-undeclared`, an **error**, and the row names the path and where
  it was mentioned: a unit field, a unit's environment, an extension's values,
  a configuration file, a generated file's path or an export's value.
- A declared root the entry mentions nowhere is `closure-root-unmentioned`, a
  **warning** — it is either dead weight or a path assembled at runtime, and
  the second is worth having written down.

A `closure` that is not a list of strings is `closure-malformed`. Paths are
recognised against `mkPlan`'s `storeDir`, so a machine whose store lives
elsewhere is planned under its own.

### When a read is refused

Refusing a read and leaving something to default against would defeat the
exercise, so the planner leaves nothing:

- **`results` holds only the slots that delivered.** An unwired slot, a wire to
  an unknown instance, a refused `reads` entry — each leaves `results` without
  that key at all, measured: `results` is `{ }`, not `{ line = null; }`.
- The plan still records the slot at `reads.<slot>.delivered = false`, and the
  row says why.
- A module that dereferences a slot which did not deliver therefore hits a
  missing attribute, and **a missing attribute is one of the two things Nix
  does not let this library catch** (the other is `abort`). It propagates. The
  row is produced either way; forcing the entry that reads the missing value is
  what raises.

That is the trade this library is making: `or [ ]` cannot be written, so it
cannot silently succeed.

### Where a refusal lives

Every row is the planner's. A module has exactly one channel through which it
can refuse a value another module produced: the `fold` of an interface it
declares. A fold refuses by returning `{ refused = "<why>"; }`, and the split is
fixed — the fold states the message, the planner states the row's identifier
(`interface-fold-refused`), its subject (the consuming entry) and its severity
(error). The slot is then absent from `results`, as any refused read is.

Two consumers of one refused provider are two rows, one per consuming entry,
because each consumer is a subject of its own.

Nothing else is a channel:

- An `impl` returns `units`, `configData`, `provides` and `closure`. A key
  beyond those, `refusals` included, is `implementation-unknown-key`, and that
  row's resolution names the fold.
- A declaration writing `severity` is read and discarded with
  `module-declared-severity`, and every row the planner produced for that
  module keeps the severity the planner gave it.
- A module raising anywhere other than a fold is `module-raised`, which names
  what was being forced. The module's own text is not the message: `tryEval`
  reports that something raised and never what it said, which is the reason a
  refusal is a returned value rather than a `throw`.

## 3. Roots

A root composes members. It is a function of `{ service, ... }` — nothing else
is handed in, so a root that needs a package closes over it — and returns
`services` plus the capabilities it re-exports.

```nix
# fixtures/minimal-typed-edge/modules/borg-push/default.nix
{ borgbackup, openssh, sshHostIdentity, borgRepository }:

{ service, ... }:
let
  client = service "client" {
    module = import ../fixtures/minimal-typed-edge/modules/borg-push/client.nix {
      inherit borgbackup openssh sshHostIdentity borgRepository;
    };
    defaults.path = "/home";
  };
in
{
  services = { inherit client; };
  provides.identity = client.provides.identity;
}
```

`service "<name>" { module, defaults ? { }, fixed ? { } }`:

- `defaults` a deployment may overwrite; `fixed` it may not
  (`settings-fixed-path` names both files).
- **A root keys every member's settings under that member's own name, including
  when it owns exactly one member.** A deployment writing `settings.quota`
  instead of `settings.server.quota` is `settings-not-member-keyed`.
- A knob that is neither a default nor fixed is `settings-undeclared-knob`.
- Re-exporting under a different name still points at the member's own
  capability, so `wire` addresses the name the *instance exposes*.
- A member's declaration is read **once**, against the settings its instance
  resolved, so the capabilities a root publishes and the exports the placement
  produces come from one value.
- A capability set may therefore be derived from a member's settings. A root
  over such a member forwards the whole set — `provides = main.provides;` —
  rather than naming a capability, because a name written in the root is a name
  chosen before the deployment has said anything. The knob the set comes from
  is an ordinary default or fixed value with no extra status.

## 4. The deployment

Two files by convention: the machine registry and the instances.

```nix
# deployment/machines.nix
{
  machines = {
    vault = {
      address = "vault.example";
      tags = [ "always-on" ];
      system = "x86_64-linux";
      serviceManager = "systemd";
    };
    alpha = {
      address = "alpha.example";
      tags = [ "always-on" "backed-up" ];
      system = "x86_64-linux";
      serviceManager = "systemd";
    };
  };
}
```

| Key | Is |
| --- | --- |
| `address` | how a consumer reaches the machine, and what an `impl` on it receives as `target.address` |
| `tags` | what a placement selects on |
| `system` | the system string, elaborated into the platform record every entry's `target` carries — **required once a placement selects the machine** |
| `serviceManager` | what runs the machine's units — **required once a placement selects the machine** |
| `microarchitecture` | optional; becomes the record's `gcc.arch` and `gcc.tune`, **replacing** whatever codegen group the platform itself carries, and is recorded on the machine entry when declared |

A machine declares those five keys and nothing else. A machine a placement
selected that declares no `system` or no `serviceManager` is
`machine-target-incomplete`, whose row names the missing keys and how many
entries are placed on it: a placement on such a machine has no derivable
target, so no `impl` on it is handed one. A machine nobody is placed on may
declare neither and produces no row.

`system` is elaborated once per distinct system and microarchitecture in the
fleet rather than once per machine, and a system string nixpkgs cannot parse is
a row rather than a raise.

```nix
# deployment/instances.nix
{
  instances = {
    vault-repo = {
      module = borgRepo.services.default;          # the root function
      settings.server.quota = 500;                 # member-keyed
      placement.every.server = { machines = [ "vault" ]; };
      wire.clients = { instance = "nightly"; provides = "identity"; };
      exposes = [ "repo" ];
    };

    nightly = {
      module = borgPush.services.default;
      settings.client.path = "/home";
      placement.every.client = { tags = [ "backed-up" ]; };
      wire.repo = { instance = "vault-repo"; provides = "repo"; };
      exposes = [ "identity" ];
    };
  };
}
```

| Key | Meaning |
| --- | --- |
| `module` | the root function |
| `settings.<member>.<knob>` | overrides a default the member declared |
| `placement.every.<member>` | `{ machines ? [ ], tags ? [ ] }`, unioned; an unknown machine is a row, a member on no machine is a row |
| `wire.<slot>` | `{ instance, provides }` — the far end, named once, by the deployment |
| `exposes` | which of the root's capabilities other instances may wire to |

**Only what the instance exposes is addressable.** Wiring to a capability the
root provides but the instance does not expose is
`wire-capability-not-exposed`, whose row lists what *is* exposed.

Note what the deployment does **not** write: not the arity of a read (the
consuming module's `reach` decides it), and not the far end's machine list (the
far instance's placement decides it). The two wires above point at each other
and the graph is still acyclic, because a capability's exports are a function
of module and settings and never of a `wire`.

## Generated files

`varsState` tells the planner which generated files exist, keyed by the entry of
the value they belong to:

```nix
varsState."nightly:vars/hostKey@alpha" = {
  "ssh_host_ed25519_key" = { present = true; };
  "ssh_host_ed25519_key.pub" = { present = true; content = "ssh-ed25519 AAAA… root@alpha"; };
};
```

`<instance>:vars/<generator>@<machine>` for a `per = "placement"` value and
`<instance>:vars/<generator>` for a `per = "instance"` one, so that one value
has one answer about whether it exists no matter how many machines receive it.

A value the state does not name has not run its generator. Reading its public
half through a slot is a `set-entry-absent` **error** naming that machine: the
entry stays in the set with a null value and an absent marker, and any artifact
rendered over the set — the `authorized_keys` file above — is recorded as **not
computed** rather than hashed over the entries that do have values.

That single behaviour is the whole argument of the worked example. A fold with
`or [ ]` produces a two-line file and a healthy service; this produces a row
naming `gamma` before anything is deployed.
