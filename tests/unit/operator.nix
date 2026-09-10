{
  planner,
  support,
  operatorSource,
  imageSource,
}:
let
  inherit (builtins)
    attrNames
    filter
    length
    toJSON
    ;

  inherit (support)
    hasInfix
    planOf
    root
    soleRoot
    ;

  inherit (support.worked) borgbackup openssh;

  # The image reader arrives as an argument for the reason flakelet's does: this
  # suite holds each directory as its own store path, so a relative import out of
  # one would resolve outside the store.
  reader = import (operatorSource + "/read.nix") {
    inherit planner;
    imageReader = import (imageSource + "/read.nix") { inherit planner; };
  };

  sorted = builtins.sort (a: b: a < b);

  pub = planner.interface {
    name = "pub";
    exports.publicKey = support.publicString;
  };

  simple = _: {
    closure = [ borgbackup ];
    units.only.command = "${borgbackup}/bin/borg serve";
  };

  scheduled = _: {
    closure = [ borgbackup ];
    units.only = {
      command = "${borgbackup}/bin/borg prune";
      schedule = "daily";
    };
  };

  # A closure root nothing mentions is the cheapest warning the planner has, so
  # this deployment's table carries a row and no error.
  unmentioned = _: {
    closure = [
      borgbackup
      openssh
    ];
    units.only.command = "${borgbackup}/bin/borg serve";
  };

  deployment =
    implementation:
    planOf {
      instances.svc = {
        module = soleRoot { module = _: { impl = implementation; }; };
        placement.every.only.machines = [ "one" ];
      };
    };

  one = deployment simple;
  oneKey = "svc:only@one";

  readOf =
    realise: result:
    reader.read {
      inherit (result) plan;
      inherit realise;
    };

  worked = support.workedResult;
  workedRead = reader.read { inherit (worked) plan; };

  placedOf =
    plan:
    sorted (
      filter (
        key:
        builtins.match "machine:.*" key == null
        && builtins.match ".*:vars/.*" key == null
        && reader.parseKey key != null
      ) (attrNames plan)
    );

  # Two instances, one machine, and two keys that project onto one artifact name:
  # `a-b:c@one` and `a:b-c@one` both flatten to `a-b-c-one`.
  colliding = planOf {
    instances = {
      "a-b" = {
        module = root { members.c.module = _: { impl = simple; }; };
        placement.every.c.machines = [ "one" ];
      };
      a = {
        module = root { members."b-c".module = _: { impl = simple; }; };
        placement.every."b-c".machines = [ "one" ];
      };
    };
  };

  # A registry that declares no address, written as a plan rather than reached
  # through one: the reading is a function of the plan, and this is the plan that
  # carries the condition.
  addressless = {
    "machine:bare" = {
      tags = [ ];
      system = "x86_64-linux";
      serviceManager = "systemd";
    };
    "svc:only@bare" = {
      key = "sha256-0000000000000000";
      placement.reason = "every";
      units.only.command = "/bin/true";
    };
  };

  unreceived = {
    "machine:bare" = {
      address = "bare.example";
      tags = [ ];
    };
    "holder:vars/app" = {
      delivery = [ ];
      deliveryDerivedFrom = [ ];
      files."ca.pub" = {
        path = "/run/vars/holder/app/ca.pub";
        secrecy = "public";
      };
    };
  };

  rowsById = id: reading: filter (r: r.id == id) reading.rows;
  idsOf = reading: sorted (map (r: r.id) reading.rows);
