## Why

`tests/e2e/shared-postgres/deployment/init.sh` is 93 lines of imperative provisioning for one
server. Roughly a third of it exists because three declarations are missing, and each absence is
visible in the library rather than in the script:

- **A configuration file's record carries a mode and no owner.** `configFileKeys` is
  `[ "mode" "reload" "source" "render" ]` (`lib/module.nix:90-95`). A generated value's file record
  in the same library carries `owner`, `group` and `mode` with defaults and a record of which of
  them the declaration stated (`lib/module.nix:380-391,428-444`), and `CLAUDE.md` states the rule
  for it: "A file record's `owner`, `group` and `mode` are one value's and never one machine's".
  Two file-writing channels in one library, one of which cannot say who reads the file. The
  consequence is `init.sh:25-31`: `pg_hba.conf` is written by a heredoc into a temporary and
  `install -m 0600`-ed by the unit's own account, because `configData` cannot name one. The same
  module declares its other configuration file declaratively
  (`tests/e2e/shared-postgres/deployment/modules/postgresql/databases.nix:105-126`), so the
  contrast is inside one module.
- **The record is not even honoured where it exists.** A configuration file reaches a unit as
  `BindReadOnlyPaths=<from>:<path>` (`image/read.nix:681-683`), and `from` is a store object for a
  `source` file and for a recipe of literals (`image/read.nix:300-310`). A store object is
  `root:root` at `0444` - `CLAUDE.md` records the consequence elsewhere, that "a store file is 0444
  and ssh refuses a private key that readable" - so a declaration stating `mode = "0600"` is bound
  world-readable and nothing says so. Only a `ref`-bearing recipe is written on the host, where
  `install -m ${file.mode}` does honour it (`image/default.nix:200-212`). The mode is therefore a
  fact the plan records, the key hashes, and no realiser applies for two of the three dispositions.
- **The three unit directory kinds carry a name and no mode.** `systemdDirectives` names
  `StateDirectory`, `RuntimeDirectory` and `CacheDirectory` and no `*Mode`
  (`image/read.nix:82-84`), and the directory itself is declared only through a backend extension a
  deployment writes for itself (`tests/e2e/shared-postgres/deployment/default.nix:51-62`).
  PostgreSQL refuses a data directory at systemd's default `0755`, so the folder declares no
  directory at all and hand-makes one: `init.sh:14` is `install -d -m 0700 "$PGDATA"`. The second
  cost is that the absence defeats a check that exists. `entry-unit-directory-shared`
  (`lib/plan.nix:657-665`) reads only what an extension application recorded
  (`lib/plan.nix:678-696` over `unit.extends`), so a directory nobody declares is claimed by
  nobody, and two entries sharing one data directory on one machine earn no row.
- **There is no first-boot guard.** `ConditionPathExists` and the whole `Condition*`/`Assert*`
  family are in neither directive table (`image/read.nix:76-94,101-116`), so "initialise once" is
  `init.sh:16`, `if [ ! -s "$PGDATA/PG_VERSION" ]`. It is the most common provisioning shape there
  is and it is unstatable.

The four are one question - what must a module be able to say for a stateful server's setup to be
a declaration - and the answer moves no bytes a deployment did not state: three record fields, six
directory fields, two condition fields, and one rule about who installs the file.

## What Changes

- **A configuration file's record states the account that may read it.** `configData.<path>` gains
  `owner` and `group`, typed as `atoms.userName` and `atoms.groupName`, defaulting to `root` and
  `root`, recorded on every file whether stated or not. Only the fields a declaration actually
  stated enter the entry's key, through the same projection a value's file record already uses
  (`fileKeyInput` and `ownershipKeys`, `lib/plan.nix:116-122`), so no entry that states no
  ownership re-keys. `mode` is unchanged and stays required (`config-file-mode-missing`,
  `lib/module.nix:928-936`).
