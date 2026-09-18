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
| the external generator's contract: its name grammar, its one program per value, the address a step dials | the contract | `secrets/read.nix`, as a row |
| the bytes of an artifact | the derivation | nothing: a build either runs or does not |

A refusal about a fact the plan carries is a row from the planner. A refusal
about a fact the realisation statement carries is a row from the deployment
build, which is the only layer handed the statement. A realiser refuses only
conditions one of those two already reported as an error row, so no path through
a deployment build reaches a raise without a row having been produced first.

A fact a machine holds at run time is in none of those three columns, so it is in no table here. A
user-scope machine whose roots are not writable, whose account has no lingering or whose portabled
does not answer is refused by the command itself, naming the machine, the requirement and what the
machine answered, because nothing the plan records could have said it:
[operator.md](operator.md) states that question and what provisioning it verifies.

The realisers keep their raises, and a raise is the answer a caller that imported `image/read.nix`,
`flakelet/read.nix` or `secrets/read.nix` and called it directly receives. Every refusal of every
realiser carries the identifier of the row that reports the same condition, or a recorded reason
why no deployment reaches it, and `tests/unit/diagnostics.nix` crosses that data against the rows
`lib/`, `operator/read.nix` and the secrets reading produce: a refusal with no row above it fails
the suite naming it. Which files are examined is read off the realiser sources the suite is handed
rather than written out, so a realiser is accounted for by existing, and the pairing is the account
rather than a fragment of a message, so rewording a refusal changes nothing.

A reading asks each realiser for the rules only it knows - `acceptsName`, `acceptsUnit`,
`acceptsHostPath`, `confinement`, `backend` and `scopes` of `flakelet/read.nix`, `acceptsName`,
`acceptsUnit`, `profileNames`, `denials`, `hostPaths`, `versionFor` and `scopes` of
`image/read.nix`, `unrenderable` and `fail` of `secrets/read.nix` - and one rule therefore has one
home, with the row and the raise saying the same thing. `scopes` is the list of deployment scopes
the realiser realises, which is what `operator-entry-scope-unsupported` is read from.

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

A row reaches a program with all six fields. The build writes them into
`diagnostics.json` beside the rendered `diagnostics.txt`, and the command's one
decode of that file keeps every one of them, so a tool holds the evidence and
the resolution rather than the two of the four a rendered line carries: what was
observed and which declaration to edit are the fields an author acts on. That
decode is the only reader of the file - every consumer of a build's rows goes
through it, the fallback the reading composes where a build wrote no table
included - because two decodes of one file diverge and the one every command
already imports would stay the lossy one.

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
| `interface-fold-refusal-malformed` | an interface's fold refused a set-valued read with `planner.refuse` of something other than a sentence: a value of another kind, or an empty string. The row names the fold, the slot and the consuming entry, and states that a refusal travels to the table as the row's whole message. The slot is left absent |

### Leaf modules

