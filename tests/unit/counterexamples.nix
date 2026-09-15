# Counterexamples: one test per invariant this tree states about itself and does
# not hold. Every test asserts the documented claim, so each is red until the
# claim is made true or the claim is withdrawn, and none of them asserts what the
# tree does today.
#
# Only claims whose counterexample can be evaluated live here. A deployment that
# ends the evaluation instead of producing a row cannot be asserted by nix-unit at
# all - the raise takes the run that would report it - and those probes are in
# tests/counterexamples/, run one process each by `checks.planner-totality`.
{
  planner,
  support,
  operatorSource,
  imageSource,
  flakeletSource,
  secretsSource,
}:
let
  inherit (builtins)
    attrNames
    concatLists
    concatStringsSep
    filter
    head
    isString
    length
    map
    removeAttrs
    split
    ;

  inherit (support)
    hasInfix
    hasRow
    planOf
    publicString
    rowIds
    rowsById
    secretFile
    soleRoot
    ;

  # The realiser readings, wired the way every other suite wires them: each
  # directory is its own store path here, so a relative import out of one would
  # resolve outside the store.
  assemble = name: text: "/nix/store/${planner.util.shortHash text}-${name}";
  imageReader = import (imageSource + "/read.nix") { inherit planner assemble; };
  flakeletReader = import (flakeletSource + "/read.nix") {
    inherit planner;
    reader = imageReader;
  };
  operatorReader = import (operatorSource + "/read.nix") {
    inherit planner imageReader flakeletReader;
  };
  secretsReader = import (secretsSource + "/read.nix") { inherit planner; };
  secretsStep = import (secretsSource + "/backend.nix") {
    inherit planner;
    reader = secretsReader;
  };

  readBy =
    realiser: result:
    operatorReader.read {
      inherit (result) plan diagnostics;
      realise.default.realiser = realiser;
    };

  lines = text: filter isString (split "\n" text);
  blocks = text: filter isString (split "\n\n" text);

  placedKeys = result: filter (key: result.plan.${key} ? placement) (attrNames result.plan);
  valueKeys = result: filter (key: result.plan.${key} ? delivery) (attrNames result.plan);

  quiet = _: { impl = _: { units.main.command = "/bin/true"; }; };
  unitNamed = name: _: { impl = _: { units.${name}.command = "/bin/true"; }; };

  onOne = module: {
    inherit module;
    placement.every.only.machines = [ "one" ];
  };

  greeting = planner.interface {
    name = "greeting";
    exports.text = publicString;
  };

  identity = planner.interface {
    name = "identity";
    exports.key = secretFile;
  };

  # A member whose slot set moves with its settings: the cheapest deployment whose
  # table is one warning row and no error, which is what a subject rule is read
  # against.
  slotSetMoves = {
    module =
      { service, ... }:
      {
        services.only = service "only" {
          module =
            { settings, ... }:
            {
              uses = if settings.extra then { peer.interface = greeting; } else { };
              impl = _: { units.main.command = "/bin/true"; };
            };
          defaults.extra = true;
        };
      };
    settings.only.extra = false;
    placement.every.only.machines = [ "one" ];
  };

  # A generated value with one secret file, owned by an instance placed on `one`.
  valueOwner =
    {
      file ? { },
      generator ? { },
    }:
    _: {
      vars.token = {
        files."key" = {
          secrecy = "secret";
        }
        // file;
      }
      // generator;
      provides.identity.interface = identity;
      impl =
        { vars, ... }:
        {
          provides.identity.exports.key = vars.token."key";
          units.main = {
            command = "/bin/true";
            env.KEYFILE = vars.token."key".path;
          };
        };
    };

  configured = file: _: {
    impl = _: {
      units.main.command = "/bin/true";
      configData."/etc/app.conf" = {
        mode = "0444";
      }
      // file;
    };
  };
