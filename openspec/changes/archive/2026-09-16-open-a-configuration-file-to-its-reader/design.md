## Context

See `proposal.md` - Why. The shapes that decide the approach are the ones the tree already holds:

- **A value's file record is the precedent, in the same file.** `fileKeys` is
  `[ "secrecy" "owner" "group" "mode" ]` with `fileTypes` over the last three
  (`lib/module.nix:380-391`), `fileRecord` applies the defaults `root`, `root`, `0400` and records
  `stated` (`lib/module.nix:428-444`), and `fileKeyInput` removes the unstated ownership keys from
  what the key hashes (`lib/plan.nix:116-122`). Everything this change needs for a configuration
  file's record is that mechanism applied a second time.
- **A configuration file reaches a unit as a bind, not as a copy.**
  `BindReadOnlyPaths=${p.from}:${p.path}` (`image/read.nix:681-683`) over `fromOf`
  (`image/read.nix:300-310`): a `source` file's `from` is its own store path, a literal recipe's is
  the store object the reading assembled, and a `ref`-bearing recipe's is the staging path the
  attach script writes (`image/read.nix:222-224`). A bind shows the source's ownership and mode, so
  for two of the three dispositions the record's mode is decorative today. The empty mount point
  the image carries is created at the declared mode (`image/default.nix:99-105`) and the bind
  covers it.
- **The store carries exactly one record.** A store object is `root:root` at `0444`, which is why
  `delivery.ssh_key` copies a key out of the store to use it (`CLAUDE.md`, Machine layer
  snapshots). Nothing a realiser does to a store path changes that.
- **`renderUnit` is the one renderer.** `flakelet/read.nix:176-181` delegates to it and appends an
  `[Install]` section, so a directive added to `unitDirectives` is emitted by both realisers or by
  neither. A vocabulary field the table does not name is already a refusal with a recorded account
  (`image/read.nix:142-145,564,577-578`).
- **The claim index reads declarations, not paths.** `directoriesOf` walks `unit.extends` and keys
  a claim `"${field}/${name}"` (`lib/plan.nix:678-696`); the claims are collected in `placedEntry`
  (`lib/plan.nix:809-814`) and grouped twice in `entries`. A directory the vocabulary carries is
  another declaration site for the same claim, not another index.
- **`lib/` never raises and every check is a row** (`CLAUDE.md`, Purity and totality), and a fact
  the realisation statement carries is a row from `operator/read.nix` rather than from `mkPlan`.
  Which realiser meets an entry is stated beside the deployment, so "this realiser cannot install
  this record" is `operator/read.nix`'s row and `flakelet/read.nix`'s refusal, never `mkPlan`'s.

## Goals / Non-Goals

**Goals:**

- A module can say who reads a configuration file it declares, in the same words it says who reads
  a generated value's file.
- A record a realiser cannot honour is refused rather than silently widened, and a record it can
  honour is applied.
- A stateful service's setup - a directory at a mode, a file at an ownership, a step that runs once
  - is a declaration the plan carries rather than a shell script the plan carries the path of.
- Every deployment that states no ownership keeps its entry key, its artifact and its version
  digest.

**Non-Goals:**

- **No declarative database or role vocabulary.** The DDL in
  `tests/e2e/shared-postgres/deployment/init.sh` is application logic and stays a script; what
  leaves it is the provisioning the library can express. A `databases` vocabulary would be a policy
  construct in a planner that routes capabilities.
- **No `ExecStartPre`, no `Type=notify`, no socket units, no `Assert*` polarity.** Each is a
  separate decision with its own shape, exactly as
  `openspec/changes/hold-a-long-running-daemon/design.md:30-33` records for the same family. The
  bootstrap this change makes statable is a unit of its own ordered before the one that needs it,
  which is what the vocabulary already expresses with `after` and `requires`.
- **No account creation.** Nothing in a plan creates a user or a group (`CLAUDE.md`, End-to-end
  layer): a record naming `postgres` says which account may read the file, and which identity that
  resolves to is the machine's answer, which is why the atoms are names and not ids.
- **No writing of configuration bytes by the command.** `cli/` writes values and copies artifacts;
  a configuration file is a realiser's artifact. Moving it into `cli/remote.py` would give one file
  two writers.
- **No change to `reload`, to the `[Install]` decision or to how a secret reaches a unit.**

## Decisions

### The record is the value file record's, field for field