| id | Raised when |
| --- | --- |
| `declaration-unknown-key` | a key this subset does not read; the row lists the ones it does |
| `declaration-malformed` | a value the reading indexes into is not a record: the declaration itself, a port claim, a slot, a capability, a generator, a generated file's record, a pin or its `locked` half. The row names the module file and the site inside it, and the malformed value declares nothing rather than being defaulted into existence |
| `declaration-excluded-key` | a key this subset deliberately excludes; the evidence is its trigger |
| `module-declared-severity` (warning) | a module tried to set a row's severity |
| `impl-missing` | the module declares no `impl` |
| `platforms-malformed` | `platforms` is not a list of strings |
| `slot-interface-missing` | a slot declares no interface value |
| `capability-interface-missing` | a capability declares no interface value; a capability publishes exactly the keyset of the interface it declares, so there is nothing to check without one |
| `slot-reach-domain` | `reach` is outside `one` / `all` |
| `slot-reach-local` | `reach = "local"`, which derives from a locality this subset does not declare |
| `slot-reads-unknown-export` | a `reads` entry the interface does not declare; the evidence lists what it does |
| `vars-file-secrecy-domain` | a generated file's `secrecy` is outside the two values |
| `vars-file-ownership-malformed` | a generated file's `owner`, `group` or `mode` fails its type; the failing value is not recorded and the default is delivered |
| `vars-per-domain` | a generator's `per` is neither `instance` nor `placement` |
| `vars-deploy-malformed` | `deploy` is not a boolean |
| `vars-reads-malformed` | `reads` is not a list of strings |
| `vars-reads-unknown-generator` | `reads` names a generator the module does not declare; the evidence lists what it does |
| `vars-reads-arity` | a `per = "instance"` generator reads a `per = "placement"` sibling, so the read has no single answer |
| `vars-reads-cycle` | a generator transitively reads itself; the recorded reads of every generator in the cycle are dropped |
| `capability-consumers-malformed` | a capability's `consumers` is neither `one` nor `many`; the value is not recorded and the capability is taken by any number of slots |
| `port-claim-not-fixed` | a port claim with no `fixed`; this subset allocates nothing |
| `port-claim-not-a-port` | a port claim's `fixed` is not an integer of 1 to 65535. The claim is recorded nowhere, so nothing compares it, and a number written as text is not read as the number it spells |
| `port-claim-protocol-unknown` | a port claim's `proto` is outside `tcp` / `udp`; the row names the domain, the number is still recorded and the claim is compared as though it stated no protocol |
| `port-claim-address-malformed` | a port claim's `address` is not one address, a wildcard spelling included. The absence of the key is already every address of the machine, the number is still recorded and the claim is compared as though it stated no address |
| `vars-program-malformed` | a generator's `program` is not exactly one store path. Omitting the key is no row at all: a program is recorded as a literal string, neither run nor read here |
| `name-carries-key-separator` | a machine, an instance, a member or a generator is named with `/`, `@` or `:`. A plan key is `<instance>:<member>@<machine>` and a generated value's is `<instance>:vars/<generator>@<machine>`, so such a name produces a key that takes apart into parts nothing declared. The named thing is left out of every key the plan builds |

### Machines and targets

| id | Raised when |
| --- | --- |
| `machine-target-incomplete` | a machine a placement selects declares no `address`, no `system` or no `serviceManager`, so a placement on it has no derivable target and is not planned |
| `machine-scope-unknown` | a machine declares a `scope` outside `system` and `user`; a refused value is as incomplete as none, so the machine has no derivable target and every placement on it is dropped rather than planned |
| `machine-seal-recipient-malformed` | a machine declares a `sealRecipient` outside the grammar one age native recipient carries, which is `age1` and 58 characters of the bech32 alphabet as one word. The row names the machine and the registry file, and the refused line is left out of every projection. The recipient is in no target, so refusing it drops no placement: every entry on the machine is still planned, and the machine has no recipient a delivery can seal to |
| `placement-platform-mismatch` | the machine's `system` is outside the module's `platforms` |
| `unit-account-in-user-scope` | a unit declares `user` and the machine its placement selected declares `scope = "user"`, so the account is a fact the scope cannot honor: a user service manager runs every unit as the account that owns it and can switch to no other. A refusal and not a filter, as `placement-platform-mismatch` is, so the entry stays in the plan |
| `unit-groups-in-user-scope` | a unit's extension application records `supplementaryGroups`, under any backend, on a machine whose scope is `user`; a group is granted by a system service manager and an account cannot grant one to itself |
| `port-privileged-in-user-scope` | a fixed port claim below 1024 on a machine whose scope is `user`; binding one needs a capability the account does not hold. The claim is read after normalisation, so this row and the allocation index name one number |

### Composition and placement

