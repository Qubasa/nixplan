## Why

A machine that declares no `address` ends the evaluation of a deployment the planner otherwise
only warns about, and nothing in the tree can turn that into a row.

`targetOf` composes the target out of the fields it has and omits the ones it does not:
`(if address == null then { } else { inherit address; })` (`lib/resolve.nix:425-438`). The comment
above it states why the address is in there at all: "a unit may be rendered from the address, and an
entry's key hashes the target" (`lib/resolve.nix:421-424`). So a module is invited to render
`target.address`, and on a machine that declares none the field is absent rather than null. Reading
an absent attribute is one of the two failures `builtins.tryEval` does not catch, which
`lib/diagnostics.nix:55-58` records at `diag.guard` itself: "it catches neither an abort nor a
missing attribute". No guard, no row and no later stratum can recover it. `mkPlan` answers
`error: attribute 'address' missing` and no diagnostics table exists to read.

Two modules in this repository render it today. `fixtures/minimal-typed-edge/modules/borg-repo/server.nix:36`
publishes `ssh://borg@${target.address}:${toString alloc.ports.ssh}/srv/borg`, and
`tests/e2e/shared-postgres/deployment/modules/postgresql/databases.nix:84` publishes
`postgresql://${ownerOf db}@${target.address}:${port}/${db}`. Adding one machine that has not been
told where it lives to either fleet replaces a warning with an unattributed abort.

The absence is currently treated as benign at three sites. `address` is read with a `null` fallback
beside four other registry fields (`lib/resolve.nix:268-274`); `machine-target-incomplete` is
produced only for a machine declaring no `system` or no `serviceManager`
(`lib/resolve.nix:378-398`); and `operator-entry-machine-no-address` is a warning whose evidence
says "an address is read by the step that dials a machine and by no step that builds one"
(`operator/read.nix:286-294`). That reasoning is sound about a **build** and silent about an
**evaluation**, and the evaluation is where the address is spent.

The same hole has a second mouth. `incompleteMachines` tests key presence,
`!(machines.${name} ? ${k})` (`lib/resolve.nix:393-398`), while `targetOf` reads the value a field
reader produced (`lib/resolve.nix:428-431`). A registry writing `system = 64` earns
`declaration-field-malformed` and falls back to null (`lib/resolve.nix:102-106`), is excluded from
`targeted` (`lib/resolve.nix:303`), and produces a target with no `system` and no
`machine-target-incomplete` row. A module rendering `target.system.config` then aborts the same way.

## What Changes

- **An address is a field a machine must declare once a placement selects it.** `address` joins
  `system` and `serviceManager` in `machineTargetKeys` (`lib/resolve.nix:50-53`). A selected machine
  missing any of the three is `machine-target-incomplete`, the error row that already carries that
  sentence, naming the machine, the missing keys, the registry file and how many entries were placed
  on it.
- **A placement onto such a machine is not planned.** The machine is dropped from the set a selector
  places on, in the same stratum the row is produced in and before any key exists. The precedent is
  in the tree: a name carrying a key separator is refused and filtered out of the member set
  (`lib/resolve.nix:209-212`, `:528`) rather than planned and then complained about. A row cannot
  stop an abort, so the declaration the abort would come from is what has to go.
- **Every planned entry's target carries every field.** `targetOf` stops composing a partial record.
  An implementation is handed a target with `address`, `system` and `serviceManager`, or its entry
  does not exist, so `target ? address` guards become dead code and `target.address` needs none.
- **The completeness test reads the value, not the key.** A machine declaring `address = 22` is as
  incomplete as one declaring nothing, so the malformed-declaration path reaches no target either.
- **`operator-entry-machine-no-address` is removed.** No plan the planner produces can carry a
  placed entry whose machine record has no address, so the reading would be restating a fact the
  layer above it now owns. The record still carries the absence rather than omitting the field, so a
  hand-written record still reads, and the refusal at the point of dialling
  (`cli/manifest.py:230-251`) does not move.

## Capabilities

### New Capabilities

<!-- none: every requirement below belongs to a capability that exists -->

### Modified Capabilities

- `planner/machine-platform`: the registry's required fields gain the address; a selected machine
  whose target is incomplete carries no planned entry; a planned entry's target is total.
- `planner/plan-artifact`: the recorded scenario that an implementation is handed a machine value
  with no address field is reversed. `prove-plan-on-real-machines/specs/planner/plan-artifact/spec.md:27-31`
  states it and `tests/unit/coverage.nix:126` holds that file accountable, so the reversal is a delta
  there rather than a test quietly deleted.
- `planner/diagnostics`: the general rule this change is the second instance of - a declaration
  whose absence a module would force through a path the planner cannot catch is left out of every
  later stratum, not merely reported.
- `operator/deployment-build`: the address row of the deployment build is removed and the reading's
  totality over the absence is kept.

## Impact

- `lib/resolve.nix`: `machineTargetKeys` gains `address`; `incompleteMachines` reads field values
  rather than declaration keys; `placeable` gains the completeness clause; the selection is read
  twice, once as requested and once as planned, so the row and `member-not-placed` see what the
  selector matched while `lib/plan.nix` sees what survived; `targetOf` returns a total record or
  nothing.
- `lib/plan.nix`: no edit is expected. A member whose every placement was dropped reaches the
  unplaced branch (`lib/plan.nix:1045-1055`), which already records the selector, and the machine
  records are still built from the machines the deployment selected (`lib/plan.nix:1076-1093`).
- `operator/read.nix`: the `operator-entry-machine-no-address` block (`:286-294`) is deleted. The
  record keeps `address` as an absence, which `hold-every-stated-guarantee` requires of it.
- `cli/`: no behaviour change. `cli/manifest.py:230-251` keeps its refusal; its docstring stops
  calling the absence a warning of the planner.
- `tests/unit/platform.nix`, `tests/unit/resolution.nix`, `tests/unit/operator.nix`,
  `tests/unit/diagnostics.nix`, `tests/unit/secrets.nix`: the scenarios below, and three recorded
  expectations that this change reverses.
- `fixtures/minimal-typed-edge/deployment/machines.nix:6-38` declares an address for all four
  machines and `perf/fleet.nix:152-157` and `perf/mesh.nix:186-191` declare one for every generated
  machine, so no golden plan and no golden diagnostics table moves. Every end-to-end registry
  declares one too (`tests/e2e/shared-postgres/deployment/machines.nix:12-27`,
  `tests/e2e/newcomer/template/deployment/machines.nix:2-14`).
- `docs/authoring.md`, `docs/diagnostics.md`, `docs/operator.md`, `CLAUDE.md`.
- Nothing under `image/`, `flakelet/` or `secrets/` changes. `image/read.nix:131-137` keeps pairing
  its three target refusals to `machine-target-incomplete`, which this change widens rather than
  retires, and `secrets-delivery-machine-no-address` stays where it is because it pairs a refusal of
  the secrets reading; what changes is that a planner-produced plan no longer reaches it.
