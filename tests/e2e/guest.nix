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

  # The account the user-scope folder of openspec/changes/run-an-entry-without-root deploys as. A user-scope run is made as an
  # account rather than in a mode, and the login is what the run connects as, so
  # no unit of that folder names it: a unit declaring a `user` in user scope is
  # `unit-account-in-user-scope`. The assertion below says why a plan cannot
  # create it.
  account = "deployer";

  # The three roots a user-scope run writes under, which do not move with the
  # scope: `util.varsRoot` in lib/util.nix, the staging root `stagingOf` derives
  # in image/read.nix, and the sealed root a value survives a reboot in, which
  # `cli/remote.py` verifies under the same three names. Each is made writable by
  # the account here, at provision time, because root at deploy time is what this
  # change exists to remove. The modes are the ones the run's own steps give
  # them: `0711` is traversable by any and listable by none, which is what a
  # staged file reached by its full path needs and what keeps one entry's file
  # names from publishing another's, and the sealed root is the account's alone.
  accountRoots = [
    {
      path = "/run/vars";
      mode = "0711";
    }
    {
      path = "/run/portable-planner";
      mode = "0711";
    }
    {
      path = "/var/lib/planner/sealed";
      mode = "0700";
    }
  ];

  # The throwaway dm-verity pairs of the folders whose images they sign, read
  # out of those folders rather than copied here: a public half is provisioning
  # this image installs and the private half is an argument of that folder's
  # build, and two copies of a pair are two things that can disagree. One pair
  # per folder, because no file of an end-to-end folder may name another's.
  verities = {
    "user-scope" = import ./user-scope/verity.nix { inherit (pkgs) writeText; };
    "friend-enrollment" = import ./friend-enrollment/verity.nix { inherit (pkgs) writeText; };
  };

  # systemd enumerates `*.crt` under /etc/verity.d, so the certificates of two
  # folders admit two folders' images and neither refuses the other's.
  verityCertificates = lib.mapAttrs' (folder: pair: {
    name = "verity.d/planner-e2e-${folder}.crt";
    value = {
      source = pair.certificate;
    };
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
        {
          assertion =
            config.users.users ? postgres
            && config.users.users.postgres.group == "postgres"
            && config.users.groups ? postgres;
          message = "tests/e2e/shared-postgres/ runs its server as the `postgres` account, and no plan creates an account: a module's unit names a user and no realiser provisions one, so the account is the machine's and has to be declared here. Every property of this image is part of every snapshot cut's key, so adding it makes the next run of every folder cold; `rookery snapshot gc --all` reclaims the orphans";
        }
        {
          assertion =
            lib.all
              (
                unit:
                builtins.elem unit config.systemd.additionalUpstreamSystemUnits
                && config.systemd.units.${unit}.wantedBy == [ "sockets.target" ]
              )
              [
                "systemd-mountfsd.socket"
                "systemd-nsresourced.socket"
              ];
          message = "the user-scope folder of openspec/changes/run-an-entry-without-root attaches an image as an unprivileged account, and that account's own portabled delegates the mount to systemd-mountfsd and the user namespace to systemd-nsresourced: both are the machine's daemons, no plan creates a unit on a machine, and NixOS carries no option for either, so the upstream units are copied in and each socket is enabled by a drop-in of its own. Every property of this image is part of every snapshot cut's key, so adding it makes the next run of every folder cold; `rookery snapshot gc --all` reclaims the orphans";
        }
        {
          assertion = lib.all (unit: builtins.elem unit config.systemd.additionalUpstreamUserUnits) [
            "systemd-portabled.service"
            "dbus-org.freedesktop.portable1.service"
          ];
          message = "`portablectl --user` talks to one unprivileged systemd-portabled per account over that account's own bus, which is D-Bus activated through the alias the second name is: the service file systemd ships at share/dbus-1/services names it, and the session bus reads it because systemd's package is in this image's system profile. No plan runs a daemon for an account, so the units are the machine's and are copied in here";
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
            config.users.users ? ${account}
            && config.users.users.${account}.linger
            && config.users.users.${account}.home == "/home/${account}"
            &&
              config.users.users.${account}.openssh.authorizedKeys.keys == [
                sshKeys.snakeOilEd25519PublicKey
              ];
          message = "the user-scope folder of openspec/changes/run-an-entry-without-root is deployed as the `deployer` account, and no plan creates an account: a machine's scope is a registry fact and the account that honours it is the machine's own. Lingering is what keeps that account's service manager alive with nobody logged in, which is the only way a non-interactive run reaches its bus, and the one credential is this image's published snakeoil pair, because a per-run credential would re-key every cut. Every property of this image is part of every snapshot cut's key; `rookery snapshot gc --all` reclaims the orphans";
        }
        {
          assertion = config.users.users.${account}.homeMode == "711";
          message = "portabled extracts an image's metadata in a child that has joined the user namespace systemd-nsresourced delegated, and the account's own uid is not mapped in it: the child runs as a foreign uid. `extract_now` then asks whether the image path is the root directory (portable.c:372 -> chaseat_prefix_root -> path_is_root_at, fd-util.c:1054), which opens the path itself `O_PATH|O_DIRECTORY`; a world-traversable path answers ENOTDIR and is read as `not root`, and a home at NixOS' `createHome` default of 0700 answers EACCES, which portable.c:373 returns unlogged and the manager reports as `AttachImage failed: Access denied`. So every component of the pool path has to be traversable by a uid that owns none of it, which no plan can state - the account and its home are the machine's - and traversal is all that is granted, a listable home publishing one entry's image names to every account. Every property of this image is part of every snapshot cut's key; `rookery snapshot gc --all` reclaims the orphans";
        }
        {
          assertion = builtins.elem account config.nix.settings.trusted-users;
          message = "the run copies each artifact to the machine as the account it deploys as, and a `nix copy` from a login the remote daemon does not trust is refused for want of a signature whatever the client passes, the artifact being a local build nobody signed. Which logins a machine trusts with its own store is provisioning root does once, no plan records it, and a machine that trusts none of them is a user-scope machine no artifact can reach";
        }
        {
          assertion = lib.all (
            root:
            builtins.any (
              rule: rule == "d ${root.path} ${root.mode} ${account} ${account} -"
            ) config.systemd.tmpfiles.rules
          ) accountRoots;
          message = "the values root, the sealed root and the image staging root are the same paths in both scopes, so no uid enters a plan and a scope flip re-keys entries and never values: making them writable by the account is root's work at provision time and never the run's, which is what this image does with three tmpfiles rules. A plan states none of them - a path that moved with the scope would put an account's name into every entry key that renders one";
        }
        {
          assertion = lib.all (
            name: config.environment.etc.${name}.source == verityCertificates.${name}.source
          ) (builtins.attrNames verityCertificates);
          message = "an account attaches only a signed dm-verity image: systemd-mountfsd applies its untrusted image policy to anything outside the system trusted directories and an unsigned image escalates to an interactive polkit action a non-interactive run cannot answer. systemd reads `*.crt` from /etc/verity.d, and each public half installed here is the half of a folder's own verity.nix whose private half signs that folder's image, which rides beside this image the way the snakeoil ssh key does. One pair per folder, because no file of an end-to-end folder may name another's. A plan carries neither half: the signing key is an argument of the build and the public key is provisioning";
        }
        {
          assertion =
            config.security.polkit.enable
            && lib.hasInfix "org.freedesktop.portable1." config.security.polkit.extraConfig
            && lib.hasInfix account config.security.polkit.extraConfig;
          message = "an account's own portabled authorizes an attach through polkit, so a machine with no polkit answers `Access denied` before it reads the image: the daemon and the rule that admits the account are the machine's, upstream's own user-scope test refuses to run without `pkcheck`, and no plan creates either. Every property of this image is part of every snapshot cut's key; `rookery snapshot gc --all` reclaims the orphans";
        }
        {
          assertion = builtins.elem pkgs.headscale config.environment.systemPackages;
          message = "tests/e2e/friend-enrollment/ runs the coordination server as a planned entry, and the operator's own acts against it are not the plan's: minting the single-use join credential, reading the node list back and expiring a node are `headscale` invocations made over ssh, so the tool has to be the machine's. The entry carries the same package in its own closure, which is one store path and not two. Every property of this image is part of every snapshot cut's key, so adding it makes the next run of every folder cold; `rookery snapshot gc --all` reclaims the orphans";
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

      # the user-scope folder of openspec/changes/run-an-entry-without-root is deployed as this account. It runs no unit of its
      # own: a user-scope unit is refused an account, so the login is the whole
      # of what the run uses it for. The assertion above says why a plan cannot
      # create it, and `linger` is what drives systemd.services.linger-users,
      # which runs `loginctl enable-linger`.
      users.groups.${account} = { };
      users.users.${account} = {
        isNormalUser = true;
        group = account;
        linger = true;
        home = "/home/${account}";
        createHome = true;
        homeMode = "711";
        openssh.authorizedKeys.keys = [ sshKeys.snakeOilEd25519PublicKey ];
      };

      # The run copies an artifact with `nix copy --to ssh://<account>@<machine>`,
      # and the remote daemon refuses an unsigned path from a login that is not
      # trusted however the client is invoked, so the account is trusted here.
      # Provisioning again: root states it once per machine, no plan records who
      # a machine trusts, and the artifact is the operator's own build.
      nix.settings.trusted-users = [ account ];

      # Root at provision time, never at deploy time. One rule per fixed root,
      # in the shape the assertion above reads back.
      systemd.tmpfiles.rules = map (
        root: "d ${root.path} ${root.mode} ${account} ${account} -"
      ) accountRoots;

      # The public half of each pair whose private half signs a folder's image.
      # systemd enumerates `*.crt` under /etc/verity.d, /run/verity.d and
      # /usr/lib/verity.d, and an image whose roothash no installed certificate
      # signed is refused by systemd-mountfsd's untrusted image policy.
      environment.etc = verityCertificates;

      # The authority an account's portabled asks before it attaches. Without
      # polkit the check cannot be answered at all and every attach is
      # `Access denied`; with it, a rule admitting this account is what makes a
      # non-interactive run possible, an interactive prompt being no answer.
      security.polkit.enable = true;
      security.polkit.extraConfig = ''
        polkit.addRule(function(action, subject) {
          if (subject.user == "${account}" &&
              (action.id.indexOf("org.freedesktop.portable1.") == 0 ||
               action.id.indexOf("io.systemd.mount-file-system.") == 0)) {
            return polkit.Result.YES;
          }
        });
      '';

      # The two daemons an account's portabled delegates to. NixOS carries no
      # option for either, so the upstream units are copied in and each socket
      # is enabled by a drop-in of its own, which is the documented way to enable
      # an upstream unit.
      systemd.package = systemdWithNamespaceResource;

      systemd.additionalUpstreamSystemUnits = [
        "systemd-mountfsd.service"
        "systemd-mountfsd.socket"
        "systemd-nsresourced.service"
        "systemd-nsresourced.socket"
      ];

      systemd.units."systemd-mountfsd.socket" = {
        overrideStrategy = "asDropin";
        wantedBy = [ "sockets.target" ];
      };

      systemd.units."systemd-nsresourced.socket" = {
        overrideStrategy = "asDropin";
        wantedBy = [ "sockets.target" ];
      };

      # The account's own portabled, and the alias the session bus activates it
      # through.
      systemd.additionalUpstreamUserUnits = [
        "systemd-portabled.service"
        "dbus-org.freedesktop.portable1.service"
      ];

      services.flakelets.enable = true;

      # The mesh of tests/e2e/friend-enrollment/. The client is the machine's
      # daemon and the server's tool is the machine's program, for the two
      # reasons the assertions above state: a daemon holding a tun device and a
      # node key is nothing a plan creates, and the operator's mint, node list
      # and expiry are acts against the server rather than units of it. Neither
      # costs a byte of traffic until a login presents a credential, so every
      # other folder boots with an idle client.
      services.tailscale.enable = true;
      environment.systemPackages = [ pkgs.headscale ];

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
