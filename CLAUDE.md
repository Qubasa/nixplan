This file holds project invariants, if you encounter a project invariant that has not been written down yet,
please add it to this file. Also if you encounter bugs, you can add them here such that next time we won't make that mistake again.
Keep it concise and human readable please.

Commit `c6fcb62` deleted every comment in the tree. The load-bearing ones are back at their own
constructs, shortened. This file is the index of the same invariants, so a rule can be found
without reading the code first.

## Purity and totality

- `lib/` never raises. Every check returns a diagnostics row, and evaluation stays total: one
  malformed declaration becomes a row and the rest is still read.
- `throw`, `abort`, `assert`, `.check ` and `korora.check` MUST NOT appear in `lib/*.nix`.
  `tests/unit/diagnostics.nix` scans the source text for them. It drops lines whose first
  non-space character is `#`, so prose may name a raising call, but a trailing comment on a line
  of code counts as code and fails the scan.
- korora's `verify` is the only entry point the library uses. `check` raises.
- `builtins.tryEval` catches a `throw` and a failed `assert`. It catches neither an abort nor a
  missing attribute, and both are documented as propagating. A missing attribute inside `lib/` is
  a bug that fails the suite loudly.
- `mkPlan` realises nothing: no derivation, no filesystem read, no network, and every store path
  in a plan is a literal string.
- `storeDir` is an argument. Never write `/nix/store` into `lib/`.
- `util.shortHash` discards string context on purpose: `hashString` refuses a context-carrying
  string, and a plan of a real deployment has to stay keyable. `util.uniqueStrings` keeps context,
  because a closure root's context is what lets a consumer copy the bytes.
- `image/` and `flakelet/` do the opposite and raise. A fact the entry does not record is a
  refusal naming the entry and the field, never a default. Every refusal there is a condition
  `mkPlan` also reports as a row.

## Diagnostics

- A row is a value a caller returns beside its result. No accumulator, no ambient list.
- Table order is identifier, then subject, then message, so two evaluations of one input render
  the same bytes. `fixtures/minimal-typed-edge/plan/diagnostics.txt` is compared against that.
- A subject is a plan key, a path relative to the deployment root, or an issue identifier. An
  absolute path is refused, because a rendered table would differ between checkouts. A message and
  a resolution keep their absolute paths on purpose: they name the file to edit.
- The same fact produced twice is one row. `dedup` keeps the first.

## Keys and identity

- An entry key is structural: placement decides it, never units. Two instances that wire each
  other would otherwise each need the other's units to know its own key.
- A plan key is `<instance>:<service>@<machine>`, and a keyed form appends `@<hash>`. Split at the
  last `@`.
- A generated value is an entry of its own: `<instance>:vars/<generator>` for `per = "instance"`,
  `<instance>:vars/<generator>@<machine>` for `per = "placement"`. A value delivered to a machine
  that runs none of the services reading it has no unit entry to live in.
- The delivery set is deliberately not in a value's key. A machine joining because a new consumer
  declared a read does not change the value, and re-keying it would ask for a regeneration of
  bytes that are still correct.
- `varsState` is keyed by the value's entry, not by machine: one value has one answer about
  whether it exists however many machines receive it.
- An image's version digest is deliberately not the entry key. A configuration file's content
  moves the key and never enters the image, so keying the image on it would rebuild equal bytes.

## Interfaces, composition, reads

- An interface is identified by the value an author imported. `name` is a label for row text; two
  interfaces in two files may share one. The `interfaces` argument is attribution, never a
  registry: an interface absent from it is still an interface.
- A root keys each member's settings under that member's own name, including when it owns exactly
  one member, and forwards nothing.
- Two instances wiring each other is not a cycle: a capability's exports are a function of module
  and settings, never of a wire. Do not add cycle detection.
- A refused read leaves the slot absent from `results` - not `null`, not `{}`. `or [ ]` cannot be
  written, so it cannot silently succeed.
- A unit reference (`after`, `requires`) is checked against the units the module declared itself.
- The delivery set of a generated value comes from the owner's placements plus the machine of
  every entry that declared a read of an export backed by one of its files. Nothing else enters
  it: not the value; not the interface; not what `impl` interpolates. A routable secret is bounded
  by nobody, so a declared read is the only thing that widens the set. An omitted read is the only
  thing that narrows it.
- Every value entry carries `delivery` and `deliveryDerivedFrom` whether or not either holds
  anything. A reader must not be able to mistake either field for an absence.
- A `deploy = false` generator's value still exists and its public files still travel in the plan.
  What is refused is opening one of its files on a machine. A unit or configuration file of the
  owner is `vars-not-deployed-opened`; a consumer's declared read is `slot-reads-undeployed-value`.