`configData.<path>` gains `owner` and `group` only: `mode` is already there and already required
(`config-file-mode-missing`, `lib/module.nix:928-936`). The types are `atoms.userName` and
`atoms.groupName`, the defaults are `root` and `root`, a value failing its type is
`config-file-ownership-malformed` and is not recorded, and the record every reader sees comes from
one function that applies the defaults, the way `fileRecord` does, so nothing downstream writes
`or "root"`.

The defaults differ from a value's `0400` because the fields differ in what they default around: a
value defaults closed because a generated value is a credential until it says otherwise, and a
configuration file's mode is stated by every declaration already, so there is no default to choose.

Alternatives rejected:

- **One `readableBy` knob naming an account.** It cannot express a group-readable file, which is
  exactly the shape `tests/e2e/shared-postgres/` needs for a credential-adjacent file and the shape
  `open-a-delivered-value-to-its-reader` already settled for a value's file.
- **A uid and a gid.** The plan is not told what a name resolves to on a machine
  (`lib/atoms.nix:88-92`), and two machines may resolve one name differently and legitimately.

### Only the ownership a declaration stated enters the key

`keyInput.configData` is the record itself (`lib/plan.nix:786-803`), so recording two more fields on
every file would re-key every entry that declares a configuration file, and with it every image
version digest and every flakelet generation. The projection that already exists for a value's
file - `fileKeyInput` over `ownershipKeys` (`lib/plan.nix:116-122`) - is reused: the key hashes the
record minus the ownership keys the declaration did not state. Because `mode` is required on a
configuration file, only `owner` and `group` are ever removed, and a file stating neither keys
exactly as it did.

What does move is the plan's own text: the record is what `pruned` publishes, so
`fixtures/minimal-typed-edge/plan/backup.json:576-588` gains two lines. That is the answer to the
golden question and it is deliberate - a reader must not be able to mistake an absent `owner` for
"the record does not say", which is the rule `CLAUDE.md` states for `delivery`, `files` and
`closure`. The regeneration is `nix eval --json .#debug.worked.plan | jq -S .`.

Alternative rejected: **recording the ownership only where stated.** It keeps the golden byte-equal
and makes every reader of the plan write `or "root"` three times, which is the thing `fileRecord`
exists to prevent.

### The record decides who installs the file

A configuration file is bound from the store where the record it states is the record a store
object carries - `root:root` at `0444` - and is written onto the host by the realiser otherwise.
The reading gains one derived field beside `disposition`, so the two questions stay separate: the
disposition says where the bytes come from, and the new field says who puts them at the path. A
`ref`-bearing recipe is host-written as it already is.

Under `image` this is the existing staging path (`image/default.nix:183-221`) applied to a larger
set: the candidate is created at `0600`, the ownership and then the mode are set, and it is moved
into place, so the guarantee `hold-every-stated-guarantee` made holds for the ownership too - the
file is never at the attaching login's umask and never wider than the record, and an interrupted
run leaves no widened file. Under `flakelet` it is a refusal, because that realiser runs no step on
a machine at all.

This is what makes the declared mode load-bearing for the first time, and it is the one behaviour
change that touches an existing declaration:
`fixtures/minimal-typed-edge/modules/borg-repo/server.nix:41` states `0600` over a literal recipe
and is bound world-readable today.

Alternatives rejected:

- **Honour the ownership only where the file is already host-written.** It leaves a stated mode
  silently widened for a `source` file and for a literal recipe, which is the defect, and it makes
  the record's meaning depend on the recipe's shape.
- **Carry the file in the artifact at the stated record.** The store cannot hold it: permissions
  are normalised, which is the fact `delivery.ssh_key` works around.
- **Let the command write it, the way it writes a value.** A value's bytes are the operator's and
  arrive beside the artifacts; a configuration file's bytes are the artifact's. Two writers of one
  file is the collision this tree reports as a row.

### The permission question joins the sites that already ask it, and gains no fourth predicate

`admits` (`lib/plan.nix:345-353`) is the predicate: an account is admitted by the owner bit where
it owns the file, by the group bit where the unit declares that group, and by the world bit
otherwise. The rule is asked at three sites today - `denialsOf` in `image/read.nix:375-407` against
the profile, `operator-entry-access-denied` in `operator/read.nix:334-348` mirroring it, and
`slot-reads-value-unreadable-by-user` in `lib/plan.nix:358-390` for a consumer's declared reads -
and `CLAUDE.md` warns that "A fourth site is a place to forget it" about a rule of the same family.

