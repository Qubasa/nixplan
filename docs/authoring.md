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

An interface is a value you import. It is identified by that value or by an
identity it claims, validated against no registry, and its `name` is a label for
diagnostic output only. Two interfaces in two files may carry the same `name` —
wiring one to the other is an `interface-mismatch` row that prints both
declaring files.

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
this library owns, and the three constructors — `interface`, `unitExtension` and
`fold`.

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

**An interface may claim an identity with `id`.** It is optional, it is a claim
rather than a registration — an interface absent from every `interfaces` map is
still an interface, and a claim makes none of them known to the planner — and
**both** ends of a wire must claim before a claim is used: where either end
claims nothing, two interfaces are one interface only when they are one value.
Two authors evaluating this library twice hold unequal values of one shape, and
a claim is what wires them:

```nix
# interfaces/default.nix, continued
sshHostIdentity = korora.interface {
  id = "example.com/ssh-host-identity";
  name = "ssh-host-identity";
  exports = { publicKey = { type = korora.string; }; };
};
```

| Fact | Consequence |
| --- | --- |
| an identity is the `id`, each export's name, korora type name and resolved secrecy, and the fold's name | two interfaces claiming one `id` whose identities differ are `interface-id-conflict`, an error, and an edge between them is refused |
| a claim carries no function | it survives two evaluations of this library, which value equality does not |
| an `id` is a non-empty string carrying no whitespace | anything else is `interface-id-malformed` and the claim is disregarded: the interface is identified by its value |
| an `id` carrying neither `.` nor `/` | `interface-id-unnamespaced`, a warning: it identifies exactly as a qualified one does, and the namespace is shared with every other author |
| a claim decides only whether an edge exists | each side verifies its own values against the type it imported, and two korora types sharing one name are one type for identity however differently they verify |

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
| its output is whatever its consumers can use | a fold returns records, and rendering bytes from them is the consuming implementation's, because one interface has one fold and any number of consumers |
| the planner forces it under a guard | a fold that raises is `interface-fold-raised` and the slot is then **absent** from `results`, the same as any refused read |
| a fold that is not a function | `interface-fold-not-a-function` against the interface's declaring file, rather than an error at the read |
| a fold no set-valued read applies | `interface-fold-unapplied`, a warning: a policy nobody applies is a policy nobody is held to |
| a fold may carry a name | `fold = korora.fold "<name>" (set: …)`, which behaves in every respect as the bare function it carries |
| an interface claiming an `id` needs a named fold | a fold's name is part of an identity and a bare function supplies none, so a claim beside a bare fold is `interface-id-unnamed-fold` and the claim is disregarded; an interface claiming nothing may spell its fold either way |
| a fold name that is not a non-empty whitespace-free string | `interface-fold-name-malformed` against the declaring file, and the fold is not applied: the read delivers the provider-keyed set unchanged |

An interface that declares no fold delivers the set unchanged, keyed by
provider entry, which is what every interface in `fixtures/minimal-typed-edge/`
does.

## 2. Leaf modules

A leaf module is a function of `{ settings, ... }` returning a declaration. It
declares eight keys at most; anything else is a row.

