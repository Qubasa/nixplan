{ inputs, ... }:
let
  # korora is pinned as a source, so types.nix is the entry point. Importing the
  # flake's default.nix warns instead.
  korora = import "${inputs.korora}/types.nix";
  systems = inputs.nixpkgs.lib.systems;
  nixpkgsLib = inputs.nixpkgs.lib;
  platformSource = inputs.nixpkgs.rev;
  folder = ./fixtures/minimal-typed-edge;
  planner = import ./lib { inherit korora systems platformSource; };
  worked = planner.mkPlan (import ./tests/unit/worked.nix { inherit planner folder; }).args;
  openspecRoot = ./openspec;
  imageSource = ./image;
  secretsSource = ./secrets;
  flakeletSource = ./flakelet;
  operatorSource = ./operator;
  suites = import ./tests {
    inherit
      korora
      systems
      nixpkgsLib
      platformSource
      folder
      openspecRoot
      ;
    libSource = ./lib;
    inherit
      imageSource
      secretsSource
      flakeletSource
      operatorSource
      ;
    perfSource = ./perf;
    repoSource = ./.;
  };

  # The counterexample probes, named rather than listed by hand: each is
  # evaluated in its own process by `checks.planner-counterexamples-eval`,
  # because an uncatchable raise takes the run that would report it.
  probes = import ./tests/counterexamples/probes.nix {
    inherit
      planner
      imageSource
      flakeletSource
      operatorSource
      secretsSource
      ;
  };
