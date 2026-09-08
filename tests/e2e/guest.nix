# The guest every end-to-end machine boots, and every invariant it has to hold
# restated as an assertion.
#
# rookery is resolved at run time rather than as a flake input (design.md D2),
# so `${inputs.rookery}/nix/base-image-configuration.nix` is not available at
# evaluation and this configuration is ours. Each invariant below is carried
# with the assertion rookery carries for it, copied from
# `rookery/nix/base-image-configuration.nix:25-59`, so a future trim of this
# file fails `nix build` rather than producing a guest that boots and is never
# reachable. `docs/cluster.md` names the file to diff against when rookery moves.
#
# One image serves both end-to-end folders (design.md D2), so the invariants the
# second one needs are here too, in the same form: a portable-service manager
# and its client, with the assertion that says which test would otherwise be
# asserting against a stand-in.
#
# What this image does NOT carry: any artifact of the plan, any credential, and
# any declared flakelet service. The endpoint is installed and enabled with an
# empty service set; everything it runs arrives by delivery.
{
  lib,
  pkgs,
  nixpkgs,
  system,
  flakeletModule,
}:
let
  # x86_64's q35 exposes a 16550 (`ttyS`); rookery wires the primary console to
  # port 0 and captures it to the run's serial.log.
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

      # virtiofs, and the reserved `rookery` tag the run exports its generated
      # key through (`rookery/qemu/spec.py:238-241`). `nofail` is load-bearing:
      # a boot with no share behind the tag must still come up.
      boot.initrd.availableKernelModules = [ "virtiofs" ];
      boot.kernelModules = [ "vmw_vsock_virtio_transport" ];
      fileSystems."/rookery" = {
        device = "rookery";
        fsType = "virtiofs";
        options = [ "nofail" ];
        neededForBoot = false;
      };

      # `nofail` hides an absent or failed mount behind a happily-booted guest,
      # so the host cannot tell "mounted" from "never mounted" over SSH.
      # `Vm.wait_for_share` reads this enumeration off the serial log, framed by
      # the sentinels it parses (`rookery/qemu/command.py:51-52`,
      # `api.py:154-171`), which is why the unit is here and not only in
      # rookery's own image: the host-side helper is unusable without it.
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

      # `nofail` for the same reason: local-fs.target failing is irreversible and
      # takes sockets.target with it, so the vsock sshd never binds and the host
      # sees a bare readiness timeout. Nothing here updates its own bootloader.
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

      # The TCP sshd is the delivery channel; the vsock sshd systemd-ssh-generator
      # derives from it is the control channel. One credential serves both, and
      # the image ships neither a password nor a key.
      services.openssh = {
        enable = true;
        settings = {
          PermitRootLogin = "prohibit-password";
          PasswordAuthentication = false;
        };
      };

      # The run's key, installed from the virtiofs share at boot rather than read
      # out of it by sshd: `authorizedKeysFiles` pointing into the share would put
      # sshd's StrictModes in play over a directory the host owns. The condition
      # is what makes a share-less boot of this same image come up cleanly - the
      # unit is skipped, not failed, and then nobody can log in at all.
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
    # Room for what the run delivers: two artifacts and their closures.
    additionalSpace = "2048M";
  };
in
# `make-disk-image` builds inside `vmTools.runInLinuxVM`, whose result carries no
# `overrideAttrs`, so the guest travels beside the image rather than in a
# passthru. `toplevel` is the closure a reader inspects: the qcow2 itself
# references nothing, while the system inside it references everything.
image
// {
  inherit guest;
  toplevel = guest.config.system.build.toplevel;
}