A configuration file joins the first two: `denialsOf` reads configuration files beside generated
ones, so a file only root may read is denied under a confining profile, and the operator's row
mirrors it with no edit because it maps the builder's own denial list. The third site is about
another entry's delivered value, which a configuration file is not, so the planner's answer for the
entry's own file is a second identifier over the same predicate:
`entry-config-file-unreadable-by-user`, produced beside `unreadableRows` where the units and the
configuration record are both in hand. One predicate, four sites, and the count is held by
`tests/unit/diagnostics.nix` crossing every refusal against the row that reports it.

The planner-side row is not redundant with the profile denial: a `flakelet` entry runs under the
`trusted` profile, which denies nothing (`flakelet/read.nix:47-50`), so without it a unit running
as `postgres` and shown a `root:root 0400` file is an `EACCES` at start with no row anywhere.

Alternative rejected: **one row identifier for both readings.** The subject and the resolution
differ - one names a slot and a provider's generator, the other names the entry's own declaration -
and a message that covered both would name neither.

### The directory kinds enter the vocabulary, not a realiser's table

The narrowest fix for the missing mode is three more extension fields
(`stateDirectoryMode` and its two siblings in `systemdDirectives`), and it is rejected: an
extension field is tagged with a backend, is invisible to a launchd target and is invisible to the
plan, so the directory would stay a fact only a systemd deployment can state and only a realiser
can read. The claim index already reads extension applications by name; what it cannot see is a
directory a module could not portably declare at all.

So the vocabulary carries `stateDirectory`, `runtimeDirectory` and `cacheDirectory` as lists of
relative names, and one mode per kind, because a service manager applies one mode per kind rather
than one per directory. A list keeps the single-directory case one line and the two-directory case
possible, and a name is relative because the kind decides the root.

`directoriesOf` then reads both sites, and a kind declared at both on one unit is
`unit-directory-declared-twice` rather than two directives a renderer has to reconcile.

**Open question, stated rather than assumed.** `openspec/changes/declare-service-state` proposes a
third declaration site for the same directory: `implKeys` gains `state.folders.<abs path>` with an
owner and a disposition, and its proposal already promises to refuse "a state folder plus a systemd
`stateDirectory` extension field on the same unit"
(`openspec/changes/declare-service-state/proposal.md:47-51`). That change is unimplemented, and the
two declarations are not the same fact - a state folder is an absolute path with a snapshot
disposition and dump/restore hooks, a unit directory is a name the service manager creates and owns
for a unit - but they will frequently name one directory on one machine. Whichever change lands
second owes the third leg of that refusal, and a later change may well subsume the unit directory
into the state declaration. This change does not decide that, and it does not add an absolute path
to the unit vocabulary, which is the part that would be genuinely incompatible.

### The condition is two polarities over an absolute path, and it is a condition

`startIfPathPresent` and `startIfPathAbsent`, each typed as an absolute path. A unit may state one
of each and both are ANDed, which is what a service manager does with them; one path in both is
`unit-condition-contradicts-itself`, a unit that never starts. The semantics are systemd's
`Condition*`: the unit is skipped and reported successful, so a unit ordered `after` and `requires`
a skipped bootstrap still starts. `Assert*`, which fails the unit instead, is left out: it is a
different fact and the one this change needs is the skip.

Alternatives rejected:

- **One field plus a polarity enum.** Two fields that may both be stated say more than one field
  and a tag, and the contradiction row is the same either way.
