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

  # vale exits non-zero only for error-level rules, so without this wrapper treefmt
  # would throw away every warning vale printed.
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
  projectRootFile = "flake.nix";
  programs.deadnix.enable = true;
  programs.nixfmt.enable = true;
  programs.shellcheck.enable = true;
  programs.yamlfmt.enable = true;

  programs.ruff-check.enable = true;
  programs.ruff-format.enable = true;
  programs.mypy.enable = true;

  # One run per directory of top-level modules, because that is what each import
  # expects beside it: check_test.py imports check, test_harness.py imports delivery.
  programs.mypy.directories = {
    "perf".options = [ "--strict" ];

    "tests/e2e" = {
      options = [ "--strict" ];
      extraPythonPackages = [ pkgs.python3Packages.pytest ];
    };

    # mypy descends into a subdirectory only when it is a package, and these two are
    # not. Naming them as roots is what gets them checked at all. The name is a label
    # rather than a path.
    "e2e-folders" = {
      directory = "tests/e2e";
      modules = [
        "wired-pair"
        "portable-image"
        "secret-delivery"
      ];
      options = [ "--strict" ];
      extraPythonPackages = [ pkgs.python3Packages.pytest ];
    };
  };

  settings.global.excludes = [
    # The suites evaluate this folder as committed and compare a golden plan field
    # by field, so a formatter here would edit a test's subject.
    "fixtures/**"
    # Written change records, and command documents the openspec CLI installs.
    "openspec/**"
    ".omp/**"
    "**/__pycache__/*"
    "**/.mypy_cache/*"
    "**/.ruff_cache/*"
    "**/.pytest_cache/*"
  ];

  settings.formatter.vale = {
    command = lib.getExe valeLint;
    includes = [ "*.md" ];
  };

  # No vulture and no harper. Vulture's only finding is an interface parameter name in
  # tests/e2e/delivery.py, and harper flags realiser, flakelet and keyset.
}
