# Diagnostics

A plan and a table of problems come out together, always both. No check aborts
the pass, so forty instances with two mistakes render as forty instances with
two marks rather than as one error message.

## The row

```nix
{
  id = "slot-reads-undeployed-value";     # stable identifier for the kind
  subject = "nightly:client@alpha";       # a plan key, a deployment-relative path, or an issue id
  severity = "error";                     # "error" or "warning", and nothing else
  message = "…";                          # one line
  evidence = "…";                         # what the planner saw
  resolution = "…";                       # what the author is expected to do
}
```

- **Rows are values callers return alongside their result.** Nothing
  accumulates them, and no ambient list exists for them to land in.
- **The table is deterministic**: ordered by id, then subject, then message, and
  deduplicated — the same fact produced twice is one row. Two evaluations of one
  input give byte-identical output.
- **`applicable` is `false` when any row is an error.** A warning alone leaves
  the plan applicable.
- **A module cannot set a severity.** Declaring `severity` is read, discarded,
  and answered with a `module-declared-severity` warning.
- **A subject is checked.** An absolute path would make a rendered table differ
  between checkouts, so it is reduced to its last component and the reduction is
  itself a row (`diagnostic-subject-invalid`) naming the row that carried it.

## Rendering

`planner.render <table>` is a function of the table alone — it does not read the
deployment again — and produces the format the example folders commit:

```
  ! vault-repo:server@vault  clients names three entries and `nightly:client@gamma` has no bytes
      severity: error
      evidence: the slot declares reach `all` over `nightly.identity`, and `publicKey` of that
                entry is declared and not generated
      resolution: generate the missing value for that placement and replan; a set-valued read
                names its entries, so the set cannot be shortened by dropping it
```

`planner.mkTable <rows>` builds a table from raw rows (ordering, subject
discipline and deduplication applied).

## Every row the planner can produce

### Interfaces and atoms

| id | Raised when |
| --- | --- |
| `export-atom-missing-type` | an export atom declares no `type` |
| `export-atom-secrecy-domain` | `secrecy` is neither `"public"` nor `"secret"` |
| `export-atom-excluded-key` | an atom declares `locality` or `lifecycle`; the evidence is the condition that would bring the field back |
| `export-atom-unknown-key` | any other atom key — a misspelling is a row, not a silence |
| `interface-mismatch` | a slot's interface and the wired capability's interface are different values; the row prints both declaring files, so two same-named interfaces are distinguishable |
| `interface-fold-not-a-function` | an interface declares a `fold` that is not a function; the row's subject is the declaring file and its evidence states what a fold is applied to |
| `interface-fold-unapplied` (warning) | an interface declares a `fold` and no slot of the deployment reads it with `reach = "all"`, so the policy is never applied |

### Leaf modules

| id | Raised when |
| --- | --- |
| `declaration-unknown-key` | a key this subset does not read; the row lists the ones it does |
| `declaration-excluded-key` | a key this subset deliberately excludes; the evidence is its trigger |
| `module-declared-severity` (warning) | a module tried to set a row's severity |
| `impl-missing` | the module declares no `impl` |
| `platforms-malformed` | `platforms` is not a list of strings |
| `slot-interface-missing` / `capability-interface-missing` | a slot or capability declares no interface value |
| `slot-reach-domain` | `reach` is outside `one` / `all` |
| `slot-reach-local` | `reach = "local"`, which derives from a locality this subset does not declare |
| `slot-reads-unknown-export` | a `reads` entry the interface does not declare; the evidence lists what it does |
| `vars-file-secrecy-domain` | a generated file's `secrecy` is outside the two values |
| `vars-per-domain` | a generator's `per` is neither `instance` nor `placement` |
| `vars-deploy-malformed` | `deploy` is not a boolean |
| `vars-reads-malformed` | `reads` is not a list of strings |
| `vars-reads-unknown-generator` | `reads` names a generator the module does not declare; the evidence lists what it does |
| `vars-reads-arity` | a `per = "instance"` generator reads a `per = "placement"` sibling, so the read has no single answer |
| `vars-reads-cycle` | a generator transitively reads itself; the recorded reads of every generator in the cycle are dropped |
| `port-claim-not-fixed` | a port claim with no `fixed`; this subset allocates nothing |

### Machines and targets

| id | Raised when |
| --- | --- |
| `machine-target-incomplete` | a machine declares no `system` or no `serviceManager`, so a placement on it has no derivable target |
| `placement-platform-mismatch` | the machine's `system` is outside the module's `platforms` |

### Composition and placement

| id | Raised when |
| --- | --- |
| `settings-not-member-keyed` | the deployment defines a knob outside any member's namespace |
| `settings-undeclared-knob` | the member declares it neither as a default nor as fixed |
| `settings-fixed-path` | the deployment writes a path the module declared `fixed`; the row names both files and neither value silently wins |
| `placement-unknown-member` | `placement.every.<m>` names a member the root does not own |
| `placement-unknown-machine` | a placement names a machine the registry does not hold |
| `member-not-placed` | a member matched no machine and no tag, so nothing it declares runs anywhere |
| `exposes-unknown-capability` | `exposes` names a capability the root does not provide |
| `slot-set-settings-derived` (warning) | the set of slots a member asks for differs between its resolved settings and its own values, so the module is publishing a cut; the evidence is the condition that would make member cuts a construct of their own |

