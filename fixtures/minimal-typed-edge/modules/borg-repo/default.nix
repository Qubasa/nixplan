{
  borgbackup,
  sshHostIdentity,
  borgRepository,
}:

{ service, ... }:
let
  server = service "server" {
    module = import ./server.nix { inherit borgbackup sshHostIdentity borgRepository; };
    defaults.quota = 250;

    fixed.port = 22;
  };
in
{
  services = { inherit server; };

  provides.repo = server.provides.repo;
}