- A secret export must publish a generated file, never a bare value: `export-secret-not-a-reference`.
  A path in the plan is deliverable; bytes in the plan are a leak.

## Platform record

- The `is*` predicates are absent on purpose: each is a function of `parsed`, and recording them
  would put seventy-five derived booleans into every entry and every entry's key.
- `platform.gccNames` is written out by hand and must name every `gcc` field the pinned nixpkgs
  sets on any exposed platform. `tests/unit/platform.nix` crosses the list against every double.
- A declared microarchitecture replaces the whole `gcc` group rather than merging into it, because
  `elaborate` applies its arguments over `platforms.select`. That is what `crossSystem` does too.
- If the upstream guard in `tests/unit/platform.nix` goes red, upstream fixed `_withoutFunctions`.
  Rewrite the measurement in `design.md` D7. Do not delete the guard. Its evidence is the
  surviving function paths, not a failed `toJSON`: serialising a function aborts the suite.

## Realisers

- An image carries an empty file at every host path it is shown. The image root is a read-only
  squashfs, so a missing mount point is not a missing file at run time but a unit that cannot start
  (`Failed to create parent directories …: Read-only file system`, then `226/NAMESPACE`).
- An image carries no configuration bytes and no generated bytes. They arrive from the host at
  attach time, which keeps an image byte-identical across a configuration edit.
- `$root` in the attach script is `PORTABLE_PLANNER_ROOT`. It prefixes host state and never a
  store path.
- Every profile except `trusted` carries `DynamicUser=yes` and `PrivateUsers=yes`.
- A field missing from `systemdDirectives` in `image/read.nix` fails the build on purpose. An
  extension exists to add a field, so dropping one would make the extension a comment.
- flakelet decides `[Install]`, no plan field does. A long-running unit is wanted by
  `multi-user.target`; a scheduled unit's timer is wanted by `timers.target` and its service is
  wanted by nothing. An `[Install]` on that service runs the job once at deploy time and again on
  its schedule.
- The flakelet realiser refuses an entry shown a host path it would have to assemble - a
  configuration file - because it has no assemble step. A delivered generated file is its own
  source (`from == path`) and arrives before activation, so it is not refused.
- `flakelet/read.nix` restates two rules from flakelet's own `manager.rs`: `validate_name` and
  `validate_units`. `LOCKED_URL_PREFIX` in `tests/e2e/delivery.py` must match the prefix written
  there.

## Registration points

Each of these lists is hand-maintained. An addition that skips one fails a check, or worse, is
silently unobserved.

- A new unit suite goes in `suites` in `tests/default.nix`. That attrset is the only registration
  point, and its key names feed the coverage cross-walk. `coverage` is passed its own name too;
  that is not a cycle.
- A new top-level file or directory goes in `classOf` in `tests/unit/layers.nix`.
- A new `spec.md` anywhere goes in `accountable` or `excused` in `tests/unit/coverage.nix`.
- A new excluded construct goes in `lib/excluded.nix`, gets a test in `tests/unit/exclusions.nix`,
  and moves the row count that suite compares against the fixture README's table.
- `README.md` must keep naming `docs/`, `docs/README.md`, `lib/`, `image/`, `flakelet/`,
  `fixtures/`, `perf/`, `openspec/`, `tests/unit/`, `tests/e2e/` and the four documented commands.
  `tests/unit/layers.nix` asserts each literal.
- A `#### Scenario:` heading names its test by construction: `test_<snake_case>` under pytest,
  `test<CamelCase>` under nix-unit. A name present in both layers is a failure, not a bonus.
- `openspec/**` is exempt from the path scan: a record describes the repository as it was.

## Fixtures and goldens

- `fixtures/**` is excluded from the formatter. The suites evaluate it as committed and compare
  the golden plan with `==`, so a formatter would be editing a test's subject.
- Regenerate the golden with `nix eval --json .#planner.worked.plan | jq -S .`. Nothing in the
  evaluating layer can write to the working tree.
- `gamma` deliberately has not run its generator. That one absence is what the folder exercises:
  `set-entry-absent`, the incomplete render and the absence marker.
- `vault` carries no `backed-up` tag. A self-tagged server would put its own key into the set it
  authorizes, and the folder has no field to narrow a `reach = "all"` set.
- `borg-repo`'s port 22 is `fixed` rather than a default, because the `url` export is built from
  it. It is also the only `fixed` against `defaults` coverage in the fixture.
- `borgRepository` declares two exports so that provider keyset equality has something to be equal
  about. `quota` is not spare.
- Package defaults in `tests/unit/worked.nix` are literal store-path strings, because a fixture
  references a package and realises nothing. The `packages` argument exists so the image check can
  hand the same deployment real ones.
- A fixture carrying `...` or a hash that is not sixteen hex digits has stopped being evidence.