in
{
  # Keys and identity: "An artifact is addressed by the name its plan key projects
  # onto ... The projection is not injective, so two keys sharing one name is
  # `operator-entry-name-collision` rather than a silent overwrite."
  # The projection that is compared carries the machine, so it cannot collide
  # inside one machine; the projection that decides a unit file name drops it.
  testTwoEntriesOfOneMachineDoNotShareAUnitFileName =
    let
      result = planOf {
        instances.a = {
          module =
            { service, ... }:
            {
              services.b = service "b" { module = unitNamed "c-main"; };
              services."b-c" = service "b-c" { module = unitNamed "main"; };
            };
          placement.every.b.machines = [ "one" ];
          placement.every."b-c".machines = [ "one" ];
        };
      };
      reading = readBy "flakelet" result;
      files = concatLists (map (entry: entry.units) (builtins.attrValues reading.entries));
      doubled = filter (file: length (filter (other: other == file) files) > 1) (
        planner.util.uniqueStrings files
      );
    in
    {
      expr = {
        inherit doubled;
        reported = doubled == [ ] || reading.rows != [ ];
      };
      expected = {
        doubled = [ "a-b-c-main.service" ];
        reported = true;
      };
    };

  # Realisers: "The reading classifies a plan record by what it records and never
  # by the text of its key ... one matching none of the three is
  # `operator-plan-record-unclassified`." A member named `""` carries none of the
  # three key separators, so it is planned, and `parseKey`'s three groups each
  # want a character: the record is dropped from the manifest with no row.
  testEveryPlacedEntryIsReadOrNamed =
    let
      result = planOf {
        instances.app = {
          module =
            { service, ... }:
            {
              services.good = service "good" { module = quiet; };
              services."" = service "" { module = quiet; };
            };
          placement.every.good.machines = [ "one" ];
          placement.every."".machines = [ "one" ];
        };
      };
      reading = readBy "flakelet" result;
      named = key: reading.entries ? ${key} || filter (row: row.subject == key) reading.rows != [ ];
    in
    {
      expr = {
        placed = placedKeys result;
        unread = filter (key: !(named key)) (placedKeys result);
      };
      expected = {
        placed = [
          "app:@one"
          "app:good@one"
        ];
        unread = [ ];
      };
    };

  # Realisers: "One store entry per generated value" and the four projection
  # refusals. `keysOf` selects values by matching `(.+):vars/(.+)` against the key
  # text, so a value of an instance named `""` is in no store entry, in no
  # delivery and in no row: the external generator is asked for bytes a unit opens.
  testTheSecretsReadingSeesEveryGeneratedValueThePlanCarries =
    let
      result = planOf {
        instances."" = onOne (soleRoot {
          module = valueOwner {
            generator.program = "/nix/store/00000000000000000000000000000000-gen.drv";
          };
          provides = [ "identity" ];
        });
      };
      seen = length (secretsReader.valuesOf result.plan);
    in
    {
      expr = {
        planned = valueKeys result;
        everyValueIsSeenOrRefused =
          seen == length (valueKeys result)
          ||
            secretsReader.rows {
              inherit (result) plan;
            } != [ ];
      };
      expected = {
        planned = [ ":vars/token@one" ];
        everyValueIsSeenOrRefused = true;
      };
    };

  # Keys and identity: "A field enters a key only where its value differs from
  # the default it would resolve to unstated". A record byte-identical to the one
  # an omission resolves to therefore keys as it did, and a re-keyed value is a
  # regenerated secret.
  testStatingAGeneratedFileDefaultDoesNotRekeyTheValue =
    let
      valueOf =
        file:
        (planOf {
          instances.app = onOne (soleRoot {
            module = valueOwner { inherit file; };
            provides = [ "identity" ];
          });
        }).plan."app:vars/token@one";
      unstated = valueOf { };
      stated = valueOf {
        mode = "0400";
        owner = "root";
        group = "root";
      };
    in
    {
      expr = {
        recordsAreEqual = removeAttrs unstated [ "key" ] == removeAttrs stated [ "key" ];
        keyMoved = unstated.key != stated.key;
      };
      expected = {
        recordsAreEqual = true;
        keyMoved = false;
      };
    };

  # Keys and identity: "Stating a default is therefore no re-key, whichever
  # record states it, and a configuration file's `mode`, which has no default to
  # sit at, is always in the key". The same rule one file kind over: an entry
  # re-keyed here is a new digest under the image realiser, a new artifact and a
  # stop/detach/attach of a running unit for an edit that changes no byte.
  testStatingAConfigurationFileOwnershipDefaultDoesNotRekeyTheEntry =
    let
      entryOf =
        file:
        (planOf {
          instances.app = onOne (soleRoot {
            module = configured ({ render = [ { text = "a"; } ]; } // file);
          });
        }).plan."app:only@one";
      unstated = entryOf { };
      stated = entryOf {
        owner = "root";
        group = "root";
      };
    in
    {
      expr = {
        recordsAreEqual = removeAttrs unstated [ "key" ] == removeAttrs stated [ "key" ];
        keyMoved = unstated.key != stated.key;
      };
      expected = {
        recordsAreEqual = true;
        keyMoved = false;
      };
    };

  # Keys and identity: a plan key names one record. `machine` is a legal instance
  # name and the plan is one `//` of three families, so an unplaced member named
  # after a machine replaces that machine's record: the address is gone and every
  # placed entry's `dependsOn` still names the key of the record that was there.
  testAPlanKeyNamesOneRecord =
    let
      result = planOf {
        instances.machine = {
          module = { service, ... }: { services.one = service "one" { module = quiet; }; };
        };
        instances.app = onOne (soleRoot {
          module = quiet;
        });
      };
      record = result.plan."machine:one";
    in
    {
      expr = {
        theMachineRecordSurvives = record ? address;
        itIsNotAServiceEntry = !(record ? placement);
        theProvenanceEdgeResolves = result.plan."app:only@one".dependsOn == [ "machine:one@${record.key}" ];
      };
      expected = {
        theMachineRecordSurvives = true;
        itIsNotAServiceEntry = true;
        theProvenanceEdgeResolves = true;
      };
    };

  # Diagnostics: "`row`, `error` and `warning` ... are what applies `util.oneLine`,
  # so one row is one line whatever a deployment interpolated into it, and a
  # rendered table cannot show a row nobody produced." A subject passes through
  # neither, and `mkTable`'s own subject repair rewrites a row outside those
  # three, so a name carrying a line break - which the key grammar admits, it
  # being none of `@`, `:`, `/` - renders one row as two lines.
  testASubjectCarryingALineBreakRendersOneLinePerRow =
    let
      result = planOf {
        instances.${"app\nsecond line"} = slotSetMoves;
        sources.deployment = "deployment.nix";
      };
      rendered = planner.render result.diagnostics;
    in
    {
      expr = {
        renderedBlocks = length (blocks rendered);
        linesPerBlock = map (block: length (lines block)) (blocks rendered);
      };
      expected = {
        renderedBlocks = length result.diagnostics;
        linesPerBlock = map (_: 4) result.diagnostics;
      };
    };

  # Diagnostics: "A subject is a plan key, a path relative to the deployment root,
  # or an issue identifier", against Keys and identity: the name grammar "is a
  # denylist of the three separators rather than an allowlist". `isPlanKey` is an
  # allowlist, so a plan key the planner built from a legal name is refused as a
  # subject and the error that says so makes a warning-only table deployment-fatal.
  testANameTheKeyGrammarAdmitsIsNotRefusedByTheSubjectRule =
    let
      tabled =
        name:
        planOf {
          instances.${name} = slotSetMoves;
          sources.deployment = "deployment.nix";
        };
    in
    {
      expr = {
        ascii = (tabled "cafe").applicable;
        plussed = (tabled "app+1").applicable;
        spaced = (tabled "app v2").applicable;
        ids = rowIds (tabled "app+1");
      };
      expected = {
        ascii = true;
        plussed = true;
        spaced = true;
        ids = [ "slot-set-settings-derived" ];
      };
    };

  # Diagnostics: "The same fact produced twice is one row. `dedup` keeps the
  # first." `mkTable` repairs an out-of-grammar subject to its last path component
  # and dedups afterwards, so two facts about two files whose names agree collapse
  # and a reader never learns about the second module.
  testTwoModuleFilesSharingABasenameKeepTwoRows =
    let
      result = planOf {
        instances = {
          app = slotSetMoves;
          other = slotSetMoves;
        };
        sources = {
          deployment = "deployment.nix";
          leaves = {
            app.only = "/home/one/modules/leaf.nix";
            other.only = "/home/two/modules/leaf.nix";
          };
        };
      };
    in
    {
      expr = length (rowsById "slot-set-settings-derived" result);
      expected = 2;
    };

  # Diagnostics: "one row is one line whatever a deployment interpolated into it",
  # where the library's own definition of a line break is `[\n\r]`. `oneLine`
  # replaces `\n` alone, so a fold - the one channel a module states a message
  # through - can rewrite the subject and the message a reader sees.
  testAFoldRefusalCannotCarryACarriageReturn =
    let
      refusing = planner.interface {
        name = "pub";
        exports.text = publicString;
        fold = _: planner.refuse "\r  ! vault:only@one  every value of this set was accepted";
      };
      provider = _: {
        provides.pub.interface = refusing;
        impl = _: {
          provides.pub.exports.text = "hi";
          units.main.command = "/bin/true";
        };
      };
      consumer = _: {
        uses.far = {
          interface = refusing;
          reach = "all";
          reads = [ "text" ];
        };
        impl = _: { units.main.command = "/bin/true"; };
      };
      result = planOf {
        instances = {
          provider =
            onOne (soleRoot {
              module = provider;
              provides = [ "pub" ];
            })
            // {
              exposes = [ "pub" ];
            };
          consumer =
            onOne (soleRoot {
              module = consumer;
            })
            // {
              wire.far = {
                instance = "provider";
                provides = "pub";
              };
            };
        };
      };
      row = head (rowsById "interface-fold-refused" result);
    in
    {
      expr = planner.util.carriesLineBreak row.message;
      expected = false;
    };

  # Diagnostics: a row's severity is the producer's, and `lib/diagnostics.nix`
  # states the domain as `severities`. Nothing reads it: a row built through the
  # exported `row` with any severity at all is tabled, rendered, and counted as no
  # error by every reading that asks `severity == "error"`.
  testARowSeverityIsHeldToTheStatedDomain =
    let
      built =
        severity:
        planner.mkTable [
          (planner.row {
            id = "x-row";
            subject = "app:only@one";
            inherit severity;
            message = "m";
            evidence = "e";
            resolution = "r";
          })
        ];
    in
    {
      expr = {
        offDomain = map (row: row.severity) (built "info");
        lineCount = length (lines (planner.render (built "warning\n      note: forged")));
      };
      expected = {
        offDomain = [ "error" ];
        lineCount = 4;
      };
    };

  # Interfaces: "A secret export must publish a generated file, never a bare
  # value ... A path in the plan is deliverable; bytes in the plan are a leak."
  # Nothing compares an export atom's secrecy with the secrecy of the file backing
  # it, so a generated file that omitted `secrecy` hands its `content` to a module
  # whose interface calls the value secret, and the bytes are in the plan.
  testASecretExportMayNotBeBackedByAPublicFile =
    let
      loose = planner.interface {
        name = "identity";
        exports.key = {
          type = planner.korora.attrs;
          secrecy = "secret";
        };
      };
      owner = _: {
        vars.app.files."key" = { };
        provides.identity.interface = loose;
        impl =
          { vars, ... }:
          {
            provides.identity.exports.key = vars.app."key";
            units.main = {
              command = "/bin/true";
              env.TOKEN = vars.app."key".content;
            };
          };
      };
      result = planOf {
        varsState."app:vars/app@one"."key" = {
          present = true;
          content = "hunter2";
        };
        instances.app = onOne (soleRoot {
          module = owner;
          provides = [ "identity" ];
        });
      };
    in
    {
      expr = {
        applicable = result.applicable;
        bytesInThePlan = result.plan."app:only@one".units.main.env.TOKEN or "<absent>";
      };
      expected = {
        applicable = false;
        bytesInThePlan = "<absent>";
      };
    };

  # Interfaces: a claimed identity is nominal and name-deep, so korora's `struct`
  # putting no member in `type.name` is the recorded trade and not the defect: two
  # member sets under one claim are one identity and the edge resolves. What the
  # claim may not do is stand in for the structural check, which is made where the
  # value crosses the wire, against the consuming interface's own declared type.
  testAClaimedIdentityDoesNotCollapseTwoStructSchemas =
    let
      endpointOf =
        members:
        planner.interface {
          name = "endpoint";
          id = "example.com/endpoint";
          exports.where.type = planner.korora.struct "endpoint" members;
        };
      provided = endpointOf {
        host = planner.korora.string;
        port = planner.korora.string;
      };
      consumed = endpointOf {
        host = planner.korora.string;
        port = planner.korora.int;
      };
      provider = _: {
        provides.endpoint.interface = provided;
        impl = _: {
          provides.endpoint.exports.where = {
            host = "db.example";
            port = "5432";
          };
          units.main.command = "/bin/true";
        };
      };
      consumer = _: {
        uses.far = {
          interface = consumed;
          reads = [ "where" ];
        };
        impl = _: { units.main.command = "/bin/true"; };
      };
      result = planOf {
        instances = {
          provider =
            onOne (soleRoot {
              module = provider;
              provides = [ "endpoint" ];
            })
            // {
              exposes = [ "endpoint" ];
            };
          consumer =
            onOne (soleRoot {
              module = consumer;
            })
            // {
              wire.far = {
                instance = "provider";
                provides = "endpoint";
              };
            };
        };
      };
    in
    {
      expr = {
        identitiesAgree = planner.identityOf provided == planner.identityOf consumed;
        rows = map (
          row:
          removeAttrs row [
            "evidence"
            "message"
            "resolution"
            "severity"
          ]
        ) (rowsById "slot-read-type-mismatch" result);
        namesTheSlot = hasInfix "slot `far` of `consumer:only`" (
          (head (rowsById "slot-read-type-mismatch" result)).message
        );
        slotFilled = result.plan."consumer:only@one".reads.far ? values;
        providerStillPlanned = result.plan ? "provider:only@one";
        applicable = result.applicable;
      };
      expected = {
        identitiesAgree = true;
        rows = [
          {
            id = "slot-read-type-mismatch";
            subject = "consumer:only";
          }
        ];
        namesTheSlot = true;
        slotFilled = false;
        providerStillPlanned = true;
        applicable = false;
      };
    };

  # Interfaces: "The readability comparison is one predicate, `util.admits`, asked
  # at the three sites that hold the facts ... A fourth site is a place to forget
  # it." The planner asks it of a consumer's declared reads and of a configuration
  # file, never of the entry's own generated value, so a unit that cannot open its
  # own secret is a row under one realiser's profile and silence everywhere else.
  testAUnitThatCannotOpenItsOwnValueIsARow =
    let
      result = planOf {
        instances.app = onOne (soleRoot {
          module = _: {
            vars.token.files."key" = {
              secrecy = "secret";
              owner = "root";
              group = "root";
              mode = "0400";
            };
            provides.identity.interface = identity;
            impl =
              { vars, ... }:
              {
                provides.identity.exports.key = vars.token."key";
                units.main = {
                  command = "/bin/true";
                  user = "nobody";
                  env.KEYFILE = vars.token."key".path;
                };
              };
          };
          provides = [ "identity" ];
        });
      };
    in
    {
      expr = result.applicable;
      expected = false;
    };

  # Interfaces: "An undeployed value is on no machine, so binding its path mounts
  # nothing and the unit fails at `226/NAMESPACE` naming neither the value nor the
  # declaration." A value delivered to one machine and named by an entry on
  # another is the same run-time failure, and the row family that reports the
  # `deploy = false` case has no delivery-set half.
  testNamingAValuePathOnAMachineOutsideTheDeliverySetIsARow =
    let
      pathAndKey = planner.interface {
        name = "identity";
        exports = {
          key = secretFile;
          keyPath = publicString;
        };
      };
      owner = _: {
        vars.app.files."key".secrecy = "secret";
        provides.identity.interface = pathAndKey;
        impl =
          { vars, ... }:
          {
            provides.identity.exports = {
              key = vars.app."key";
              keyPath = vars.app."key".path;
            };
            units.main.command = "/bin/true";
          };
      };
      consumer = _: {
        uses.far = {
          interface = pathAndKey;
          reads = [ "keyPath" ];
        };
        impl =
          { results, ... }:
          {
            units.main = {
              command = "/bin/true";
              env.KEYFILE = results.far.keyPath;
            };
          };
      };
      result = planOf {
        instances = {
          owner =
            onOne (soleRoot {
              module = owner;
              provides = [ "identity" ];
            })
            // {
              exposes = [ "identity" ];
            };
          consumer = {
            module = soleRoot { module = consumer; };
            placement.every.only.machines = [ "two" ];
            wire.far = {
              instance = "owner";
              provides = "identity";
            };
          };
        };
      };
    in
    {
      expr = {
        delivery = result.plan."owner:vars/app@one".delivery;
        applicable = result.applicable;
      };
      expected = {
        delivery = [ "one" ];
        applicable = false;
      };
    };

  # Interfaces: "The `interfaces` argument is attribution, never a registry" and
  # "Attribution decides what a row says and nothing about which rows exist."
  # Listing an interface no module of the deployment imports turns a buildable
  # deployment into an inapplicable one, over a declaration it never reaches.
  testAttributionDoesNotDecideApplicability =
    let
      stray = planner.interface {
        name = "stray";
        exports.text = { };
      };
      leaf = _: {
        provides.greeting.interface = greeting;
        impl = _: {
          provides.greeting.exports.text = "hi";
          units.main.command = "/bin/true";
        };
      };
      run =
        interfaces:
        planOf {
          inherit interfaces;
          instances.app = onOne (soleRoot {
            module = leaf;
            provides = [ "greeting" ];
          });
        };
      bare = run { };
      listed = run { "interfaces/stray.nix".stray = stray; };
    in
    {
      expr = {
        samePlan = bare.plan == listed.plan;
        bare = bare.applicable;
        listed = listed.applicable;
      };
      expected = {
        samePlan = true;
        bare = true;
        listed = true;
      };
    };

  # Diagnostics: "A refusal is recognised by the marker attribute that
  # constructor writes and by nothing else, so a fold's own successful result may
  # carry an attribute named `refused`". A partitioning fold - the shape a fold
  # exists for - therefore delivers its set: its own `refused` list is a member
  # of the result and no refusal of the whole. The delivered set is named by the
  # consumer's own unit, so the one row this deployment earns is the warning any
  # set-valued read whose membership enters a key earns.
  testAFoldMayReturnAnAttributeCalledRefused =
    let
      partitioning = planner.interface {
        name = "pub";
        exports.text = publicString;
        fold = set: {
          accepted = attrNames set;
          refused = filter (key: set.${key}.text == "") (attrNames set);
        };
      };
      provider = _: {
        provides.pub.interface = partitioning;
        impl = _: {
          provides.pub.exports.text = "hi";
          units.main.command = "/bin/true";
        };
      };
      consumer = _: {
        uses.far = {
          interface = partitioning;
          reach = "all";
          reads = [ "text" ];
        };
        impl =
          { results, ... }:
          {
            units.main = {
              command = "/bin/true";
              env.ACCEPTED = if results ? far then concatStringsSep "," results.far.accepted else "<absent>";
            };
          };
      };
      result = planOf {
        instances = {
          provider =
            onOne (soleRoot {
              module = provider;
              provides = [ "pub" ];
            })
            // {
              exposes = [ "pub" ];
            };
          consumer =
            onOne (soleRoot {
              module = consumer;
            })
            // {
              wire.far = {
                instance = "provider";
                provides = "pub";
              };
            };
        };
      };
    in
    {
      expr = {
        applicable = result.applicable;
        refusals = rowsById "interface-fold-refused" result;
        malformed = rowsById "interface-fold-refusal-malformed" result;
        accepted = result.plan."consumer:only@one".units.main.env.ACCEPTED;
      };
      expected = {
        applicable = true;
        refusals = [ ];
        malformed = [ ];
        accepted = "provider:only@one";
      };
    };

  # Realisers: the image "binds a configuration file from the store only where the
  # plan holds its bytes", and flakelet's own reading says such a file "arrives
  # with the artifact's closure". A `source` is read for neither its kind nor its
  # store, so a host path outside the store is bound into a unit and a non-string
  # reaches `readFile` in the builder.
  testAConfigurationFileSourceIsReadForItsKindAndHeldToTheStore =
    let
      refusedFor =
        source:
        !(planOf {
          instances.app = onOne (soleRoot {
            module = configured { inherit source; };
          });
        }).applicable;
    in
    {
      expr = {
        hostPath = refusedFor "/etc/ssl/private/host.key";
        otherKind = refusedFor 42;
      };
      expected = {
        hostPath = true;
        otherKind = true;
      };
    };

  # Realisers: "An image carries an empty file at every host path it is shown."
  # Two shown paths of one entry that nest cannot both be files: the image builder
  # stops at `install: cannot create directory ... Not a directory` and the
  # flakelet builder at `mkdir: cannot create directory 'files/etc/app'`, naming a
  # store path and no declaration. The planner's own claim index compares exact
  # duplicates only.
  testTwoShownHostPathsOfOneEntryMayNotNest =
    let
      result = planOf {
        instances.app = onOne (soleRoot {
          module = _: {
            impl = _: {
              units.main.command = "/bin/true";
              configData."/etc/app" = {
                mode = "0444";
                render = [ { text = "a\n"; } ];
              };
              configData."/etc/app/inner.conf" = {
                mode = "0444";
                render = [ { text = "b\n"; } ];
              };
            };
          };
        });
      };
    in
    {
      expr = result.applicable;
      expected = false;
    };

  # Diagnostics: "`unit-value-newline` is about every string a unit record carries
  # at any depth - a plain field, an element of a list, a name or a value of an
  # attribute set". The name of the unit itself is the outermost such name and is
  # scanned by nobody: flakelet's unit rule is built out of `builtins.match`,
  # whose `.` matches a newline, so the artifact renders a directive no module
  # wrote.
  testAUnitNameCarryingALineBreakIsARow =
    let
      result = planOf {
        instances.app = onOne (soleRoot {
          module = unitNamed "main\nConditionPathExists=/nonexistent";
        });
      };
    in
    {
      expr = {
        reported = hasRow "unit-value-newline" result;
        applicable = result.applicable;
      };
      expected = {
        reported = true;
        applicable = false;
      };
    };

  # Diagnostics: "A configuration file's host path is held to the grammar one word
  # of a rendered shell step can carry ... The check is the library's, so every
  # realiser and every plan reader inherits it." A unit file is a third consumer
  # with a grammar of its own: `:` is systemd's field separator in
  # `BindReadOnlyPaths=` and the directive is dropped, and `%` introduces a
  # specifier and the bind lands on a path the image has no mount point for.
  testAConfigurationFilePathIsAWordAUnitFileCanBind =
    let
      rowsFor =
        path:
        rowIds (planOf {
          instances.app = onOne (soleRoot {
            module = _: {
              impl = _: {
                units.main.command = "/bin/true";
                configData.${path} = {
                  mode = "0444";
                  render = [ { text = "hello\n"; } ];
                };
              };
            };
          });
        });
    in
    {
      expr = {
        colon = rowsFor "/etc/a:b";
        specifier = rowsFor "/etc/a%bc";
      };
      expected = {
        colon = [ "config-file-path-refused" ];
        specifier = [ "config-file-path-refused" ];
      };
    };

  # Diagnostics: "`image/read.nix` renders a unit's `env` key into the file as
  # `Environment="<k>=<v>"` and escapes the key with nothing". The reasoning is
  # about a line break; a double quote is the same free directive, and systemd
  # answers `Invalid syntax, ignoring` and starts the unit without the variable.
  testAnEnvironmentNameIsEscapedTheWayItsValueIs =
    let
      result = planOf {
        instances.app = onOne (soleRoot {
          module = _: {
            impl = _: {
              units.main = {
                command = "/bin/true";
                env."QUOTED\"KEY" = "v";
              };
            };
          };
        });
      };
      image = imageReader.read {
        inherit (result) plan;
        key = "app:only@one";
        profile = "trusted";
      };
      rendered = imageReader.renderUnit image "main";
      directive = head (filter (line: hasInfix "Environment=" line) (lines rendered));
    in
    {
      # Either the plan refuses the name or the rendered directive escapes it the
      # way the same line's value is escaped. Today it is `Environment="QUOTED"KEY=v"`,
      # which systemd answers `Invalid syntax, ignoring`.
      expr = rowIds result != [ ] || directive == ''Environment="QUOTED\"KEY=v"'';
      expected = true;
    };

  # Keys and identity: an image's version digest "is taken over what the artifact
  # holds", and the operator's command reads it as identity equality. The
  # confinement profile is what the artifact attaches under and is in the attach
  # script, and it is not in the digest: tightening a profile leaves one digest,
  # one image name, `nothing changed` on every apply and `current` in the report.
  testTheVersionDigestCarriesTheConfinementProfile =
    let
      result = planOf {
        instances.app = onOne (soleRoot {
          module = quiet;
        });
      };
      versionUnder =
        profile:
        (imageReader.read {
          inherit (result) plan;
          inherit profile;
          key = "app:only@one";
        }).version;
    in
    {
      expr = versionUnder "trusted" == versionUnder "strict";
      expected = false;
    };

  # Realisers: the secrets reading's two halves, "`rows` ... raises nothing, and
  # `store`, `configuration` and `deliveriesOf` refuse with the sentence that row
  # states". A file record's ownership is one of the words the rendered deploy
  # step escapes and `rows` asks about the path and the address only, so an owner
  # the `userName` atom admits and `wordRule` refuses is a bare `throw` where the
  # operator is owed a table.
  testAnOwnershipTheRenderRefusesIsARowFirst =
    let
      result = planOf {
        instances.app = onOne (soleRoot {
          module = valueOwner {
            file.owner = "svc$";
            generator = {
              per = "instance";
              program = "/nix/store/00000000000000000000000000000000-gen.drv";
            };
          };
          provides = [ "identity" ];
        });
      };
      rendered = builtins.tryEval (
        builtins.deepSeq (secretsStep.render {
          inherit (result) plan;
          get = "/nix/store/00000000000000000000000000000000-get";
        }) "rendered"
      );
    in
    {
      expr = {
        planApplicable = result.applicable;
        renderRefuses = !rendered.success;
        reportedAsARow = secretsReader.rows { inherit (result) plan; } != [ ];
      };
      expected = {
        planApplicable = true;
        renderRefuses = true;
        reportedAsARow = true;
      };
    };
}
