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
    tryEval
    ;

  inherit (support)
    hasInfix
    planOf
    rowIds
    soleRoot
    ;

  reader = import (secretsSource + "/read.nix") { inherit planner; };
  deployStep = import (secretsSource + "/backend.nix") { inherit planner reader; };

  imageReader = import (imageSource + "/read.nix") { inherit planner; };
  flakeletReader = import (flakeletSource + "/read.nix") {
    inherit planner;
    reader = imageReader;
  };
  operatorReader = import (operatorSource + "/read.nix") {
    inherit planner;
    inherit imageReader flakeletReader;
  };

  rowsOf = plan: reader.rows { inherit plan; };
  idsOf = plan: map (row: row.id) (rowsOf plan);
  rowsById = id: plan: filter (row: row.id == id) (rowsOf plan);
  oneRow = id: plan: head (rowsById id plan);

  # deepSeq, because a refusal guards fields a lazy read would never force.
  raises = value: !(tryEval (builtins.deepSeq value value)).success;

  programOf = gen: "/nix/store/9dm4x2vqk7z1n5bpr3jlfg8ys6cwh0az-generate-${gen}.drv";
  getProgram = "/nix/store/3q8xk1p7v2mz9jd4rlnb6ycsfwg0h5aq-age-backend/bin/secrets-age-backend";

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
    };

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
        files.token = {
          path = "/run/vars/hand/token";
          secrecy = "secret";
          inPlan = "reference";
        };
      }
      // entry
    ) entries;

  lines = text: filter builtins.isString (builtins.split "\n" text);
  deliverLines = text: filter (line: builtins.match " *deliver .*" line != null) (lines text);
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
          files.".nixos-secrets-metadata".path = "/run/vars/a/b/meta";
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
          "    deliver 'issuer:host:one' 'key' 'root@one.example:22' '/run/vars/issuer/host' '/run/vars/issuer/host/key'"
          "    deliver 'issuer:host:two' 'key' 'root@two.example:22' '/run/vars/issuer/host' '/run/vars/issuer/host/key'"
          "    deliver 'issuer:session' 'token' 'root@one.example:22' '/run/vars/issuer/session' '/run/vars/issuer/session/token'"
          "    deliver 'issuer:session' 'token' 'root@two.example:22' '/run/vars/issuer/session' '/run/vars/issuer/session/token'"
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
            ${named}.files."key@id".path = "/run/vars/a/key";
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
          files."key@id".path = "/run/vars/a/b/key";
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
          files.".nixos-secrets-metadata".path = "/run/vars/a/b/meta";
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
        # The same absence, read as a deployment: a warning, and every entry is
        # still realised, because no build step dials a machine.
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
        deploymentSeverities = [ "warning" ];
        deploymentRows = [ "operator-entry-machine-no-address" ];
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
}