- **The record is honoured by whoever puts the file at the path.** A file is bound from the store
  only where the record it states is the record a store object carries, `root:root` at `0444`.
  Anything else is a file the realiser writes on the host: `image` installs it at the stated
  ownership and mode from the same assembled store object, and `flakelet`, which runs no step on a
  machine, refuses it as `operator-entry-path-not-installable`, the way it already refuses a
  `ref`-bearing recipe.
- **A unit that cannot open a configuration file its own entry shows it is a row.**
  `entry-config-file-unreadable-by-user` is the twin of `slot-reads-value-unreadable-by-user`
  (`lib/plan.nix:358-390`) over the same `admits` predicate (`lib/plan.nix:345-353`), and a
  configuration file joins the profile comparison at the two sites that already make it:
  `denialsOf` (`image/read.nix:375-407`) and its mirror `operator-entry-access-denied`
  (`operator/read.nix:334-348`).
- **A unit may state the directories it is given and their modes.** The vocabulary gains
  `stateDirectory`, `runtimeDirectory` and `cacheDirectory` as lists of relative names, and
  `stateDirectoryMode`, `runtimeDirectoryMode` and `cacheDirectoryMode` as file modes. A mode with
  no directory of its kind is `unit-directory-mode-without-directory`, the shape
  `unit-restart-delay-without-policy` already has; one kind declared both in the vocabulary and in
  an extension application on one unit is `unit-directory-declared-twice`.
- **A directory a unit declares is the same claim however it was declared.** `directoriesOf`
  (`lib/plan.nix:678-696`) reads the vocabulary fields beside the extension applications, so the
  existing `entry-unit-directory-shared` warning sees a directory declared either way, and a claim
  keeps carrying the field it was recorded under.
- **A unit may state a path its start is conditional on.** `startIfPathPresent` and
  `startIfPathAbsent`, each an absolute path; a unit may state one of each, and one path in both is
  `unit-condition-contradicts-itself`. The planner's domain says which condition holds, not which
  directive a service manager spells it with, and the semantics are systemd's `Condition*`: a unit
  whose condition does not hold is skipped, not failed.
- **Both realisers render every new field, and a field no table names stays a build refusal.**
  `unitDirectives` (`image/read.nix:101-116`) gains eight entries and `systemdDirectives` gains
  none; `flakelet/read.nix:176-179` delegates, so a flakelet unit carries them by construction. A
  vocabulary field the table does not name is `accounts.unitFieldUnrendered`
  (`image/read.nix:142-145,564,577-578`), which stays a refusal with a recorded account, because an
  addition to the vocabulary that a realiser did not follow is the realiser's defect.
- **`tests/e2e/shared-postgres/` declares what it used to script.** The data directory and its
  `0700` become a `stateDirectory` and a `stateDirectoryMode`; the authentication file becomes a
  declared configuration file outside the data directory, reached by the `hba_file` setting in the
  configuration file the module already declares; the bootstrap becomes its own unit guarded by
  `startIfPathAbsent`, leaving the DDL unit to run on every apply. Two further defects of that
  folder go with it: the DDL is non-convergent (`init.sh:87-92` only ever `CREATE DATABASE`, so
  changing `eu.owner` at `tests/e2e/shared-postgres/deployment/instances.nix:13` leaves the
  database owned by the old role forever and that role keeps a valid login), and it interpolates
  identifiers into SQL unescaped (`init.sh:79-90` for `owner` and `database`, `consume.sh:49` for
  `LABEL`; only the password is escaped, correctly, at `init.sh:74`).

## Capabilities

### New Capabilities

<!-- none: the record, the vocabulary, both realisers and the folder all exist -->

### Modified Capabilities

- `planner/plan-artifact`: a configuration file's record states its owner and group, with the
  defaults and the stated-fields rule a value's file record already has, and a unit that cannot
  open a file its own entry shows it is a row.
- `planner/unit-vocabulary`: the vocabulary gains the three directory kinds, their three modes and
  the two condition paths, with the rows that refuse a mode without a directory, a kind declared
  twice and a condition that contradicts itself; and a directory a unit declares is a claim however
  it was declared.
