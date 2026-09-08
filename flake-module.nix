{ inputs, ... }:
let
  # korora is pinned as a source input, so the non-deprecated entry point is
  # types.nix. Importing the flake's default.nix warns instead.
  korora = import "${inputs.korora}/types.nix";
  systems = inputs.nixpkgs.lib.systems;
  folder = ./fixtures/minimal-typed-edge;
  planner = import ./lib { inherit korora systems; };
  worked = planner.mkPlan (import ./tests/unit/worked.nix { inherit planner folder; }).args;
  changesRoot = ./openspec/changes;
  imageSource = ./image;
  flakeletSource = ./flakelet;
  suites = import ./tests {
    inherit
      korora
      systems
      folder
      changesRoot
      ;
    libSource = ./lib;
    inherit imageSource flakeletSource;
    perfSource = ./perf;
    repoSource = ./.;
  };
in
{
  flake.lib = planner;

  # The worked deployment, evaluated. This is what the golden fixture is
  # regenerated from and what a reader inspects with
  # `nix eval .#planner.worked.diagnostics`.
  flake.planner = {
    inherit worked suites;
    rendered = planner.render worked.diagnostics;
    failures = import ./tests/report.nix suites;
    failuresBySuite = builtins.mapAttrs (_: suite: import ./tests/report.nix suite) suites;
  };

  perSystem =
    { pkgs, system, ... }:
    let
      suite = pkgs.writeText "planner-suite.nix" ''
        import ${./tests} {
          korora = import ${inputs.korora}/types.nix;
          systems = (import ${inputs.nixpkgs}/lib).systems;
          folder = ${folder};
          libSource = ${./lib};
          imageSource = ${./image};
          flakeletSource = ${./flakelet};
          perfSource = ${./perf};
          repoSource = ${./.};
          changesRoot = ${changesRoot};
        }
      '';

      # The four inputs the measured evaluation reads, named separately rather
      # than sliced out of one copy of the tree: a measurement's identity is the
      # code it measured, so editing a document does not invalidate a recorded
      # result. `workedLoader` is here because `eval.nix` cannot reach it
      # relatively once the copy is this narrow.
      perfRoot = ./perf;
      libRoot = ./lib;
      workedLoader = ./tests/unit/worked.nix;

      # One measurement per fixture and size. The measured evaluation reads no
      # flake, writes to no store and needs no network, so it runs in the
      # sandbox on caches that are empty by construction.
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

      # pytest is new in this repository: assertion rewriting is what names the
      # field that differs without any comparison code to maintain.
      pytestEnv = pkgs.python3.withPackages (ps: [ ps.pytest ]);

      # The cluster suite imports rookery through `PYTHONPATH`, which only holds
      # within one python minor version, so its environment is built on the
      # interpreter rookery is built for rather than on `pkgs.python3`. Measured:
      # rookery is python 3.13 while `nixos-unstable`'s `python3` is 3.14. The
      # runner compares the two at run time and refuses with both named
      # (design.md D4), so a rookery bump surfaces here as a named refusal.
      clusterPytestEnv = pkgs.python313.withPackages (ps: [ ps.pytest ]);

      # The image builder, and the artifact its check asserts against. The
      # worked deployment's two packages arrive as real ones there: the
      # fixture's literal strings name bytes that were never built, and an
      # image is bytes.
      imageBuilder = import ./image {
        inherit (pkgs) lib;
        inherit pkgs planner;
      };

      # The second realiser over the same plan: a store-backed service artifact
      # a real endpoint activates, rather than an image something attaches.
      flakeletBuilder = import ./flakelet {
        inherit pkgs planner;
      };

      # The wired-pair deployment, realised. Its plan is the subject of that
      # folder's test; the artifacts are what a machine is handed.
      wiredPairArtifacts = import ./tests/e2e/wired-pair/artifacts.nix {
        inherit pkgs planner flakeletBuilder;
      };

      # The portable-image deployment, realised by the other realiser: two
      # images, one attachable on the machine the run boots and one built for a
      # machine it is not.
      portableImageArtifacts = import ./tests/e2e/portable-image/artifacts.nix {
        inherit pkgs planner imageBuilder;
      };

      # The guest every end-to-end machine boots: this repository's
      # configuration, with rookery's invariants restated as assertions
      # (design.md D5) and the portable-service manager the second folder needs.
      e2eGuest = import ./tests/e2e/guest.nix {
        inherit (pkgs) lib;
        inherit pkgs system;
        nixpkgs = inputs.nixpkgs;
        flakeletModule = inputs.flakelet.nixosModules.flakelet;
      };

      # The entry point. Everything this repository owns is baked in as a store
      # path, so `nix run` builds it through the ordinary pure path; only rookery
      # is resolved at run time, with the caller's own credentials (design.md D2).
      e2eRunner = pkgs.writeShellApplication {
        name = "planner-e2e";
        runtimeInputs = [
          pkgs.nix
          pkgs.openssh
        ];
        text = ''
          export PLANNER_WIRED_PAIR=${wiredPairArtifacts}
          export PLANNER_WIRED_PAIR_DEPLOYMENT=${./tests/e2e/wired-pair/deployment}
          export PLANNER_PORTABLE_IMAGE=${portableImageArtifacts}
          export PLANNER_E2E_GUEST_IMAGE=${e2eGuest}/nixos.qcow2
          export PLANNER_E2E=${./tests/e2e}
          exec ${clusterPytestEnv}/bin/python3 ${./tests/e2e/runner.py} "$@"
        '';
      };

      # A shell hook runs again on every nested entry - direnv, then a
      # `nix develop` inside it - so a plain prepend grows PYTHONPATH without
      # bound. `dir` is a shell word, evaluated by the hook.
      onPythonPath = dir: ''
        case ":''${PYTHONPATH-}:" in
          *":${dir}:"*) ;;
          *) export PYTHONPATH="${dir}''${PYTHONPATH:+:$PYTHONPATH}" ;;
        esac
      '';

      # pytest by hand over the suites that need no machine. It is the same
      # `pytestEnv` the checks are built on, so a manual run and a check cannot
      # disagree about the interpreter. Each artifact-backed suite skips itself
      # until its `PLANNER_*` variable names a built path, which the
      # corresponding `nix build` prints.
      plannerShell = pkgs.mkShell {
        packages = [ pytestEnv ];
        shellHook = ''
          planner_root="$(git rev-parse --show-toplevel)"
          # A check copies `delivery.py` in beside the tests; here it is a path.
          # Without it the two cluster suites fail to import rather than skip.
          ${onPythonPath "$planner_root/tests/e2e"}
        '';
      };

      # pytest by hand over the cluster suite, which needs three things this
      # repository's default shell cannot carry: rookery's interpreter rather
      # than `pkgs.python3` (design.md D4), the two built store paths the suite
      # reads, and rookery itself - private, so resolved at entry with the
      # caller's own credentials rather than pinned as an input (design.md D2).
      #
      # The driver and the deployment come from the working tree, not from the
      # store the runner bakes in: the point of running by hand is that an edit
      # is what runs. The environment is assembled by the runner's own
      # `--print-env`, so this shell and `nix run .#planner-e2e` cannot drift
      # apart. A shell opened where rookery cannot be fetched still opens, and
      # the suite then skips itself by name.
      clusterShell = pkgs.mkShell {
        packages = [
          clusterPytestEnv
          pkgs.nix
          pkgs.openssh
        ];
        shellHook = ''
          planner_root="$(git rev-parse --show-toplevel)"
          export PLANNER_WIRED_PAIR=${wiredPairArtifacts}
          export PLANNER_WIRED_PAIR_DEPLOYMENT="$planner_root/tests/e2e/wired-pair/deployment"
          export PLANNER_PORTABLE_IMAGE=${portableImageArtifacts}
          export PLANNER_E2E_GUEST_IMAGE=${e2eGuest}/nixos.qcow2
          ${onPythonPath "$planner_root/tests/e2e"}
          if rookery_env=$(${clusterPytestEnv}/bin/python3 ${./tests/e2e/runner.py} --print-env); then
            eval "$rookery_env"
          else
            echo "planner-cluster: no rookery, so the end-to-end tests will skip themselves" >&2
          fi
          echo "planner-cluster: pytest tests/e2e/<folder>/test_<folder>.py" >&2
        '';
      };
    in
    {
      # The suite is nix-unit over a generated entry point, so the tests import
      # store paths and read nothing from the working tree.
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

      # The gate: measured counters against committed budgets, per plan entry,
      # with the two-sided ratchet and the growth bound across fleet sizes.
      checks.planner-perf =
        pkgs.runCommand "planner-perf"
          {
            nativeBuildInputs = [ pkgs.python3 ];
          }
          ''
            python3 ${perfRoot}/check.py --results ${measurement} --budgets ${perfRoot}/budgets.json
            touch "$out"
          '';

      # The checker's own behaviour, case by case.
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

      # The harness's own pure half: which machine a key names, which address a
      # delivery dials, what the copy runs in. Its subject is `delivery.py` and
      # the runner, not the planner and not a machine, so it is a check. What a
      # delivery does to a booted machine is `apps.planner-e2e`, which no build
      # sandbox can run (design.md D5).
      checks.planner-delivery =
        pkgs.runCommand "planner-delivery"
          {
            nativeBuildInputs = [ pytestEnv ];
          }
          ''
            python3 -m pytest -q -rs --no-header -p no:cacheprovider ${./tests/e2e}/test_harness.py
            touch "$out"
          '';

      packages.planner-perf = perf;
      packages.planner-perf-results = measurement;
      packages.planner-e2e-wired-pair = wiredPairArtifacts;
      packages.planner-e2e-guest = e2eGuest;
      packages.planner-e2e-portable-image = portableImageArtifacts;

      # pytest on PATH for a manual run. Two shells because the cluster suite's
      # interpreter is rookery's and the rest of the repository's is
      # `pkgs.python3`: one shell carrying both would leave `python3` ambiguous.
      devShells.planner = plannerShell;
      devShells.planner-cluster = clusterShell;

      # The only output in this repository whose subject is machines and the
      # network between them. It is an app rather than a check because a build
      # sandbox has neither `/dev/net/tun` nor `/dev/vhost-vsock` and cannot ask
      # the daemon whether a path is valid, which is the first thing a delivery
      # does (design.md D2). `checks.planner-delivery` holds the half of the
      # delivery driver that is pure functions and needs no machine.
      apps.planner-e2e = {
        type = "app";
        program = "${e2eRunner}/bin/planner-e2e";
        meta.description = "Run the planner's end-to-end tests on real machines";
      };
    };
}
