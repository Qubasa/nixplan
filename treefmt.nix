# treefmt.nix
{ pkgs, lib, ... }:
let
  benBalterStyles = pkgs.fetchFromGitHub {
    owner = "benbalter";
    repo = "vale-styles";
    rev = "v0.0.3";
    hash = "sha256-8giIiK/nv0uJubsZdSVNut2WA4J4YFjP1NTGs9tTKms=";
  };

  writeGoodStyles = pkgs.fetchFromGitHub {
    owner = "vale-cli";
    repo = "write-good";
    rev = "v0.4.1";
    hash = "sha256-W/eHlXklAVlAnY8nLPi/SIKsg8UUnH8UkH99BDo5yKk=";
  };

  valeStyles = pkgs.linkFarm "vale-styles" {
    BenBalter = "${benBalterStyles}/BenBalter";
    write-good = "${writeGoodStyles}/write-good";
    Universe = ./styles/Universe;
  };

  valeConfig = pkgs.writeText "vale.ini" ''
    StylesPath = ${valeStyles}
    MinAlertLevel = warning

    [*.md]
    BasedOnStyles = BenBalter, write-good, Universe
    write-good.E-Prime = NO
    write-good.Passive = suggestion
    write-good.TooWordy = suggestion
  '';

  # vale only sets a nonzero exit code for error-level rules, so treefmt would
  # otherwise throw away every warning vale printed.
  valeLint = pkgs.writeShellApplication {
    name = "vale-lint";
    runtimeInputs = [ pkgs.vale ];
    text = ''
      status=0
      alerts=$(vale --config=${valeConfig} --output=line --no-wrap "$@" 2>&1) || status=$?
      if [ -n "$alerts" ]; then
        printf '%s\n' "$alerts"
        status=1
      fi
      exit "$status"
    '';
  };
in
{
  # Used to find the project root
  projectRootFile = "flake.nix";
  programs.deadnix.enable = true;
  programs.nixfmt.enable = true;
  programs.shellcheck.enable = true;
  programs.yamlfmt.enable = true;

  # Python. This repository owns no python package, so ruff's rules are in
  # `ruff.toml` at the root and mypy's are here. Both used to be flags on a
  # `nix build` check, where an edit was only told about them by a build.
  programs.ruff-check.enable = true;
  programs.ruff-format.enable = true;
  programs.mypy.enable = true;

  # One run per directory of top-level modules, because that is what each
  # import expects to be beside: `check_test.py` imports `check`, and
  # `test_harness.py` imports `delivery` and `runner`.
  programs.mypy.directories = {
    "perf".options = [ "--strict" ];

    "tests/e2e" = {
      options = [ "--strict" ];
      extraPythonPackages = [ pkgs.python3Packages.pytest ];
    };

    # mypy descends into a subdirectory only when it is a package, and these
    # two are not: pytest imports each `test_<folder>.py` as a top-level
    # module. Naming them as roots is what gets them checked at all, and the
    # run is from `tests/e2e` so their `import delivery` resolves as it does
    # under pytest. The name is a label rather than a path, because a path this
    # repository names has to resolve (`tests/unit/layers.nix`).
    "e2e-folders" = {
      directory = "tests/e2e";
      modules = [
        "wired-pair"
        "portable-image"
      ];
      options = [ "--strict" ];
      extraPythonPackages = [ pkgs.python3Packages.pytest ];
    };
  };

  # No vulture, which rookery runs beside these three: its only finding on this
  # tree is `cmd` in the `Namespace` protocol (tests/e2e/delivery.py), where the
  # parameter name is the interface rookery's `Cluster.run` is called through
  # rather than a dead local.

  settings.global.excludes = [
    # The worked deployment is a fixture: the suites evaluate it as committed
    # and compare a golden plan field by field, so a formatter rewriting it
    # would be editing a test's subject.
    "fixtures/**"
    # Specifications, proposals and task records. They are the written history
    # of a change and are edited through the openspec workflow, so prose rules
    # aimed at documentation would rewrite a record after the fact.
    "openspec/**"
    # The openspec workflow's own command and skill documents, installed by its
    # CLI rather than written here. Formatting them would rewrite a vendored
    # file that the next install overwrites.
    ".omp/**"
    # Tool caches. They are gitignored, so this only matters for a tree that
    # has run pytest, ruff or mypy in place.
    "**/__pycache__/*"
    "**/.mypy_cache/*"
    "**/.ruff_cache/*"
    "**/.pytest_cache/*"
  ];

  settings.formatter.vale = {
    command = lib.getExe valeLint;
    includes = [ "*.md" ];
  };

  # No harper: its findings on this prose are `realiser`, `flakelet`, `keyset`
  # and heading capitalisation, and the two grammar rules that do fire are
  # false positives ("a uid", "every one that is missing"). The prose rules
  # this project holds itself to are the vale styles above.
}
