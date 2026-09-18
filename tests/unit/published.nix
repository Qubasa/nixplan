# The modules this repository publishes for a consumer to compose, read the way
# a consumer reaches them: by the output name, applied to values the consumer
# already has, and never by a path into this source.
#
# A suite instantiates no package set, so the coordination module is applied to
# a store that stands in for one: every builder it spends writes a store object
# named by its own bytes, which is what `support.assemble` does for a realiser's
# configuration file. That stand-in is load-bearing rather than incidental - two
# objects rendered from one text are one path here, so the entry's own
# configuration file and the object an administrative invocation reads are
# asserted to be one rendering rather than two that happen to agree today.
{
  planner,
  support,
  nixpkgsLib,
  imageSource,
  repoSource,
}:
let
  inherit (builtins)
    attrNames
    elem
    filter
    functionArgs
    head
    isFunction
    length
    match
    ;

  inherit (support) hasInfix;

  sorted = builtins.sort (a: b: a < b);

  publishedRoot = repoSource + "/published";

  coordinationModule = import (publishedRoot + "/coordination");
  provisioningModule = import (publishedRoot + "/provisioning");
  outputs = import (publishedRoot + "/flake-module.nix");

  # The consumers of those two modules inside this repository: the folder that
  # places a coordination server, and the image its machines boot. Read as text
  # with comments stripped, because what these scenarios are about is which
  # file states a fact and not what any of them evaluates to.
  e2eRoot = repoSource + "/tests/e2e";
  folderRoot = e2eRoot + "/friend-enrollment";

  codeIn = text: map support.codeOf (support.lines text);
  states = text: token: builtins.any (line: hasInfix token line) (codeIn text);

  guestText = builtins.readFile (e2eRoot + "/guest.nix");
  guestModule = import (e2eRoot + "/guest.nix");
  provisioningText = builtins.readFile (publishedRoot + "/provisioning/default.nix");

  deploymentFile = folderRoot + "/deployment/default.nix";
  instancesFile = folderRoot + "/deployment/instances.nix";
  folderText = builtins.readFile deploymentFile;
  instancesText = builtins.readFile instancesFile;

  entriesIn = dir: sorted (attrNames (builtins.readDir dir));

  imageReader = import (imageSource + "/read.nix") {
    inherit planner;
    assemble = null;
  };

  # A store object named by its bytes, in the shape `util.storePathsIn`
  # recognises: nix's base 32 carries no `e`, and a sha256 in hex does.
  hash32 =
    value:
    builtins.replaceStrings [ "e" ] [ "k" ] (
      builtins.substring 0 32 (builtins.hashString "sha256" value)
    );

  store = name: text: "${builtins.storeDir}/${hash32 "${name}:${text}"}-${name}";

  # The name a store object carries, which is how the deployment build resolves
  # the names this module publishes against an entry's own closure.
  objectName =
    path:
    let
      m = match ".*/[0-9a-z]{32}-(.*)" path;
    in
    if m == null then null else head m;

  # A consumer's own package set, stood in for. Every builder returns an object
  # keyed by the bytes it was handed, so an edit to what the module renders
  # moves the path and nothing else does.
  pkgs = {
    lib = nixpkgsLib;
    headscale = store "headscale-0.26.1" "headscale";
    jq = store "jq-1.8.1" "jq";
    writeText = name: text: store name text;
    # The runtime inputs are the wrapper's own bytes in a real package set, so
    # a stand-in that keyed its path by them would key it by a path rather than
    # by what the module wrote.
    writeShellApplication =
      {
        name,
        text,
        ...
      }:
      {
        inherit name;
        outPath = store name text;
      };
    runCommand = name: _: script: {
      inherit name;
      outPath = store name script;
    };
  };

  clientUrl =
    { address, port }:
    "http://${address}:${toString port}";

  # The two facts the module refuses to default, stated the way a consumer
  # states them, and a domain that is not the server's own host.
  coordination = coordinationModule {
    inherit pkgs clientUrl;
    domain = "mesh.example";
    policy = {
      mode = "file";
      path = "";
    };
  };

  registry.hub = {
    address = "hub.example";
    tags = [ "coordinates" ];
    system = "x86_64-linux";
    serviceManager = "systemd";
  };

  planWith =
    settings:
    planner.mkPlan {
      machines = registry;
      instances.mesh = {
        module = coordination.root;
        inherit settings;
        placement.every.hub.machines = [ "hub" ];
      };
    };

  defaulted = planWith { };

  # The choices the end-to-end cluster makes, stated where that cluster states
  # them: in the settings of its own instance rather than in the module's text.
  stated = planWith {
    hub = {
      listenAddress = "0.0.0.0";
      verifyClients = false;
      relayUrls = [ ];
      relayPaths = [ ];
    };
  };

  entryKey = "mesh:hub@hub";
  configPath = "/etc/planner-coordination/mesh-hub/config.yaml";

  entryOf = result: result.plan.${entryKey};
  recordOf = result: (entryOf result).configData.${configPath};
  bytesOf = result: (head (recordOf result).render).text;
  namesIn = result: sorted (filter (n: n != null) (map objectName (entryOf result).closure));

  # The provisioning declaration, evaluated against a machine that carries what
  # a consumer's package set carries. Every fact the module states is a fact of
  # the attribute set it returns.
  machineWith =
    {
      mesonFlags ? [ "-Dvmlinux-h=provided" ],
      withPortabled ? true,
      sysctl ? { },
    }:
    {
      systemd.package = {
        inherit mesonFlags withPortabled;
      };
      boot.kernel.sysctl = sysctl;
    };

  declarationOf =
    args: config:
    provisioningModule args {
      inherit config;
      lib = nixpkgsLib;
    };

  certificate = store "operator.crt" "a verity public half";

  provisioned = declarationOf {
    account = "deployer";
    verityCertificates."operator.crt" = certificate;
  } (machineWith { });

  bare = declarationOf { account = "deployer"; } (machineWith { });

  failing = declaration: filter (a: !a.assertion) declaration.assertions;

  words = text: filter (word: word != "") (filter builtins.isString (builtins.split " " text));

  # The three roots a user-scope run writes under, each named by the layer that
  # owns it rather than written out here: two are the library's, and the image
  # staging root is the image realiser's own.
  commandRoots = sorted [
    planner.util.varsRoot
    planner.util.sealedRoot
    (builtins.dirOf (imageReader.stagingOf "an-entry"))
  ];

  # Each rule is `d <path> <mode> <account> <group> -`.
  ruleRoots = sorted (map (rule: builtins.elemAt (words rule) 1) provisioned.systemd.tmpfiles.rules);
