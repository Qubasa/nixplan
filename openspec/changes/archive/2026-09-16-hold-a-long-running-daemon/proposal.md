## Why

A daemon is the thing this planner cannot deploy. Two gaps, both reachable in an afternoon by
anyone writing their second service:

- **A crashed unit stays dead.** The unit vocabulary is eleven fields (`lib/module.nix:58-70`) and
  the systemd extension table is sixteen directives (`image/read.nix:66-83`); neither carries
  `Restart=`. A module that writes `restart` on a unit gets `implementation-unknown-key`, and a
  module that declares it through `planner.unitExtension` - which the library accepts, because
  `lib/interface.nix:421-432` takes arbitrary `fields` - produces a deployment the planner calls
  applicable and the image build refuses at `image/read.nix:406`. That refusal's own account says
  there is no row above it (`image/read.nix:108-111`), so the first sign of trouble is a build
  failure in a layer the author was told never raises about a deployment's content.
- **A configuration file cannot be shown to a flakelet service at all.**
  `flakelet/read.nix:125,162` refuses every host path where `from != path`, and
  `image/read.nix:217-225` gives every `configData` file `from = staged`. The refusal is written
  against a real limitation - the realiser runs no step on the machine that could assemble bytes -
  but it is applied to files that need no assembly: a `source` disposition is already a finished
  store path (`docs/authoring.md:478`), and a `render` list of nothing but `text` items is bytes the
  plan itself holds, which is why it carries `contentHash` over them. So nginx, PostgreSQL and every
  other server with a configuration file is image-only, and `image` is the realiser that cannot read
  a secret under a confining profile (`image/read.nix:255-263`).

The two are one question - what does a module have to be able to say for a real server to be
deployable - and both are answered without widening anything: a restart policy is two typed fields
and two directives, and the flakelet refusal narrows from "a configuration file" to "bytes that do
not exist until run time".

## What Changes

- **`restart` and `restartSec` join the unit vocabulary.** `restart` takes `no`, `on-failure`,
  `on-abnormal` or `always`; `restartSec` is a duration. Both are typed, both are recorded on the
  unit, and both are part of the entry's key the way every other unit field is.
- **A restart policy that contradicts the unit's shape is a row.** A `oneShot` unit declaring
  `restart = "always"` is `unit-restart-contradicts-one-shot`; a scheduled unit declaring any
  restart but `no` is `unit-restart-on-scheduled`, because the timer decides when that service runs.
- **Both realisers render them.** `Restart=` and `RestartSec=` are emitted on a unit that declared
  them, and omitted entirely on a unit that did not, so a unit that asked for nothing keeps the
  service manager's own default.
- **A configuration file whose bytes exist at build time is shown from the store.** A `source` file
  is shown from its own store path. A `render` list of nothing but `text` items is assembled into the
  artifact at build time and shown from that path. Both are then paths bytes already arrive at, so
  the flakelet reading accepts them.
- **A configuration file whose bytes cannot exist until run time is still refused, and says so
  precisely.** A `render` list carrying any `ref` names a path on the machine, so the realiser that
  runs no assemble step refuses it, and the refusal names the reference rather than the file's
  kind. The planner reports it as a row first, the way every realiser refusal is reported.
- **An extension field no builder renders is a row.** `operator-entry-extension-field-unrendered`
  names the entry, the unit, the extension, the field and the backend, so a deployment that cannot
  be built is refused by the planner rather than by a `throw` in a realiser.

## Capabilities

### Modified Capabilities

- `planner/unit-vocabulary`: the vocabulary gains `restart` and `restartSec`; a policy that
  contradicts a one-shot or a scheduled unit is a row; a configuration file's `source` and
  text-only `render` dispositions are stated to be bytes that exist before the machine does
  anything.
- `realiser/portable-service-image`: `Restart=`/`RestartSec=` rendering, and a configuration file
  shown from the store rather than from the staging directory where its bytes exist at build time.
- `realiser/flakelet-artifact`: which host paths the realiser accepts, narrowed from "a path bytes
  already arrive at" to "a path whose bytes exist before activation"; the artifact carries a file
  assembled from literals.
- `operator/deployment-build`: an extension field the selected realiser has no rendering for is an
  error row naming both sides.

## Impact

- `lib/module.nix`: `unitVocabulary` gains two fields; `readUnits` gains the two contradiction rows.
- `lib/atoms.nix`: a `restartPolicy` atom over the four values.
- `image/read.nix`: `systemdDirectives`-adjacent rendering in `renderUnit` for the two fields;
  `hostPathsOf` shows a `source` file from its store path and a text-only `render` from the path the
  realiser assembled; the `extensionFieldUnknown` account gains the row id it currently states as
  `null`.
- `image/default.nix`: the assemble step no longer stages a file whose bytes are already a store
  path; the remaining staging is for `ref`-bearing recipes only.
- `flakelet/read.nix`: `acceptsHostPath` and `pathRule` restated over the narrowed rule.
- `flakelet/default.nix`: the artifact carries a file assembled from literals beside `meta.json` and
  `units/`.
- `operator/read.nix`: the new row, mirroring the builder's directive table the way
  `operator-entry-access-denied` mirrors its denial table.
- `tests/unit/{module,image,flakelet,operator,diagnostics}.nix`, `docs/authoring.md`,
  `docs/flakelet.md`, `docs/plan.md`, `docs/diagnostics.md`, `CLAUDE.md`.
- `tests/e2e/shared-postgres/` (from `openspec/changes/run-a-shared-database-on-real-machines`)
  gains a restart policy on its server and a configuration file in place of its flag list, which is
  what proves both halves on a machine.