### Units, extensions and configuration files

| id | Raised when |
| --- | --- |
| `implementation-malformed` | an `impl` returned something other than an attribute set |
| `implementation-unknown-key` | a key outside the unit vocabulary, the implementation's own keys or an `extends` entry's keys — a service manager's raw stanza is this row, and for an implementation's own keys the resolution names the interface fold as where a refusal belongs |
| `unit-field-type-mismatch` | a unit field's value fails its type; the failing value is not recorded |
| `unit-reference-unknown` | `after` or `requires` names a unit the module did not declare |
| `unit-extends-malformed` | `extends` is not a list |
| `unit-extension-missing` | an `extends` entry's `extension` is not a `planner.unitExtension` value |
| `unit-extension-missing-type` / `unit-extension-unknown-key` / `unit-extension-excluded-key` | an extension's field declares no `type`, a key outside `{ type }`, or an excluded construct |
| `unit-extension-unknown-field` | `values` assigns a key the extension does not declare |
| `unit-extension-type-mismatch` | an assigned value fails its field's type |
| `unit-extension-backend-mismatch` | the extension's `backend` is not the target machine's `serviceManager`; the fields are still recorded under that backend |
| `config-file-mode-missing` | a configuration file declares no `mode` |
| `config-file-reload-malformed` | `reload` is not a list of this module's unit names |
| `config-file-render-item` | a `render` item is neither one public literal nor one reference |
| `config-file-disposition` | a file declares both `source` and `render`, or neither |

### Closures and pins

| id | Raised when |
| --- | --- |
| `closure-malformed` | `closure` is not a list of strings |
| `closure-path-undeclared` | the entry mentions a store path no declared root covers; the row names where it was mentioned |
| `closure-root-unmentioned` (warning) | a declared root nothing in the entry mentions |
| `pin-underspecified` | a `pin` names no revision or no content hash |
| `pin-malformed` | a `pin` is not the shape the lock key carries |

### Wiring and resolution

| id | Raised when |
| --- | --- |
| `slot-unwired` | no deployment wires the slot; it resolves to no value at all |
| `wire-unknown-instance` | the wire names an instance the deployment does not declare |
| `wire-unknown-capability` | the instance exposes no such capability |
| `wire-capability-not-exposed` | the root provides it and the instance does not expose it; the row lists what is exposed |
| `reach-one-placement-count` | `reach = "one"` against a capability with no placement or more than one; the row names the slot and the placements |
| `reach-all-no-placement` | `reach = "all"` against a capability placed nowhere |
| `provider-export-missing` / `provider-export-extra` | the published keyset is not the interface's keyset |
| `export-type-mismatch` | a published value fails its atom's type |
| `export-secret-not-a-reference` | an export declared `secret` publishes something other than a generated file, so its bytes would be in the plan rather than its path |
| `slot-reads-undeployed-value` | a `reads` entry names a secret export backed by a `deploy = false` generator, so the path it names resolves to nothing at run time |
| `interface-fold-raised` | the interface's `fold` raised while combining the set the slot collected; the slot is then absent from `results` |
| `interface-fold-refused` | the interface's `fold` returned `{ refused = "<why>"; }`; the fold states the message and the planner states the identifier, the consuming entry as subject and the severity |
| `module-raised` | a module's own code raised a catchable error; its value is recorded as not computed and the rest of the plan is still produced |

### The plan itself

| id | Raised when |
| --- | --- |
| `set-entry-absent` | a read names an entry whose value has not been generated; the entry stays in the set with a null value and an absent marker |
| `set-read-in-key` (warning) | a set-valued read's membership is part of the reading entry's key, so that entry is re-keyed when a machine joins or leaves the set |
| `vars-not-deployed-opened` | a unit or configuration file of the owning module names the path of a `deploy = false` generator's file |
| `vars-generator-claimed-twice` | two members of one instance declare the same generator name, which is one address for two values |
| `diagnostic-subject-invalid` | a row carried a subject that is not a plan key, a deployment-relative path or an issue identifier |

## Refusals by subtraction

Seven constructs are deliberately absent. Writing one is **not** an unknown-key
misspelling row: it is `declaration-excluded-key` or `export-atom-excluded-key`
whose evidence is *the condition that would bring the construct back*.

```
locality        the first export whose value is a unix socket path or a loopback port
lifecycle       the first value that is not knowable at evaluation
pick, strategy  the first service whose machine the operator lets the planner choose
enable, member wiring   a module publishing a composition whose cuts an operator wants
externals       a non-fleet resource this deployment has to name
collects, contributes, answers, probes   clanServices/pki, and nothing smaller
register, frontier, orchestrator         not this change
```

`planner.excluded` is that table as data (`rows`, and `constructs.<key> = {
row, trigger }`), and `tests/unit/exclusions.nix` writes one deployment per
construct to prove none of them is silently accepted.

## What is not caught

Evaluation is total for everything the interpreter lets a library catch. Two
things it does not:

- **`abort`** — no `tryEval` catches it.
- **A missing attribute** — including a module dereferencing a slot that did not
  deliver (see [authoring.md](authoring.md#when-a-read-is-refused)).

Both are documented as propagating rather than claimed to be contained. Inside
library source they are bugs, and `tests/unit/diagnostics.nix` greps this tree
to keep `throw`, `abort`, `assert` and korora's raising `check` out of it.
