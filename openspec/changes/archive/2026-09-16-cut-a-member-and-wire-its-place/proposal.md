## Why

A module publishes one composition and a deployment takes all of it or writes a second module.
`members.<name>.enable` and `wire.<member>.<slot>` are refused by name
(`lib/excluded.nix:37-44`, reported at `lib/resolve.nix:1436-1444`), and the trigger recorded beside
them is *"a module publishing a composition whose coherent cuts an operator wants"*. That module now
exists twice over:

- `notes/examples/instance-as-group/` is written around it. `mygame` keeps three members and never
  mentions a database; `mygame-eu` and `mygame-us` are the same module with
  `members.db.enable = false` and `wire.server.db` naming a database of `pg-shared`
  (`deployment/instances.nix:139,155,164,187`). The folder's README calls that pair "the whole rule
  in two files", and its own first line says the shape does not exist in any tree.
- `tests/e2e/shared-postgres/`, from `openspec/changes/run-a-shared-database-on-real-machines`,
  works around it: its two consumers are two instances of a consumer module that declares its slot
  unconditionally, because a module that owned a private database and could be cut down to a shared
  one is not writable today.

What the cut buys is not a convenience. Without it, a module author who wants to serve both cases
publishes two roots over the same leaves, and the deployment learns which parts of a composition
exist from the *module's* file name rather than from its own text. With it, a reference inside a root
is a binding when its target is a kept sibling and an address when it is not, and that is the one
rule the corpus spends three files establishing.

Two smaller gaps come with it. A capability has no way to say it may be taken once
(`capabilityKeys` is `[ "interface" "severity" ]`, `lib/module.nix:107`), so two instances wiring one
database is legal and silently wrong; and a deployment that cuts a member may still name it in
`placement` or `settings`, which needs to be a row rather than a placement of nothing.

And one larger one, without which the cut has nothing to convert: **a root cannot bind one member's
slot to a sibling's capability at all.** `serviceKeys` is `[ "module" "defaults" "fixed" ]`
(`lib/compose.nix:14-18`), so a member handle takes no wire, and a slot is filled only by an
instance-level `wire.<slot>` that reaches every member declaring that name. A module composing a
consumer and its private provider therefore cannot say so; the deployment has to. That is the half
of the corpus's `mygame/default.nix` this tree has no construct for, and it is what makes "a
reference is a binding when its target is a kept sibling" a rule about something.

## What Changes

- **A deployment may cut a member.** `members.<name>.enable = false` removes that member from the
  instance: it produces no plan entry, takes no placement, needs no settings, owns no generated value
  and contributes no closure.
- **A root may bind a member's slot to a capability it holds.** `service "<name>" { module; wire.<slot> = <a member's capability>; }`
  fills that member's slot from inside the module, so a composition's internal edges are Nix
  bindings the author wrote and a mistyped one is an error in the module's own file.
- **Cutting a member turns every binding that named it into an unfilled slot**, and the deployment
  fills it with `wire.<member>.<slot> = { instance; provides; }`. A slot whose binding points at a
  kept sibling stays a binding and SHALL NOT be wireable from the deployment - a deployment that
  wires one earns a row naming both.
- **Cutting changes no key that remains.** An entry of a kept member carries the key it had when
  nothing was cut, so a deployment that cuts a member redelivers nothing else.
- **A capability may declare that it is taken once.** `consumers = "one"` on a provided capability
  makes a second instance wiring it an error row naming both consumers and the capability.
- **Naming a cut member is a row.** A `placement`, a `settings` namespace or a wire naming a member
  the instance cut is an error row naming the member and the cut, rather than a placement of a member
  that does not exist.
- **The exclusion table loses one row.** `member cuts` leaves `lib/excluded.nix`, the exclusion
  suite, and the table in `fixtures/minimal-typed-edge/README.md`; six of the seven rows remain.

## Capabilities

### Modified Capabilities

- `planner/typed-edge`: a member may be cut; a member-scoped wire fills the slot the cut opened; a
  binding to a kept sibling is not wireable; a capability may be declared single-consumer, and a
  second consumer is a row.
- `planner/plan-artifact`: a cut member produces no entry and no value, and no entry that remains
  changes its key or records where the composition was cut.
- `planner/diagnostics`: the rows this adds, and the exclusion row it removes.

## Impact

- `lib/resolve.nix`: `instanceKeys` gains `members`; the member reading drops a cut member before
  placement, settings namespaces and generators are read; the wire reading takes a member's binding
  as the slot's value and reads `wire.<member>.<slot>` as an address rather than refusing it; the
  binding-versus-address rule; the single-consumer check, which is a fold over every instance's
  wires rather than a per-slot check.
- `lib/compose.nix`: `serviceKeys` gains `wire`, so a member handle carries the bindings the root
  wrote; and the handles carry which members the deployment kept, so a binding naming a cut member
  resolves to an unfilled slot rather than to a value.
- `lib/module.nix`: `capabilityKeys` gains `consumers`.
- `lib/excluded.nix`: `enable` and `memberWire` removed, and the `member cuts` row with them.
- `lib/plan.nix`: nothing, which is the claim - a cut is an absence of entries and not a field.
- `tests/unit/exclusions.nix` and `fixtures/minimal-typed-edge/README.md`: the table and its row
  count.
- `tests/unit/{resolve,compose,typed-edge,plan,diagnostics}.nix`, `docs/authoring.md`,
  `docs/diagnostics.md`, `docs/plan.md`, `CLAUDE.md`.
- `tests/e2e/shared-postgres/`: its two consumer instances become two cuts of one consumer module
  that owns a private database, wired to the shared cluster. Every plan key of that folder stays
  where it is, which is the evidence the corpus asks for.
