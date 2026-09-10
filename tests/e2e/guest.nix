# The guest every end-to-end machine boots. The invariants below are copied from
# rookery's base-image-configuration.nix, which the run resolves at run time rather
# than pinning, so nothing checks the copy. Diff it when rookery moves.
#
# The image carries no plan artifact and no flakelet service: every entry arrives by
# delivery, or a test passes without proving anything. Its one credential is the
# snakeoil key below, because a resumed cut authorizes whatever it froze.
{
  lib,
  pkgs,
  nixpkgs,
  system,
  flakeletModule,
}:
let
  console = "ttyS0";

  sshKeys = import "${nixpkgs}/nixos/tests/ssh-keys.nix" pkgs;

  guestModule =
    { config, modulesPath, ... }:
    {
      imports = [
        "${modulesPath}/profiles/qemu-guest.nix"
        flakeletModule
      ];

      assertions = [
        {
          assertion = lib.all (fs: fs.fsType != "virtiofs") (builtins.attrValues config.fileSystems);
          message = "a virtiofs device does not survive the migration save and restore a snapshot cut is made of, so this guest mounts no host share: rookery/snapshot/cluster_lineage.py builds each slot's VmSpec without one, and the run's credential therefore comes from the image instead";
        }
        {
          assertion = builtins.elem "vmw_vsock_virtio_transport" config.boot.kernelModules;
          message = "rookery SSH-over-vsock requires the 'vmw_vsock_virtio_transport' guest module";
        }
        {
          assertion = lib.all (fs: fs.mountPoint == "/" || builtins.elem "nofail" fs.options) (
            builtins.attrValues config.fileSystems
          );
          message = "rookery images must mount every non-root filesystem nofail: a required mount that stalls drops the guest into emergency mode and it never becomes reachable";
        }
        {
          assertion = !config.networking.dhcpcd.enable && config.networking.useNetworkd;
          message = "rookery images must ship no dhcpcd; networkd is the DHCP client";
        }
        {
          assertion = config.boot.loader.systemd-boot.enable && !config.boot.loader.efi.canTouchEfiVariables;
          message = "the cluster boots through OVMF with a blank varstore, so the image needs systemd-boot on a GPT ESP and must not write host EFI variables";
        }
        {
          assertion = builtins.any (p: lib.hasPrefix "console=${console}," p) config.boot.kernelParams;
          message = "the run diagnoses a failed boot from the serial log, so the kernel console must be the primary UART (${console})";
        }
        {
          assertion = !config.networking.firewall.enable;
          message = "the wire under test is traffic between two guests on the cluster LAN; a firewall in the guest would make a resolved wire look unresolved";
        }
        {
          assertion = config.services.flakelets.enable && config.services.flakelets.services == { };
          message = "the endpoint is enabled with no declared service: every entry this image runs arrives by delivery, so a declared service here would be an artifact the image already had";
        }
        {
          assertion =
            !config.services.openssh.settings.PasswordAuthentication
            &&
              config.users.users.root.openssh.authorizedKeys.keys == [
                sshKeys.snakeOilEd25519PublicKey
              ];
          message = "the only way in is the one key this image carries. A resumed snapshot authorizes whatever its cut froze, so a per-run credential would have to be a key input and would then re-key every cut; the key is nixpkgs' published snakeoil pair from nixos/tests/ssh-keys.nix, which authorizes nothing but an offline throwaway guest";
        }
        {
          assertion = config.systemd.package.withPortabled;
          message = "tests/e2e/portable-image/ attaches a planner-built image by running the artifact's own bin/attach on this guest, and that script calls `portablectl`, which talks to systemd-portabled: a systemd built without portabled would leave that test asserting against a stand-in, which is the one thing this layer exists to avoid";
        }
        {
          assertion = builtins.elem config.systemd.package config.environment.systemPackages;
          message = "the attach script the artifact carries resolves `portablectl` and `systemctl` on PATH, so systemd's own package has to be in the guest's system profile";
        }
        {
          assertion = lib.all (feature: builtins.elem feature config.nix.settings.experimental-features) [
            "nix-command"
            "flakes"
          ];
          message = "a machine of tests/e2e/newcomer/ locks a flake of its own, fetches its inputs and builds a deployment in its own store, and a stock nix.conf answers all three with a refusal about experimental features: the two flags every reader already has are part of this image";
        }
      ];

      boot.kernelModules = [ "vmw_vsock_virtio_transport" ];

      fileSystems."/" = {
        device = "/dev/disk/by-label/nixos";
        fsType = "ext4";
      };

      fileSystems."/boot" = {
        device = "/dev/disk/by-label/ESP";
        fsType = "vfat";
        options = [ "nofail" ];
      };

      boot.loader.systemd-boot.enable = true;
      boot.loader.efi.canTouchEfiVariables = false;
      boot.loader.timeout = lib.mkForce 0;
      boot.kernelParams = [ "console=${console},115200" ];

      networking.firewall.enable = false;
      networking.useDHCP = false;
      networking.useNetworkd = true;
      networking.tempAddresses = "disabled";
      systemd.network.enable = true;
      systemd.network.networks."10-rookery-dhcp" = {
        matchConfig.Type = "ether";
        networkConfig = {
          DHCP = "yes";
          Domains = "~.";
          IPv6PrivacyExtensions = false;
        };
        dhcpV4Config.UseDomains = true;
      };
      services.resolved.enable = true;

      # The TCP listener is the delivery channel, and systemd's ssh generator derives the
      # vsock control channel from it. One credential serves both.
      services.openssh = {
        enable = true;
        settings = {
          PermitRootLogin = "prohibit-password";
          PasswordAuthentication = false;
        };
      };

      users.users.root.openssh.authorizedKeys.keys = [ sshKeys.snakeOilEd25519PublicKey ];

      services.flakelets.enable = true;

      # The workstation of tests/e2e/newcomer/ builds on the machine, so its store
      # holds a nixpkgs checkout and the inputs of one deployment build. Both flags
      # are what a reader's own machine has; neither reaches a delivered artifact.
      nix.settings.experimental-features = [
        "nix-command"
        "flakes"
      ];

      documentation.enable = false;
      documentation.nixos.enable = false;
      system.stateVersion = config.system.nixos.release;
    };

  guest = nixpkgs.lib.nixosSystem {
    inherit system;
    modules = [ guestModule ];
  };

  image = import "${nixpkgs}/nixos/lib/make-disk-image.nix" {
    inherit lib pkgs;
    config = guest.config;
    name = "planner-e2e-guest-image";
    format = "qcow2";
    partitionTableType = "efi";
    label = "nixos";
    diskSize = "auto";
    # Room for the two delivered artifacts and their closures, and for the nixpkgs
    # checkout and build inputs a machine of tests/e2e/newcomer/ fetches for itself.
    additionalSpace = "6144M";
  };
in
# make-disk-image runs inside a VM builder whose result has no overrideAttrs, so
# the configuration rides beside the image instead of being read back out of it.
image
// {
  inherit guest;
  toplevel = guest.config.system.build.toplevel;
  sshPrivateKey = sshKeys.snakeOilEd25519PrivateKey;
}
