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

  # The pusher offers something, which is unusual for a client and is the shape
  # that makes the two wires in ../../deployment/instances.nix point at each
  # other. A machine being backed up is the authority on its own host key, so the
  # capability belongs here rather than on the server that has to trust it.
  provides.identity = client.provides.identity;
}
