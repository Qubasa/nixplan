## 1. Record what exists

- [ ] 1.1 Record, before any edit: the bytes of `fixtures/minimal-typed-edge/plan/backup.json` and
  `.../diagnostics.txt`, the key of `vault-repo:server@vault`
  (`sha256-a090a60d56683eba`, `backup.json:592`), the image version digest and rendered unit file of
  one `tests/e2e/portable-image` entry, and the artifact content of one `tests/e2e/wired-pair`
  entry. Every "unchanged" claim below is compared against these bytes rather than against a
  description.
- [ ] 1.2 Confirm by a throwaway `mkPlan` and a throwaway image build that a configuration file
  declaring `mode = "0600"` over a literal recipe is bound from a `0444` store object today, so the
  defect this change fixes is observed rather than inferred. The subject is
  `fixtures/minimal-typed-edge/modules/borg-repo/server.nix:40-52`.
- [ ] 1.3 Confirm whether any check reads the worked fixture's `vault-repo:server@vault` entry as a
  flakelet artifact, since 1.2's file becomes a host-installed file and flakelet refuses one. Record
  the answer here; if one does, it is that check that states `image` for the entry, not this rule
  that narrows.

## 2. The configuration file's record

- [ ] 2.1 Add `owner` and `group` to `configFileKeys` (`lib/module.nix:90-95`) with types
  `atoms.userName` and `atoms.groupName`, and add the record function that applies the defaults
  `root` and `root` and records which of the two the declaration stated, written the way
  `fileRecord` is (`lib/module.nix:428-444`). Verify by a throwaway plan that a file stating both
  records both, a file stating neither records the defaults, and the stated list holds exactly what
  was declared.
- [ ] 2.2 Add `config-file-ownership-malformed` for a value failing either type, mirroring
  `vars-file-ownership-malformed` (`lib/module.nix:415-426`). Verify the row names the module, the
  file and the type, and that the record carries the default rather than the failing value.
- [ ] 2.3 Record the ownership on both branches of `configDataRecord` (`lib/plan.nix:415-454`),
  including the branch that records `computed = false`, so a reader cannot mistake an incomplete
  render for a record that does not say. Verify against the worked fixture, whose one file takes
  that branch (`backup.json:576-588`).
- [ ] 2.4 Project the ownership out of the key where it was not stated, by reusing `fileKeyInput`
  and `ownershipKeys` (`lib/plan.nix:116-122`) for `keyInput.configData`
  (`lib/plan.nix:786-803`). Verify that the recorded key of `vault-repo:server@vault` from 1.1 is
  unchanged, and that adding `group = "borg"` to that file moves it.
- [ ] 2.5 Answer the golden question in the tree: regenerate with
  `nix eval --json .#debug.worked.plan | jq -S .` and verify the only difference against 1.1 is
  `"group": "root"` and `"owner": "root"` inside `configData."/srv/borg/.ssh/authorized_keys"`, that
  no `key` field moved anywhere in the file, and that `diagnostics.txt` is byte-identical - that
  unit declares no account (`server.nix:54-56`), so `admits` admits it.
- [ ] 2.6 Add `entry-config-file-unreadable-by-user` beside `unreadableRows`
  (`lib/plan.nix:358-390`) over the existing `admits` (`lib/plan.nix:345-353`), comparing each unit
  of the entry against each configuration file the entry declares. Verify with a throwaway
  deployment whose unit runs as `app` and whose file is `root:root 0400`: one error row naming the
  unit, the account, the path and the record, and no row when the file states `group = "app"` and a
  group-readable mode while the unit declares that group.

## 3. The unit vocabulary

- [ ] 3.1 Add `directoryName` and `absolutePath` to `lib/atoms.nix`, and verify by a throwaway
  korora `verify` that a relative name and an absolute path pass their own and fail the other, so a
  misplaced value is `unit-field-type-mismatch` and needs no identifier of its own.
- [ ] 3.2 Add `stateDirectory`, `runtimeDirectory`, `cacheDirectory` (lists of `directoryName`) and
  `stateDirectoryMode`, `runtimeDirectoryMode`, `cacheDirectoryMode` (`atoms.fileMode`) to
  `unitVocabulary` (`lib/module.nix:58-72`). Verify a throwaway plan records each on a unit that
  declares it and none on a unit that does not, and that the entry key moves when one is added.
- [ ] 3.3 Add `unit-directory-mode-without-directory`, the shape
  `unit-restart-delay-without-policy` already has. Verify the row names the module and the unit and
  that the mode is not recorded.
