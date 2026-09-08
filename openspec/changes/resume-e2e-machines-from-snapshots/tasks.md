## 1. Baseline

- [x] 1.1 Record the cold baseline of the machine layer on the host the work is done on
  - `nix run .#planner-e2e -- -q --durations=15` at `bebb39e`: **76.36s, 29 passed**. Fixture setup
    before the first test of each folder: **13.50s** (`wired-pair`, two machines) and **14.90s**
    (`portable-image`, one machine) - **28.40s of boot** - against **5.06s** for the delivery setup
    that follows it.
- [x] 1.2 Record what the snapshot cache holds before any change
  - `rookery snapshot list` was empty: nothing in this repository had ever taken a cut.

## 2. The credential

- [x] 2.1 Bake the credential into `tests/e2e/guest.nix`
  - `sshKeys = import "${nixpkgs}/nixos/tests/ssh-keys.nix" pkgs`; root authorizes
    `snakeOilEd25519PublicKey` and the guest attrset exports `sshPrivateKey`.
  - `nix eval --raw .#packages.x86_64-linux.planner-e2e-guest.sshPrivateKey` →
    `/nix/store/q16kzrcgmsn8dhyi848mzqsxwhj6570r-privkey.snakeoil`, and
    `nix eval --json '...guest.config.users.users.root.openssh.authorizedKeys.keys'` →
    `["ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIDPQXmEVMVLmeFRyafKMVWgPDkv8/uRBTwmcEDatZzMD snakeoil"]`.
    The extra attributes survive `config.packages`, so the shell can read the key off the package.
- [x] 2.2 Delete the share plumbing from the guest
  - `fileSystems."/rookery"`, `cluster-authorized-key.service`, `rookery-virtiofs-report.service`
    and the `virtiofs` initrd module are gone; `nix build .#packages.x86_64-linux.planner-e2e-guest`
    succeeds, so every surviving assertion still holds.
- [x] 2.3 Replace the two assertions the deletion invalidates
  - One asserts password authentication is off **and** root's authorized keys are exactly the
    image's snakeoil key; the other that no `fileSystems` entry is `virtiofs`. Both messages name
    why a cut cannot carry a share. Observed live rather than by flipping them:
    `test_the_machines_are_reached_with_the_key_the_image_carries` and
    `test_no_host_directory_is_mounted_in_a_machine`.
- [x] 2.4 Export `PLANNER_E2E_SSH_KEY` from the runner app and the cluster shell
  - `nix develop .#planner-cluster` exports the store path, and every e2e run below connected with
    a 0600 copy of it. Without the variable both folders skip themselves, which is the intended
    refusal: the run no longer generates a key.

## 3. The harness

- [x] 3.1 Replace `delivery.keypair` with `delivery.ssh_key(root, source)`
  - `test_the_key_a_run_connects_with_is_a_private_copy_of_the_images` asserts the bytes and the
    0600 mode against a 0444 source. `nix build .#checks.x86_64-linux.planner-delivery` - 10 passed.
- [x] 3.2 Memoize `delivery.state_root()` and add `tests/e2e/conftest.py`
  - `@functools.cache`, so one process has one fallback directory and the key copy and the machine
    state share it. The fixture is named `state_root` because rookery resolves it by name.
- [x] 3.3 Replace `delivery.booted` with `cluster_stage` and `await_ready`
  - The factory states the posture once (`uefi=True`, `secure_boot=False`, `tpm=False`,
    `scope="session"`, no `extra_*`), and `await_ready` waits each slot to `wait_for_ssh` and then
    `multi-user.target` before the cluster's `wait_ready`/`wait_for_network`.
  - `nix fmt` needed one change to satisfy `mypy --strict` with rookery absent: the factory's return
    is annotated `Callable[[Preparation], Any]`, since an `Any` decorator is `untyped-decorator`.

## 4. The two folders

- [x] 4.1 Convert `tests/e2e/wired-pair/test_wired_pair.py`
  - Module-level `pytest.importorskip("rookery.snapshot")` and `allow_module_level` env skips
    replace the per-fixture skips; `booted` is the stage; `run` derives from `booted.cluster` and
    carries `resumed`. 27 passed.
- [x] 4.2 Convert `tests/e2e/portable-image/test_portable_image.py` the same way with one machine
  - 8 passed.
- [x] 4.3 Verify no existing test changed name or subject
  - The diff of both files touches imports, the module-level constants and the fixture wiring only;
    the six additions of task 5 are the only new `def test_` lines.

## 5. The new scenarios

- [x] 5.1 `test_a_prepared_cluster_is_cached_for_the_next_run`
  - Asserts one resume state across the machines (a whole-cluster cut is all-or-nothing) and that
    the stage's key names a usable group in the cache afterwards, via
    `delivery.cut_is_cached`. Passed cold and warm.
