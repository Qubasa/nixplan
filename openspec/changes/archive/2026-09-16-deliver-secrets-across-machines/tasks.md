# Tasks

Ordered end-to-end first: the folder that proves the capability on real machines is written before
the library that satisfies it, so the target is a run rather than a shape.

## 1. The machine layer, written first

- [x] 1.1 `tests/e2e/secret-delivery/deployment/`: `interfaces/default.nix` declaring
  `tokenEndpoint` with `url` (public `korora.url`), `token` (secret `korora.secretRef`) and
  `caCert` (public `korora.string`).
- [x] 1.2 `modules/issuer/api.nix`: `vars.session = { per = "instance"; files.token.secrecy =
  "secret"; }`, `vars.ca = { per = "instance"; deploy = false; files."ca.pub".secrecy = "public"; }`,
  a fixed port claim, one long-running unit serving `200` only when the request's bearer equals the
  bytes at `vars.session.token.path` and `401` otherwise, binding `0.0.0.0`; exports
  `url` from `target.address` and the claimed port, `token = vars.session.token`,
  `caCert = vars.ca."ca.pub".value`.
- [x] 1.3 `modules/probe/client.nix`: `uses.api = { interface = tokenEndpoint; reads = [ "url"
  "token" "caCert" ]; }`, one one-shot unit that fetches with the value at
  `results.api.token.path` and asserts `200`, fetches without it and asserts `401`, and asserts its
  `CA_CERT` environment value is non-empty; `remainAfterExit` so the run is observable after it
  exits.
- [x] 1.4 `modules/idle/job.nix`: one long-running unit, no slot, no generator — the bystander.
- [x] 1.5 `deployment/machines.nix`: `alpha` `10.0.0.10` tag `issues`, `beta` `10.0.0.11` tag
  `reads`, `gamma` `10.0.0.12` tag `idle`, all `x86_64-linux`/`systemd`.
- [x] 1.6 `deployment/instances.nix`: `issuer` (exposes `api`), `probe` (wires `api` to `issuer`),
  `idle`; `deployment/default.nix` assembling `args` with `interfaces`, `sources` and `varsState`
  keyed by vars entry, mirroring `tests/e2e/wired-pair/deployment/default.nix`.
- [x] 1.7 `tests/e2e/secret-delivery/artifacts.nix`: the three flakelet artifacts, `plan.json`, and
  a `passthru` carrying the plan, the keys, the vars entry keys and the token bytes the run
  delivers.
- [x] 1.8 `flake-module.nix`: `planner-e2e-secret-delivery` package plus its two entries in
  `e2eArtifactPaths` (`PLANNER_SECRET_DELIVERY`, `PLANNER_SECRET_DELIVERY_DEPLOYMENT`), so the app
  and `planner-e2e-env` export the same set.
- [x] 1.9 `tests/e2e/delivery.py`: `vars_entries`, `deliver_value` and `value_path`, with the
  refusal for a delivery-set member the plan gives no address for; `tests/e2e/test_harness.py`
  gains the pure-half assertions for them.
- [x] 1.10 `tests/e2e/secret-delivery/test_secret_delivery.py`: the session-scoped three-machine
  `delivery.cluster_stage`, the delivery phase, and one test per scenario of
  `specs/delivery/real-cluster/spec.md`:
  `test_a_secret_reaches_the_machines_the_plan_names`,
  `test_a_machine_outside_the_delivery_set_holds_nothing`,
  `test_a_value_nobody_receives_is_on_no_machine`,
  `test_a_consumer_authenticates_with_the_delivered_secret`,
  `test_the_provider_refuses_a_request_without_it`,
  `test_no_artifact_carries_the_delivered_bytes`,
  `test_a_public_generated_value_travels_in_the_plan`.