| id | Raised when |
| --- | --- |
| `settings-not-member-keyed` | the deployment defines a knob outside any member's namespace |
| `settings-undeclared-knob` | the member declares it neither as a default nor as fixed |
| `settings-fixed-path` | the deployment writes a path the module declared `fixed`; the row names both files and neither value silently wins |
| `settings-knob-unkeyable` | a knob resolves to a value carrying a function, and the resolved settings are serialised into the entry's key; the row names the module file that declares the knob and the deployment file that sets it, and the value is recorded in no entry and in no key |
| `placement-unknown-member` | `placement.every.<m>` names a member the root does not own |
| `placement-unknown-machine` | a placement names a machine the registry does not hold |
| `member-not-placed` | a member matched no machine and no tag, so nothing it declares runs anywhere |
| `exposes-unknown-capability` | `exposes` names a capability the root does not provide |
| `slot-set-settings-derived` (warning) | the set of slots a member asks for differs between its resolved settings and its own values, so the module is publishing a cut; the evidence names the deployment's own cut, `members.<name>.enable = false`, which removes the whole member |
| `members-unknown-member` | `members.<name>` names a member the instance's root does not own; the evidence lists the ones it does |
| `member-and-slot-name-collide` | a root owns a member and a slot of the same name, so one `wire.<name>` key would address a member's own slots and a slot of every member at once |
| `cut-member-named` | the deployment places, configures or wires a member the same deployment cuts with `members.<name>.enable = false`; a cut member takes no placement, needs no settings and fills no slot |
| `binding-malformed` | a root binds a member's slot to something other than a capability off a sibling's handle, which carries the member it came from. A hand-written record naming a member and a capability and carrying no interface is not one of those handles, so it earns this row too and the slot is the deployment's to fill |
| `binding-unknown-slot` | a root binds a slot the member does not declare; the evidence lists the ones it does |
| `member-name-disagrees` | a root declares a member under one attribute key and the member names itself another. The key is the identity, since placement, the settings namespace and every plan key are read from it, and the second spelling is a member nothing else can address |

### Units, extensions and configuration files

