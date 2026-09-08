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

    # The port is fixed rather than a default because the url export is built from it.
    # A deployment moving it would rewrite a value this module publishes about itself.
    fixed.port = 22;
  };
in
{
  services = { inherit server; };

  provides.repo = server.provides.repo;
}
