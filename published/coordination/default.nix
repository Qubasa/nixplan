# The module this repository publishes for placing a coordination server: the
# membership authority of a mesh, as an entry a plan places rather than as wiring
# a machine image carries. A deployment composes it; nothing here is reachable by
# naming a path inside this repository's source.
#
# Two facts this module refuses to choose are arguments of this function, so a
# composing root that omits one fails the evaluation of its own deployment file
# before a plan exists: `clientUrl`, because plain HTTP over a machine's own
# address is a transport no published module may pick on a consumer's behalf,
# and `policy`, because an empty admission policy admits everybody. `domain` is
# an argument for a third reason - it has no defensible default at all, and the
# server's own state is keyed by it.
#
# Every other choice a cluster makes is a settings knob below, whose default is
# the value this module can defend outside a cluster: the listener, the relay's
# client verification and its relay maps, the embedded relay, the metrics
# listener, the address prefixes, the node expiry and the name-service
# statements.
#
# What the operator runs is published as two names rather than two paths: the
# `coordinate` statement of a deployment names them and the deployment build
# resolves each against the entry's own closure, so nothing reproduces a path
# rule of this module's. Every program named there takes the configuration
# object as the argument after its verb.
{
  pkgs,

  # `{ address, port } -> string`: the url a client is configured with. The
  # address is the one the registry declares for the machine the entry is placed
  # on, and the port is the one the entry claimed.
  clientUrl,

  # `{ mode, path }`: who the server admits. An empty path admits everybody,
  # which is a statement a consumer makes rather than a default this module
  # ships.
  policy,

  # The domain the names of this mesh live under. It is not the server's own
  # host: the server refuses a base domain that is a suffix of its url, the
  # clients taking the domain over.
  domain,

  # The group admitted machines are filed under, and how long a minted
  # credential admits anybody. Both are the generator's facts, so they are
  # arguments rather than settings: the program that mints is built here, where
  # an entry's identity does not exist yet.
  group ? "members",
  expiry ? "24h",

  headscale ? pkgs.headscale,
  jq ? pkgs.jq,
}:
let
  inherit (pkgs) lib;

  # The server's own state: its database, the key it encrypts client traffic
  # with and the key its relay identifies itself by. Keyed by the mesh this
  # server coordinates rather than by the identity of the entry that runs it,
  # because the programs an operator runs are built here, before an entry
  # exists, and both they and the entry's own configuration have to name one
  # socket. Two entries coordinating one mesh on one machine therefore share a
  # state directory, which the planner records as `entry-unit-directory-shared`.
  stateName = "planner-coordination/${domain}";
  stateDir = "/var/lib/${stateName}";
  socket = "${stateDir}/server.sock";

  # The name the object an administrative invocation reads carries. The
  # extension is the whole point: the server decides a configuration's format
  # from it, and the object the realiser binds for the serving unit is named by
  # a digest with no suffix.
  configurationName = "planner-coordination.yaml";

  quoted = lib.escapeShellArg;

  # One configuration, rendered from the settings of one placement. Both objects
  # come from this, so the socket the operator's programs reach and the socket
  # the serving unit binds are one string.
  configurationOf =
    {
      settings,
      url,
      port,
    }:
    let
      list = items: "[${lib.concatStringsSep ", " (map (item: "\"${item}\"") items)}]";
    in
    builtins.concatStringsSep "\n" ([
      "server_url: ${url}"
      "listen_addr: ${settings.listenAddress}:${toString port}"
      # An empty value disables the listener. A port nothing reads is a claim
      # this entry would owe its machine.
      ''metrics_listen_addr: "${settings.metricsAddress}"''
      "grpc_listen_addr: ${settings.grpcListenAddress}"
      "grpc_allow_insecure: false"
      "noise:"
      "  private_key_path: ${stateDir}/noise_private.key"
      "prefixes:"
      "  v4: ${settings.prefixV4}"
      "  v6: ${settings.prefixV6}"
      "  allocation: ${settings.allocation}"
      "derp:"
      "  server:"
      "    enabled: ${if settings.embeddedRelay then "true" else "false"}"
      "    region_id: ${toString settings.relayRegionId}"
      "    region_code: ${settings.relayRegionCode}"
      "    region_name: ${settings.relayRegionName}"
      "    stun_listen_addr: ${settings.listenAddress}:${toString settings.stunPort}"
      "    private_key_path: ${stateDir}/derp_server_private.key"
      "    automatically_add_embedded_derp_region: true"
      # Verification is the server asking its own relay whether a presenter is
      # a node it admitted. A deployment whose clients have no route to the
      # relay states false and says why in its own file.
      "    verify_clients: ${if settings.verifyClients then "true" else "false"}"
      "  urls: ${list settings.relayUrls}"
      "  paths: ${list settings.relayPaths}"
      "  auto_update_enabled: false"
      "  update_frequency: 24h"
      "disable_check_updates: true"
      "node:"
      "  expiry: ${settings.nodeExpiry}"
      "  ephemeral:"
      "    inactivity_timeout: 30m"
      "  routes:"
      "    ha:"
      "      probe_interval: 10s"
      "      probe_timeout: 5s"
      "database:"
      "  type: sqlite"
      "  sqlite:"
      "    path: ${stateDir}/db.sqlite"
      "    write_ahead_log: true"
      "log:"
      "  level: info"
      "  format: text"
      "policy:"
      "  mode: ${policy.mode}"
      # Escaped rather than written as an indented string: nix strips the
      # common indentation of one of those, so an indented `path: ""` renders
      # a top-level `path` and the policy loses the only key it states.
      "  path: \"${policy.path}\""
      "dns:"
      "  magic_dns: ${if settings.magicDns then "true" else "false"}"
      "  base_domain: ${domain}"
      "  override_local_dns: ${if settings.overrideLocalDns then "true" else "false"}"
      "  nameservers:"
      "    global: ${list settings.nameservers}"
      "  search_domains: ${list settings.searchDomains}"
      "  extra_records: []"
      "unix_socket: ${socket}"
      ''unix_socket_permission: "0770"''
      "logtail:"
      "  enabled: false"
      ""
    ]);

  # A program the plan records or a verb runs is one file and not a directory:
  # the plan records a generator's program as exactly one store path, and the
  # tool that runs one runs the path itself. The wrapper's own bytes carry the
  # PATH `runtimeInputs` built, so the file still finds the server's tool.
  fileOf =
    wrapper:
    pkgs.runCommand wrapper.name { } ''
      cp ${wrapper}/bin/${wrapper.name} "$out"
    '';

  # The group's own identifier, read back rather than written down: the tool's
  # flag is `-u, --user uint`, so what it takes is the number the server's
  # database assigned, and that database is a source no plan reads. The group is
  # created where the server does not hold it, so the program converges instead
  # of failing on the first run of a fresh server.
  ownerId = ''
    owner_of() {
      headscale --config "$config" users list --output json |
        jq -r --arg name ${quoted group} '(. // []) | map(select(.name == $name)) | .[0].id // empty'
    }
    owner="$(owner_of)"
    if [ -z "$owner" ]; then
      headscale --config "$config" users create ${quoted group} > /dev/null
      owner="$(owner_of)"
    fi
    if [ -z "$owner" ]; then
      echo "planner coordination: the server admits no group ${group} and would not create one" >&2
      exit 1
    fi
  '';

  # The entry's own tool, and the whole of what an operator runs against the
  # server: the serving unit starts it under `serve`, and the verbs of the
  # command run it under the other two. Every verb takes the configuration as
  # its first argument, because this file is built before the entry that holds
  # one exists.
  program = fileOf (
    pkgs.writeShellApplication {
      name = "planner-coordination";
      runtimeInputs = [
        headscale
        jq
      ];
      text = ''
        verb="''${1:-}"
        config="''${2:-}"
        if [ -z "$verb" ] || [ -z "$config" ]; then
          echo "planner coordination: <serve|list|expel> <configuration> [identifier]" >&2
          exit 2
        fi
        shift 2
        case "$verb" in
          serve)
            exec headscale --config "$config" serve
            ;;
          list)
            # Printed as the server answered it. A credential the server minted
            # appears masked to its leading fragment, so the answer carries no
            # bearer authority and may be read back whole.
            exec headscale --config "$config" nodes list --output json
            ;;
          expel)
            identifier="''${1:-}"
            if [ -z "$identifier" ]; then
              echo "planner coordination: expel takes the identifier the listing printed" >&2
              exit 2
            fi
            exec headscale --config "$config" nodes expire --identifier "$identifier" --force
            ;;
          *)
            echo "planner coordination: $verb is no verb of this program" >&2
            exit 2
            ;;
        esac
      '';
    }
  );

  # The credential generator's own program, the store path the plan records for
  # the value. It is run under the contract every generator's program is run
  # under - one program, an output directory in `out`, the files it writes under
  # it - on the machine the server answers on, because the socket it mints
  # against is that machine's.
  #
  # Two files: the key, which is bearer authority until it is spent, and the
  # expiry the server minted it under, which is a fact the operator is told.
  # Neither is printed here: both are read out of `$out` by whatever ran this.
  mint = fileOf (
    pkgs.writeShellApplication {
      name = "planner-coordination-mint";
      runtimeInputs = [
        headscale
        jq
      ];
      text = ''
        config="''${1:-}"
        if [ -z "$config" ]; then
          echo "planner coordination: mint takes the configuration object of the entry that serves this mesh; run it with \`planner invite\`" >&2
          exit 2
        fi
        if [ -z "''${out:-}" ]; then
          echo "planner coordination: mint writes the files it mints under \$out, and nothing set one" >&2
          exit 2
        fi
        ${ownerId}
        # One answer, read twice: the key is presented byte for byte, so it is
        # written with no trailing byte a presenter would have to strip.
        answer="$(headscale --config "$config" preauthkeys create \
          --user "$owner" --expiration ${quoted expiry} --output json)"
        printf '%s' "$(printf '%s' "$answer" | jq -r '.key')" > "$out/preauthkey"
        printf '%s' "$(printf '%s' "$answer" | jq -r '.expiration.seconds')" > "$out/expiry"
      '';
    }
  );

  # A stated policy file is a store object this entry has to carry, or the plan
  # records a path the machine does not hold. A path inside a package is a
  # mention the closure cannot be declared from here, so a consumer hands the
  # file itself.
  policyClosure =
    if policy.path != "" && lib.hasPrefix "${builtins.storeDir}/" policy.path then
      [ policy.path ]
    else
      [ ];

  leaf = import ./server.nix {
    inherit
      configurationOf
      configurationName
      clientUrl
      stateName
      policyClosure
      ;
    inherit (pkgs) writeText;
    admin = {
      program = "${program}";
      mint = "${mint}";
    };
  };
