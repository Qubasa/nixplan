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