| id | Raised when |
| --- | --- |
| `implementation-malformed` | an `impl` returned something other than an attribute set |
| `implementation-formals-closed` | an `impl` names its arguments closed, so the pattern refuses a name the planner hands it or requires one the planner does not, and the interpreter lets a caller catch neither refusal. The implementation is not applied, the entry is planned and records no unit, and the resolution names the `...` an implementation's contract asks for |
| `implementation-unknown-key` | a key outside the unit vocabulary, the implementation's own keys or an `extends` entry's keys — a service manager's raw stanza is this row, and for an implementation's own keys the resolution names the interface fold as where a refusal belongs |
| `unit-field-type-mismatch` | a unit field's value fails its type; the failing value is not recorded |
| `unit-reference-unknown` | `after` or `requires` names a unit the module did not declare |
| `unit-extends-malformed` | `extends` is not a list |
| `unit-extension-missing` | an `extends` entry's `extension` is not a `planner.unitExtension` value |
| `unit-extension-missing-type` | an extension's field declares no `type` |
| `unit-extension-unknown-key` | an extension's field declares a key outside `{ type }` |
| `unit-extension-excluded-key` | an extension's field declares an excluded construct; the evidence is its trigger |
| `unit-extension-unknown-field` | `values` assigns a key the extension does not declare |
| `unit-extension-type-mismatch` | an assigned value fails its field's type |
| `unit-extension-backend-mismatch` | the extension's `backend` is not the target machine's `serviceManager`; the fields are still recorded under that backend |
| `unit-value-newline` | a value a unit record carries at any depth holds a line break, which a unit file has no line to put; the row names the field path |
| `unit-env-name-malformed` | a unit declares an environment name outside the grammar a service manager carries. An assignment is written `NAME=value` with no escape of its own, so a name outside it is a directive the manager refuses in part; neither the name nor its value is recorded |
| `unit-restart-delay-without-policy` | a unit declares `restartSec` and no `restart`, so the delay changes nothing; the delay is not recorded |
| `unit-restart-contradicts-one-shot` | a `oneShot` unit declares `restart = "always"`, which restarts it for as long as it keeps succeeding; the policy is not recorded |
| `unit-restart-on-scheduled` | a unit declares a `schedule` and a restart policy other than `no`, which is a second schedule nobody declared; the policy is not recorded |
| `unit-probe-without-timeout` | a unit declares a `probe` and no `probeTimeout`, so the only bound on the probe would be a service manager's default, which is a fact the plan does not record; neither field is recorded |
| `unit-probe-timeout-without-probe` | a unit declares a `probeTimeout` and no `probe`, so the bound bounds nothing; the bound is not recorded |
| `unit-probe-timeout-unbounded` | a unit declares a `probeTimeout` spelling zero, which a service manager reads as no bound at all, so the value that looks like the tightest bound is the absence of the one the field exists for; neither field is recorded. The check covers every spelling of zero the duration type admits, not the literal `0` |
| `unit-probe-on-one-shot` | a `oneShot` unit declares a `probe`, and a job that applies and exits reports whether it worked in its own exit status, so a probe ordered after it answers a question already answered; neither field is recorded |
| `unit-probe-on-scheduled` | a unit declares a `schedule` and a `probe`, and a scheduled unit is not running between elapses, so the probe would report the schedule rather than the service; neither field is recorded |
| `unit-probe-declared-twice` | two units of one entry declare a `probe`. An entry is activated and rolled back as one, so whether it is serving is one question with one answer, and a realiser derives one file for it; the row names both units and neither statement is recorded |
| `unit-directory-mode-without-directory` | a unit declares a directory mode for a kind it declares no directory of, and a mode alone creates nothing; the mode is not recorded |
| `unit-directory-declared-twice` | a unit declares one directory kind in the vocabulary and again in a backend extension application, and a renderer handed two statements about one directory has no way to choose; neither is recorded |
| `unit-condition-contradicts-itself` | a unit states one path as both `startIfPathPresent` and `startIfPathAbsent`, so it is skipped whether the path is there or not; neither condition is recorded |
| `config-file-mode-missing` | a configuration file declares no `mode` |
| `config-file-reload-malformed` | `reload` is not a list of this module's unit names |
| `config-file-render-item` | a `render` item is neither one public literal nor one reference |
| `config-file-disposition` | a file declares both `source` and `render`, or neither |
| `config-file-ownership-malformed` | a configuration file's `owner` or `group` fails its type; the failing value is not recorded and the default is installed |
| `config-file-path-refused` | a configuration file's host path carries a character outside the grammar a rendered step can carry as one shell word; the file is not recorded |
| `config-file-source-refused` | a configuration file's `source` is a value of another kind, or a path outside the store directory the plan is read against. The library records one literal store path and resolves nothing, the way it records a generator's `program`, so the file is not recorded |

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
| `wire-names-bound-slot` | the deployment wires a slot the instance's own root binds to a member it keeps, so the two statements disagree about what the composition is; the binding resolves the slot |
| `capability-consumers-exceeded` | a capability declaring `consumers = "one"` is wired by more than one slot; the count is over wires, so one consumer placed on twelve machines is one consumer. The cardinality is read by the member's own capability name, so exposing the capability under another name, or under two names, changes which name a wire may address and never how many wires may take it |
| `wire-unknown-instance` | the wire names an instance the deployment does not declare |
| `wire-unknown-capability` | the instance exposes no such capability |
| `wire-capability-not-exposed` | the root provides it and the instance does not expose it; the row lists what is exposed |
| `wire-capability-untyped` | the far end of a wire or a binding declares no interface value, so neither comparison an edge makes can be made; the row names the consuming entry, the slot and the capability, the slot is left absent from the consumer's results, and the module that declared the capability earns `capability-interface-missing` for the same absence |
| `reach-one-placement-count` | `reach = "one"` against a capability with no placement or more than one; the row names the slot and the placements |
| `reach-all-no-placement` | `reach = "all"` against a capability placed nowhere |
| `provider-export-missing` | the published keyset lacks an export the interface declares |
| `provider-export-extra` | the entry publishes an export the interface does not declare; the extra export is delivered to nobody |
| `export-type-mismatch` | a published value fails its atom's type |
| `export-secret-not-a-reference` | an export declared `secret` publishes something other than a generated file, so its bytes would be in the plan rather than its path |
| `export-secret-backed-by-public-file` | an export an interface declares secret is published from a generated file that declares no secrecy of its own, so bytes a plan carries in the open would travel under the name of a value an interface calls secret. The plan carries the value at the stricter of the two declarations and the export publishes nothing |
| `slot-reads-undeployed-value` | a `reads` entry names a secret export backed by a `deploy = false` generator, so the path it names resolves to nothing at run time |
| `slot-read-type-mismatch` | a read is delivered a value the type the consuming interface declares for it refuses; the row names the read, the far end and korora's own report. A claimed identity is name-deep, so this is where the shape of a value that crossed the wire is compared |
| `slot-reads-value-unreadable-by-user` | a unit runs as an account the recorded ownership and mode of a file backing one of the entry's reads do not admit, so the unit starts and fails with `EACCES` |
| `entry-config-file-unreadable-by-user` | a unit runs as an account the record of a configuration file its own entry shows it does not admit, so the unit starts and fails with `EACCES`. The same comparison as the row above, over the entry's own declaration rather than another entry's delivered value |
| `entry-value-unreadable-by-user` | a unit names the path of a file of its own entry's generator, and runs as an account the recorded ownership and mode of that file do not admit, so the unit starts and fails with `EACCES`. The same comparison as the two rows above, over a value the entry produces itself rather than one another entry publishes |
| `interface-fold-raised` | the interface's `fold` raised while combining the set the slot collected; the slot is then absent from `results`, and the row renders only where no implementation forces that slot |
| `interface-fold-refused` | the interface's `fold` returned `planner.refuse "<why>"`; the fold states the message and the planner states the identifier, the consuming entry as subject and the severity. The slot is absent from `results`, so a consumer reading it under `results ? <slot>` renders the row and one reading it unconditionally ends the evaluation of the whole table with a missing attribute |
| `module-raised` | a module's own code raised a catchable error; its value is recorded as not computed and the rest of the plan is still produced |

