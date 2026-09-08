# The three entries of the cluster deployment, built by the flakelet realiser.
#
# Two plans rather than one: the same source with a different served file, which
# is a different unit, a different key and therefore a different identity to the
# endpoint. That is what the redelivery requirement is asserted against, and it
# is produced here rather than by editing anything at run time.
{
  pkgs,
  planner,
  flakeletBuilder,
}:
let
  packagesWith = pageDir: {
    python3 = "${pkgs.python3Minimal}";
    curl = "${pkgs.curl}";
    coreutils = "${pkgs.coreutils}";
    page = pageDir;
  };

  planWith =
    pageDir:
    planner.mkPlan
      (import ./deployment {
        inherit planner;
        packages = packagesWith "${pageDir}";
      }).args;

  pageDirOf =
    name: text:
    pkgs.writeTextFile {
      name = "cluster-page-${name}";
      destination = "/index.html";
      inherit text;
    };

  pages = {
    first = pageDirOf "first" "cluster page, first delivery\n";
    second = pageDirOf "second" "cluster page, second delivery\n";
  };

  first = planWith pages.first;
  second = planWith pages.second;

  serverKey = "site:server@alpha";
  clientKey = "check:client@beta";
  sweepKey = "sweep:job@alpha";

  artifactOf =
    result: key:
    flakeletBuilder.artifact {
      plan = result.plan;
      inherit key;
    };

  entries = {
    site = artifactOf first serverKey;
    check = artifactOf first clientKey;
    site-changed = artifactOf second serverKey;
    sweep = artifactOf first sweepKey;
  };

  planFile =
    name: result: pkgs.writeText "planner-cluster-${name}.json" (builtins.toJSON result.plan);
in
(pkgs.linkFarm "planner-cluster-artifacts" (
  [
    {
      name = "plan.json";
      path = planFile "plan" first;
    }
    {
      name = "plan-changed.json";
      path = planFile "plan-changed" second;
    }
  ]
  ++ map (name: {
    inherit name;
    path = entries.${name};
  }) (builtins.attrNames entries)
)).overrideAttrs
  (old: {
    passthru = (old.passthru or { }) // {
      inherit entries;
      plan = first;
      planChanged = second;
      keys = {
        server = serverKey;
        client = clientKey;
        sweep = sweepKey;
      };
      pages = builtins.mapAttrs (_: p: "${p}") pages;
    };
  })
