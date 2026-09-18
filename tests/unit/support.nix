{
  planner,
  folder,
  perfSource,
  korora,
  systems,
}:
let
  inherit (builtins)
    any
    attrNames
    concatLists
    concatStringsSep
    filter
    genList
    head
    isString
    length
    mapAttrs
    match
    readDir
    sort
    split
    stringLength
    substring
    tryEval
    ;

  k = planner.korora;

  # A second, independent evaluation of the library. `import` is memoised by path
  # and not by application, so this is a different value of the same shape, which
  # is the arrangement two authors of two flakes are in.
  anotherEvaluation = libSource: import libSource { inherit korora systems; };
in
rec {
  inherit
    planner
    folder
    perfSource
    anotherEvaluation
    ;
  korora = k;

  publicString = {
    type = k.string;
  };
  publicInt = {
    type = k.int;
  };
  publicUrl = {
    type = k.url;
    secrecy = "public";
  };
  secretFile = {
    type = k.secretRef;
    secrecy = "secret";
  };

  inherit (planner) interface;

  root =
    {
      members,
      provides ? { },
    }:
    { service, ... }:
    let
      services = mapAttrs (name: spec: service name spec) members;
    in
    {
      inherit services;
      provides = mapAttrs (_: ref: services.${ref.member}.provides.${ref.capability}) provides;
    };

  soleRoot =
    {
      module,
      defaults ? { },
      fixed ? { },
      provides ? [ ],
    }:
    root {
      members.only = {
        inherit module defaults fixed;
      };
      provides = builtins.listToAttrs (
        map (cap: {
          name = cap;
          value = {
            member = "only";
            capability = cap;
          };
        }) provides
      );
    };

  # Each machine declares the recipient a delivery seals to, because a machine a
  # delivered value reaches and that declares none earns a warning of its own,
  # and a suite about a file record or a closure would then carry that warning in
  # every row list it asserts. The registries that deliberately declare none are
  # the worked fixture's and the cases about the warning itself.
  machines = {
    one = {
      address = "one.example:22";
      tags = [ "everywhere" ];
      system = "x86_64-linux";
      serviceManager = "systemd";
      sealRecipient = "age1kjrd4qmquzt6wxdg8jj52vw3rqdhl53d7d68ayfpx0nvetvnwh5auff9ej";
    };
    two = {
      address = "two.example:22";
      tags = [ "everywhere" ];
      system = "x86_64-linux";
      serviceManager = "systemd";
      sealRecipient = "age1lyv75cszqel3n0s9vdd5uphnnksmx9zn3ak7zrt2m8w628f6a60s0d6cgk";
    };
  };

  laptop = {
    address = "laptop.example:22";
    tags = [ "everywhere" ];
    system = "aarch64-darwin";
    serviceManager = "launchd";
    sealRecipient = "age18qwr8shvp904mw6l3e5ywldyaqcml8393kzq64q086r8jxw4fpc8x768yp";
  };

  laptopMachines = machines // {
    inherit laptop;
  };

  systemdService = planner.unitExtension {
    backend = "systemd";
    name = "systemd-service";
    fields = {
      protectSystem = {
        type = k.enum "protect-system" [
          "no"
          "yes"
          "full"
          "strict"
        ];
      };
      stateDirectory = {
        type = k.string;
      };
    };
  };

  planOf =
    args:
    planner.mkPlan (
      {
        inherit machines;
      }
      // args
    );

  # One instance with one member and nothing but an implementation: the smallest
  # deployment a test about a unit, a closure, a platform record or a realiser
  # needs. `instances` joins the entry rather than replacing it, and `args` is
  # merged over the whole call, so a second instance and a state answer are each
  # stated beside the entry rather than by a builder of their own.
  entryPlan =
    {
      instance ? "svc",
      member ? "only",
      on ? [ "one" ],
      registry ? machines,
      instances ? { },
      args ? { },
    }:
    implementation:
    planOf (
      {
        machines = registry;
        instances = {
          ${instance} = {
            module = soleRoot { module = _: { impl = implementation; }; };
            placement.every.${member}.machines = on;
          };
        }
        // instances;
      }
      // args
    );

  identity = planner.interface {
    name = "identity";
    exports.publicKey = publicString;
  };

  pub = planner.interface {
    name = "pub";
    exports.publicKey = publicString;
  };

  providerOf = iface: _: {
    provides.identity.interface = iface;
    impl = _: {
      provides.identity.exports.publicKey = "ssh-ed25519 AAAA";
      units.only.command = "/bin/true";
    };
  };

  provider = providerOf identity;

  # The consumer records the names of what it received, so a refused slot is
  # observable without the test touching it and aborting the suite.
  consumer =
    {
      interface ? identity,
      reach ? null,
      reads ? null,
    }:
    _: {
      uses.far = {
        inherit interface;
      }
      // (if reach == null then { } else { inherit reach; })
      // (if reads == null then { } else { inherit reads; });
      impl =
        { results, ... }:
        {
          units.only = {
            command = "/bin/true";
            env = {
              SLOTS = concatStringsSep "," (attrNames results);
              FAR = if results ? far then concatStringsSep "," (attrNames results.far) else "";
            };
          };
        };
    };

  # One instance exposing a capability and one wired to it, which is the whole
  # deployment a test about a wire needs. Every name, list and attribution a
  # scenario varies is an argument, so no suite forks the shape: a null
  # `consumerModule` leaves the provider alone and a null `wire` leaves the slot
  # unwired. `consumers` is how a suite runs several instances of one module,
  # each stating only the machines and the wire it varies, and a null `slot` is
  # how a consumer declaring more than one of them states the whole record.
  edge =
    {
      consumerModule ? null,
      providerModule ? provider,
      consumerName ? "consumer",
      providerName ? "provider",
      consumerMachines ? [ "one" ],
      providerMachines ? [ "one" ],
      capability ? "identity",
      provides ? [ capability ],
      exposes ? provides,
      slot ? "far",
      registry ? machines,
      interfaces ? { },
      sources ? { },
      varsState ? { },
      instances ? { },
      consumers ? { },
      wire ? {
        instance = providerName;
        provides = capability;
      },
    }:
    let
      consuming =
        spec:
        let
          wired = spec.wire or wire;
        in
        {
          module = soleRoot { inherit (spec) module; };
          placement.every.only.machines = spec.machines or consumerMachines;
        }
        // (
          if wired == null then
            { }
          else if slot == null then
            { wire = wired; }
          else
            { wire.${slot} = wired; }
        );
    in
    planOf {
      machines = registry;
      inherit sources varsState interfaces;
      instances = {
        ${providerName} = {
          module = soleRoot {
            inherit provides;
            module = providerModule;
          };
          placement.every.only.machines = providerMachines;
          inherit exposes;
        };
      }
      // (
        if consumerModule == null then
          { }
        else
          { ${consumerName} = consuming { module = consumerModule; }; }
      )
      // mapAttrs (_: consuming) consumers
      // instances;
    };

  rowIds = result: map (r: r.id) result.diagnostics;
  rowsById = id: result: filter (r: r.id == id) result.diagnostics;
  countById = id: result: length (rowsById id result);
  hasRow = id: result: rowsById id result != [ ];
  subjectsById = id: result: map (r: r.subject) (rowsById id result);
  severityById =
    id: result:
    let
      rows = rowsById id result;
    in
    if rows == [ ] then null else (head rows).severity;
  messageById =
    id: result:
    let
      rows = rowsById id result;
    in
    if rows == [ ] then null else (head rows).message;
  evidenceById =
    id: result:
    let
      rows = rowsById id result;
    in
    if rows == [ ] then null else (head rows).evidence;
  resolutionById =
    id: result:
    let
      rows = rowsById id result;
    in
    if rows == [ ] then null else (head rows).resolution;

  # Substring, not regex, so a needle may contain regex characters unescaped.
  hasInfix =
    needle: hay:
    let
      n = stringLength needle;
      h = stringLength hay;
    in
    h >= n && any (i: substring i n hay == needle) (genList (i: i) (h - n + 1));

  filesUnder =
    dir:
    let
      entries = readDir dir;
    in
    concatLists (
      map (
        name:
        if entries.${name} == "directory" then
          map (rest: "${name}/${rest}") (filesUnder (dir + "/${name}"))
        else
          [ name ]
      ) (attrNames entries)
    );

  lines = text: filter isString (split "\n" text);

  # Source scans compare lines with comments removed: a sentence naming a raising
  # call is not a file that makes one.
  codeOf =
    line:
    let
      m = match "([^#]*)#.*" line;
    in
    if m == null then line else head m;

  worked = import ./worked.nix { inherit planner folder; };
  workedResult = planner.mkPlan worked.args;

  # A suite realises nothing, so a configuration file a realiser assembles at
  # build time stands in as a store path keyed by its own bytes: two readings of
  # one recipe answer one path, and an edited recipe answers another, which is
  # what a real `writeText` does.
  assemble = name: text: "/nix/store/${planner.util.shortHash text}-${name}";

  # deepSeq, because a refusal guards fields a lazy read would never force.
  # Without it every refusal test passes without testing anything.
  raises = value: !(tryEval (builtins.deepSeq value value)).success;

  # One unit of one entry, serving: the cheapest implementation with a closure.
  serving = unit: _: {
    closure = [ worked.borgbackup ];
    units.${unit}.command = "${worked.borgbackup}/bin/borg serve";
  };

  # One entry owning one generated secret, with the state that says its bytes
  # exist: the deployment every realiser suite reads a delivered file through. A
  # declared secret with no state is a row of its own, so the state is stated.
  valuePlan =
    {
      instance ? "svc",
      unit ? "only",
      generator ? "hostKey",
      file ? "key",
      content ? "PRIVATE-KEY-BYTES",
      fileArgs ? { },
      unitArgs ? { },
      extraUnits ? { },
      openIt ? false,
      extra ? (_: { }),
      instances ? { },
    }:
    planOf {
      instances = {
        ${instance} = {
          module = soleRoot {
            module = _: {
              vars.${generator}.files.${file} = {
                secrecy = "secret";
              }
              // fileArgs;
              impl =
                { vars, ... }:
                {
                  closure = [ worked.borgbackup ];
                  units = {
                    ${unit} = {
                      command = "${worked.borgbackup}/bin/borg serve";
                    }
                    // (if openIt then { env.KEYFILE = vars.${generator}.${file}.path; } else { })
                    // unitArgs;
                  }
                  // extraUnits;
                }
                // extra vars;
            };
          };
          placement.every.only.machines = [ "one" ];
        };
      }
      // instances;
      varsState."${instance}:vars/${generator}@one".${file} = {
        present = true;
        inherit content;
      };
    };

  # Every realiser reading and the ladder over it. The evaluating layer holds
  # each realiser directory as its own store path, so a relative import out of
  # one would resolve outside the store and the sources arrive as arguments the
  # way they arrive at a suite.
  realiser =
    {
      imageSource ? null,
      flakeletSource ? null,
      operatorSource ? null,
      secretsSource ? null,
      assemble ? null,
    }:
    rec {
      imageReader = import (imageSource + "/read.nix") { inherit planner assemble; };

      flakeletReader = import (flakeletSource + "/read.nix") {
        inherit planner;
        reader = imageReader;
      };

      operatorReader = import (operatorSource + "/read.nix") {
        inherit planner imageReader flakeletReader;
      };

      secretsReader = import (secretsSource + "/read.nix") { inherit planner; };

      planned =
        {
          instance ? "svc",
          member ? "only",
          registry ? machines,
          machine ? "one",
        }:
        implementation:
        let
          result = entryPlan {
            inherit instance member registry;
            on = [ machine ];
          } implementation;
        in
        {
          inherit result;
          inherit (result) plan;
          key = "${instance}:${member}@${machine}";
        };

      readOf =
        {
          read ? imageReader.read,
          profile ? null,
          instance ? "svc",
          registry ? machines,
          machine ? "one",
        }:
        implementation:
        let
          p = planned { inherit instance registry machine; } implementation;
        in
        read (
          {
            inherit (p) plan key;
          }
          // (if profile == null then { } else { inherit profile; })
        );

      rowsById = id: reading: filter (r: r.id == id) reading.rows;
      idsOf = reading: sort (a: b: a < b) (map (r: r.id) reading.rows);
    };
}
