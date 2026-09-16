# Design

## D1 - A refusal belongs to the layer that holds the fact

Three layers hold three kinds of fact, and each kind has exactly one layer that can see it whole:

| Fact | Held by | Reported by |
| --- | --- | --- |
| the entry's units, closure, target, configuration data, generated files | the plan | `mkPlan`, as a row |
| the realiser and the confinement profile of an entry | the realisation statement | `operator/read.nix`, as a row |
| the bytes of an artifact | the derivation | nothing - a build either runs or does not |

The rule follows: a refusal about a fact the plan carries is a row from `mkPlan`; a refusal about a
fact the statement carries is a row from the deployment build; and a realiser raises only for a
condition one of those two already reported as an error row.

The alternative is the arrangement the tree has today: the realiser refuses, because the realiser is
where the fact is finally needed. That reads well and loses for three reasons.

- **A raise is not a table.** A realiser's `fail` is a string out of one call, and the caller is
  building one entry of one deployment. The user with four mistakes across three instances gets the
  first one, then the second on the next `nix build`. The whole point of the row format is that
  forty instances with two mistakes render as forty instances with two marks.
- **The realiser is called too late to be believed.** `mkPlan` answers `applicable = true` and the
  build then throws. Every consumer that reads `applicable` - the command, a downstream flake, the
  end-to-end folders - was told the deployment was fine by the layer whose job is to say so.
- **A statement-level fact reaches the realiser stripped of the thing that would explain it.**
  `image.build` takes `{ plan, key, profile }`. Handed `profile = "stricT"`, the realiser can say
  the profile is not one of four; it cannot say which statement wrote it, or that the entry took it
  from the `default` statement, or that a sibling key was the one the author meant. The reading has
  the whole statement, so its row can name the key, the field and the alternatives.

The realisers keep their raises. A raise there is the guard for a caller that imported
`image/read.nix` and called it directly, which the unit suites do, and which any consumer holding
the two files as store paths may do. What changes is that no path through the deployment build can
reach one of those raises without a row having been produced first.

## D2 - The audit, refusal by refusal

The rule is only worth writing down if every existing refusal has an owner under it. Every `fail`
in `image/read.nix` and `flakelet/read.nix`, and the layer that reports it first after this change:

| Refusal | Where | Reported first by |
| --- | --- | --- |
| entry records no `closure` | `image/read.nix:181` | nothing - the field is always recorded (D4) |
| entry records no `units` | `:180` | nothing - the field is always recorded (D4) |
| entry records no unit, nothing to attach | `:339` | the reading: an entry with no unit is realised into nothing, and a statement naming it is a row (D5) |
| entry records no `target`, no platform, no service manager | `:178`, `:187`, `:193` | `mkPlan` - `machine-target-incomplete` already fires for a machine record that carries neither half |
| a closure root outside the store directory | `:343` | `mkPlan` - a new error row; today the root is at most an unmentioned-root warning |
| a closure root the plan delivers by reference | `:345` | `mkPlan` - a new error row |
| a unit mentions a store path the closure does not declare | `:282` | `mkPlan` - `closure-path-undeclared` |
| an extension field for another backend | `:284` | `mkPlan` - `unit-extension-backend-mismatch` |
| an extension field this builder has no rendering for, or one it cannot spell | `:286`, `:288` | the reading, through the realiser's own directive table (D3) |
| a unit value carrying a newline | `:355` | `mkPlan` - a new error row |
| a profile that is not one of four | `:199` | the reading - a statement fact (D7) |
| a unit needing an access the profile denies | `:350` | the reading - the statement crossed with the entry (D3) |
| the machine runs a service manager this builder does not emit for | `:341` | the reading - the statement crossed with the entry (D3) |
| the key is not a placed entry key | `:92` | the reading - shape classification (D6) |
| the plan has no such entry | `:173` | the reading - it enumerates the plan |
| a service name the endpoint refuses | `flakelet/read.nix:132` | the reading, through the realiser's own predicate (D3) |
| a unit file name the endpoint refuses | `:134` | the reading, through the realiser's own predicate (D3) |
| a host path this realiser cannot assemble | `:135-139` | the reading - the statement crossed with the entry (D3) |