in
{
  flake.lib = planner;

  # The library elaborated against a caller's own platform definitions. `flake.lib`
  # is the pin this flake carries, applied and recorded, and this is the way out of
  # it: a consumer following another package set hands its own `lib.systems` here
  # and states the identity beside it, so one package set decides every entry key
  # instead of two.
  flake.mkLib =
    {
      systems,
      platformSource ? null,
    }:
    import ./lib { inherit korora systems platformSource; };

  # The deployment build, published for a consumer that is not this repository.
  # `flake.lib` alone leaves a caller able to plan and unable to build, and the
  # only other reach is a path inside this flake's source, which is not an
  # interface. `mkDeployment` takes the caller's own `pkgs`, so it is a
  # system-independent output like the library beside it.
  flake.operator = import ./operator { korora = inputs.korora; };

  # The suites, their failures and the worked plan, under a name no application and
  # no package uses. `planner` is the command.
  flake.debug = {
    inherit worked suites;
    rendered = planner.render worked.diagnostics;
    failures = import ./tests/report.nix suites;
    failuresBySuite = builtins.mapAttrs (_: suite: import ./tests/report.nix suite) suites;
  };

  perSystem =
    {
      config,
      pkgs,
      system,
      ...
    }:
    let
      suite = pkgs.writeText "planner-suite.nix" ''
        import ${./tests} {
          korora = import ${inputs.korora}/types.nix;
          systems = (import ${inputs.nixpkgs}/lib).systems;
          nixpkgsLib = import ${inputs.nixpkgs}/lib;
          platformSource = "${platformSource}";
          folder = ${folder};
          libSource = ${./lib};
          imageSource = ${./image};
          secretsSource = ${./secrets};
          flakeletSource = ${./flakelet};
          operatorSource = ${./operator};
          perfSource = ${./perf};
          repoSource = ${./.};
          openspecRoot = ${openspecRoot};
        }
      '';

      # Named separately rather than sliced out of one copy of the tree, so editing a
      # document does not invalidate a recorded measurement.
      perfRoot = ./perf;
      libRoot = ./lib;
      workedLoader = ./tests/unit/worked.nix;

      measurement =
        pkgs.runCommand "planner-perf-results"
          {
            nativeBuildInputs = [
              pkgs.jq
              pkgs.nix
            ];
          }
          ''
            export HOME="$(mktemp -d)"
            export NIX_CONFIG="experimental-features = nix-command"
            mkdir -p "$out"
            bash ${perfRoot}/measure.sh \
              --korora ${inputs.korora} \
              --nixpkgs ${inputs.nixpkgs} \
              --root ${perfRoot} \
              --lib ${libRoot} \
              --folder ${folder} \
              --worked ${workedLoader} \
              --out "$out"
          '';

      perf = pkgs.writeShellApplication {
        name = "planner-perf";
        runtimeInputs = [
          pkgs.jq
          pkgs.python3
          pkgs.nix
        ];
        text = ''
          out=$(mktemp -d)
          trap 'rm -rf "$out"' EXIT
          bash ${perfRoot}/measure.sh --korora "${inputs.korora}" \
            --nixpkgs "${inputs.nixpkgs}" --root ${perfRoot} \
            --lib ${libRoot} --folder ${folder} --worked ${workedLoader} \
            --out "$out" "$@"
          python3 ${perfRoot}/check.py --results "$out" --budgets ${perfRoot}/budgets.json
        '';
      };

      pytestEnv = import ./pytest-env.nix pkgs;

      # The one function that builds a deployment, handed to every folder as an
      # argument. A folder resolves no path outside itself, which is what the
      # end-to-end path scan holds it to.
      operator = import ./operator { korora = inputs.korora; };

      # The published leaf modules, handed to every folder the same way, so a
      # folder composes what a consumer outside this checkout composes rather
      # than a module of its own that nothing outside it can name.
      coordination = import ./published/coordination;

      e2eRoot = ./tests/e2e;

      # Discovery rather than registration: a folder holding a deployment is a
      # package of this flake without a line here, the way the runner already
      # finds a folder's tests by looking.
      e2eFolders = builtins.filter (
        name: builtins.pathExists (e2eRoot + "/${name}/deployment/default.nix")
      ) (builtins.attrNames (builtins.readDir e2eRoot));

      # What every folder is handed, and what a folder is handed only where it
      # names it. A published module goes in the second set, so handing it to
      # every folder widens the argument pattern of none of the folders that
      # compose one of nothing.
      e2eArguments = {
        inherit pkgs planner operator;
      };

      e2eOffered = e2eArguments // {
        inherit coordination;
      };

      # `builtins.functionArgs` answers `{ }` for a lambda with no attribute
      # pattern, and a folder whose deployment is `args: …` forwards whatever it
      # was handed to a deployment of its own whose pattern is closed - so such
      # a folder is handed the base set rather than the offered one, and naming
      # a published module is what asks for it.
      buildsOf =
        folder:
        let
          deployment = import (e2eRoot + "/${folder}/deployment/default.nix");
          named = builtins.functionArgs deployment;
        in
        deployment (if named == { } then e2eArguments else builtins.intersectAttrs named e2eOffered);

      # A folder's `default` build is the folder's own package name; any other
      # build of the same folder is suffixed with its own.
      e2eDeployments = builtins.listToAttrs (
        builtins.concatLists (
          map (
            folder:
            pkgs.lib.mapAttrsToList (build: deployment: {
              name = "planner-e2e-${folder}" + (if build == "default" then "" else "-${build}");
              value = deployment;
            }) (buildsOf folder)
          ) e2eFolders
        )
      );

      e2eGuest = import ./tests/e2e/guest.nix {
        inherit (pkgs) lib;
        inherit pkgs system;
        nixpkgs = inputs.nixpkgs;
        flakeletModule = inputs.flakelet.nixosModules.flakelet;
        # The machine module this repository publishes, imported by the guest
        # rather than restated in it: the machines under test and a reader's
        # own machine are one text, so a fact added to the declaration cannot
        # be forgotten here.
        provisioningModule = import ./published/provisioning;
      };

      lemmalog = pkgs.callPackage ./lemmalog.nix { };

      # One row per variable a machine-layer run reads off a built artifact. The app
      # exports every row and `planner-e2e-env` prints the same rows out of the two
      # files below, so neither can name an artifact the other does not. A
      # deployment is absent on purpose: the machine layer builds one with the
      # command, so no link farm is forced before pytest starts.
      e2eToolArtifactPaths = {
        PLANNER_CLI = pkgs.lib.getExe config.packages.planner;
        PLANNER_CLI_SRC = "${config.packages.planner-src}";
        PLANNER_TAILSCALE = "${pkgs.tailscale}";
      };

      # These two rows force the guest's own NixOS evaluation, which is 8 of the 9
      # seconds an uncached `planner-e2e-env` spends. They are a file of their own so
      # that a shell being entered can print the rows it needs without evaluating a
      # disk image it is not about to boot.
      e2eGuestArtifactPaths = {
        PLANNER_E2E_GUEST_IMAGE = "${e2eGuest}/nixos.qcow2";
        PLANNER_E2E_SSH_KEY = "${e2eGuest.sshPrivateKey}";
      };

      e2eArtifactPaths = e2eToolArtifactPaths // e2eGuestArtifactPaths;

      envNameOf = folder: pkgs.lib.toUpper (builtins.replaceStrings [ "-" ] [ "_" ] folder);

      # The declaration of each folder is the one variable that names the working
      # tree in the shell and the store in the app, so both come out of one attrset
      # rather than being written twice. `store` is that subtree alone: naming the
      # checkout root instead would put every file in the runner's closure.
      e2eDeploymentPaths = builtins.listToAttrs (
        map (folder: {
          name = "PLANNER_${envNameOf folder}_DEPLOYMENT";
          value = {
            store = e2eRoot + "/${folder}/deployment";
            rel = "tests/e2e/${folder}/deployment";
          };
        }) e2eFolders
      );

      exportsOf =
        paths:
        pkgs.lib.concatStrings (pkgs.lib.mapAttrsToList (name: path: "export ${name}=${path}\n") paths);

      e2eExports = exportsOf e2eArtifactPaths;

      e2eToolPaths = pkgs.writeText "planner-e2e-tool-paths" (exportsOf e2eToolArtifactPaths);

      e2eGuestEnvPaths = pkgs.writeText "planner-e2e-guest-paths" (exportsOf e2eGuestArtifactPaths);

      # The attribute is named as a string and built when the script runs. An
      # interpolation here would put the guest image in the closure of every shell
      # this script is in, and entering the checkout would build it.
      e2eEnvScript = pkgs.writeShellApplication {
        name = "planner-e2e-env";
        runtimeInputs = [
          pkgs.git
          pkgs.nix
        ];
        text = ''
          guest=yes
          for arg in "$@"; do
            case "$arg" in
              --without-guest) guest=no ;;
              *)
                echo "planner-e2e-env: $arg is no argument of this command: the only one is --without-guest, which prints every row but the guest image's" >&2
                exit 2
                ;;
            esac
          done

          # Every path this prints is a path in the working tree, so a working tree
          # of this repository is what it needs. `git rev-parse --show-toplevel`
          # answers about the caller's own directory, and continuing on its answer
          # printed `export PLANNER_E2E=/tests/e2e` from anywhere else.
          if ! root="$(git rev-parse --show-toplevel 2> /dev/null)"; then
            echo "planner-e2e-env: $PWD is in no git checkout, and this prints the paths of one: run it from a checkout of nixplan" >&2
            exit 1
          fi
          if ! cmp -s "$root/flake.nix" ${./flake.nix}; then
            echo "planner-e2e-env: $root is not a checkout of nixplan, and this prints that checkout's own paths: its flake.nix is not the one this command was built from" >&2
            exit 1
          fi
          attrs=("$root#planner-e2e-tool-paths")
          if [ "$guest" = yes ]; then
            attrs+=("$root#planner-e2e-guest-paths")
          fi
          mapfile -t built < <(nix build --no-link --print-out-paths "''${attrs[@]}")
          cat "''${built[@]}"
          printf 'export PLANNER_E2E_FLAKE=%q\n' "$root"
          ${pkgs.lib.concatStrings (
            pkgs.lib.mapAttrsToList (
              name: paths: "printf 'export ${name}=%q\\n' \"$root/${paths.rel}\"\n"
            ) e2eDeploymentPaths
          )}
          if ! ${pytestEnv}/bin/python3 ${./tests/e2e/runner.py} --print-env; then
            echo "planner-e2e-env: no rookery, so the end-to-end tests will skip themselves" >&2
          fi
          if [ "$guest" = no ]; then
            echo "planner-e2e-env: --without-guest, so \$PLANNER_E2E_GUEST_IMAGE and \$PLANNER_E2E_SSH_KEY are unset and every machine-layer folder skips itself: run planner-e2e-env with no argument before pytest" >&2
          fi
        '';
      };

      # The invariant index as a queryable store. The corpus under
      # `docs/lemmalog/` is the source; the store is derived and gitignored, for
      # the reason the golden plan is regenerated by a command rather than edited:
      # the engine writes derived facts and episodes into it on every load.
      lemmalogLoader = pkgs.writeShellApplication {
        name = "planner-lemmalog";
        runtimeInputs = [
          lemmalog
          pkgs.git
        ];
        text = ''
          reload=no
          for arg in "$@"; do
            case "$arg" in
              --reload) reload=yes ;;
              *)
                echo "planner-lemmalog: $arg is no argument of this command: the only one is --reload, which rebuilds the store from the corpus" >&2
                exit 2
                ;;
            esac
          done

          # The corpus an edit is in is the checkout's, and the store copy is what
          # a shell entered from anywhere else has. The same reading the shell
          # itself does, for the same reason.
          facts=${./docs/lemmalog}
          if root="$(git rev-parse --show-toplevel 2> /dev/null)" &&
            cmp -s "$root/flake.nix" ${./flake.nix}; then
            facts="$root/docs/lemmalog"
          fi

          store="''${LEMMALOG_MCP_PATH:-$PWD/.direnv/lemmalog.store}"
          if [ -e "$store" ] && [ "$reload" = no ]; then
            echo "planner-lemmalog: $store already holds the index, loaded from $facts: --reload rebuilds it from the corpus" >&2
            exit 0
          fi
          mkdir -p "$(dirname "$store")"
          rm -f "$store"
          export LEMMALOG_MCP_PATH="$store"

          for file in "$facts"/*.facts; do
            lemmalog-cli observe --facts "$(cat "$file")"
          done

          # One paragraph of the corpus is one batch, so an analysis that dies is
          # uninstalled by itself rather than with the four beside it.
          batch=""
          while IFS= read -r line; do
            case "$line" in
              '%'*) continue ;;
            esac
            if [ -z "$line" ]; then
              if [ -n "$batch" ]; then
                lemmalog-cli rules --rules "$batch"
                batch=""
              fi
              continue
            fi
            batch="$batch$line"$'\n'
          done < "$facts/rules.dl"
          if [ -n "$batch" ]; then
            lemmalog-cli rules --rules "$batch"
          fi

          echo "planner-lemmalog: $store" >&2
        '';
      };

      e2eRunner = pkgs.writeShellApplication {
        name = "planner-e2e";
        runtimeInputs = [
          pkgs.git
          pkgs.nix
          pkgs.openssh
        ];
        text = ''
          ${e2eExports}
          ${pkgs.lib.concatStrings (
            pkgs.lib.mapAttrsToList (name: paths: "export ${name}=${paths.store}\n") e2eDeploymentPaths
          )}
          # `planner build` resolves a flake reference, so the checkout is what it
          # is given. A run from outside one sets nothing and the folders skip.
          if root="$(git rev-parse --show-toplevel 2> /dev/null)"; then
            export PLANNER_E2E_FLAKE="$root"
          fi
          export PLANNER_E2E=${./tests/e2e}
          exec ${pytestEnv}/bin/python3 ${./tests/e2e/runner.py} "$@"
        '';
      };

      # The probes of tests/counterexamples/, one `nix eval` each. A probe that
      # answers "ok" holds; one that raises is a deployment the library ends the
      # evaluation over where a diagnostics row is owed, and the raise is what a
      # nix-unit `expr` cannot assert - it would take the run reporting it.
      probeFile = pkgs.writeText "planner-counterexamples.nix" ''
        import ${./tests/counterexamples/probes.nix} {
          planner = import ${./lib} {
            korora = import ${inputs.korora}/types.nix;
            systems = (import ${inputs.nixpkgs}/lib).systems;
            platformSource = "${platformSource}";
          };
          imageSource = ${imageSource};
          flakeletSource = ${flakeletSource};
          operatorSource = ${operatorSource};
          secretsSource = ${secretsSource};
        }
      '';

    in
    {
      checks.planner-tests =
        pkgs.runCommand "planner-tests"
          {
            nativeBuildInputs = [ pkgs.nix-unit ];
          }
          ''
            export HOME="$(mktemp -d)"
            nix-unit --eval-store "$HOME" ${suite}
            touch "$out"
          '';

      checks.planner-counterexamples-eval =
        pkgs.runCommand "planner-counterexamples-eval"
          {
            nativeBuildInputs = [ pkgs.nix ];
          }
          ''
            export HOME="$(mktemp -d)"
            export NIX_CONFIG="experimental-features = nix-command"
            broke=0
            for name in ${pkgs.lib.concatStringsSep " " (builtins.attrNames probes)}; do
              if said="$(nix eval --eval-store "$HOME" --raw \
                  --file ${probeFile} --apply "p: p.$name" 2>&1)"; then
                printf 'ok      %s\n' "$name"
              else
                printf 'raises  %s\n' "$name"
                printf '%s\n' "$said" | sed -n 's/^ *\(error: .*\)$/        \1/p'
                broke=1
              fi
            done
            if [ "$broke" = 1 ]; then
              echo "each probe above ends an evaluation where a row is owed: tests/counterexamples/README.md" >&2
              exit 1
            fi
            touch "$out"
          '';

      # The operator's command, against the invariants it states about itself.
      # Red for the same reason the suite above is: each test asserts the claim.
      checks.planner-counterexamples-cli =
        pkgs.runCommand "planner-counterexamples-cli"
          {
            nativeBuildInputs = [ pytestEnv ];
          }
          ''
            export PYTHONPATH=${./cli}
            python3 -m pytest -q -rs --no-header -p no:cacheprovider ${./cli}/counterexample_test.py
            touch "$out"
          '';

      checks.planner-perf =
        pkgs.runCommand "planner-perf"
          {
            nativeBuildInputs = [ pkgs.python3 ];
          }
          ''
            python3 ${perfRoot}/check.py --results ${measurement} --budgets ${perfRoot}/budgets.json
            touch "$out"
          '';

      checks.planner-perf-checker =
        pkgs.runCommand "planner-perf-checker"
          {
            nativeBuildInputs = [ pkgs.python3 ];
          }
          ''
            cp ${./perf}/check.py ${./perf}/check_test.py .
            python3 -m unittest discover -s . -p 'check_test.py' -v
            touch "$out"
          '';

      checks.planner-delivery =
        pkgs.runCommand "planner-delivery"
          {
            nativeBuildInputs = [ pytestEnv ];
          }
          ''
            export PYTHONPATH=${./cli}
            python3 -m pytest -q -rs --no-header -p no:cacheprovider ${./tests/e2e}/test_harness.py
            touch "$out"
          '';

      packages = e2eDeployments // {
        # The authoring vocabulary as one file a program reads without evaluating
        # anything of its own. A projection and not a validator: it names what a
        # declaration may carry, and whether one value satisfies its type is
        # `planner diagnose`'s answer.
        planner-schema = pkgs.writeText "planner-schema.json" (builtins.toJSON planner.vocabulary);
        planner-perf = perf;
        planner-perf-results = measurement;
        planner-e2e-guest = e2eGuest;
        planner-e2e-env = e2eEnvScript;
        planner-e2e-tool-paths = e2eToolPaths;
        planner-e2e-guest-paths = e2eGuestEnvPaths;
        planner-lemmalog = lemmalogLoader;
        inherit lemmalog;
      };

      # An app rather than a check: a build sandbox has no tun device and no vhost-vsock,
      # and cannot ask the daemon whether a path is valid, which is what a delivery does
      # first.
      apps.planner-e2e = {
        type = "app";
        program = "${e2eRunner}/bin/planner-e2e";
        meta.description = "Run the planner's end-to-end tests on real machines";
      };
    };
}
