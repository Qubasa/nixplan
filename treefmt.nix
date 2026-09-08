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

  programs.mypy.directories = {
    "perf".options = [ "--strict" ];

    "tests/e2e" = {
      options = [ "--strict" ];
      extraPythonPackages = [ pkgs.python3Packages.pytest ];
    };

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


  settings.global.excludes = [
    "fixtures/**"
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

}
