{
  planner,
  support,
  libSource,
  operatorSource,
  imageSource,
  flakeletSource,
  repoSource,
  secretsSource,
}:
let
  inherit (builtins)
    all
    any
    attrNames
    elem
    filter
    isString
    length
    split
    substring
    ;

  inherit (support)
    countById
    evidenceById
    hasInfix
    messageById
    planOf
    publicString
    resolutionById
    root
    rowIds
    severityById
    soleRoot
    subjectsById
    ;

  inherit (planner.util) sortStrings uniqueStrings;

  ids = result: uniqueStrings (rowIds result);

  subjectLines =
    rendered: filter (l: substring 0 4 l == "  ! ") (filter isString (split "\n" rendered));

  renderedBlocks = rendered: filter isString (split "\n\n" rendered);

  operatorImageReader = import (imageSource + "/read.nix") { inherit planner; };

  operatorFlakeletReader = import (flakeletSource + "/read.nix") {
    inherit planner;
    reader = operatorImageReader;
  };

  operatorReader = import (operatorSource + "/read.nix") {
    inherit planner;
    imageReader = operatorImageReader;
    flakeletReader = operatorFlakeletReader;
  };

  secretsReader = import (secretsSource + "/read.nix") { inherit planner; };

  # A plan carrying one of every condition the secrets reading refuses. The
  # identifiers its accounts name are crossed against the rows this produces,
  # so an account naming a row nothing builds is named rather than believed.
  secretsValue = {
    key = "sha256-0000000000000000";
    per = "instance";
    deploy = true;
    delivery = [ "one" ];
    deliveryDerivedFrom = [ "written by hand" ];
    program = "/nix/store/9dm4x2vqk7z1n5bpr3jlfg8ys6cwh0az-generate.drv";
    files.token = {
      path = "/run/vars/hand/token";
      secrecy = "secret";
      inPlan = "reference";
    };
  };

  secretsCorpus = {
    "machine:one".address = "one.example:22";
    "machine:one".tags = [ ];
    "machine:quiet".tags = [ ];
    "machine:spaced".address = "10.0.0.11 ";
    "machine:spaced".tags = [ ];

    # No program, a read of a record that is not a value, and a delivery to a
    # machine the plan does not carry.
    "a:vars/plain" = removeAttrs secretsValue [ "program" ] // {
      delivery = [ "ghost" ];
      reads = [ "machine:one" ];
    };

    # No `per`, a file the contract reserves, and a machine with no address.
    "a:vars/quiet" = removeAttrs secretsValue [ "per" ] // {
      delivery = [ "quiet" ];
      files.".nixos-secrets-metadata".path = "/run/vars/hand/meta";
    };

    # A component the contract's grammar does not admit, a file name outside it,
    # and an address the rendered step cannot carry as one word.
    "a:vars/loud name" = secretsValue // {
      delivery = [ "spaced" ];
      files."key@id".path = "/run/vars/hand/key";
    };

    # Two keys projecting onto one name, one of whose components carries the
    # character the projection joins on.
    "a:b:vars/c" = secretsValue;
    "a:vars/b:c" = secretsValue;
  };

  secretsRowIds = uniqueStrings (map (row: row.id) (secretsReader.rows { plan = secretsCorpus; }));

  # The realisers the accounting covers. Which files of one are examined is read
  # off the source the suite is handed, so a file is examined by existing and a
  # fourth realiser by being passed in.
  realisers = [
    {
      label = "image";
      source = imageSource;
      inherit (operatorImageReader) accounts;
    }
    {
      label = "flakelet";
      source = flakeletSource;
      inherit (operatorFlakeletReader) accounts;
    }
    {
      label = "secrets";
      source = secretsSource;
      inherit (secretsReader) accounts;
    }
  ];

  realiserFiles = builtins.concatLists (
    map (
      realiser:
      map (rel: {
        label = "${realiser.label}/${rel}";
        inherit (realiser) accounts;
        text = builtins.readFile (realiser.source + "/${rel}");
      }) (filter (rel: hasInfix ".nix" rel) (support.filesUnder realiser.source))
    ) realisers
  );

  codeOf = text: filter (line: !isComment line) (support.lines text);

  # A file refuses if it defines a raising `fail` or borrows another reading's,
  # which is what separates a realiser's evaluation layer from a builder writing
  # a shell `fail` into a script it renders.
  definesRefusal =
    code: any (line: hasInfix "fail =" line) code && any (line: hasInfix "throw" line) code;

  borrowsRefusal = code: any (line: builtins.match ".*[a-zA-Z]\\.fail .*" line != null) code;

  refuses = code: definesRefusal code || borrowsRefusal code;

  isRefusal = line: builtins.match ".*[^a-zA-Z_]fail [^=].*" line != null;

  accountNameOf =
    line:
    let
      m = builtins.match ".*fail [a-zA-Z.]*accounts\\.([A-Za-z0-9]+).*" line;
    in
    if m == null then null else builtins.head m;

  # Every refusal of a file that refuses is paired with a row by the account it
  # names rather than by its wording. A file that raises and refuses nothing the
  # walk can read is named too: a raise nobody can account for is what this
  # exists to catch.
  accountingOf =
    {
      files,
      produced,
    }:
    let
      read = map (file: file // { code = codeOf file.text; }) files;
      refusing = filter (file: refuses file.code) read;
      raisesWithNoRefusal = filter (
        file: !(refuses file.code) && any (line: hasInfix "throw" line) file.code
      ) read;
      refusalsIn =
        file:
        map (line: {
          inherit (file) label accounts;
          inherit line;
        }) (filter isRefusal file.code);
      every = builtins.concatLists (map refusalsIn refusing);
      accountOf =
        refusal:
        let
          name = accountNameOf refusal.line;
        in
        if name == null || !(refusal.accounts ? ${name}) then null else refusal.accounts.${name};
      accounted =
        refusal:
        let
          account = accountOf refusal;
        in
        account != null && (account.id != null || account ? because);
      declared = uniqueStrings (
        filter (id: id != null) (
          builtins.concatLists (
            map (file: map (account: account.id) (builtins.attrValues file.accounts)) refusing
          )
        )
      );
    in
    {
      examined = sortStrings (uniqueStrings (map (file: file.label) refusing));
      refusals = length every;
      accountedBy = map (refusal: accountNameOf refusal.line) every;
      unaccounted = map (refusal: "${refusal.label}: ${refusal.line}") (
        filter (refusal: !(accounted refusal)) every
      );
      unexamined = sortStrings (map (file: file.label) raisesWithNoRefusal);
      namedByNoProducer = sortStrings (filter (id: !(builtins.elem id produced)) declared);
    };

  producerIds =
    builtins.concatLists (
      map (
        source:
        builtins.concatLists (
          map (
            line:
            let
              m = builtins.match ".*id = \"([^\"]+)\".*" line;
            in
            if m == null then [ ] else m
          ) (support.lines (builtins.readFile source))
        )
      ) totalFiles
    )
    ++ secretsRowIds;

  refusalAccounting = accountingOf {
    files = realiserFiles;
    produced = producerIds;
  };

  # A realiser the accounting has never been told about, as text: nothing but
  # being handed to the walk decides whether its refusals are examined.
  fabricated =
    {
      accounts ? { },
      refusal,
    }:
    {
      label = "fourth/read.nix";
      inherit accounts;
      text = builtins.concatStringsSep "\n" [
        "  fail = account: message: throw \"planner fourth: \${message}\";"
        refusal
      ];
    };

  accountingWith =
    file:
    accountingOf {
      files = realiserFiles ++ [ file ];
      produced = producerIds;
    };

  operatorFiles = filter (rel: hasInfix ".nix" rel) (support.filesUnder operatorSource);

  handWrittenRows = builtins.concatLists (
    map (
      rel:
      let
        code = filter (line: !isComment line) (
          support.lines (builtins.readFile (operatorSource + "/${rel}"))
        );
      in
      map (_: rel) (filter (line: hasInfix "severity = " line) code)
    ) operatorFiles
  );

  brokenMember = "ma\nin";

  brokenPlan = {
    "machine:one" = {
      address = "one.example:22";
      tags = [ ];
      system = "x86_64-linux";
      serviceManager = "systemd";
    };
    "svc:${brokenMember}@one" = {
      key = "sha256-0000000000000000";
      placement.reason = "every";
      units.only.command = "/bin/true";
    };
  };

  brokenRead = operatorReader.read {
    plan = brokenPlan;
    realise.default.realiser = "podman";
  };

  identity = planner.interface {
    name = "identity";
    exports = {
      publicKey = publicString;
      privateKey = publicString // {
        secrecy = "secret";
      };
    };
  };

  pub = planner.interface {
    name = "pub";
    exports.publicKey = publicString;
  };

  pair = planner.interface {
    name = "pair";
    exports = {
      a = publicString;
      b = publicString;
    };
  };

  theirs = planner.interface {
    name = "theirs";
    exports.publicKey = publicString;
  };

  quiet = _: {
    impl = _: {
      units.only.command = "/bin/true";
    };
  };

  identityProvider = _: {
    provides.thing.interface = identity;
    impl = _: {
      provides.thing.exports = {
        publicKey = "ssh-ed25519 AAAA";
        privateKey = "/run/vars/hostKey/key";
      };
      units.only.command = "/bin/true";
    };
  };

  pubProvider = _: {
    provides.thing.interface = pub;
    impl = _: {
      provides.thing.exports.publicKey = "ssh-ed25519 AAAA";
      units.only.command = "/bin/true";
    };
  };

  keysetProvider = _: {
    provides.thing.interface = pair;
    impl = _: {
      provides.thing.exports.a = "x";
      units.only.command = "/bin/true";
    };
  };

  reader = slot: _: {
    uses.slot = slot;
    impl = _: {
      units.only.command = "/bin/true";
    };
  };

  placedOn = machine: module: {
    inherit module;
    placement.every.only.machines = [ machine ];
  };

  wiredTo =
    machine: instance: module:
    (placedOn machine module)
    // {
      wire.slot = {
        inherit instance;
        provides = "thing";
      };
    };

  exposedOn = machines: module: {
    inherit module;
    placement.every.only = { inherit machines; };
    exposes = [ "thing" ];
  };

  everyMistakeArgs = {
    inherit (support) machines;

    interfaces."interfaces/default.nix" = {
      inherit
        identity
        pub
        pair
        theirs
        ;
    };

    instances = {
      identityProvider = exposedOn [ "one" ] (soleRoot {
        module = identityProvider;
        provides = [ "thing" ];
      });

      shared = exposedOn [ "one" "two" ] (soleRoot {
        module = pubProvider;
        provides = [ "thing" ];
      });

      keysetProvider = placedOn "one" (soleRoot {
        module = keysetProvider;
        provides = [ "thing" ];
      });

      unwiredReader = placedOn "one" (soleRoot {
        module = reader {
          interface = identity;
          reads = [ "publicKey" ];
        };
      });

      secretReader = wiredTo "one" "identityProvider" (soleRoot {
        module = reader {
          interface = identity;
          reads = [ "privateKey" ];
        };
      });

      arityReader = wiredTo "one" "shared" (soleRoot {
        module = reader {
          interface = pub;
          reach = "one";
          reads = [ "publicKey" ];
        };
      });

      mismatchReader = wiredTo "one" "shared" (soleRoot {
        module = reader {
          interface = theirs;
          reads = [ "publicKey" ];
        };
      });
    };

    sources.leaves = {
      identityProvider.only = "modules/identity-provider.nix";
      shared.only = "modules/pub-provider.nix";
      keysetProvider.only = "modules/keyset-provider.nix";
      unwiredReader.only = "modules/unwired-reader.nix";
      secretReader.only = "modules/secret-reader.nix";
      arityReader.only = "modules/arity-reader.nix";
      mismatchReader.only = "modules/mismatch-reader.nix";
    };
  };

  everyMistake = planner.mkPlan everyMistakeArgs;

  oneBad = planOf {
    instances = {
      good = placedOn "one" (soleRoot {
        module = quiet;
      });
      bad = placedOn "two" (soleRoot {
        module = _: { };
      });
    };
    sources.leaves.bad.only = "modules/bad.nix";
  };

  # Calls that raise. None may appear in library code. Comment lines are dropped
  # before the scan, so prose may name one, but a trailing comment on a line of code
  # counts as code.
  raising = [
    "throw"
    "abort"
    "assert "
    ".check "
    ".check("
    "korora.check"
  ];

  libraryFiles = filter (rel: hasInfix ".nix" rel) (support.filesUnder libSource);

  isComment = line: builtins.match "[[:space:]]*#.*" line != null;

  # Every file the tree declares total, which is `lib/` plus the reading beside
  # it: `operator/read.nix` produces rows and raises nothing, so the same rule
  # is checked there rather than only stated about it. A realiser's own reading
  # is not here even where it produces rows, because a realiser raises.
  totalFiles = map (rel: libSource + "/${rel}") libraryFiles ++ [
    (operatorSource + "/read.nix")
  ];

  raises = builtins.concatLists (
    map (
      file:
      let
        code = filter (line: !isComment line) (support.lines (builtins.readFile file));
        rel = baseNameOf (toString file);
      in
      builtins.concatLists (
        map (call: map (_: "${rel}: ${call}") (filter (line: hasInfix call line) code)) raising
      )
    ) totalFiles
  );

  # Every row identifier the tree writes as a literal, against the table
  # `docs/diagnostics.md` publishes. The three families are the three ways an
  # identifier is bound: written at the row, defaulted on a helper's argument,
  # and named on one of the key-row helpers' `excluded` / `unknown` /
  # `missingType` fields.
  idBindings = [
    "[^A-Za-z]id = \"([a-z0-9-]+)\".*"
    "[^A-Za-z]id \\? \"([a-z0-9-]+)\".*"
    ".*(excluded|unknown|missingType) = \"([a-z0-9-]+)\".*"
  ];

  idsInLine =
    line:
    builtins.concatLists (
      map (
        pattern:
        let
          m = builtins.match ".*${pattern}" line;
        in
        if m == null then [ ] else [ (builtins.elemAt m (builtins.length m - 1)) ]
      ) idBindings
    );

  # A reading above `lib/` is a producer here where it builds a row of its own.
  # `image/read.nix` and `flakelet/read.nix` name identifiers they do not
  # produce, which is what `refusalAccounting` crosses; this walk is about what
  # the document owes a reader.
  producingFiles = totalFiles ++ [ (secretsSource + "/read.nix") ];

  producedIds = sortStrings (
    uniqueStrings (
      builtins.concatLists (
        map (
          file:
          builtins.concatLists (
            map idsInLine (filter (l: !isComment l) (support.lines (builtins.readFile file)))
          )
        ) producingFiles
      )
    )
  );

  documentLines = support.lines (builtins.readFile (repoSource + "/docs/diagnostics.md"));

  documentedIds = sortStrings (
    uniqueStrings (
      builtins.concatLists (
        map (
          line:
          let
            m = builtins.match "\\| `([a-z0-9-]+)`.*" line;
          in
          if m == null then [ ] else [ (builtins.head m) ]
        ) documentLines
      )
    )
  );

  undocumentedRows = filter (id: !elem id documentedIds) producedIds;
  unproducedRows = filter (id: !elem id producedIds) documentedIds;

  # The subtraction table is the same kind of claim: a comma-separated list of
  # construct names, then the trigger that would bring them back.
  documentedConstructs = sortStrings (
    uniqueStrings (
      builtins.concatLists (
        map (
          line:
          let
            m = builtins.match "([a-zA-Z]+(, [a-zA-Z]+)*)  +[a-z].*" line;
          in
          if m == null then [ ] else filter isString (split ", " (builtins.head m))
        ) documentLines
      )
    )
  );

  treeConstructs = sortStrings (attrNames planner.excluded.constructs);

  # A fold that refuses: it states why, and the planner decides the row's
  # identifier, its subject and its severity.
  refusing = planner.interface {
    name = "pub";
    exports.publicKey = publicString;
    fold = set: {
      refused = "the set names ${toString (length (attrNames set))} provider and none of them is authoritative";
    };
  };

  refusingProvider = _: {
    provides.thing.interface = refusing;
    impl = _: {
      provides.thing.exports.publicKey = "ssh-ed25519 AAAA";
      units.only.command = "/bin/true";
    };
  };

  setReader = _: {
    uses.slot = {
      interface = refusing;
      reach = "all";
      reads = [ "publicKey" ];
    };
    impl =
      { results, ... }:
      {
        units.only = {
          command = "/bin/true";
          env.SLOTS = builtins.concatStringsSep "," (attrNames results);
        };
      };
  };

  refusedFold =
    readers:
    planOf {
      interfaces."interfaces/folded.nix".refusing = refusing;
      instances = {
        vault = exposedOn [ "one" ] (soleRoot {
          module = refusingProvider;
          provides = [ "thing" ];
        });
      }
      // builtins.listToAttrs (
        map (name: {
          inherit name;
          value = wiredTo "one" "vault" (soleRoot {
            module = setReader;
          });
        }) readers
      );
    };

  twoRefusedFolds = refusedFold [
    "first"
    "second"
  ];

  # The deployment's own half, one malformed value at a time. Each is a value a
  # deployment can write and the reading has to answer for.
  malformed =
    write:
    planOf {
      instances = {
        good = placedOn "one" (soleRoot {
          module = quiet;
        });
        bad = write;
      };
    };

  # The module's own half, one malformed value at a time, beside an instance that
  # is well formed. The leaf files are named so that each row's subject is the
  # module file a reader has to edit rather than a plan key.
  leafSources.leaves = {
    bad.only = "modules/bad.nix";
    good.only = "modules/good.nix";
  };

  badLeaf =
    module:
    planOf {
      sources = leafSources;
      instances = {
        good = placedOn "one" (soleRoot {
          module = quiet;
        });
        bad = placedOn "two" (soleRoot {
          inherit module;
        });
      };
    };

  # What a well-formed instance of these probes is planned into, so each probe
  # asserts the rest of the deployment rather than only its own row.
  plannedWhole = result: attrNames result.plan."good:only@one".units;

  # One malformed value per shape a module's declaration has, each planned.
  shapeProbes = {
    claim = badLeaf (_: {
      claims.ports.api = 5432;
      impl = _: {
        units.main.command = "/bin/run";
      };
    });
    slot = badLeaf (_: {
      uses.far = "identity";
      impl = _: {
        units.main.command = "/bin/run";
      };
    });
    capability = badLeaf (_: {
      provides.thing = 5;
      impl = _: {
        units.main.command = "/bin/run";
      };
    });
    generator = badLeaf (_: {
      vars.token = 5;
      impl = _: {
        units.main.command = "/bin/run";
      };
    });
    declaration = badLeaf (_: 5);
  };

  # The same capability, re-exported and wired, so that "addressable by no wire"
  # is observed rather than assumed.
  untypedCapabilityWired = planOf {
    sources.leaves = {
      good.only = "modules/good.nix";
      bad.only = "modules/bad.nix";
      app.only = "modules/app.nix";
    };
    instances = {
      good = placedOn "one" (soleRoot {
        module = quiet;
      });
      bad = exposedOn [ "one" ] (soleRoot {
        module = _: {
          provides.thing = 5;
          impl = _: {
            units.main.command = "/bin/run";
          };
        };
        provides = [ "thing" ];
      });
      app = wiredTo "two" "bad" (soleRoot {
        module = consumerOfPub;
      });
    };
  };

  raisingDeclaration = badLeaf (_: {
    uses.far = {
      interface = pub;
      reads = [ (throw "the module could not decide what it reads") ];
    };
    impl = _: {
      units.main.command = "/bin/run";
    };
  });

  # A root binding one member's slot to a record it wrote by hand rather than to
  # the capability value off its sibling's handle.
  handWrittenBinding =
    { service, ... }:
    {
      services = {
        backend = service "backend" {
          module = pubProvider;
        };
        app = service "app" {
          module = consumerOfPub;
          wire.slot = {
            member = "backend";
            capability = "thing";
          };
        };
      };
    };

  # Every shape at once, beside one instance that is well formed: five malformed
  # records, a declaration that raises, a wire to an untyped capability and a
  # binding nobody took off a handle.
  everyMalformedShapeArgs = {
    inherit (support) machines;
    sources.leaves = {
      good.only = "modules/good.nix";
      claim.only = "modules/claim.nix";
      slot.only = "modules/slot.nix";
      capability.only = "modules/capability.nix";
      generator.only = "modules/generator.nix";
      whole.only = "modules/whole.nix";
      raising.only = "modules/raising.nix";
      consumer.only = "modules/consumer.nix";
      bound.app = "modules/bound-app.nix";
      bound.backend = "modules/bound-backend.nix";
    };
    instances = {
      good = placedOn "one" (soleRoot {
        module = quiet;
      });
      claim = placedOn "one" (soleRoot {
        module = _: {
          claims.ports.api = 5432;
          impl = _: {
            units.main.command = "/bin/run";
          };
        };
      });
      slot = placedOn "one" (soleRoot {
        module = _: {
          uses.far = "identity";
          impl = _: {
            units.main.command = "/bin/run";
          };
        };
      });
      capability = exposedOn [ "one" ] (soleRoot {
        module = _: {
          provides.thing = 5;
          impl = _: {
            units.main.command = "/bin/run";
          };
        };
        provides = [ "thing" ];
      });
      generator = placedOn "one" (soleRoot {
        module = _: {
          vars.token = 5;
          impl = _: {
            units.main.command = "/bin/run";
          };
        };
      });
      whole = placedOn "one" (soleRoot {
        module = _: 5;
      });
      raising = placedOn "one" (soleRoot {
        module = _: {
          uses.far = {
            interface = pub;
            reads = [ (throw "the module could not decide what it reads") ];
          };
          impl = _: {
            units.main.command = "/bin/run";
          };
        };
      });
      consumer = wiredTo "two" "capability" (soleRoot {
        module = consumerOfPub;
      });
      bound = {
        module = handWrittenBinding;
        placement.every.backend.machines = [ "one" ];
        placement.every.app.machines = [ "two" ];
      };
    };
  };

  everyMalformedShape = planner.mkPlan everyMalformedShapeArgs;

  located = result: map (r: "${r.id} :: ${r.subject}") result.diagnostics;

  # An interface whose exports are not atoms, imported by two modules and listed
  # by no deployment: the rows it earns are the rows a listed one earns.
  untyped = {
    name = "untyped";
    exports = {
      typeless = { };
      notAnAtom = 5;
    };
  };

  untypedProvider = _: {
    provides.thing.interface = untyped;
    impl = _: {
      provides.thing.exports = {
        typeless = "x";
        notAnAtom = "y";
      };
      units.only.command = "/bin/true";
    };
  };

  untypedPlan = planOf {
    instances.vault = exposedOn [ "one" ] (soleRoot {
      module = untypedProvider;
      provides = [ "thing" ];
    });
  };

  # A fold whose refusal is not a sentence. Both spellings the channel refuses:
  # a value of another kind, and one carrying nothing.
  refusingWith =
    stated:
    planner.interface {
      name = "pub";
      exports.publicKey = publicString;
      fold = _: { refused = stated; };
    };

  refusedWith =
    stated:
    let
      iface = refusingWith stated;
    in
    planOf {
      instances = {
        vault = exposedOn [ "one" ] (soleRoot {
          module = _: {
            provides.thing.interface = iface;
            impl = _: {
              provides.thing.exports.publicKey = "ssh-ed25519 AAAA";
              units.only.command = "/bin/true";
            };
          };
          provides = [ "thing" ];
        });
        reader = wiredTo "one" "vault" (soleRoot {
          module = _: {
            uses.slot = {
              interface = iface;
              reach = "all";
              reads = [ "publicKey" ];
            };
            impl = _: { units.only.command = "/bin/true"; };
          };
        });
      };
    };

  # An interface two modules import, claiming an identity the library refuses,
  # and one whose fold is not a function. The deployment lists neither.
  badlyIdentified = planner.interface {
    name = "claimer";
    id = 7;
    exports.publicKey = publicString;
  };

  badlyFolded = planner.interface {
    name = "folder";
    exports.publicKey = publicString;
    fold = "not a function";
  };

  unattributed =
    iface:
    planOf {
      instances = {
        vault = exposedOn [ "one" ] (soleRoot {
          module = _: {
            provides.thing.interface = iface;
            impl = _: {
              provides.thing.exports.publicKey = "ssh-ed25519 AAAA";
              units.only.command = "/bin/true";
            };
          };
          provides = [ "thing" ];
        });
        reader = wiredTo "one" "vault" (soleRoot {
          module = _: {
            uses.slot = {
              interface = iface;
              reads = [ "publicKey" ];
            };
            impl = _: { units.only.command = "/bin/true"; };
          };
        });
      };
    };

  consumerOfPub = reader {
    interface = pub;
    reads = [ "publicKey" ];
  };

  # A root that binds one member's slot to its sibling's capability. A deployment
  # keeps the binding, cuts the member out from under it, or contradicts it.
  boundPair =
    { service, ... }:
    let
      backend = service "backend" { module = pubProvider; };
      app = service "app" {
        module = consumerOfPub;
        wire.slot = backend.provides.thing;
      };
    in
    {
      services = {
        inherit backend app;
      };
      provides.thing = backend.provides.thing;
    };

  twoQuiet = root {
    members = {
      keeper.module = quiet;
      gone.module = quiet;
    };
  };

  # The same capability as `pubProvider` publishes, declared for one slot.
  soleUseProvider = _: {
    provides.thing = {
      interface = pub;
      consumers = "one";
    };
    impl = _: {
      provides.thing.exports.publicKey = "ssh-ed25519 AAAA";
      units.only.command = "/bin/true";
    };
  };

  takenTwice = planOf {
    instances = {
      vault = exposedOn [ "one" ] (soleRoot {
        module = soleUseProvider;
        provides = [ "thing" ];
      });
      first = wiredTo "one" "vault" (soleRoot {
        module = consumerOfPub;
      });
      second = wiredTo "two" "vault" (soleRoot {
        module = consumerOfPub;
      });
    };
  };

  exclusionHeader = "| Out | Why not now | Trigger to add it |";

  fixtureReadme = builtins.readFile "${support.folder}/README.md";

  exclusionTableRows =
    (builtins.foldl'
      (
        st: line:
        if st.closed then
          st
        else if !st.open then
          st // { open = line == exclusionHeader; }
        else if substring 0 1 line != "|" then
          st // { closed = true; }
        else if builtins.match "[|[:space:]-]+" line != null then
          st
        else
          st // { rows = st.rows + 1; }
      )
      {
        open = false;
        closed = false;
        rows = 0;
      }
      (support.lines fixtureReadme)
    ).rows;

  # The exclusion suite as data rather than as text: which constructs it refuses
  # is what it states, and a row nobody refuses is what this crosses.
  exclusionSuite = import (repoSource + "/tests/unit/exclusions.nix") { inherit planner support; };

  exclusionCoverage = exclusionSuite.testEveryExclusionTableRowIsCovered;

  constructRows = map (construct: construct.row) (builtins.attrValues planner.excluded.constructs);
