# The plan artifact

The plan is the only thing the two halves of an architecture have to agree on,
so its shape is a contract rather than an output format.

**A plan is flat, keyed, and free of expressions.** Values are strings, numbers,
booleans, lists and attribute sets — no functions, no derivations, and no store
path that is not a literal string. `builtins.toJSON` succeeds on it and reading
it back yields an equal value.

## Entry keys

| Key shape | Is |
| --- | --- |
| `<instance>:<service>@<machine>` | a placed service |
| `<instance>:vars/<generator>` | a generated value that exists once for the instance |
| `<instance>:vars/<generator>@<machine>` | a generated value that exists once per placement |
| `<instance>:<service>` | a service no placement selected: it runs nowhere, so it carries no machine, no target, no closure and nothing it depends on |
| `machine:<name>` | a machine that carries a placement |

A key is **structural**: it is decided by placement alone and never by whether a
member produced units, because two instances that wire each other would then
each need the other's units to know their own key.

An empty attribute set or list is an absence rather than a fact, so it is not
written. `nightly:client@alpha` has no `alloc` because it claims no ports.

## A service entry

```json
"nightly:client@alpha": {
  "key": "sha256-2d3474aed7b9bb34",
  "placement": { "reason": "every", "tags": ["backed-up"] },
  "storeDir": "/nix/store",
  "target": { "address": "alpha.example", "serviceManager": "systemd", "system": { "system": "x86_64-linux", "config": "x86_64-unknown-linux-gnu", … } },
  "closure": ["/nix/store/…-openssh-9.8p1", "/nix/store/…-borgbackup-1.4.0"],
  "dependsOn": ["machine:alpha@sha256-5840440439b3bbf1"],
  "units": {
    "borgPush": {
      "command": "…/bin/borg create --stats ssh://borg@vault.example:22/srv/borg::{now} /home",
      "env": { "BORG_QUOTA_GIB": "500", "BORG_RSH": "…/bin/ssh -i /run/vars/nightly/hostKey/ssh_host_ed25519_key" }
    }
  },
  "env": { "BORG_QUOTA_GIB": "500", "BORG_RSH": "…/bin/ssh -i /run/vars/nightly/hostKey/ssh_host_ed25519_key" },
  "settings": { "client": { "path": { "source": "deployment", "value": "/home" } } },
  "vars": { "hostKey": { "files": { "ssh_host_ed25519_key": { "secrecy": "secret", "inPlan": "reference", "deploy": true } } } },
  "provides": { … },
  "reads": { … }
}
```

This entry claims no ports and renders no file, so it carries neither `alloc`
nor `configData`; `vault-repo:server@vault` carries both. It has one unit, so
its `env` and that unit's `env` hold the same variables — they are not the same
field, and the table below says why.

| Field | Contract |
| --- | --- |
| `key` | a hash over instance, service, machine, that machine's key, the target it was planned for, its pin, its units, its declared closure, the store directory, its configuration data, its resolved reads, its settings and its allocated ports. Two evaluations of one input produce equal keys; an unrelated edit moves nothing |
| `placement` | `reason` plus the `machines` or `tags` that selected it |
| `storeDir` | the store directory the entry's paths are read against and the one a consumer populates, so a machine whose store lives elsewhere is planned under its own |
| `target` | `{ system, serviceManager, address }`: the reduced platform record of the machine's system, what runs its units, and the address it is reached at. Each field is present only where the registry declared it, and the whole record is absent at an entry no placement selected |
| `closure` | the store path roots the implementation **declared**, as literal strings. The planner's scan verifies them and never produces them |
| `pin` | `{ key, locked }`, the lock entry the resolver handed the module. Recorded, never verified; absent when the module declares none |
| `dependsOn` | keys that appear elsewhere **in the same plan**, each carrying the depended-on entry's own key hash |
| `units.<name>` | one unit: `command` and whichever other vocabulary fields it declared, its own `env`, and `extends.<backend>` for the typed extensions it applied |
| `env` | the variables **every unit of the entry agrees on**, and nothing else. A unit's environment lives on the unit, so two units disagreeing about a variable is two records and no row |
| `configData."<path>"` | `{ mode, reload, computed }` plus the file's identity, below |
| `settings.<member>.<knob>` | `{ value, source }` where source is `defaults`, `deployment` or `fixed` — every resolved value records where it came from |
| `vars.<gen>.files.<file>` | `{ path, secrecy, inPlan, deploy }`, plus `bytes: "absent"` when the generator has not run. The path is the same on every machine that receives the value, and `deploy` is what tells a realiser whether bytes arrive at it: a realiser shows a path to a unit only where they do |
| `alloc.ports.<claim>` | the fixed port |