| Key | Shape |
| --- | --- |
| `platforms` | list of system strings |
| `claims.ports.<name>` | `{ proto, fixed, address }` — `fixed` is required and is an integer of 1 to 65535, the planner allocates nothing. `proto` is one of `tcp` / `udp`, and an unstated one claims the number on every protocol of the domain. `address` is the one address the listener binds, and an unstated one is every address of the machine, which is the only spelling of the wildcard |
| `vars.<generator>` | `{ files.<file> = { secrecy }, per ? "placement", deploy ? true, reads ? [ ], program ? <store path> }` — below |
| `uses.<slot>` | `{ interface, reach ? "one", reads ? <every export> }` |
| `provides.<capability>` | `{ interface, consumers ? "many" }` |
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
declares one, `results.clients` is the folded value and the consumer renders
its own file from it. A second interface is for a different policy, never for
a different output format: two consumers that write the same host keys as an
`authorized_keys` file and as a `known_hosts` line read one interface and
render twice.

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
| `files.<file>.owner`, `.group` | the account and group the file is delivered to, as names rather than identifiers, both defaulting to `root`. A value that is not a portable account name is `vars-file-ownership-malformed` and the default is delivered |
| `files.<file>.mode` | the permission bits it is delivered at: four octal digits, defaulting to `"0400"`. `640`, `"0999"` and `"rw-r-----"` are `vars-file-ownership-malformed` |
| `per` | `"placement"` (the default) is one value per machine the owner is placed on; `"instance"` is one value for the instance however many machines run it |
| `deploy` | `false` means no machine receives the bytes. One value still exists, so a public file's value still travels in the plan, and anything that would open one of its files on a machine is refused |
| `reads` | sibling generators of the same module. A `"placement"` generator may read an `"instance"` one; the reverse is `vars-reads-arity`, because the placements hold one value each and the reader is one value |
| `program` | the store path of the program that produces the files, recorded as a literal string and neither run nor read here. A declaration that is not exactly one store path is `vars-program-malformed`; omitting the key is valid, and the reader that needs a program is what refuses |

A file's path is `/run/vars/<instance>/<generator>/<file>`, the same on every
machine that receives it: one delivery of one value has one name. Two members of
one instance declaring the same generator name is `vars-generator-claimed-twice`
— a generator is addressed by instance and name, so the two declarations would
be one address for two values.

