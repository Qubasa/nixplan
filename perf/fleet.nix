{ planner, size }:
let
  inherit (builtins)
    attrValues
    concatStringsSep
    genList
    listToAttrs
    mapAttrs
    ;

  k = planner.korora;

  agentPkg = "/nix/store/9dm4x2vqk7z1n5bpr3jlfg8ys6cwh0az-fleet-agent-1.0";

  machineNames = genList (i: "m${toString i}") size;

  identity = planner.interface {
    name = "fleet-identity";
    exports = {
      publicKey = {
        type = k.string;
      };
      privateKey = {
        type = k.secretRef;
        secrecy = "secret";
      };
    };
  };

  registry = planner.interface {
    name = "fleet-registry";
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
          closure = [ agentPkg ];
          provides.identity.exports = {
            publicKey = vars.hostKey."key.pub".content;
            privateKey = vars.hostKey."key";
          };
          units.agent = {
            command = "${agentPkg}/bin/agent --registry ${results.registry.url}";
            env = {
              FLEET_REGISTRY = results.registry.url;
              FLEET_SELF = machine;
              FLEET_INTERVAL = toString settings.interval;
            };
          };
        };
    };

  hubModule =
    { settings, ... }:
    {
      platforms = [ "x86_64-linux" ];

      claims.ports.api = {
        proto = "tcp";
        count = 1;
        fixed = settings.port;
      };

      uses.peers = {
        interface = identity;
        reach = "all";
        reads = [ "publicKey" ];
      };

      provides.registry.interface = registry;

      impl =
        { alloc, results, ... }:
        {
          closure = [ agentPkg ];
          provides.registry.exports.url = "https://hub.example:${toString alloc.ports.api}/registry";
          configData."/etc/fleet/peers" = {
            mode = "0444";
            reload = [ "hub" ];
            render = [
              {
                text = concatStringsSep "\n" (
                  attrValues (mapAttrs (entry: read: "${entry} ${read.publicKey}") results.peers)
                );
              }
            ];
          };
          units.hub.command = "${agentPkg}/bin/hub --port ${toString alloc.ports.api}";
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
        fixed.port = 8443;
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
        address = "${name}.fleet.example:22";
        tags = [ "fleet" ];
        system = "x86_64-linux";
        serviceManager = "systemd";
      };
    }) machineNames
  );

  interfaces."perf/fleet.nix" = {
    inherit identity registry;
  };

  instances = {
    mesh = {
      module = agentRoot;
      settings.agent.interval = 900;
      placement.every.agent.tags = [ "fleet" ];
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
          content = "fleet-key-${name}";
        };
      };
    }) machineNames
  );

  sources = {
    deployment = "perf/fleet.nix";
    machines = "perf/fleet.nix";
    modules = {
      mesh = "perf/fleet.nix";
      hub = "perf/fleet.nix";
    };
    leaves = {
      mesh.agent = "perf/fleet.nix";
      hub.hub = "perf/fleet.nix";
    };
  };
}
