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

## Which layer reports a refusal

Three layers hold three kinds of fact, and each kind has exactly one layer that
can see it whole:

| Fact | Held by | Reported by |
| --- | --- | --- |
| the entry's units, closure, target, configuration data and generated files | the plan | `mkPlan`, as a row |
| the realiser and the confinement profile of an entry | the realisation statement | `operator/read.nix`, as a row |
| the bytes of an artifact | the derivation | nothing: a build either runs or does not |

A refusal about a fact the plan carries is a row from the planner. A refusal
about a fact the realisation statement carries is a row from the deployment
build, which is the only layer handed the statement. A realiser refuses only
conditions one of those two already reported as an error row, so no path through
a deployment build reaches a raise without a row having been produced first.

The realisers keep their raises, and a raise is the answer a caller that
imported `image/read.nix` or `flakelet/read.nix` and called it directly
receives. `tests/unit/diagnostics.nix` holds that rule to the source: every
`fail` of either realiser is crossed against the row producers of `lib/` and
`operator/read.nix`, and a refusal with no row above it fails the suite naming
it. The deployment build asks each realiser for the rules only it knows -
`acceptsName`, `acceptsUnit`, `acceptsHostPath`, `confinement` and `backend` of
`flakelet/read.nix`, `profileNames`, `denials`, `hostPaths` and `versionFor` of
`image/read.nix` - and one rule therefore has one home, with the row and the
raise saying the same thing.

`row`, `error` and `warning` are exported from the library, and every producer
of a row uses them: they are what applies `util.oneLine` to a message, an
evidence line and a resolution, so one row is one line whatever a deployment
interpolated into it.

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
| `interface-mismatch` | a slot's interface and the wired capability's interface are not one interface; the row prints both declaring files, so two same-named interfaces are distinguishable, and its evidence names the rule that refused the edge: both ends claim an identity and the two claims differ, or the two carry one name and are different values, or they are different values and at most one of them claims an identity |
| `interface-fold-not-a-function` | an interface declares a `fold` that is not a function; the row's subject is the declaring file and its evidence states what a fold is applied to |
| `interface-fold-unapplied` (warning) | an interface declares a `fold` and no slot of the deployment reads it with `reach = "all"`, so the policy is never applied |
| `interface-fold-name-malformed` | a named fold's `name` is not a non-empty string free of whitespace; the subject is the declaring file, the evidence states that a name is the only part of a fold two evaluations can compare, and the resolution names both spellings. The fold is not applied and a set-valued read delivers the provider-keyed set unchanged |
| `interface-id-malformed` | a declared `id` is not a non-empty string free of whitespace; the subject is the declaring file, the message names what was written, the evidence states that an identity is claimed with a string two authors can both write, and the resolution names the qualified form. The claim is disregarded and the interface is identified by its value |
| `interface-id-unnamed-fold` | an interface claims an `id` and declares a fold carrying no name; the evidence states that a fold's name is part of an identity and a bare function supplies none, and the resolution names the fold constructor or deleting the `id`. The claim is disregarded |
| `interface-id-unnamespaced` (warning) | a declared `id` carries neither `.` nor `/`; the evidence states that the namespace is shared with every other author and the resolution names a qualified form. The claim still identifies and the plan stays applicable |
| `interface-id-conflict` | two interfaces claim one `id` and their identities differ, observed from the `interfaces` map or at a wire and reported once; the row is subjected to the first of the two declaring files by sort order, names the second, and its evidence states what differs — an export one side declares alone, an export's two type names, an export's two secrecies, or two fold names. An edge between them is refused |

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
| `unit-env-value-newline` | a unit's environment value carries a line break, which a unit file has no line to put |
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
| `closure-root-outside-store` | a declared root that is not a path under the store directory the plan is read against |
| `closure-root-is-delivered` | a declared root the plan also records as a delivered reference, whose bytes reach the units from the machine rather than from a closure |
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
| `interface-fold-raised` | the interface's `fold` raised while combining the set the slot collected; the slot is then absent from `results`, and the row renders only where no implementation forces that slot |
| `interface-fold-refused` | the interface's `fold` returned `{ refused = "<why>"; }`; the fold states the message and the planner states the identifier, the consuming entry as subject and the severity. The slot is absent from `results`, so a consumer reading it under `results ? <slot>` renders the row and one reading it unconditionally ends the evaluation of the whole table with a missing attribute |
| `module-raised` | a module's own code raised a catchable error; its value is recorded as not computed and the rest of the plan is still produced |

### The plan itself

| id | Raised when |
| --- | --- |
| `set-entry-absent` | a read names an entry whose value has not been generated; the entry stays in the set with a null value and an absent marker |
| `set-read-in-key` (warning) | a set-valued read's membership is part of the reading entry's key, so that entry is re-keyed when a machine joins or leaves the set |
| `vars-not-deployed-opened` | a unit or configuration file of the owning module names the path of a `deploy = false` generator's file |
| `vars-generator-claimed-twice` | two members of one instance declare the same generator name, which is one address for two values |
| `diagnostic-subject-invalid` | a row carried a subject that is not a plan key, a deployment-relative path or an issue identifier |

### Every row the deployment build can produce

These are the rows about the realisation statement, and about the statement
crossed with the entry it is about. They come out of `operator/read.nix`, and a
caller reads them in the same table as the planner's own.

| id | Raised when |
| --- | --- |
| `operator-realiser-unknown` | the statement names a realiser that does not exist |
| `operator-image-profile-missing` | an image entry's statement carries no `profile` |
| `operator-image-profile-unknown` | the profile stated is not one the image realiser implements |
| `operator-statement-names-nothing` | a statement key is neither a plan key the plan carries nor a prefix of one |
| `operator-statement-not-a-record` | a statement an entry is read by is a bare value rather than a record |
| `operator-plan-record-unclassified` | a plan record is neither a generated value, a service entry nor a machine record |
| `operator-entry-realises-nothing` | a statement names an entry that declares no unit, so there is nothing to realise |
| `operator-entry-path-not-assembled` | the stated realiser runs no step that could assemble a host path the entry is shown |
| `operator-entry-service-manager-mismatch` | the entry's machine runs one service manager and the stated realiser emits for another |
| `operator-entry-name-refused` | the endpoint of the stated realiser refuses the service name or a unit file name the entry derives |
| `operator-entry-access-denied` | a unit needs an access the confinement profile the statement produced denies |
| `operator-entry-name-collision` | two plan keys project onto one artifact name |
| `operator-entry-machine-no-address` (warning) | the machine record of a placed entry declares no address; an address is read by the step that dials and by no step that builds |

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