Three new rows in `mkPlan`, eleven in the reading, one plan-record change, and one entry class that
realises nothing. Nothing on the list stops being a refusal.

## D3 - The reading asks each realiser what it accepts

Six of the rows above are about the entry and the realiser together, and two of those are rules only
flakelet knows: its name rule and its unit-file rule, both restated from flakelet's own
`manager.rs`. Copying either into `operator/read.nix` would give one rule two homes, which is the
failure `flakelet/read.nix:36-40` already guards against by writing the rule as the sentence the
refusal prints.

The reading therefore imports what it needs and asks. `operator/read.nix` already imports
`../image/read.nix` for `nameOf`, `unitFileName` and `profileNames`; it gains `acceptsName`,
`acceptsUnit` and `confinement` from `../flakelet/read.nix`, all four of which are pure predicates
over strings and take no `pkgs`. The realiser stays the author of its rule, the reading is the
author of the row, and the sentence in the row and the sentence in the raise are the same string.

The alternative - a realiser exporting a `rows` function so each realiser writes its own rows - was
rejected because a row needs the statement to be worth reading (D1) and a realiser is not handed
one. A realiser exporting predicates and the reading writing rows keeps the statement where the rows
are written.

## D4 - The two fields the pruning may not drop

`pruned` (`lib/plan.nix:22`) removes every empty list and empty attribute set from an entry record.
For most fields that is right: `alloc`, `vars` and `configData` are absent when there is nothing to
say, and a reader writes `entry.alloc or { }`. For `closure` and `units` it is wrong, and the reason
is the one `CLAUDE.md` already gives for `delivery` and `deliveryDerivedFrom`: a reader must not be
able to mistake either field for an absence.

An empty closure and an empty unit set are answers. "This entry depends on no store path" and "this
entry runs nothing" are facts about a service, produced by a module that ran correctly. An absent
field is a different claim - that the plan does not know - and `required` in the image reader reads
it as exactly that.

| Option | Why not |
| --- | --- |
| `entry.closure or [ ]` in the realisers | It makes an absent field and an empty field one answer, so a plan that genuinely failed to record a closure builds an image with none. `required` exists to catch that, and this would delete it. |
| Keep pruning and add a row for the empty case | The empty case is correct. A row would refuse two ordinary services. |
| Stop pruning altogether | The pruning is what keeps a plan readable, and the golden fixture is compared field by field. Twelve empty fields per entry would be noise in every plan a person reads. |
| Exempt `closure` and `units` | One rule, stated where the analogous rule for `delivery` already is. |

The cost is a golden-plan regeneration: `fixtures/minimal-typed-edge/plan/plan.json` gains a
`closure` and a `units` field on the entries that were losing them. That file is regenerated with
the command `CLAUDE.md` names, and the fixture's diagnostics file does not move, because no row
changes.

## D5 - A placed entry that runs no unit

With `units` always recorded, `talker:main@host` reaches the next refusal down: "entry records no
unit, so there is nothing to attach" (`image/read.nix:339`). That refusal is right about an image -
an image with no unit has nothing for `portablectl` to attach - and wrong about the deployment, which
is correct and ought to build.

The entry runs nothing because its whole contribution is an export another entry reads. The reading
classifies it: a placed entry declaring no unit is realised into nothing. It appears in the
deployment record with its machine and its address, so a consumer can see the plan placed it, and it
contributes no artifact and no row.

That leaves one way to ask for the impossible: naming such an entry in the realisation statement.
`realise."talker:main" = { realiser = "image"; profile = "strict"; }` asks for an image of an entry
with nothing to attach, and receives an error row naming the entry and the statement key. The
alternative, silence, is the defect this change exists to remove: a user who states a realiser and
receives no artifact has been ignored.

## D6 - Classification by shape, and the key that matches neither

`isMachineRecord = key: match "machine:.*" key != null` asks a question about text that only a record
can answer. `machine` is a legal instance name, `vars/x` is a legal member name, and the plan's key
grammar reserves neither, so both classifications are wrong on inputs the planner accepts. Prefix
matching is wrong in principle for the same reason the repository refuses to key an entry on its
units: identity is structural. What a record is, is decided by what it records.