- `realiser/portable-service-image`: a configuration file is installed at the record it states
  rather than bound from a store object that cannot carry it; the new unit fields are rendered; a
  configuration file only root may read joins the profile denial table.
- `realiser/flakelet-artifact`: the rule for a host path this realiser can show gains its second
  half - the record, beside the bytes - and a record the artifact cannot install is refused with the
  row that reports it first.
- `delivery/real-cluster`: `tests/e2e/shared-postgres/` declares its data directory, its
  authentication file and its bootstrap guard, converges the roles and databases the deployment
  names, and escapes what it interpolates into SQL.

No `operator/deployment-build` delta is written: "The realiser of an entry is stated, never
inferred" and "An inapplicable deployment is not built"
(`openspec/changes/report-every-refusal-as-a-row/specs/operator/deployment-build/spec.md:227,275`)
already require every refusal of the stated realiser to be a row of the table, and the new row is
one of those. Its identifier is named in the flakelet delta and registered in `docs/diagnostics.md`.

## Impact

- `lib/module.nix`: `configFileKeys` gains `owner` and `group`; the configuration file reading
  gains their types, `config-file-ownership-malformed` and the record function that applies the
  defaults and records which fields were stated, written the way `fileRecord`
  (`lib/module.nix:428-444`) is; `unitVocabulary` gains eight fields; `readUnits` gains the three
  new unit rows.
- `lib/atoms.nix`: `directoryName` and `absolutePath`, so a relative condition path and an absolute
  directory name are `unit-field-type-mismatch` rather than three more identifiers.
- `lib/plan.nix`: `configDataRecord` (`:415-454`) records the ownership on both its branches; the
  key projection removes the ownership keys the declaration did not state, reusing `fileKeyInput`
  and `ownershipKeys` (`:116-122`); `entry-config-file-unreadable-by-user` beside `unreadableRows`
  (`:358-390`) over the existing `admits`; `directoriesOf` (`:678-696`) reads the vocabulary fields
  beside `unit.extends`.
- `image/read.nix`: `configFilesOf` (`:252-261`) projects the ownership; a derived `install` field
  beside `disposition` says whether a file is bound from the store or written on the host;
  `denialsOf` (`:375-407`) reads configuration files beside generated ones; `unitDirectives` gains
  the eight entries; `renderUnit` (`:661-718`) emits them.
- `image/default.nix`: the assemble set (`:183-221`) is the host-written files rather than the
  `ref`-bearing recipes alone, and the install carries the ownership before the file is moved into
  place, keeping the guarantee `hold-every-stated-guarantee` made: the file is never at the
  attaching login's umask and never wider than the record.
- `flakelet/read.nix`: `pathRule` and a second predicate over the record (`:119-133`), the refusal
  and its account (`:39-43,160-174`).
- `operator/read.nix`: the new row beside `operator-entry-path-not-assembled` (`:295-304`) over a
  list built from the flakelet reader's own predicate, so nothing about the rule is restated there.
- `fixtures/minimal-typed-edge/plan/backup.json`: the one configuration file's record
  (`:576-588`) gains `"owner": "root"` and `"group": "root"`. No key moves, and the golden
  diagnostics table does not move: that unit declares no account
  (`fixtures/minimal-typed-edge/modules/borg-repo/server.nix:54-56`), so `admits` admits it. That
  file states `mode = "0600"` (`:41`), so it becomes a host-written file, which is the one existing
  declaration in the tree this change moves; every other configuration file under `tests/e2e/` and
  `perf/` states `0444`.
- `tests/unit/{module,units,plan,image,flakelet,operator,diagnostics}.nix`, `tests/unit/coverage.nix`,
  `docs/{authoring,plan,flakelet,diagnostics}.md`, `CLAUDE.md`.
- `tests/e2e/shared-postgres/`: `init.sh` loses its directory creation, its heredoc and its shell
  guard and gains convergence and escaping; `deployment/modules/postgresql/databases.nix` gains the
  declarations; `deployment/default.nix` gains a second build with a changed owner, the way
  `portable-image` builds the same deployment twice.
