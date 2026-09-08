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

  vars.hostKey = {
    files."ssh_host_ed25519_key" = {
      secrecy = "secret";
    };
    files."ssh_host_ed25519_key.pub" = {
      secrecy = "public";
    };
  };

  uses.repo = {
    interface = borgRepository;
    reach = "one";
    reads = [
      "url"
      "quota"
    ];
  };

  provides.identity = {
    interface = sshHostIdentity;
  };

  impl =
    { vars, results, ... }:
    {
      closure = [
        borgbackup
        openssh
      ];

      provides.identity.exports = {
        publicKey = vars.hostKey."ssh_host_ed25519_key.pub".content;

        privateKey = vars.hostKey."ssh_host_ed25519_key";
      };

      units.borgPush = {
        command = "${borgbackup}/bin/borg create --stats ${results.repo.url}::{now} ${settings.path}";
        env = {
          BORG_RSH = "${openssh}/bin/ssh -i ${vars.hostKey."ssh_host_ed25519_key".path}";
          BORG_QUOTA_GIB = toString results.repo.quota;
        };
      };
    };
}
