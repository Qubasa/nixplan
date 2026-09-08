{
  borgbackup,
  openssh,
  sshHostIdentity,
  borgRepository,
}:

{ service, ... }:
let
  client = service "client" {
    module = import ./client.nix {
      inherit
        borgbackup
        openssh
        sshHostIdentity
        borgRepository
        ;
    };
    defaults.path = "/home";
  };
in
{
  services = { inherit client; };

  provides.identity = client.provides.identity;
}
