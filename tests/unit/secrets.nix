{
  planner,
  support,
  secretsSource,
  operatorSource,
  imageSource,
  flakeletSource,
}:
let
  inherit (builtins)
    attrNames
    filter
    head
    ;

  inherit (support)
    hasInfix
    lines
    planOf
    raises
    rowIds
    soleRoot
    ;

  realiser = support.realiser {
    inherit
      imageSource
      flakeletSource
      operatorSource
      secretsSource
      ;
  };

  inherit (realiser) operatorReader;

  reader = realiser.secretsReader;

  deployStep = import (secretsSource + "/backend.nix") { inherit planner reader; };

  # The same renderer over a reading whose word rule admits everything. The
  # grammar and the escape have to fail independently, so the escape is read
  # where the grammar catches nothing.
  unruled = import (secretsSource + "/backend.nix") {
    inherit planner;
    reader = reader // {
      unrenderable = _: false;
    };
  };

  rowsOf = plan: reader.rows { inherit plan; };
  idsOf = plan: map (row: row.id) (rowsOf plan);
  rowsById = id: plan: filter (row: row.id == id) (rowsOf plan);
  oneRow = id: plan: head (rowsById id plan);

  programOf = gen: "/nix/store/9dm4x2vqk7z1n5bpr3jlfg8ys6cwh0az-generate-${gen}.drv";
  getProgram = "/nix/store/3q8xk1p7v2mz9jd4rlnb6ycsfwg0h5aq-age-backend/bin/secrets-age-backend";
  sealProgram = "/nix/store/7b5wq2ckx9nz4mj1pdlr8vfhs6gy03at-age-1.2.1/bin/age";

  # One age native recipient, the public line `age-keygen` prints: one word of
  # the grammar a rendered step can carry, which is what lets the recipient be
  # a word rather than a file in the store.
  recipient = "age1ql3z7hjy54pw3hyww5ayyfg7zqgvc7w3j2elw8zmrj2kg5sfn9aqmcac8p";

  caBytes = "PUBLIC-CA-BYTES";

  # One instance, three generators: a shared secret every placement receives, a
  # value nobody receives, and one value per placement that reads the shared one.
  module =
    {
      program ? true,
      reads ? [ "session" ],
    }:
    let
      declared = gen: if program then { program = programOf gen; } else { };
    in
    _: {
      vars = {
        session = {
          per = "instance";
          files.token.secrecy = "secret";
        }
        // declared "session";

        ca = {
          per = "instance";
          deploy = false;
          files."ca.pub".secrecy = "public";
        }
        // declared "ca";

        host = {
          inherit reads;
          files."key".secrecy = "secret";
        }
        // declared "host";
      };

      impl =
        { vars, ... }:
        {
          units.only = {
            command = "/bin/true";
            env = {
              TOKEN_FILE = vars.session.token.path;
              HOST_KEY_FILE = vars.host."key".path;
              CA_CERT = vars.ca."ca.pub".content;
            };
          };
        };
    };

  deployment =
    args:
    planOf {
      instances.issuer = {
        module = soleRoot { module = module args; };
        placement.every.only.machines = [
          "one"
          "two"
        ];
      };
      varsState = {
        "issuer:vars/session".token.present = true;
        "issuer:vars/ca"."ca.pub" = {
          present = true;
          content = caBytes;
        };
        "issuer:vars/host@one"."key".present = true;
        "issuer:vars/host@two"."key".present = true;
      };
    };

  worked = deployment { };

  storeOf =
    plan:
    reader.store {
      inherit plan;
      backend = "age";
    };

  configurationOf =
    plan:
    reader.configuration {
      inherit plan;
      backend = "age";
      backends = {
        prompt = { };
        store.age = { };
      };
    };

  renderOf =
    plan:
    deployStep.render {
      inherit plan;
      get = getProgram;
      seal = sealProgram;
    };

  # A file record as the planner writes one. The ownership and the mode are
  # always there, the rendered step carrying all three as words, so a record
  # missing one is a row about the record rather than about the file's name.
  handFile =
    attrs:
    {
      owner = "root";
      group = "root";
      mode = "0400";
      secrecy = "secret";
      inPlan = "reference";
    }
    // attrs;

  # A value entry as the planner emits one, for the two refusals a plan the
  # planner produces cannot reach: a key two components can be read out of, and a
  # component carrying the character the name joins on.
  synthetic =
    entries:
    {
      "machine:one" = {
        key = "sha256-0000000000000000";
        address = "one.example:22";
        tags = [ ];
      };
    }
    // builtins.mapAttrs (
      _: entry:
      {
        key = "sha256-0000000000000000";
        per = "instance";
        deploy = true;
        delivery = [ "one" ];
        deliveryDerivedFrom = [ "written by hand" ];
        program = programOf "hand";
        files.token = handFile { path = "/run/vars/hand/token"; };
      }
      // entry
    ) entries;

  # The calls of one rendered step, by the name the reading gave that step.
  callLines = step: text: filter (line: builtins.match " *${step} .*" line != null) (lines text);
  deliverLines = callLines "deliver";
  sealLines = callLines "seal_copy";

  # The worked plan with one field of the shared value's only file replaced, so
  # a word the rendered step carries can be moved one at a time.
  sessionFileWith =
    attrs:
    worked.plan
    // {
      "issuer:vars/session" = worked.plan."issuer:vars/session" // {
        files.token = worked.plan."issuer:vars/session".files.token // attrs;
      };
    };

  # The worked plan with a recipient stated on the machine records named and
  # none on the others: the plan's own machine record is where a machine says
  # whether its values are sealed, so the whole difference between a fleet that
  # seals and one that does not is one field of one record.
  withRecipients =
    recipients:
    worked.plan
    // builtins.mapAttrs (key: line: worked.plan.${key} // { sealRecipient = line; }) recipients;

  sealing = withRecipients {
    "machine:one" = recipient;
    "machine:two" = null;
  };

  bothSealing = withRecipients {
    "machine:one" = recipient;
    "machine:two" = recipient;
  };

  unsealed = withRecipients {
    "machine:one" = null;
    "machine:two" = null;
  };
