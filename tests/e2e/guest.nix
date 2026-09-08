{
  lib,
  pkgs,
  nixpkgs,
  system,
  flakeletModule,
}:
let
  console = "ttyS0";

  guestModule =
    { config, modulesPath, ... }:
    {
      imports = [
        "${modulesPath}/profiles/qemu-guest.nix"
        flakeletModule
      ];

      assertions = [
        {
          assertion = builtins.elem "virtiofs" config.boot.initrd.availableKernelModules;
          message = "rookery virtiofs shares require the 'virtiofs' kernel module in the guest image";
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
          assertion = !config.services.openssh.settings.PasswordAuthentication;
          message = "the image carries no credential (design.md D6): the only way in is the key the run seeds over virtiofs";
        }
        {
          assertion = config.systemd.services ? rookery-virtiofs-report;
          message = "the host reads share readiness off the serial log, so the guest must enumerate its virtiofs mounts there (rookery/qemu/api.py:154-171); without the unit Vm.wait_for_share can only time out";
        }
        {
          assertion = config.systemd.package.withPortabled;
          message = "tests/e2e/portable-image/ attaches a planner-built image by running the artifact's own bin/attach on this guest, and that script calls `portablectl`, which talks to systemd-portabled: a systemd built without portabled would leave that test asserting against a stand-in, which is the one thing this layer exists to avoid";
        }
        {
          assertion = builtins.elem config.systemd.package config.environment.systemPackages;
          message = "the attach script the artifact carries resolves `portablectl` and `systemctl` on PATH, so systemd's own package has to be in the guest's system profile";
        }
      ];

      boot.initrd.availableKernelModules = [ "virtiofs" ];
      boot.kernelModules = [ "vmw_vsock_virtio_transport" ];
      fileSystems."/rookery" = {
        device = "rookery";
        fsType = "virtiofs";
        options = [ "nofail" ];
        neededForBoot = false;
      };

      systemd.services.rookery-virtiofs-report = {
        description = "Report active virtiofs mounts to the serial console";
        wantedBy = [ "multi-user.target" ];
        after = [ "local-fs.target" ];
        path = [ pkgs.util-linux ];
        serviceConfig = {
          Type = "oneshot";
          RemainAfterExit = true;
        };
        script = ''
          {
            echo "=== rookery virtiofs mounts begin ==="
            findmnt -t virtiofs -o TARGET,SOURCE || true
            echo "=== rookery virtiofs mounts end ==="
          } > /dev/${console}
        '';
      };

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

      services.openssh = {
        enable = true;
        settings = {
          PermitRootLogin = "prohibit-password";
          PasswordAuthentication = false;
        };
      };

      systemd.services.cluster-authorized-key = {
        description = "Install the run's public key into root's authorized_keys";
        wantedBy = [ "multi-user.target" ];
        before = [ "sshd.service" ];
        after = [ "local-fs.target" ];
        unitConfig.ConditionPathExists = "/rookery/authorized_keys";
        serviceConfig = {
          Type = "oneshot";
          RemainAfterExit = true;
        };
        script = ''
          install -d -m 700 -o root -g root /root/.ssh
          install -m 600 -o root -g root /rookery/authorized_keys /root/.ssh/authorized_keys
        '';
      };

      services.flakelets.enable = true;

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
    additionalSpace = "2048M";
  };
in
image
// {
  inherit guest;
  toplevel = guest.config.system.build.toplevel;
}