- [ ] 3.4 Add `startIfPathPresent` and `startIfPathAbsent` (`atoms.absolutePath`) and
  `unit-condition-contradicts-itself`. Verify one of each on one unit is recorded with no row, the
  same path in both produces the row and records neither, and a relative path is
  `unit-field-type-mismatch`.
- [ ] 3.5 Add `unit-directory-declared-twice` for one kind declared both in the vocabulary and in a
  backend extension application on one unit. Verify the row names the module, the unit and the kind,
  and that neither declaration is recorded.

## 4. The two realisers

- [ ] 4.1 Project `owner` and `group` in `configFilesOf` (`image/read.nix:252-261`) and derive one
  field beside `disposition` saying whether the file is bound from the store or installed on the
  host, the store's own record being `root:root` at `0444`. Verify `hostPathsOf`
  (`image/read.nix:312-335`) answers `from` as the store path for a file stating the store's record
  and as the staged path otherwise, for both `source` and literal dispositions.
- [ ] 4.2 Install the host-written files in the attach script (`image/default.nix:183-221`): the
  candidate is created closed, the ownership and then the mode are set, and it is moved into place,
  keeping the comparison that writes only where the bytes differ and re-applies the record either
  way. Verify by running the artifact's script under a `PORTABLE_PLANNER_ROOT` of a throwaway
  directory that the file lands `owner:group` at the declared mode, that a second run prints
  `nothing changed`, and that a run stopped between the two steps leaves no file readable by an
  account the record excludes.
- [ ] 4.3 Add the eight entries to `unitDirectives` (`image/read.nix:101-116`) and emit them in
  `renderUnit` (`image/read.nix:661-718`). Verify the rendered unit file of the entry recorded in
  1.1 is byte-identical when it declares none of them, and that a unit declaring a state directory,
  its mode and a condition renders all three directives.
- [ ] 4.4 Verify a vocabulary field the table does not name still fails the build with
  `accounts.unitFieldUnrendered` and its recorded account
  (`image/read.nix:142-145,564,577-578`), by removing one mapping in a throwaway edit.
- [ ] 4.5 Read configuration files beside generated files in `denialsOf`
  (`image/read.nix:375-407`). Verify a `strict` entry whose unit runs unconfined of a `root:root
  0400` configuration file is denied naming the path, the record and the account; that the same file
  at a group the unit declares is not; and that `operator-entry-access-denied`
  (`operator/read.nix:334-348`) reports it with no edit in that file, because it maps the builder's
  own denial list.
- [ ] 4.6 Narrow `acceptsHostPath` and `pathRule` in `flakelet/read.nix:119-133` with the record
  half, add the refusal and its account (`flakelet/read.nix:39-43,160-174`), and add
  `operator-entry-path-not-installable` to `operator/read.nix` beside
  `operator-entry-path-not-assembled` (`:295-304`) over a list built from the flakelet reader's own
  predicate. Verify a flakelet entry declaring a file at `postgres:postgres 0440` is inapplicable
  with that row, builds its plan and both tables and no artifact, that the row's resolution names
  both ways out, and that `tests/unit/diagnostics.nix` still crosses every refusal against a row.
- [ ] 4.7 Verify a flakelet unit carries the new directives with no second mapping table in
  `flakelet/read.nix`, and that the artifact of the entry recorded in 1.1 is byte-identical when its
  units declare none of the new fields.

## 5. The collision index

- [ ] 5.1 Have `directoriesOf` (`lib/plan.nix:678-696`) read the three vocabulary fields beside the
  extension applications, keeping the `"${field}/${name}"` claim so a state directory and a runtime
  directory of one name stay two claims. Verify the claims of the entry
  `tests/unit/plan.nix:283-301` builds through an extension are unchanged, and that the same
  directory declared through the vocabulary produces the same claim.
- [ ] 5.2 Verify `entry-unit-directory-shared` (`lib/plan.nix:657-665`) fires for two entries of one
  machine declaring one runtime directory through the vocabulary, with the same severity, subject
  and message shape it has for an extension-declared one, and that the deployment still builds.
- [ ] 5.3 Verify no new claim collides in the existing fixtures: `perf/fleet.nix` and
  `perf/mesh.nix` declare no directory, and the worked fixture declares none, so the golden plan and
  the golden diagnostics table from 1.1 stay byte-equal.

## 6. Scenarios, registration and documents