in
{
  testAGeneratedValueBecomesOneStoreEntry =
    let
      store = storeOf worked.plan;
      configuration = configurationOf worked.plan;
    in
    {
      expr = {
        rows = rowIds worked;
        names = attrNames store;
        session = store."issuer:session";
        final = configuration._type;
        theConfigurationCarriesTheSameEntries = attrNames configuration.store == attrNames store;
        aServiceEntryContributesNone = filter (name: hasInfix "only" name) (attrNames store);
      };
      expected = {
        rows = [ ];
        names = [
          "issuer:ca"
          "issuer:host:one"
          "issuer:host:two"
          "issuer:session"
        ];
        session = {
          backend = "age";
          dependencies = [ ];
          generate = programOf "session";
          prompts = { };
          files.token.deploy = true;
        };
        final = "secrets-configuration";
        theConfigurationCarriesTheSameEntries = true;
        aServiceEntryContributesNone = [ ];
      };
    };

  testADeclaredReadBecomesADependency =
    let
      store = storeOf worked.plan;
      cyclic = deployment { reads = [ "host" ]; };
    in
    {
      expr = {
        reader = store."issuer:host:one".dependencies;
        theOtherPlacement = store."issuer:host:two".dependencies;
        theValueRead = store."issuer:session".dependencies;
        cycleRows = rowIds cyclic;
        # A cycle is refused before the reading, and the reads the planner
        # recorded are none, so no order is derived from a cycle.
        cycleDependencies = (storeOf cyclic.plan)."issuer:host:one".dependencies;
      };
      expected = {
        reader = [ "issuer:session" ];
        theOtherPlacement = [ "issuer:session" ];
        theValueRead = [ ];
        cycleRows = [ "vars-reads-cycle" ];
        cycleDependencies = [ ];
      };
    };

  testAnUndeployedValueIsGeneratedAndSentNowhere =
    let
      store = storeOf worked.plan;
      delivered = map (delivery: delivery.name) (reader.deliveriesOf worked.plan);
    in
    {
      expr = {
        itExists = store ? "issuer:ca";
        files = store."issuer:ca".files;
        itIsGenerated = store."issuer:ca".generate == programOf "ca";
        inherit delivered;
        theScriptNamesIt = hasInfix "issuer:ca" (renderOf worked.plan);
      };
      expected = {
        itExists = true;
        files."ca.pub".deploy = false;
        itIsGenerated = true;
        delivered = [
          "issuer:host:one"
          "issuer:host:two"
          "issuer:session"
        ];
        theScriptNamesIt = false;
      };
    };

  testARequiredFieldThePlanCannotAnswerIsRefused =
    let
      programless = deployment { program = false; };
    in
    {
      expr = {
        theRestOfThePlanIsFine = rowIds programless;
        rows = idsOf programless.plan;
        theReadingAnsweredThem = !(raises (rowsOf programless.plan));
        refused = raises (storeOf programless.plan);
        theWholeConfigurationIsRefused = raises (configurationOf programless.plan);
        # Not the reading's business: a program is a fact about the value, so a
        # plan that carries none is still a plan.
        theEntryIsThere = programless.plan."issuer:vars/session" ? files;
        theEntryCarriesNoProgram = programless.plan."issuer:vars/session" ? program;
      };
      expected = {
        theRestOfThePlanIsFine = [ ];
        rows = [
          "secrets-value-no-program"
          "secrets-value-no-program"
          "secrets-value-no-program"
          "secrets-value-no-program"
        ];
        theReadingAnsweredThem = true;
        refused = true;
        theWholeConfigurationIsRefused = true;
        theEntryIsThere = true;
        theEntryCarriesNoProgram = false;
      };
    };

  testTwoValuesProjectingOntoOneNameAreRefused =
    let
      # `a:b` with generator `c`, and `a` with generator `b:c`: two keys, one
      # name. The planner emits neither, and one would store its bytes over the
      # other's.
      colliding = synthetic {
        "a:b:vars/c" = { };
        "a:vars/b:c" = { };
      };
      apart = synthetic {
        "a:b:vars/c" = { };
        "a:vars/d" = { };
      };
    in
    {
      expr = {
        collisions = map (each: {
          inherit (each) name keys;
        }) (reader.collisionsOf colliding);
        row = removeAttrs (oneRow "secrets-name-collision" colliding) [
          "evidence"
          "severity"
        ];
        refused = raises (storeOf colliding);
        neitherEntryIsEmitted = raises (attrNames (storeOf colliding));
        # The pair is what this refuses. Apart, the second key collides with
        # nothing and is refused on its own account, for the colon it carries.
        apartTheyCollideWithNothing = reader.collisionsOf apart;
        oneOfThemAlone = raises (storeOf apart);
      };
      expected = {
        collisions = [
          {
            name = "a:b:c";
            keys = [
              "a:b:vars/c"
              "a:vars/b:c"
            ];
          }
        ];
        row = {
          id = "secrets-name-collision";
          subject = "a:b:vars/c";
          message = "`a:b:vars/c`, `a:vars/b:c` project onto one name, `a:b:c`, and one would overwrite the other's stored bytes";
          resolution = "rename one of the two";
        };
        refused = true;
        neitherEntryIsEmitted = true;
        apartTheyCollideWithNothing = [ ];
        oneOfThemAlone = true;
      };
    };

  testANameComponentCarryingTheSeparatorIsRefused =
    let
      inGenerator = synthetic {
        "a:vars/b:c" = { };
      };
      inMachine = synthetic {
        "a:vars/b@c:d" = {
          per = "placement";
        };
      };
      clean = synthetic {
        "a:vars/b" = { };
      };
    in
    {
      expr = {
        generator = raises (storeOf inGenerator);
        machine = raises (storeOf inMachine);
        generatorRow = removeAttrs (oneRow "secrets-name-carries-separator" inGenerator) [
          "evidence"
          "severity"
        ];
        machineNamesItsComponent = (oneRow "secrets-name-carries-separator" inMachine).message;
        # The rule and nothing wider: the same plan without the colon is read.
        withoutIt = attrNames (storeOf clean);
        andItRowsNothing = idsOf clean;
      };
      expected = {
        generator = true;
        machine = true;
        generatorRow = {
          id = "secrets-name-carries-separator";
          subject = "a:vars/b:c";
          message = "the generator of `a:vars/b:c` is `b:c`, which carries `:` - the character the projected name joins on, so its name could not be read back";
          resolution = "rename the generator";
        };
        machineNamesItsComponent = "the machine of `a:vars/b@c:d` is `c:d`, which carries `:` - the character the projected name joins on, so its name could not be read back";
        withoutIt = [ "a:b" ];
        andItRowsNothing = [ ];
      };
    };

  testANameComponentOutsideTheContractsGrammarIsRefused =
    let
      spaced = synthetic {
        "a:vars/b c" = { };
      };
      slashed = synthetic {
        "a:vars/b/c" = { };
      };
      reserved = synthetic {
        "a:vars/b" = {
          files.".nixos-secrets-metadata" = handFile { path = "/run/vars/a/b/meta"; };
        };
      };
    in
    {
      expr = {
        space = raises (storeOf spaced);
        slash = raises (storeOf slashed);
        theToolsOwnFileName = raises (storeOf reserved);
        rows = idsOf spaced ++ idsOf slashed;
        spacedNamesTheGrammar = (oneRow "secrets-name-outside-grammar" spaced).message;
      };
      expected = {
        space = true;
        slash = true;
        theToolsOwnFileName = true;
        rows = [
          "secrets-name-outside-grammar"
          "secrets-name-outside-grammar"
        ];
        spacedNamesTheGrammar = "the generator of `a:vars/b c` is `b c`, and a name the external generator admits carries ASCII letters, digits, `_`, `.`, `-` and nothing else";
      };
    };

  testAPerMachineValueKeepsItsMachineInItsName =
    let
      store = storeOf worked.plan;
      keys = filter (key: hasInfix ":vars/host" key) (attrNames worked.plan);
    in
    {
      expr = {
        planKeys = keys;
        names = filter (name: hasInfix "host" name) (attrNames store);
        # Every field but the name is equal, so the name is the only thing that
        # keeps the two machines' values apart in the tool's storage.
        entriesAreOtherwiseEqual = store."issuer:host:one" == store."issuer:host:two";
        theSharedValueNamesNoMachine = reader.nameOf worked.plan "issuer:vars/session";
      };
      expected = {
        planKeys = [
          "issuer:vars/host@one"
          "issuer:vars/host@two"
        ];
        names = [
          "issuer:host:one"
          "issuer:host:two"
        ];
        entriesAreOtherwiseEqual = true;
        theSharedValueNamesNoMachine = "issuer:session";
      };
    };

  testTheRenderedStepTargetsTheDeliverySet =
    let
      script = renderOf worked.plan;
    in
    {
      expr = {
        deliveries = deliverLines script;
        itReadsTheFileList = hasInfix "while read -r generator file" script;
        itRefusesAPairItDoesNotName = hasInfix "the plan names no delivery for" script;
        theBackendIsWhatFetches = hasInfix getProgram script;
        itTakesItsSshOptionsFromTheEnvironment =
          hasInfix "ssh_options=\${PLANNER_SECRETS_SSH_OPTS:-}" script
          && hasInfix "ssh $ssh_options -T" script;
      };
      expected = {
        # The shared value goes to both placements; each per-machine value goes
        # to its own machine and to no other.
        deliveries = [
          "    deliver 'issuer:host:one' 'key' 'root@one.example:22' '/run/vars/issuer/host' '/run/vars/issuer/host/key' '0400' 'root:root'"
          "    deliver 'issuer:host:two' 'key' 'root@two.example:22' '/run/vars/issuer/host' '/run/vars/issuer/host/key' '0400' 'root:root'"
          "    deliver 'issuer:session' 'token' 'root@one.example:22' '/run/vars/issuer/session' '/run/vars/issuer/session/token' '0400' 'root:root'"
          "    deliver 'issuer:session' 'token' 'root@two.example:22' '/run/vars/issuer/session' '/run/vars/issuer/session/token' '0400' 'root:root'"
        ];
        itReadsTheFileList = true;
        itRefusesAPairItDoesNotName = true;
        theBackendIsWhatFetches = true;
        itTakesItsSshOptionsFromTheEnvironment = true;
      };
    };

  testTheLastPairOfTheFileListIsDelivered =
    let
      script = renderOf worked.plan;
      loop = filter (line: hasInfix "while read" line) (lines script);
    in
    {
      expr = {
        # The tool joins the list with newlines, so its last line has none, and a
        # plain `read` returns non-zero having already assigned that line. Without
        # the guard the loop drops the pair: the file is stored and delivered
        # nowhere, and the unit that opens its path fails at NAMESPACE.
        loop = loop;
      };
      expected = {
        loop = [ ''while read -r generator file || [ -n "$generator" ]; do'' ];
      };
    };

  testTheRenderedStepCarriesNoBytes =
    let
      script = renderOf worked.plan;
    in
    {
      expr = {
        # The public value's bytes are in the plan, which is what makes their
        # absence from the script an observation rather than a vacuum.
        thePlanCarriesThem = hasInfix caBytes (builtins.toJSON worked.plan);
        theScriptCarriesThem = hasInfix caBytes script;
        theConfigurationCarriesThem = hasInfix caBytes (builtins.toJSON (configurationOf worked.plan));
      };
      expected = {
        thePlanCarriesThem = true;
        theScriptCarriesThem = false;
        theConfigurationCarriesThem = false;
      };
    };

  testTheRenderedStepWritesASealedCopyForAMachineThatSeals =
    let
      script = renderOf sealing;
      numbered = lines script;
      at =
        needle:
        head (
          filter (i: hasInfix needle (builtins.elemAt numbered i)) (
            builtins.genList (i: i) (builtins.length numbered)
          )
        );
      tokenPath = worked.plan."issuer:vars/session".files.token.path;
    in
    {
      expr = {
        # One machine of the delivery set states a recipient and the other does
        # not, so the whole difference is inside one rendered script.
        sealed = sealLines script;
        plaintext = deliverLines script;
        # Sealed copy first: a run interrupted between the two must never leave
        # a sealed copy older than the plaintext beside it.
        theSealedCopyIsSentFirst =
          at "seal_copy 'issuer:session'" < at "deliver 'issuer:session' 'token' 'root@one";
        # The sealed path is the library's derivation of the value's own path,
        # not a root this reading restates.
        theSealedPathIsTheLibrarysOwn = hasInfix (planner.util.sealedPathOf tokenPath) script;
        # A value's bytes are in the plan, which is what makes their absence
        # from the script an observation rather than a vacuum.
        thePlanCarriesTheBytes = hasInfix caBytes (builtins.toJSON sealing);
        theScriptCarriesThem = hasInfix caBytes script;
      };
      expected = {
        sealed = [
          "    seal_copy 'issuer:host:one' 'key' 'root@one.example:22' '/var/lib/planner/sealed/issuer/host' '/var/lib/planner/sealed/issuer/host/key.age' '${recipient}'"
          "    seal_copy 'issuer:session' 'token' 'root@one.example:22' '/var/lib/planner/sealed/issuer/session' '/var/lib/planner/sealed/issuer/session/token.age' '${recipient}'"
        ];
        plaintext = [
          "    deliver 'issuer:host:one' 'key' 'root@one.example:22' '/run/vars/issuer/host' '/run/vars/issuer/host/key' '0400' 'root:root'"
          "    deliver 'issuer:host:two' 'key' 'root@two.example:22' '/run/vars/issuer/host' '/run/vars/issuer/host/key' '0400' 'root:root'"
          "    deliver 'issuer:session' 'token' 'root@one.example:22' '/run/vars/issuer/session' '/run/vars/issuer/session/token' '0400' 'root:root'"
          "    deliver 'issuer:session' 'token' 'root@two.example:22' '/run/vars/issuer/session' '/run/vars/issuer/session/token' '0400' 'root:root'"
        ];
        theSealedCopyIsSentFirst = true;
        theSealedPathIsTheLibrarysOwn = true;
        thePlanCarriesTheBytes = true;
        theScriptCarriesThem = false;
      };
    };

  testTheRenderedStepForAMachineWithoutARecipientIsUnchanged =
    let
      script = renderOf unsealed;
    in
    {
      expr = {
        sealed = sealLines script;
        plaintext = deliverLines script;
        # Not one path under the sealed root anywhere in the script: a fleet
        # stating no recipient pays nothing for this change.
        itNamesNoSealedPath = hasInfix planner.util.sealedRoot script;
        # And a machine of the set that states none is delivered to exactly as
        # it is beside a machine that seals: one record's recipient moves no
        # other machine's line.
        besideAMachineThatSeals = deliverLines (renderOf sealing) == deliverLines script;
        theScriptCarriesTheBytes = hasInfix caBytes script;
      };
      expected = {
        sealed = [ ];
        plaintext = [
          "    deliver 'issuer:host:one' 'key' 'root@one.example:22' '/run/vars/issuer/host' '/run/vars/issuer/host/key' '0400' 'root:root'"
          "    deliver 'issuer:host:two' 'key' 'root@two.example:22' '/run/vars/issuer/host' '/run/vars/issuer/host/key' '0400' 'root:root'"
          "    deliver 'issuer:session' 'token' 'root@one.example:22' '/run/vars/issuer/session' '/run/vars/issuer/session/token' '0400' 'root:root'"
          "    deliver 'issuer:session' 'token' 'root@two.example:22' '/run/vars/issuer/session' '/run/vars/issuer/session/token' '0400' 'root:root'"
        ];
        itNamesNoSealedPath = false;
        besideAMachineThatSeals = true;
        theScriptCarriesTheBytes = false;
      };
    };

  # A pure evaluation cannot run a shell, so this is a reading of the rendered
  # text. What the step does when it runs is asserted in tests/e2e/generated-secret.
  testTheRenderedStepRemovesThePlaintextItFetched =
    let
      script = renderOf bothSealing;
      numbered = lines script;
      indexed = builtins.genList (i: {
        inherit i;
        line = builtins.elemAt numbered i;
      }) (builtins.length numbered);
      firstAt =
        needle:
        let
          hits = filter (entry: hasInfix needle entry.line) indexed;
        in
        if hits == [ ] then null else (head hits).i;
      countOf = needle: builtins.length (filter (line: hasInfix needle line) numbered);
    in
    {
      expr = {
        trap = filter (line: hasInfix "trap " line) numbered;
        temporaries = countOf "mktemp";
        # The fetch writes plaintext, so a trap installed after it covers a file
        # that already exists.
        theTrapIsBeforeTheFirstFetch = firstAt "trap " < firstAt "\"$get\"";
        eachFetchTruncatesTheOneTemporary = countOf ": > \"$tmp\"" == 1;
        # The ciphertext is plaintext one key away, so the temporary it is
        # written into is removed by the same trap and truncated by the
        # redirection that writes it.
        theCiphertextIsTruncatedByItsOwnRedirection = countOf "> \"$sealed\"" == 1;
      };
      expected = {
        trap = [ "trap 'rm -f \"$tmp\" \"$sealed\"' EXIT INT TERM HUP" ];
        temporaries = 2;
        theTrapIsBeforeTheFirstFetch = true;
        eachFetchTruncatesTheOneTemporary = true;
        theCiphertextIsTruncatedByItsOwnRedirection = true;
      };
    };

  testADeliveryTargetWithNoAddressIsRefused =
    let
      addressless = worked.plan // {
        "machine:two" = removeAttrs worked.plan."machine:two" [ "address" ];
      };
      absent = removeAttrs worked.plan [ "machine:two" ];
    in
    {
      expr = {
        refused = raises (renderOf addressless);
        beforeAnyScriptExists = raises (reader.deliveriesOf addressless);
        noEntryAtAll = raises (renderOf absent);
        theAddressIsWhatIsMissing = removeAttrs (oneRow "secrets-delivery-machine-no-address" addressless) [
          "evidence"
          "severity"
        ];
        andWithNoEntryTheMachineIsUnknown = (oneRow "secrets-delivery-machine-unknown" absent).message;
        # The machine is what is missing, not the value: the same plan with the
        # address renders.
        withTheAddress = deliverLines (renderOf worked.plan) != [ ];
        andRowsNothing = idsOf worked.plan;
      };
      expected = {
        refused = true;
        beforeAnyScriptExists = true;
        noEntryAtAll = true;
        theAddressIsWhatIsMissing = {
          id = "secrets-delivery-machine-no-address";
          subject = "issuer:vars/host@two";
          message = "value `issuer:vars/host@two` is delivered to machine `two`, and that machine's entry records no address";
          resolution = "declare an `address` for `two` in the deployment's machine registry";
        };
        andWithNoEntryTheMachineIsUnknown = "value `issuer:vars/host@two` is delivered to machine `two`, and the plan carries no `machine:two` entry to read an address out of";
        withTheAddress = true;
        andRowsNothing = [ ];
      };
    };

  testAPlanTheReadingRefusesStillAnswersWithATable =
    let
      programless = deployment { program = false; };
      table = rowsOf programless.plan;
      first = head table;
    in
    {
      expr = {
        itAnswered = !(raises table);
        subjects = map (row: row.subject) table;
        itNamesTheEntry = hasInfix first.subject first.message;
        itSaysWhatHasToChange = first.resolution;
        # The same plan read for a configuration is still refused, which is what
        # makes the table an answer rather than a softening.
        theConfigurationIsStillRefused = raises (configurationOf programless.plan);
      };
      expected = {
        itAnswered = true;
        subjects = [
          "issuer:vars/ca"
          "issuer:vars/host@one"
          "issuer:vars/host@two"
          "issuer:vars/session"
        ];
        itNamesTheEntry = true;
        itSaysWhatHasToChange = "declare `program` on the generator, or read this plan with something that needs none";
        theConfigurationIsStillRefused = true;
      };
    };

  testEveryConditionOfOnePlanIsReportedNotTheFirst =
    let
      # One plan, two conditions: a file name the contract does not admit, and a
      # value recording no program.
      pair =
        named: programless:
        let
          plan = synthetic {
            ${named}.files."key@id" = handFile { path = "/run/vars/a/key"; };
            ${programless} = { };
          };
        in
        plan // { ${programless} = removeAttrs plan.${programless} [ "program" ]; };
    in
    {
      expr = {
        firstThenSecond = idsOf (pair "a:vars/one" "a:vars/two");
        # The same two conditions, swapped between the keys the walk sorts on.
        secondThenFirst = idsOf (pair "a:vars/two" "a:vars/one");
      };
      expected = {
        firstThenSecond = [
          "secrets-file-name-outside-grammar"
          "secrets-value-no-program"
        ];
        secondThenFirst = [
          "secrets-value-no-program"
          "secrets-file-name-outside-grammar"
        ];
      };
    };

  testAValueWithNoProgramIsARow =
    let
      programless = deployment { program = false; };
    in
    {
      expr = {
        row = removeAttrs (oneRow "secrets-value-no-program" programless.plan) [ "evidence" ];
      };
      expected = {
        row = {
          id = "secrets-value-no-program";
          subject = "issuer:vars/ca";
          severity = "error";
          message = "entry `issuer:vars/ca` records no `program`, and the external generator runs one program per stored value";
          resolution = "declare `program` on the generator, or read this plan with something that needs none";
        };
      };
    };

  testAFileNameOutsideTheContractsGrammarIsARow =
    let
      named = synthetic {
        "a:vars/b" = {
          files."key@id" = handFile { path = "/run/vars/a/b/key"; };
        };
      };
    in
    {
      expr = {
        row = removeAttrs (oneRow "secrets-file-name-outside-grammar" named) [ "evidence" ];
      };
      expected = {
        row = {
          id = "secrets-file-name-outside-grammar";
          subject = "a:vars/b";
          severity = "error";
          message = "generated file `key@id` of `a:vars/b` is not a name the external generator admits, which carries ASCII letters, digits, :, `_`, `.`, `-` and nothing else";
          resolution = "rename the file";
        };
      };
    };

  testTheContractsReservedProvenanceNameIsARow =
    let
      reserved = synthetic {
        "a:vars/b" = {
          files.".nixos-secrets-metadata" = handFile { path = "/run/vars/a/b/meta"; };
        };
      };
    in
    {
      expr = {
        row = removeAttrs (oneRow "secrets-file-name-reserved" reserved) [ "evidence" ];
      };
      expected = {
        row = {
          id = "secrets-file-name-reserved";
          subject = "a:vars/b";
          severity = "error";
          message = "generated file `.nixos-secrets-metadata` of `a:vars/b` carries the name the external generator keeps for its own provenance record";
          resolution = "rename the file";
        };
      };
    };

  testARecipientMachineWithNoAddressIsAnErrorRow =
    let
      addressless = worked.plan // {
        "machine:two" = removeAttrs worked.plan."machine:two" [ "address" ];
      };
      deploymentBuild = operatorReader.read { plan = addressless; };
    in
    {
      expr = {
        severity = (oneRow "secrets-delivery-machine-no-address" addressless).severity;
        subjects = map (row: row.subject) (rowsById "secrets-delivery-machine-no-address" addressless);
        # The same absence, read as a deployment: no row at all, and every entry
        # is still realised, because no build step dials a machine.
        deploymentSeverities = map (row: row.severity) deploymentBuild.rows;
        deploymentRows = map (row: row.id) deploymentBuild.rows;
        deploymentRefused = deploymentBuild.refused;
        everyEntryIsRealised = builtins.attrValues (
          builtins.mapAttrs (_: entry: entry.realised) deploymentBuild.entries
        );
      };
      expected = {
        severity = "error";
        subjects = [
          "issuer:vars/host@two"
          "issuer:vars/session"
        ];
        deploymentSeverities = [ ];
        deploymentRows = [ ];
        deploymentRefused = false;
        everyEntryIsRealised = [
          true
          true
        ];
      };
    };

  testAnAddressTheRenderedStepCannotCarryIsARow =
    let
      spaced = worked.plan // {
        "machine:two" = worked.plan."machine:two" // {
          address = "10.0.0.11 ";
        };
      };
    in
    {
      expr = {
        row = removeAttrs (oneRow "secrets-rendered-word-refused" spaced) [ "evidence" ];
        theStepIsNotRendered = raises (renderOf spaced);
      };
      expected = {
        row = {
          id = "secrets-rendered-word-refused";
          subject = "issuer:vars/host@two";
          severity = "error";
          message = "the address of `two` is `root@10.0.0.11 `, which is not something this reading will render into a shell script";
          resolution = "write `two` as one shell word of ASCII letters, digits, `_`, `.`, `/`, `:`, `@`, `%`, `+`, `=`, `,`, `~`, `-` and nothing else";
        };
        theStepIsNotRendered = true;
      };
    };

  # The rule above refuses a quote, so this reads the escape with the rule
  # switched off: what is asserted is that the value the grammar never reached
  # still renders as one inert word.
  testAWordCarryingAQuoteIsEscapedRatherThanQuotedByHand =
    let
      hostile = worked.plan // {
        "machine:two" = worked.plan."machine:two" // {
          address = "10.0.0.11' ; id ; '";
        };
      };
      script = unruled.render {
        plan = hostile;
        get = getProgram;
        seal = sealProgram;
      };
    in
    {
      expr = {
        theGrammarRefusesItToday = reader.unrenderable "root@10.0.0.11' ; id ; '";
        theWordsAreStillOne = filter (hasInfix "10.0.0.11") (deliverLines script);
      };
      expected = {
        theGrammarRefusesItToday = true;
        theWordsAreStillOne = [
          "    deliver 'issuer:host:two' 'key' 'root@10.0.0.11'\\'' ; id ; '\\''' '/run/vars/issuer/host' '/run/vars/issuer/host/key' '0400' 'root:root'"
          "    deliver 'issuer:session' 'token' 'root@10.0.0.11'\\'' ; id ; '\\''' '/run/vars/issuer/session' '/run/vars/issuer/session/token' '0400' 'root:root'"
        ];
      };
    };

  testARefusedGenerationNamesEveryReasonInOneTable =
    let
      # One plan carrying a row of the planner's and rows of the reading's.
      broken = deployment {
        program = false;
        reads = [ "host" ];
      };
      generation = reader.generation { inherit (broken) plan diagnostics; };
      marks = filter (line: hasInfix "  ! " line) (lines generation.refusal);
    in
    {
      expr = {
        refused = generation.refused;
        ids = map (row: row.id) generation.diagnostics;
        thePlansOwnRowIsRenderedToo =
          hasInfix (head (filter (row: row.id == "vars-reads-cycle") generation.diagnostics)).message
            generation.refusal;
        itIsTheRenderedTable =
          generation.refusal == "planner secrets: this plan cannot be read as a generator configuration.\n\n"
          + planner.render generation.diagnostics;
        # Not a message naming one condition: every reason has its own mark.
        reasons = builtins.length marks;
      };
      expected = {
        refused = true;
        ids = [
          "secrets-value-no-program"
          "secrets-value-no-program"
          "secrets-value-no-program"
          "secrets-value-no-program"
          "vars-reads-cycle"
        ];
        thePlansOwnRowIsRenderedToo = true;
        itIsTheRenderedTable = true;
        reasons = 5;
      };
    };

  testAWarningDoesNotRefuseAGeneration =
    let
      warned = planner.warning {
        id = "set-read-in-key";
        subject = "issuer:only@one";
        message = "a warning of the plan this generation is read from";
        evidence = "a warning that stopped a build would be an error";
        resolution = "read the table";
      };
      generation = reader.generation {
        inherit (worked) plan;
        diagnostics = [ warned ];
      };
    in
    {
      expr = {
        refused = generation.refused;
        refusal = generation.refusal;
        severities = map (row: row.severity) generation.diagnostics;
        # The three things the generation writes beside its table are produced.
        theConfigurationIsBuilt = attrNames (configurationOf worked.plan).store;
        theNamesAreBuilt = map (value: value.name) (reader.valuesOf worked.plan);
        theStepIsRendered = deliverLines (renderOf worked.plan) != [ ];
      };
      expected = {
        refused = false;
        refusal = null;
        severities = [ "warning" ];
        theConfigurationIsBuilt = [
          "issuer:ca"
          "issuer:host:one"
          "issuer:host:two"
          "issuer:session"
        ];
        theNamesAreBuilt = [
          "issuer:ca"
          "issuer:host:one"
          "issuer:host:two"
          "issuer:session"
        ];
        theStepIsRendered = true;
      };
    };

  testEveryValueTheRenderedStepEscapesIsCrossedAgainstTheReading =
    let
      # The step and the reading are crossed through the words the reading
      # publishes: the call of each rendered step carries one word per entry of
      # that set whose `steps` name it, and that step's own shell function reads
      # exactly those positions, so a set the two halves do not share is a call
      # the function cannot take apart.
      index =
        list: needle:
        head (
          filter (i: builtins.elemAt list i == needle) (builtins.genList (i: i) (builtins.length list))
        );

      crossing =
        words:
        let
          script =
            (import (secretsSource + "/backend.nix") {
              inherit planner;
              reader = reader // {
                renderedWords = words;
              };
            }).render
              {
                plan = bothSealing;
                get = getProgram;
                seal = sealProgram;
              };
          numbered = lines script;
          wordsOf = step: filter (word: builtins.elem step word.steps) words;
          # The function a step's calls land in, from its own opening line to the
          # brace that closes it: the positions a script reads somewhere are the
          # union of both functions', which is one question too coarse.
          bodyOf =
            step:
            let
              opened = index numbered "${step}() {";
              after = builtins.genList (i: builtins.elemAt numbered (opened + 1 + i)) (
                builtins.length numbered - opened - 1
              );
            in
            builtins.concatStringsSep "\n" (builtins.genList (builtins.elemAt after) (index after "}"));
          carriedBy =
            step:
            builtins.length (
              filter (word: builtins.isString word && word != "") (
                builtins.split " +" (head (callLines step script))
              )
            )
            - 1;
          readBy =
            step: filter (n: hasInfix ("$" + toString n) (bodyOf step)) (builtins.genList (i: i + 1) 9);
        in
        {
          fields = map (word: word.field) words;
          theStepCarriesOneWordPerField = map (
            step: carriedBy step == 2 + builtins.length (wordsOf step)
          ) reader.renderedSteps;
          theStepReadsThemAll = map (
            step: readBy step == builtins.genList (i: i + 1) (2 + builtins.length (wordsOf step))
          ) reader.renderedSteps;
        };

      # One plan per word a record states on its own, each moving that word alone
      # out of what a rendered word admits. The two sealed words are not among
      # them and cannot be: each is the file's own path put through
      # `sealedPathOf`, so a sealed word this reading refuses is a path it
      # refuses, which is the one row `aRefusedPathIsOneRow` reads.
      hostile = {
        address = worked.plan // {
          "machine:one" = worked.plan."machine:one" // {
            address = "10.0.0.10 ";
          };
        };
        parent = sessionFileWith { path = "/token"; };
        path = sessionFileWith { path = "/run/vars/issuer/ses sion/token"; };
        mode = sessionFileWith { mode = "0 400"; };
        ownership = sessionFileWith { owner = "svc$"; };
        recipient = withRecipients {
          "machine:one" = "age1 nope";
          "machine:two" = null;
        };
      };

      stated = filter (word: hostile ? ${word.field}) reader.renderedWords;

      checks = filter (
        word:
        builtins.any (row: hasInfix "${word.what} of " row.message) (
          rowsById "secrets-rendered-word-refused" hostile.${word.field}
        )
      ) stated;

      held = crossing reader.renderedWords;
      andOneWordMore = crossing (reader.renderedWords ++ [ (head reader.renderedWords) ]);
      andOneWordFewer = crossing (builtins.tail reader.renderedWords);
    in
    {
      expr = {
        inherit held;
        checkedByTheReading = map (word: word.field) checks;
        # The words no record states, which are the two a path is put through a
        # derivation for.
        derivedFromAnotherWord = map (word: word.field) (
          filter (word: !(hostile ? ${word.field})) reader.renderedWords
        );
        # The row of a word the reading never checked before: it names the
        # field, the value entry and the text the step cannot carry.
        theOwnershipRow = removeAttrs (oneRow "secrets-rendered-word-refused" hostile.ownership) [
          "evidence"
        ];
        # The recipient is a word of the machine's own record, so its row names
        # the machine the way the address's does and its subject stays the value.
        theRecipientRow = removeAttrs (oneRow "secrets-rendered-word-refused" hostile.recipient) [
          "evidence"
        ];
        # A path whose own word is refused is one mistake, so the words derived
        # from it are not three rows.
        aRefusedPathIsOneRow = map (row: row.message) (
          rowsById "secrets-rendered-word-refused" hostile.path
        );
        # And the refusal is the second time each fact is stated: the reading
        # rowed it, the step will not render it.
        theStepRefusesEachOfThem = map (word: raises (renderOf hostile.${word.field})) stated;
        # A word only the rendering half carries: the call grows and the
        # function reads no more than it did.
        aWordOnlyTheStepCarries = andOneWordMore.theStepReadsThemAll;
        # And the other way: a word the reading checks that the call does not
        # carry leaves the function reading a position nothing supplies.
        aWordTheStepDoesNotCarry = andOneWordFewer.theStepReadsThemAll;
      };
      expected = {
        held = {
          fields = [
            "address"
            "parent"
            "path"
            "mode"
            "ownership"
            "sealedParent"
            "sealed"
            "recipient"
          ];
          theStepCarriesOneWordPerField = [
            true
            true
          ];
          theStepReadsThemAll = [
            true
            true
          ];
        };
        checkedByTheReading = [
          "address"
          "parent"
          "path"
          "mode"
          "ownership"
          "recipient"
        ];
        derivedFromAnotherWord = [
          "sealedParent"
          "sealed"
        ];
        theOwnershipRow = {
          id = "secrets-rendered-word-refused";
          subject = "issuer:vars/session";
          severity = "error";
          message = "the ownership of `issuer:vars/session` is `svc$:root`, which is not something this reading will render into a shell script";
          resolution = "write `issuer:vars/session` as one shell word of ASCII letters, digits, `_`, `.`, `/`, `:`, `@`, `%`, `+`, `=`, `,`, `~`, `-` and nothing else";
        };
        theRecipientRow = {
          id = "secrets-rendered-word-refused";
          subject = "issuer:vars/host@one";
          severity = "error";
          message = "the seal recipient of `one` is `age1 nope`, which is not something this reading will render into a shell script";
          resolution = "write `one` as one shell word of ASCII letters, digits, `_`, `.`, `/`, `:`, `@`, `%`, `+`, `=`, `,`, `~`, `-` and nothing else";
        };
        aRefusedPathIsOneRow = [
          "the path of `issuer:vars/session` is `/run/vars/issuer/ses sion/token`, which is not something this reading will render into a shell script"
        ];
        theStepRefusesEachOfThem = [
          true
          true
          true
          true
          true
          true
        ];
        aWordOnlyTheStepCarries = [
          false
          false
        ];
        aWordTheStepDoesNotCarry = [
          false
          false
        ];
      };
    };

  testAnOwnershipTheReadingAdmitsRenders =
    let
      owned = sessionFileWith {
        owner = "svc";
        group = "readers";
      };
      script = renderOf owned;
    in
    {
      expr = {
        rows = idsOf owned;
        theStepCarriesBoth = filter (hasInfix "issuer:session") (deliverLines script);
        theStepSetsThem = filter (hasInfix "chown '$7'") (lines script) != [ ];
      };
      expected = {
        rows = [ ];
        theStepCarriesBoth = [
          "    deliver 'issuer:session' 'token' 'root@one.example:22' '/run/vars/issuer/session' '/run/vars/issuer/session/token' '0400' 'svc:readers'"
          "    deliver 'issuer:session' 'token' 'root@two.example:22' '/run/vars/issuer/session' '/run/vars/issuer/session/token' '0400' 'svc:readers'"
        ];
        theStepSetsThem = true;
      };
    };

  testAValueEntryIsRecognisedByTheDeliveryItRecords =
    let
      # An instance called `machine`, beside a machine of that name: the value's
      # key text is a machine record's and its record is a value's.
      named = synthetic { "machine:vars/token" = { }; } // {
        "machine:machine" = {
          key = "sha256-0000000000000000";
          address = "m.example";
          tags = [ ];
        };
      };
      unreadable = synthetic { "vars/token" = { }; };
    in
    {
      expr = {
        names = attrNames (storeOf named);
        itRowsNothing = idsOf named;
        theMachineRecordIsNoValue =
          reader.valuesOf named == reader.valuesOf (removeAttrs named [ "machine:machine" ]);
        # A record the reading recognises and whose key names no components: one
        # row against the key the plan carries, and no store entry.
        unreadableRow = removeAttrs (oneRow "secrets-key-not-a-value" unreadable) [ "evidence" ];
        refused = raises (storeOf unreadable);
        andNothingIsDelivered = raises (reader.deliveriesOf unreadable);
      };
      expected = {
        names = [ "machine:token" ];
        itRowsNothing = [ ];
        theMachineRecordIsNoValue = true;
        unreadableRow = {
          id = "secrets-key-not-a-value";
          subject = "vars/token";
          severity = "error";
          message = "`vars/token` is not a generated value's key of the form `<instance>:vars/<generator>` or `<instance>:vars/<generator>@<machine>`";
          resolution = "plan this deployment again, so that every generated value sits at the key the planner writes and every read names one of them";
        };
        refused = true;
        andNothingIsDelivered = true;
      };
    };

  testAServiceEntryWhoseKeyNamesAGeneratorContributesNoStoreEntry =
    let
      # One placed service entry of the worked plan, moved to the key a
      # generated value of the same instance would sit at.
      impostor = worked.plan // {
        "issuer:vars/only@one" = worked.plan."issuer:only@one";
      };
    in
    {
      expr = {
        itIsAPlacedEntry = impostor."issuer:vars/only@one" ? placement;
        names = attrNames (storeOf impostor);
        rows = idsOf impostor;
        theStepNamesIt = hasInfix "issuer:only" (renderOf impostor);
      };
      expected = {
        itIsAPlacedEntry = true;
        names = [
          "issuer:ca"
          "issuer:host:one"
          "issuer:host:two"
          "issuer:session"
        ];
        rows = [ ];
        theStepNamesIt = false;
      };
    };
}
