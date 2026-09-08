This file holds project invariants, if you encounter a project invariant that has not been written down yet,
please add it to this file. Also if you encounter bugs, you can add them here such that next time we won't make that mistake again.
Keep it concise and human readable please.

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