- [x] 1.11 Confirm the folder is refused for the right reason before the library lands (the
  planner's `declaration-excluded-key` rows for `per` and `deploy`), so the run is a red test rather
  than a missing one.

## 2. The declaration

- [x] 2.1 `lib/excluded.nix`: delete the `per` and `deploy` constructs and the
  `per/deploy/delivery` row.
- [x] 2.2 `lib/module.nix` `readVars`: accept `per`, `deploy` and `reads` beside `files`; return
  `generators.<gen> = { files, per, deploy, reads }`; rows for a `per` outside the domain, a
  `deploy` that is not a boolean, a `reads` that is not a list of declared sibling names, and the
  `instance`-reads-`placement` arity mismatch.
- [x] 2.3 `lib/module.nix`: delete `slot-reads-secret-export` and the `secretReads` filter, and
  drop it from `resolvable`.
- [x] 2.4 `lib/resolve.nix`: the per-instance generator collision row, emitted once per instance.

## 3. Resolution

- [x] 3.1 `lib/resolve.nix` `mkPlacement`: `path = "/run/vars/${iname}/${gen}/${fname}"`; read the
  file state under the value's own entry key rather than under the machine; carry `per`, `deploy`
  and `reads` on the resolved record.
- [x] 3.2 `lib/resolve.nix` `exportRecord`: keep the generator and file a vars-backed export came
  from, so an edge can name the value behind an export.
- [x] 3.3 `lib/resolve.nix` `mkEdge`: a secret export resolves to `{ path, secrecy }` for the
  consumer; a read of a secret export backed by a `deploy = false` generator is an error row.
- [x] 3.4 `lib/resolve.nix`: the delivery index — for each generated value, the owner's placements
  and, from the reader index's providers, the machines of the entries whose `reads` name an export
  it backs, each with the reason it is in the set.

## 4. The plan

- [x] 4.1 `lib/plan.nix`: `varsEntries` — one entry per value, keyed `<instance>:vars/<gen>` or
  `<instance>:vars/<gen>@<machine>`, carrying `per`, `deploy`, `delivery`, `deliveryDerivedFrom`,
  `reads`, `dependsOn`, `files` and `key`.
- [x] 4.2 `lib/plan.nix` `entries`: merge the vars entries into the plan beside the machine and
  service entries.
- [x] 4.3 `lib/plan.nix`: the row for a unit, environment, extension or configuration file that
  mentions the path of a file no machine receives, over `mentionSites`.

## 5. The realisers

- [x] 5.1 `flakelet/read.nix`: refuse only the host paths whose `from` differs from their `path`,
  with the message naming the step that does not exist; state the delivered case in the comment.
- [x] 5.2 `image/read.nix`: confirm nothing depends on the old path shape, and that a vars entry in
  the plan is ignored by a reader asked for a service entry (`parseKey` refuses `vars/`).

## 6. The evaluating layer

- [x] 6.1 `tests/unit/secrets.nix`: one test per scenario of `specs/planner/secret-delivery/spec.md`
  and of the `ADDED` requirements of `specs/planner/plan-artifact/spec.md`; register it in `suites`
  in `tests/default.nix`.
- [x] 6.2 `tests/unit/coverage.nix`: the five new spec files in `accountable`.
- [x] 6.3 `tests/unit/exclusions.nix`: delete `testPerIsRefused` and `testDeployIsRefused`, and move
  the row count the suite compares against the fixture README's table.
- [x] 6.4 `tests/unit/resolution.nix`: rewrite `testAConsumerAsksForThePrivateHalf` for the
  acceptance and the delivery set; update `testAProducerUsesItsOwnSecret` and
  `testASecretExportWithNoReader` for the instance-qualified path and the owner's set.
- [x] 6.5 `tests/unit/{plan,units,image,flakelet}.nix` and `tests/unit/worked.nix`: `varsState`
  keyed by vars entry, and the instance-qualified paths.
- [x] 6.6 `tests/unit/flakelet.nix`: `testAnEntryShownAGeneratedFile` asserts the build and the
  absence of bytes; the configuration-file refusal is untouched.
- [x] 6.7 `perf/{fleet,mesh}.nix`: `varsState` keyed by vars entry.

## 7. The fixture and the documents

- [x] 7.1 Regenerate `fixtures/minimal-typed-edge/plan/backup.json` with
  `nix eval --json .#planner.worked.plan | jq -S .`, and `plan/diagnostics.txt` if it moves.
- [x] 7.2 `fixtures/minimal-typed-edge/README.md`: delete the `per`, `deploy`, per-consumer delivery
  row from the exclusion table; `plan/README.md` gains the vars entries it now carries.
- [x] 7.3 `docs/README.md`: the `varsState` shape and the new library surface.
- [x] 7.4 `docs/authoring.md`: `per`, `deploy`, `reads`, what a consumer of a secret writes, and the
  `varsState` example.
- [x] 7.5 `docs/plan.md`: the vars entry class and its fields.
- [x] 7.6 `docs/diagnostics.md`: the new rows.
- [x] 7.7 `docs/cluster.md` and `README.md`: the third folder, its machines and its artifact.
- [x] 7.8 `docs/flakelet.md`: what the realiser now accepts and why.
- [x] 7.9 `CLAUDE.md`: the invariants this change adds — the vars entry key shape, the delivery set's
  single source, `varsState`'s keying, and the flakelet host-path line.

## 8. Verification

- [x] 8.1 `nix build .#checks.x86_64-linux.planner-tests -L`.
- [x] 8.2 `nix build .#checks.x86_64-linux.planner-perf -L`; regenerate `perf/budgets.json` if the
  new entry class moved the per-entry cost, and record why.
- [x] 8.3 `nix build .#checks.x86_64-linux.planner-delivery -L` and `treefmt`.
- [x] 8.4 `nix run .#planner-e2e secret-delivery` — the folder passes against real machines.
- [x] 8.5 `nix run .#planner-e2e` — the two existing folders still pass.

## 9. Found by the machine layer

- [x] 9.1 `image/read.nix`: quote every rendered `Environment=` value and refuse one containing a
  newline. The first public export whose value carried a space reached the unit as two assignments
  and the consumer read back the first word.
- [x] 9.2 `specs/realiser/portable-service-image/spec.md`: the requirement and its two scenarios,
  with `testAnEnvironmentValueCarriesASpace` and `testAnEnvironmentValueCarriesANewline` in
  `tests/unit/image.nix`.
- [x] 9.3 `perf/budgets.json`: re-recorded. A generated value is an entry, so per-entry cost fell at
  every fixture and the ratchet demanded the tighter figures.
- [x] 9.4 `tests/e2e/portable-image/test_portable_image.py`: a stray `breakpoint()` left the whole
  run wedged in pdb. Removed.