The ownership and mode are one value's, not one machine's: every machine in the
delivery set holds the file the same way. A unit of an entry that reads such a
file and runs as an account the record does not admit is
`slot-reads-value-unreadable-by-user` — the planner compares the unit's `user`
and the groups it declares against the record, so a service that cannot open its
own credential is a row rather than an `EACCES` at start. A unit declaring no
`user` is root and is admitted by every record.

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
impl = { instance, member, machine, target, settings, vars, alloc, results }: { … };
```

| Field | Is |
| --- | --- |
| `instance` | the instance name this placement belongs to |
| `member` | the member name this placement is, which is the attribute key its composing root declared it under. The pair `instance` and `member` is what every plan key of this member is built from, so a path or a directory named after the two is unique among the entries of one machine by construction - which is what `entry-host-path-claimed-twice`, `entry-port-claimed-twice` and `entry-unit-directory-shared` resolve to |
| `machine` | the machine name, or `null` at a member no placement selected |
| `target` | `{ system, serviceManager, address }` — the reduced platform record of the machine's system, the service manager that runs its units, and the address it is reached at. All three are present at every placed entry. **Absent** at a member no placement selected |
| `settings` | resolved settings: defaults, then the deployment, then `fixed` |
| `vars.<gen>.<file>` | `{ present, secrecy, path, content }` — `content` is `null` for a secret or an ungenerated file |
| `alloc.ports.<claim>` | the fixed port the claim declared |
| `results.<slot>` | **only the slots that delivered** (see below) |

Those eight and nothing else. `target` is **absent** rather than null where
there is no placement to have a target, so an `impl` that destructures
`{ target, ... }` or reads `args.target` unconditionally raises at an unplaced
member — and that raise propagates for the same reason a refused read's does
(below). Read it under `machine != null`, or write the module so only a placed
member forces the value. A machine that declares no `address`, no `system` or
no `serviceManager` has no derivable target, and that case is
`machine-target-incomplete` on the registry: the placement onto such a machine
is dropped rather than planned, so no `impl` is handed a partial target.

A planned entry's target therefore carries all three fields. Read
`target.address` plainly: there is no machine a placement selected for which it
is absent, and `target ? address` guards nothing.

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
| `restart` | `restartPolicy` | what the service manager does when it stops: `no`, `on-failure`, `on-abnormal`, `always` |
| `restartSec` | `duration` | how long to wait before restarting; recordable only beside a `restart` |
| `stateDirectory` | list of `directoryName` | directories the service manager creates and keeps, relative to the root that kind implies |
| `runtimeDirectory` | list of `directoryName` | the same, deleted when the unit restarts |
| `cacheDirectory` | list of `directoryName` | the same, a cache the machine may drop |
| `stateDirectoryMode` | `fileMode` | the mode those state directories are created at; recordable only beside one |
| `runtimeDirectoryMode` | `fileMode` | the same for `runtimeDirectory` |
| `cacheDirectoryMode` | `fileMode` | the same for `cacheDirectory` |
| `startIfPathPresent` | `absolutePath` | it runs only while that path exists |
| `startIfPathAbsent` | `absolutePath` | it runs only while that path does not |
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

**A unit file is line oriented.** A value carrying a line break is
`unit-value-newline`, wherever the record holds it: a command, an environment
value, an element of a list, a field of an extension. The row names the field
path, and the rule is over the record rather than over a list of fields, so a
field added later is covered by it. A space, a quote and a backslash are facts a
unit file can carry and are no row: escaping them is the renderer's work.

**The restart domain is four values, not a service manager's seven.** The other
three systemd carries are meaningless without a `Type=` or a `WatchdogSec=` this
vocabulary does not carry, so a renderer maps these four to whatever its own
manager calls the same thing. A value outside the four is
`unit-field-type-mismatch`, and the row's evidence names the four.

A restart policy is read against the shape the unit already declared, and a
contradiction is a row rather than a value a renderer has to reconcile. A
`oneShot` unit asking for `always` is `unit-restart-contradicts-one-shot`: a unit
that applies and exits successfully would be restarted for as long as it keeps
succeeding. `on-failure` on a `oneShot` unit is a legitimate shape and no row. A
unit declaring a `schedule` and any policy but `no` is
`unit-restart-on-scheduled`, because the timer already decides when it runs. A
`restartSec` with no `restart` is `unit-restart-delay-without-policy`. In each
case the field is not recorded, so no renderer is handed two statements about
when the unit runs.

**A directory is declared, not made.** The three kinds are the three a service
manager creates for a unit and owns on its behalf, and a mode is per kind
because that is the grain one is applied at. A name is relative to the root its
kind implies, so a name stating a root of its own fails `directoryName` and is
`unit-field-type-mismatch` rather than earning an identifier: the kind decides
where the directory lives. A mode beside no directory of its kind is
`unit-directory-mode-without-directory`, the shape
`unit-restart-delay-without-policy` already has, and the mode is not recorded.
One kind declared both here and in a backend extension application is
`unit-directory-declared-twice` and neither statement is recorded: a renderer
handed two statements about one directory has no way to choose. A directory is a
claim against the machine either way, so two entries of one machine recording
one of them is `entry-unit-directory-shared` whichever site declared it.

**A condition is one path and a polarity.** `startIfPathPresent` and
`startIfPathAbsent` are what replaces a shell test inside the unit's own
command, so a step that runs once is a declaration the service manager honours.
One path stated as both is `unit-condition-contradicts-itself` - the unit would
be skipped whether the path is there or not - and neither condition is recorded.
A relative path fails `absolutePath` and is `unit-field-type-mismatch`: a
relative path resolves against nothing the plan records.

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
| `owner` | a `userName`, defaulting to `root` |
| `group` | a `groupName`, defaulting to `root` |
| `reload` | the units **this module declared** that this file is for; a file that names no unit reloads none |
| `source` | the store path holding the rendered file |
| `render` | the ordered recipe the machine concatenates |

**Exactly one of `source` and `render`.** Neither or both is
`config-file-disposition`. A missing or non-string `mode` is
`config-file-mode-missing`, a `reload` that is not a list is
`config-file-reload-malformed`, and a `reload` entry naming a unit this module
did not declare is `unit-reference-unknown`.

**The record is the same three fields a generated value's file record carries**,
with the same rule about the key: only the fields a declaration actually stated
enter the entry's own key, so a file stating no ownership keys exactly as it did
before the two fields existed. `mode` is always in it, being required. A value
failing either type is `config-file-ownership-malformed`, and the record then
carries the default rather than the failing value.

The ownership is read wherever the file meets an account. A unit of the entry
running as an account the record does not admit is
`entry-config-file-unreadable-by-user`; the same comparison against a profile's
imposed account is the image realiser's denial, and a realiser that binds store
objects rather than installing files refuses a record a store object cannot
carry (`operator-entry-path-not-installable`).

**A host path is one shell word.** The attribute name reaches a generated shell
script of the realisation, so it is held to ASCII letters, digits and
`_`, `.`, `/`, `:`, `@`, `%`, `+`, `=`, `,`, `~`, `-`. A path outside that is
`config-file-path-refused` and the file is left out of the entry record, the way
a name carrying a key separator is left out of every key it would have entered.
It is the same grammar the delivery step's paths and addresses are held to.

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
- **One unguarded read ends the whole table.** `applicable` forces every row of
  every entry, so an implementation that reaches an absent slot leaves nothing
  rendered for any entry at all: the row was produced, and no table survives to
  carry it.

That is the trade this library is making: `or [ ]` cannot be written, so it
cannot silently succeed.

The one read worth guarding is a slot whose interface declares a `fold` that
can refuse, because that is the only refusal whose message an author wrote.
Read it as `if results ? <slot> then … else …` and the fold's own message
renders. Every other refused read is a wiring row the planner produced before
any implementation ran — an unwired slot is `slot-unwired` whatever the module
does next — so those slots are read unguarded, and guarding one would hide a
wiring mistake behind a fallback.

### Where a refusal lives

Every row is the planner's. A module has exactly one channel through which it
can refuse a value another module produced: the `fold` of an interface it
declares. A fold refuses by returning `{ refused = "<why>"; }`, and the split is
fixed — the fold states the message, the planner states the row's identifier
(`interface-fold-refused`), its subject (the consuming entry) and its severity
(error). The slot is then absent from `results`, as any refused read is.

Two consumers of one refused provider are two rows, one per consuming entry,
because each consumer is a subject of its own.

Whether that refusal is rendered is the consuming module's decision, never a
planner behaviour that varies. The row, the undelivered read and the
inapplicable plan are produced identically either way; only the forcing of the
absent slot decides whether a table exists to print them. A consumer of a
refusing fold that reads `results.<slot>` unconditionally ends the evaluation
with a missing attribute, and the fold's message goes with it.

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

`service "<name>" { module, defaults ? { }, fixed ? { }, wire ? { } }`:

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

### Binding one member's slot to another's capability

`wire.<slot>` on a member is the root filling that slot itself, with the
capability **value** off a sibling's handle:

```nix
{ service, ... }:
let
  db = service "db" { module = postgres; };
  app = service "app" {
    module = api;
    wire.database = db.provides.database;
  };