## Perf harness

- `perf/eval.nix` stays a plain Nix file. Making it a flake attribute folds flake evaluation into
  every gated counter and invalidates all nine recorded budgets at once.
- Fake store hashes are exactly 32 characters of Nix's base 32 (no `e`, `o`, `t`, `u`). Anything
  else stops `util.storePathsIn` recognising the path, and the closure check then exercises
  nothing while the suite stays green.
- `perf/mesh.nix` keeps one unit per peer, each ordered `after` the hub: that reference list
  crossed against the entry's own unit names is the quadratic path the fixture measures. Mesh also
  spells placements as explicit machine lists, where `perf/fleet.nix` uses tags.
- `perf/measure.sh` applies arguments with `--apply` because `nix eval --file` will not auto-call
  a function from `--argstr`.
- A budget is cost per plan entry, with a margin of 0.15 and a growth bound of 1.25 across sizes
  4, 16, 64, and 256.
- `tests/unit/perf.nix` plans size 64 rather than 256, and compares plans rather than deployments,
  because a deployment carries module functions and two functions are never equal in Nix.

## Tooling

- The vale wrapper in `treefmt.nix` turns any printed alert into exit 1, because vale itself exits
  0 for warning-level rules. Every `*.md` outside the excludes is linted, this file included.
- mypy runs once per directory of top-level modules, because that is what each import expects to
  be beside. `e2e-folders` is a label rather than a path, and its run happens from `tests/e2e` so
  that `import delivery` resolves the way it does under pytest.
- `ruff.toml` carries the rules because this repository owns no python package. `src` names the
  two import roots. The one devshell carries the interpreter `pytest-env.nix` builds, and
  `tests/e2e/runner.py` refuses a run where it and rookery's own disagree. `target-version` is a
  floor below that interpreter, not a record of it: it bounds what `UP` may rewrite to.
- `devshells.nix` is one shell and it names no built artifact. A store reference in its hook
  would make entering the checkout build the 3.7 GiB guest image, so the machine layer's
  variables arrive from `eval "$(planner-e2e-env)"` instead, which resolves
  `packages.planner-e2e-env-paths` by name when it is called. That file and the `planner-e2e`
  app are rendered from one attrset, `e2eArtifactPaths` in `flake-module.nix`: a variable added
  to one is added to both.
- `pytest.ini` keeps `-rs`: an artifact-backed suite skips itself when its `PLANNER_*` variable
  names no built path, and the skip reason is the only thing that tells that apart from a run with
  nothing to say.
- `workdirs/` is gitignored and holds git worktrees of this same tree, so it is invisible to the
  flake and to treefmt but not to pytest: `pytest.ini` names it in `norecursedirs`, or `pytest .`
  collects two files called `test_harness.py` and refuses the second as an import mismatch.
- `resolve_rookery` builds with `--refresh`. A branch reference resolves through nix's tarball
  TTL, so without it a run uses whatever rookery was fetched last, and one from before a nixpkgs
  bump is a different python minor version. That is reported as `PYTHON VERSION MISMATCH`, which
  reads like a real pin disagreement and is not one: check the resolved revision before changing
  `pytest-env.nix`.
- vulture and harper are deliberately not run. Vulture's only finding is `cmd` in the `Namespace`
  protocol of `tests/e2e/delivery.py`, which is an interface parameter name. Harper flags
  `realiser`, `flakelet` and `keyset`.
- Build the individual check. Never `nix flake check` the whole flake.

## End-to-end layer

- `tests/e2e/guest.nix` restates the invariants of rookery's `nix/base-image-configuration.nix`.
  rookery is resolved at run time rather than pinned as an input, so nothing checks the copy
  mechanically. Diff it when rookery moves.
- The guest image carries no plan artifact and no declared flakelet service, and its only
  credential is the image's own snakeoil key. Every entry arrives by delivery, otherwise the tests
  pass vacuously.
- TCP sshd is the delivery channel, and systemd's ssh generator derives the vsock control channel
  from it.
- `additionalSpace = "2048M"` is room for the two delivered artifacts and their closures.
- Machine addresses are rookery's static MAC-keyed dnsmasq leases, `10.0.0.(10 + i)`. They are not
  free-choice test values.
- A served unit binds `0.0.0.0` because it starts before the DHCP lease exists. The plan is held
  to the exported URL, which does use `target.address`.
- `--retry` in the probe exists for cross-machine boot ordering, not for flakiness.
- `schedule = "daily"` keeps the next elapse in the future for the whole run.
- The cluster's dnsmasq has no upstream, which is why the offline assertion holds.
- The pytest phases are session-scoped and order-dependent. The trailing `wait_until_succeeds`
  restores the wire for the phases after it.