in
{
  testAFactTheModuleRefusesToDefaultIsAnArgument =
    let
      coordinationArgs = functionArgs coordinationModule;
      provisioningArgs = functionArgs provisioningModule;
      requiredIn = args: sorted (filter (name: !args.${name}) (attrNames args));
      defaultedIn = args: sorted (filter (name: args.${name}) (attrNames args));
    in
    {
      expr = {
        # The url a client is configured with and who is admitted are arguments
        # with no default, so a composing root that states neither fails its own
        # evaluation before a plan exists.
        coordinationRequires = requiredIn coordinationArgs;
        coordinationDefaults = defaultedIn coordinationArgs;
        provisioningRequires = requiredIn provisioningArgs;
      };
      expected = {
        coordinationRequires = [
          "clientUrl"
          "domain"
          "pkgs"
          "policy"
        ];
        coordinationDefaults = [
          "expiry"
          "group"
          "headscale"
          "jq"
        ];
        provisioningRequires = [ "account" ];
      };
    };

  testTheClustersChoicesAreDeclarationsOfItsDeployment = {
    expr = {
      # Outside a cluster the module binds the loopback, verifies the relay's
      # clients, publishes no metrics listener and carries upstream's relay map.
      defended = {
        listener = hasInfix "listen_addr: 127.0.0.1:8080" (bytesOf defaulted);
        verifies = hasInfix "verify_clients: true" (bytesOf defaulted);
        metrics = hasInfix ''metrics_listen_addr: ""'' (bytesOf defaulted);
        relayMap = hasInfix ''urls: ["https://controlplane.tailscale.com/derpmap/default"]'' (
          bytesOf defaulted
        );
        expiry = hasInfix "expiry: 180d" (bytesOf defaulted);
      };
      # Each of them is a knob a deployment states, and the statement is what
      # the plan then holds.
      declared = {
        listener = hasInfix "listen_addr: 0.0.0.0:8080" (bytesOf stated);
        verifies = hasInfix "verify_clients: false" (bytesOf stated);
        relayMap = hasInfix "urls: []" (bytesOf stated);
        relayPaths = hasInfix "paths: []" (bytesOf stated);
      };
      # A settings knob is in the entry's key, so the two are two entries of two
      # deployments rather than one entry read twice.
      reKeyed = (entryOf defaulted).key != (entryOf stated).key;
    };
    expected = {
      defended = {
        listener = true;
        verifies = true;
        metrics = true;
        relayMap = true;
        expiry = true;
      };
      declared = {
        listener = true;
        verifies = true;
        relayMap = true;
        relayPaths = true;
      };
      reKeyed = true;
    };
  };

  testAnAdministrativeInvocationReadsAnObjectTheLoaderAccepts = {
    expr = {
      # The server decides a configuration's format from the extension, and the
      # object the realiser binds for the serving unit is named by a digest with
      # no suffix, so the object an operator's verb reads carries one.
      names = coordination.names;
      carried = namesIn defaulted;
      # Every object a verb runs out of that entry is a declared closure root of
      # it, the minting program included: a generator's `program` is no closure
      # root and no mention site, so an entry that did not declare it is one the
      # copy never put on the machine.
      mints = elem defaulted.plan."mesh:vars/enrollment".program (entryOf defaulted).closure;
      # The objects are store objects of the entry's own closure and no host
      # path of it: the only path the entry states is the one its own unit
      # reads, and no step of a run installs a copy anywhere else.
      hostPaths = attrNames (entryOf defaulted).configData;
    };
    expected = {
      names = {
        program = "planner-coordination";
        configuration = "planner-coordination.yaml";
      };
      carried = [
        "planner-coordination"
        "planner-coordination-mint"
        "planner-coordination.yaml"
      ];
      mints = true;
      hostPaths = [ configPath ];
    };
  };

  testTheServingUnitReadsTheConfigurationThePlanHolds =
    let
      record = recordOf defaulted;
      text = bytesOf defaulted;
      entry = entryOf defaulted;
    in
    {
      expr = {
        # The bytes are the plan's, at a record a store object can carry, which
        # is what lets the realiser bind it rather than install a copy.
        holdsTheBytes = {
          inherit (record)
            computed
            owner
            group
            mode
            ;
          fragments = length record.render;
        };
        unitReadsIt = hasInfix " serve ${configPath}" entry.units.serve.command;
        # One derivation, two objects: the object an administrative invocation
        # reads is keyed by the very bytes the plan holds, so a second rendering
        # would be a second path.
        oneRendering = elem (store coordination.names.configuration text) entry.closure;
        # And the socket those programs reach is the socket that configuration
        # states.
        statesTheSocket = hasInfix "unix_socket: ${coordination.socket}" text;
      };
      expected = {
        holdsTheBytes = {
          computed = true;
          owner = "root";
          group = "root";
          mode = "0444";
          fragments = 1;
        };
        unitReadsIt = true;
        oneRendering = true;
        statesTheSocket = true;
      };
    };

  testAPublishedModuleIsReachedByAnOutputName = {
    expr = {
      # Each is under a name whose namespace says which kind of module it is: a
      # deployment composes a planner module, a machine's own configuration
      # imports a NixOS one.
      namespaces = sorted (attrNames outputs.flake);
      planner = attrNames outputs.flake.plannerModules;
      nixos = attrNames outputs.flake.nixosModules;
      # Each output is the module itself rather than a path into this source.
      published = {
        coordination =
          functionArgs outputs.flake.plannerModules.coordination == functionArgs coordinationModule;
        provisioning =
          functionArgs outputs.flake.nixosModules.provisioning == functionArgs provisioningModule;
      };
    };
    expected = {
      namespaces = [
        "nixosModules"
        "plannerModules"
      ];
      planner = [ "coordination" ];
      nixos = [ "provisioning" ];
      published = {
        coordination = true;
        provisioning = true;
      };
    };
  };

  testAPublishedModuleIsComposedByAConsumerWhoPinsNothingOfThisFlake = {
    expr = {
      # Nothing either module requires is an input this repository pins: a
      # consumer hands their own package set and their own facts.
      pinned = filter (
        name:
        elem name [
          "korora"
          "planner"
          "systems"
          "nixpkgs"
          "libSource"
        ]
      ) (attrNames (functionArgs coordinationModule) ++ attrNames (functionArgs provisioningModule));
      # Composed against that package set alone, the module places its entry.
      placed = filter (key: defaulted.plan.${key} ? placement) (attrNames defaulted.plan);
      applicable = defaulted.applicable;
      # The declaration a machine imports is a module of its configuration, not
      # a function of this repository's library.
      machineModule = isFunction (provisioningModule {
        account = "deployer";
      });
    };
    expected = {
      pinned = [ ];
      placed = [ entryKey ];
      applicable = true;
      machineModule = true;
    };
  };

  testAProvisionedMachineAnswersEveryPreflightFact =
    let
      account = provisioned.users.users.deployer;
    in
    {
      expr = {
        # The account a run connects as, its manager kept alive with nobody
        # logged in, and a home traversable by a uid that owns none of it.
        login = {
          inherit (account)
            isNormalUser
            linger
            homeMode
            createHome
            ;
          inherit (account) home group;
        };
        # That login trusted with the machine's own store.
        trusted = provisioned.nix.settings.trusted-users;
        # The fixed roots, writable by it.
        roots = ruleRoots;
        # The certificate an image's signature is verified against.
        verity = provisioned.environment.etc;
        # The authorization rule that admits the account's own attach.
        authorization = {
          enabled = provisioned.security.polkit.enable;
          admits = hasInfix ''subject.user == "deployer"'' provisioned.security.polkit.extraConfig;
          portable = hasInfix "org.freedesktop.portable1." provisioned.security.polkit.extraConfig;
          mount = hasInfix "io.systemd.mount-file-system." provisioned.security.polkit.extraConfig;
        };
        # The daemons an unprivileged mount and user namespace are delegated to,
        # each socket enabled by a drop-in of its own.
        delegation = {
          units = provisioned.systemd.additionalUpstreamSystemUnits;
          wanted = builtins.mapAttrs (_: unit: unit.wantedBy) provisioned.systemd.units;
        };
        # The account's own portable-service daemon and its activation.
        portabled = provisioned.systemd.additionalUpstreamUserUnits;
      };
      expected = {
        login = {
          isNormalUser = true;
          linger = true;
          homeMode = "711";
          createHome = true;
          home = "/home/deployer";
          group = "deployer";
        };
        trusted = [ "deployer" ];
        roots = commandRoots;
        verity."verity.d/operator.crt".source = certificate;
        authorization = {
          enabled = true;
          admits = true;
          portable = true;
          mount = true;
        };
        delegation = {
          units = [
            "systemd-mountfsd.service"
            "systemd-mountfsd.socket"
            "systemd-nsresourced.service"
            "systemd-nsresourced.socket"
          ];
          wanted = {
            "systemd-mountfsd.socket" = [ "sockets.target" ];
            "systemd-nsresourced.socket" = [ "sockets.target" ];
          };
        };
        portabled = [
          "systemd-portabled.service"
          "dbus-org.freedesktop.portable1.service"
        ];
      };
    };

  testTheProvisioningDeclarationStatesNoFourthRoot = {
    expr = {
      # Exactly the roots the command states, each named by the layer that owns
      # it: a fourth would put an account's name into every entry key that
      # renders one.
      roots = ruleRoots;
      # And each is made writable by the account rather than by a group the
      # declaration invented.
      owned = map (rule: hasInfix " deployer deployer " rule) provisioned.systemd.tmpfiles.rules;
      count = length provisioned.systemd.tmpfiles.rules;
    };
    expected = {
      roots = commandRoots;
      owned = [
        true
        true
        true
      ];
      count = 3;
    };
  };

  testTheProvisioningDeclarationCarriesNoCredential = {
    expr = {
      # A declaration that shipped a credential would admit its own author.
      keys = bare.users.users.deployer.openssh.authorizedKeys.keys;
      installed = attrNames bare.environment.etc;
      # The certificate it installs is the consumer's own value, and no private
      # half of any pair is an argument of it at all.
      stated = provisioned.environment.etc."verity.d/operator.crt".source;
      arguments = sorted (attrNames (functionArgs provisioningModule));
    };
    expected = {
      keys = [ ];
      installed = [ ];
      stated = certificate;
      arguments = [
        "account"
        "authorizedKeys"
        "group"
        "home"
        "homeMode"
        "userNamespaceInterface"
        "verityCertificates"
      ];
    };
  };

  testASystemdWithNoUserNamespaceInterfaceIsRefused =
    let
      unbuilt = declarationOf { account = "deployer"; } (machineWith {
        mesonFlags = [ ];
      });
      stated =
        declarationOf
          {
            account = "deployer";
            userNamespaceInterface = true;
          }
          (machineWith {
            mesonFlags = [ ];
          });
      row = head (failing unbuilt);
    in
    {
      expr = {
        # The evaluation fails before a machine is built, naming the property
        # and what a reader does about it.
        refused = length (failing unbuilt);
        namesTheProperty = hasInfix "user-namespace interface" row.message;
        namesTheFlag = hasInfix "-Dvmlinux-h=provided" row.message;
        namesTheOverride = hasInfix "userNamespaceInterface = true" row.message;
        # A consumer whose package set resolved the header says so and is
        # admitted.
        admitted = failing stated;
        # And the declaration rebuilds no service manager of its own.
        rebuilds = provisioned.systemd ? package;
        # A manager built without the portable daemon is the other half of the
        # same fact.
        withoutPortabled = length (
          failing (
            declarationOf { account = "deployer"; } (machineWith {
              withPortabled = false;
            })
          )
        );
      };
      expected = {
        refused = 1;
        namesTheProperty = true;
        namesTheFlag = true;
        namesTheOverride = true;
        admitted = [ ];
        rebuilds = false;
        withoutPortabled = 1;
      };
    };

  testAKernelRefusingAnUnprivilegedUserNamespaceIsNamed =
    let
      refusing = declarationOf { account = "deployer"; } (machineWith {
        sysctl."user.max_user_namespaces" = 0;
      });
      permitting = declarationOf { account = "deployer"; } (machineWith {
        sysctl."user.max_user_namespaces" = 10000;
      });
      row = head (failing refusing);
    in
    {
      expr = {
        refused = length (failing refusing);
        namesTheKnob = hasInfix "user.max_user_namespaces" row.message;
        namesWhoseFactItIs = hasInfix "no plan can state it" row.message;
        # Unset is not refused: the knob nobody stated is the kernel's default.
        unset = failing bare;
        permitted = failing permitting;
      };
      expected = {
        refused = 1;
        namesTheKnob = true;
        namesWhoseFactItIs = true;
        unset = [ ];
        permitted = [ ];
      };
    };

  # The facts the provisioning declaration carries, by the name a machine's own
  # configuration would have to state them under. A test machine restating one
  # is the second copy this change exists to delete, and a scan is what can see
  # that: the fact is which file says it.
  testTheTestMachineImportsThePublishedDeclaration =
    let
      restatements = [
        "nix.settings.trusted-users"
        "systemd.tmpfiles"
        "security.polkit"
        "additionalUpstreamSystemUnits"
        "additionalUpstreamUserUnits"
        "verity.d"
        "linger ="
        planner.util.varsRoot
        planner.util.sealedRoot
        (builtins.dirOf (imageReader.stagingOf "an-entry"))
      ];
    in
    {
      expr = {
        # The declaration reaches the image as an argument, the way every
        # published thing reaches a folder, rather than as a path into this
        # source.
        received = functionArgs guestModule ? provisioningModule;
        stated = (functionArgs guestModule).provisioningModule or false;
        imported = states guestText "provisioningModule";
        # And the image restates none of the facts it carries.
        restated = filter (fact: states guestText fact) restatements;
      };
      expected = {
        received = true;
        stated = false;
        imported = true;
        restated = [ ];
      };
    };

  # The two facts of that image which are a test machine's own rather than a
  # machine's role. That each is explained where it is stated is a sentence a
  # reader writes and no scan can hold; what is asserted is the division.
  testAGuestFactThatIsNotProvisioningStaysTheGuests = {
    expr = {
      image = {
        credential = states guestText "snakeOilEd25519PublicKey";
        manager = states guestText "-Dvmlinux-h=provided";
      };
      # The declaration ships neither: a published declaration carrying a
      # credential would admit its own author, and one rebuilding a service
      # manager would put that build in the closure of every machine that
      # imports it.
      declaration = filter (token: states provisioningText token) [
        "snakeOil"
        "overrideAttrs"
        "systemd.package ="
      ];
      # What the declaration does about the manager instead is assert.
      asserts = length provisioned.assertions;
    };
    expected = {
      image = {
        credential = true;
        manager = true;
      };
      declaration = [ ];
      asserts = 3;
    };
  };

  testAFolderComposesThePublishedModuleItWouldOtherwiseHold = {
    expr = {
      # The module reaches the folder as an argument the way the deployment
      # build does, and reaches the instance through it.
      received = functionArgs (import deploymentFile) ? coordination;
      composed = functionArgs (import instancesFile) ? coordination;
      # What the folder holds is its own service and nothing a consumer
      # outside this repository would need: no module of a coordination
      # server, and no minting script of its own.
      modules = entriesIn (folderRoot + "/deployment/modules");
      deployment = entriesIn (folderRoot + "/deployment");
      # The cluster's own choices are declarations of its deployment: the two
      # the module refuses to default are stated beside the build, and the
      # rest are settings of the instance.
      refusedToDefault = filter (token: !(states folderText token)) [
        "clientUrl"
        "policy"
      ];
      chosen = filter (token: !(states instancesText token)) [
        "listenAddress"
        "embeddedRelay"
        "verifyClients"
        "relayUrls"
        "nodeExpiry"
      ];
    };
    expected = {
      received = true;
      composed = true;
      modules = [ "guestapp" ];
      deployment = [
        "default.nix"
        "instances.nix"
        "machines.nix"
        "mesh.nix"
        "modules"
        "run.sh"
      ];
      refusedToDefault = [ ];
      chosen = [ ];
    };
  };

  testTheMachinesAFolderRunsOnAreProvisionedByThePublishedDeclaration = {
    expr = {
      # One image for the whole layer, and it is the one that imports the
      # declaration: the machines under test and a reader's own machine are one
      # text.
      images = filter (rel: match ".*guest\\.nix" rel != null) (support.filesUnder e2eRoot);
      imports = states guestText "provisioningModule";
      # What the image hands it is what is a test machine's own, and the rest
      # of every preflight fact is the declaration's.
      handed = filter (token: !(states guestText token)) [
        "account"
        "authorizedKeys"
        "verityCertificates"
      ];
      # The folder whose machines are deployed as an account configures none of
      # them itself.
      folderConfigures = filter (
        rel:
        builtins.any (token: states (builtins.readFile (folderRoot + "/${rel}")) token) [
          "users.users"
          "systemd.tmpfiles"
          "security.polkit"
        ]
      ) (filter (rel: match ".*\\.nix" rel != null) (support.filesUnder folderRoot));
    };
    expected = {
      images = [ "guest.nix" ];
      imports = true;
      handed = [ ];
      folderConfigures = [ ];
    };
  };
}