- [ ] 6.1 Add the `planner/plan-artifact` scenarios as `testAConfigurationFileStatingAnOwnerAndAGroup`,
  `testAConfigurationFileStatingNoOwnership`, `testOnlyTheOwnershipStatedEntersTheKey`,
  `testAnOwnershipThatFailsItsType`, `testAUnitThatCannotOpenItsOwnConfigurationFile`,
  `testAUnitAdmittedByTheFilesGroup` and `testAUnitThatDeclaresNoAccount` to `tests/unit/plan.nix`,
  and verify each is red against the pre-change tree and green after groups 2 and 3.
- [ ] 6.2 Add the `planner/unit-vocabulary` scenarios as
  `testAUnitDeclaringAStateDirectoryAndItsMode`, `testADirectoryModeWithNoDirectoryOfItsKind`,
  `testADirectoryNameThatIsNotRelative`, `testAUnitDeclaringNoDirectoryKeepsItsKey`,
  `testOneDirectoryKindDeclaredTwice`, `testAUnitThatStartsOnlyWhileAPathIsMissing`,
  `testAUnitThatStartsOnlyOnceAPathExists`, `testAConditionThatContradictsItself` and
  `testAConditionPathThatIsNotAbsolute` to `tests/unit/units.nix`, and
  `testTwoEntriesSharingADirectoryDeclaredThroughTheVocabulary` and
  `testAStateDirectoryAndARuntimeDirectoryOfOneName` to `tests/unit/plan.nix`, where the claim index
  is exercised.
- [ ] 6.3 Add the `realiser/portable-service-image` scenarios as
  `testAUnitDeclaringADirectoryRendersBothDirectives`, `testAConditionRenderedWithThePolarityStated`,
  `testAVocabularyFieldWithNoDirectiveFailsTheBuild`,
  `testAConfigurationFileOnlyRootMayReadUnderAConfiningProfile`,
  `testAGroupReadableConfigurationFileUnderAConfiningProfile`,
  `testAConfigurationFileUnderTheUnconfinedProfile`,
  `testAFileWhoseRecordTheStoreCarriesIsShownFromTheStore`,
  `testAFileStatingAnOwnershipIsInstalledOnTheHost`,
  `testAFileStatingAModeTheStoreCannotCarryIsInstalledOnTheHost`,
  `testAReferencedRecipeIsInstalledAtTheRecordItStates` and
  `testAnInterruptedInstallLeavesNoFileAtAWiderRecord` to `tests/unit/image.nix`.
- [ ] 6.4 Add the `realiser/flakelet-artifact` scenarios as
  `testAFlakeletUnitCarriesTheDirectoryAndConditionDirectives`,
  `testAUnitDeclaringNoneOfTheNewFieldsIsByteIdentical`,
  `testAnEntryShownAConfigurationFileStatingAnOwnership`,
  `testAnEntryShownAFileAtAModeNoStoreObjectHas`,
  `testAnEntryShownAFileWhoseRecordTheStoreCarries` and
  `testADeliveredFilesRecordIsNotThisRealisersToInstall` to `tests/unit/flakelet.nix`, and the
  deployment-build half of 4.6 to `tests/unit/operator.nix`.
- [ ] 6.5 Move this change's five spec files from `excused` to `accountable` in
  `tests/unit/coverage.nix` - the excuse "an unimplemented change" expires the moment a task here is
  ticked - and verify `testEverySpecificationIsClassified`, the excuse-staleness check and the
  scenario cross-walk are green: every scenario heading must find the identifier it derives, and no
  name may exist in both the unit and the end-to-end layer.
- [ ] 6.6 Add the six new identifiers to `docs/diagnostics.md` where the row tables live:
  `config-file-ownership-malformed`, `unit-directory-mode-without-directory`,
  `unit-directory-declared-twice` and `unit-condition-contradicts-itself` under "Units, extensions
  and configuration files" (`docs/diagnostics.md:160-183`),
  `entry-config-file-unreadable-by-user` under "What two entries of one machine both claim" or the
  entry rows beside it, and `operator-entry-path-not-installable` under "Every row the deployment
  build can produce". Update `docs/authoring.md` (the vocabulary table, the configuration file
  record, the three new unit rows), `docs/plan.md` (the record's two fields and the stated-fields
  rule) and `docs/flakelet.md` (which host paths are accepted and why). Verify
  `nix build .#checks.x86_64-linux.treefmt` passes, vale included.
