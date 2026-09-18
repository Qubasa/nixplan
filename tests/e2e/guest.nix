# The guest every end-to-end machine boots. The invariants below are copied from
# rookery's base-image-configuration.nix, which the run resolves at run time rather
# than pinning, so nothing checks the copy. Diff it when rookery moves.
#
# The image carries no plan artifact and no flakelet service: every entry arrives by
# delivery, or a test passes without proving anything. Its one credential is the
# snakeoil key below, because a resumed cut authorizes whatever it froze.
#
# The one-time root work a user-scope run rests on is not stated here: this
# image imports the declaration this repository publishes for provisioning a
# machine, so the path these tests exercise and the path a reader follows are
# one text. What is left of it here is the two facts that are a test machine's
# and not a machine's role - the snakeoil credential, handed to the module as
# the logins that may reach the account, and a service manager rebuilt for a
# package set whose build sandbox has no BTF, which the declaration asserts
# about and deliberately does not do.
{
  lib,
  pkgs,
  nixpkgs,
  system,
  flakeletModule,
  provisioningModule,
}:
let
  console = "ttyS0";

  sshKeys = import "${nixpkgs}/nixos/tests/ssh-keys.nix" pkgs;

  # The account every user-scope folder deploys as, handed to the published
  # declaration below. A user-scope run is made as an account rather than in a
  # mode, and the login is what the run connects as, so no unit of those
  # folders names it: a unit declaring a `user` in user scope is
  # `unit-account-in-user-scope`. What makes the account usable - lingering, a
  # traversable home, the trusted login, the roots, the authorization and the
  # two daemons - is the declaration's and is stated in none of the lines
  # below.
  account = "deployer";

  # The throwaway dm-verity pairs of the folders whose images they sign, read
  # out of those folders rather than copied here: a public half is provisioning
  # the declaration installs and the private half is an argument of that
  # folder's build, and two copies of a pair are two things that can disagree.
  # One pair per folder, because no file of an end-to-end folder may name
  # another's.
  verities = {
    "user-scope" = import ./user-scope/verity.nix { inherit (pkgs) writeText; };
    "friend-enrollment" = import ./friend-enrollment/verity.nix { inherit (pkgs) writeText; };
  };

  # The declaration installs each under /etc/verity.d by the name it is keyed
  # with, so the certificates of two folders admit two folders' images and
  # neither refuses the other's.
  verityCertificates = lib.mapAttrs' (folder: pair: {
    name = "planner-e2e-${folder}.crt";
    value = pair.certificate;
  }) verities;

  # The one property of this image that is not a line of configuration. An
  # account's own portabled allocates a delegated user namespace before it
  # mounts anything (portable.c:620-626), nsresourced exposes that interface
  # only where it loaded its own BPF LSM program, and that half of nsresourced
  # is compiled in only with a `vmlinux.h`
  # (nsresourced-manager.c:228-235, nsresourcework.c:1082-1097). The pinned
  # nixpkgs builds systemd in a sandbox with no `/sys/kernel/btf`, so meson's
  # `vmlinux-h=auto` resolves to neither provided nor generated and
  # `portablectl --user` answers
  # `io.systemd.NamespaceResource.UserNamespaceInterfaceNotSupported` before it
  # reads a byte of an image. The header is dumped from the BTF of the kernel
  # this guest boots, so the program the daemon loads was compiled against the
  # kernel that verifies it.
  vmlinuxHeader =
    pkgs.runCommand "vmlinux-h-${pkgs.linuxPackages.kernel.version}"
      {
        nativeBuildInputs = [ pkgs.bpftools ];
      }
      ''
        mkdir -p "$out"
        bpftool btf dump file ${pkgs.linuxPackages.kernel.dev}/vmlinux format c > "$out/vmlinux.h"
      '';

  systemdWithNamespaceResource = pkgs.systemd.overrideAttrs (previous: {
    mesonFlags = previous.mesonFlags ++ [
      "-Dvmlinux-h=provided"
      "-Dvmlinux-h-path=${vmlinuxHeader}/vmlinux.h"
    ];
  });

  guestModule =
    { config, modulesPath, ... }:
    {
      imports = [
        "${modulesPath}/profiles/qemu-guest.nix"
        flakeletModule

        # The one-time root work a user-scope run verifies and creates none of,
        # as the declaration this repository publishes rather than as a second
        # copy of it. What this image hands it is what is a test machine's own:
        # the account the folders deploy as, the logins that may reach it -
        # here the published snakeoil pair, because a resumed cut authorizes
        # whatever its cut froze - and the public half of each folder's verity
        # pair. `userNamespaceInterface` is not stated: the declaration reads
        # it off the build flags of the service manager below, which is the
        # one this image rebuilds for exactly that reason.
        (provisioningModule {
          inherit account verityCertificates;
          authorizedKeys = [ sshKeys.snakeOilEd25519PublicKey ];
        })
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
        {
          assertion =
            config.users.users ? postgres
            && config.users.users.postgres.group == "postgres"
            && config.users.groups ? postgres;
          message = "tests/e2e/shared-postgres/ runs its server as the `postgres` account, and no plan creates an account: a module's unit names a user and no realiser provisions one, so the account is the machine's and has to be declared here. Every property of this image is part of every snapshot cut's key, so adding it makes the next run of every folder cold; `rookery snapshot gc --all` reclaims the orphans";
        }
        {
          assertion = config.boot.kernelPackages.kernel == pkgs.linuxPackages.kernel;
          message = "the systemd this image boots is built against a `vmlinux.h` dumped from the BTF of pkgs.linuxPackages.kernel, and nsresourced loads the BPF program compiled from it into the kernel that is running: a header of one kernel and a running kernel of another is a program the verifier may reject, and the account's user namespace then goes unallocated for a reason no plan and no run can name";
        }
        {
          assertion = builtins.elem "-Dvmlinux-h=provided" config.systemd.package.mesonFlags;
          message = "the pinned nixpkgs builds systemd where `/sys/kernel/btf` does not exist, so it carries no `vmlinux.h`, nsresourced exposes no user-namespace interface and `portablectl --user` refuses before it reads an image: this image builds its own systemd with the header provided. A plan cannot state it - the scope is a fact about a machine and the daemons that honour it are the machine's - and every property of this image is part of every snapshot cut's key, so `rookery snapshot gc --all` reclaims the orphans";
        }
        {
          assertion =
            config.users.users.${account}.openssh.authorizedKeys.keys == [
              sshKeys.snakeOilEd25519PublicKey
            ];
          message = "which logins may reach the deploying account is this image's own fact and never the published declaration's: a declaration that shipped a credential would admit whoever published it, so the key is an argument the consumer states and this consumer states the published snakeoil pair, which authorizes nothing but an offline throwaway guest. Everything else about that account - the lingering, the traversable home, the trusted login, the three roots, the authorization rule and the two delegating daemons - is the declaration's and is restated in no line of this file. A per-run credential would be a key input and would re-key every snapshot cut; `rookery snapshot gc --all` reclaims the orphans";
        }
        {
          assertion =
            config.services.tailscale.enable
            && builtins.elem config.services.tailscale.package config.environment.systemPackages;
          message = "the mesh client of tests/e2e/friend-enrollment/ is a system daemon: it opens a tun device, holds CAP_NET_ADMIN and keeps its node key under /var/lib/tailscale, and the friend machine that joins with it is a user-scope machine whose entries are never root. No plan creates a daemon on a machine, so the client is provisioning like the accounts above it, and it is inert until a login presents a credential. Every property of this image is part of every snapshot cut's key; `rookery snapshot gc --all` reclaims the orphans";
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

      # tests/e2e/shared-postgres/'s server runs as this account and writes its
      # cluster under /var/lib/postgresql. The assertion above says why a plan
      # cannot state it.
      users.groups.postgres = { };
      users.users.postgres = {
        isSystemUser = true;
        group = "postgres";
        home = "/var/lib/postgresql";
        createHome = true;
        homeMode = "700";
      };

      # The service manager this image builds for itself, which the published
      # declaration asserts about and deliberately does not do: a rebuild is a
      # property of one package set's build sandbox rather than of a machine's
      # role, and it would otherwise sit in the closure of every machine that
      # imports the declaration.
      systemd.package = systemdWithNamespaceResource;

      services.flakelets.enable = true;

      # The mesh client of tests/e2e/friend-enrollment/. It is the machine's
      # own daemon for the reason the assertion above states: a daemon holding
      # a tun device and a node key is nothing a plan creates. The server's own
      # tool is not here any more - every act against the server is a verb of
      # the operator's command running the program the entry's own closure
      # carries, so a copy in the system profile would be a second store path
      # of the same tool. The client costs no byte of traffic until a login
      # presents a credential, so every other folder boots with an idle one.
      services.tailscale.enable = true;

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