in
{
  testAnInstanceNamesNoModule =
    let
      result = malformed { placement.every.only.machines = [ "one" ]; };
    in
    {
      expr = {
        rows = ids result;
        namesTheInstance = subjectsById "declaration-field-missing" result;
        namesTheField = hasInfix "`module`" (messageById "declaration-field-missing" result);
        # Every other instance is still planned.
        planned = attrNames result.plan;
        applicable = result.applicable;
      };
      expected = {
        rows = [
          "declaration-field-missing"
          "placement-unknown-member"
        ];
        namesTheInstance = [ "bad:instance" ];
        namesTheField = true;
        planned = [
          "good:only@one"
          "machine:one"
        ];
        applicable = false;
      };
    };

  testADeclarationCarriesTheWrongType =
    let
      wired = module: (placedOn "one" module) // { wire = "not a record"; };
      cases = {
        wire = malformed (
          wired (soleRoot {
            module = quiet;
          })
        );
        exposes =
          (placedOn "one" (soleRoot {
            module = quiet;
          }))
          // {
            exposes = "thing";
          };
        machines = {
          module = soleRoot { module = quiet; };
          placement.every.only.machines = "one";
        };
      };
      registry = planner.mkPlan {
        machines.one = {
          address = "one.example:22";
          tags = "everywhere";
          system = 64;
          serviceManager = "systemd";
        };
        instances.good = placedOn "one" (soleRoot {
          module = quiet;
        });
      };
      fieldsOf =
        result:
        sortStrings (
          map (r: r.message) (filter (r: r.id == "declaration-field-malformed") result.diagnostics)
        );
    in
    {
      expr = {
        wire = fieldsOf cases.wire;
        exposes = fieldsOf (malformed cases.exposes);
        machines = fieldsOf (malformed cases.machines);
        registry = fieldsOf registry;
        # A table and a plan, both, for every one of them.
        stillPlans = all (r: r.plan != { }) [
          cases.wire
          (malformed cases.exposes)
          (malformed cases.machines)
          registry
        ];
      };
      expected = {
        wire = [
          "instance `bad` declares `wire` as `not a record`, and the reading needs a record"
        ];
        exposes = [
          "instance `bad` declares `exposes` as `thing`, and the reading needs a list of names"
        ];
        machines = [
          "the placement of `only` in instance `bad` declares `machines` as `one`, and the reading needs a list of names"
        ];
        registry = [
          "machine `one` declares `system` as a value of type int, and the reading needs a name"
          "machine `one` declares `tags` as `everywhere`, and the reading needs a list of names"
        ];
        stillPlans = true;
      };
    };

  # Every case below is a declaration the reading refuses. The refusal is a row
  # and the plan is still forceable: a missing attribute and a type error are
  # the two failures `tryEval` cannot catch, so a reading that reaches one loses
  # the whole table rather than filling a row in it.
  testAWireNamesSomethingTheReadingRefused =
    let
      iface = planner.interface {
        name = "pub";
        exports.publicKey = publicString;
      };
      provider = soleRoot {
        module = _: {
          provides.thing.interface = iface;
          impl = _: {
            provides.thing.exports.publicKey = "ssh-ed25519 AAAA";
            units.only.command = "/bin/true";
          };
        };
        provides = [ "thing" ];
      };
      consumer = soleRoot {
        module = _: {
          uses.slot = {
            interface = iface;
            reads = [ "publicKey" ];
          };
          impl = _: { units.only.command = "/bin/true"; };
        };
      };
      wired =
        instance: write:
        planOf {
          instances = {
            ${instance} = exposedOn [ "one" ] provider;
            reader = (placedOn "one" consumer) // write;
          };
        };
      cases = {
        separatorInstance = wired "va:ult" {
          wire.slot = {
            instance = "va:ult";
            provides = "thing";
          };
        };
        noCapability = wired "vault" { wire.slot.instance = "vault"; };
        instanceNotAName = wired "vault" {
          wire.slot = {
            instance = 3;
            provides = "thing";
          };
        };
        capabilityNotAName = wired "vault" {
          wire.slot = {
            instance = "vault";
            provides = 3;
          };
        };
      };
      # The plan is forced: the reading of a refused name is what used to end
      # the evaluation, and no row is a row about a plan nobody can read.
      read = result: {
        rows = ids result;
        planned = builtins.deepSeq result.plan (result.plan != { });
        # The read is recorded and resolved to nothing, so the consuming
        # implementation is handed no value for the slot.
        delivered = result.plan."reader:only@one".reads.slot.delivered;
      };
    in
    {
      expr = builtins.mapAttrs (_: read) cases;
      expected = {
        separatorInstance = {
          rows = [ "name-carries-key-separator" ];
          planned = true;
          delivered = false;
        };
        noCapability = {
          rows = [ "declaration-field-missing" ];
          planned = true;
          delivered = false;
        };
        instanceNotAName = {
          rows = [ "declaration-field-malformed" ];
          planned = true;
          delivered = false;
        };
        capabilityNotAName = {
          rows = [ "declaration-field-malformed" ];
          planned = true;
          delivered = false;
        };
      };
    };

  testAGeneratorReadsASiblingTheReadingRefused =
    let
      result = planOf {
        instances.inst = placedOn "one" (soleRoot {
          module = _: {
            vars."a:b".files.f = { };
            vars.good = {
              reads = [ "a:b" ];
              files.g = { };
            };
            impl = _: { units.only.command = "/bin/true"; };
          };
        });
      };
    in
    {
      expr = {
        rows = ids result;
        # The surviving generator is an entry, and forcing it does not reach the
        # sibling the reading left out of every set.
        planned = builtins.deepSeq result.plan (elem "inst:vars/good@one" (attrNames result.plan));
        reads = result.plan."inst:vars/good@one".reads or null;
      };
      expected = {
        rows = [ "name-carries-key-separator" ];
        planned = true;
        reads = null;
      };
    };

  testADeclarationIsNotTheKindTheReadingNeeds =
    let
      cases = {
        moduleIsARecord = malformed {
          module = {
            services = { };
          };
          placement.every.only.machines = [ "one" ];
        };
        settings = malformed (
          (placedOn "one" (soleRoot {
            module = quiet;
          }))
          // {
            settings = "not a record";
          }
        );
        namespace = malformed (
          (placedOn "one" (soleRoot {
            module = quiet;
          }))
          // {
            settings.only = "not a record";
          }
        );
        instance = malformed "nope";
        machine = planner.mkPlan {
          machines.one = "x86_64-linux";
          instances = { };
        };
      };
      readable =
        result: builtins.deepSeq result.plan (elem "declaration-field-malformed" (rowIds result));
    in
    {
      expr = builtins.mapAttrs (_: readable) cases;
      expected = {
        moduleIsARecord = true;
        settings = true;
        namespace = true;
        instance = true;
        machine = true;
      };
    };

  testAPortClaimIsNotARecord =
    let
      result = shapeProbes.claim;
      entry = result.plan."bad:only@two";
    in
    {
      expr = {
        rows = ids result;
        count = countById "declaration-malformed" result;
        severity = severityById "declaration-malformed" result;
        subjects = subjectsById "declaration-malformed" result;
        namesTheClaim = hasInfix "port claim `api` of modules/bad.nix" (
          messageById "declaration-malformed" result
        );
        namesTheKind = hasInfix "a value of type int" (messageById "declaration-malformed" result);
        claimed = entry ? alloc;
        theRestIsPlanned = plannedWhole result;
        applicable = result.applicable;
      };
      expected = {
        rows = [ "declaration-malformed" ];
        count = 1;
        severity = "error";
        subjects = [ "modules/bad.nix" ];
        namesTheClaim = true;
        namesTheKind = true;
        claimed = false;
        theRestIsPlanned = [ "only" ];
        applicable = false;
      };
    };

  testASlotIsNotARecord =
    let
      result = shapeProbes.slot;
      entry = result.plan."bad:only@two";
    in
    {
      expr = {
        rows = ids result;
        count = countById "declaration-malformed" result;
        subjects = subjectsById "declaration-malformed" result;
        namesTheSlot = hasInfix "slot `far` of modules/bad.nix" (
          messageById "declaration-malformed" result
        );
        namesTheKind = hasInfix "`identity`" (messageById "declaration-malformed" result);
        wired = entry ? reads;
        theRestIsPlanned = plannedWhole result;
        applicable = result.applicable;
      };
      expected = {
        rows = [ "declaration-malformed" ];
        count = 1;
        subjects = [ "modules/bad.nix" ];
        namesTheSlot = true;
        namesTheKind = true;
        wired = false;
        theRestIsPlanned = [ "only" ];
        applicable = false;
      };
    };

  testACapabilityIsNotARecord =
    let
      result = shapeProbes.capability;
      entry = result.plan."bad:only@two";
      wired = untypedCapabilityWired;
    in
    {
      expr = {
        rows = ids result;
        subjects = subjectsById "declaration-malformed" result;
        namesTheCapability = hasInfix "capability `thing` of modules/bad.nix" (
          messageById "declaration-malformed" result
        );
        publishes = entry ? provides;
        theRestIsPlanned = plannedWhole result;
        addressed = {
          rows = ids wired;
          delivered = wired.plan."app:only@two".reads.slot.delivered;
          read = wired.plan."app:only@two".reads.slot ? entry;
        };
        applicable = result.applicable;
      };
      expected = {
        rows = [ "declaration-malformed" ];
        subjects = [ "modules/bad.nix" ];
        namesTheCapability = true;
        publishes = false;
        theRestIsPlanned = [ "only" ];
        addressed = {
          rows = [
            "declaration-malformed"
            "wire-capability-untyped"
          ];
          delivered = false;
          read = false;
        };
        applicable = false;
      };
    };

  testAModuleReturnsSomethingOtherThanARecord =
    let
      result = shapeProbes.declaration;
    in
    {
      expr = {
        rows = ids result;
        subjects = {
          malformed = subjectsById "declaration-malformed" result;
          missing = subjectsById "impl-missing" result;
        };
        namesTheModule = hasInfix "modules/bad.nix is declared as a value of type int" (
          messageById "declaration-malformed" result
        );
        theOtherHalfReadsTheSame = messageById "implementation-malformed" (
          badLeaf (_: {
            impl = _: 5;
          })
        );
        theRestIsPlanned = plannedWhole result;
        applicable = result.applicable;
      };
      expected = {
        rows = [
          "declaration-malformed"
          "impl-missing"
        ];
        subjects = {
          malformed = [ "modules/bad.nix" ];
          missing = [ "modules/bad.nix" ];
        };
        namesTheModule = true;
        theOtherHalfReadsTheSame = "the implementation of modules/bad.nix returned a value that is not an attribute set";
        theRestIsPlanned = [ "only" ];
        applicable = false;
      };
    };

  testAModuleRaisesWhileComputingItsDeclaration =
    let
      result = raisingDeclaration;
    in
    {
      expr = {
        rows = ids result;
        subjects = {
          raised = subjectsById "module-raised" result;
          missing = subjectsById "impl-missing" result;
        };
        namesWhatWasForced = messageById "module-raised" result;
        theRestIsPlanned = plannedWhole result;
        applicable = result.applicable;
      };
      expected = {
        rows = [
          "impl-missing"
          "module-raised"
        ];
        subjects = {
          raised = [ "member:only" ];
          missing = [ "modules/bad.nix" ];
        };
        namesWhatWasForced = "the declaration of member `only` raised a catchable error, so its value is recorded as not computed";
        theRestIsPlanned = [ "only" ];
        applicable = false;
      };
    };

  testAProbePlansEveryMalformedShapeAtOnce =
    let
      forced = builtins.tryEval (builtins.deepSeq everyMalformedShape everyMalformedShape);
    in
    {
      expr = {
        completed = forced.success;
        rows = located everyMalformedShape;
        wellFormed = attrNames everyMalformedShape.plan."good:only@one".units;
        twice = located (planner.mkPlan everyMalformedShapeArgs) == located everyMalformedShape;
        applicable = everyMalformedShape.applicable;
      };
      expected = {
        completed = true;
        rows = [
          "binding-malformed :: bound:app"
          "declaration-malformed :: modules/capability.nix"
          "declaration-malformed :: modules/claim.nix"
          "declaration-malformed :: modules/generator.nix"
          "declaration-malformed :: modules/slot.nix"
          "declaration-malformed :: modules/whole.nix"
          "impl-missing :: modules/raising.nix"
          "impl-missing :: modules/whole.nix"
          "module-raised :: member:only"
          "slot-unwired :: bound:app"
          "wire-capability-untyped :: consumer:only"
        ];
        wellFormed = [ "only" ];
        twice = true;
        applicable = false;
      };
    };

  # What each probe above asserts: the row's identifier beside its subject. The
  # second half is the same assertion against a table the row was taken out of,
  # which is what a reading that dropped the declaration would have produced: it
  # still completes and it names nothing, so completion is not the claim.
  testAProbeNamesTheDeclarationItPlanned =
    let
      named =
        table: map (r: "${r.id} :: ${r.subject}") (filter (r: r.id == "declaration-malformed") table);
      dropped = result: filter (r: r.id != "declaration-malformed") result.diagnostics;
      silent = result: {
        completed = builtins.deepSeq (dropped result) true;
        named = named (dropped result);
      };
    in
    {
      expr = {
        claimed = builtins.mapAttrs (_: result: named result.diagnostics) shapeProbes;
        silent = builtins.mapAttrs (_: silent) shapeProbes;
      };
      expected = {
        claimed = {
          capability = [ "declaration-malformed :: modules/bad.nix" ];
          claim = [ "declaration-malformed :: modules/bad.nix" ];
          declaration = [ "declaration-malformed :: modules/bad.nix" ];
          generator = [ "declaration-malformed :: modules/bad.nix" ];
          slot = [ "declaration-malformed :: modules/bad.nix" ];
        };
        silent = builtins.mapAttrs (_: _: {
          completed = true;
          named = [ ];
        }) shapeProbes;
      };
    };

  testAPublishedExportDeclaresNoAtom = {
    expr = {
      rows = ids untypedPlan;
      namesTheExport = any (
        r: r.id == "export-atom-missing-type" && hasInfix "untyped.typeless" r.message
      ) untypedPlan.diagnostics;
      # The interface is listed nowhere, so the row names it rather than a file.
      subjects = uniqueStrings (subjectsById "export-atom-missing-type" untypedPlan);
      applicable = untypedPlan.applicable;
    };
    expected = {
      rows = [ "export-atom-missing-type" ];
      namesTheExport = true;
      subjects = [ "interface:untyped" ];
      applicable = false;
    };
  };

  testAnExportsAtomIsNotAnAtom = {
    expr = {
      namesTheExport = any (
        r:
        r.id == "export-atom-missing-type"
        && hasInfix "untyped.notAnAtom" r.message
        && hasInfix "rather than an atom" r.message
      ) untypedPlan.diagnostics;
      count = countById "export-atom-missing-type" untypedPlan;
    };
    expected = {
      namesTheExport = true;
      count = 2;
    };
  };

  testARefusalIsNotText =
    let
      result = refusedWith { why = "no"; };
      row = builtins.head (filter (r: r.id == "interface-fold-refusal-malformed") result.diagnostics);
    in
    {
      expr = {
        rows = ids result;
        subject = row.subject;
        namesTheSlot = hasInfix "`slot`" row.message;
        namesTheInterface = hasInfix "`pub`" row.message;
        namesWhatItWas = hasInfix "a value of type set" row.message;
        severity = row.severity;
        theSlotIsUndelivered = result.plan."reader:only@one".reads.slot.delivered;
      };
      expected = {
        rows = [ "interface-fold-refusal-malformed" ];
        subject = "reader:only";
        namesTheSlot = true;
        namesTheInterface = true;
        namesWhatItWas = true;
        severity = "error";
        theSlotIsUndelivered = false;
      };
    };

  testARefusalCarriesNoReason =
    let
      result = refusedWith "";
      row = builtins.head (filter (r: r.id == "interface-fold-refusal-malformed") result.diagnostics);
    in
    {
      expr = {
        rows = ids result;
        subject = row.subject;
        namesTheSlot = hasInfix "`slot`" row.message;
        namesTheInterface = hasInfix "`pub`" row.message;
        # Not a row rendered with an empty message.
        emptyMessages = filter (r: r.message == "") result.diagnostics;
      };
      expected = {
        rows = [ "interface-fold-refusal-malformed" ];
        subject = "reader:only";
        namesTheSlot = true;
        namesTheInterface = true;
        emptyMessages = [ ];
      };
    };

  testAnUnattributedInterfaceDeclaresAMalformedIdentity =
    let
      result = unattributed badlyIdentified;
    in
    {
      expr = {
        rows = ids result;
        subjects = uniqueStrings (subjectsById "interface-id-malformed" result);
        applicable = result.applicable;
      };
      expected = {
        rows = [ "interface-id-malformed" ];
        subjects = [ "interface:claimer" ];
        applicable = false;
      };
    };

  testAnUnattributedInterfaceDeclaresAFoldThatIsNotAFunction =
    let
      result = unattributed badlyFolded;
    in
    {
      expr = {
        rows = ids result;
        subjects = uniqueStrings (subjectsById "interface-fold-not-a-function" result);
      };
      expected = {
        rows = [
          "interface-fold-not-a-function"
          "interface-fold-unapplied"
        ];
        subjects = [ "interface:folder" ];
      };
    };

  testADeploymentWithOneBadInstance = {
    expr = {
      planKeys = attrNames oneBad.plan;
      goodEntryIsWhole = attrNames oneBad.plan."good:only@one".units;
      rows = ids oneBad;
      subjects = subjectsById "impl-missing" oneBad;
      applicable = oneBad.applicable;
    };
    expected = {
      planKeys = [
        "bad:only@two"
        "good:only@one"
        "machine:one"
        "machine:two"
      ];
      goodEntryIsWhole = [ "only" ];
      rows = [ "impl-missing" ];
      subjects = [ "modules/bad.nix" ];
      applicable = false;
    };
  };

  testADeploymentWithNoMistakes =
    let
      result = planOf {
        instances.good = placedOn "one" (soleRoot {
          module = quiet;
        });
      };
    in
    {
      expr = {
        carriesATable = result ? diagnostics;
        isList = builtins.isList result.diagnostics;
        rows = result.diagnostics;
        carriesAPlan = attrNames result.plan;
        applicable = result.applicable;
      };
      expected = {
        carriesATable = true;
        isList = true;
        rows = [ ];
        carriesAPlan = [
          "good:only@one"
          "machine:one"
        ];
        applicable = true;
      };
    };

  testEveryAuthoringMistakeAtOnce =
    let
      forced = builtins.tryEval (builtins.deepSeq everyMistake everyMistake);
    in
    {
      expr = {
        forcingSucceeds = forced.success;
        rows = ids everyMistake;
        rowCount = length everyMistake.diagnostics;
        planIsWhole = length (attrNames everyMistake.plan);
        applicable = everyMistake.applicable;
      };
      expected = {
        forcingSucceeds = true;
        rows = [
          "export-secret-not-a-reference"
          "interface-mismatch"
          "provider-export-missing"
          "reach-one-placement-count"
          "slot-unwired"
        ];
        rowCount = 5;
        planIsWhole = 10;
        applicable = false;
      };
    };

  testAModulesOwnCodeRaisesACatchableError =
    let
      raising = _: {
        impl = _: {
          units.only.command = throw "the module author's own mistake";
        };
      };
      result = planOf {
        instances = {
          broken = placedOn "one" (soleRoot {
            module = raising;
          });
          quiet = placedOn "two" (soleRoot {
            module = quiet;
          });
        };
      };
    in
    {
      expr = {
        rows = ids result;
        severity = severityById "module-raised" result;
        namesTheModule = hasInfix "broken:only@one" (messageById "module-raised" result);
        subjects = subjectsById "module-raised" result;
        restOfThePlan = attrNames result.plan;
        otherEntryIsWhole = attrNames result.plan."quiet:only@two".units;
        applicable = result.applicable;
      };
      expected = {
        rows = [ "module-raised" ];
        severity = "error";
        namesTheModule = true;
        subjects = [ "broken:only@one" ];
        restOfThePlan = [
          "broken:only@one"
          "machine:one"
          "machine:two"
          "quiet:only@two"
        ];
        otherEntryIsWhole = [ "only" ];
        applicable = false;
      };
    };

  testTwoRunsOverOneInput =
    let
      first = planner.mkPlan everyMistakeArgs;
      second = planner.mkPlan everyMistakeArgs;
    in
    {
      expr = {
        tablesEqual = first.diagnostics == second.diagnostics;
        idsEqual = rowIds first == rowIds second;
        orderIsById = rowIds first == sortStrings (rowIds first);
        rowCount = length first.diagnostics;
      };
      expected = {
        tablesEqual = true;
        idsEqual = true;
        orderIsById = true;
        rowCount = 5;
      };
    };

  testARowCarriesItsResolution =
    let
      rows = everyMistake.diagnostics;
      namesAFileOrACommand = r: hasInfix ".nix" r.resolution || hasInfix "`" r.resolution;
    in
    {
      expr = {
        rowCount = length rows;
        everyResolutionIsNonEmpty = all (r: r.resolution != "") rows;
        noneRestatesTheMessage = all (r: r.resolution != r.message) rows;
        everyResolutionNamesAFileOrACommand = all namesAFileOrACommand rows;
      };
      expected = {
        rowCount = 5;
        everyResolutionIsNonEmpty = true;
        noneRestatesTheMessage = true;
        everyResolutionNamesAFileOrACommand = true;
      };
    };

  testAnErrorBlocksTheApply = {
    expr = {
      applicable = oneBad.applicable;
      hasAnError = any (r: r.severity == "error") oneBad.diagnostics;
      entryCount = length (attrNames oneBad.plan);
      badEntryStillThere = oneBad.plan ? "bad:only@two";
    };
    expected = {
      applicable = false;
      hasAnError = true;
      entryCount = 4;
      badEntryStillThere = true;
    };
  };

  testAWarningDoesNotBlockTheApply =
    let
      result = planOf {
        instances = {
          provider = exposedOn [ "one" ] (soleRoot {
            module = pubProvider;
            provides = [ "thing" ];
          });
          setReader = wiredTo "two" "provider" (soleRoot {
            module = reader {
              interface = pub;
              reach = "all";
              reads = [ "publicKey" ];
            };
          });
        };
      };
    in
    {
      expr = {
        rows = ids result;
        severity = severityById "set-read-in-key" result;
        applicable = result.applicable;
      };
      expected = {
        rows = [ "set-read-in-key" ];
        severity = "warning";
        applicable = true;
      };
    };

  testAModuleAuthorCannotSetASeverity =
    let
      result = planOf {
        instances.retagging = placedOn "one" (soleRoot {
          module = reader {
            interface = pub;
            reads = [ "publicKey" ];
            severity = "warning";
          };
        });
        sources.leaves.retagging.only = "modules/retagging.nix";
      };
    in
    {
      expr = {
        rows = ids result;
        attemptRows = countById "module-declared-severity" result;
        attemptSeverity = severityById "module-declared-severity" result;
        namesTheModule = hasInfix "modules/retagging.nix" (messageById "module-declared-severity" result);
        retaggedRowSeverity = severityById "slot-unwired" result;
      };
      expected = {
        rows = [
          "module-declared-severity"
          "slot-unwired"
        ];
        attemptRows = 1;
        attemptSeverity = "warning";
        namesTheModule = true;
        retaggedRowSeverity = "error";
      };
    };

  testRenderingTheFoldersOwnRows =
    let
      table = support.workedResult.diagnostics;
      rendered = planner.render table;
      blocks = renderedBlocks rendered;
      renderedAs =
        r:
        any (
          b: hasInfix "  ! ${r.subject}  ${r.message}" b && hasInfix "      severity: ${r.severity}" b
        ) blocks;
    in
    {
      expr = {
        rowCount = length table;
        oneBlockPerRow = length blocks == length table;
        everyRowRendered = all renderedAs table;
        readsTheDeploymentAgain = hasInfix "fixtures/minimal-typed-edge" rendered;
      };
      expected = {
        rowCount = 2;
        oneBlockPerRow = true;
        everyRowRendered = true;
        readsTheDeploymentAgain = false;
      };
    };

  testRenderingIsStableUnderUnrelatedChange =
    let
      extended = planner.mkPlan (
        support.worked.args
        // {
          instances = support.worked.args.instances // {
            quiet = {
              module = soleRoot { module = quiet; };
              placement.every.only.machines = [ "vault" ];
            };
          };
        }
      );
    in
    {
      expr = {
        renderedUnchanged =
          planner.render extended.diagnostics == planner.render support.workedResult.diagnostics;
        tableUnchanged = extended.diagnostics == support.workedResult.diagnostics;
        theInstanceLanded = extended.plan ? "quiet:only@vault";
        entriesGained = length (attrNames extended.plan) - length (attrNames support.workedResult.plan);
      };
      expected = {
        renderedUnchanged = true;
        tableUnchanged = true;
        theInstanceLanded = true;
        entriesGained = 1;
      };
    };

  testARowWhoseSubjectIsAnAbsolutePath =
    let
      absolute = "/home/someone/checkout/deployment/machines.nix";
      result = planner.mkPlan {
        machines.one = {
          address = "one.example:22";
          tags = [ ];
          system = "x86_64-linux";
          serviceManager = "systemd";
          region = "eu-west";
        };
        instances.i = placedOn "one" (soleRoot {
          module = quiet;
        });
        sources.machines = absolute;
      };
      rendered = planner.render result.diagnostics;
    in
    {
      expr = {
        rows = ids result;
        invalidRows = countById "diagnostic-subject-invalid" result;
        severity = severityById "diagnostic-subject-invalid" result;
        namesTheRowThatCarriedIt = hasInfix "`declaration-unknown-key`" (
          messageById "diagnostic-subject-invalid" result
        );
        subjects = uniqueStrings (map (r: r.subject) result.diagnostics);
        noSubjectLineCarriesTheAbsolutePath = !any (l: hasInfix absolute l) (subjectLines rendered);
        subjectLineCount = length (subjectLines rendered);
      };
      expected = {
        rows = [
          "declaration-unknown-key"
          "diagnostic-subject-invalid"
        ];
        invalidRows = 1;
        severity = "error";
        namesTheRowThatCarriedIt = true;
        subjects = [ "machines.nix" ];
        noSubjectLineCarriesTheAbsolutePath = true;
        subjectLineCount = 2;
      };
    };

  testARaisingHelperIsIntroduced = {
    expr = {
      calls = raises;
      readAtLeastOneFile = libraryFiles != [ ];
    };
    expected = {
      calls = [ ];
      readAtLeastOneFile = true;
    };
  };

  testAModuleDeclaresASeverity =
    let
      result = planOf {
        instances.tagging = placedOn "one" (soleRoot {
          module = _: {
            provides.thing = {
              interface = pub;
              severity = "warning";
            };
            impl = _: {
              units.only.command = "/bin/true";
            };
          };
          provides = [ "thing" ];
        });
        sources.leaves.tagging.only = "modules/tagging.nix";
      };
    in
    {
      expr = {
        rows = ids result;
        readAndDiscarded = countById "module-declared-severity" result;
        itsOwnSeverity = severityById "module-declared-severity" result;
        namesTheModule = hasInfix "modules/tagging.nix" (messageById "module-declared-severity" result);
        theOtherRowKeepsThePlannersSeverity = severityById "provider-export-missing" result;
      };
      expected = {
        rows = [
          "module-declared-severity"
          "provider-export-missing"
        ];
        readAndDiscarded = 1;
        itsOwnSeverity = "warning";
        namesTheModule = true;
        theOtherRowKeepsThePlannersSeverity = "error";
      };
    };

  testAnImplementationReturnsARefusalsField =
    let
      result = planOf {
        instances.refusing = placedOn "one" (soleRoot {
          module = _: {
            impl = _: {
              units.only.command = "/bin/true";
              refusals = [ "the far end is wrong" ];
            };
          };
        });
        sources.leaves.refusing.only = "modules/refusing.nix";
      };
    in
    {
      expr = {
        rows = ids result;
        severity = severityById "implementation-unknown-key" result;
        namesTheKey = hasInfix "`refusals`" (messageById "implementation-unknown-key" result);
        namesTheFold = hasInfix "belongs in the fold of the interface that carries it" (
          support.resolutionById "implementation-unknown-key" result
        );
        applicable = result.applicable;
      };
      expected = {
        rows = [ "implementation-unknown-key" ];
        severity = "error";
        namesTheKey = true;
        namesTheFold = true;
        applicable = false;
      };
    };

  testAFoldRefusesAProvider =
    let
      result = refusedFold [ "reader" ];
      row = builtins.head (support.rowsById "interface-fold-refused" result);
    in
    {
      expr = {
        rows = ids result;
        inherit (row) subject severity message;
        namesTheEntries = hasInfix "`vault:only@one`" row.evidence;
        theSlotIsUndelivered = result.plan."reader:only@one".units.only.env.SLOTS;
        applicable = result.applicable;
      };
      expected = {
        rows = [ "interface-fold-refused" ];
        subject = "reader:only";
        severity = "error";
        message = "the set names 1 provider and none of them is authoritative";
        namesTheEntries = true;
        theSlotIsUndelivered = "";
        applicable = false;
      };
    };

  testOneBadProviderReadByTwoConsumers =
    let
      result = twoRefusedFolds;
      rows = support.rowsById "interface-fold-refused" result;
    in
    {
      expr = {
        rows = length rows;
        subjects = sortStrings (map (r: r.subject) rows);
        messages = uniqueStrings (map (r: r.message) rows);
        neitherWasDropped = all (r: r.severity == "error") rows;
      };
      expected = {
        rows = 2;
        subjects = [
          "first:only"
          "second:only"
        ];
        messages = [ "the set names 1 provider and none of them is authoritative" ];
        neitherWasDropped = true;
      };
    };

  testAModuleRaisesOutsideAFold =
    let
      result = planOf {
        instances.broken = placedOn "one" (soleRoot {
          module = _: {
            impl = _: {
              units.only.command = throw "unknown module 'pam_unix'. Provide a `package` field";
            };
          };
        });
        sources.leaves.broken.only = "modules/broken.nix";
      };
    in
    {
      expr = {
        rows = ids result;
        severity = severityById "module-raised" result;
        namesWhatWasForced = hasInfix "broken:only@one" (messageById "module-raised" result);
        carriesTheModulesOwnText = hasInfix "pam_unix" (messageById "module-raised" result);
        applicable = result.applicable;
      };
      expected = {
        rows = [ "module-raised" ];
        severity = "error";
        namesWhatWasForced = true;
        carriesTheModulesOwnText = false;
        applicable = false;
      };
    };

  testARowIsBuiltOutsideTheLibrary =
    let
      outside = builtins.head (filter (r: r.id == "operator-realiser-unknown") brokenRead.rows);
      inside = builtins.head oneBad.diagnostics;
      fields = [
        "evidence"
        "id"
        "message"
        "resolution"
        "severity"
        "subject"
      ];
    in
    {
      expr = {
        outsideFields = attrNames outside;
        libraryFields = attrNames inside;
        severity = outside.severity;
        rowsWrittenByHand = handWrittenRows;
        readSomeSource = operatorFiles != [ ];
      };
      expected = {
        outsideFields = fields;
        libraryFields = fields;
        severity = "error";
        rowsWrittenByHand = [ ];
        readSomeSource = true;
      };
    };

  testAMemberNameCarriesALineBreak =
    let
      row = builtins.head (filter (r: r.id == "operator-realiser-unknown") brokenRead.rows);
    in
    {
      expr = {
        messageLines = length (support.lines row.message);
        evidenceLines = length (support.lines row.evidence);
        resolutionLines = length (support.lines row.resolution);
        namesTheMember = hasInfix "svc:ma in@one" row.message;
        memberCarriedABreak = length (support.lines brokenMember) == 2;
      };
      expected = {
        messageLines = 1;
        evidenceLines = 1;
        resolutionLines = 1;
        namesTheMember = true;
        memberCarriedABreak = true;
      };
    };

  testARealiserRefusesAConditionNoRowReports =
    let
      workedRealise."vault-repo:server" = {
        realiser = "image";
        profile = "trusted";
      };
      reading = operatorReader.read {
        inherit (support.workedResult) plan;
        realise = workedRealise;
      };
    in
    {
      expr = {
        # Every `fail` of every realiser is answered by a row a producing layer
        # produces, or by a reason its account states for why no deployment
        # reaches it.
        unaccounted = refusalAccounting.unaccounted;
        namedByNoProducer = refusalAccounting.namedByNoProducer;
        unexamined = refusalAccounting.unexamined;
        readSomeRefusals = refusalAccounting.refusals;
        readSomeProducers = length producerIds > 20;
        # The rows the accounting names are rows this tree really produces.
        theReadingProducesThem = reading.rows;
      };
      expected = {
        unaccounted = [ ];
        namedByNoProducer = [ ];
        unexamined = [ ];
        readSomeRefusals = 36;
        readSomeProducers = true;
        theReadingProducesThem = [ ];
      };
    };

  testARealiserIsAddedWithoutEditingTheAccounting =
    let
      fourth = accountingWith (fabricated {
        refusal = "  check = value: if value then value else fail \"a fourth realiser refuses\";";
      });
    in
    {
      expr = {
        # No list decides this: `secrets/backend.nix` is examined because it is a
        # file under a source the suite is handed and it defines a refusal.
        examined = refusalAccounting.examined;
        theFourthIsExamined = builtins.elem "fourth/read.nix" fourth.examined;
        andItsRefusalIsNamed = fourth.unaccounted;
      };
      expected = {
        examined = [
          "flakelet/read.nix"
          "image/read.nix"
          "secrets/backend.nix"
          "secrets/read.nix"
        ];
        theFourthIsExamined = true;
        andItsRefusalIsNamed = [
          "fourth/read.nix:   check = value: if value then value else fail \"a fourth realiser refuses\";"
        ];
      };
    };

  testARefusalWithNoRowAboveItFailsTheSuite =
    let
      unrowed = accountingWith (fabricated {
        accounts.unrowed.id = null;
        refusal = "  check = value: if value then value else fail accounts.unrowed \"nothing rows this\";";
      });
      excused = accountingWith (fabricated {
        accounts.unrowed = {
          id = null;
          because = "no deployment reaches it";
        };
        refusal = "  check = value: if value then value else fail accounts.unrowed \"nothing rows this\";";
      });
    in
    {
      expr = {
        named = unrowed.unaccounted;
        # The same refusal, accounted by a recorded reason rather than by a row.
        withAReason = excused.unaccounted;
      };
      expected = {
        named = [
          "fourth/read.nix:   check = value: if value then value else fail accounts.unrowed \"nothing rows this\";"
        ];
        withAReason = [ ];
      };
    };

  testAnAccountedRowNobodyProducesFailsTheSuite =
    let
      invented = accountingWith (fabricated {
        accounts.invented.id = "no-layer-produces-this";
        refusal = "  check = value: if value then value else fail accounts.invented \"invented\";";
      });
    in
    {
      expr = {
        named = invented.namedByNoProducer;
        # The identifier is the only thing wrong with it, so the refusal itself
        # is accounted for.
        andTheRefusalIsAccounted = invented.unaccounted;
      };
      expected = {
        named = [ "no-layer-produces-this" ];
        andTheRefusalIsAccounted = [ ];
      };
    };

  testARefusalIsReworded =
    let
      reworded = map (
        file:
        file
        // {
          text =
            builtins.replaceStrings
              [ "is not a placed entry key" ]
              [ "does not read as the key of a placed entry" ]
              file.text;
        }
      ) realiserFiles;
      after = accountingOf {
        files = reworded;
        produced = producerIds;
      };
    in
    {
      expr = {
        theWordingChanged =
          hasInfix "does not read as the key of a placed entry"
            (builtins.head (filter (file: file.label == "image/read.nix") reworded)).text;
        pairedTheSameWay = after.accountedBy == refusalAccounting.accountedBy;
        unaccounted = after.unaccounted;
        namedByNoProducer = after.namedByNoProducer;
      };
      expected = {
        theWordingChanged = true;
        pairedTheSameWay = true;
        unaccounted = [ ];
        namedByNoProducer = [ ];
      };
    };

  testARefusalCarriesNoAccount =
    let
      bare = accountingWith (fabricated {
        accounts.unrowed.id = "operator-entry-name-refused";
        refusal = "  check = value: if value then value else fail \"a message and nothing else\";";
      });
    in
    {
      expr = {
        # The realiser carries an account naming a produced row, and this refusal
        # names none of it, which a message fragment would have matched by
        # accident.
        named = bare.unaccounted;
        itsRowIsProduced = bare.namedByNoProducer;
      };
      expected = {
        named = [
          "fourth/read.nix:   check = value: if value then value else fail \"a message and nothing else\";"
        ];
        itsRowIsProduced = [ ];
      };
    };

  testAnApplicableDeploymentIsRealisedWithoutARaise =
    let
      worked = support.workedResult;
      realise."vault-repo:server" = {
        realiser = "image";
        profile = "trusted";
      };
      reading = operatorReader.read {
        inherit (worked) plan;
        inherit realise;
      };
      artifactOf =
        key:
        let
          entry = reading.entries.${key};
          artifact =
            if entry.realiser == "image" then
              operatorImageReader.read {
                inherit (worked) plan;
                inherit key;
                inherit (entry) profile;
              }
            else
              operatorFlakeletReader.read {
                inherit (worked) plan;
                inherit key;
              };
        in
        builtins.tryEval (builtins.deepSeq artifact artifact);
      keys = attrNames reading.entries;

      # An applicable deployment of the same shape, because the worked fixture
      # carries one deliberate error of its own: a generator that has not run.
      applicable = planOf {
        instances.svc = placedOn "one" (soleRoot {
          module = quiet;
        });
      };
      applicableReading = operatorReader.read { inherit (applicable) plan; };
      applicableArtifact =
        let
          built = operatorFlakeletReader.read {
            inherit (applicable) plan;
            key = "svc:only@one";
          };
        in
        builtins.tryEval (builtins.deepSeq built built);
    in
    {
      expr = {
        applicableIsApplicable = applicable.applicable;
        applicableRows = applicableReading.rows;
        applicableRealised = applicableArtifact.success;
        refused = reading.refused;
        rows = reading.rows;
        read = keys;
        raised = filter (key: !(artifactOf key).success) keys;
      };
      expected = {
        applicableIsApplicable = true;
        applicableRows = [ ];
        applicableRealised = true;
        refused = false;
        rows = [ ];
        read = [
          "nightly:client@alpha"
          "nightly:client@beta"
          "nightly:client@gamma"
          "vault-repo:server@vault"
        ];
        raised = [ ];
      };
    };

  # `docs/diagnostics.md` is a claim about the tree, so the two sides are
  # compared rather than maintained beside each other. Each side reports the
  # document with the identifier, because that is what a reader has to edit.
  testTheLibraryGainsARow = {
    expr = {
      undocumented = map (id: "docs/diagnostics.md is missing `${id}`") undocumentedRows;
      scanned = length producedIds;
    };
    expected = {
      undocumented = [ ];
      scanned = length documentedIds;
    };
  };

  testADocumentTabulatesARowTheTreeCannotProduce = {
    expr = {
      unproduced = map (
        id: "docs/diagnostics.md tabulates `${id}`, which no reading of this tree writes"
      ) unproducedRows;
      constructs = documentedConstructs;
    };
    expected = {
      unproduced = [ ];
      constructs = treeConstructs;
    };
  };

  testADeploymentCuttingAMemberEarnsNoExclusionRow =
    let
      result = planOf {
        instances.svc = {
          module = twoQuiet;
          members.gone.enable = false;
          placement.every.keeper.machines = [ "one" ];
        };
      };
    in
    {
      expr = {
        rows = ids result;
        planned = filter (key: !hasInfix "machine:" key) (attrNames result.plan);
        applicable = result.applicable;
      };
      expected = {
        rows = [ ];
        planned = [ "svc:keeper@one" ];
        applicable = true;
      };
    };

  testAMemberScopedWireEarnsNoExclusionRow =
    let
      result = planOf {
        instances = {
          far = exposedOn [ "one" ] (soleRoot {
            module = pubProvider;
            provides = [ "thing" ];
          });
          svc = {
            module = boundPair;
            members.backend.enable = false;
            placement.every.app.machines = [ "one" ];
            wire.app.slot = {
              instance = "far";
              provides = "thing";
            };
          };
        };
      };
      read = result.plan."svc:app@one".reads.slot;
    in
    {
      expr = {
        rows = ids result;
        wire = read.wire;
        entry = read.entry;
        values = read.values;
        applicable = result.applicable;
      };
      expected = {
        rows = [ ];
        wire = {
          instance = "far";
          provides = "thing";
        };
        entry = "far:only@one";
        values.publicKey = "ssh-ed25519 AAAA";
        applicable = true;
      };
    };

  # The table, the suite that refuses one deployment per row, and the fixture
  # README that publishes it: a row leaves all three or the three disagree here.
  testTheTableTheSuiteAndTheFixturesReadmeAgree = {
    expr = {
      libraryRows = sortStrings (uniqueStrings planner.excluded.rows);
      readmeRows = exclusionTableRows;
      suiteRows = sortStrings exclusionCoverage.expr.coveredRows;
      constructsWithoutARefusal = exclusionCoverage.expr.constructsWithoutATest;
      refusalsAsserted = length (filter (name: hasInfix "IsRefused" name) (attrNames exclusionSuite));
      theTableNamesMemberCuts = elem "member cuts" (planner.excluded.rows ++ constructRows);
      theSuiteNamesMemberCuts = elem "member cuts" (
        exclusionCoverage.expr.coveredRows ++ exclusionCoverage.expected.coveredRows
      );
      theReadmeNamesMemberCuts = hasInfix "member cuts" fixtureReadme;
    };
    expected = {
      libraryRows = [
        "collect family"
        "externals"
        "lifecycle"
        "locality"
        "placement.pick/strategy/allocation"
        "runtime plane"
      ];
      readmeRows = 6;
      suiteRows = [
        "collect family"
        "externals"
        "lifecycle"
        "locality"
        "placement.pick/strategy/allocation"
        "runtime plane"
      ];
      constructsWithoutARefusal = [ ];
      refusalsAsserted = length (attrNames planner.excluded.constructs);
      theTableNamesMemberCuts = false;
      theSuiteNamesMemberCuts = false;
      theReadmeNamesMemberCuts = false;
    };
  };

  testTheSixRemainingRowsAreStillRefused = {
    expr = {
      rows = sortStrings (uniqueStrings planner.excluded.rows);
      rowOfEveryConstruct = sortStrings (uniqueStrings constructRows);
      constructsNamingNoRow = filter (
        name: !elem planner.excluded.constructs.${name}.row planner.excluded.rows
      ) (attrNames planner.excluded.constructs);
      constructsNamingNoTrigger = filter (name: planner.excluded.constructs.${name}.trigger == "") (
        attrNames planner.excluded.constructs
      );
    };
    expected = {
      rows = [
        "collect family"
        "externals"
        "lifecycle"
        "locality"
        "placement.pick/strategy/allocation"
        "runtime plane"
      ];
      rowOfEveryConstruct = [
        "collect family"
        "externals"
        "lifecycle"
        "locality"
        "placement.pick/strategy/allocation"
        "runtime plane"
      ];
      constructsNamingNoRow = [ ];
      constructsNamingNoTrigger = [ ];
    };
  };

  testEachNewRowNamesADeclarationToEdit =
    let
      contradicted = planOf {
        instances = {
          far = exposedOn [ "one" ] (soleRoot {
            module = pubProvider;
            provides = [ "thing" ];
          });
          svc = {
            module = boundPair;
            placement.every = {
              backend.machines = [ "one" ];
              app.machines = [ "one" ];
            };
            wire.app.slot = {
              instance = "far";
              provides = "thing";
            };
          };
        };
      };

      cut = planOf {
        instances.svc = {
          module = twoQuiet;
          members.gone.enable = false;
          placement.every = {
            keeper.machines = [ "one" ];
            gone.machines = [ "one" ];
          };
        };
      };
    in
    {
      expr = {
        boundSlotSubjects = subjectsById "wire-names-bound-slot" contradicted;
        boundSlotNamesTheDeployment = hasInfix "deployment/instances.nix wires slot `slot` of `svc:app`" (
          messageById "wire-names-bound-slot" contradicted
        );
        boundSlotNamesTheBinding = hasInfix "binds to member `backend`" (
          messageById "wire-names-bound-slot" contradicted
        );
        boundSlotOffersTheCut = hasInfix "`members.backend.enable = false` in deployment/instances.nix" (
          resolutionById "wire-names-bound-slot" contradicted
        );
        boundSlotOffersTheDeletion = hasInfix "or delete the wire" (
          resolutionById "wire-names-bound-slot" contradicted
        );

        cutSubjects = subjectsById "cut-member-named" cut;
        cutNamesTheDeployment = hasInfix "deployment/instances.nix places `gone` of instance `svc`" (
          messageById "cut-member-named" cut
        );
        cutNamesTheCut = hasInfix "`members.gone.enable = false`" (evidenceById "cut-member-named" cut);
        cutOffersTheDeletion = hasInfix "delete the reference to `gone` in deployment/instances.nix" (
          resolutionById "cut-member-named" cut
        );
        cutOffersTheKeeping = hasInfix "keep the member by deleting `members.gone.enable = false`" (
          resolutionById "cut-member-named" cut
        );

        exceededSubjects = subjectsById "capability-consumers-exceeded" takenTwice;
        exceededNamesTheCapability = hasInfix "capability `thing` of `vault:only`" (
          messageById "capability-consumers-exceeded" takenTwice
        );
        exceededOffersTheDeclaration = hasInfix "declare `consumers = \"many\"` on `thing`" (
          resolutionById "capability-consumers-exceeded" takenTwice
        );
        exceededOffersTheOtherWire = hasInfix "to another capability" (
          resolutionById "capability-consumers-exceeded" takenTwice
        );
      };
      expected = {
        boundSlotSubjects = [ "svc:app" ];
        boundSlotNamesTheDeployment = true;
        boundSlotNamesTheBinding = true;
        boundSlotOffersTheCut = true;
        boundSlotOffersTheDeletion = true;

        cutSubjects = [ "svc:instance" ];
        cutNamesTheDeployment = true;
        cutNamesTheCut = true;
        cutOffersTheDeletion = true;
        cutOffersTheKeeping = true;

        exceededSubjects = [ "vault:only" ];
        exceededNamesTheCapability = true;
        exceededOffersTheDeclaration = true;
        exceededOffersTheOtherWire = true;
      };
    };

  # The whole table, not the deduplicated identifiers: a second sentence about
  # one absence is what a row of its own for a cut slot would be.
  testACutWithAnUnwiredSlotReportsTheExistingRow =
    let
      result = planOf {
        instances.svc = {
          module = boundPair;
          members.backend.enable = false;
          placement.every.app.machines = [ "one" ];
        };
      };
    in
    {
      expr = {
        rows = rowIds result;
        subjects = subjectsById "slot-unwired" result;
        namesTheCut = hasInfix "binds it to member `backend`, which deployment/instances.nix cuts" (
          evidenceById "slot-unwired" result
        );
        namesTheScopedForm = hasInfix "write `wire.app.slot = " (resolutionById "slot-unwired" result);
        applicable = result.applicable;
      };
      expected = {
        rows = [ "slot-unwired" ];
        subjects = [ "svc:app" ];
        namesTheCut = true;
        namesTheScopedForm = true;
        applicable = false;
      };
    };

  testTwoConsumersReportOneRow = {
    expr = {
      rows = ids takenTwice;
      count = countById "capability-consumers-exceeded" takenTwice;
      namesTheFirstSlot = hasInfix "`first:only.slot`" (
        messageById "capability-consumers-exceeded" takenTwice
      );
      namesTheSecondSlot = hasInfix "`second:only.slot`" (
        messageById "capability-consumers-exceeded" takenTwice
      );
      applicable = takenTwice.applicable;
    };
    expected = {
      rows = [ "capability-consumers-exceeded" ];
      count = 1;
      namesTheFirstSlot = true;
      namesTheSecondSlot = true;
      applicable = false;
    };
  };

  testTheRowOutlivesThePlacementsItDropped =
    let
      result = planOf {
        machines.bare = {
          tags = [ "fleet" ];
          system = "x86_64-linux";
          serviceManager = "systemd";
        };
        instances.svc = {
          module = soleRoot {
            module = quiet;
          };
          placement.every.only.tags = [ "fleet" ];
        };
      };
    in
    {
      expr = {
        rows = rowIds result;
        namesTheMachine = hasInfix "`bare`" (messageById "machine-target-incomplete" result);
        subjects = subjectsById "machine-target-incomplete" result;
        countsThePlacements = hasInfix "places one entry on it" (
          evidenceById "machine-target-incomplete" result
        );
        planned = filter (key: !hasInfix "machine:" key) (attrNames result.plan);
      };
      expected = {
        rows = [ "machine-target-incomplete" ];
        namesTheMachine = true;
        subjects = [ "deployment/machines.nix" ];
        countsThePlacements = true;
        planned = [ "svc:only" ];
      };
    };

  testOneRowForOneMachineHoweverManyPlacementsSelectedIt =
    let
      result = planOf {
        machines.bare = {
          tags = [ "fleet" ];
          system = "x86_64-linux";
          serviceManager = "systemd";
        };
        instances = {
          first = {
            module = twoQuiet;
            placement.every = {
              keeper.tags = [ "fleet" ];
              gone.machines = [ "bare" ];
            };
          };
          second = {
            module = soleRoot {
              module = quiet;
            };
            placement.every.only.machines = [ "bare" ];
          };
        };
      };
    in
    {
      expr = {
        rows = ids result;
        count = countById "machine-target-incomplete" result;
        countsEveryPlacement = hasInfix "places three entries on it" (
          evidenceById "machine-target-incomplete" result
        );
      };
      expected = {
        rows = [ "machine-target-incomplete" ];
        count = 1;
        countsEveryPlacement = true;
      };
    };

  testTheRowNamesTheKeysTheMachineDidNotDeclare =
    let
      result = planOf {
        machines.bare = {
          tags = [ ];
          system = "x86_64-linux";
        };
        instances.svc = {
          module = soleRoot {
            module = quiet;
          };
          placement.every.only.machines = [ "bare" ];
        };
      };
      message = messageById "machine-target-incomplete" result;
    in
    {
      expr = {
        rows = rowIds result;
        namesBothKeys = hasInfix "declares no `address`, `serviceManager`" message;
        namesNeitherDeclaredKey = hasInfix "`system`" message;
        theResolutionNamesTheFile = resolutionById "machine-target-incomplete" result;
      };
      expected = {
        rows = [ "machine-target-incomplete" ];
        namesBothKeys = true;
        namesNeitherDeclaredKey = false;
        theResolutionNamesTheFile = "declare `address`, `serviceManager` for `bare` in deployment/machines.nix";
      };
    };

  testADroppedPlacementProducesNoModuleRow =
    let
      result = planOf {
        machines = support.machines // {
          bare = {
            tags = [ ];
            system = "x86_64-linux";
            serviceManager = "systemd";
          };
        };
        instances.svc = {
          module = soleRoot {
            module = _: {
              impl =
                { target, ... }:
                {
                  units.only.command = "/bin/serve ${target.address}";
                };
            };
          };
          placement.every.only.machines = [
            "one"
            "bare"
          ];
        };
      };
      forced = builtins.tryEval (
        builtins.deepSeq {
          inherit (result) plan diagnostics;
        } true
      );
    in
    {
      expr = {
        rows = rowIds result;
        forcingBothSucceeds = forced.success && forced.value;
        rendered = result.plan."svc:only@one".units.only.command;
        theDroppedEntry = result.plan ? "svc:only@bare";
      };
      expected = {
        rows = [ "machine-target-incomplete" ];
        forcingBothSucceeds = true;
        rendered = "/bin/serve one.example:22";
        theDroppedEntry = false;
      };
    };
}