- **A `conditionPathExists` passthrough carrying systemd's `!` prefix.** The vocabulary is portable
  (`CLAUDE.md`, Realisers: the restart domain "is the planner's own domain, so a realiser maps it
  to its manager's spelling"), and a passthrough makes every plan a systemd plan and the negation a
  string nothing types.

### The folder splits its bootstrap from its DDL

`init.sh` does two things with two lifetimes: it initialises a cluster once (`init.sh:16-23`) and
it applies roles and databases on every apply (`init.sh:65-93`). A condition on the existing unit
would gate both and the second must not be gated - that is what makes a changed owner take effect.
So the module declares a `bootstrap` unit carrying `startIfPathAbsent = "${stateDir}/PG_VERSION"`
and the existing `init` unit is ordered after it. The shell test at `init.sh:16` goes, and the
`0700` data directory becomes `stateDirectory` plus `stateDirectoryMode`.

### The authentication file leaves the data directory

`hba_file` is a setting the module can write into the configuration file it already declares
(`tests/e2e/shared-postgres/deployment/modules/postgresql/databases.nix:105-126`), so the
authentication file does not have to live inside the data directory and therefore does not have to
be created by a step that already has the account. It becomes
`configData."/etc/${instance}-${member}/pg_hba.conf"`, derived from the pair an entry's plan key is
built from, like every other path of that folder. `initdb`'s generated file is then read by nothing,
which is why `--auth-local` and `--auth-host` (`init.sh:19-20`) go with it.

That closes the second configuration source the brief asks about: the private postmaster the DDL
step starts (`init.sh:35-39`) runs against `initdb`'s own configuration today, so
`--auth-host=scram-sha-256` and not the plan's `password_encryption` decides how a role's password
is hashed. The step starts it with `-c config_file=<the declared file>` beside its existing
`listen_addresses=` and `unix_socket_directories=`, so one declared file decides encryption and
authentication for both the private postmaster and the published one.

### Convergence is an ALTER, not a DROP

`init.sh:87-92` creates a database only where none exists, so a changed owner never reaches an
existing one. The step ensures the database exists and then states its owner
(`ALTER DATABASE … OWNER TO …`), and a role that owned it and is no longer named loses its login
(`ALTER ROLE … NOLOGIN`) rather than being dropped: a dropped role takes its owned objects with it
or fails, and the deployment's statement is about who may log in, not about deleting a machine's
history. The old role's login is what the folder can observe, which is the scenario.

### Escaping is doubling, at every site

An identifier is interpolated between double quotes and a literal between single quotes, so the
escape is doubling the respective quote at the site - `init.sh:74` already does it correctly for
the password and is the model. `owner` and `database` (`init.sh:79-90`) and `LABEL`
(`consume.sh:49`) get the same treatment.

The limit is stated rather than papered over: a quote-carrying **owner** is not exercised on a
machine, because that module's `dsn` export is built from the owner
(`…/modules/postgresql/databases.nix:84`) and is typed `url`, which a quote in the userinfo fails,
so the deployment earns an export row before any SQL runs. What the folder exercises on a machine is
a quote-carrying **label**, which is the interpolation a declaration can legally carry one in; the
identifier escaping is stated in the spec and held by the same doubling.

## Risks / Trade-offs

- **The golden plan moves.** → Two lines per configuration file record, no key, and the golden
  diagnostics table unchanged because the fixture's unit declares no account. Regeneration is one
  command and the task list says which bytes are expected to move.
- **Every entry with a configuration file gets one new image version digest.** → The digest is
  taken over the record of each shown path, and that record gains two fields, so it moves once for
  every such entry, which is one redelivery. What does not move is the rule: a literal recipe's
  bytes stay in the digest and in the image's closure, because a host-installed file is installed
  from the same store object the bind used to name, so "an edit to a literal file moves the image's
  version digest and an edit to a referenced one does not" is unchanged.
- **One existing declaration changes realisation.** → The fixture's `0600` authorized_keys file
  becomes host-installed under `image`, and would be refused under `flakelet`. The task list checks
  whether any suite reads that entry as a flakelet artifact and states the fixture's answer - the
  declaration is what it is, and the fixture exists to be evidence - rather than weakening the rule.
- **flakelet loses a case `hold-a-long-running-daemon` had just opened.** → Only for a record the
  store cannot carry, which is a file whose declaration asks for something that realiser cannot do
  at all. The row's resolution names both ways out: state the record the store carries, or state
  `image` for the entry. A deployment that wants a private configuration file under a store-backed
  realiser is asking for a step on the machine, which is what `image` is.
- **Eight new vocabulary fields is a large widening for one change.** → Six of them are one fact
  with three kinds and a mode each, and the seventh and eighth are one fact with two polarities.
  The alternative is three changes that each move `unitVocabulary`, `unitDirectives`, the row table
  and the same four documents.
- **Cost.** → The directory reading is per unit and the ownership is per file; both are linear in
  what an entry already declares, and the claim index gains a second source for one flat list. The
  gate is `nix build .#checks.x86_64-linux.planner-perf`, whose budgets are per plan entry with a
  margin of 0.15, and `perf/fleet.nix:107` and `perf/mesh.nix:137` declare one configuration file
  each and no directory.
- **A record naming an account no machine has.** → Unchanged from a value's file record: the plan
  states a name, the realiser installs at that name, and a machine that cannot resolve it fails the
  install with the name in the message. Nothing in a plan creates an account, and inventing one
  would be a realiser deciding a fact the deployment did not state.