The three shapes are already disjoint and already documented:

| Shape | Test | Stated by |
| --- | --- | --- |
| generated value | records `delivery` | `CLAUDE.md`: every value entry carries `delivery` and `deliveryDerivedFrom` whether or not either is populated |
| service entry | records `placement` | `lib/plan.nix:565` and `:611` - both the placed and the unplaced form record it |
| machine record | records neither, and records `address` and `tags` | `lib/plan.nix:777-781` |

A service entry is then placed when its key carries an `@`, split at the last one, as `CLAUDE.md`
already requires of every reader of a key. That split is a reading of the key grammar and not a
classification: it answers "on which machine", never "what kind of record is this". An instance
called `machine` is a service entry, and `machine:only@host` names instance `machine`, service
`only`, machine `host`.

A key matching none of the three shapes is a record the reading cannot place. Three options, and the
first two lose:

- **Ignore it.** The behaviour today for `machine:only@host`: a build with no `entries/` and an
  apply that copies nothing and reports success. A defect that reports success is worse than one
  that stops.
- **Assume it is a machine record.** The classification the reading has today, by another name.
- **Refuse it with a row naming the key and the three shapes.** A plan that grows a fourth kind of
  record then fails one named test in the unit layer, and the person adding the kind is the person
  who reads the row.

The third. The row is an error, because a build that skips a record it does not understand cannot
know whether it skipped an artifact somebody needs.

## D7 - A statement that names nothing, and a field the default carries

`statementOf` reads the statement by plan key, then by the `<instance>:<service>` prefix, then by
`default`, and returns `{ }` when none matches. Three defects follow from what it does not do.

A key that names no entry and no prefix of one is silently a statement about nothing. The reading
enumerates the plan, so it can compare: every key of `realise` other than `default` is either a plan
key the plan carries or a prefix of one. Anything else is an error row naming the key given and the
nearest keys the plan carries. This is the same posture as the command's refusal of an entry name it
cannot find, and the reason it is an error rather than a warning is that the statement expresses an
intent about confinement, and a confinement decision nobody applied is the defect in `stricT`.

A statement that is not a record - `realise."svc:only" = "image"` - reads as an attribute set, and
`statement.realiser or stated` answers the default. A string is not a statement, and the row names
the type.

The fallback is per statement, not per field: `realiser` falls back to `realise.default.realiser`
because `readEntry` reads `stated` separately, and `profile` has no such line. A deployment that
states `default = { realiser = "image"; profile = "strict"; }` and then names one entry to pin
something else about it loses the profile and is refused. The fix is to resolve the statement field
by field down the same three steps the statement is already read by, so `profile` and `realiser`
inherit alike. The alternative - documenting the asymmetry - was rejected because no reader can
predict which fields inherit, and the set of fields will grow.

## D8 - What a build of an inapplicable deployment produces

`operator/default.nix:92` is `if reading.refused then throw reading.refusal else built`, and the
`built` it discards is the tree holding `plan.json`, `diagnostics.json` and `diagnostics.txt`. The
rendered table survives as the message of the raise; the machine-readable half does not exist for
any deployment that has an error, which is every deployment a tool would want to read rows out of.

The derivation is therefore produced. Two shapes for it:

| Shape | For | Against |
| --- | --- | --- |
| the tree, with no `entries/` | one fact in one place: the rows in `diagnostics.json` say the deployment is inapplicable, and the absence of an artifact follows from that | the absence is also what an applicable deployment placing no entry produces |
| the tree, plus a marker file recording refusal | a consumer reads one field | a second statement of a fact the table already carries, in a file that can disagree with it, and a consumer that reads the marker and not the table loses the reason |

The marker loses. The tie-breaker is the objection to the winner: the shape of the tree is not the
place applicability is read from, so the ambiguity is not one a consumer meets. `diagnostics.json`
carries the rows, error severity is computable from them, and a build with no artifacts and no error
rows is a deployment that placed nothing. The requirement says so, and says the shape of the tree
carries no claim about applicability.

