# One deployment and three images: the entry this host attaches, the entry it
# cannot because no machine here runs its architecture, and the entry a build is
# allowed to drop.
#
# The report script is a fact about this fixture and stays here. So does the
# realisation statement: nothing in a plan says whether an entry wants an image
# or a flakelet artifact, and this folder wants images. The host paths are the
# watching module's own, derived there from the identity of its entry.
{
  pkgs,
  planner,
  operator,
}:
let
  reportOf =
    delivery:
    pkgs.writeShellScript "planner-portable-report" ''
      set -u
      printf 'assembled-begin\n'
      ${pkgs.coreutils}/bin/cat "$ASSEMBLED"
      printf 'assembled-end\n'
      printf 'identity: uid=%s\n' "$(${pkgs.coreutils}/bin/id -u)"
      if original=$(${pkgs.coreutils}/bin/cat "$ORIGINAL" 2>&1); then
        printf 'original-read: succeeded with %s\n' "$original"
      else
        printf 'original-read: %s\n' "$original"
      fi
      if secret=$(${pkgs.coreutils}/bin/cat "$SECRET" 2>&1); then
        printf 'secret-read: succeeded with %s\n' "$secret"
      else
        printf 'secret-read: %s\n' "$secret"
      fi
      printf 'delivery: %s\n' ${delivery}
      exec ${pkgs.coreutils}/bin/sleep infinity
    '';

  # The long-running unit of `beacon:ping`, which writes the one file its module
  # derives and then stays up. Everything it runs is a reference of it.
  beaconScript = pkgs.writeShellScript "planner-portable-beacon" ''
    set -u
    printf 'beacon up\n' > "$1"
    exec ${pkgs.coreutils}/bin/sleep infinity
  '';

  # The probe of the `probed` build below, which refuses whatever it reads: the
  # failure is what that build is for, and a probe that could pass would make
  # the phase's evidence a race with the unit it probes.
  refusingProbe = pkgs.writeShellScript "planner-portable-probe" ''
    set -u
    printf 'probe: %s does not say this service is serving\n' "$1" >&2
    exit 1
  '';

  interfaces = import ./interfaces/default.nix { korora = planner.korora; };
  inherit (interfaces) reportFile;

  # The one extension field the confined unit needs: membership of the group the
  # secret is delivered to, because the profile gives it no static account.
  grouped = planner.unitExtension {
    backend = "systemd";
    name = "systemd-service";
    fields = {
      supplementaryGroups = {
        type = planner.korora.listOf planner.korora.string;
      };
    };
  };

  reportModuleOf = delivery: {
    services.default = import ./modules/report/default.nix {
      report = "${reportOf delivery}";
      inherit reportFile grouped;
    };
  };

  mirrorModule = {
    services.default = import ./modules/mirror/default.nix {
      coreutils = "${pkgs.coreutils}";
      inherit reportFile;
    };
  };

  beaconModuleOf = probeCommand: {
    services.default = import ./modules/beacon/default.nix {
      beacon = "${beaconScript}";
      inherit probeCommand;
    };
  };

  registry = import ./machines.nix;

  # One statement per instance rather than one table, so a build that drops an
  # instance drops its statement with it: a statement naming a key the plan does
  # not carry is a row of its own.
  #
  # `watch:file` is stated strict because the enforcement is the claim under
  # test. `mirror:copy` is never attached and `beacon:ping` is attached and then
  # retired, so both take the default profile.
  statements = {
    watch."watch:file" = {
      realiser = "image";
      profile = "strict";
    };
    mirror."mirror:copy" = {
      realiser = "image";
      profile = "default";
    };
    beacon."beacon:ping" = {
      realiser = "image";
      profile = "default";
    };
  };

  buildOf =
    {
      delivery,
      probeCommand ? null,
      drop ? [ ],
    }:
    operator.mkDeployment {
      inherit pkgs planner;

      realise = builtins.foldl' (stated: kept: stated // kept) { } (
        builtins.attrValues (builtins.removeAttrs statements drop)
      );

      args =
        let
          deployment = import ./instances.nix {
            report = reportModuleOf delivery;
            mirror = mirrorModule;
            beacon = beaconModuleOf probeCommand;
          };
        in
        {
          instances = builtins.removeAttrs deployment.instances drop;
          inherit (registry) machines;

          varsState."watch:vars/upstream".secret.present = true;

          interfaces = {
            "interfaces/default.nix" = interfaces;
          };

          sources = {
            deployment = "instances.nix";
            machines = "machines.nix";
            modules = {
              watch = "report/default.nix";
              mirror = "mirror/default.nix";
              beacon = "beacon/default.nix";
            };
            leaves = {
              watch.file = "report/watch.nix";
              mirror.copy = "mirror/copy.nix";
              beacon.ping = "beacon/ping.nix";
            };
          };
        };
    };
in
{
  default = buildOf { delivery = "first"; };

  # A second build of the same deployment, whose unit runs another script and so
  # carries another identity. Nothing attaches it: what a report says about a
  # machine holding an earlier build needs two identities and one machine.
  changed = buildOf { delivery = "second"; };

  # The same deployment without `beacon`, so the image the machine holds for
  # that entry is a holding this build names nothing for while `watch:file` is
  # still named, still placed and still reachable.
  retired = buildOf {
    delivery = "first";
    drop = [ "beacon" ];
  };

  # The same deployment whose `beacon` declares a probe that refuses. This
  # realiser starts the probe at attach and has no generation to return to, so
  # applying this build is a failed step over a machine that stays attached.
  probed = buildOf {
    delivery = "first";
    probeCommand = "${refusingProbe}";
  };
}