in
{
  services = { inherit db app; };
  provides.database = db.provides.database;
}
```

- The value is a capability, never a name: a mistyped attribute is a Nix error
  in the module's own file, and a binding therefore carries no instance name —
  a root that could name an instance would be a module naming a deployment.
  A binding that is not one of the root's own capabilities is
  `binding-malformed`, and one naming a slot the member does not declare is
  `binding-unknown-slot`.
- A bound slot needs no deployment statement and is subject to **every** check a
  wire is: one interface, `reach` against the bound capability's placements, and
  every declared read resolved against the bound provider's exports.
- A member name and a slot name may not collide, because a deployment's `wire`
  addresses both: `member-and-slot-name-collide`.

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
| `address` | how a consumer reaches the machine, and what an `impl` on it receives as `target.address` — **required once a placement selects the machine** |
| `tags` | what a placement selects on |
| `system` | the system string, elaborated into the platform record every entry's `target` carries — **required once a placement selects the machine** |
| `serviceManager` | what runs the machine's units — **required once a placement selects the machine** |
| `microarchitecture` | optional; becomes the record's `gcc.arch` and `gcc.tune`, **replacing** whatever codegen group the platform itself carries, and is recorded on the machine entry when declared |
| `reserves` | optional; the host resources the machine already holds outside the deployment, `{ ports.<name> = { proto, number }; paths = [ … ]; }`, checked against what the entries placed on it claim and recorded in no plan field |

A machine declares those six keys and nothing else. A machine a placement
selected that declares no `address`, no `system` or no `serviceManager` is
`machine-target-incomplete`, whose row names the missing keys and how many
entries the deployment places on it. Every placement onto such a machine is
dropped rather than planned, because a module reading a field of a partial
target is a missing attribute the planner can neither catch nor report, and the
machine's own record is still in the plan. A machine nobody is placed on may
declare none of the three and produces no row, so a registry may list a machine
that has not been provisioned yet.

Completeness is read off the value the registry reading produced, so a machine
declaring `address = 22` is as incomplete as one declaring nothing: it earns
both `declaration-field-malformed` and `machine-target-incomplete`.

`reserves` states the host resources the machine's own image already holds,
outside the deployment entirely:

```nix
reserves = {
  ports.sshd = {
    proto = "tcp";
    number = 22;
  };
  paths = [ "/etc/ssh/sshd_config" ];
};
```

A reserved resource is a claimant of the collision index beside the entries
placed on that machine, keyed `machine:<name>`: a port an entry claims with the
same protocol and number earns `entry-port-claimed-twice`, and a path an entry
writes a configuration file to earns `entry-host-path-claimed-twice`. An absent
statement checks nothing, so a registry written before the key existed produces
the plan and the table it always produced. No plan field records the statement
and no realiser reads it: it opens no port, renders no socket unit and creates
no file. The planner never reads the machine either, so a reservation is a
declaration and never a probe, and a reserved path that does not exist is no
row.

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
| `members.<member>.enable` | `false` cuts the member: it produces no entry at all |
| `wire.<slot>` | `{ instance, provides }` — the far end, named once, by the deployment |
| `wire.<member>.<slot>` | the same, for one member's own slot, which is how a slot a cut opened is filled |
| `exposes` | which of the root's capabilities other instances may wire to |

**Only what the instance exposes is addressable.** Wiring to a capability the
root provides but the instance does not expose is
`wire-capability-not-exposed`, whose row lists what *is* exposed.

Note what the deployment does **not** write: not the arity of a read (the
consuming module's `reach` decides it), and not the far end's machine list (the
far instance's placement decides it). The two wires above point at each other
and the graph is still acyclic, because a capability's exports are a function
of module and settings and never of a `wire`.

### Cutting a member

An instance may state that a member of the module it names does not exist:

```nix
instances.eu = {
  module = myGame.services.default;
  members.db.enable = false;                                  # the cut
  placement.every.server = { machines = [ "alpha" ]; };
  wire.server.db = { instance = "pg-shared"; provides = "database"; };
};
```

- A cut member takes no placement, needs no settings, owns no generated value,
  contributes no closure and produces **no plan entry of any kind**. A member
  the deployment does not mention is kept, so an instance writing no `members`
  block keeps the whole composition.
- `members.<name>` admits exactly one key, `enable`. A name the root does not
  own is `members-unknown-member`.
- Placing, configuring or wiring a member the same deployment cut is
  `cut-member-named`, whose resolution names both ways out.
- **A slot the module bound to a member the deployment cut becomes an ordinary
  unfilled slot**, and `wire.<member>.<slot>` is how the deployment fills it.
  No line of the module differs between the two cases: what decides whether a
  reference is a binding or an address is whether its target is a kept member.
  Left unwired it is the ordinary `slot-unwired` row, whose evidence names the
  cut.
- Wiring a slot the root binds to a member the instance **keeps** is
  `wire-names-bound-slot`: the two statements disagree about what the
  composition is, and the binding resolves the slot.

### How many consumers a capability admits

`provides.<capability>.consumers` is `"many"` (the default) or `"one"`. A
capability declaring `"one"` that two slots wire is
`capability-consumers-exceeded`, one row for the capability naming both slots.
The count is over wires across the whole deployment, so a consumer placed on
twelve machines is one consumer, and two capabilities of one instance taken by
two consumers is no row.

The cardinality is a property of the capability the member declared, and it is
read by that member's own capability name. What an instance root's `provides`
decides is which name a wire may address; how many wires may take the capability
stays the member's statement. Re-exposing it under another name, or under two
names at once, therefore admits the same number of consumers, and a wire naming
any of those names counts against that one capability.

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