### The plan itself

| id | Raised when |
| --- | --- |
| `set-entry-absent` | a read names an entry whose value has not been generated; the entry stays in the set with a null value and an absent marker |
| `set-read-in-key` (warning) | a set-valued read's membership is part of the reading entry's key, so that entry is re-keyed when a machine joins or leaves the set |
| `vars-not-deployed-opened` | a unit or configuration file of the owning module names the path of a `deploy = false` generator's file |
| `vars-path-off-delivery-set` | a unit or a configuration file of a placed entry names the path of a generated value the entry's own machine does not receive. A delivery set is what the owner's placements and the declared reads make it, so the mention resolves to nothing rather than widening it, and the row names the machines that do receive the value. `vars-not-deployed-opened` is the same rule where that set is empty |
| `vars-generator-claimed-twice` | two members of one instance declare the same generator name, which is one address for two values |
| `value-ownership-in-user-scope` | a generated file record states an `owner` or a `group` and the value's delivery set names a machine whose scope is `user`, which the delivery cannot chown; the subject is the value entry and the row names the machine and the field. A stated `mode` is honoured, an account being able to chmod what it owns |
| `machine-receives-a-value-unsealed` (warning) | a generated value's delivery set names a machine whose registry record states no `sealRecipient`, so that machine receives the bytes under `/run` and no copy it can open after a reboot. The subject is the machine and the row names the values delivered there, one row per machine however many values reach it. A warning and not an error: the delivery works and the deployment is realisable, and what the machine lacks is a recovery no deployment had before the field existed |
| `diagnostic-subject-invalid` | a row carried a subject that is not a plan key, a deployment-relative path or an issue identifier |
| `diagnostic-severity-invalid` | a row was built with a severity outside `error` and `warning`. The row that carried it is replaced by this one, so nothing in the table carries a severity no producer may state, and the resolution names `error` and `warning` as the two constructors a producer has |
| `declaration-field-missing` | a field of the deployment's own half - a machine, an instance, a member's placement or a wire - is absent where the reading needs one. A key the reading cannot default is reported rather than read as an empty value |
| `declaration-field-malformed` | the same field carries a value of the wrong kind. The deployment's half is read with the tolerance the module's half is read with, so the rest of the deployment is still read |
| `plan-key-claimed-twice` | two records of different families claim one plan key: a machine record and a service entry, or a generated value and an entry. A reader takes a key apart to recover what a record is, so the first claimant in sort order is the record the key names and every other one is in no plan |
| `planner-argument-malformed` | an argument of `mkPlan` carries a value of another kind than the reading below it indexes, coerces or hashes: `machines`, `instances`, `interfaces`, `varsState`, `sources` or one of its four fields, or `storeDir`. The argument is read as unstated, the rest of the deployment is still planned, and the subject is the file the caller writes its deployment in |

### What two claimants of one machine both claim