The refusal a person sees is unchanged in wording and moves in place: `planner build` prints the
rendered table and exits non-zero, which is `make-an-apply-observable`'s to state, and a Nix
consumer asking for an entry's artifact of an inapplicable deployment is refused with the same table
the file carries. Nothing is realised for an inapplicable deployment, which is what the requirement
title has said since the capability was written.

## D9 - The identity a build publishes, and the identity a machine stores

Two digests exist for one entry and they answer different questions:

| Digest | Computed over | Moves when |
| --- | --- | --- |
| the plan entry key (`entry.key`, published as `key` in `manifest.json`) | instance, service, machine, target, pin, units, closure, values read, keys depended on | anything about the plan entry moves, including the machine's address |
| the artifact version (`image.version`, stored by the endpoint as `settings_hash`) | name, units, closure, store directory, service manager, host paths, instance, service, machine, platform | a byte of the artifact moves |

Changing a machine's address moves the first and not the second, so the field a build publishes and
the field a machine reports can never be compared - which is what a status report needs to do.

Settled: the build publishes the artifact version. `manifest.json`'s per-entry identity becomes the
digest the endpoint records, and the plan entry key stays in `plan.json`, which travels in the same
tree and is where provenance belongs.

The cost of the other direction - making the endpoint store the plan entry key - is the property
`test_an_unchanged_entry_is_a_no_op` and `testAnUnchangedEntryIsANoOp` assert. flakelet decides a
generation is a repeat by comparing `settings_hash`, so an address edit would present every entry on
that machine as a new generation with byte-identical content. `CLAUDE.md` records the same reasoning
for the image's own version digest: a configuration file's content moves the plan key and never
enters the image, so keying the image on it would rebuild equal bytes. Publishing the plan key as
the machine-side identity is that mistake in the other direction.

`flake_url` stays `plan:<plan key>`. It is provenance and display, and naming the plan key there is
what lets a person on the machine find the entry in the plan.

## D10 - An address is needed to apply and not to build

`operator-entry-machine-no-address` is an error, so a registry that has not yet been told where a
machine lives cannot build any artifact of any entry - including the entries on the machines whose
addresses are known. Nothing in a build reads the address: it is copied into the deployment record
for the command to dial with.

`lib/excluded.nix:23` records the shape this collides with - an address assigned only after a daemon
authenticates, in two of the twelve sketches the corpus came from. A deployment in that shape has to
be buildable.

The row therefore becomes a warning, the record carries the absence rather than omitting the field,
and refusing to dial stays with the command, where `operator/apply-command`'s "The command refuses
before it dials" already requires every refusal derivable from the plan and the record to happen
before the first contact. The severity rule in `planner/diagnostics` is unharmed: a warning does not
block an apply of the entries that can be applied, and the entry that cannot be dialled is refused
by the command that would dial it.

The alternative, deferring the question to `make-an-apply-observable`, was rejected because the
error is what blocks the build, and this change is where the build's refusals are decided.

## D11 - One constructor for a row, wherever a row is built

`lib/diagnostics.nix:33-47` is the only place that knows a row has six fields and that three of them
pass through `util.oneLine`. `lib/default.nix:70-73` exports `render` and `mkTable` and keeps the
constructor private, which was right while `lib/` was the only producer. `operator/read.nix` is the
second producer, and it writes the six fields three times and applies `oneLine` nowhere.

The consequence is not hypothetical: the reading interpolates `key`, `realiser` and `profile` into
messages, all three from a deployment's own text, and the rendering in `diagnostics.txt` is
line-oriented. One newline in a member name splits one row into two lines, and every reader that
parses the rendered table reads a row that does not exist.

`row`, `error` and `warning` are therefore exported beside `render` and `mkTable`, and every
producer outside the library uses them. The alternative - applying `oneLine` inside `mkTable` - was
rejected because `mkTable` is also the deduplicating and sorting step, and a row that arrives
malformed and is repaired at the table has already been compared against its neighbours in its
malformed form. Repair belongs at construction, which is where the library does it today.
