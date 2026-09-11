## 1. Register the change and the shared image's new fact

- [ ] 1.1 List this change's two spec files under `excused` in `tests/unit/coverage.nix` with the
  reason the tree already uses for an unimplemented change, and verify
  `nix build .#checks.x86_64-linux.planner-tests` reports no unclassified specification - without
  this the suite fails the moment the files are `git add`ed
- [ ] 1.2 Add `users.users.postgres` (and its group) to `tests/e2e/guest.nix` with an assertion
  naming `tests/e2e/shared-postgres/`, stating that no plan creates an account and that the addition
  re-keys every snapshot cut, and verify the image evaluates:
  `nix build .#planner-e2e-paths` resolves and the assertion message is present in the source
- [ ] 1.3 Record the orphaned cuts before and after with `rookery snapshot list`, run
  `rookery snapshot gc --all`, and verify one folder resumes cold and then warm on a second run

## 2. The deployment

- [ ] 2.1 Write `tests/e2e/shared-postgres/deployment/interfaces/default.nix` declaring one
  interface with `dsn`, `username`, `password` (secret) and `version`, and verify a throwaway
  `nix eval` of the interface reports the four export atoms and their secrecies
- [ ] 2.2 Write `deployment/modules/postgresql/databases.nix`: a leaf with a `fixed` port claim, one
  generator per configured database, `provides` mapped over `settings.databases`, and an `impl`
  publishing `dsn`/`username`/`password`/`version` per database; verify a throwaway `mkPlan` over it
  reports empty diagnostics and one capability per database
- [ ] 2.3 Write `deployment/modules/postgresql/cluster.nix`: a root over the one member, re-exporting
  each capability by the database's own name from the member handle's resolved settings, and verify
  the plan carries `eu` and `us` as capabilities of the cluster entry
- [ ] 2.4 Write the two units in the leaf's `impl` - a root `oneShot` initialiser with
  `remainAfterExit`, and the long-running server as `user = "postgres"` with `after`/`requires`
  naming the initialiser - and verify the plan records both units and the reference
- [ ] 2.5 Write the initialising program as a package the entry declares in `closure`: initialise the
  data directory when empty, write the authentication file, create each database and owning role, set
  each role's password from its delivered file; verify it is idempotent by running it twice in a
  throwaway container or namespace and comparing the resulting data directory listing
- [ ] 2.6 Write `deployment/modules/app/` - the consumer module declaring one slot reading
  `dsn`, `username`, `password` and `version`, and one unit that writes and reads a row - and verify
  a throwaway plan resolves the read and records the password as a reference rather than a value
- [ ] 2.7 Write `deployment/machines.nix` (two machines at the cluster's static addresses) and
  `deployment/instances.nix` (the cluster instance with two databases and `exposes`, and two consumer
  instances each wiring one), and verify `applicable` is true and the diagnostics table is empty
- [ ] 2.8 Write `deployment/default.nix` taking `pkgs`, `planner` and `operator`, returning one
  deployment build, and verify `nix build .#planner-e2e-shared-postgres` produces a tree carrying
  `plan.json`, `manifest.json` and one artifact per entry
- [ ] 2.9 Verify the folder is discovered without editing the flake: `nix eval` the package name and
  confirm `testAnEndToEndFolderIsAddedWithoutEditingTheFlake` still passes

## 3. The machine layer

- [ ] 3.1 Declare the folder's stage through `delivery.cluster_stage` with two slots, `uefi = true`,
  its own additional space for the data directory and artifacts, and a preparation body that waits
  for `multi-user.target` and yields; verify `test_a_cut_carries_no_delivery`'s claim holds for this
  stage by asserting a freshly obtained machine holds no artifact
- [ ] 3.2 Add the build, value-source and apply fixtures: build in the pytest process, mint two
  passwords, write them under `<source>/<value entry key>/<file>` at 0600, apply with
  `planner apply --values` through `Cluster.run`; verify the step log names two value writes and
  three activations
- [ ] 3.3 Verify the apply order: the cluster is activated before either consumer, read off the
  recorded step lines

## 4. The assertions

- [ ] 4.1 `test_two_instances_take_one_database_each`: the plan carries three entries, each
  consumer's unit carries its own `dsn` and not the other's
- [ ] 4.2 `test_a_consumer_on_another_machine_reads_over_the_address_the_plan_recorded`: the far
  consumer's record names the planned address and port, and the row it wrote is readable
- [ ] 4.3 `test_one_process_is_behind_both_capabilities`: one `MainPID` for the server, both
  databases answered by it, and the initialiser reported as an exited one-shot
- [ ] 4.4 `test_a_credential_of_one_capability_is_refused_by_the_other`: presenting the `eu`
  credential to the `us` database is refused by the server, with the server's own message
- [ ] 4.5 `test_a_consumers_machine_holds_its_own_credential_only` and
  `test_a_working_consumer_is_outside_one_delivery_set`: each machine holds its own value file and
  the other's path does not exist, and each value's `delivery`/`deliveryDerivedFrom` name the
  provider's machine and one consumer's
- [ ] 4.6 `test_data_written_before_a_restart_is_readable_after_it`: restart the long-running unit,
  read the row back, and confirm the initialiser's start timestamp did not move
- [ ] 4.7 Verify no password appears in the build tree, in `plan.json`, or in any machine's store:
  grep the built farm and `/nix/store` on both machines
- [ ] 4.8 Verify each test is one ssh command reporting `key=value` lines, and that the whole folder
  runs without the guest's ssh socket refusing a connection: `nix run .#planner-e2e -- shared-postgres`

## 5. Documents and the tooling account

- [ ] 5.1 Add the folder's invariants to `CLAUDE.md`: why the server takes flags rather than a
  configuration file, why the initialising unit is the only reader of the password, why the account
  lives in the image and what it costs, and which of the four following changes removes each reason
- [ ] 5.2 Verify `tests/e2e/shared-postgres` is picked up by the treefmt mypy run whose module list
  is read from the directory, and that `nix build .#checks.x86_64-linux.treefmt` passes
- [ ] 5.3 Run the whole end-to-end layer once and verify no other folder regressed from the image
  change: `nix run .#planner-e2e`