A claimant is a placed entry or the machine's own record, which claims the
resources the registry's `reserves` states its host image already holds. A claim
is read off what the plan already records, and a row is per machine, so one
member placed on two machines claims its resources on each of them and collides
with nothing. Two units of one entry recording one directory is one claim too:
the claimant is the entry. Each row names every claimant, the machine and the
resource, is reported once for one collision with the first of the colliding
plan keys as its subject, and resolves to deriving the resource from `instance`
and `member`, the pair the entry's own key is built from. A port resolves to
that or to stating the `address` each listener binds, two addresses of one
machine being two listeners. A machine's key enters the same sort the entry keys
enter, so it is the subject exactly when it sorts first and a named claimant
either way, and the resolution of a row it is a claimant of names the registry's
reservation beside the entry's claim. A reservation earns no row on its own: a
reserved resource no entry claims, and a reservation on a machine no placement
selects, both leave the table as it was.

| id | Raised when |
| --- | --- |
| `entry-host-path-claimed-twice` | two entries placed on one machine declare a configuration file at one host path, so the entry applied last is the one whose rendering survives. A machine reserving that path is the second claimant where one entry declares the file |
| `entry-port-claimed-twice` | two entries placed on one machine claim one number whose protocols and whose addresses both overlap, so every entry after the first cannot bind. Two protocols overlap when they are the same or either claim states none, an unstated protocol claiming the number on every protocol of the domain; two addresses overlap when they are the same or either claim states none, an unstated address being every address of the machine. Two claims of one number binding two different addresses are two listeners that run, and are no row. Overlap is not equality, so one claim can take part in more than one collision and each row names its own claimants, protocol, and address. A machine reserving a number whose protocol and address overlap is the second claimant where one entry claims it |
| `entry-unit-directory-shared` (warning) | two entries placed on one machine record one unit directory name under `runtimeDirectory`, `stateDirectory` or `cacheDirectory`. A warning rather than an error: the service manager deletes a runtime directory when its unit restarts, and a shared state directory is a handoff a deployment may intend. This one has no reservation half, a unit directory name being in the service manager's own namespace rather than a host path the registry can state |
| `entry-host-path-nested` | two claimants of one machine show one host path inside another, so one of them asks for a file where the other asks for the directory holding it. A realiser carries a file at every host path it is shown, and the builder that meets the pair names a store path and no declaration |

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
| `operator-entry-path-not-assembled` | the stated realiser runs no step that could assemble a host path the entry is shown, and the path's bytes do not exist before the entry is activated |
| `operator-entry-path-not-installable` | the stated realiser binds a store object rather than installing a file on the machine, and a configuration file the entry is shown states a record a store object does not carry. The resolution names both ways out: state the store's record, or state the realiser that installs |
| `operator-entry-extension-field-unrendered` | a unit records an extension field the stated realiser's own directive table has no rendering for |
| `operator-entry-service-manager-mismatch` | the entry's machine runs one service manager and the stated realiser emits for another |
| `operator-entry-scope-unsupported` | the entry's machine declares a scope the `scopes` list the stated realiser publishes does not carry, so the realiser emits for a privilege that machine does not offer. flakelet realises the system scope alone, its core writing `/run/systemd/system` and `/var/lib/flakelet`, and the realiser's own refusal carries this identifier |
| `operator-entry-name-refused` | the endpoint of the stated realiser refuses the service name or a unit file name the entry derives |
| `operator-entry-access-denied` | a unit needs an access the confinement profile the statement produced denies |
| `operator-entry-value-unaccounted` | a declared read of an entry names a generated value's path and no value record of the plan accounts for bytes delivered to that entry's machine at it. A value's delivery set is derived from the reads that name it, so this is a plan whose records disagree with each other, and the realiser's own refusal carries this identifier. An undeployed value is not this row: it is shown at no path, and `slot-reads-undeployed-value` is what the planner produced for declaring a read of one |
| `operator-entry-name-collision` | two plan keys project onto one artifact name |
| `operator-plan-field-missing` | a plan record carries no field the reading of it indexes. The plan prunes a field whose value was empty, and this names the record and the field rather than ending the evaluation |
| `operator-plan-key-unreadable` | a plan record is a placed entry whose key does not split into an instance, a member and a machine, so no artifact of it can be named and no realiser chosen for it. A name the key grammar refuses is recorded rather than dropped, so every placed entry of the plan is read or is the subject of a row |
| `operator-plan-field-malformed` | a plan record carries a configuration file's `owner`, `group` or `mode` as a value of another kind, and every comparison this reading makes against the record interpolates the three. The planner's own row about that file is what the resolution names, and neither comparison is made |
| `operator-entry-unit-file-collision` | two entries placed on one machine derive one unit file name. A realiser derives that name from the instance, the member and the unit name, so the second entry's file replaces the first on the machine and one entry runs the other's unit |
| `operator-entry-probe-unit-file-taken` | one entry declares a unit whose file is the one its own probe derives, so the entry claims one unit file name twice and the file that decides the activation is a unit's own. The row names the entry, the declared unit and the file, and renaming either the unit or the service removes it |
| `operator-coordination-names-nothing` | the coordination statement names, as the entry that runs a mesh's membership authority or as the generated value that is its join credential, a key the plan carries no record of that kind for. The statement is read by plan key the way the realisation statement is, so a field naming no record is a decision about nothing |
| `operator-coordination-object-unheld` | the coordination statement names a program or a configuration object that is not one store path of the stated entry's closure. A verb runs the program out of the entry's own closure, so an object the entry does not carry is one the copy never put on the machine |