- `systemctl is-active` exits 3 for an inactive unit, so that assertion uses `ssh` rather than
  `ssh_succeed`.
- The reboot is issued in the guest, not by QMP reset, because the claim is about the service
  manager bringing the machine down.
- In `portable-image`, `elsewhere` is aarch64 and never booted: it exists so an image can be built
  for a machine this host is not. The attaching entry is stated `strict` because enforcement is
  the claim under test.
- The runner's state directory prefix stays short. The virtiofs socket path
  `<state>/rookery/rookery-<pid>-<id>/vm-<i>/virtiofs-<tag>.sock` hits the 108-byte `AF_UNIX`
  limit, and virtiofsd then exits during startup with no useful error.

## Machine layer snapshots

- Each `tests/e2e/<folder>/` obtains its machines from one `@cluster_snapshot_fixture` stage,
  declared through `delivery.cluster_stage`. `@snapshot_fixture` is wrong here: a single-VM cut
  can only resume as slot 0, so two of them are both `10.0.0.10` with no route between them.
- A cut is RAM plus device state, so a snapshotted guest mounts **no virtiofs share**. Adding one
  back fails an assertion in `tests/e2e/guest.nix` rather than silently costing every cache hit.
- The credential is therefore the image's, not the run's: nixpkgs' `snakeOilEd25519*` from
  `nixos/tests/ssh-keys.nix`. One place defines both halves (the guest authorizes the public one
  and exports the private one as `e2eGuest.sshPrivateKey`), so the image and the run cannot drift.
  A store file is 0444 and ssh refuses a private key that readable, so `delivery.ssh_key` copies
  it to 0600 under the run's state root.
- A preparation body waits and yields. It reads no environment variable and runs no program, which
  is why the stage declares no `extra_env`, `extra_files` or `extra_tools`: rookery scrubs the
  environment and confines the body with Landlock, and an undeclared read or exec is an error.
  Nothing about the artifacts is in the cut's key, so editing a deployment leaves the boot cached.
- Never move a delivery, an activation or an attachment into a preparation. The body does not run
  on a cache hit, so the evidence those tests read would be a replay instead of an observation.
  `test_a_cut_carries_no_delivery` asserts the other half: a freshly obtained machine holds none.
- Wait to `multi-user.target`, not just `wait_for_ssh`. The vsock sshd answers before the login
  `PATH` exists, and a cut taken there resumes a half-booted guest.
- `uefi = true` on the stage: the guest boots systemd-boot from a GPT ESP while the decorator's
  own default is BIOS. Secure Boot and the TPM stay off. All three are part of the key.
- `tests/e2e/conftest.py`'s `state_root` is resolved by rookery **by name**; renaming it silently
  moves every run's state to rookery's own default root.
- The cut's key folds in the python environment rookery runs under, so a rookery interpreter bump
  re-keys every cut: the next run is cold. That is the intended failure mode, never a stale pass.
- Two folders never share one cut. The shape is part of the key (`vms=2;0:alpha:root;1:beta:root`
  against `vms=1;0:alpha:root`), a resume seeds one overlay and one RAM file per slot, and each
  slot's address is frozen in its own saved RAM. Sharing would also need one preparation function
  for both folders, and a session-scoped fixture instantiates once, so the folders would share a
  live cluster, which the attach tests and `test_a_cut_carries_no_delivery` deny.
- The cache never evicts. A moved key input orphans the old entry at about 2 GiB per machine, so
  editing a preparation body repeatedly fills a disk quietly. `rookery snapshot gc --all` is the
  only reclaim, and `rookery snapshot list` is how the accretion is noticed.

## Known bugs

- New files are invisible to the flake until `git add`, and the coverage cross-walk then reports
  the spec it cannot read rather than the file you forgot to stage.
- `-k wire` selects every `wired-pair` test: pytest matches the folder name too.
- Deleting a comment leaves the blank line that framed it, and `checks.treefmt` then fails on
  formatting rather than on prose. `nix fmt` after any comment removal.
- The comment strip cut five comments in half, leaving a mid-sentence fragment above the argument
  list of `lib/interface.nix`, `tests/unit/coverage.nix`, `tests/unit/worked.nix` and two fixture
  files. Removed. A blanket comment removal wants a check for a surviving `#` line.
- `mypy --strict` inside the `tests/e2e` treefmt root answers `INTERNAL ERROR` intermittently
  under mypy 2.1.0, in the build sandbox and with no file named. Rerun before believing a mypy
  failure; the same arguments in the devshell pass.
- `tests/unit/layers.nix` scans raw file text, comments included, and its
  `testAFileNamesAPathThatIsNotThere` catches stale path references that live in comments. A path
  written in a comment therefore has to resolve, and a foreign repository's file is named without
  a repository-rooted prefix.
