{
  planner,
  folder,
  # Literal store paths: the fixture names packages and realises nothing. The image
  # check hands the same deployment real ones.
  packages ? {
    borgbackup = "/nix/store/3q8xk1p7v2mz9jd4rlnb6ycsfwg0h5aq-borgbackup-1.4.0";
    openssh = "/nix/store/1w9k3zc7yq2mb5xj8vdl4rns6fga0h1p-openssh-9.8p1";
  },
}:
let
  inherit (packages) borgbackup openssh;

  interfaces = import (folder + "/interfaces/default.nix") { korora = planner.korora; };
  inherit (interfaces) sshHostIdentity borgRepository;

  borgRepo = {
    services.default = import (folder + "/modules/borg-repo/default.nix") {
      inherit borgbackup sshHostIdentity borgRepository;
    };
  };

  borgPush = {
    services.default = import (folder + "/modules/borg-push/default.nix") {
      inherit
        borgbackup
        openssh
        sshHostIdentity
        borgRepository
        ;
    };
  };

  deployment = import (folder + "/deployment/instances.nix") { inherit borgRepo borgPush; };
  registry = import (folder + "/deployment/machines.nix");

  hostKeyState = machine: pub: {
    name = "nightly:vars/hostKey@${machine}";
    value = {
      "ssh_host_ed25519_key" = {
        present = true;
      };
      "ssh_host_ed25519_key.pub" = {
        present = true;
        content = "${pub} root@${machine}";
      };
    };
  };
in
{
  inherit
    interfaces
    borgbackup
    openssh
    ;

  args = {
    inherit (deployment) instances;
    inherit (registry) machines;

    interfaces = {
      "interfaces/default.nix" = interfaces;
    };

    # alpha and beta have run their generator, gamma deliberately has not. That one
    # absence is what the whole folder exercises. The state of a value is keyed by
    # the value's own plan entry.
    varsState = builtins.listToAttrs [
      (hostKeyState "alpha" "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAICCyXFCyCrjDXgk161ICmYQX0iXoZgMe5sDtDnhA13q+")
      (hostKeyState "beta" "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIH2zYlcrdY8a7DJlJ8Az4edUdWjYfHMxcCuOpwUzwdQt")
    ];

    # Module rows are relative to modules/, everything else to the folder root.
    sources = {
      deployment = "deployment/instances.nix";
      machines = "deployment/machines.nix";
      modules = {
        vault-repo = "borg-repo/default.nix";
        nightly = "borg-push/default.nix";
      };
      leaves = {
        vault-repo.server = "borg-repo/server.nix";
        nightly.client = "borg-push/client.nix";
      };
    };
  };
}
