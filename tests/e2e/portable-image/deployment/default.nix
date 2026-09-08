# The only glue: close the package strings, import this directory's own
# interfaces, modules and deployment, and hand `mkPlan` its arguments.
#
# `paths` are the machine's own: where the operator's file is, where the entry's
# assembled copy is shown to its unit, and the path the confined unit tries to
# write. They are deployment facts rather than module ones, which is why they
# arrive here and not from a module's defaults.
{
  planner,
  packages,
  paths,
}:
let
  inherit (packages) coreutils report;

  interfaces = import ./interfaces/default.nix { korora = planner.korora; };
  inherit (interfaces) reportFile;

  reportModule = {
    services.default = import ./modules/report/default.nix {
      inherit
        report
        reportFile
        paths
        ;
    };
  };

  mirrorModule = {
    services.default = import ./modules/mirror/default.nix {
      inherit coreutils reportFile;
    };
  };

  deployment = import ./instances.nix {
    report = reportModule;
    mirror = mirrorModule;
  };
  registry = import ./machines.nix;
in
{
  inherit interfaces;

  args = {
    inherit (deployment) instances;
    inherit (registry) machines;

    interfaces = {
      "interfaces/default.nix" = interfaces;
    };

    # Row subjects: a module file relative to modules/, everything else relative
    # to this directory.
    sources = {
      deployment = "instances.nix";
      machines = "machines.nix";
      modules = {
        watch = "report/default.nix";
        mirror = "mirror/default.nix";
      };
      leaves = {
        watch.file = "report/watch.nix";
        mirror.copy = "mirror/copy.nix";
      };
    };
  };
}