## A machine entry

```json
"machine:beta": {
  "key": "sha256-a515feee51d2fc42",
  "address": "beta.example",
  "tags": ["always-on", "backed-up"],
  "system": "aarch64-linux",
  "serviceManager": "systemd"
}
```

`address` and `tags` always; `system`, `serviceManager` and
`microarchitecture` when the registry declared them. `key` is a hash of the
whole registry record, and it is the hash a placed entry's `dependsOn` carries,
so editing a machine's `serviceManager` re-keys every entry on it. The system
string stays a string here — the elaborated platform record lives on each
entry's `target.system`, once per placement rather than once per machine.

## A generated value entry

```json
"nightly:vars/hostKey@alpha": {
  "key": "sha256-b219c0b316cb1464",
  "per": "placement",
  "deploy": true,
  "delivery": ["alpha", "vault"],
  "deliveryDerivedFrom": ["nightly:client@alpha owns it", "vault-repo:server@vault named publicKey in uses.clients.reads"],
  "dependsOn": ["machine:alpha@sha256-5840440439b3bbf1"],
  "files": {
    "ssh_host_ed25519_key": { "path": "/run/vars/nightly/hostKey/ssh_host_ed25519_key", "secrecy": "secret", "inPlan": "reference", "deploy": true }
  }
}
```

A generated value is an entry rather than a record inside the entries that read
it, because a machine may receive a value while running none of the services
that read it, and a `per = "instance"` value has no single placement to live in.

| Field | Contract |
| --- | --- |
| `key` | a hash over instance, generator, cardinality, `deploy`, the file records and `dependsOn`. The machine reaches a `per = "placement"` value's key only through `dependsOn`, as for a service entry. The delivery set is deliberately **not** in it: a machine joining because a new consumer declared a read does not change the value, and re-keying it would ask for a regeneration of bytes that are still correct |
| `per` | `"instance"` — one value for the instance — or `"placement"`, one per machine the owner is placed on |
| `deploy` | whether any machine receives the bytes. Independent of `per`: one value may exist and no machine receive it |
| `delivery` | the machines that receive the bytes, sorted. Always present, empty or not: a delivery set is a field a reader must not be able to mistake for an absence |
| `deliveryDerivedFrom` | why each machine is in the set, sorted: the owning entry, and for a reader the entry, the slot and the export it declared. Always present, for the same reason |
| `reads` | the sibling values' entry keys, absent when it reads none |
| `dependsOn` | the sibling entries it reads, plus its own machine entry when `per = "placement"` |
| `files` | the file records, keyed by file name. Always present, empty or not, for the reason `delivery` is: a generator declaring no file records an empty set rather than no field |
| `files.<file>` | `{ path, secrecy, inPlan, deploy }` plus `bytes: "absent"` when the generator has not run |
| `program` | the store path of the program that produces the files, as the generator declared it. **Absent** where none was declared, and it takes part in the entry's key only where one was, so a plan written before this field existed is keyed as it was. It is the one store path in a plan the closure scan does not hold against a declared closure: a generator runs where the plan is read, never on a machine receiving its output — see [secrets.md](secrets.md) |

The set is derived from the owner's placements plus the machine of every entry
that **declared** a read of an export backed by one of these files — not from
the value, not from the interface, and not from what `impl` interpolates. A
consumer that omits an export from `uses.<slot>.reads` does not receive it, and
the export is absent from its `results` rather than null, so the omission cannot
be defaulted around.

## The platform record

`target.system` is the projection of one `lib.systems.elaborate`, reduced to
what a cross build spends:

