# The module this repository publishes for provisioning a machine: the one-time
# root work a machine needs before a run can write to it as the account it
# deploys as. Every fact here is a fact `preflight` in cli/remote.py verifies per
# run and creates never, so a machine whose configuration never imported this is
# refused at its first step naming the fact that does not hold.
#
# Root at provision time, never at deploy time. That is the whole of the
# division: this declaration is applied by whoever owns the machine, and nothing
# a run does creates, enables or relaxes one of these facts.
#
# It carries no credential. Which logins may reach the deploying account is the
# operator's own statement about their own fleet, and a published declaration
# that shipped one would admit its own author; the public half of an image
# signing pair is a value the consumer states, and the private half is an
# argument of the image build and of nothing else.
#
# Two facts it cannot create it asserts instead: a service manager whose build
# exposes the interface an unprivileged user namespace is delegated through, and
# a kernel that permits one at all. Both are properties of the package set and
# the kernel a consumer chose, so each fails the evaluation naming what to do.
{
  # The login a user-scope run connects as, whose own service manager runs the
  # entries it is handed.
  account,

  # Which logins may reach that account. Stated by the consumer, defaulted to
  # none: a declaration that defaulted to a key would admit whoever published it.
  authorizedKeys ? [ ],

  # The group the account is in, and the home its manager's runtime state hangs
  # off. The home is `0711`: an image's metadata is extracted by a child that
  # joined the user namespace nsresourced delegated, in which the account's own
  # uid is unmapped, so every component of the pool path has to be traversable
  # by a uid that owns none of it.
  group ? account,
  home ? "/home/${account}",
  homeMode ? "711",

  # The public half of each dm-verity pair whose private half signs the images
  # this operator builds, by the file name it is installed under. systemd
  # enumerates `*.crt` under /etc/verity.d, so two of them admit two operators'
  # images and neither refuses the other's.
  verityCertificates ? { },

  # Whether the service manager of this machine exposes the interface an
  # unprivileged user namespace is delegated through. Unstated, it is read off
  # the build flags of the package the machine carries, which is the only thing
  # about that build an evaluation can see; a consumer whose package set builds
  # systemd where `/sys/kernel/btf` exists resolves the header without stating
  # the flag and says so here instead.
  userNamespaceInterface ? null,
}:

{ config, lib, ... }:
let
  # The three fixed roots a user-scope run writes under, which do not move with
  # the scope: the values root, the image staging root and the root a value
  # survives a reboot in. They are the three cli/remote.py states once, and this
  # declaration states no fourth - a path that moved with the scope would put an
  # account's name into every entry key that renders one.
  #
  # The modes are the ones the run's own steps give them: `0711` is traversable
  # by any and listable by none, which is what a staged file reached by its full
  # path needs and what keeps one entry's file names from publishing another's,
  # and the sealed root is the account's alone.
  roots = [
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
in
{
  assertions = [
    {
      # An account's own portabled allocates a delegated user namespace before
      # it mounts anything, nsresourced exposes that interface only where it
      # loaded its own BPF LSM program, and that half of nsresourced is compiled
      # in only with a `vmlinux.h`. A package set that builds systemd in a
      # sandbox with no `/sys/kernel/btf` carries none, and `portablectl --user`
      # then answers
      # `io.systemd.NamespaceResource.UserNamespaceInterfaceNotSupported` before
      # it reads a byte of an image.
      assertion =
        if userNamespaceInterface != null then
          userNamespaceInterface
        else
          builtins.any (flag: flag == "-Dvmlinux-h=provided" || flag == "-Dvmlinux-h=generated") (
            config.systemd.package.mesonFlags or [ ]
          );
      message = "the service manager of this machine states no `vmlinux.h`, so systemd-nsresourced exposes no user-namespace interface and an account's own portabled refuses every attach before it reads the image: this declaration configures a service manager and builds none. Override `systemd.package` with one built `-Dvmlinux-h=provided` against the BTF of the kernel this machine boots, or state `userNamespaceInterface = true` where the package set resolved the header itself";
    }
    {
      assertion = config.systemd.package.withPortabled;
      message = "the entries this account attaches are portable images, and `portablectl` talks to systemd-portabled: a service manager built without it leaves every attach unanswerable. Override `systemd.package` with one built `withPortabled = true`; no plan can state it, the daemon being the machine's";
    }
    {
      # A kernel knob and not a package flag: the fact is the machine's, and the
      # run verifies it per apply because nothing in a plan can state it.
      assertion = (config.boot.kernel.sysctl."user.max_user_namespaces" or 1) != 0;
      message = "this machine's kernel is configured to permit no unprivileged user namespace, and an account's own portabled allocates one per attach: the fact is the machine's and no plan can state it. Leave `boot.kernel.sysctl.\"user.max_user_namespaces\"` unset, or set it above zero";
    }
  ];

  # The account a user-scope run is made as. It runs no unit of its own - a
  # user-scope unit is refused an account - so the login is the whole of what a
  # run uses it for. Lingering is what keeps its service manager alive with
  # nobody logged in, which is the only way a non-interactive run reaches its
  # bus: no plan creates an account, a machine's scope being a registry fact and
  # the account that honours it the machine's own.
  users.groups.${group} = { };
  users.users.${account} = {
    isNormalUser = true;
    inherit group home homeMode;
    createHome = true;
    linger = true;
    openssh.authorizedKeys.keys = authorizedKeys;
  };

  # A run copies each artifact to the machine as the account it deploys as, and
  # a remote daemon refuses an unsigned path from a login it does not trust
  # however the client is invoked, the artifact being a local build nobody
  # signed. Which logins a machine trusts with its own store is provisioning
  # root does once and no plan records.
  nix.settings.trusted-users = [ account ];

  systemd.tmpfiles.rules = map (root: "d ${root.path} ${root.mode} ${account} ${group} -") roots;

  # An account attaches only a signed dm-verity image: systemd-mountfsd applies
  # its untrusted image policy to anything outside the system trusted
  # directories, and an unsigned image escalates to an interactive polkit action
  # a non-interactive run cannot answer.
  environment.etc = lib.mapAttrs' (name: source: {
    name = "verity.d/${name}";
    value = { inherit source; };
  }) verityCertificates;

  # The authority an account's own portabled asks before it attaches. Without
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

  # The two daemons an account's own portabled delegates the mount and the user
  # namespace to. NixOS carries no option for either, so the upstream units are
  # copied in and each socket is enabled by a drop-in of its own, which is the
  # documented way to enable an upstream unit.
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

  # The account's own portable-service daemon, and the alias its session bus
  # activates it through: the service file systemd ships under
  # share/dbus-1/services names it, and the session bus reads it because
  # systemd's own package is in this machine's system profile.
  systemd.additionalUpstreamUserUnits = [
    "systemd-portabled.service"
    "dbus-org.freedesktop.portable1.service"
  ];
}