### Every row the secrets reading can produce

These are the facts the external generator's contract holds and no layer above
the reading knows. They come out of `secrets/read.nix` when a plan is read as a
generator configuration, and `operator.mkGeneration` renders them in one table
with the planner's own. A caller that never reads a plan that way produces none
of them.

| id | Raised when |
| --- | --- |
| `secrets-value-no-program` | a generated value's entry records no `program`, and the contract runs one program per stored value |
| `secrets-value-field-missing` | a field the contract needs to store or to deliver the value is one the plan does not record |
| `secrets-key-not-a-value` | a key read as a generated value's is not of the form `<instance>:vars/<generator>` |
| `secrets-name-carries-separator` | an instance, generator or machine name carries the character the projection joins on |
| `secrets-name-outside-grammar` | one of those names carries a character the contract's `safe-name` does not admit |
| `secrets-file-name-outside-grammar` | a generated file's name carries a character the contract does not admit |
| `secrets-file-name-reserved` | a generated file carries `.nixos-secrets-metadata`, the name the tool keeps for its own provenance record |
| `secrets-name-collision` | two plan keys project onto one stored name, and one would overwrite the other's bytes |
| `secrets-delivery-machine-unknown` | a value is delivered to a machine the plan carries no record for |
| `secrets-delivery-machine-no-address` | a recipient machine's record declares no address; an error here, where a step is rendered, and no row of a deployment build, where none is |
| `secrets-rendered-word-refused` | an address or a path the rendered deploy step cannot carry as one shell word |

## Refusals by subtraction

Some constructs are deliberately absent, one line per trigger. Writing one is
**not** an unknown-key misspelling row: it is `declaration-excluded-key` or
`export-atom-excluded-key` whose evidence is *the condition that would bring the
construct back*.

```
locality        the first export whose value is a unix socket path or a loopback port
lifecycle       the first value that is not knowable at evaluation
pick, strategy  the first service whose machine the operator lets the planner choose
dynamicPort     a persisted allocation table, so a port chosen without a claim does not move
externals       a non-fleet resource this deployment has to name
collects, contributes, answers            clanServices/pki, and nothing smaller
probes, register, frontier, orchestrator  not this change
```

`planner.excluded` is that table as data (`rows`, and `constructs.<key> = {
row, trigger }`), and `tests/unit/exclusions.nix` writes one deployment per
construct to prove none of them is silently accepted.

## What is not caught

Evaluation is total for everything the interpreter lets a library catch. Three
things it does not:

- **`abort`** — no `tryEval` catches it.
- **A missing attribute** — including a module dereferencing a slot that did not
  deliver (see [authoring.md](authoring.md#when-a-read-is-refused)).
- **A function called without an argument its pattern requires** — which is why
  an `impl` whose argument pattern is closed is read for its pattern and earns
  `implementation-formals-closed` rather than being applied.

All three are documented as propagating rather than claimed to be contained. Inside
library source they are bugs, and `tests/unit/diagnostics.nix` greps this tree
to keep `throw`, `abort`, `assert` and korora's raising `check` out of it.

What each one prints and the edit that resolves it are in one place, beside a
fourth condition that ends an evaluation without earning a row:
[authoring.md](authoring.md#what-ends-an-evaluation). This page stays the short
statement of the class.