- [ ] 6.7 Record the invariants in `CLAUDE.md` beside the neighbouring rules: under "Interfaces,
  composition, reads", that a configuration file's record carries the same three fields a value's
  file record does, with the same stated-fields rule and its own defaults; under "Diagnostics", that
  the readability comparison is one predicate asked at the sites that hold the facts and which row
  each site produces; under "Realisers", that a configuration file is bound from the store only
  where the record it states is the store's and is installed on the host otherwise, that the
  flakelet refusal now has a record half, and that the unit vocabulary carries the three directory
  kinds, their modes and the two condition polarities with the reason the domain is the planner's;
  and under "Known bugs" or "Registration points" as it fits, that a directory is claimed whether
  declared through the vocabulary or through an extension. Name the open question about
  `openspec/changes/declare-service-state`'s third declaration site where the directory rule is
  recorded.

## 7. The end-to-end folder

- [ ] 7.1 Declare the data directory in
  `tests/e2e/shared-postgres/deployment/modules/postgresql/databases.nix` as a state directory of
  the kind the service manager creates, named from `${instance}-${member}` as every path of that
  folder is, with the mode the server requires, and delete `install -d -m 0700 "$PGDATA"` from
  `tests/e2e/shared-postgres/deployment/init.sh:14`. Verify
  `test_the_init_step_creates_no_directory_of_its_own` and
  `test_the_data_directory_arrives_at_the_mode_the_server_requires`, each reading the path and the
  mode off the plan and the machine rather than off a constant.
- [ ] 7.2 Declare the authentication file as a configuration file at a path derived from the same
  pair, point the declared configuration file at it with `hba_file`, and delete the heredoc and the
  `install -m 0600` (`init.sh:25-31`). The record states the ownership and mode a store object
  carries, because this folder's entries are realised by the store-backed realiser. Verify
  `test_the_authentication_file_arrives_as_a_declared_file`, and verify the deployment still states
  no host path of its own (`tests/unit/layers.nix`, `testADeploymentStatesAHostPath`).
- [ ] 7.3 Split the bootstrap into its own unit carrying `startIfPathAbsent` of the file that proves
  the cluster exists, order the DDL unit after it, and delete the shell guard (`init.sh:16`). Verify
  `test_the_bootstrap_runs_once_and_is_skipped_after` over two applies of one machine.
- [ ] 7.4 Start the private postmaster against the declared configuration file (`init.sh:35-39`) and
  drop `--auth-local` and `--auth-host` from the initialisation (`init.sh:19-20`), so one file
  decides authentication and hashing. Verify `test_one_file_decides_how_a_password_is_hashed` by
  reading the stored verifier's method and the file the running server names.
- [ ] 7.5 Make the DDL convergent (`init.sh:87-92`): ensure the database exists, then state its
  owner, and take the login from a role that owned it and is no longer named, without dropping it.
  Add a second build to `deployment/default.nix` with a changed `eu.owner`, the way `portable-image`
  builds the same deployment twice, and verify
  `test_a_changed_database_owner_takes_effect_on_a_second_apply` and
  `test_a_role_the_deployment_no_longer_names_cannot_log_in`.
- [ ] 7.6 Escape every interpolation at its site: the owner and the database as identifiers
  (`init.sh:79-90`) and the label as a literal (`consume.sh:49`), the way the password already is
  (`init.sh:74`). Give one instance a label carrying a quote and verify
  `test_an_identifier_carrying_a_quote_is_not_sql` and the folder's existing label assertions, which
  move with it.
- [ ] 7.7 Verify the folder end to end with `nix run .#planner-e2e shared-postgres`, and check
  whether its stage's `disk_gib` still covers two builds of the deployment; if it moves, it re-keys
  this folder's cut and no other, and `rookery snapshot gc --all` is the reclaim.

## 8. Verification

- [ ] 8.1 Run `nix build .#checks.x86_64-linux.planner-tests` and verify every suite is green,
  including the fixture's `diagnostics.txt` byte comparison and the golden plan's single expected
  difference from 2.5.
- [ ] 8.2 Run `nix build .#checks.x86_64-linux.planner-perf` and verify the nine budgets hold:
  evaluation cost moves because every unit is read for six more fields and every configuration file
  for two, so record the measured cost per entry for sizes 64 and 256 and compare against the same
  measurement of the base commit rather than against the recorded budget alone.
- [ ] 8.3 Run `nix run .#planner-e2e -- wired-pair portable-image` and verify neither folder
  regressed: `portable-image` is the one that asserts an installed configuration file on a machine,
  and `wired-pair` is the one that declares none.