in
{
  testTwoDeploymentsAreBuiltByOneFunction =
    let
      first = readOf { } one;
      second = workedRead;
    in
    {
      expr = {
        entries = {
          first = attrNames first.entries;
          second = attrNames second.entries;
        };
        placed = {
          first = placedOf one.plan;
          second = placedOf worked.plan;
        };
        artifacts = {
          first = map (key: first.entries.${key}.artifact) (attrNames first.entries);
          second = length (attrNames second.manifest.entries);
        };
        rows = first.rows ++ second.rows;
      };
      expected = {
        entries = {
          first = [ oneKey ];
          second = [
            "nightly:client@alpha"
            "nightly:client@beta"
            "nightly:client@gamma"
            "vault-repo:server@vault"
          ];
        };
        placed = {
          first = [ oneKey ];
          second = [
            "nightly:client@alpha"
            "nightly:client@beta"
            "nightly:client@gamma"
            "vault-repo:server@vault"
          ];
        };
        artifacts = {
          first = [ "entries/svc-only-one" ];
          second = 4;
        };
        rows = [ ];
      };
    };

  testAnArtifactIsAddressedByItsPlanKey =
    let
      reading = workedRead;
      paths = map (key: reading.manifest.entries.${key}.path) (attrNames reading.manifest.entries);
    in
    {
      expr = {
        named = reading.manifest.entries."vault-repo:server@vault".path;
        alpha = reading.manifest.entries."nightly:client@alpha".path;
        distinct = length (planner.util.uniqueStrings paths) == length paths;
        everyKeyNamed = filter (key: !(reading.manifest.entries ? ${key})) (placedOf worked.plan);
      };
      expected = {
        named = "entries/vault-repo-server-vault";
        alpha = "entries/nightly-client-alpha";
        distinct = true;
        everyKeyNamed = [ ];
      };
    };

  testTwoEntriesProjectOntoOneArtifactName =
    let
      reading = readOf { } colliding;
      row = builtins.head (rowsById "operator-entry-name-collision" reading);
    in
    {
      expr = {
        ids = idsOf reading;
        count = length (rowsById "operator-entry-name-collision" reading);
        subject = row.subject;
        namesBoth = hasInfix "`a-b:c@one`, `a:b-c@one`" row.message;
        namesTheName = hasInfix "`a-b-c-one`" row.message;
        refused = reading.refused;
      };
      expected = {
        ids = [ "operator-entry-name-collision" ];
        count = 1;
        subject = "a-b:c@one";
        namesBoth = true;
        namesTheName = true;
        refused = true;
      };
    };

  testAnEntryStatesNoRealiser =
    let
      unstated = readOf { } one;
      defaulted = readOf { default.realiser = "flakelet"; } one;
      elsewhere = readOf {
        "other:thing" = {
          realiser = "image";
          profile = "strict";
        };
      } one;
    in
    {
      expr = {
        unstated = unstated.manifest.entries.${oneKey}.realiser;
        defaulted = defaulted.manifest.entries.${oneKey}.realiser;
        elsewhere = elsewhere.manifest.entries.${oneKey}.realiser;
        profile = unstated.manifest.entries.${oneKey}.profile;
        rows = unstated.rows ++ defaulted.rows ++ elsewhere.rows;
      };
      expected = {
        unstated = "flakelet";
        defaulted = "flakelet";
        elsewhere = "flakelet";
        profile = null;
        rows = [ ];
      };
    };

  testAnImageEntryStatesItsConfinementProfile =
    let
      stated = readOf {
        "svc:only" = {
          realiser = "image";
          profile = "strict";
        };
      } one;
      byKey = readOf {
        ${oneKey} = {
          realiser = "image";
          profile = "default";
        };
      } one;
      silent = readOf { "svc:only".realiser = "image"; } one;
      row = builtins.head (rowsById "operator-image-profile-missing" silent);
    in
    {
      expr = {
        stated = {
          realiser = stated.manifest.entries.${oneKey}.realiser;
          profile = stated.manifest.entries.${oneKey}.profile;
          rows = stated.rows;
        };
        byKey = byKey.manifest.entries.${oneKey}.profile;
        silent = {
          ids = idsOf silent;
          count = length (rowsById "operator-image-profile-missing" silent);
          subject = row.subject;
          namesTheField = hasInfix "`profile`" row.message;
          namesTheProfiles = hasInfix "`strict`" row.resolution;
          refused = silent.refused;
        };
      };
      expected = {
        stated = {
          realiser = "image";
          profile = "strict";
          rows = [ ];
        };
        byKey = "default";
        silent = {
          ids = [ "operator-image-profile-missing" ];
          count = 1;
          subject = oneKey;
          namesTheField = true;
          namesTheProfiles = true;
          refused = true;
        };
      };
    };

  testARealiserNameNothingImplements =
    let
      reading = readOf { "svc:only".realiser = "podman"; } one;
      row = builtins.head (rowsById "operator-realiser-unknown" reading);
    in
    {
      expr = {
        ids = idsOf reading;
        count = length (rowsById "operator-realiser-unknown" reading);
        subject = row.subject;
        namesTheName = hasInfix "`podman`" row.message;
        namesWhatExists = hasInfix "`flakelet`, `image`" row.message;
        refused = reading.refused;
        realisers = reader.realisers;
      };
      expected = {
        ids = [ "operator-realiser-unknown" ];
        count = 1;
        subject = oneKey;
        namesTheName = true;
        namesWhatExists = true;
        refused = true;
        realisers = [
          "flakelet"
          "image"
        ];
      };
    };

  testADeploymentWhoseDiagnosticsCarryAnError =
    let
      reading = reader.read { inherit (worked) plan diagnostics; };
    in
    {
      expr = {
        applicable = worked.applicable;
        refused = reading.refused;
        ownRows = reading.rows;
        carriesTheTable = hasInfix "clients names three entries" reading.refusal;
        carriesTheReason = hasInfix "not applicable" reading.refusal;
        tableIsTheTable = reading.diagnostics == worked.diagnostics;
      };
      expected = {
        applicable = false;
        refused = true;
        ownRows = [ ];
        carriesTheTable = true;
        carriesTheReason = true;
        tableIsTheTable = true;
      };
    };

  testADeploymentWhoseDiagnosticsCarryOnlyWarnings =
    let
      result = deployment unmentioned;
      reading = reader.read { inherit (result) plan diagnostics; };
    in
    {
      expr = {
        severities = map (r: r.severity) reading.diagnostics;
        ids = map (r: r.id) reading.diagnostics;
        applicable = result.applicable;
        refused = reading.refused;
        refusal = reading.refusal;
        everyEntryRead = attrNames reading.entries;
      };
      expected = {
        severities = [ "warning" ];
        ids = [ "closure-root-unmentioned" ];
        applicable = true;
        refused = false;
        refusal = null;
        everyEntryRead = [ oneKey ];
      };
    };

  testTheManifestNamesEveryEntryThePlanPlaced =
    let
      reading = workedRead;
      entry = reading.manifest.entries."vault-repo:server@vault";
      timers = readOf { } (deployment scheduled);
      bare = reader.read { plan = addressless; };
      row = builtins.head (rowsById "operator-entry-machine-no-address" bare);
    in
    {
      expr = {
        keys = attrNames reading.manifest.entries;
        entry = entry;
        units = reading.manifest.entries."nightly:client@alpha".units;
        withATimer = timers.manifest.entries.${oneKey}.units;
        unplacedContributeNothing = filter (key: builtins.match ".*:vars/.*" key != null) (
          attrNames reading.manifest.entries
        );
        noAddress = {
          ids = idsOf bare;
          count = length (rowsById "operator-entry-machine-no-address" bare);
          namesTheEntry = hasInfix "`svc:only@bare`" row.message;
          namesTheMachine = hasInfix "`bare`" row.message;
          address = bare.manifest.entries."svc:only@bare".address;
          refused = bare.refused;
        };
      };
      expected = {
        keys = [
          "nightly:client@alpha"
          "nightly:client@beta"
          "nightly:client@gamma"
          "vault-repo:server@vault"
        ];
        entry = {
          path = "entries/vault-repo-server-vault";
          realiser = "flakelet";
          profile = null;
          machine = "vault";
          address = "vault.example";
          units = [ "vault-repo-server-borgRepo.service" ];
          key = worked.plan."vault-repo:server@vault".key;
        };
        units = [ "nightly-client-borgPush.service" ];
        withATimer = [
          "svc-only-only.service"
          "svc-only-only.timer"
        ];
        unplacedContributeNothing = [ ];
        noAddress = {
          ids = [ "operator-entry-machine-no-address" ];
          count = 1;
          namesTheEntry = true;
          namesTheMachine = true;
          address = null;
          refused = true;
        };
      };
    };

  testTheManifestNamesEveryValueAMachineReceives =
    let
      reading = workedRead;
      empty = reader.read { plan = unreceived; };
    in
    {
      expr = {
        keys = attrNames reading.manifest.values;
        alpha = reading.manifest.values."nightly:vars/hostKey@alpha";
        gammaDelivery = reading.manifest.values."nightly:vars/hostKey@gamma".delivery;
        emptySet = empty.manifest.values."holder:vars/app";
        carriesNoBytes = {
          bytes = hasInfix "bytes" (toJSON reading.manifest);
          content = hasInfix "content" (toJSON reading.manifest);
        };
        rows = empty.rows;
      };
      expected = {
        keys = [
          "nightly:vars/hostKey@alpha"
          "nightly:vars/hostKey@beta"
          "nightly:vars/hostKey@gamma"
        ];
        alpha = {
          delivery = [ "alpha" ];
          files = {
            "ssh_host_ed25519_key" = {
              path = "/run/vars/nightly/hostKey/ssh_host_ed25519_key";
              secrecy = "secret";
            };
            "ssh_host_ed25519_key.pub" = {
              path = "/run/vars/nightly/hostKey/ssh_host_ed25519_key.pub";
              secrecy = "public";
            };
          };
        };
        gammaDelivery = [ "gamma" ];
        emptySet = {
          delivery = [ ];
          files."ca.pub" = {
            path = "/run/vars/holder/app/ca.pub";
            secrecy = "public";
          };
        };
        carriesNoBytes = {
          bytes = false;
          content = false;
        };
        rows = [ ];
      };
    };

  testTheManifestNamesTheProgramAValueDeclares =
    let
      generated = unreceived // {
        "holder:vars/minted" = {
          delivery = [ "bare" ];
          deliveryDerivedFrom = [ "holder:app@bare owns it" ];
          program = "/nix/store/9dm4x2vqk7z1n5bpr3jlfg8ys6cwh0az-mint.drv";
          files."token" = {
            path = "/run/vars/holder/minted/token";
            secrecy = "secret";
          };
        };
      };
      reading = reader.read { plan = generated; };
    in
    {
      expr = {
        minted = reading.manifest.values."holder:vars/minted";
        unprogrammed = reading.manifest.values."holder:vars/app" ? program;
      };
      expected = {
        minted = {
          delivery = [ "bare" ];
          program = "/nix/store/9dm4x2vqk7z1n5bpr3jlfg8ys6cwh0az-mint.drv";
          files."token" = {
            path = "/run/vars/holder/minted/token";
            secrecy = "secret";
          };
        };
        unprogrammed = false;
      };
    };

  testTheSameDeploymentIsReadTwice =
    let
      realise = {
        default.realiser = "flakelet";
        "vault-repo:server" = {
          realiser = "image";
          profile = "strict";
        };
      };
      first = reader.read {
        inherit (worked) plan;
        inherit realise;
      };
      second = reader.read {
        inherit (worked) plan;
        inherit realise;
      };
    in
    {
      expr = {
        manifests = first.manifest == second.manifest;
        rendered = toJSON first.manifest == toJSON second.manifest;
        artifacts =
          map (key: first.entries.${key}.artifact) (attrNames first.entries)
          == map (key: second.entries.${key}.artifact) (attrNames second.entries);
        stated = first.manifest.entries."vault-repo:server@vault".realiser;
      };
      expected = {
        manifests = true;
        rendered = true;
        artifacts = true;
        stated = "image";
      };
    };

  testAnInstanceIsNamedMachine =
    let
      result = planOf {
        instances.machine = {
          module = soleRoot { module = _: { impl = simple; }; };
          placement.every.only.machines = [ "one" ];
        };
      };
      reading = readOf { } result;
      entry = reading.entries."machine:only@one";
    in
    {
      expr = {
        planKeys = sorted (attrNames result.plan);
        entries = attrNames reading.entries;
        machine = entry.machine;
        artifact = entry.artifact;
        rows = idsOf reading;
      };
      expected = {
        planKeys = [
          "machine:one"
          "machine:only@one"
        ];
        entries = [ "machine:only@one" ];
        machine = "one";
        artifact = "entries/machine-only-one";
        rows = [ ];
      };
    };

  testAMemberIsNamedInsideTheValueNamespace =
    let
      result = planOf {
        instances.svc = {
          module = root { members."vars/x".module = _: { impl = simple; }; };
          placement.every."vars/x".machines = [ "one" ];
        };
      };
      reading = readOf { } result;
    in
    {
      expr = {
        entries = attrNames reading.entries;
        values = attrNames reading.values;
        service = reading.entries."svc:vars/x@one".service;
        rows = idsOf reading;
        read = (builtins.tryEval (builtins.deepSeq reading.manifest reading.manifest)).success;
      };
      expected = {
        entries = [ "svc:vars/x@one" ];
        values = [ ];
        service = "vars/x";
        rows = [ ];
        read = true;
      };
    };

  testAKeyMatchesNoShapeThePlanCarries =
    let
      reading = reader.read {
        plan = {
          "machine:one" = {
            address = "one.example:22";
            tags = [ ];
          };
          "odd:record@one" = {
            key = "sha256-0000000000000000";
          };
        };
      };
      row = builtins.head (rowsById "operator-plan-record-unclassified" reading);
    in
    {
      expr = {
        rows = idsOf reading;
        refused = reading.refused;
        entries = attrNames reading.entries;
        namesTheKey = hasInfix "`odd:record@one`" row.message;
        namesTheShapes =
          hasInfix "`delivery`" row.message
          && hasInfix "`placement`" row.message
          && hasInfix "address" row.message;
      };
      expected = {
        rows = [ "operator-plan-record-unclassified" ];
        refused = true;
        entries = [ ];
        namesTheKey = true;
        namesTheShapes = true;
      };
    };

  testAPlacedEntryDeclaresNoUnit =
    let
      result = planOf {
        instances.svc = {
          module = soleRoot {
            module = _: {
              provides.thing.interface = pub;
              impl = _: {
                provides.thing.exports.publicKey = "ssh-ed25519 AAAA";
              };
            };
            provides = [ "thing" ];
          };
          placement.every.only.machines = [ "one" ];
        };
      };
      silent = readOf { } result;
      asked = readOf {
        ${oneKey} = {
          realiser = "image";
          profile = "strict";
        };
      } result;
      row = builtins.head (rowsById "operator-entry-realises-nothing" asked);
    in
    {
      expr = {
        recorded = attrNames silent.manifest.entries;
        machine = silent.manifest.entries.${oneKey}.machine;
        artifact = silent.manifest.entries.${oneKey}.path;
        rows = idsOf silent;
        refused = silent.refused;
        askedRows = idsOf asked;
        askedRefused = asked.refused;
        namesTheEntry = hasInfix "`${oneKey}`" row.message;
      };
      expected = {
        recorded = [ oneKey ];
        machine = "one";
        artifact = null;
        rows = [ ];
        refused = false;
        askedRows = [ "operator-entry-realises-nothing" ];
        askedRefused = true;
        namesTheEntry = true;
      };
    };
}
