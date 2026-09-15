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

  # 32 characters of Nix's own base 32, without e, o, t and u. Anything else stops
  # the closure scan recognising these as store paths, and it then checks nothing.
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

  serviceUnit = planner.unitExtension {
    backend = "systemd";
    name = "systemd-service";
    fields.supplementaryGroups = {
      type = k.listOf k.string;
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
          instance,
          member,
          ...
        }:
        {
          closure = [ pkgByMachine.${machine} ];
          provides.identity.exports = {
            publicKey = vars.hostKey."key.pub".content;
            agentPath = pkgByMachine.${machine};
          };
          configData."/etc/mesh/agent.conf" = {
            mode = "0440";
            owner = "mesh-agent";
            group = "mesh";
            reload = [ "agent" ];
            render = [
              { text = "interval ${toString settings.interval}"; }
            ];
          };
          units.agent = {
            command = "${pkgByMachine.${machine}}/bin/agent --registry ${results.registry.url}";
            env = {
              FLEET_REGISTRY = results.registry.url;
              FLEET_INTERVAL = toString settings.interval;
            };
            user = "mesh-agent";
            runtimeDirectory = [ "${instance}-${member}" ];
            stateDirectory = [ "mesh-handoff" ];
            extends = [
              {
                extension = serviceUnit;
                values.supplementaryGroups = [ "mesh" ];
              }
            ];
          };
        };
    };

  hubModule =
    { ... }:
    {
      platforms = [ "x86_64-linux" ];

      # Two claims of one number and two narrow addresses, so the pair is compared
      # and found not to contend. The state directory below is shared with the agent
      # on m0 on purpose, so a collision row is produced and stays a warning.
      claims.ports = {
        api = {
          proto = "tcp";
          address = "10.1.0.1";
          fixed = 8443;
        };
        api-local = {
          proto = "tcp";
          address = "127.0.0.1";
          fixed = 8443;
        };
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
        {
          alloc,
          results,
          instance,
          member,
          ...
        }:
        let
          peers = attrValues results.peers;

          # One unit per peer, each ordered after the hub. That reference list crossed against
          # the entry's own unit names is the shape this fixture measures.
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
            mode = "0440";
            group = "mesh";
            reload = [ "hub" ];
            render = map (peer: {
              text = "${peer.publicKey} ${peer.agentPath}\n";
            }) peers;
          };

          units = listToAttrs (
            [
              {
                name = "hub";
                value = {
                  command = "${hubPkg}/bin/hub --port ${toString alloc.ports.api}";
                  user = "mesh-hub";
                  runtimeDirectory = [ "${instance}-${member}" ];
                  stateDirectory = [ "mesh-handoff" ];
                  extends = [
                    {
                      extension = serviceUnit;
                      values.supplementaryGroups = [ "mesh" ];
                    }
                  ];
                };
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
        reserves = {
          ports.sshd = {
            proto = "tcp";
            address = "10.1.0.1";
            number = 22;
          };
          paths = [ "/etc/ssh/sshd_config" ];
        };
      };
    }) machineNames
  );

  interfaces."perf/mesh.nix" = {
    inherit identity registry;
  };

  # Explicit machine lists here and tags in perf/fleet.nix, so both halves of
  # placement resolution are covered.
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

  # Keyed by the value's own plan entry, which for a per-placement generator is
  # the generator and the machine.
  varsState = listToAttrs (
    map (name: {
      name = "mesh:vars/hostKey@${name}";
      value = {
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