```json
"system": {
  "system": "armv7l-linux",
  "config": "armv7l-unknown-linux-gnueabihf",
  "libc": "glibc",
  "useLLVM": false,
  "linuxArch": "arm",
  "parsed": { "cpu": { "name": "armv7l", "bits": 32, "family": "arm", "…": "…" },
              "kernel": { "name": "linux", "execFormat": { "name": "elf" } },
              "abi": { "name": "gnueabihf", "float": "hard", "eabi": true } },
  "gcc": { "arch": "armv7-a", "fpu": "vfpv3-d16" }
}
```

`system` and `config` select the toolchain, `libc` and `parsed` are what a
build has to agree with, `linuxArch` is the kernel's own name for the
architecture, and `gcc` is the codegen group — `abi`, `arch`, `cmodel`, `cpu`,
`float`, `float-abi`, `fpu`, `long-double-format`, `mode`, `strict-align`,
`thumb`, `tune` — that cc-wrapper and GCC itself spend. It is absent when
the elaboration carries none of them, as on `x86_64-linux`.

The record is a `crossSystem` fragment that replays: elaborating
`{ system, gcc }` from a record reproduces it. A platform's own codegen
defaults are therefore recorded for a machine that declared no
`microarchitecture`, and a declared one **replaces** that group rather than
merging into it — declaring one on `armv7l-linux` drops the platform's `fpu`,
exactly as the same `crossSystem` would.

The `is*` predicates are **not** in the record. Each is a function of `parsed`
(`isLinux` is `parsed.kernel.name == "linux"`, `is64bit` is
`parsed.cpu.bits == 64`), so carrying all seventy-five would put derived data in
every entry, in every key and in every plan diff. Derive the one you need, or
elaborate the `system` string for the whole family.

## What a capability publishes

```json
"provides": {
  "identity": {
    "interface": "ssh-host-identity",
    "declaringFile": "interfaces/default.nix",
    "keysetEqualsInterface": true,
    "exports": {
      "publicKey": {
        "value": "ssh-ed25519 AAAA… root@alpha",
        "secrecy": "public",
        "plane": "env",
        "readBy": ["vault-repo:server@vault"]
      },
      "privateKey": {
        "value": "/run/vars/nightly/hostKey/ssh_host_ed25519_key",
        "secrecy": "secret",
        "plane": "reference",
        "readBy": []
      }
    }
  }
}
```

- **A secret is a path reference.** Its bytes appear nowhere in the plan — the
  suite greps the serialised plan for the fixture's secret bytes and asserts
  their absence.
- **An export delivered to nobody is still recorded**, with an empty reader
  list. The empty list is a fact about that export, not a reason to drop it.
- **An absent export** carries `value: null`, `bytes: "absent"` and `rows`, one
  reference per reading entry, so a null value in the plan leads to the refusal
  instead of standing beside it.
- `interface` is the interface's `name`, and `declaringFile` is where it was
  declared — the pair is what makes two same-named interfaces distinguishable.
- `interfaceId` is the identity that interface claimed, and it is **absent**
  where nothing was claimed: never null and never the interface's name, so a
  reader cannot mistake an unclaimed interface for one claiming its own label.
  No interface in `fixtures/minimal-typed-edge/` claims one, which is why the
  record above carries no such field. A claim does not re-key an entry.

## What a read records

Single-valued (`reach = "one"`):

```json
"repo": {
  "delivered": true,
  "entry": "vault-repo:server@vault",
  "reach": "one",
  "reads": ["url", "quota"],
  "values": { "url": "ssh://borg@vault.example:22/srv/borg", "quota": 500 },
  "wire": { "instance": "vault-repo", "provides": "repo" }
}
```

Set-valued (`reach = "all"`), keyed by entry even at one placement:

```json
"clients": {
  "delivered": true,
  "reach": "all",
  "entries": {
    "nightly:client@alpha": { "publicKey": "ssh-ed25519 AAAA… root@alpha" },
    "nightly:client@beta":  { "publicKey": "ssh-ed25519 AAAA… root@beta" },
    "nightly:client@gamma": {
      "publicKey": null,
      "bytes": "absent",
      "row": { "id": "set-entry-absent", "subject": "vault-repo:server@vault" }
    }
  }
}
```

**A set names its entries.** The absent one is a named entry with a null value,
a marker and the row it produced — never a shorter list. That is the single
behavioural difference the worked example exists to demonstrate.

