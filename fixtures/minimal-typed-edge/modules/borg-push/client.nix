{
  borgbackup,
  openssh,
  sshHostIdentity,
  borgRepository,
}:

{ settings, ... }:
{
  platforms = [
    "x86_64-linux"
    "aarch64-linux"
    "aarch64-darwin"
  ];

  # One keypair per placement, which is what a per-machine generator already is
  # in the target. This folder writes no `per` key: `per` is the field that
  # replaces `share = true` and it belongs to the change that can also deliver a
  # secret to a consumer, which this one cannot. The default here means the same
  # thing clan-core's default means, one value for the machine it was generated
  # on, and the fleet-wide case is simply not spellable in this folder.
  #
  # `secrecy` on a file rather than `secret = true` on a file. Same distinction
  # the target already holds — `secret` at `modules/clan/vars/settings-opts.nix:53`
  # and `deploy` at `nixosModules/clanCore/vars/interface.nix:81` — and the same
  # spelling as the export bound in ../../interfaces/exports.nix, one concept.
  #
  # A note on a gap this closes by subtraction rather than by answering it.
  # `universe-3wr` is open because a `vars` file carries `secrecy` and carries no
  # `locality` while an export carries both — an asymmetry between two
  # declarations of the same kind of thing. Here no export carries a locality
  # either, so the asymmetry is gone. What is NOT answered is the question
  # underneath it: which machine holds the bytes is still decided by the
  # generator's cardinality and by `deploy`, and neither of those is a locality.
  vars.hostKey = {
    files."ssh_host_ed25519_key" = {
      secrecy = "secret";
    };
    files."ssh_host_ed25519_key.pub" = {
      secrecy = "public";
    };
  };

  # The single-valued read. `reach = "one"` is what an omitted field means, and
  # it is written out here because the folder's subject is the consumer half and
  # a default that carries a check is worth seeing.
  #
  # The check is over the wired capability's placements, not over anything this
  # module can see: one placement passes, two are a row naming this slot and both
  # placements. In the target that row is unreachable, because a read of a role
  # with two machines is an attrset the consumer indexes by hand and a read of a
  # role with one machine is whatever the author assumed.
  uses.repo = {
    interface = borgRepository;
    reach = "one";
    reads = [
      "url"
      "quota"
    ];
  };

  # The reciprocal half. This instance and the repository instance wire each
  # other, and the graph is still acyclic for §29.5's reason: a capability's
  # exports are a function of module and settings and never of a `wire`, so
  # `provides.identity` below cannot depend on `results.repo` above.
  #
  # The corpus's one-daemon-two-networks sketch keeps a mutual pair
  # acyclic a different way, by resolving both reads through the fact register,
  # because both of its values are `at-most-probed`. Here both values are known
  # at evaluation, so the pair resolves directly and no register is involved.
  # That is the concrete thing dropping `lifecycle` buys: a mutual edge between
  # two static providers needs no plane to stand on.
  provides.identity = {
    interface = sshHostIdentity;
  };

  impl =
    { vars, results, ... }:
    {
      # The roots this entry depends on, declared rather than left to a scan of
      # its own strings. Inference cannot be complete, so the scan is a
      # contradiction check: a store path this entry mentions and does not
      # declare is a row naming the path and where it was written.
      closure = [
        borgbackup
        openssh
      ];

      provides.identity.exports = {
        publicKey = vars.hostKey."ssh_host_ed25519_key.pub".content;

        # Declared, and delivered to nobody. No slot in this folder names it,
        # because no slot in any folder may: the secrecy rule refuses a `reads`
        # entry for a `secret` export outright. ../../plan/backup.json records
        # the export as declared and not delivered, the way
        # the corpus's secrets-per-instance sketch records its own private
        # half.
        privateKey = vars.hostKey."ssh_host_ed25519_key";
      };

      units.borgPush = {
        command = "${borgbackup}/bin/borg create --stats ${results.repo.url}::{now} ${settings.path}";
        env = {
          # The private half read by the service that made it, from its own
          # unit, without a slot. This is the whole of what the secrecy rule
          # permits and it is enough: the value never appears in another
          # module's `reads`, in another entry's `env`, or in the plan as
          # anything but a reference.
          BORG_RSH = "${openssh}/bin/ssh -i ${vars.hostKey."ssh_host_ed25519_key".path}";
          BORG_QUOTA_GIB = toString results.repo.quota;
        };
      };
    };
}
