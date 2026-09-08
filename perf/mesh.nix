# A synthetic deployment whose reader is fleet-sized on the inside.
#
# `fleet.nix` grows the number of entries and keeps every entry's own work
# constant, so it measures the pipeline. This one grows the work of a single
# entry with the fleet: the hub declares one closure root, one unit and one
# render fragment per peer it read. Every one of those is a list the library
# then has to cross against another fleet-sized list, which is where a
# membership test written as a scan costs the square of the fleet while the
# plan it produces stays linear in it.
#
# The plan is therefore still O(size): one hub entry carrying O(size) units,
# roots and fragments, O(size) agent entries carrying a constant each. A
# library whose per-item work is a lookup keeps the cost per plan entry flat as
# the fleet grows; a library whose per-item work is a scan does not.
#
# Placements are spelled as explicit machine lists rather than as a tag,
# because that is the other half of placement resolution and it crosses the
# named machines against the registry.
#
# No time, no filesystem and no environment: two generations at one size are
# equal.
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

  # A literal store path string, distinct per machine. The hash is 32
  # characters over Nix's own base-32 alphabet, which digits and zeroes are in,
  # so the planner's scan recognises these as store roots without anything
  # having been built.
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

  # The hub is placed once, so the plan stays linear, and everything it
  # declares is one item per peer.
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

          # One unit per peer. The name is positional because a plan key is not
          # a legal unit name, and every one of them orders itself against the
          # hub, which is what crosses a reference list against the entry's own
          # unit names.
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
