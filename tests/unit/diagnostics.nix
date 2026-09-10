{
  planner,
  support,
  libSource,
  operatorSource,
  imageSource,
  flakeletSource,
  repoSource,
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
    hasInfix
    messageById
    planOf
    publicString
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

  # Every refusal of the two realisers, and the row that reports it first. A
  # `fail` this table does not account for is what the cross-walk below names.
  refusalsAccountedFor = [
    {
      fragment = "is not a placed entry key";
      row = "operator-plan-record-unclassified";
    }
    {
      fragment = "is not a `sha256-<hex>` value";
      row = null;
      because = "`util.shortHash` answers a `sha256-<hex>` value for every input, so no deployment reaches this";
    }
    {
      fragment = "and it is not inferable from anything else the plan carries";
      row = "machine-target-incomplete";
    }
    {
      fragment = "the plan has no entry";
      row = null;
      because = "the reading enumerates the plan and asks for no key the plan does not carry";
    }
    {
      fragment = "with no platform record";
      row = "machine-target-incomplete";
    }
    {
      fragment = "records a `target` with no `serviceManager`";
      row = "machine-target-incomplete";
    }
    {
      fragment = "the profile is stated rather than inferred";
      row = "operator-image-profile-unknown";
    }
    {
      fragment = "declared closure roots do not contain it";
      row = "closure-path-undeclared";
    }
    {
      fragment = "records extension fields for backend";
      row = "unit-extension-backend-mismatch";
    }
    {
      fragment = "which this builder has no rendering for";
      row = null;
      because = "the field is one an extension declared and the library accepted, and this builder's own directive table is missing it, which is a defect of the builder rather than of the deployment";
    }
    {
      fragment = "cannot spell as a directive";
      row = null;
      because = "the value passed the extension's own type and this builder renders no directive for its shape, which is again the builder's own table";
    }
    {
      fragment = "records no unit, so there is nothing to attach";
      row = "operator-entry-realises-nothing";
    }
    {
      fragment = "and this builder emits images for";
      row = "operator-entry-service-manager-mismatch";
    }
    {
      fragment = "which is not a path under the store directory";
      row = "closure-root-outside-store";
    }
    {
      fragment = "which the plan records as a reference";
      row = "closure-root-is-delivered";
    }
    {
      fragment = "and the stated confinement profile";
      row = "operator-entry-access-denied";
    }
    {
      fragment = "to a value containing a newline";
      row = "unit-env-value-newline";
    }
    {
      fragment = "derives the service name";
      row = "operator-entry-name-refused";
    }
    {
      fragment = "renders the unit file";
      row = "operator-entry-name-refused";
    }
    {
      fragment = "is shown the host path";
      row = "operator-entry-path-not-assembled";
    }
  ];

  realiserFiles = [
    {
      label = "image/read.nix";
      source = imageSource + "/read.nix";
    }
    {
      label = "flakelet/read.nix";
      source = flakeletSource + "/read.nix";
    }
  ];

  refusalsOf =
    file:
    map
      (line: {
        inherit (file) label;
        inherit line;
      })
      (
        filter (line: hasInfix "fail \"" line) (
          filter (line: !isComment line) (support.lines (builtins.readFile file.source))
        )
      );

  everyRefusal = builtins.concatLists (map refusalsOf realiserFiles);

  accountingOf = refusal: filter (entry: hasInfix entry.fragment refusal.line) refusalsAccountedFor;

  unaccountedRefusals = map (refusal: "${refusal.label}: ${refusal.line}") (
    filter (refusal: accountingOf refusal == [ ]) everyRefusal
  );

  producerIds = builtins.concatLists (
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
    ) (map (rel: libSource + "/${rel}") libraryFiles ++ [ (operatorSource + "/read.nix") ])
  );

  rowsNamedByNoProducer = filter (id: id != null && !(builtins.elem id producerIds)) (
    map (entry: entry.row or null) refusalsAccountedFor
  );

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

  raises = builtins.concatLists (
    map (
      rel:
      let
        code = filter (line: !isComment line) (support.lines (builtins.readFile (libSource + "/${rel}")));
      in
      builtins.concatLists (
        map (call: map (_: "${rel}: ${call}") (filter (line: hasInfix call line) code)) raising
      )
    ) libraryFiles
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

  producingFiles = map (rel: libSource + "/${rel}") libraryFiles ++ [
    (operatorSource + "/read.nix")
  ];

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
        message = row.message;
        emptyMessages = filter (r: r.message == "") result.diagnostics;
      };
      expected = {
        rows = [ "interface-fold-refusal-malformed" ];
        subject = "reader:only";
        namesTheSlot = true;
        namesTheInterface = true;
        message = row.message;
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
        # Every `fail` of either realiser is answered by a named row producer, or
        # by a reason this table states for why no deployment reaches it.
        unaccounted = unaccountedRefusals;
        namedByNoProducer = rowsNamedByNoProducer;
        readSomeRefusals = length everyRefusal;
        readSomeProducers = length producerIds > 20;
        # The rows the accounting names are rows this tree really produces.
        theReadingProducesThem = reading.rows;
      };
      expected = {
        unaccounted = [ ];
        namedByNoProducer = [ ];
        readSomeRefusals = 20;
        readSomeProducers = true;
        theReadingProducesThem = [ ];
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
        id: "docs/diagnostics.md tabulates `${id}`, which nothing under lib/ or operator/ writes"
      ) unproducedRows;
      constructs = documentedConstructs;
    };
    expected = {
      unproduced = [ ];
      constructs = treeConstructs;
    };
  };
}
