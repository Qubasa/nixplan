{
  borgbackup,
  sshHostIdentity,
  borgRepository,
}:

{ service, ... }:
let
  # One member, and it still takes a name. A single-member root keys its
  # settings namespace too, which is post 1's corrected sentence in §29.8: the
  # deployment writes `settings.server.quota` and this file forwards nothing.
  # `fixed` and `defaults` say which of the two knobs the deployment may move.
  server = service "server" {
    module = import ./server.nix { inherit borgbackup sshHostIdentity borgRepository; };
    defaults.quota = 250;

    # The port is what the interface's `url` export is built out of, so a
    # deployment moving it would change a value this module publishes as a fact
    # about itself. `fixed` takes the path away from the deployment (§29.3), and
    # it is the same word `claims.ports.<n>.fixed` uses in ./server.nix for the
    # same reason: the other party does not get to choose.
    fixed.port = 22;
  };
in
{
  services = { inherit server; };

  # Re-exported so a deployment can name it in `exposes` and a sibling instance
  # can wire it. A capability that is not re-exported here is not addressable
  # from outside the instance at all, which is what keeps cross-instance
  # resolution explicit.
  provides.repo = server.provides.repo;
}