in
{
  # The root a deployment composes. One member, because a second coordination
  # server of one mesh is a second membership authority.
  root =
    { service, ... }:
    {
      services.hub = service "hub" {
        module = leaf;
        defaults = {
          platforms = [
            "x86_64-linux"
            "aarch64-linux"
          ];
          port = 8080;
          stunPort = 3478;
          # A published module binds the loopback: a listener on every interface
          # is a decision about a network this module cannot see.
          listenAddress = "127.0.0.1";
          grpcListenAddress = "127.0.0.1:50443";
          metricsAddress = "";
          verifyClients = true;
          relayUrls = [ "https://controlplane.tailscale.com/derpmap/default" ];
          relayPaths = [ ];
          embeddedRelay = false;
          relayRegionId = 999;
          relayRegionCode = "planner";
          relayRegionName = "planner embedded relay";
          prefixV4 = "100.64.0.0/10";
          prefixV6 = "fd7a:115c:a1e0::/48";
          allocation = "sequential";
          nodeExpiry = "180d";
          magicDns = true;
          overrideLocalDns = false;
          nameservers = [ ];
          searchDomains = [ ];
        };
      };
    };

  # What a deployment writes into its `coordinate` statement. Names rather than
  # paths: the object an administrative invocation reads is rendered per
  # placement, so the build resolves each name against the entry's own closure
  # and publishes the path it found.
  names = {
    program = program.name;
    configuration = configurationName;
  };

  # The socket every one of those programs reaches, for a consumer that wants to
  # say so in its own words.
  inherit socket;
}
