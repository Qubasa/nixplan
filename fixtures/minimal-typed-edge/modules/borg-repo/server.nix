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

      provides.repo.exports = {
        url = "ssh://borg@${target.address}:${toString alloc.ports.ssh}/srv/borg";
        quota = settings.quota;
      };

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