- [x] 5.2 `test_a_resumed_machine_is_usable_at_once` - `multi-user.target` active, an ordinary
  command resolvable on the login path, on every machine. Passed warm.
- [x] 5.3 `test_a_resumed_machine_holds_the_address_its_slot_was_cut_with` - each slot's name, its
  rookery-side address and the address the guest actually holds all equal the plan's. Passed warm.
- [x] 5.4 `test_the_machines_are_reached_with_the_key_the_image_carries` - the guest's
  `authorized_keys.d/root` equals `ssh-keygen -y` of the key the run holds, `sshd_config` refuses
  passwords, and an `ssh ... true` over the cluster LAN with that key succeeds. Passed.
- [x] 5.5 `test_no_host_directory_is_mounted_in_a_machine` - no `virtiofs` in `/proc/mounts`.
  Passed.
- [x] 5.6 `test_a_cut_carries_no_delivery` - a freshly obtained machine reports `[]` from
  `flakelet status --json` and holds none of the three artifacts. Passed warm, where it has
  something to say.

## 6. Cross-walk and documentation

- [x] 6.1 Add this change's two `spec.md` paths to `accountable` in `tests/unit/coverage.nix`
  - `nix build .#checks.x86_64-linux.planner-tests` - **242/242**, so every new scenario heading
    resolves to one of the six tests. Two failures on the way there were not this change's:
    `CLAUDE.md` was an unclassified top-level entry and `README.md` had stopped naming
    `docs/README.md` (both red at `bebb39e`, 240/242); `conftest.py` did need registering as shared
    harness in `tests/unit/layers.nix`. New files are invisible to the flake until `git add`, which
    is what the first coverage failure was really reporting.
- [x] 6.2 Update `docs/cluster.md`
  - New section "Where the machines come from" with the measured table, what the cut deliberately
    excludes, what re-keys it, and the three `rookery snapshot` commands; the credential paragraph,
    the assertion list, the variable table and the state-root note follow the change.
- [x] 6.3 Record the invariants in `CLAUDE.md`
  - No share in a snapshotted guest, where the credential is defined and why it is static, why the
    preparation declares no inputs, that a delivery must never move into one, the
    `multi-user.target` rule, the `uefi` posture, the by-name `state_root`, and that a rookery
    interpreter bump re-keys every cut.

## 7. Verification

- [x] 7.1 Cold then warm, recorded against the task 1.1 baseline
  - Under rookery at python3.14 (`7cfnxxlk…`), 35 tests each time:

    |                | total | wired-pair setup | portable-image setup |
    | --- | --- | --- | --- |
    | baseline (1.1) | 76.36s | 13.50s | 14.90s |
    | cold           | 80.87s | 11.74s | 11.29s |
    | warm           | 60.91s | **1.41s** | **2.74s** |

  - Obtaining the machines drops from 28.40s to **4.15s** while the suite grew by six tests. The
    cold run is dearer than the baseline because it also writes the cuts, which is stated in the
    docs so a first run is not read as a regression.
- [x] 7.2 Verify one selected test is now cheap
  - `nix run .#planner-e2e portable-image -q -k confinement`: **4.20s** warm, twice in a row, and
    `nix develop .#planner-cluster --command pytest … -k confinement` reports `1 passed, 7
    deselected in 3.33s`. The same by-hand selection was **16.06s** in the documentation before
    this change. `-k wire` is not usable for this measurement: pytest matches the folder name, so it
    selects all 27 `wired-pair` tests.
- [x] 7.3 Verify a moved input is a miss, not a stale pass
  - Observed without arranging it: rookery's own nixpkgs bump moved its interpreter from 3.13 to
    3.14 mid-work, and the next run cold-prepared (setups back to 13.10s/14.99s) rather than
    resuming. `rookery snapshot explain <old> <new>` names the field:
    `interpreter cpython-3.13.15-final… → cpython-3.14.7-final…`. The cache now holds four
    entries, `{wired-pair, portable-image} × {3.13, 3.14}`, and `explain` shows the two folders'
    entries differing in `prep_closure` and `shape` (`vms=2;0:alpha:root;1:beta:root` against
    `vms=1;0:alpha:root`) and nothing else.
  - Two individual runs during the work missed where a hit was expected and re-prepared; that is
    `_evict_retry` discarding a seeded resume it could not establish, and it self-healed - every
    run after it hit (app 4.20s twice, by-hand 3.33s).
- [x] 7.4 Verify the whole gate
  - `nix build .#checks.x86_64-linux.planner-tests .#checks.x86_64-linux.planner-delivery` - both
    build (242/242 and 10 passed). `nix fmt` reports no change to any file this change touched; the
    one formatter failure is `shellcheck`'s `SC1091` on `.envrc` sourcing `.envrc.local`, which is
    red at `bebb39e` too. `nix run .#planner-e2e` - **35 passed**, cold and warm.