A read that did not deliver records `delivered: false` and the row says why; the
module's `results` does not contain the slot at all.

## Planes

Where a value arrived decides what changing it does. An export record's `plane`
takes exactly two values; every other place a value can land is a field of its
own rather than a `plane` string.

| Recorded as | Means | Changing the value |
| --- | --- | --- |
| `plane: "env"` | a public export a unit reads from its environment | moves the reader's key, not its closure |
| `plane: "reference"` | a secret export: a path to bytes the plan never holds | the plan is unchanged until the bytes are regenerated |
| `units.<name>.env.<var>` | a variable **that one unit** runs with | moves the entry's key; the entry's own `env` carries it only while every unit agrees on it |
| `units.<name>.extends.<backend>.<field>` | a field of one service manager, applied by value | moves the entry's key, and nothing outside that backend's rendering |
| a `configData` file's `source`, `contentHash` or `structureHash` | that file's identity | moves the identity and reloads the units the file named |
| the `closure` list | a store path root the implementation **declared** | moves the closure |
| `pin` | the lock entry the roots were resolved from | moves every entry built from it |
| `target.system` | the platform record the entry was planned for | re-keys every entry placed on that machine |

A generated file records the same distinction from the other side, as
`vars.<gen>.files.<file>.inPlan`: `"value"` for a public file, whose bytes an
implementation may interpolate into a unit's environment or a rendered
configuration file, and `"reference"` for a secret one, which the plan only ever
names by path. No file record carries bytes either way — it carries the path,
and `bytes: "absent"` while the generator has not run. What moves a secret's
bytes is delivery, and the `delivery` list on the value's own entry is the whole
statement of where to.

A configuration file names its bytes and never carries them. Beside `mode` and
the `reload` list the module wrote, a computed file carries exactly one
identity:

| The implementation declared | The entry records |
| --- | --- |
| `source` | the store path itself, and no digest — the bytes are already identified by it |
| `render` of literals only | the recipe and `contentHash`, a digest over the concatenated fragments, because the plan holds every byte it hashes |
| `render` carrying any `ref` | the recipe and `structureHash`, a digest over the fragments and the reference paths, and **no digest over the assembled bytes** |

```json
"configData": {
  "/srv/borg/.ssh/authorized_keys": {
    "mode": "0600",
    "reload": ["borgRepo"],
    "computed": false,
    "row": { "id": "set-entry-absent", "subject": "vault-repo:server@vault" }
  }
}
```

**An artifact rendered over an incomplete set is recorded as not computed** —
`computed: false`, the row that made it so, and **no identity at all** — rather
than hashed over the entries that do have values. The recipe is not even read:
a file rendered over a set with an absent entry has no bytes to hash.

## Keys and re-keying

An entry's key is a function of what it read. A set-valued read therefore puts
the *membership* of that set into the reader's key, which is a
`set-read-in-key` **warning** on that entry: adding a tag to somebody else's
machine re-keys the repository's own entry.

The warning exists because two facts are easy to conflate. What re-keys an
entry is what it read; what restarts a process is where the value landed. The
authorized-keys file lands on a configuration file's identity and in no unit
and no closure, so admitting a machine reloads sshd and rebuilds nothing — and
the key still moves.

## Acyclicity

A capability's exports are a function of module and settings and **never** of a
wire. Two instances may wire each other and both resolve, with neither
appearing in the other's `dependsOn`. The worked example does exactly this, and
`tests/unit/resolution.nix` asserts it.

## The committed fixture

`fixtures/minimal-typed-edge/plan/backup.json` is the golden copy: all
eleven entries, real hashes, real store path strings, no ellipsis and no invented
hash. `tests/unit/plan.nix` compares it to the evaluated plan field by field and
reports the differing attribute paths rather than printing both documents. The
fixture carries no prose keys of its own - every field participates in the
comparison, and what the `note` and `why` keys used to hold is beside it in
`fixtures/minimal-typed-edge/plan/README.md`.

Regenerate it - never by hand - with:

```bash
nix eval --json '.#debug.worked.plan' | jq -S . > fixtures/minimal-typed-edge/plan/backup.json
```
