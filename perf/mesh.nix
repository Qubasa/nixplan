{ planner, size }:
let
  inherit (builtins)
    attrValues
    elemAt
    genList
    length
    listToAttrs
    substring
    ;

  k = planner.korora;

  machineNames = genList (i: "m${toString i}") size;

  hashOf = i: substring 0 32 "${toString i}00000000000000000000000000000000";

  pkgOf = i: "/nix/store/${hashOf i}-mesh-agent-m${toString i}";

  hubPkg = "/nix/store/00000000000000000000000000000000-mesh-hub-1.0";

  pkgByMachine = listToAttrs (
    genList (i: {
      name = "m${toString i}";
      value = pkgOf i;
    }) size
  );

  identity = planner.interface {
    name = "mesh-identity";
    exports = {
      publicKey = {
        type = k.string;
      };
      agentPath = {
        type = k.string;
      };
    };
  };

  registry = planner.interface {
    name = "mesh-registry";
    exports.url = {
      type = k.url;
    };
  };

  agentModule =
    { settings, ... }:
    {
      platforms = [ "x86_64-linux" ];

      vars.hostKey.files = {
        "key" = {
          secrecy = "secret";
        };
        "key.pub" = {
          secrecy = "public";
        };
      };

      uses.registry = {
        interface = registry;
        reach = "one";
        reads = [ "url" ];
      };

      provides.identity.interface = identity;

      impl =
        {
          vars,
          results,
          machine,
          ...
        }:
        {
          closure = [ pkgByMachine.${machine} ];
          provides.identity.exports = {
            publicKey = vars.hostKey."key.pub".content;
            agentPath = pkgByMachine.${machine};
          };
          units.agent = {
            command = "${pkgByMachine.${machine}}/bin/agent --registry ${results.registry.url}";
            env = {
              FLEET_REGISTRY = results.registry.url;
              FLEET_INTERVAL = toString settings.interval;
            };
          };
        };
    };

  hubModule =
    { ... }:
    {
      platforms = [ "x86_64-linux" ];

      claims.ports.api = {
        proto = "tcp";
        count = 1;
        fixed = 8443;
      };

      uses.peers = {
        interface = identity;
        reach = "all";
        reads = [
          "publicKey"
          "agentPath"
        ];
      };

      provides.registry.interface = registry;

      impl =
        { alloc, results, ... }:
        let
          peers = attrValues results.peers;

          peerUnits = genList (i: {
            name = "peer-${toString i}";
            value = {
              command = "${(elemAt peers i).agentPath}/bin/probe";
              after = [ "hub" ];
            };
          }) (length peers);
        in
        {
          closure = [ hubPkg ] ++ map (peer: peer.agentPath) peers;

          provides.registry.exports.url = "https://hub.example:${toString alloc.ports.api}/registry";

          configData."/etc/mesh/peers" = {
            mode = "0444";
            reload = [ "hub" ];
            render = map (peer: {
              text = "${peer.publicKey} ${peer.agentPath}\n";
            }) peers;
          };

          units = listToAttrs (
            [
              {
                name = "hub";
                value.command = "${hubPkg}/bin/hub --port ${toString alloc.ports.api}";
              }
            ]
            ++ peerUnits
          );
        };
    };

  agentRoot =
    { service, ... }:
    let
      agent = service "agent" {
        module = agentModule;
        defaults.interval = 300;
      };
    in
    {
      services.agent = agent;
      provides.identity = agent.provides.identity;
    };

  hubRoot =
    { service, ... }:
    let
      hub = service "hub" {
        module = hubModule;
      };
    in
    {
      services.hub = hub;
      provides.registry = hub.provides.registry;
    };
in
{
  machines = listToAttrs (
    map (name: {
      inherit name;
      value = {
        address = "${name}.mesh.example:22";
        tags = [ "mesh" ];
        system = "x86_64-linux";
        serviceManager = "systemd";
      };
    }) machineNames
  );

  interfaces."perf/mesh.nix" = {
    inherit identity registry;
  };

  instances = {
    mesh = {
      module = agentRoot;
      placement.every.agent.machines = machineNames;
      wire.registry = {
        instance = "hub";
        provides = "registry";
      };
      exposes = [ "identity" ];
    };

    hub = {
      module = hubRoot;
      placement.every.hub.machines = [ "m0" ];
      wire.peers = {
        instance = "mesh";
        provides = "identity";
      };
      exposes = [ "registry" ];
    };
  };

  varsState = listToAttrs (
    map (name: {
      inherit name;
      value.hostKey = {
        "key" = {
          present = true;
        };
        "key.pub" = {
          present = true;
          content = "mesh-key-${name}";
        };
      };
    }) machineNames
  );

  sources = {
    deployment = "perf/mesh.nix";
    machines = "perf/mesh.nix";
    modules = {
      mesh = "perf/mesh.nix";
      hub = "perf/mesh.nix";
    };
    leaves = {
      mesh.agent = "perf/mesh.nix";
      hub.hub = "perf/mesh.nix";
    };
  };
}
