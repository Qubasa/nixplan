## 1. The module derives its own paths

- [x] 1.1 In `tests/e2e/shared-postgres/deployment/modules/postgresql/databases.nix`, take `instance`
  and `member` from the implementation arguments, derive `name = "${instance}-${member}"`, and use it
  for the data and socket directory (`/var/lib/postgresql/<name>`) and the configuration file
  (`/etc/<name>/postgresql.conf`). Delete every read of `settings.dataDir`. Verify with
  `nix eval --json '.#planner-e2e-shared-postgres'`-free planning: `nix run .#planner -- plan
  tests/e2e/shared-postgres/deployment` shows the two cluster entries carrying two different
  `configData` keys and two different `PGDATA` values.
- [x] 1.2 Change `fixed.port` to `defaults.port = 5432` in
  `.../modules/postgresql/default.nix` and delete `defaults.dataDir`; delete `defaults.dataDir` and
  `fixed.port` from the private member in `.../modules/app/default.nix`. Verify the plan still records
  `alloc.ports.postgres` for both cluster entries and the `dsn` export still carries the port.
- [x] 1.3 In `.../modules/app/client.nix`, derive the record path (`/run/<name>/record`) and the
  extension's `runtimeDirectory` (`<name>`) from `instance` and `member`, delete the `recordPath`
  knob and the `baseNameOf (dirOf ...)` recovery, and keep `label` as the only knob. Verify the three
  consumer entries in the plan carry three different `RECORD_PATH` values under three different
  directories.
- [x] 1.4 Verify no `.nix` file under `tests/e2e/shared-postgres/deployment/` carries an
  interpolation-free absolute host path: `grep -rn '"/' --include=*.nix
  tests/e2e/shared-postgres/deployment | grep -v '\${'` prints nothing.

## 2. The deployment places two clusters on one machine

- [x] 2.1 Add the tag that places the private instance to `alpha` in
  `.../deployment/machines.nix`, and verify `beta`'s tags are unchanged.
- [x] 2.2 In `.../deployment/instances.nix`, place both `own-app` members on that tag, state
  `5433` for its database member, delete all three `recordPath` statements, and keep the labels.
  Verify the file carries no absolute path and that `planner plan` places
  `own-app:own`, `own-app:client`, `pg:cluster` and `near-app:client` on `alpha` and `far-app:client`
  on `beta`.
- [x] 2.3 Verify the deployment is applicable and its diagnostics table carries no error row, and in
  particular none of `entry-host-path-claimed-twice`, `entry-port-claimed-twice` or
  `entry-unit-directory-shared` from the change that lands before this one.

## 3. The test reads the plan and the machines

- [x] 3.1 Delete `NEAR_RECORD`, `FAR_RECORD`, `OWN_RECORD`, `DATA_DIR`, `OWN_DATA_DIR` and
  `CONF_PATH` from `tests/e2e/shared-postgres/test_shared_postgres.py`, and read each path off the
  plan through helpers on `Run` (the entry's `configData` keyset, `units.<unit>.env`). Verify the file
  contains no `"/` literal outside a docstring.
- [x] 3.2 Move the private instance's keys and machine: `OWN_KEY`, `OWN_DB_KEY` and the delivery set
  of `own-app:vars/password-private` are `alpha`'s. Verify the existing per-machine credential tests
  pass with the value source built from the plan's own `delivery` records.
- [x] 3.3 Raise `DISK_GIB` for the machine now holding two data directories and verify the stage
  resumes: the first run is cold, `rookery snapshot list` shows one new entry for this folder and
  none for another.
- [x] 3.4 Add `test_two_instances_of_one_module_run_on_one_machine`: one ssh command reporting both
  servers' `MainPID`, their `PGDATA`, their ports and their socket files, asserting all six are
  pairwise different and both units active.
- [x] 3.5 Add `test_every_path_a_unit_uses_comes_from_the_plan`: every path asserted in this module is
  read from the plan, each contains its entry's instance and member, and the deployment's own files
  state none of them.
- [x] 3.6 Add `test_each_application_reaches_the_database_it_wired`: each consumer's record names the
  identity of the cluster it wired, the two identities differ, and each row is readable in its own
  cluster.
- [x] 3.7 Add `test_neither_cluster_carries_the_others_databases`: each server's `datname` list read
  over its own socket, asserted against what the deployment declared for it.
- [x] 3.8 Add `test_a_credential_of_the_shared_cluster_is_refused_by_the_private_one`: the shared
  instance's password presented to the private instance's port, and the server's own refusal read
  back.
- [x] 3.9 Add `test_the_private_clusters_credential_is_on_its_own_machine_only`: present on `alpha`,
  absent on `beta`, and the plan's delivery record naming `alpha` alone.
- [x] 3.10 Verify every case is one ssh command whose output is `key=value` lines, and that the
  existing eight tests of the folder still pass unchanged in meaning.

## 4. The layer's own checks

- [x] 4.1 Keep `statefulFolders` in `tests/unit/layers.nix:700` recognising this folder once
  `dataDir` is gone as a knob - either the derived name carries that text or the detection reads the
  fact that replaced it - and add `testAFolderWritingStateIsRecognisedByWhatItDeclares`. Verify it is
  red against a detection that misses the folder.
- [x] 4.2 Add `testAStatefulFolderDeclaresItsSpaceOnItsOwnStage` and
  `testOneModuleFileBacksBothInstances` to `tests/unit/layers.nix`. Verify the second is red if the
  application's database member is pointed at a second copy of the module file.
- [x] 4.3 Move this change's two spec files from `excused` to `accountable` in
  `tests/unit/coverage.nix`, the excuse having expired with the first ticked task, and verify the
  scenario cross-walk finds all nine derived test names.

## 5. Verification and record

- [x] 5.1 Run `nix build .#checks.x86_64-linux.planner-tests` and verify every suite is green,
  including `tests/unit/postgres.nix` and the layer checks.
- [x] 5.2 Run `nix run .#planner-e2e shared-postgres` and verify every test passes on real machines,
  including the four new ones; record the wall time of the cold run.
- [x] 5.3 Update `CLAUDE.md`'s `shared-postgres` invariants: the port is a default and why, every host
  path is derived from `instance` and `member`, which machine holds which cluster, the record's new
  location, and that `disk_gib` moved for this folder's cut alone.
- [x] 5.4 Run `nix build .#checks.x86_64-linux.treefmt` and verify formatters, `ruff`, `mypy` and
  `vale` are green.
