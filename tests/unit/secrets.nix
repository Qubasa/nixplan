{
  planner,
  support,
  secretsSource,
}:
let
  inherit (builtins)
    attrNames
    filter
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
        refused = raises (storeOf programless.plan);
        theWholeConfigurationIsRefused = raises (configurationOf programless.plan);
        # Not the reading's business: a program is a fact about the value, so a
        # plan that carries none is still a plan.
        theEntryIsThere = programless.plan."issuer:vars/session" ? files;
        theEntryCarriesNoProgram = programless.plan."issuer:vars/session" ? program;
      };
      expected = {
        theRestOfThePlanIsFine = [ ];
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
        # The rule and nothing wider: the same plan without the colon is read.
        withoutIt = attrNames (storeOf clean);
      };
      expected = {
        generator = true;
        machine = true;
        withoutIt = [ "a:b" ];
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
      };
      expected = {
        space = true;
        slash = true;
        theToolsOwnFileName = true;
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
        # The machine is what is missing, not the value: the same plan with the
        # address renders.
        withTheAddress = deliverLines (renderOf worked.plan) != [ ];
      };
      expected = {
        refused = true;
        beforeAnyScriptExists = true;
        noEntryAtAll = true;
        withTheAddress = true;
      };
    };
}
