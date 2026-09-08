{
  borgbackup,
  sshHostIdentity,
  borgRepository,
}:

{ settings, ... }:
{
  platforms = [
    "x86_64-linux"
    "aarch64-linux"
  ];

  claims.ports.ssh = {
    proto = "tcp";
    count = 1;
    fixed = settings.port;
  };

  # The set-valued read, and the reason `reach` could not be left out of this
  # folder.
  #
  # `reach = "all"` says the far end is every placement of the wired capability
  # and that the read is an attrset keyed by machine. It is not a convenience: in
  # the target, membership is authored, so a role IS a set, and a slot pointing
  # at a role points at a set whether or not anybody says so. Leaving the field
  # out does not make the read single-valued, it makes the arity a thing the
  # reader has to infer from a machine list somewhere else. §31.1 calls that
  # exact silence the defect.
  #
  # What the field buys here is one refusal that clan-core cannot state. Upstream
  # builds this same set by folding `getPublicValue` over the client machines with
  # a default of null and dropping the nulls
  # (`clanServices/borgbackup/default.nix:57-72`, and
  # `clanServices/zerotier/default.nix:229-240` is the same shape for addresses).
  # A machine whose key has not been generated is not in the fold, the server is
  # healthy, the repository is up, and one client cannot push. `reach = "all"`
  # names its entries instead of counting them, so a named entry with no value is
  # a row against that entry. ../../plan/diagnostics.txt carries it for gamma.
  #
  # `reads = [ "publicKey" ]` is the consumer half of the type, and it is the
  # half clan-core declared and never enforced: `manifest.exports.inputs` is
  # declared at `clan-core/lib/inventory/distributed-service/service-module.nix:350-353`,
  # written by two services, and read by nothing. Two things follow from writing
  # it here. A slot with no wire is a row rather than an empty attrset, so `or
  # [ ]` is not a thing this file could write. And naming `privateKey` in this
  # list is refused by the secrecy rule in ../../interfaces/exports.nix, which is
  # how a backup server stops being a plausible place for every client's private
  # key to end up.
  uses.clients = {
    interface = sshHostIdentity;
    reach = "all";
    reads = [ "publicKey" ];
  };

  provides.repo = {
    interface = borgRepository;
  };

  impl =
    { results, alloc, target, ... }:
    {
      closure = [ borgbackup ];

      # Both exports of the declared interface, because a provider's keyset
      # equals its interface's keyset. Dropping `quota` here would be a row
      # naming this file and the interface's declaring file, which is the
      # refusal ../../interfaces/default.nix keeps a second export around for.
      # The address is the machine the planner placed this service on, read out
      # of the target it handed the implementation. The deployment declares it
      # once, in ../../deployment/machines.nix; a `settings.host` beside it
      # would be the same fact declared twice.
      provides.repo.exports = {
        url = "ssh://borg@${target.address}:${toString alloc.ports.ssh}/srv/borg";
        quota = settings.quota;
      };

      # The authorized-keys file is the collected read rendered. One line per
      # entry of `results.clients`, keyed by machine, and the key is a public
      # string that this service never had to hold a private half to obtain.
      #
      # It is `configData` and not part of the closure, so admitting a machine
      # reloads sshd and rebuilds nothing. Worth naming because the set is in
      # this entry's key anyway — ../../plan/diagnostics.txt has the row — and the
      # two facts are about different things: what re-keys an entry and what
      # restarts a process are decided separately.
      #
      # `render` and not `source`, because content computed from a set-valued
      # read exists at evaluation and in no store path. Every fragment is a
      # public literal, so the plan holds the bytes it hashes; a recipe naming a
      # secret's path would carry a hash over the recipe and no digest over the
      # assembled file. `reload` is the unit this file is for and not every unit
      # of the entry.
      configData."/srv/borg/.ssh/authorized_keys" = {
        mode = "0600";
        reload = [ "borgRepo" ];
        render = [
          {
            text = builtins.concatStringsSep "\n" (
              builtins.attrValues (
                builtins.mapAttrs (machine: c: "# ${machine}\n${c.publicKey}") results.clients
              )
            );
          }
        ];
      };

      units.borgRepo = {
        command = "${borgbackup}/bin/borg serve --restrict-to-path /srv/borg";
      };
    };
}
